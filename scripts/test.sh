#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="${SIM:-platform=iOS Simulator,name=iPhone 17}"
WATCH_SIM="generic/platform=watchOS Simulator"
# Concrete watchOS Simulator for watch UI tests (xcodebuild requires a concrete
# device to run XCTests). Name-only works when one standalone watch simulator
# exists; override with WATCH_TEST_SIM='platform=watchOS Simulator,id=…' on
# machines where the name is ambiguous.
WATCH_TEST_SIM="${WATCH_TEST_SIM:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)}"
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

# ── Deployment-target consistency guard ──────────────────────────────────────
# Enforces the settled floor set for this change (18.7 is NOT a valid watchOS or
# macOS deployment target under Xcode 26 — there is no 18.x version line for
# those platforms — so those floors stay 26.5 while all iOS IPHONEOS floors drop):
#   IPHONEOS_DEPLOYMENT_TARGET (all 8: app, unit + UI tests, widget) = 18.7
#   MACOSX_DEPLOYMENT_TARGET   (all 6: app, unit + UI tests)         = 26.5
#   WATCHOS_DEPLOYMENT_TARGET  (all 2: watch target)                 = 26.5
#   Package.swift floor literals: .iOS = 18.7, .watchOS = 26.5, .macOS = 26.5
DEPLOYMENT_TARGET_IOS="${DEPLOYMENT_TARGET_IOS:-18.7}"
DEPLOYMENT_TARGET_OTHER="${DEPLOYMENT_TARGET_OTHER:-26.5}"
EXPECTED_TARGET_LITERALS=16    # all *_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_PACKAGE_LITERALS=3     # .iOS/.watchOS/.macOS in Package.swift

verify_deployment_target() {
    local pbxproj="SingleThread.xcodeproj/project.pbxproj"
    local package="SingleThreadCore/Package.swift"
    local drift=0
    local ios_target=0 other_target=0 pkg_ios=0 pkg_other=0
    local line target val

    echo "==> Verifying deployment targets / package floors"
    echo "    (iOS $DEPLOYMENT_TARGET_IOS, macOS/watchOS $DEPLOYMENT_TARGET_OTHER)…"

    # 1) All *_DEPLOYMENT_TARGET literals in project.pbxproj must match the
    #    per-platform floor constant (IPHONEOS 18.7; MACOSX/WATCHOS 26.5).
    #    Iterate real file lines (not `grep -o` output, which bash splits by
    #    whitespace) so each literal is inspected exactly once.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET = [0-9]+\.[0-9]+;'; then
            target=$(echo "$line" | grep -oE '(IPHONEOS|MACOSX|WATCHOS)')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            if [[ "$target" == "IPHONEOS" ]]; then
                ios_target=$((ios_target + 1))
                if [[ "$val" != "$DEPLOYMENT_TARGET_IOS" ]]; then
                    echo "    ✗ $target = $val (expected $DEPLOYMENT_TARGET_IOS)"
                    drift=1
                fi
            else
                other_target=$((other_target + 1))
                if [[ "$val" != "$DEPLOYMENT_TARGET_OTHER" ]]; then
                    echo "    ✗ $target = $val (expected $DEPLOYMENT_TARGET_OTHER)"
                    drift=1
                fi
            fi
        fi
    done < "$pbxproj"

    # 2) Package platform floor literals must match the same per-platform set.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '\.(iOS|watchOS|macOS)\("[0-9]+\.[0-9]+"\)'; then
            target=$(echo "$line" | grep -oE '\.iOS|\.watchOS|\.macOS')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            if [[ "$target" == ".iOS" ]]; then
                pkg_ios=$((pkg_ios + 1))
                if [[ "$val" != "$DEPLOYMENT_TARGET_IOS" ]]; then
                    echo "    ✗ package $target = $val (iOS expected $DEPLOYMENT_TARGET_IOS)"
                    drift=1
                fi
            else
                pkg_other=$((pkg_other + 1))
                if [[ "$val" != "$DEPLOYMENT_TARGET_OTHER" ]]; then
                    echo "    ✗ package $target = $val (expected $DEPLOYMENT_TARGET_OTHER)"
                    drift=1
                fi
            fi
        fi
    done < "$package"

    if [[ "$drift" -eq 1 ]]; then
        echo ""
        echo "❌ Deployment-target drift: not every literal matches the settled floor set"
        echo "   (iOS $DEPLOYMENT_TARGET_IOS / macOS+watchOS $DEPLOYMENT_TARGET_OTHER)."
        echo "   Fix SingleThread.xcodeproj/project.pbxproj and SingleThreadCore/Package.swift."
        exit 1
    fi
    printf "    ✓ All deployment-target + package-floor literals match\n"
    printf "      (iOS %s × %d, macOS/watchOS %s × %d, package .iOS %d, package other %d)\n" \
        "$DEPLOYMENT_TARGET_IOS" "$ios_target" \
        "$DEPLOYMENT_TARGET_OTHER" "$other_target" \
        "$pkg_ios" "$pkg_other"
}

verify_deployment_target

# ── Full pipeline ──────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 0 && "${UI_ONLY:-0}" -eq 0 ]]; then
    echo "==> Formatting…"
    swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/
    swiftlint --fix

    echo ""
    echo "==> SwiftFormat check…"
    swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/

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
    echo "==> Watch UI tests…"
    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing \
      -only-testing:SingleThreadWatchUITests

    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadWatchUITests

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
