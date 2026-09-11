#!/bin/bash
# Run one test (or suite) with a pinned destination, and fail when the run
# executed zero cases.
#
# A zero-match `-only-testing:` still prints "** TEST SUCCEEDED **" and exits 0,
# so a red-first check can silently pass without ever running the test. This
# wrapper counts the cases in the result bundle and exits non-zero when none
# ran, and it bounds the run so a hung suite can't eat the session.
#
# Usage: scripts/test-one.sh <Target/Suite/case> [timeout-seconds]
set -euo pipefail

ONLY="${1:?usage: test-one.sh <Target/Suite/case> [timeout-seconds]}"
LIMIT="${2:-600}"

cd "$(dirname "$0")/.."

# Destination precedence: explicit SIM= > this worktree's .simulator_id > default.
if [ -n "${SIM:-}" ]; then
  DEST="$SIM"
elif [ -f .simulator_id ]; then
  DEST="platform=iOS Simulator,id=$(cat .simulator_id)"
else
  DEST="platform=iOS Simulator,name=iPhone 17"
  echo "warning: no .simulator_id in this checkout — using the shared default device" >&2
fi

WORK="$(mktemp -d)"
BUNDLE="$WORK/result.xcresult"
LOG="$WORK/xcodebuild.log"
trap 'rm -rf "$WORK"' EXIT

xcodebuild test \
  -scheme SingleThread \
  -destination "$DEST" \
  -derivedDataPath DerivedData \
  -resultBundlePath "$BUNDLE" \
  -only-testing:"$ONLY" >"$LOG" 2>&1 &
XCB=$!

# Bound the run: an unbounded foreground suite has hung for 600 s twice.
( sleep "$LIMIT"; kill -0 "$XCB" 2>/dev/null && kill "$XCB" ) 2>/dev/null &
WATCH=$!

set +e
wait "$XCB"
STATUS=$?
set -e
kill "$WATCH" 2>/dev/null || true

if [ "$STATUS" -ne 0 ]; then
  echo "xcodebuild exited $STATUS after -only-testing:$ONLY" >&2
  tail -25 "$LOG" >&2
  exit "$STATUS"
fi

SUMMARY="$(xcrun xcresulttool get test-results summary --path "$BUNDLE" --compact 2>/dev/null || true)"
TOTAL="$(printf '%s' "$SUMMARY" | python3 -c \
  'import json,sys;
data=sys.stdin.read()
print(json.loads(data)["totalTestCount"] if data.strip() else "unknown")' 2>/dev/null || echo unknown)"

if [ "$TOTAL" = "unknown" ]; then
  echo "FAIL: could not read the result bundle — the run is unverified, not passing." >&2
  exit 2
fi
if [ "$TOTAL" -eq 0 ]; then
  echo "FAIL: -only-testing:$ONLY matched no tests (0 cases ran)." >&2
  echo "A zero-match run exits 0 and prints TEST SUCCEEDED — it proves nothing." >&2
  exit 1
fi

echo "ok: $TOTAL case(s) ran for $ONLY"
