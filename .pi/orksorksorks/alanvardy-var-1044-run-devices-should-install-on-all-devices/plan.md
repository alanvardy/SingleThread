# Implementation Plan

## Overview

`./scripts/run-devices.sh` gains a third platform leg — discover → build →
install → launch → summary for a physical Apple Watch — so one run covers
iPhone, iPad, macOS, and Apple Watch. The iOS and macOS legs keep their current
sequence and behaviour; every watch failure path names a cause and a fix, and
the watch is built even when its CoreDevice tunnel is down, so the device-signed
`Debug-watchos` product is verifiable on a Mac where the watch is currently
`disconnected`.

Scope is `scripts/run-devices.sh` plus two new committed files in Phase 3
(`scripts/fixtures/devicectl-devices.json`, `scripts/test-run-devices.sh`). No
`.swift` file, no `project.pbxproj`, no `Makefile`/CI change, no shell test
target.

## Pre-flight notes for the implementer

- **`reality` is at `hardwareProperties.reality`, not top-level.** The design's
  filter clause (`reality == "physical"`) is written in the discovery code as
  `hardware.get("reality")`, alongside the existing `hardware.get("platform")`.
  A top-level `device["reality"]` does not exist in devicectl 2026-09 output and
  would exclude every watch.
- **Shell rules** (`~/.pi/agent/AGENTS.md`): the command tool runs fish, so run
  every verification through `bash -c '…'` or a `/tmp/*.sh` file — a heredoc or
  `$?` at the command line is a hard rejection.
- The whole Phase 1 + 2 end state of `scripts/run-devices.sh` was prototyped and
  validated with stubbed `xcrun`/`xcodebuild`/`open` (5 control-flow cases) plus
  `bash -n` and `shellcheck`; the snippets below are that validated code.
- Use the `edit` tool for the in-place changes (never a full-file `write` of
  `run-devices.sh`), so the untouched iOS/macOS regions are provably untouched.

---

## Phase 1: Walking skeleton — discover, diagnose, and build the watch app

Files: `scripts/run-devices.sh` (only).

### Changes

#### 1. Header comment — document the new overrides and the watch prerequisite

**File**: `scripts/run-devices.sh` (lines 3–23)
**Action**: modify

Replace the override list lines 10–12 and append a prerequisite paragraph after
line 23 (`# runbook for the signed flow.`):

```diff
-# scripts/run-devices.sh — build SingleThread for iOS, install + launch it on
-# every paired iPhone/iPad that has Developer Mode enabled (via devicectl),
-# and (by default) also build + launch it on the host Mac.
+# scripts/run-devices.sh — build SingleThread for iOS, install + launch it on
+# every paired iPhone/iPad that has Developer Mode enabled (via devicectl),
+# install + launch the watch app on every paired Apple Watch that is reachable,
+# and (by default) also build + launch it on the host Mac.
@@
 # Overrides (same env-override pattern as scripts/test.sh):
 #   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
-#   RUN_MAC=0   # skip the macOS build + launch step (default RUN_MAC=1)
+#   RUN_WATCH=0            # skip the watchOS build + install + launch step (default RUN_WATCH=1)
+#   RUN_MAC=0              # skip the macOS build + launch step (default RUN_MAC=1)
+#   WATCH_BUNDLE_ID=…      # defaults to ${BUNDLE_ID}.watchkitapp
+#   DEVICES_JSON_IN=…      # dev seam: read a saved `xcrun devicectl list devices -j`
+#                          # inventory instead of querying CoreDevice (offline filter checks)
@@
-# Devices are discovered dynamically each run, so a new iPhone/iPad is picked
+# Devices are discovered dynamically each run, so a new iPhone/iPad/Apple Watch
 # is picked up without editing this script.
@@
 # runbook for the signed flow.
+#
+# Apple Watch prerequisite: the watch must be on your wrist with its paired
+# iPhone nearby and unlocked, so CoreDevice's network tunnel to the watch is up.
+# A paired watch with the tunnel down is reported as unreachable with that hint
+# rather than surfacing a raw devicectl 4016 assertion later.
```

