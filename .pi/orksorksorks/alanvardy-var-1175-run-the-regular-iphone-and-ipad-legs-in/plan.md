# Implementation Plan

## Overview

Change `scripts/run-devices.sh` so the regular iPhone/iPad legs and the Apple
Watch leg run in **simulators** by default, while the physical **iPhone Duo**
and the **macOS** leg stay on hardware. Add `IOS_TARGET=sim|device` (default
`sim`) so the old all-physical iOS sweep is one env var away, report every leg
honestly in the summary, and rewrite `scripts/test-run-devices.sh` to cover the
new behaviour offline (stubbed `simctl`, sim-vs-device fixtures, happy + sad
paths).

**Decisions locked at the plan gate:**

1. **`IOS_TARGET` scope (Q1 = A).** The Duo always deploys physically in both
   modes. `IOS_TARGET` selects only how the *regular* iPhone/iPad legs run:
   `sim` (default) → simulators; `device` → the old all-physical filter.
2. **Watch leg (Q2 = B).** The watch moves to **paired watch simulators**; the
   physical `devicectl` watch discovery/install/launch path is removed. (The
   watch app installs and launches on an unpaired watch sim — see
   `scripts/appstore-screenshots.sh:29-31` — so no `simctl pair` step is
   needed.) There is no `WATCH_TARGET` escape hatch: the ticket only asks for
   `IOS_TARGET`, so `IOS_TARGET=device` restores the old physical iPhone/iPad
   sweep but the watch stays on sims.
3. **Duo identity (Q3 = A, hybrid).** `DUO_DEVICE_ID=<udid>` wins when set;
   otherwise a case-insensitive substring match on the device name
   (`iPhone Duo`). This avoids the silent-drop failure mode of a name-only
   match.

**Out of scope (unchanged):** the macOS leg, CI, and the watch
auto-registration/4016 messaging (deleted with the physical watch path).

## Verified ground truth (checked this session)

- `scripts/run-devices.sh:41-56` declares the env vars and product paths to
  mirror. `RUN_WATCH`/`RUN_MAC` (lines 42-43 in the file as read) are the
  pattern for `IOS_TARGET`.
- Product paths: `$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app`
  (Duo), `${CONFIGURATION}-watchos/SingleThreadWatch.app` (old physical watch),
  `$CONFIGURATION/SingleThread.app` (macOS). The sim paths are
  `Debug-iphonesimulator/SingleThread.app` and
  `Debug-watchsimulator/SingleThreadWatch.app`
  (`scripts/appstore-screenshots.sh:176,179`).
- The iOS discovery filter is the **first** `<<'PY'` heredoc
  (`scripts/run-devices.sh:~88-133`); the watch filter is the second. The
  deciding predicates are `platform == "iOS"`, `deviceType in ("iPhone","iPad")`,
  `reality == "physical"`.
- Simulator UDID resolution to copy: `resolve_sim_udid()` at
  `scripts/test.sh:27-36` (anchored `index(s, n " (") == 1`), worktree
  precedence at `scripts/test.sh:53-75`.
- simctl boot/install/launch recipe to copy:
  `scripts/appstore-screenshots.sh:696-700` (iOS) and `:834-837` (watch),
  launch at `:623-625` / `:816-818`.
- `scripts/test-run-devices.sh` has `extract_filter()` (`:51-58`), a PATH-stub
  harness `run_flow()` (`:129-147`), stubs for `xcodebuild`/`xcrun`/`open`
  (`:117-127`), and product dirs `Debug-watchos`/`Debug-iphoneos`/`Debug`
  (`:118-120`). **No `simctl` stub exists.**
- Fixture (`scripts/fixtures/devicectl-devices.json`) physical iOS entries:
  `Fixture iPhone` (devMode enabled), `Fixture iPad DevMode Off`,
  `Fixture iPhone Duo` (devMode disabled); simulated: `Fixture iPhone Sim`.
- No simulator lock file exists in this repo (only the `.simulator_id`
  convention); `scripts/run-devices.sh` is not in the `Makefile` and is invoked
  via the fish alias `r` (`~/.dev/dotfiles/fish/functions/r.fish`).

---

## Phase 1: Walking skeleton — sim iPhone leg end-to-end

