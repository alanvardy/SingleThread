#!/usr/bin/env bash
# Offline checks for scripts/run-devices.sh discovery + summary behaviour.
#
# Covers what a hardware-free run can: script syntax, shellcheck, the two inline
# python discovery filters replayed against a saved `xcrun devicectl list
# devices -j` inventory (scripts/fixtures/devicectl-devices.json), and the bash
# control flow (zero-device gate, failure tally, build gate, summary, exit
# codes) replayed with stubbed xcrun/xcodebuild. The install/launch legs against
# a real watch are verified by a hardware run of ./scripts/run-devices.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPT=scripts/run-devices.sh
FIXTURE=scripts/fixtures/devicectl-devices.json

if [[ ! -f "$FIXTURE" ]]; then
    echo "❌ Missing fixture $FIXTURE" >&2
    exit 1
fi

fail=0
check() {
    local label="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        echo "✅ $label"
    else
        echo "❌ $label" >&2
        printf '   want: %s\n   got:  %s\n' "$want" "$got" >&2
        fail=1
    fi
}

echo "==> bash -n"
bash -n "$SCRIPT"
echo "✅ syntax"

if command -v shellcheck >/dev/null 2>&1; then
    echo "==> shellcheck"
    # SC1111 is excluded: the pre-existing iOS message in run-devices.sh contains
    # unicode quotes, and rewriting that message is not part of this change.
    shellcheck -S warning --exclude=SC1111 "$SCRIPT"
    echo "✅ shellcheck"
else
    echo "⚠️  shellcheck not installed — skipped"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The two discovery filters are inline python heredocs. Extract them in file
# order (1 = iOS, 2 = watch) so the fixture assertions below exercise the exact
# code the script runs — no copy that can drift.
extract_filter() {
    awk -v want="$1" -v open="<<'PY'" '
        index($0, open) { n++; inblock = 1; next }
        /^PY$/ { inblock = 0; next }
        inblock && n == want { print }
    ' "$SCRIPT"
}
extract_filter 1 > "$work/ios.py"
extract_filter 2 > "$work/watch.py"
if [[ ! -s "$work/ios.py" || ! -s "$work/watch.py" ]]; then
    echo "❌ could not extract both discovery filters from $SCRIPT (did a heredoc move?)" >&2
    exit 1
fi

python3 "$work/ios.py" "$FIXTURE" "$work/ios-unreachable.log" device \
    > "$work/ios-out" 2> "$work/ios-stderr"
python3 "$work/ios.py" "$FIXTURE" "$work/ios-sim-unreachable.log" sim \
    > "$work/ios-sim-out" 2> "$work/ios-sim-stderr"
python3 "$work/watch.py" "$FIXTURE" "$work/watch-unreachable.log" > "$work/watch-out" 2> "$work/watch-stderr"
for produced in ios-out ios-stderr ios-sim-out ios-sim-stderr watch-out watch-stderr; do
    if [[ ! -e "$work/$produced" ]]; then
        echo "❌ a discovery filter did not produce $work/$produced" >&2
        exit 1
    fi
done

# IOS_TARGET=device (the legacy all-physical sweep): every paired physical
# iPhone/iPad qualifies.
check "device mode emits the reachable physical iPhone" \
    "1" "$(grep -c '|Fixture iPhone$' "$work/ios-out" || true)"
check "device mode emits the paired iPhone Duo even with Developer Mode off" \
    "1" "$(grep -c '|Fixture iPhone Duo$' "$work/ios-out" || true)"
check "device mode emits the physical iPad with Developer Mode off" \
    "1" "$(grep -c '|Fixture iPad DevMode Off$' "$work/ios-out" || true)"
check "device mode excludes a simulated iOS device" \
    "0" "$(grep -c '|Fixture iPhone Sim$' "$work/ios-out" || true)"
check "device mode warns about Developer Mode off" \
    "2" "$(grep -c 'Developer Mode off' "$work/ios-stderr" || true)"
