#!/usr/bin/env bash
set -euo pipefail

# scripts/run-devices.sh — build SingleThread for iOS, install + launch it in a
# simulator (the regular iPhone; the iPad follows), deploy it physically to the
# iPhone Duo (via devicectl), install + launch the watch app on an Apple Watch
# simulator, and (by default) also build + launch it on the host Mac. Set
# IOS_TARGET=device to build + launch on every paired physical iPhone/iPad
# instead (the Duo is always deployed physically).
#
#   ./scripts/run-devices.sh
#
# Overrides (same env-override pattern as scripts/test.sh):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   IOS_TARGET=sim         # sim (default) → the regular iPhone/iPad legs run on
#                          # simulators; device → the old all-physical sweep
#   SIM_IPHONE=…           # UDID or device name for the iPhone sim; empty → this
#                          # worktree's .simulator_id, else the iPhone 17 default
#   SIM_IPAD=…             # UDID or device name for the iPad sim; empty → iPad (A16)
#   SIM_WATCH=…            # UDID or device name for the watch sim; empty → Apple Watch Series 11 (46mm)
#   DUO_DEVICE_ID=…        # UDID of the physical iPhone Duo; empty → name match on "iPhone Duo"
#   RUN_WATCH=0            # skip the watchOS build + install + launch step (default RUN_WATCH=1)
#   RUN_MAC=0              # skip the macOS build + launch step (default RUN_MAC=1)
#   WATCH_BUNDLE_ID=…      # defaults to ${BUNDLE_ID}.watchkitapp
#   DEVICES_JSON_IN=…      # dev seam: read a saved `xcrun devicectl list devices -j`
#                          # inventory instead of querying CoreDevice (offline filter checks)
#
# Devices are discovered dynamically each run, so a new iPhone/iPad is picked
# up without editing this script. A newly paired device is registered
# in the developer account during its own build (-allowProvisioningDeviceRegistration),
# so no manual Xcode step is needed before it can install. A device that is unreachable (locked, asleep,
# off this Wi-Fi, unplugged mid-run) is detected during discovery and reported
# — the remaining devices still get built and run; an unreachable device counts
# as a failed step so the run exits non-zero. If no iOS devices are found and
# RUN_MAC=1, the script still does the macOS step; set RUN_MAC=0 to keep the
# old fail-fast behavior. The macOS app is built unsigned (CODE_SIGNING_ALLOWED=NO,
# matching `make mac-build`) because signing needs the Mac provisioning profile
# to carry the In-App Purchase entitlement — see make mac-run / the TestFlight
# runbook for the signed flow.
#
# Apple Watch prerequisite: the watch runs on a simulator, not on hardware, so
# no wrist / paired-iPhone / CoreDevice tunnel is involved. The named watch
# simulator must exist (xcrun simctl list devices); the app installs and launches
# on an unpaired watch sim (see scripts/appstore-screenshots.sh:29-31), so no
# simctl pair step is needed. An unavailable watch sim is a notice, not a
# failure; set SIM_WATCH= to pin one.

SCHEME="${SCHEME:-SingleThread}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.SingleThread}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
RUN_WATCH="${RUN_WATCH:-1}"
RUN_MAC="${RUN_MAC:-1}"
IOS_TARGET="${IOS_TARGET:-sim}"
SIM_IPHONE="${SIM_IPHONE:-}"   # explicit UDID or device name; empty = worktree sim, else iPhone 17
SIM_IPAD="${SIM_IPAD:-}"       # explicit UDID or device name; empty = iPad (A16)
SIM_WATCH="${SIM_WATCH:-}"     # explicit UDID or device name; empty = Apple Watch Series 11 (46mm)
DUO_DEVICE_ID="${DUO_DEVICE_ID:-}"
WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${BUNDLE_ID}.watchkitapp}"
DEVICES_JSON_IN="${DEVICES_JSON_IN:-}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-unreachable-$$.log"
trap 'rm -f "$DEVICES_JSON" "$UNREACHABLE_LOG"' EXIT

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app"
MAC_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/SingleThread.app"
SIM_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/SingleThread.app"
WATCH_SIM_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchsimulator/SingleThreadWatch.app"

