#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/check-warnings.sh"

# ── Configuration ──────────────────────────────────────────────────────────────
# Destination is resolved after cd: an explicit SIM wins, else this worktree's
# dedicated simulator from .simulator_id, else the shared default device.
SIM="${SIM:-}"
WATCH_SIM="generic/platform=watchOS Simulator"
# Concrete watchOS Simulator for watch UI tests (xcodebuild requires a concrete
# device to run XCTests). The default is name-based and resolved to the matching
# device's UDID before the watch stage (see the full pipeline), which keeps it
# unambiguous when multiple watchOS runtimes are installed; override with
# WATCH_TEST_SIM='platform=watchOS Simulator,id=…' to pin a specific device.
WATCH_TEST_SIM="${WATCH_TEST_SIM:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)}"
MAC_SIM="platform=macOS"
SCHEME="SingleThread"
WATCH_SCHEME="SingleThreadWatch"
DERIVED_DATA="DerivedData"


# Pin a name-only simulator destination to its concrete UDID: with multiple
# runtimes installed a bare `name=…` destination is ambiguous (iOS hangs, the
# watch normalizes to OS:latest and can match nothing). Falls back to leaving
# the caller's destination unchanged when no UDID resolves.
resolve_sim_udid() {
    local name="$1"
    # Match the device *name* at the start of a listing line. An unanchored
    # substring match also matches a device that merely contains the name —
    # e.g. `name=iPhone 17` selecting the leftover "Gate iPhone 17" sim.
    xcrun simctl list devices available \
        | awk -v n="$name" '{ s = $0; sub(/^[ \t]+/, "", s); if (index(s, n " (") == 1) print }' \
        | head -1 \
        | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
}
# Pre-boot the simulator so the first test run doesn't pay a cold boot; matches
# CI's pre-boot pattern (ci.yml:48-52). Safe to call when the sim is already up.
preboot_sim() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b
}

cd "$(dirname "$0")/.."

LOG_DIR="$DERIVED_DATA/logs"
rm -rf "$LOG_DIR"

# Prefer this worktree's dedicated simulator when SIM was not set explicitly.
# This is what keeps parallel agents off each other's simulator (see the
# worktree_sim fish function that writes .simulator_id).
if [[ -z "$SIM" ]]; then
    WORKTREE_SIM_UDID=""
    [[ -f .simulator_id ]] && WORKTREE_SIM_UDID="$(tr -d '[:space:]' < .simulator_id)"
    if [[ -n "$WORKTREE_SIM_UDID" ]] \
        && xcrun simctl list devices 2>/dev/null | grep -qF "($WORKTREE_SIM_UDID)"; then
        SIM="platform=iOS Simulator,id=$WORKTREE_SIM_UDID"
        echo "==> Using this worktree's simulator ${WORKTREE_SIM_UDID}"
    else
        [[ -n "$WORKTREE_SIM_UDID" ]] \
            && echo "⚠️  .simulator_id ($WORKTREE_SIM_UDID) is not a known simulator — falling back" >&2
        SIM="platform=iOS Simulator,name=iPhone 17"
    fi
fi

# Resolve the destination to a concrete ID once, then pre-boot it for all modes.
if [[ "$SIM" != *",id="* ]]; then
    SIM_NAME="${SIM##*name=}"; SIM_NAME="${SIM_NAME%%,*}"
    SIM_UDID="$(resolve_sim_udid "$SIM_NAME")"
    [[ -n "$SIM_UDID" ]] && SIM="platform=iOS Simulator,id=$SIM_UDID"
fi
if [[ "$SIM" == *",id="* ]]; then
    preboot_sim "${SIM##*id=}"
fi

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

# Reclaim age-expired build/test caches before this worktree starts building —
# the moment reclamation is cheapest, since nothing here is mid-build yet. The
# policy is shared across repositories (XCTest test clones, stale .xcresult
# bundles, idle cargo artifact dirs) and is age-gated so it can never disturb a
# concurrent gate's in-flight artifacts. It is a no-op when the helper is not
# installed — CI and any other machine — so a clean checkout behaves identically.
command -v disk-clean >/dev/null 2>&1 && disk-clean || true