#### 2. Defaults block, second temp log, watch product path

**File**: `scripts/run-devices.sh` (lines 25–35)
**Action**: modify

```diff
 DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
+RUN_WATCH="${RUN_WATCH:-1}"
 RUN_MAC="${RUN_MAC:-1}"
+WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${BUNDLE_ID}.watchkitapp}"
+DEVICES_JSON_IN="${DEVICES_JSON_IN:-}"
 DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
 UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-unreachable-$$.log"
-trap 'rm -f "$DEVICES_JSON" "$UNREACHABLE_LOG"' EXIT
+WATCH_UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-watch-unreachable-$$.log"
+trap 'rm -f "$DEVICES_JSON" "$UNREACHABLE_LOG" "$WATCH_UNREACHABLE_LOG"' EXIT
 
 APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app"
+WATCH_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos/SingleThreadWatch.app"
 MAC_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/SingleThread.app"
```

#### 3. `DEVICES_JSON_IN` inventory seam

**File**: `scripts/run-devices.sh` (lines 40–45)
**Action**: modify

Turns the `devicectl list devices` call into a replayable seam. The copy (not a
symlink/reuse) keeps the `EXIT` trap's `rm -f` valid, so the operator's saved
inventory is never deleted.

```diff
 echo "==> Discovering paired iPhone/iPad devices…"
-if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
+if [[ -n "$DEVICES_JSON_IN" ]]; then
+    # Offline seam: a saved inventory is replayed so the discovery filters can be
+    # checked without hardware. The temp copy keeps the EXIT trap's cleanup valid.
+    echo "  (using the saved inventory in DEVICES_JSON_IN=$DEVICES_JSON_IN)"
+    if ! cp "$DEVICES_JSON_IN" "$DEVICES_JSON" 2>/dev/null; then
+        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN could not be read." >&2
+        exit 1
+    fi
+elif ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
     echo "❌ devicectl could not list devices." >&2
     echo "   Plug in a device, unlock it, and tap “Trust”, then retry." >&2
     exit 1
 fi
```

#### 4. Second discovery filter — physical, paired Apple Watch

**File**: `scripts/run-devices.sh` (insert after line 93, before the
`if [[ ${#DEVICES[@]} -eq 0 ]]` gate at line 95)
**Action**: add

Reads the same `$DEVICES_JSON` as the iOS filter. Keep condition: `platform ==
"watchOS"` **and** `deviceType == "appleWatch"` **and**
`hardwareProperties.reality == "physical"` **and**
`developerModeStatus == "enabled"`. Then: not `paired` → stderr notice, no
failure; paired but `properties.connection.state != "connected"` → name logged to
`$WATCH_UNREACHABLE_LOG` and a wrist/paired-iPhone hint; otherwise print
`identifier|name` (the CoreDevice pairing UUID, never the udid or name).

The whole block is guarded by `RUN_WATCH=1` so `RUN_WATCH=0` produces **zero**
watch output and contributes nothing to the failure tally.

```bash
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
```

> The `PY` terminator must stay at column 0 (heredoc terminator); the shell lines
> around it are indented. Do not re-indent the python body — a uniformly
> indented module is an `IndentationError`.

#### 5. Zero-device gate — a reachable watch is a reason to continue

**File**: `scripts/run-devices.sh` (lines 95–107)
**Action**: modify

Without this, `RUN_MAC=0` with no iOS device exits before the watch leg, making
the ticket's feature unreachable in that configuration. The existing fail-fast
for unreachable-only iOS devices (`existing behaviour`) is preserved when there
is no watch to fall back on.