DEFAULT_IPHONE_SIM="iPhone 17"
DEFAULT_IPAD_SIM="iPad (A16)"
DEFAULT_WATCH_SIM="Apple Watch Series 11 (46mm)"

cd "$(dirname "$0")/.."

# Pin a name-only simulator to a concrete UDID. An anchored name match stops
# `iPhone 17` selecting the leftover "Gate iPhone 17" sim (scripts/test.sh:27-36).
resolve_sim_udid() {
    local name="$1"
    xcrun simctl list devices available \
        | awk -v n="$name" '{ s = $0; sub(/^[ \t]+/, "", s); if (index(s, n " (") == 1) print }' \
        | head -1 \
        | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
}

# Precedence: an explicit UDID passes through; else this worktree's dedicated
# simulator (.simulator_id, written by the worktree_sim fish function); else the
# named default. Always yields a concrete UDID — never a bare `name=`.
resolve_ios_udid() { # $1 = value (UDID or name), $2 = default name, $3 = 1 to prefer .simulator_id
    local value="$1" default="$2" prefer_worktree="$3" udid=""
    if [[ -n "$value" ]]; then
        if [[ "$value" =~ ^[A-Fa-f0-9-]{36}$ ]]; then printf '%s\n' "$value"; return 0; fi
        resolve_sim_udid "$value"; return 0
    fi
    if [[ "$prefer_worktree" -eq 1 && -f .simulator_id ]]; then
        udid="$(tr -d '[:space:]' < .simulator_id)"
        if [[ -n "$udid" ]] && xcrun simctl list devices 2>/dev/null | grep -qF "($udid)"; then
            printf '%s\n' "$udid"; return 0
        fi
    fi
    resolve_sim_udid "$default"
}

# ── Discover devices ─────────────────────────────────────────────────────────
if [[ "$IOS_TARGET" == "sim" ]]; then
    echo "==> Discovering the paired iPhone Duo…"
else
    echo "==> Discovering paired iPhone/iPad devices…"
fi
if [[ -n "$DEVICES_JSON_IN" ]]; then
    # Offline seam: a saved inventory is replayed so the discovery filters can be
    # checked without hardware. The temp copy keeps the EXIT trap's cleanup valid.
    echo "  (using the saved inventory in DEVICES_JSON_IN=$DEVICES_JSON_IN)"
    if ! cp "$DEVICES_JSON_IN" "$DEVICES_JSON" 2>/dev/null; then
        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN could not be read." >&2
        exit 1
    fi
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$DEVICES_JSON" 2>/dev/null; then
        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN is not valid JSON." >&2
        exit 1
    fi
elif ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    echo "   Plug in a device, unlock it, and tap “Trust”, then retry." >&2
    exit 1
fi

# Emits "identifier|name" per qualifying devicectl target (platform iOS, iPhone
# or iPad, physical). Simulated devices are excluded — they are not devicectl
# install targets. In sim mode (the default) only the physical iPhone Duo is a
# devicectl target: DUO_DEVICE_ID wins when set, otherwise the name is matched
# case-insensitively on "iPhone Duo"; the regular iPhone/iPad legs run on
# simulators instead. In device mode every paired physical iPhone/iPad qualifies
# (the old all-physical sweep). A paired physical phone whose Developer Mode is
# off still qualifies and is named on stderr, so a newly paired device (e.g. a
# second iPhone) is never silently omitted. Unreachable qualifying devices are
# logged to "$UNREACHABLE_LOG" for the failure tally, so a phone that is locked /
# off-network / has Remote Device Services down is reported with the real reason
# instead of a raw devicectl 4016 install error.
DEVICES=()
while IFS= read -r entry; do
    DEVICES+=("$entry")