# ── Deployment-target consistency guard ──────────────────────────────────────
# Enforces the settled floor set (VAR-1015): iOS drops from 18.7 to 17.0 — the
# Observation / EventKit `fullAccess` floor — and watchOS from 26.5 to 11.0.
# watchOS 11 and 26 support the same Watches (Series 6+), so 11.0 loses no
# hardware while covering watches that have not taken the 26.5 point update.
# macOS stays 26.5 (out of scope for VAR-1014, and unverifiable here: CI is
# macos-26 only). The app target is a native macOS build — SUPPORTED_PLATFORMS
# includes macosx, macOS-only entitlements, no Catalyst — so the Mac App Store
# listing derives from MACOSX_DEPLOYMENT_TARGET, NOT from
# IPHONEOS_DEPLOYMENT_TARGET. That independence is why macOS and watchOS are
# tracked as separate constants with separate literal counts.
#   IPHONEOS_DEPLOYMENT_TARGET (all 8: app, unit + UI tests, widget) = 17.0
#   MACOSX_DEPLOYMENT_TARGET   (all 6: app, unit + UI tests)         = 26.5
#   WATCHOS_DEPLOYMENT_TARGET  (all 6: watch app + watch UI tests + watch tests) = 11.0
#   Package.swift floor literals: .iOS = 17.0, .watchOS = 11.0, .macOS = 26.5
DEPLOYMENT_TARGET_IOS="${DEPLOYMENT_TARGET_IOS:-17.0}"
DEPLOYMENT_TARGET_WATCHOS="${DEPLOYMENT_TARGET_WATCHOS:-11.0}"
DEPLOYMENT_TARGET_MACOSX="${DEPLOYMENT_TARGET_MACOSX:-26.5}"
EXPECTED_IOS_LITERALS=8        # IPHONEOS_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_WATCHOS_LITERALS=6    # WATCHOS_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_MACOS_LITERALS=6      # MACOSX_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_PACKAGE_IOS=1         # .iOS("…") in Package.swift
EXPECTED_PACKAGE_WATCHOS=1     # .watchOS("…") in Package.swift
EXPECTED_PACKAGE_MACOS=1       # .macOS("…") in Package.swift

# Every xcodebuild invocation must go through run_xcodebuild so its output is
# scanned for compiler warnings. A bare call is a silent hole in the gate.
verify_xcodebuild_wrapped() {
    local script="$SCRIPT_DIR/test.sh"
    local bare
    bare="$(grep -cE '^[[:space:]]*xcodebuild' "$script" || true)"
    echo "==> Verifying every xcodebuild is wrapped"
    if [[ "$bare" -ne 0 ]]; then
        echo "    ✗ $bare bare xcodebuild invocation(s) in $script"
        echo "      Route them through run_xcodebuild <log> xcodebuild …"
        exit 1
    fi
    printf "    ✓ no bare xcodebuild invocations\n"
}