Thinnest path that makes the new default real: `IOS_TARGET` exists, discovery
splits to Duo-only, and one regular iPhone boots in the simulator, gets the app
built/installed/launched, and is reported separately from the Duo.

### Changes

#### 1. Env vars + header — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Add after `RUN_MAC` (around line 46):

```bash
IOS_TARGET="${IOS_TARGET:-sim}"
SIM_IPHONE="${SIM_IPHONE:-}"   # explicit UDID or device name; empty = worktree sim, else iPhone 17
SIM_IPAD="${SIM_IPAD:-}"       # explicit UDID or device name; empty = iPad (A16)
SIM_WATCH="${SIM_WATCH:-}"     # explicit UDID or device name; empty = Apple Watch Series 11 (46mm)
DUO_DEVICE_ID="${DUO_DEVICE_ID:-}"
```

Add the default simulator names and the sim product paths alongside the
`APP_PATH` block:

```bash
DEFAULT_IPHONE_SIM="iPhone 17"
DEFAULT_IPAD_SIM="iPad (A16)"
DEFAULT_WATCH_SIM="Apple Watch Series 11 (46mm)"
SIM_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/SingleThread.app"
```

Update the header docstring (lines 4-40) to state: the regular iPhone/iPad legs
run in simulators by default; the iPhone Duo and macOS stay physical; the watch
runs in a simulator (Phase 3); and document the new overrides
(`IOS_TARGET=sim|device` default `sim`, `SIM_IPHONE=`, `SIM_IPAD=`,
`SIM_WATCH=`, `DUO_DEVICE_ID=`). Describe `IOS_TARGET=device` as "the old
all-physical iPhone/iPad sweep (the Duo is always deployed physically)".

#### 2. UDID resolution helpers — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Add after `cd "$(dirname "$0")/.."` (line 58). Copy `resolve_sim_udid` verbatim
from `scripts/test.sh:27-36` and add a worktree-preferring resolver:

```bash
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
```

`SIM_IPHONE`/`SIM_IPAD`/`SIM_WATCH` are empty by default; the resolver's `$2`
is the named fallback, so no name is baked into the env vars. Keep
`.simulator_id` preference for the iPhone only (`$3=1`); the iPad and watch use
`$3=0`.

Resolve the targets up front (just before the sim leg), then iterate the
resolved list — the iPad is added to this same array in Phase 2:

```bash
sim_targets=()
if [[ "$IOS_TARGET" == "sim" ]]; then
    sim_targets+=("iPhone|$(resolve_ios_udid "$SIM_IPHONE" "$DEFAULT_IPHONE_SIM" 1)")
fi
```

In device mode `sim_targets` stays empty and no simulator is touched.

#### 3. Split the iOS discovery filter — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Change the filter invocation to pass a mode and the Duo override, and branch the
predicate on `sys.argv[3]`:

```bash
done < <(python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" "$IOS_TARGET" "$DUO_DEVICE_ID" <<'PY'
import json
import sys

mode = sys.argv[3] if len(sys.argv) > 3 else "device"
duo_id = sys.argv[4] if len(sys.argv) > 4 else ""
# ... open payload/unreachable_log as today ...
```

Replace the device-selection predicate (the `platform`/`deviceType`/`reality`
block) with:

```python
        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("deviceType") not in ("iPhone", "iPad"):
            continue
        if hardware.get("reality") != "physical":
            continue
        if mode != "device":
            # Default sim mode: only the physical iPhone Duo is a devicectl
            # target. DUO_DEVICE_ID wins when set; otherwise a name match.
            if duo_id:
                if device.get("identifier") != duo_id:
                    continue
            elif "iphone duo" not in name.lower():
                continue
```

Update the surrounding comments to explain the split. Keep the unreachable
detection and Developer-Mode note unchanged. Change the discovery banner to
branch on mode: `==> Discovering the paired iPhone Duo…` in sim mode, the
existing all-physical banner in device mode.