check "device mode logs no unreachable devices" \
    "0" "$(wc -l < "$work/ios-unreachable.log" | tr -d ' ')"

# IOS_TARGET=sim (the default): only the physical iPhone Duo is a devicectl
# target; the regular iPhone/iPad run on simulators.
check "sim mode emits the paired iPhone Duo" \
    "1" "$(grep -c '|Fixture iPhone Duo$' "$work/ios-sim-out" || true)"
check "sim mode excludes the regular physical iPhone" \
    "0" "$(grep -c '|Fixture iPhone$' "$work/ios-sim-out" || true)"
check "sim mode excludes the physical iPad" \
    "0" "$(grep -c '|Fixture iPad DevMode Off$' "$work/ios-sim-out" || true)"
check "sim mode excludes a simulated iOS device" \
    "0" "$(grep -c '|Fixture iPhone Sim$' "$work/ios-sim-out" || true)"
check "sim mode warns about the Duo's Developer Mode off" \
    "1" "$(grep -c 'Developer Mode off' "$work/ios-sim-stderr" || true)"
check "sim mode logs no unreachable devices" \
    "0" "$(wc -l < "$work/ios-sim-unreachable.log" | tr -d ' ')"

# DUO_DEVICE_ID wins over the name match: an explicit identifier selects exactly
# the Duo, and a non-matching identifier selects nothing.
python3 "$work/ios.py" "$FIXTURE" "$work/ios-duo-unreachable.log" sim \
    "CCCCCCCC-0000-0000-0000-000000000009" > "$work/ios-duo-out" 2>/dev/null
check "sim mode selects only the DUO_DEVICE_ID device" \
    "CCCCCCCC-0000-0000-0000-000000000009|Fixture iPhone Duo" "$(cat "$work/ios-duo-out")"
python3 "$work/ios.py" "$FIXTURE" "$work/ios-bogus-unreachable.log" sim \
    "BBBBBBBB-0000-0000-0000-000000000000" > "$work/ios-bogus-out" 2>/dev/null
check "sim mode ignores a non-matching DUO_DEVICE_ID" \
    "0" "$(wc -c < "$work/ios-bogus-out" | tr -d ' ')"

check "watch filter emits only the reachable physical watch" \
    "AAAAAAAA-0000-0000-0000-000000000002|Fixture Watch Reachable" "$(cat "$work/watch-out")"
check "watch filter logs the tunnel-down watch as unreachable" \
    "Fixture Watch Ultra" "$(cat "$work/watch-unreachable.log")"
check "watch filter reports the unpaired watch" \
    "1" "$(grep -c 'not paired with this Mac' "$work/watch-stderr" || true)"
check "watch filter reports the developer-mode-disabled watch" \
    "1" "$(grep -c 'Developer Mode disabled' "$work/watch-stderr" || true)"

# A saved inventory that is valid JSON but not a devicectl payload must make the
# filters emit nothing without a traceback (run-devices.sh rejects invalid JSON
# up front; this covers the valid-JSON/wrong-shape case).
echo '{}' > "$work/empty-inventory.json"
python3 "$work/ios.py" "$work/empty-inventory.json" "$work/ios-empty-unreachable.log" sim \
    > "$work/ios-empty-out" 2> "$work/ios-empty-stderr"
python3 "$work/watch.py" "$work/empty-inventory.json" "$work/watch-empty-unreachable.log" \
    > "$work/watch-empty-out" 2> "$work/watch-empty-stderr"
check "iOS filter tolerates an inventory missing result.devices" \
    "0" "$(wc -c < "$work/ios-empty-out" | tr -d ' ')"
check "iOS filter emits no traceback on a missing-shape inventory" \
    "0" "$(grep -c 'Traceback' "$work/ios-empty-stderr" || true)"
check "watch filter tolerates an inventory missing result.devices" \
    "0" "$(wc -c < "$work/watch-empty-out" | tr -d ' ')"