```diff
 if [[ ${#DEVICES[@]} -eq 0 ]]; then
-    if [[ "$UNREACHABLE_COUNT" -gt 0 ]]; then
+    if [[ "$UNREACHABLE_COUNT" -gt 0 && ${#WATCH_DEVICES[@]} -eq 0 ]]; then
         echo "❌ $UNREACHABLE_COUNT device(s) found but unreachable — see messages above (unlock the device and connect it to this Mac's Wi-Fi, then retry)." >&2
         exit 1
     fi
     if [[ "$RUN_MAC" -eq 1 ]]; then
-        echo "  (no iPhone/iPad with Developer Mode enabled found — macOS run only)"
+        if [[ ${#WATCH_DEVICES[@]} -gt 0 || "$WATCH_UNREACHABLE_COUNT" -gt 0 ]]; then
+            echo "  (no iPhone/iPad with Developer Mode enabled found — macOS + Apple Watch run only)"
+        else
+            echo "  (no iPhone/iPad with Developer Mode enabled found — macOS run only)"
+        fi
+    elif [[ ${#WATCH_DEVICES[@]} -gt 0 ]]; then
+        echo "  (no iPhone/iPad with Developer Mode enabled found — Apple Watch run only)"
     else
         echo "❌ No iPhone/iPad with Developer Mode enabled found." >&2
         echo "   Plug in the device and enable Settings → Privacy & Security → Developer Mode, then retry." >&2
         exit 1
     fi
 fi
```

#### 6. Failure seeding + the watch-build gate

**File**: `scripts/run-devices.sh` (lines 109–112)
**Action**: modify

Unreachable watches are failed steps (design decision 3 / D1). The watch app is
built whenever a *physical* watch was discovered — reachability is irrelevant to
a build (design decision 4 / D2) — which for a tunnel-down watch means
`WATCH_UNREACHABLE_COUNT > 0` rather than a non-empty `WATCH_DEVICES`.

```diff
 failures=0
 # Devices that are paired but unreachable count as failed steps, matching the
 # old behavior where the guaranteed-failing install attempt was tried and failed.
 failures=$((failures + UNREACHABLE_COUNT))
+failures=$((failures + WATCH_UNREACHABLE_COUNT))
+
+# The watch app is built whenever a physical watch was discovered — reachability
+# is irrelevant to a build, and building here is the only way to exercise the
+# device-signed watch product without depending on the tunnel being up.
+WATCH_BUILD_NEEDED=0
+if [[ "$RUN_WATCH" -eq 1 ]] && [[ ${#WATCH_DEVICES[@]} -gt 0 || "$WATCH_UNREACHABLE_COUNT" -gt 0 ]]; then
+    WATCH_BUILD_NEEDED=1
+fi
+
+# Watch leg counters (reported by the Phase 3 summary).
+WATCH_LAUNCHED=0
+WATCH_FAILED=0
+WATCH_LAUNCH_FORM="none"
```

Declaring the counters here (rather than in Phase 2) keeps `set -u` satisfied
for the Phase-1 build-failure increments; both counter increments and the
`WATCH_LAUNCH_FORM` writer arrive in Phase 2.

#### 7. Watch build leg (between the iOS leg and the macOS leg)

**File**: `scripts/run-devices.sh` (insert between the iOS block's closing `fi`
at line 148 and the `# ── macOS (host) step` comment at line 150)
**Action**: add

Signed `generic/platform=watchOS` build with `-allowProvisioningUpdates`, into
the shared `$DERIVED_DATA`; both failure paths are loud and name a fix, and a
missing product never no-ops silently.

```bash
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
    fi
fi
```

Phase 2 turns the trailing `fi` into an `else` branch holding install + launch —
do not add an `else` now.

### Verification

#### Automated

- [x] `bash -n scripts/run-devices.sh` — clean
- [x] `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` — clean
      (`SC1111` is the pre-existing unicode-quote warning at the existing iOS
      "Trust" message; fixing it is out of scope). Plain `shellcheck` exits 1 on
      that pre-existing warning — that is the baseline, not a regression.
- [x] All Phase-1 control flow re-run with stubbed tooling (the harness already
      exists at `/tmp/var1044-run-devices-new.sh` + `/tmp/var1044-harness.sh` if
      you want to re-derive it; otherwise use the real runs below):
      `bash -c 'cd DerivedData-repo && PATH=/tmp/var1044-stubs:$PATH DEVICES_JSON_IN=<fixture> RUN_MAC=0 bash scripts/run-devices.sh'`