Also update the comment block above the loop (the "Building against each
device's own destination" note) to say it applies to the Duo / device mode.

#### 4. iPhone simulator leg — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Add `SIM_TOTAL`/`SIM_LAUNCHED` counters next to `IOS_LAUNCHED`. Insert a new
block **before** the device (Duo) loop, guarded by `[[ "$IOS_TARGET" == "sim" ]]`:

```bash
# ── iPhone/iPad simulator leg ─────────────────────────────────────────────────
SIM_TOTAL=0
SIM_LAUNCHED=0
if [[ "$IOS_TARGET" == "sim" ]]; then
    for spec in "${sim_targets[@]}"; do
        sim_label="${spec%%|*}"; udid="${spec#*|}"
        SIM_TOTAL=$((SIM_TOTAL + 1))
        if [[ -z "$udid" ]]; then
            echo "❌ No available simulator for $sim_label — set SIM_IPHONE=/SIM_IPAD= to pin one." >&2
            failures=$((failures + 1)); continue
        fi
        echo ""
        echo "==> Booting $sim_label simulator ($udid)…"
        if ! xcrun simctl bootstatus "$udid" -b; then
            echo "❌ Simulator $sim_label ($udid) failed to boot." >&2
            failures=$((failures + 1)); continue
        fi
        echo "==> Building $SCHEME ($CONFIGURATION) for the $sim_label simulator…"
        if ! xcodebuild -scheme "$SCHEME" -destination "id=$udid" \
          -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" build; then
            echo "❌ Build failed for the $sim_label simulator." >&2
            failures=$((failures + 1)); continue
        fi
        if [[ ! -d "$SIM_APP_PATH" ]]; then
            echo "❌ Built app not found at $SIM_APP_PATH" >&2
            failures=$((failures + 1)); continue
        fi
        echo "==> Installing on the $sim_label simulator…"
        if ! xcrun simctl install "$udid" "$SIM_APP_PATH"; then
            echo "❌ Install failed on the $sim_label simulator." >&2
            failures=$((failures + 1)); continue
        fi
        echo "==> Launching on the $sim_label simulator…"
        if xcrun simctl launch "$udid" "$BUNDLE_ID"; then
            SIM_LAUNCHED=$((SIM_LAUNCHED + 1))
        else
            echo "❌ Launch failed on the $sim_label simulator." >&2
            failures=$((failures + 1))
        fi
    done
fi
```

(`bootstatus -b` boots a shutdown device and blocks until booted; the
codebase treats a non-zero bootstatus as a boot failure — keep `simctl boot …
|| true` optional/unnecessary here so the sad path is testable.)

Update the zero-device gate (`if [[ ${#DEVICES[@]} -eq 0 ]]`) so sim mode does
not fail-fast when no Duo is found but `IOS_TARGET=sim` is set — sims always
provide an iOS target. Simplest: change the gate condition to
`if [[ ${#DEVICES[@]} -eq 0 && "$IOS_TARGET" != "sim" ]]`.

#### 5. Summary split — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Replace the first summary line with mode-aware lines:

```bash
if [[ "$IOS_TARGET" == "sim" ]]; then
    echo "  iPhone/iPad (sim): $SIM_LAUNCHED/$SIM_TOTAL launched"
    echo "  iPhone Duo (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
else
    echo "  iPhone/iPad (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
fi
```

Update the final success sentence to count sims honestly, e.g.
`summary="Installed and launched on ${#DEVICES[@]} device(s) and $SIM_LAUNCHED simulator(s)"`.

#### 6. Offline coverage — `scripts/test-run-devices.sh`

**File**: `scripts/test-run-devices.sh`
**Action**: modify

- **Filter invocation/args**: both `python3 "$work/ios.py"` calls (fixture
  assertions `:66-95` and the wrong-shape block `:98-113`) must now pass mode +
  Duo id, e.g.:
  `python3 "$work/ios.py" "$FIXTURE" "$work/ios-unreachable.log" sim` for the
  Duo assertions and `... device` for the legacy all-physical assertions.
- **New filter assertions** (sim mode): emits `|Fixture iPhone Duo` =1;
  excludes `|Fixture iPhone` =0, `|Fixture iPad DevMode Off` =0,
  `|Fixture iPhone Sim` =0; "Developer Mode off" count =1; unreachable =0.
- **`DUO_DEVICE_ID` assertion**: run the filter in sim mode with the Duo's
  identifier (`CCCCCCCC-…0009`, exact value from the fixture) and assert it is
  the only emission; with a bogus id assert 0 emissions.
- **Stubs**: extend the `xcrun` stub (`:124`) to answer simulator listings —
  `simctl list devices [available]` prints deterministic lines including
  `iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown)` and
  `iPad (A16) (22222222-…) (Shutdown)`; a `STUB_SIM_BOOT_FAIL=1` env makes
  `simctl bootstatus` exit 1. Create
  `"$work/derived/Build/Products/Debug-iphonesimulator/SingleThread.app"` next
  to the existing product dirs (`:118-120`).
- **Flow assertions**:
  - Retarget `"every paired physical iPhone installs (Duo included)"` → assert
    the Duo-only discovery + sim line, e.g. want text
    `iPhone Duo (device): 1/1 launched` and absent `No reachable iPhone/iPad found.`
    (`DEVICES_JSON_IN="$FIXTURE" RUN_WATCH=0 RUN_MAC=0`).
  - Add `"default sim mode launches the iPhone simulator"`: want
    `iPhone/iPad (sim): 1/1 launched` and `==> Launching on the iPhone simulator`.
  - Add `"IOS_TARGET=device restores the all-physical sweep"`: env
    `IOS_TARGET=device`, want `iPhone/iPad (device): 3/3 launched`, absent
    `iPhone/iPad (sim)`.

### Verification
#### Automated
- [x] `bash -n scripts/run-devices.sh` passes
- [x] `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` passes
- [x] `bash scripts/test-run-devices.sh` passes (all filter + flow checks)
- [x] `make lint` passes (no source changes, sanity only)

#### Manual
- [ ] `IOS_TARGET=device DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_WATCH=0 RUN_MAC=0 ./scripts/run-devices.sh` emits the old all-physical discovery/filter messages and the `(device)` summary line (stub or real hardware not required for the discovery lines; use the test harness log).
- [ ] After the sim leg runs for real, `xcrun simctl list devices | grep 11111111` is irrelevant — instead confirm the booted worktree sim shows the app launched.

---

## Phase 2: iPad simulator leg + sim sad paths

Add the iPad to the sim target list, make the loop drive both, and cover the
simulator failure modes.

### Changes

#### 1. iPad target — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Extend the loop's target list to two entries (the loop already handles a list):

```bash
    sim_targets+=("iPad|$(resolve_ios_udid "$SIM_IPAD" "$DEFAULT_IPAD_SIM" 0)")
```

The iPad is resolved with `$3=0` so it never inherits `.simulator_id`.
(`SIM_TOTAL` becomes 2 automatically.)

No lock machinery is added: this repo has no lock file. Respect the
`.simulator_id` convention (iPhone only) and never call
`simctl shutdown all`/`booted` — boot exactly the resolved UDIDs and leave them
running, since the point of the script is a live app to poke at.

#### 2. Sad-path coverage — `scripts/test-run-devices.sh`

**File**: `scripts/test-run-devices.sh`
**Action**: modify

- Update the phase-1 sim flow expectation to `iPhone/iPad (sim): 2/2 launched`.
- Add `"simulator boot failure is a failed step"`: env `STUB_SIM_BOOT_FAIL=1`,
  expect exit 1 and `failed to boot`; assert the Duo/macOS legs still ran.
- Add `"missing sim product is a failed step"`: pass
  `DERIVED_DATA="$work/derived-nosim"` (a tree with `Debug`/`Debug-iphoneos`/
  `Debug-watchos` but no `Debug-iphonesimulator`) in the `run_flow` env args
  (later `env` assignments win), expect exit 1 and `Built app not found at`.
- Add `"unresolvable iPad sim is a failed step"`: `SIM_IPAD=No Such Device`,
  expect exit 1 and `No available simulator for iPad`.

### Verification
#### Automated
- [x] `bash -n scripts/run-devices.sh` and `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` pass
- [x] `bash scripts/test-run-devices.sh` passes, including the three new sad-path flows

#### Manual
- [ ] `./scripts/run-devices.sh` (or `r`) boots the worktree iPhone sim **and**
  the iPad sim, installs/launches `SingleThread` on both, and the summary prints
  `iPhone/iPad (sim): 2/2 launched`.
- [ ] With `SIM_IPAD=No Such Device ./scripts/run-devices.sh`, the run reports
  the iPad as a failed step but still launches the Duo (if present) and macOS.

---

## Phase 3: Watch leg on paired watch simulators

Replace the physical watch discovery + devicectl loop with a watch-sim
boot/build/install/launch leg; delete the now-dead watch filter and its
messaging.

### Changes

#### 1. Remove the physical watch path — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Delete:
- the second `<<'PY'` discovery heredoc and the whole `WATCH_DEVICES` /
  `WATCH_UNREACHABLE_COUNT` discovery block (the block guarded by `RUN_WATCH`),
- `WATCH_UNREACHABLE_LOG` from the env block and the `trap`, and
  `WATCH_UNREACHABLE_COUNT` from the `failures` tally,
- `WATCH_BUILD_NEEDED` and every reference to it (zero-device gate, banner
  wording),
- the per-watch loop and the generic unreachable-watch fallback build,
- `WATCH_LAUNCHED`/`WATCH_FAILED`'s physical semantics and
  `record_watch_launch_form` / `WATCH_LAUNCH_FORM` / `WATCH_LAUNCH_FORM_MIXED`
  (simctl launch has no flag variance).

Keep `RUN_WATCH` (and its `=0` skip semantics) and `WATCH_BUNDLE_ID`.

Add a `WATCH_SIM_APP_PATH`:
`$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchsimulator/SingleThreadWatch.app`.

#### 2. Watch simulator leg — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

```bash
# ── Apple Watch simulator leg ─────────────────────────────────────────────────
WATCH_TOTAL=0
WATCH_LAUNCHED=0
WATCH_FAILED=0
if [[ "$RUN_WATCH" -eq 1 ]]; then
    watch_udid="$(resolve_sim_udid "$SIM_WATCH")"
    if [[ -z "$watch_udid" ]]; then
        echo "  (no '$SIM_WATCH' simulator available — skipping the Apple Watch leg; set SIM_WATCH= to pin one)"
    else
        WATCH_TOTAL=1
        echo ""
        echo "==> Booting Apple Watch simulator ($SIM_WATCH, $watch_udid)…"
        if ! xcrun simctl bootstatus "$watch_udid" -b; then
            echo "❌ Apple Watch simulator failed to boot." >&2
            failures=$((failures + 1)); WATCH_FAILED=1
        else
            echo "==> Building SingleThreadWatch ($CONFIGURATION) for the simulator…"
            if ! xcodebuild -scheme SingleThreadWatch -destination "id=$watch_udid" \
              -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" build; then
                echo "❌ Watch build failed." >&2
                failures=$((failures + 1)); WATCH_FAILED=1
            elif [[ ! -d "$WATCH_SIM_APP_PATH" ]]; then
                echo "❌ Built watch app not found at $WATCH_SIM_APP_PATH" >&2
                failures=$((failures + 1)); WATCH_FAILED=1
            else
                echo "==> Installing on the Apple Watch simulator…"
                if ! xcrun simctl install "$watch_udid" "$WATCH_SIM_APP_PATH"; then
                    echo "❌ Watch install failed." >&2
                    failures=$((failures + 1)); WATCH_FAILED=1
                else
                    echo "==> Launching $WATCH_BUNDLE_ID on the Apple Watch simulator…"
                    if xcrun simctl launch "$watch_udid" "$WATCH_BUNDLE_ID"; then
                        WATCH_LAUNCHED=1
                    else
                        echo "❌ Watch launch failed." >&2
                        failures=$((failures + 1)); WATCH_FAILED=1
                    fi
                fi
            fi
        fi
    fi
fi
```

#### 3. Watch summary line — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

```bash
if [[ "$RUN_WATCH" -eq 0 ]]; then
    echo "  Apple Watch (sim): skipped (RUN_WATCH=0)"
elif [[ "$WATCH_TOTAL" -eq 0 ]]; then
    echo "  Apple Watch (sim): no simulator available (not a failure)"
else
    echo "  Apple Watch (sim): $WATCH_LAUNCHED launched, $WATCH_FAILED failed"
fi
```

Drop the launch-flag lines. Update the final success sentence's watch phrase to
the same `and $WATCH_LAUNCHED Apple Watch(es)` wording if any watch launched.

#### 4. Update the header — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Add `SIM_WATCH=` to the overrides list. Replace the "Apple Watch prerequisite"
paragraph (wrist / paired-iPhone / tunnel) with the simulator requirement: the
named watch simulator must exist; `simctl` installs and launches the watch app
on an unpaired watch sim (`scripts/appstore-screenshots.sh:29-31`).

#### 5. Rewrite watch coverage — `scripts/test-run-devices.sh`

**File**: `scripts/test-run-devices.sh`
**Action**: modify

- Delete `extract_filter 2`, `"$work/watch.py"`, and every watch-filter fixture
  assertion (`:88-95`); the "did a heredoc move" guard reduces to the single iOS
  filter (`extract_filter 1`).
- Delete the `watch()` fixture helper, `flow-unreachable-watch.json`,
  `flow-reachable-watch.json`, and the watch flows
  `"unreachable-watch-only still builds"` / `"reachable-watch-only succeeds"`.
- Extend the `xcrun` stub to resolve the watch name
  (`Apple Watch Series 11 (46mm) (33333333-…) (Shutdown)`) and stub
  `simctl install`/`launch`; create
  `"$work/derived/Build/Products/Debug-watchsimulator/SingleThreadWatch.app"`
  and drop the now-unused `Debug-watchos` dir if nothing reads it.
- Keep/extend `"no iOS and no watch keeps the iOS fail-fast"` and
  `"RUN_WATCH=0 emits no watch output"` against `flow-no-devices.json` with
  `IOS_TARGET=device` so the old fail-fast semantics stay asserted.
- Add `"watch simulator leg launches"`: default env, want
  `Apple Watch (sim): 1 launched, 0 failed` and
  `==> Launching app.alanvardy.SingleThread.watchkitapp on the Apple Watch simulator`.
- Add `"no watch simulator available is not a failure"`:
  `SIM_WATCH=No Such Watch`, expect a `no ... simulator available` notice, the
  watch leg skipped without a failure, and exit 0 when macOS/watch are the only
  legs (mirrors the old "no installable watch found (not a failure)" behavior).
- Add `"watch simulator boot failure is a failed step"`:
  `STUB_SIM_BOOT_FAIL=1` plus `IOS_TARGET=device`/no iOS devices, expect exit 1
  and `Apple Watch simulator failed to boot`.

### Verification
#### Automated
- [x] `bash -n scripts/run-devices.sh` and
  `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` pass
- [x] `bash scripts/test-run-devices.sh` passes with the rewritten watch flows
- [x] No `devicectl` watch references remain:
  `rg -n 'WATCH_DEVICES|WATCH_UNREACHABLE|watchkitapp.*devicectl|4016' scripts/run-devices.sh` returns nothing
  (all watch-path references are gone; the `4016` alternative still matches two
  pre-existing *iOS*-only comments about the physical-phone unreachable check —
  altering those would change iOS behavior and is out of Phase 3 scope)

#### Manual
- [ ] `./scripts/run-devices.sh` (or `r`) boots an Apple Watch simulator,
  installs and launches `SingleThreadWatch`, and prints
  `Apple Watch (sim): 1 launched, 0 failed`.
- [ ] `RUN_WATCH=0 ./scripts/run-devices.sh` prints `Apple Watch (sim): skipped (RUN_WATCH=0)` and does no watch build.
- [ ] With `IOS_TARGET=device` and a Duo + watches present, only the Duo is
  touched on hardware and the watch still runs on the simulator.

---

## Post-plan gate (parent, after all phases commit)

- [ ] `./scripts/test.sh` via the `run-gate` skill (build + lint + Periphery +
  unit + UI) — the full CI-identical gate runs **once** after the phases commit.
- [ ] `make format` + `make lint` before the final commit.
- [x] Confirm no `IOS_TARGET`/fixture seam needs wiring into `scripts/test.sh` or
  the `Makefile`: `scripts/test-run-devices.sh` is currently standalone and not
  referenced by the gate, so no wiring is expected — verify with
  `rg -n 'test-run-devices' Makefile scripts/test.sh` and add a gate step only
  if the repo convention requires it.
  (verified: `rg -n 'test-run-devices' Makefile scripts/test.sh` returns nothing —
  the harness stays standalone, no gate wiring needed)