check "watch filter emits no traceback on a missing-shape inventory" \
    "0" "$(grep -c 'Traceback' "$work/watch-empty-stderr" || true)"

# ── Control flow — stubbed tooling, no hardware ─────────────────────────────
# Replays the script end-to-end so the zero-device gate, failure tally, build
# gate, summary and exit codes are exercised. Stubs keep every xcodebuild and
# devicectl call at exit 0.
stub_dir="$work/stubs"
mkdir -p "$stub_dir" \
    "$work/derived/Build/Products/Debug-watchos/SingleThreadWatch.app" \
    "$work/derived/Build/Products/Debug-iphoneos/SingleThread.app" \
    "$work/derived/Build/Products/Debug-iphonesimulator/SingleThread.app" \
    "$work/derived/Build/Products/Debug/SingleThread.app" \
    "$work/derived-nosim/Build/Products/Debug-watchos/SingleThreadWatch.app" \
    "$work/derived-nosim/Build/Products/Debug-iphoneos/SingleThread.app" \
    "$work/derived-nosim/Build/Products/Debug/SingleThread.app"
cat > "$stub_dir/xcodebuild" <<'STUB'
#!/usr/bin/env bash
if [[ "${STUB_MAC_BUILD_FAIL:-0}" == "1" ]]; then
    for arg in "$@"; do
        if [[ "$arg" == "platform=macOS" ]]; then
            echo "stub macOS build failure" >&2
            exit 1
        fi
    done
fi
exit 0
STUB
# simctl listings are answered from a fixed inventory so the sim legs resolve a
# concrete UDID; every devicectl/other call is a no-op success.
cat > "$stub_dir/xcrun" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "simctl" ]]; then
    case "$2" in
        list)
            printf '    iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown)\n'
            printf '    iPad (A16) (22222222-2222-2222-2222-222222222222) (Shutdown)\n'
            printf '    Apple Watch Series 11 (46mm) (33333333-3333-3333-3333-333333333333) (Shutdown)\n'
            exit 0
            ;;
        bootstatus)
            [[ "${STUB_SIM_BOOT_FAIL:-0}" == "1" ]] && exit 1
            exit 0
            ;;
    esac
fi
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub_dir/open"
chmod +x "$stub_dir/xcodebuild" "$stub_dir/xcrun" "$stub_dir/open"

python3 - "$work" <<'PY'
import json
import pathlib
import sys

work = pathlib.Path(sys.argv[1])


def watch(state, tunnel):
    return {
        "identifier": "AAAAAAAA-0000-0000-0000-000000000001",
        "hardwareProperties": {
            "platform": "watchOS",
            "deviceType": "appleWatch",
            "reality": "physical",
        },
        "deviceProperties": {"name": "Stub Watch", "developerModeStatus": "enabled"},
        "connectionProperties": {
            "pairingState": "paired",
            "transportType": "localNetwork",
            "tunnelState": tunnel,
        },
        "properties": {"connection": {"pairingState": "paired", "state": state}},
    }


(work / "flow-unreachable-watch.json").write_text(
    json.dumps({"result": {"devices": [watch("disconnected", "disconnected")]}})
)
(work / "flow-reachable-watch.json").write_text(
    json.dumps({"result": {"devices": [watch("connected", "connected")]}})
)
(work / "flow-no-devices.json").write_text(json.dumps({"result": {"devices": []}}))
PY

run_flow() {
    local label="$1" want_exit="$2" want_text="$3" want_absent="$4"
    shift 4
    local log="$work/flow-$label.log" got_exit
    if env PATH="$stub_dir:$PATH" DERIVED_DATA="$work/derived" "$@" \
        bash "$SCRIPT" > "$log" 2>&1; then
        got_exit=0
    else
        got_exit=$?
    fi
    local ok=1
    [[ "$got_exit" == "$want_exit" ]] || ok=0
    if [[ -n "$want_text" ]] && ! grep -qF "$want_text" "$log"; then ok=0; fi
    if [[ -n "$want_absent" ]] && grep -qF "$want_absent" "$log"; then ok=0; fi
    check "flow: $label (exit $got_exit)" "ok" "$([[ "$ok" -eq 1 ]] && echo ok || echo bad)"
    if [[ "$ok" -ne 1 ]]; then
        sed 's/^/   | /' "$log" >&2
    fi
}

