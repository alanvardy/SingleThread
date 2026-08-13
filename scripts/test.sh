#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="platform=iOS Simulator,name=iPhone 17"
SCHEME="SingleThread"

cd "$(dirname "$0")/.."

echo "==> Formatting…"
swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
swiftlint --fix --config .swiftlint.yml

echo ""
echo "==> SwiftFormat check…"
swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/

echo ""
echo "==> SwiftLint…"
swiftlint lint --strict --config .swiftlint.yml

echo ""
echo "==> Building…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -configuration Debug build

echo ""
echo "==> Unit tests…"
xcodebuild test -scheme "$SCHEME" \
  -destination "$SIM" \
  -only-testing:SingleThreadTests

echo ""
echo "✅ All CI checks passed."