- [x] `ls -d DerivedData/Build/Products/Debug-watchos/SingleThreadWatch.app`
- [x] `codesign -dv --verbose=2 DerivedData/Build/Products/Debug-watchos/SingleThreadWatch.app`
      reports `TeamIdentifier=6NWX2DHB9Q`
- [x] `ls -d DerivedData/Build/Products/Debug-iphoneos/SingleThread.app` — the
      iOS product from the same `DerivedData` is still intact after the watch
      build (shared-DerivedData risk in `design.md`)

#### Manual

- [ ] **M1 — `RUN_WATCH=0`**: `RUN_WATCH=0 ./scripts/run-devices.sh` → output
      contains no line mentioning a watch, no `Debug-watchos` build, exit code
      as before this change.
- [ ] **M2 — watch discovered but tunnel down** (this Mac's state today):
      `RUN_WATCH=1 RUN_MAC=0 ./scripts/run-devices.sh` → prints
      `==> Discovering paired Apple Watches…`, names `Alan’s Apple Watch` as
      unreachable with the wrist/paired-iPhone hint, and prints **no**
      `Probe Watch S9` / `LocalTest Watch` / `CI Watch S11-local` line (the
      sims are excluded); the watch build still runs (the `Debug-watchos`
      product appears); exit 1.
- [ ] **M3 — saved-inventory replay** (no hardware, no rebuild of the filter):
      `xcrun devicectl list devices -j /tmp/var1044-devices.json` then
      `DEVICES_JSON_IN=/tmp/var1044-devices.json RUN_MAC=0 ./scripts/run-devices.sh`
      → the only watch name in the output is the real one; if its tunnel is up
      it is installed/launched, otherwise it is named unreachable (never both
      silent and absent). Never commit `/tmp/var1044-devices.json` — a live
      capture contains real UDIDs and serial numbers.

---

## Phase 2: Install + launch on the wrist (hardware-gated)

Files: `scripts/run-devices.sh` (only).

### Changes

#### 1. Per-watch install + launch loop (the `else` branch of the Phase 1 block)

**File**: `scripts/run-devices.sh` (inside the Phase-1 watch block)
**Action**: modify — extend `elif … fi` to `elif … else … fi`

Install uses the same `identifier|name` UUID as the iOS leg (never the udid),
and the launch retries once without `--activate` (documented "not supported on
all platforms") so "unsupported flag" is distinguishable from "app will not
launch". `WATCH_LAUNCH_FORM` records which form exited 0.

```bash
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
```

Unreachable watches are **not** install targets — they never enter
`WATCH_DEVICES`; they were already counted in Phase 1, so the loop must not
re-attempt them and must not surface a raw 4016 for them.

### Verification

#### Automated

- [ ] `bash -n scripts/run-devices.sh` and
      `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` — clean
- [ ] Stub control flow (the harness this plan was validated with) confirms:
      reachable watch + `RUN_MAC=0` → install and launch invoked once with the
      CoreDevice `identifier`; unreachable-only watch → zero install attempts
      and exit 1.

#### Manual (hardware — the merge gate)

- [ ] **M4 — happy path, watch on the wrist** (watch reachable, paired iPhone
      nearby and unlocked, both on this Mac's network):
      `RUN_MAC=0 ./scripts/run-devices.sh` → watch build succeeds,
      `Debug-watchos/SingleThreadWatch.app` is produced, the watch is installed
      and launched, the run ends `✅ … and 1 Apple Watch(es).` and exits 0.
- [ ] **M5 — which launch flag form worked**: the run prints
      `⚠️  --activate was rejected … retrying without it…` only if the first
      form failed; the Phase 3 summary line `Watch launch flags:` shows the form
      that exited 0. Record it in the PR — it is the only proof available for
      the watchOS flag-support unknown in `design.md` ("Open Risks").
- [ ] **M6 — sad path** (watch taken off the wrist / paired iPhone locked):
      `RUN_MAC=0 ./scripts/run-devices.sh` → the watch is named unreachable with
      the wrist/iPhone hint, **zero** install attempts are made, exit 1.
- [ ] **M7 — new build is really on the wrist**:
      `xcrun devicectl device info details --device 6EF5C1CD-A890-559B-98D5-8F7F5A5A699A`
      shows the app installed.

> **UNVALIDATED — this phase's hardware run is a merge gate.** A direct
> `devicectl device install app` of a `SKIP_INSTALL=YES` companion-embedded
> watch bundle has never succeeded anywhere in this repo (research Q4/Q5,
> design "Open Risks" item 1). If M4 fails with a provisioning/install error
> that cannot be resolved by signing in to Xcode with team 6NWX2DHB9Q, **stop
> and report** — design decision 1 (direct-to-watch install vs. companion
> relay) has to be revisited rather than patched around. Do not proceed to
> Phase 3 as "done" without M4's ✅.

---

## Phase 3: Hardening — summary, wording, and a hardware-free filter check

Files: `scripts/run-devices.sh`, `scripts/fixtures/devicectl-devices.json`
(new), `scripts/test-run-devices.sh` (new).

### Changes

#### 1. Per-platform summary block

**File**: `scripts/run-devices.sh` (the summary block, lines 174–182)
**Action**: modify

Keeps the existing `✅`/`❌` lines and exit codes exactly, and adds one line per
platform. The watch line distinguishes *0 watches found (not a failure)* →
*unreachable* → *failed*, and prints the working launch-flag form when a launch
succeeded.

```diff
+# ── Summary ────────────────────────────────────────────────────────────────────
 echo ""
+echo "==> Summary"
+echo "  iPhone/iPad: ${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
+if [[ "$RUN_WATCH" -eq 0 ]]; then
+    echo "  Apple Watch: skipped (RUN_WATCH=0)"
+elif [[ ${#WATCH_DEVICES[@]} -eq 0 && "$WATCH_UNREACHABLE_COUNT" -eq 0 ]]; then
+    echo "  Apple Watch: 0 watches found (not a failure)"
+else
+    watch_line="  Apple Watch: $WATCH_LAUNCHED launched, $WATCH_FAILED failed, $WATCH_UNREACHABLE_COUNT unreachable"
+    if [[ "$WATCH_UNREACHABLE_COUNT" -gt 0 ]]; then
+        watch_line="$watch_line  (tunnel down — is the watch on your wrist?)"
+    fi
+    echo "$watch_line"
+    if [[ "$WATCH_LAUNCHED" -gt 0 ]]; then
+        echo "  Watch launch flags: $WATCH_LAUNCH_FORM"
+    fi
+fi
+if [[ "$RUN_MAC" -eq 1 ]]; then
+    echo "  macOS: built and launched"
+else
+    echo "  macOS: skipped (RUN_MAC=0)"
+fi
+
+echo ""
 if [[ "$failures" -eq 0 ]]; then
     summary="Installed and launched on ${#DEVICES[@]} device(s)"
     [[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
+    [[ "$WATCH_LAUNCHED" -gt 0 ]] && summary="$summary and $WATCH_LAUNCHED Apple Watch(es)"
     echo "✅ $summary."
 else
     echo "❌ $failures step(s) failed — see errors above." >&2
     exit 1
 fi
```

Hint strings are now complete and each names a fix: tunnel down (watch
discovery), signing/profile failure and missing `Debug-watchos` product (watch
build), launch-flag fallback taken and both launch forms failing (launch),
devicectl 4016 (watch install). New messages deliberately contain no unicode
quote characters (SC1111).

#### 2. Fixture — a saved `devicectl list devices -j` inventory

**File**: `scripts/fixtures/devicectl-devices.json`
**Action**: create

Generate it once with this snippet, review it, then commit the JSON it writes
(`grep -n 'CCCCCCCC' scripts/fixtures/devicectl-devices.json` must show
`…0007` for `Fixture iPhone` — `scripts/test-run-devices.sh` pins that value).
The inventory is synthetic: it mirrors the real 2026-09 shape
(`hardwareProperties`/`deviceProperties`/`connectionProperties`/`properties`) and
covers every filter branch, with invented identifiers, UDIDs and serial numbers.

```bash
python3 - <<'PY'
import json, pathlib

def dev(kind, reality, name, devmode, ident, udid, product_type,
        pair="paired", state="connected", transport="localNetwork", tunnel="connected"):
    platform, device_type = ("watchOS", "appleWatch") if kind == "watch" else ("iOS", kind)
    d = {
        "identifier": ident,
        "hardwareProperties": {
            "platform": platform,
            "deviceType": device_type,
            "reality": reality,
            "marketingName": name,
            "productType": product_type,
            "udid": udid,
            "serialNumber": "SYNTH000000",
            "ecid": 1,
        },
        "deviceProperties": {"name": name, "bootState": "booted"},
        "connectionProperties": {
            "authenticationType": "manualPairing",
            "pairingState": pair,
            "transportType": transport,
            "tunnelState": tunnel,
        },
        "properties": {
            "connection": {
                "authenticationType": "manualPairing",
                "pairingState": pair,
                "state": state,
            }
        },
    }
    if devmode is not None:
        d["deviceProperties"]["developerModeStatus"] = devmode
    return d

watch_physical = dict(kind="watch", reality="physical", product_type="Watch6,18")
watch_sim = dict(kind="watch", reality="simulated", product_type="Watch6,18",
                 transport="sameMachine")

devices = [
    # Physical watch, paired, tunnel down -> named unreachable, counted as a failure.
    dev(**watch_physical, name="Fixture Watch Ultra", devmode="enabled",
        ident="AAAAAAAA-0000-0000-0000-000000000001", udid="00000000-0001",
        state="disconnected", tunnel="disconnected"),
    # Physical watch, paired, tunnel up -> the only reachable watch.
    dev(**watch_physical, name="Fixture Watch Reachable", devmode="enabled",
        ident="AAAAAAAA-0000-0000-0000-000000000002", udid="00000000-0002"),
    # Physical watch, Developer Mode enabled but not paired -> quiet skip.
    dev(**watch_physical, name="Fixture Watch Unpaired", devmode="enabled",
        ident="AAAAAAAA-0000-0000-0000-000000000003", udid="00000000-0003",
        pair="unpaired", state="disconnected", tunnel="disconnected"),
    # Physical watch with Developer Mode off -> skip notice.
    dev(**watch_physical, name="Fixture Watch DevMode Off", devmode="disabled",
        ident="AAAAAAAA-0000-0000-0000-000000000004", udid="00000000-0004"),
    # Watch simulators as devicectl lists them -> excluded by reality.
    dev(**watch_sim, name="Fixture Watch Sim", devmode=None,
        ident="BBBBBBBB-0000-0000-0000-000000000005", udid="00000000-0005",
        state="disconnected", tunnel="disconnected"),
    dev(**watch_sim, name="Fixture Watch Sim DevMode", devmode="enabled",
        ident="BBBBBBBB-0000-0000-0000-000000000006", udid="00000000-0006",
        state="disconnected", tunnel="disconnected"),
    # Reachable physical iPhone -> the iOS leg's own case.
    dev(kind="iPhone", reality="physical", name="Fixture iPhone", devmode="enabled",
        ident="CCCCCCCC-0000-0000-0000-000000000007", udid="00000000-0007",
        product_type="iPhone17,1"),
    # iOS device with Developer Mode off -> iOS skip notice.
    dev(kind="iPad", reality="physical", name="Fixture iPad DevMode Off", devmode="disabled",
        ident="CCCCCCCC-0000-0000-0000-000000000008", udid="00000000-0008",
        product_type="iPad16,3"),
]

out = {"result": {"devices": devices}}
p = pathlib.Path('scripts/fixtures')
p.mkdir(parents=True, exist_ok=True)
(p / 'devicectl-devices.json').write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
print("fixture written:", p / 'devicectl-devices.json')
PY
```

The input format contract is `xcrun devicectl list devices -j` output verbatim
(top-level `result.devices`); a live capture dropped in via `DEVICES_JSON_IN`
needs no conversion.

#### 3. Offline filter + script checks

**File**: `scripts/test-run-devices.sh`
**Action**: create

The repo has no shell test target and the design excludes adding one, so this is
a standalone script (`bash scripts/test-run-devices.sh`, exit 1 on failure). It
extracts the two inline python filters from `run-devices.sh` *in file order*
(1 = iOS, 2 = watch) so the assertions exercise the code the script actually
runs rather than a copy that can drift — and fails loudly if a heredoc moves.

```bash
#!/usr/bin/env bash
# Offline checks for scripts/run-devices.sh discovery + summary behaviour.
#
# Covers what a hardware-free run can: script syntax, shellcheck, and the two
# inline python discovery filters replayed against a saved
# `xcrun devicectl list devices -j` inventory
# (scripts/fixtures/devicectl-devices.json). The install/launch legs need a real
# watch and are verified by a hardware run of ./scripts/run-devices.sh.
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
    awk -v want="$1" '/<<.PY./{n++; inblock=1; next} /^PY$/{inblock=0} inblock && n==want{print}' "$SCRIPT"
}
extract_filter 1 > "$work/ios.py"
extract_filter 2 > "$work/watch.py"
if [[ ! -s "$work/ios.py" || ! -s "$work/watch.py" ]]; then
    echo "❌ could not extract both discovery filters from $SCRIPT (did a heredoc move?)" >&2
    exit 1
fi

python3 "$work/ios.py" "$FIXTURE" "$work/ios-unreachable.log" > "$work/ios-out" 2> "$work/ios-stderr"
python3 "$work/watch.py" "$FIXTURE" "$work/watch-unreachable.log" > "$work/watch-out" 2> "$work/watch-stderr"

check "iOS filter emits the reachable physical iPhone" \
    "CCCCCCCC-0000-0000-0000-000000000007|Fixture iPhone" "$(cat "$work/ios-out")"
check "iOS filter logs no unreachable devices" \
    "0" "$(wc -l < "$work/ios-unreachable.log" | tr -d ' ')"
check "iOS filter reports the Developer-Mode-disabled iPad" \
    "1" "$(grep -c 'Developer Mode disabled' "$work/ios-stderr" || true)"

check "watch filter emits only the reachable physical watch" \
    "AAAAAAAA-0000-0000-0000-000000000002|Fixture Watch Reachable" "$(cat "$work/watch-out")"
check "watch filter logs the tunnel-down watch as unreachable" \
    "Fixture Watch Ultra" "$(cat "$work/watch-unreachable.log")"
check "watch filter reports the unpaired watch" \
    "1" "$(grep -c 'not paired with this Mac' "$work/watch-stderr" || true)"
check "watch filter reports the developer-mode-disabled watch" \
    "1" "$(grep -c 'Developer Mode disabled' "$work/watch-stderr" || true)"

echo ""
if [[ "$fail" -eq 0 ]]; then
    echo "✅ run-devices.sh offline checks passed."
else
    echo "❌ run-devices.sh offline checks failed." >&2
    exit 1
fi
```

`scripts/test-run-devices.sh` is **not** wired into `make test` or
`scripts/test.sh`: the design excludes a shell test target, and this script must
not change the CI gate. It is run by hand and by the reviewer.

### Verification

#### Automated

- [ ] `chmod +x scripts/test-run-devices.sh && bash scripts/test-run-devices.sh`
      → every check `✅`, exit 0
- [ ] `bash -n scripts/run-devices.sh` and
      `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` — clean
- [ ] `jq -e '.result.devices | length == 8' scripts/fixtures/devicectl-devices.json`
      (or `python3 -c 'import json;print(len(json.load(open("scripts/fixtures/devicectl-devices.json"))["result"]["devices"]))'`)
- [ ] `git status --short` shows no `.pi/` file and no captured live inventory
- [ ] `make format` then `make lint` — no Swift changes, but this is the repo's
      pre-commit pair and must not regress

#### Manual

- [ ] **M8 — the `RUN_WATCH × RUN_MAC` matrix** using stubs or the real Mac:

      | `RUN_WATCH` | `RUN_MAC` | watch reachable | expected |
      |---|---|---|---|
      | 0 | 1 | any | no watch output at all; same actions and exit as before this change |
      | 0 | 0 | any | iOS-only run, unchanged |
      | 1 | 0 | yes | watch built + installed + launched; ✅; exit 0 |
      | 1 | 0 | no | watch named unreachable; exit 1; no install attempt |
      | 1 | 1 | yes | all four platforms; ✅; exit 0 |
      | 1 | 1 | no | macOS + iOS still complete, watch named unreachable; ❌; exit 1 |

- [ ] `RUN_WATCH=0` produces no `==> Discovering paired Apple Watches…` line, no
      `Apple Watch` build, and no watch contribution to `failures`
- [ ] Every printed failure message names both a cause and a next action (read
      the captured output of the matrix, not just the exit codes)
- [ ] `RUN_WATCH=1 RUN_MAC=0 ./scripts/run-devices.sh` with the real watch named
      unreachable is the expected local outcome today (the tunnel is
      `disconnected`); it must exit 1 and must not print a raw devicectl 4016

#### Final gate

- [ ] One full `./scripts/test.sh` via the `run-gate` skill (async gate
      subagent, managed worktree, multi-hour timeout) — this script is not
      exercised by that gate, so the expectation is no new failures
- [ ] `git rm DELETEME` and `git status --short` clean before the PR is marked
      ready (branch bootstrap artifact; see `AGENTS.md`)

---

## Deviations from `structure.md` (and why)

1. **`reality` is read as `hardwareProperties.reality`.** `structure.md`/
   `design.md` write `reality == "physical"` without a path; the live 2026-09
   inventory carries it under `hardwareProperties` (verified against a real
   `xcrun devicectl list devices -j` capture). A top-level `device["reality"]`
   is always `None` and would drop every watch.
2. **The zero-device gate now considers a reachable watch** (Phase 1 change 5).
   `structure.md` did not list this block. Without it, `RUN_MAC=0` with no iOS
   device exits before the watch leg, so the new feature is unreachable in that
   configuration. The existing fail-fast for unreachable-only iOS devices is
   preserved when there is no watch, so today's behaviour is unchanged.
3. **An unpaired watch is a quiet skip, not a failed step** (Phase 1 change 4).
   `structure.md` put everything found-but-unreachable into `failures`, which
   would contradict design decision 6 ("a bare unpaired watch is also not a
   failure"). Pairing and reachability are therefore split: unpaired → skip
   notice (like Developer Mode disabled), paired-but-tunnel-down → failed step.
4. **`scripts/test-run-devices.sh` is a hand-run script, not a test target**
   (decision D3, and an explicit non-goal in `design.md`).
5. **`RUN_WATCH=0` is not byte-for-byte stdout-identical**: the new per-platform
   summary block (mandated by `structure.md` Phase 3) always prints. The
   *device-facing* behaviour — which builds, installs and launches run, and the
   exit code — is unchanged, which is how `structure.md`'s "byte-for-byte" check
   is verified in M8.
6. **`shellcheck` is run with `--exclude=SC1111`.** The script has one
   pre-existing SC1111 warning (unicode quotes in the existing iOS "Trust"
   message) and shellcheck is not wired into CI; fixing that message is
   adjacent-code cleanup, which the plan rules forbid.

## Out of scope (unchanged by this plan)

- Watch simulator flows (`Makefile` watch targets, CI `watch-ui-tests`,
  `scripts/test.sh`), `project.pbxproj` (signing, entitlements, bundle ids,
  `WKCompanionAppBundleIdentifier`), `Makefile`, `.github/workflows/ci.yml`.
- No `RUN_IOS` switch, no discovery refactor into functions, no parallel legs,
  no companion-relay install path, no `RUN_WATCH`-aware `make` target.
- No Swift code and no Swift tests: this ticket's logic is entirely shell, and
  `design.md` explicitly excludes a unit-test target for it. The
  `SingleThreadWatch` app itself is not modified.
