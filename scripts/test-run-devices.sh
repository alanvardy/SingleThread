#!/usr/bin/env bash
# Offline checks for scripts/run-devices.sh discovery + summary behaviour.
#
# Covers what a hardware-free run can: script syntax, shellcheck, and the two
# inline python discovery filters replayed against a saved
# `xcrun devicectl list devices -j` inventory
# (scripts/fixtures/devicectl-devices.json). The install/launch legs need a real
# watch and are verified by a hardware run of ./scripts/run-devices.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPT=scripts/run-devices.sh
FIXTURE=scripts/fixtures/devicectl-devices.json

if [[ ! -f "$FIXTURE" ]]; then
    echo "❌ Missing fixture $FIXTURE" >&2
    exit 1
fi

fail=0
check() {
    local label="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        echo "✅ $label"
    else
        echo "❌ $label" >&2
        printf '   want: %s\n   got:  %s\n' "$want" "$got" >&2
        fail=1
    fi
}

echo "==> bash -n"
bash -n "$SCRIPT"
echo "✅ syntax"

if command -v shellcheck >/dev/null 2>&1; then
    echo "==> shellcheck"
    # SC1111 is excluded: the pre-existing iOS message in run-devices.sh contains
    # unicode quotes, and rewriting that message is not part of this change.
    shellcheck -S warning --exclude=SC1111 "$SCRIPT"
    echo "✅ shellcheck"
else
    echo "⚠️  shellcheck not installed — skipped"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The two discovery filters are inline python heredocs. Extract them in file
# order (1 = iOS, 2 = watch) so the fixture assertions below exercise the exact
# code the script runs — no copy that can drift.
extract_filter() {
    awk -v want="$1" '/<<.PY./{n++; inblock=1; next} /^PY$/{inblock=0} inblock && n==want{print}' "$SCRIPT"
}
extract_filter 1 > "$work/ios.py"
extract_filter 2 > "$work/watch.py"
if [[ ! -s "$work/ios.py" || ! -s "$work/watch.py" ]]; then
    echo "❌ could not extract both discovery filters from $SCRIPT (did a heredoc move?)" >&2
    exit 1
fi

python3 "$work/ios.py" "$FIXTURE" "$work/ios-unreachable.log" > "$work/ios-out" 2> "$work/ios-stderr"
python3 "$work/watch.py" "$FIXTURE" "$work/watch-unreachable.log" > "$work/watch-out" 2> "$work/watch-stderr"

check "iOS filter emits the reachable physical iPhone" \
    "CCCCCCCC-0000-0000-0000-000000000007|Fixture iPhone" "$(cat "$work/ios-out")"
check "iOS filter logs no unreachable devices" \
    "0" "$(wc -l < "$work/ios-unreachable.log" | tr -d ' ')"
check "iOS filter reports the Developer-Mode-disabled iPad" \
    "1" "$(grep -c 'Developer Mode disabled' "$work/ios-stderr" || true)"

check "watch filter emits only the reachable physical watch" \
    "AAAAAAAA-0000-0000-0000-000000000002|Fixture Watch Reachable" "$(cat "$work/watch-out")"
check "watch filter logs the tunnel-down watch as unreachable" \
    "Fixture Watch Ultra" "$(cat "$work/watch-unreachable.log")"
check "watch filter reports the unpaired watch" \
    "1" "$(grep -c 'not paired with this Mac' "$work/watch-stderr" || true)"
check "watch filter reports the developer-mode-disabled watch" \
    "1" "$(grep -c 'Developer Mode disabled' "$work/watch-stderr" || true)"

echo ""
if [[ "$fail" -eq 0 ]]; then
    echo "✅ run-devices.sh offline checks passed."
else
    echo "❌ run-devices.sh offline checks failed." >&2
    exit 1
fi
