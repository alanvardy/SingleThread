#!/usr/bin/env bash
set -euo pipefail

# scripts/run-devices.sh — build SingleThread for iOS, install + launch it on
# every paired iPhone/iPad that has Developer Mode enabled (via devicectl),
# install + launch the watch app on every paired Apple Watch that is reachable,
# and (by default) also build + launch it on the host Mac.
#
#   ./scripts/run-devices.sh
#
# Overrides (same env-override pattern as scripts/test.sh):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   RUN_WATCH=0            # skip the watchOS build + install + launch step (default RUN_WATCH=1)
#   RUN_MAC=0              # skip the macOS build + launch step (default RUN_MAC=1)
#   WATCH_BUNDLE_ID=…      # defaults to ${BUNDLE_ID}.watchkitapp
#   DEVICES_JSON_IN=…      # dev seam: read a saved `xcrun devicectl list devices -j`
#                          # inventory instead of querying CoreDevice (offline filter checks)
#
# Devices are discovered dynamically each run, so a new iPhone/iPad/Apple Watch
# is picked up without editing this script. A device that is unreachable (locked, asleep,
# off this Wi-Fi, unplugged mid-run) is detected during discovery and reported
# — the remaining devices still get built and run; an unreachable device counts
# as a failed step so the run exits non-zero. If no iOS devices are found and
# RUN_MAC=1, the script still does the macOS step; set RUN_MAC=0 to keep the
# old fail-fast behavior. The macOS app is built unsigned (CODE_SIGNING_ALLOWED=NO,
# matching `make mac-build`) because signing needs the Mac provisioning profile
# to carry the In-App Purchase entitlement — see make mac-run / the TestFlight
# runbook for the signed flow.
#
# Apple Watch prerequisite: the watch must be on your wrist with its paired
# iPhone nearby and unlocked, so CoreDevice's network tunnel to the watch is up.
# A paired watch with the tunnel down is reported as unreachable with that hint
# rather than surfacing a raw devicectl 4016 assertion later.

SCHEME="${SCHEME:-SingleThread}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.SingleThread}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
RUN_WATCH="${RUN_WATCH:-1}"
RUN_MAC="${RUN_MAC:-1}"
WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${BUNDLE_ID}.watchkitapp}"
DEVICES_JSON_IN="${DEVICES_JSON_IN:-}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-unreachable-$$.log"
WATCH_UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-watch-unreachable-$$.log"
trap 'rm -f "$DEVICES_JSON" "$UNREACHABLE_LOG" "$WATCH_UNREACHABLE_LOG"' EXIT

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app"
WATCH_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos/SingleThreadWatch.app"
MAC_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/SingleThread.app"

cd "$(dirname "$0")/.."

# ── Discover devices ─────────────────────────────────────────────────────────
echo "==> Discovering paired iPhone/iPad devices…"
if [[ -n "$DEVICES_JSON_IN" ]]; then
    # Offline seam: a saved inventory is replayed so the discovery filters can be
    # checked without hardware. The temp copy keeps the EXIT trap's cleanup valid.
    echo "  (using the saved inventory in DEVICES_JSON_IN=$DEVICES_JSON_IN)"
    if ! cp "$DEVICES_JSON_IN" "$DEVICES_JSON" 2>/dev/null; then
        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN could not be read." >&2
        exit 1
    fi
elif ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    echo "   Plug in a device, unlock it, and tap “Trust”, then retry." >&2
    exit 1
fi

# Emits "identifier|name" per qualifying device (platform iOS, iPhone or iPad,
# Developer Mode enabled). Skipped devices go to stderr so stdout stays parseable;
# unreachable qualifying devices are logged to "$UNREACHABLE_LOG" for the failure
# tally, so a phone that is locked / off-network / has Remote Device Services down
# is reported with the real reason instead of a raw devicectl 4016 install error.
DEVICES=()
while IFS= read -r entry; do
    DEVICES+=("$entry")
