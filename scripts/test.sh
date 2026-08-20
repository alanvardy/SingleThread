#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="${SIM:-platform=iOS Simulator,name=iPhone 17}"
WATCH_SIM="generic/platform=watchOS Simulator"
MAC_SIM="platform=macOS"
SCHEME="SingleThread"
WATCH_SCHEME="SingleThreadWatch"
DERIVED_DATA="DerivedData"
# Delete XCTest simulator runtimes older than this many hours. Keeps space in
# check without ever touching runtimes from an in-flight parallel test run.
# Override with RUNTIME_AGE_HOURS=... on the command line.
RUNTIME_AGE_HOURS="${RUNTIME_AGE_HOURS:-1}"
RUNTIMES_DIR="$HOME/Library/Developer/XCTestDevices"

cd "$(dirname "$0")/.."

# Clean up abandoned XCTests runtimes. Each UI test run leaves a fresh
# ~3 GB runtime in ~/Library/Developer/XCTestDevices that Xcode never prunes.
# This deletes only entries older than RUNTIME_AGE_HOURS, so it cannot
# interfere with parallel tests that are actively writing to a runtime.
cleanup_xctest_runtimes() {
    if [[ ! -d "$RUNTIMES_DIR" ]]; then
        echo "    (no $RUNTIMES_DIR; nothing to clean)"
        return
    fi

    local now cutoff_sec
    local removed=0
    now=$(date +%s)
    cutoff_sec=$((RUNTIME_AGE_HOURS * 3600))

    echo "==> Pruning XCTest runtimes older than ${RUNTIME_AGE_HOURS}h…"
    for entry in "$RUNTIMES_DIR"/*; do
        # Skip non-directories and symlinks.
        [[ -d "$entry" ]] || continue
        [[ -L "$entry" ]] && continue

        local mtime
        mtime=$(stat -f '%m' "$entry" 2>/dev/null) || continue
        if ((now - mtime > cutoff_sec)); then
            rm -rf "$entry"
            removed=$((removed + 1))
        fi
    done

    if [[ "$removed" -gt 0 ]]; then
        echo "==> Removed $removed stale runtime director(ies)."
    else
        echo "==> No stale runtimes to remove."
    fi
}

# ── Mode ───────────────────────────────────────────────────────────────────────
MODE="${1:-full}"
case "$MODE" in
    --unit-only) UNIT_ONLY=1 ;;
    --ui-only)   UI_ONLY=1 ;;
    full)        UNIT_ONLY=0; UI_ONLY=0 ;;
    *)
        echo "Usage: $0 [--unit-only|--ui-only]"
        echo "  (no argument)  Run the full pipeline (format, lint, build, periphery, unit + UI tests)"
        echo "  --unit-only    Run only unit tests (with own build)"
        echo "  --ui-only      Run only UI tests (with own build)"
        exit 1
        ;;
esac

# Reclaim space before any test/build runs. Safe under parallel execution:
# only entries older than RUNTIME_AGE_HOURS are removed, and APFS keeps open
# handles alive anyway, so an in-flight UI test is never disturbed.
cleanup_xctest_runtimes

# ── Full pipeline ──────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 0 && "${UI_ONLY:-0}" -eq 0 ]]; then
    echo "==> Formatting…"
    swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/
    swiftlint --fix

    echo ""
    echo "==> SwiftFormat check…"
    swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/

    echo ""
    echo "==> SwiftLint…"
    swiftlint lint --strict

    echo ""
    echo "==> Building…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing

    echo ""
    echo "==> Watch build…"
    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build

    echo ""
    echo "==> Periphery…"
    periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict

    echo ""
    echo "==> Unit tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadTests

    echo ""
    echo "==> UI tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadUITests

    echo ""
    echo "==> macOS build…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      build

    echo ""
    echo "==> macOS unit tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test \
      -only-testing:SingleThreadTests

    echo ""
    echo "✅ All CI checks passed."
    exit 0
fi

# ── Unit-only ──────────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 1 ]]; then
    echo "==> Building (unit tests)…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing \
      -only-testing:SingleThreadTests

    echo ""
    echo "==> Unit tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadTests

    echo ""
    echo "✅ Unit tests passed."
    exit 0
fi

# ── UI-only ────────────────────────────────────────────────────────────────────
echo "==> Building (UI tests)…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  -only-testing:SingleThreadUITests

echo ""
echo "==> UI tests…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadUITests

echo ""
echo "✅ UI tests passed."