verify_deployment_target() {
    local pbxproj="SingleThread.xcodeproj/project.pbxproj"
    local package="SingleThreadCore/Package.swift"
    local drift=0
    local ios_target=0 watchos_target=0 macos_target=0
    local pkg_ios=0 pkg_watchos=0 pkg_macos=0
    local line target val expected

    echo "==> Verifying deployment targets / package floors"
    echo "    (iOS $DEPLOYMENT_TARGET_IOS, watchOS $DEPLOYMENT_TARGET_WATCHOS, macOS $DEPLOYMENT_TARGET_MACOSX)…"

    # 1) Unchanged pbxproj scan; each platform gets its OWN counter.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET = [0-9]+\.[0-9]+;'; then
            target=$(echo "$line" | grep -oE '(IPHONEOS|MACOSX|WATCHOS)')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            case "$target" in
                IPHONEOS) ios_target=$((ios_target + 1)); expected="$DEPLOYMENT_TARGET_IOS" ;;
                WATCHOS)  watchos_target=$((watchos_target + 1)); expected="$DEPLOYMENT_TARGET_WATCHOS" ;;
                *)        macos_target=$((macos_target + 1)); expected="$DEPLOYMENT_TARGET_MACOSX" ;;
            esac
            if [[ "$val" != "$expected" ]]; then
                echo "    ✗ $target = $val (expected $expected)"
                drift=1
            fi
        fi
    done < "$pbxproj"

    # 2) Unchanged Package.swift scan; per-platform counters.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '\.(iOS|watchOS|macOS)\("[0-9]+\.[0-9]+"\)'; then
            target=$(echo "$line" | grep -oE '\.iOS|\.watchOS|\.macOS')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            case "$target" in
                .iOS)      pkg_ios=$((pkg_ios + 1)); expected="$DEPLOYMENT_TARGET_IOS" ;;
                .watchOS)  pkg_watchos=$((pkg_watchos + 1)); expected="$DEPLOYMENT_TARGET_WATCHOS" ;;
                *)         pkg_macos=$((pkg_macos + 1)); expected="$DEPLOYMENT_TARGET_MACOSX" ;;
            esac
            if [[ "$val" != "$expected" ]]; then
                echo "    ✗ package $target = $val (expected $expected)"
                drift=1
            fi
        fi
    done < "$package"

    # 3) Per-platform count drift: a net move between platforms (or a
    #    literal added/removed) must fail even when the total is unchanged.
    #    (A strict 1:1 exchange that leaves each platform's count identical is
    #    not caught by any count-based scheme.)
    [[ "$ios_target" -eq "$EXPECTED_IOS_LITERALS" ]] || {
        echo "    ✗ IPHONEOS literal count $ios_target (expected $EXPECTED_IOS_LITERALS)"; drift=1; }
    [[ "$watchos_target" -eq "$EXPECTED_WATCHOS_LITERALS" ]] || {
        echo "    ✗ WATCHOS literal count $watchos_target (expected $EXPECTED_WATCHOS_LITERALS)"; drift=1; }
    [[ "$macos_target" -eq "$EXPECTED_MACOS_LITERALS" ]] || {
        echo "    ✗ MACOSX literal count $macos_target (expected $EXPECTED_MACOS_LITERALS)"; drift=1; }
    [[ "$pkg_ios" -eq "$EXPECTED_PACKAGE_IOS" ]] || {
        echo "    ✗ package .iOS count $pkg_ios (expected $EXPECTED_PACKAGE_IOS)"; drift=1; }
    [[ "$pkg_watchos" -eq "$EXPECTED_PACKAGE_WATCHOS" ]] || {
        echo "    ✗ package .watchOS count $pkg_watchos (expected $EXPECTED_PACKAGE_WATCHOS)"; drift=1; }
    [[ "$pkg_macos" -eq "$EXPECTED_PACKAGE_MACOS" ]] || {
        echo "    ✗ package .macOS count $pkg_macos (expected $EXPECTED_PACKAGE_MACOS)"; drift=1; }

    if [[ "$drift" -eq 1 ]]; then
        echo ""
        echo "❌ Deployment-target drift: not every literal matches the settled floor set"
        echo "   (iOS $DEPLOYMENT_TARGET_IOS / watchOS $DEPLOYMENT_TARGET_WATCHOS / macOS $DEPLOYMENT_TARGET_MACOSX)."
        echo "   Fix SingleThread.xcodeproj/project.pbxproj and SingleThreadCore/Package.swift."
        exit 1
    fi
    printf "    ✓ All deployment-target + package-floor literals match\n"
    printf "      (iOS %s × %d, watchOS %s × %d, macOS %s × %d; package .iOS %d, .watchOS %d, .macOS %d)\n" \
        "$DEPLOYMENT_TARGET_IOS" "$ios_target" \
        "$DEPLOYMENT_TARGET_WATCHOS" "$watchos_target" \
        "$DEPLOYMENT_TARGET_MACOSX" "$macos_target" \
        "$pkg_ios" "$pkg_watchos" "$pkg_macos"
}

verify_deployment_target
verify_xcodebuild_wrapped