done < <(python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

with open(sys.argv[2], "a", encoding="utf-8") as unreachable_log:
    for device in payload["result"]["devices"]:
        hardware = device.get("hardwareProperties", {})
        props = device.get("deviceProperties", {})
        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("deviceType") not in ("iPhone", "iPad"):
            continue
        name = props.get("name", "unknown device")
        if props.get("developerModeStatus") != "enabled":
            print(f"  (skipping {name} — Developer Mode disabled)", file=sys.stderr)
            continue
        # Physical devices install over a connection (localNetwork, wired, or
        # sameMachine for local simulators). When CoreDevice cannot reach the
        # device — locked, asleep, on another network, or Remote Device
        # Services down — devicectl fails every later call with a raw
        # usage-assertion error (4016). Detect it here so the message names
        # the actual problem before any build/install work is wasted.
        conn = device.get("connectionProperties", {}) or {}
        conn_state = (((device.get("properties") or {}).get("connection")) or {}).get("state")
        if conn.get("transportType") is None or conn_state == "unavailable" or conn.get("tunnelState") == "unavailable":
            print(f"  (skipping {name} — unreachable (locked, asleep, or on another network?)\n    unlock it, confirm it is on the same Wi-Fi as this Mac, then retry)", file=sys.stderr)
            print(name, file=unreachable_log)
            continue
        print(f"{device['identifier']}|{name}")
PY
)

UNREACHABLE_COUNT=0
if [[ -s "$UNREACHABLE_LOG" ]]; then
    UNREACHABLE_COUNT=$(wc -l < "$UNREACHABLE_LOG" | tr -d ' ')
fi

# Emits "identifier|name" per *reachable* physical Apple Watch. The four paired
# watch simulators appear in the same inventory, so `reality == "physical"` is
# part of the filter; watch sims are excluded silently. A watch that is paired
# but has its CoreDevice tunnel down cannot be installed to, and devicectl would
# fail every later call with a raw 4016 — it goes to "$WATCH_UNREACHABLE_LOG"
# and is named here with the wrist/paired-iPhone cause instead. A watch that is
# not paired with this Mac is skipped quietly: there is nothing to install to
# and it is not a failure (zero watches found is a notice, not an error).
#
# RUN_WATCH=0 skips all of this — no watch output, no watch failures — so the
# run is byte-for-byte the pre-watch-script behavior.
WATCH_DEVICES=()
WATCH_UNREACHABLE_COUNT=0
if [[ "$RUN_WATCH" -eq 1 ]]; then
    echo "==> Discovering paired Apple Watches…"
    while IFS= read -r entry; do
        WATCH_DEVICES+=("$entry")
    done < <(python3 - "$DEVICES_JSON" "$WATCH_UNREACHABLE_LOG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

with open(sys.argv[2], "a", encoding="utf-8") as unreachable_log:
    for device in payload["result"]["devices"]:
        hardware = device.get("hardwareProperties", {})
        props = device.get("deviceProperties", {})
        if hardware.get("platform") != "watchOS":
            continue
        if hardware.get("deviceType") != "appleWatch":
            continue
        # reality is "physical" for a wrist-worn watch and "simulated" for the
        # paired watch simulators listed alongside it in the same inventory.
        if hardware.get("reality") != "physical":
            continue
        name = props.get("name", "unknown watch")
        if props.get("developerModeStatus") != "enabled":
            print(f"  (skipping {name} — Developer Mode disabled)", file=sys.stderr)
            continue
        conn = device.get("connectionProperties", {}) or {}
        conn_props = (device.get("properties") or {}).get("connection") or {}
        if conn.get("pairingState") != "paired":
            print(f"  (skipping {name} — not paired with this Mac; pair it in Xcode → Window → Devices and Simulators)", file=sys.stderr)
            continue
        # Only "connected" means CoreDevice has a live tunnel to the watch
        # (the state a real watch reports when it is off the wrist / its paired
        # iPhone is asleep is "disconnected", which the iOS predicate above does
        # not treat as unreachable — the watch needs its own check).
        if conn_props.get("state") != "connected":
            print(f"  (skipping {name} — unreachable (watch off the wrist, or its paired iPhone is asleep / on another network?)\n    put the watch on your wrist, unlock its paired iPhone, keep it near this Mac, then retry)", file=sys.stderr)
            print(name, file=unreachable_log)
            continue
        print(f"{device['identifier']}|{name}")
PY
    )

    if [[ -s "$WATCH_UNREACHABLE_LOG" ]]; then
        WATCH_UNREACHABLE_COUNT=$(wc -l < "$WATCH_UNREACHABLE_LOG" | tr -d ' ')
    fi
