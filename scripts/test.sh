#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="platform=iOS Simulator,name=iPhone 17"
SCHEME="SingleThread"
DERIVED_DATA="DerivedData"

cd "$(dirname "$0")/.."

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

# ── Full pipeline ──────────────────────────────────────────────────────────────
if [[ "${UNIT_ONLY:-0}" -eq 0 && "${UI_ONLY:-0}" -eq 0 ]]; then
    echo "==> Formatting…"
    swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
    swiftlint --fix

    echo ""
    echo "==> SwiftFormat check…"
    swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/

    echo ""
    echo "==> SwiftLint…"
    swiftlint lint --strict

    echo ""
    echo "==> Building…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing \
      SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

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
      -only-testing:SingleThreadTests \
      SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

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
  -only-testing:SingleThreadUITests \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

echo ""
echo "==> UI tests…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadUITests

echo ""
echo "✅ UI tests passed."