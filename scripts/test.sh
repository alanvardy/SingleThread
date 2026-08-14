#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="platform=iOS Simulator,name=iPhone 17"
SCHEME="SingleThread"
DERIVED_DATA="DerivedData"

cd "$(dirname "$0")/.."

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
echo "✅ All CI checks passed."