done < <(python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" "$IOS_TARGET" "$DUO_DEVICE_ID" <<'PY'
import json
import sys

mode = sys.argv[3] if len(sys.argv) > 3 else "device"
duo_id = sys.argv[4] if len(sys.argv) > 4 else ""

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

with open(sys.argv[2], "a", encoding="utf-8") as unreachable_log:
    result = payload.get("result") if isinstance(payload, dict) else None
    devices = result.get("devices", []) if isinstance(result, dict) else []
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        props = device.get("deviceProperties", {})
        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("deviceType") not in ("iPhone", "iPad"):
            continue
        # A paired iOS simulator shares platform/deviceType with a physical
        # device but is not a devicectl install target, so exclude it here.
        if hardware.get("reality") != "physical":
            continue
        name = props.get("name", "unknown device")
        if mode != "device":
            # Default sim mode: only the physical iPhone Duo is a devicectl
            # target. DUO_DEVICE_ID wins when set; otherwise a name match.
            if duo_id:
                if device.get("identifier") != duo_id:
                    continue
            elif "iphone duo" not in name.lower():
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
        # Developer Mode is required to run a development-signed build. Do not
        # pre-skip on it: every paired physical phone (e.g. a second iPhone)
        # must receive the build, and devicectl reports the real failure if
        # Developer Mode is off. Name the likely cause up front instead.
        if props.get("developerModeStatus") != "enabled":
            print(f"  (note: {name} has Developer Mode off — if the install below fails, enable Settings → Privacy & Security → Developer Mode on it)", file=sys.stderr)
        print(f"{device['identifier']}|{name}")
PY
)

UNREACHABLE_COUNT=0
if [[ -s "$UNREACHABLE_LOG" ]]; then
    UNREACHABLE_COUNT=$(wc -l < "$UNREACHABLE_LOG" | tr -d ' ')
fi

