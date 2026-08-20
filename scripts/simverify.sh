#!/usr/bin/env bash
set -euo pipefail

# ── Configuration (mirrors scripts/test.sh) ─────────────────────────────────
SIM="${SIM:-platform=iOS Simulator,name=iPhone 17}"
WATCH_SIM="generic/platform=watchOS Simulator"
MAC_SIM="platform=macOS"
SCHEME="SingleThread"
DERIVED_DATA="DerivedData"

cd "$(dirname "$0")/.."

# Pre-boot the simulator (CI-identical gate; do not skip `bootstatus -b`).
DEVICE=$(echo "$SIM" | sed -E 's/.*name=([^\]]*).*/\1/')
SIM_UDID=$(xcrun simctl list devices available \
    | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
echo "==> Booting $DEVICE ($SIM_UDID)…"
xcrun simctl boot "$SIM_UDID" || true
xcrun simctl bootstatus "$SIM_UDID" -b

# Build + drive the appearance gates (XCTest foreground handoff).
echo "==> Building (simverify)…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  -only-testing:SingleThreadUITests

echo "==> Running (simverify)…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadUITests

# Supporting visual evidence (best-effort; the XCTest asserts are the gate).
mkdir -p build
xcrun simctl io "$SIM_UDID" screenshot "build/simverify-cold-launch.png" || true

echo "==> Simverify gate passed."