fi

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    if [[ "$UNREACHABLE_COUNT" -gt 0 && ${#WATCH_DEVICES[@]} -eq 0 ]]; then
        echo "❌ $UNREACHABLE_COUNT device(s) found but unreachable — see messages above (unlock the device and connect it to this Mac's Wi-Fi, then retry)." >&2
        exit 1
    fi
    if [[ "$RUN_MAC" -eq 1 ]]; then
        if [[ ${#WATCH_DEVICES[@]} -gt 0 || "$WATCH_UNREACHABLE_COUNT" -gt 0 ]]; then
            echo "  (no iPhone/iPad with Developer Mode enabled found — macOS + Apple Watch run only)"
        else
            echo "  (no iPhone/iPad with Developer Mode enabled found — macOS run only)"
        fi
    elif [[ ${#WATCH_DEVICES[@]} -gt 0 ]]; then
        echo "  (no iPhone/iPad with Developer Mode enabled found — Apple Watch run only)"
    else
        echo "❌ No iPhone/iPad with Developer Mode enabled found." >&2
        echo "   Plug in the device and enable Settings → Privacy & Security → Developer Mode, then retry." >&2
        exit 1
    fi
fi

failures=0
# Devices that are paired but unreachable count as failed steps, matching the
# old behavior where the guaranteed-failing install attempt was tried and failed.
failures=$((failures + UNREACHABLE_COUNT))
failures=$((failures + WATCH_UNREACHABLE_COUNT))

# The watch app is built whenever a physical watch was discovered — reachability
# is irrelevant to a build, and building here is the only way to exercise the
# device-signed watch product without depending on the tunnel being up.
WATCH_BUILD_NEEDED=0
if [[ "$RUN_WATCH" -eq 1 ]] && [[ ${#WATCH_DEVICES[@]} -gt 0 || "$WATCH_UNREACHABLE_COUNT" -gt 0 ]]; then
    WATCH_BUILD_NEEDED=1
fi

# Watch leg counters (reported by the Phase 3 summary).
WATCH_LAUNCHED=0
WATCH_FAILED=0
WATCH_LAUNCH_FORM="none"

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

# ── Apple Watch step ─────────────────────────────────────────────────────────
if [[ "$WATCH_BUILD_NEEDED" -eq 1 ]]; then
    echo ""
    echo "==> Building SingleThreadWatch ($CONFIGURATION) for a real Apple Watch…"
    if ! xcodebuild -scheme SingleThreadWatch \
      -destination 'generic/platform=watchOS' \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA" \
      -allowProvisioningUpdates \
      build; then
        echo "❌ Watch build failed." >&2
        echo "   If this is a signing error (No profiles for '$WATCH_BUNDLE_ID'), open Xcode →" >&2
        echo "   Settings → Accounts, sign in with team 6NWX2DHB9Q, then retry." >&2
        failures=$((failures + 1))
        WATCH_FAILED=$((WATCH_FAILED + 1))
    elif [[ ! -d "$WATCH_APP_PATH" ]]; then
        echo "❌ Built watch app not found at $WATCH_APP_PATH" >&2
        echo "   The watch product path may have changed — check the SingleThreadWatch" >&2
        echo "   scheme's destination (generic/platform=watchOS) and the Products dir." >&2
        failures=$((failures + 1))
        WATCH_FAILED=$((WATCH_FAILED + 1))
    else
        for entry in "${WATCH_DEVICES[@]}"; do
            watch_id="${entry%%|*}"
            watch_name="${entry#*|}"

            echo ""
            echo "==> Installing on ${watch_name}…"
            if ! watch_install_output=$(xcrun devicectl device install app --device "$watch_id" "$WATCH_APP_PATH" 2>&1); then
                echo "$watch_install_output" >&2
                echo "❌ Watch install failed on $watch_name." >&2
                if [[ "$watch_install_output" == *4016* ]]; then
                    echo "   devicectl lost the connection to the watch mid-run (error 4016) — put it on" >&2
                    echo "   your wrist, unlock its paired iPhone, keep it near this Mac, then retry." >&2
                fi
                failures=$((failures + 1))
                WATCH_FAILED=$((WATCH_FAILED + 1))
                continue
            fi

            echo "==> Launching $WATCH_BUNDLE_ID on ${watch_name}…"
            if xcrun devicectl device process launch --terminate-existing --activate --device "$watch_id" "$WATCH_BUNDLE_ID"; then
                WATCH_LAUNCHED=$((WATCH_LAUNCHED + 1))
                WATCH_LAUNCH_FORM="--terminate-existing --activate"
            else
                echo "⚠️  --activate was rejected (it is not supported on every watchOS version) — retrying without it…" >&2
                if xcrun devicectl device process launch --terminate-existing --device "$watch_id" "$WATCH_BUNDLE_ID"; then
                    WATCH_LAUNCHED=$((WATCH_LAUNCHED + 1))
                    WATCH_LAUNCH_FORM="--terminate-existing"
                else
                    echo "❌ Watch launch failed on $watch_name (both the --activate and the minimal form failed)." >&2
                    failures=$((failures + 1))
                    WATCH_FAILED=$((WATCH_FAILED + 1))
                fi
            fi
        done
    fi
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