run_flow "unreachable-watch-only still builds" 1 \
    "==> Building SingleThreadWatch" "No reachable iPhone/iPad found." \
    DEVICES_JSON_IN="$work/flow-unreachable-watch.json" RUN_WATCH=1 RUN_MAC=0
run_flow "reachable-watch-only succeeds" 0 \
    "and 1 Apple Watch(es)" "No reachable iPhone/iPad found." \
    DEVICES_JSON_IN="$work/flow-reachable-watch.json" RUN_WATCH=1 RUN_MAC=0
run_flow "no iOS and no watch keeps the iOS fail-fast" 1 \
    "No reachable iPhone/iPad found." "==> Building SingleThreadWatch" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" IOS_TARGET=device RUN_WATCH=1 RUN_MAC=0
run_flow "RUN_WATCH=0 emits no watch output" 1 \
    "No reachable iPhone/iPad found." "Apple Watch" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" IOS_TARGET=device RUN_WATCH=0 RUN_MAC=0
run_flow "default sim mode launches the iPhone simulator" 0 \
    "iPhone/iPad (sim): 2/2 launched" "No reachable iPhone/iPad found." \
    DEVICES_JSON_IN="$work/flow-no-devices.json" RUN_WATCH=0 RUN_MAC=0
run_flow "simulator boot failure is a failed step" 1 \
    "failed to boot" "" \
    DEVICES_JSON_IN="$FIXTURE" RUN_WATCH=0 RUN_MAC=1 STUB_SIM_BOOT_FAIL=1
check "boot failure still runs the Duo leg" "1" \
    "$(grep -c 'iPhone Duo (device): 1/1 launched' "$work/flow-simulator boot failure is a failed step.log" || true)"
check "boot failure still runs the macOS leg" "1" \
    "$(grep -c 'macOS: built and launched' "$work/flow-simulator boot failure is a failed step.log" || true)"
run_flow "missing sim product is a failed step" 1 \
    "Built app not found at" "" \
    DEVICES_JSON_IN="$FIXTURE" RUN_WATCH=0 RUN_MAC=0 DERIVED_DATA="$work/derived-nosim"
run_flow "unresolvable iPad sim is a failed step" 1 \
    "No available simulator for iPad" "" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" RUN_WATCH=0 RUN_MAC=0 SIM_IPAD="No Such Device"
run_flow "sim mode deploys only the iPhone Duo physically" 0 \
    "iPhone Duo (device): 1/1 launched" "No reachable iPhone/iPad found." \
    DEVICES_JSON_IN="$FIXTURE" RUN_WATCH=0 RUN_MAC=0
run_flow "IOS_TARGET=device restores the all-physical sweep" 0 \
    "iPhone/iPad (device): 3/3 launched" "iPhone/iPad (sim)" \
    DEVICES_JSON_IN="$FIXTURE" IOS_TARGET=device RUN_WATCH=0 RUN_MAC=0
run_flow "macOS success is reported in the summary" 0 \
    "macOS: built and launched" "macOS: build failed" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" RUN_WATCH=0 RUN_MAC=1
run_flow "macOS build failure is reported in the summary" 1 \
    "macOS: build failed" "macOS: built and launched" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" RUN_WATCH=0 RUN_MAC=1 STUB_MAC_BUILD_FAIL=1

echo ""
if [[ "$fail" -eq 0 ]]; then
    echo "✅ run-devices.sh offline checks passed."
else
    echo "❌ run-devices.sh offline checks failed." >&2
    exit 1
fi
