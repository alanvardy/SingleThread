#!/usr/bin/env bash
set -euo pipefail

# scripts/run-devices.sh — build SingleThread for iOS, install + launch it on
# every paired iPhone/iPad that has Developer Mode enabled (via devicectl),
# and (by default) also build + launch it on the host Mac.
#
#   ./scripts/run-devices.sh
#
# Overrides (same env-override pattern as scripts/test.sh):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   RUN_MAC=0   # skip the macOS build + launch step (default RUN_MAC=1)
#
# Devices are discovered dynamically each run, so a new iPhone/iPad is picked
# up without editing this script. A device that is unreachable (locked, asleep,
# unplugged mid-run) fails its own install/launch step and is reported — the
# remaining devices still get built and run. If no iOS devices are found and
# RUN_MAC=1, the script still does the macOS step; set RUN_MAC=0 to keep the
# old fail-fast behavior. The macOS app is built unsigned (CODE_SIGNING_ALLOWED=NO,
# matching `make mac-build`) because signing needs the Mac provisioning profile
# to carry the In-App Purchase entitlement — see make mac-run / the TestFlight
# runbook for the signed flow.

SCHEME="${SCHEME:-SingleThread}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.SingleThread}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
RUN_MAC="${RUN_MAC:-1}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
trap 'rm -f "$DEVICES_JSON"' EXIT

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app"
MAC_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/SingleThread.app"

cd "$(dirname "$0")/.."

# ── Discover devices ─────────────────────────────────────────────────────────
echo "==> Discovering paired iPhone/iPad devices…"
if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    echo "   Plug in a device, unlock it, and tap “Trust”, then retry." >&2
    exit 1
fi

# Emits "identifier|name" per qualifying device (platform iOS, iPhone or iPad,
# Developer Mode enabled). Skipped devices go to stderr so stdout stays parseable.
DEVICES=()
while IFS= read -r entry; do
    DEVICES+=("$entry")
done < <(python3 - "$DEVICES_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

for device in payload["result"]["devices"]:
    hardware = device.get("hardwareProperties", {})
    props = device.get("deviceProperties", {})
    if hardware.get("platform") != "iOS":
        continue
    if hardware.get("deviceType") not in ("iPhone", "iPad"):
        continue
    if props.get("developerModeStatus") != "enabled":
        print(f"  (skipping {props.get('name', 'unknown device')} — Developer Mode disabled)", file=sys.stderr)
        continue
    print(f"{device['identifier']}|{props.get('name', 'unknown device')}")
PY
)

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    if [[ "$RUN_MAC" -eq 1 ]]; then
        echo "  (no iPhone/iPad with Developer Mode enabled found — macOS run only)"
    else
        echo "❌ No iPhone/iPad with Developer Mode enabled found." >&2
        echo "   Plug in the device and enable Settings → Privacy & Security → Developer Mode, then retry." >&2
        exit 1
    fi
fi

failures=0

# ── Build once for all devices ────────────────────────────────────────────────
if [[ ${#DEVICES[@]} -gt 0 ]]; then
    echo ""
    echo "==> Building $SCHEME ($CONFIGURATION) for iOS devices…"
    xcodebuild -scheme "$SCHEME" \
      -destination 'generic/platform=iOS' \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA" \
      build

    if [[ ! -d "$APP_PATH" ]]; then
        echo "❌ Built app not found at $APP_PATH" >&2
        exit 1
    fi

    # ── Install + launch per device ────────────────────────────────────────
    for entry in "${DEVICES[@]}"; do
        device_id="${entry%%|*}"
        device_name="${entry#*|}"

        echo ""
        echo "==> Installing on ${device_name}…"
        if ! xcrun devicectl device install app --device "$device_id" "$APP_PATH"; then
            echo "❌ Install failed on $device_name (is it unlocked?)." >&2
            failures=$((failures + 1))
            continue
        fi

        echo "==> Launching on ${device_name}…"
        if ! xcrun devicectl device process launch --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"; then
            echo "❌ Launch failed on $device_name." >&2
            failures=$((failures + 1))
        fi
    done
fi

# ── macOS (host) step ──────────────────────────────────────────────────────────
if [[ "$RUN_MAC" -eq 1 ]]; then
    echo ""
    echo "==> Building $SCHEME ($CONFIGURATION) for macOS…"
    if ! xcodebuild -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      build; then
        echo "❌ macOS build failed." >&2
        failures=$((failures + 1))
    elif [[ ! -d "$MAC_APP_PATH" ]]; then
        echo "❌ Built macOS app not found at $MAC_APP_PATH" >&2
        failures=$((failures + 1))
    else
        echo "==> Launching $BUNDLE_ID on macOS…"
        if ! open "$MAC_APP_PATH"; then
            echo "❌ Failed to open $MAC_APP_PATH" >&2
            failures=$((failures + 1))
        fi
    fi
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    summary="Installed and launched on ${#DEVICES[@]} device(s)"
    [[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
    echo "✅ $summary."
else
    echo "❌ $failures step(s) failed — see errors above." >&2
    exit 1
fi