# ── Full pipeline ──────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 0 && "${UI_ONLY:-0}" -eq 0 ]]; then
    echo "==> Formatting…"
    swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/ SingleThreadWatchTests/
    swiftlint --fix

    echo ""
    echo "==> SwiftFormat check…"
    swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/ SingleThreadWatchTests/

    echo ""
    echo "==> SwiftLint…"
    swiftlint lint --strict

    echo ""
    echo "==> Warning-check self-test…"
    bash "$SCRIPT_DIR/tests/warning-check/run.sh"

    echo ""
    echo "==> Building…"
    run_xcodebuild "$LOG_DIR/ios-build.log" xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing

    # Resolve the watch test destination once, before the watch stage: with
    # multiple watchOS runtimes installed, xcodebuild normalizes a name-only
    # `platform=watchOS Simulator,name=…` destination to OS:latest — which can
    # land on a runtime that has no device of that name, so the destination
    # matches nothing and the stage dies with an opaque "Unable to find a
    # device matching the provided destination specifier" error. Pinning the
    # UDID (and pre-booting it, mirroring the iOS path above) makes the name
    # unambiguous. An explicit WATCH_TEST_SIM with `id=` passes through.
    if [[ "$WATCH_TEST_SIM" != *",id="* ]]; then
        watch_sim_name="${WATCH_TEST_SIM##*name=}"; watch_sim_name="${watch_sim_name%%,*}"
        watch_sim_udid="$(resolve_sim_udid "$watch_sim_name")"
        if [[ -z "$watch_sim_udid" ]]; then
            echo "❌ No watch simulator matches '$watch_sim_name'." >&2
            echo "   Available watch simulators:" >&2
            xcrun simctl list devices available | grep -Ei 'watch' || true
            echo "   Pick one and set WATCH_TEST_SIM='platform=watchOS Simulator,id=<udid>'." >&2
            exit 1
        fi
        WATCH_TEST_SIM="platform=watchOS Simulator,id=$watch_sim_udid"
    fi
    [[ "$WATCH_TEST_SIM" == *",id="* ]] && preboot_sim "${WATCH_TEST_SIM##*id=}"

    echo ""
    echo "==> Watch build…"
    run_xcodebuild "$LOG_DIR/watch-build.log" xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build

    echo ""
    echo "==> Periphery…"
    periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict

    echo ""
    echo "==> UI tests…"
    run_xcodebuild "$LOG_DIR/ios-ui-test.log" xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadUITests

    echo ""
    echo "==> Watch UI tests…"
    run_xcodebuild "$LOG_DIR/watch-build-for-testing.log" xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing \
      -only-testing:SingleThreadWatchUITests \
      -only-testing:SingleThreadWatchTests

    # Local-only fix: this machine's watchOS 26.5 simruntime is missing
    # lib_TestingInterop.dylib (/usr/lib/swift), so the watch UI test runner
    # crashes at launch with "Library not loaded: @rpath/lib_TestingInterop.dylib".
    # Bundle the Xcode-side lib into the runner's Frameworks so the gate runs.
    # CI's watch sim runtime includes it; harmless elsewhere (no-op if absent).
    _watch_runner="$DERIVED_DATA/Build/Products/Debug-watchsimulator/SingleThreadWatchUITests-Runner.app/Frameworks"
    if [[ -d "$_watch_runner" && -f "$DERIVED_DATA/Build/Products/Debug-watchsimulator/SingleThreadWatchUITests-Runner.app/Frameworks/Testing.framework/Testing" ]]; then
        _testing_interop="/Applications/Xcode.app/Contents/Developer/Platforms/WatchSimulator.platform/Developer/usr/lib/lib_TestingInterop.dylib"
        if [[ -f "$_testing_interop" && ! -f "$_watch_runner/lib_TestingInterop.dylib" ]]; then
            echo "    (local only) embedding lib_TestingInterop.dylib into watch UI test runner…"
            cp "$_testing_interop" "$_watch_runner/"
        fi
    fi

    run_xcodebuild "$LOG_DIR/watch-ui-test.log" xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadWatchUITests

    echo ""
    echo "==> Watch unit tests…"
    run_xcodebuild "$LOG_DIR/watch-unit-test.log" xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadWatchTests

    echo ""
    echo "==> macOS unit tests…"
    run_xcodebuild "$LOG_DIR/mac-unit-test.log" xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadTests

    echo ""
    echo "✅ All CI checks passed."
    exit 0
fi

# ── Unit-only ──────────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 1 ]]; then
    echo "==> Unit tests (macOS native)…"
    run_xcodebuild "$LOG_DIR/mac-unit-only.log" xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadTests

    echo ""
    echo "✅ Unit tests passed (macOS native)."
    exit 0
fi

# ── UI-only ────────────────────────────────────────────────────────────────────
echo "==> Building (UI tests)…"
run_xcodebuild "$LOG_DIR/ios-ui-build.log" xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  -only-testing:SingleThreadUITests

echo ""
echo "==> UI tests…"
run_xcodebuild "$LOG_DIR/ios-ui-test-only.log" xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadUITests

echo ""
echo "✅ UI tests passed."