if [[ ${#DEVICES[@]} -eq 0 && "$IOS_TARGET" != "sim" ]]; then
    if [[ "$UNREACHABLE_COUNT" -gt 0 ]]; then
        echo "❌ $UNREACHABLE_COUNT device(s) found but unreachable — see messages above (unlock the device and connect it to this Mac's Wi-Fi, then retry)." >&2
        exit 1
    fi
    if [[ "$RUN_MAC" -eq 1 ]]; then
        echo "  (no reachable iPhone/iPad found — macOS run only)"
    else
        echo "❌ No reachable iPhone/iPad found." >&2
        echo "   Pair an iPhone/iPad, unlock it, and connect it to this Mac's Wi-Fi, then retry." >&2
        exit 1
    fi
fi

failures=0
# Devices that are paired but unreachable count as failed steps, matching the
# old behavior where the guaranteed-failing install attempt was tried and failed.
failures=$((failures + UNREACHABLE_COUNT))

# iOS leg counters (reported by the summary). A device is counted as launched
# only once devicectl launch exits 0, so a failed install is not reported as
# "launched".
IOS_LAUNCHED=0

# Simulator leg counters: in sim mode the regular iPhone/iPad legs report
# separately from the physical Duo (see the summary).
SIM_TOTAL=0
SIM_LAUNCHED=0

# Watch simulator leg counters (reported by the summary).
WATCH_TOTAL=0
WATCH_LAUNCHED=0
WATCH_FAILED=0

# macOS leg status (reported by the summary). Set to the outcome inside the
# macOS block below so a failed build is not reported as "built and launched".
MAC_STATUS="not run"

# ── iPhone/iPad simulator leg ─────────────────────────────────
# In sim mode the regular iPhone/iPad legs run on simulators; the iPhone Duo is
# still deployed physically by the device loop below. Targets are resolved to a
# concrete UDID up front so a bare `name=` destination never reaches xcodebuild.
if [[ "$IOS_TARGET" == "sim" ]]; then
    sim_targets=(
        "iPhone|$(resolve_ios_udid "$SIM_IPHONE" "$DEFAULT_IPHONE_SIM" 1)"
        "iPad|$(resolve_ios_udid "$SIM_IPAD" "$DEFAULT_IPAD_SIM" 0)"
    )
    for spec in "${sim_targets[@]}"; do
        sim_label="${spec%%|*}"
        sim_udid="${spec#*|}"
        SIM_TOTAL=$((SIM_TOTAL + 1))
        if [[ -z "$sim_udid" ]]; then
            echo "❌ No available simulator for $sim_label — set SIM_IPHONE=/SIM_IPAD= to pin one." >&2
            failures=$((failures + 1))
            continue
        fi
        echo ""
        echo "==> Booting the $sim_label simulator ($sim_udid)…"
        if ! xcrun simctl bootstatus "$sim_udid" -b; then
            echo "❌ Simulator $sim_label ($sim_udid) failed to boot." >&2
            failures=$((failures + 1))
            continue
        fi
        echo "==> Building $SCHEME ($CONFIGURATION) for the $sim_label simulator…"
        if ! xcodebuild -scheme "$SCHEME" -destination "id=$sim_udid" \
          -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" build; then
            echo "❌ Build failed for the $sim_label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        if [[ ! -d "$SIM_APP_PATH" ]]; then
            echo "❌ Built app not found at $SIM_APP_PATH" >&2
            failures=$((failures + 1))
            continue
        fi
        echo "==> Installing on the $sim_label simulator…"
        if ! xcrun simctl install "$sim_udid" "$SIM_APP_PATH"; then
            echo "❌ Install failed on the $sim_label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        echo "==> Launching on the $sim_label simulator…"
        if xcrun simctl launch "$sim_udid" "$BUNDLE_ID"; then
            SIM_LAUNCHED=$((SIM_LAUNCHED + 1))
        else
            echo "❌ Launch failed on the $sim_label simulator." >&2
            failures=$((failures + 1))
        fi
    done
fi

# ── Build + install + launch per iOS device (Duo / device mode) ──────────────
# Building against each device's own destination — rather than one
# generic/platform=iOS build — is what auto-registers a newly paired phone:
# -allowProvisioningDeviceRegistration only registers the *destination* device,
# so a generic destination leaves a new device out of the embedded provisioning
# profile and its install fails with 0xe8008012 ("This provisioning profile
# cannot be installed on this device"). The first device compiles; the rest only
# re-sign against the shared team profile, which now includes every registered
# device.
if [[ ${#DEVICES[@]} -gt 0 ]]; then
    for entry in "${DEVICES[@]}"; do
        device_id="${entry%%|*}"
        device_name="${entry#*|}"

        echo ""
        echo "==> Building $SCHEME ($CONFIGURATION) for ${device_name}…"
        if ! xcodebuild -scheme "$SCHEME" \
          -destination "id=$device_id" \
          -configuration "$CONFIGURATION" \
          -derivedDataPath "$DERIVED_DATA" \
          -allowProvisioningUpdates \
          -allowProvisioningDeviceRegistration \
          build; then
            echo "❌ Build failed for $device_name." >&2
            failures=$((failures + 1))
            continue
        fi

        if [[ ! -d "$APP_PATH" ]]; then
            echo "❌ Built app not found at $APP_PATH" >&2
            failures=$((failures + 1))
            continue
        fi

        echo "==> Installing on ${device_name}…"
        if ! xcrun devicectl device install app --device "$device_id" "$APP_PATH"; then
            echo "❌ Install failed on $device_name (is it unlocked?)." >&2
            failures=$((failures + 1))
            continue
        fi

        echo "==> Launching on ${device_name}…"
        if xcrun devicectl device process launch --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"; then
            IOS_LAUNCHED=$((IOS_LAUNCHED + 1))
        else
            echo "❌ Launch failed on $device_name." >&2
            failures=$((failures + 1))
        fi
    done
fi

# ── Apple Watch simulator leg ────────────────────────────────────────────────
# The watch runs on a simulator, not on hardware. The watch app installs and
# launches on an unpaired watch sim (scripts/appstore-screenshots.sh:29-31), so
# no simctl pair step is needed. An unavailable watch simulator is a notice, not
# a failure; RUN_WATCH=0 skips the leg entirely.
if [[ "$RUN_WATCH" -eq 1 ]]; then
    watch_udid="$(resolve_ios_udid "$SIM_WATCH" "$DEFAULT_WATCH_SIM" 0)"
    if [[ -z "$watch_udid" ]]; then
        echo "  (no '$SIM_WATCH' simulator available — skipping the Apple Watch leg; set SIM_WATCH= to pin one)"
    else
        WATCH_TOTAL=1
        echo ""
        echo "==> Booting Apple Watch simulator ($SIM_WATCH, $watch_udid)…"
        if ! xcrun simctl bootstatus "$watch_udid" -b; then
            echo "❌ Apple Watch simulator failed to boot." >&2
            failures=$((failures + 1))
            WATCH_FAILED=1
        else
            echo "==> Building SingleThreadWatch ($CONFIGURATION) for the simulator…"
            if ! xcodebuild -scheme SingleThreadWatch -destination "id=$watch_udid" \
              -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" build; then
                echo "❌ Watch build failed." >&2
                failures=$((failures + 1))
                WATCH_FAILED=1
            elif [[ ! -d "$WATCH_SIM_APP_PATH" ]]; then
                echo "❌ Built watch app not found at $WATCH_SIM_APP_PATH" >&2
                failures=$((failures + 1))
                WATCH_FAILED=1
            else
                echo "==> Installing on the Apple Watch simulator…"
                if ! xcrun simctl install "$watch_udid" "$WATCH_SIM_APP_PATH"; then
                    echo "❌ Watch install failed." >&2
                    failures=$((failures + 1))
                    WATCH_FAILED=1
                else
                    echo "==> Launching $WATCH_BUNDLE_ID on the Apple Watch simulator…"
                    if xcrun simctl launch "$watch_udid" "$WATCH_BUNDLE_ID"; then
                        WATCH_LAUNCHED=1
                    else
                        echo "❌ Watch launch failed." >&2
                        failures=$((failures + 1))
                        WATCH_FAILED=1
                    fi
                fi
            fi
        fi
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
        MAC_STATUS="build failed"
    elif [[ ! -d "$MAC_APP_PATH" ]]; then
        echo "❌ Built macOS app not found at $MAC_APP_PATH" >&2
        failures=$((failures + 1))
        MAC_STATUS="app not found"
    else
        echo "==> Launching $BUNDLE_ID on macOS…"
        if ! open "$MAC_APP_PATH"; then
            echo "❌ Failed to open $MAC_APP_PATH" >&2
            failures=$((failures + 1))
            MAC_STATUS="launch failed"
        else
            MAC_STATUS="built and launched"
        fi
    fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "==> Summary"
if [[ "$IOS_TARGET" == "sim" ]]; then
    echo "  iPhone/iPad (sim): $SIM_LAUNCHED/$SIM_TOTAL launched"
    echo "  iPhone Duo (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
else
    echo "  iPhone/iPad (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
fi
if [[ "$RUN_WATCH" -eq 0 ]]; then
    echo "  Apple Watch (sim): skipped (RUN_WATCH=0)"
elif [[ "$WATCH_TOTAL" -eq 0 ]]; then
    echo "  Apple Watch (sim): no simulator available (not a failure)"
else
    echo "  Apple Watch (sim): $WATCH_LAUNCHED launched, $WATCH_FAILED failed"
fi
if [[ "$RUN_MAC" -eq 1 ]]; then
    echo "  macOS: $MAC_STATUS"
else
    echo "  macOS: skipped (RUN_MAC=0)"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    summary="Installed and launched on ${#DEVICES[@]} device(s) and $SIM_LAUNCHED simulator(s)"
    [[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
    [[ "$WATCH_LAUNCHED" -gt 0 ]] && summary="$summary and $WATCH_LAUNCHED Apple Watch(es)"
    echo "✅ $summary."
else
    echo "❌ $failures step(s) failed — see errors above." >&2
    exit 1
fi