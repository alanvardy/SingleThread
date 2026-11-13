# Implementation Plan

## Overview

Add an `IOS_TARGET=duo` mode to `scripts/run-devices.sh` that deploys the build
to the physical iPhone Duo **only** — skipping the regular iPhone/iPad
simulator legs, the Apple Watch leg, and the macOS leg — report that leg
honestly in the summary, and add `rd.fish` to the dotfiles repo so
`rd` is a one-command Duo-only sibling of `r`.

**Decisions locked (from `medium.md` + recon):**

1. **Flag shape = `IOS_TARGET=duo`** (not a new boolean, not a change to
   `device` mode). This mirrors the VAR-1175 `IOS_TARGET=sim|device`
   convention and keeps `device` as the legacy all-physical sweep.
2. **`duo` implies watch + macOS off by default.** The RUN_WATCH/RUN_MAC
   defaults are applied *after* a duo check with the unset-preserving
   `${VAR:-…}` form, so an explicit `RUN_WATCH=1` / `RUN_MAC=1` still opts
   back in.
3. **No Python filter change.** Duo is `!= "device"`, so it already falls into
   the existing `mode != "device"` branch that keeps only the physical Duo and
   honours `DUO_DEVICE_ID`. The filter gets a *test* proving this, not an edit.
4. **Two repos, two phases / two commits.** Phase 1 edits
   `scripts/run-devices.sh` + `scripts/test-run-devices.sh` on the ticket
   branch. Phase 2 creates `rd.fish` in `~/dev/dotfiles` (a different repo,
   which per its `AGENTS.md` allows direct commits to `main`).
5. **No gate wiring.** `scripts/test-run-devices.sh` is standalone and is not
   referenced by `Makefile` / `scripts/test.sh` (verified this session:
   `rg -n 'test-run-devices' Makefile scripts/test.sh` returns nothing), so no
   new gate entry is required.

## Verified ground truth (checked this session)

- `scripts/run-devices.sh:70-76` — env parsing block (`RUN_WATCH`, `RUN_MAC`,
  `IOS_TARGET`, `SIM_*`, `DUO_DEVICE_ID`).
- `scripts/run-devices.sh:170-174` — discovery banner: sim banner if
  `IOS_TARGET == "sim"`, else the all-physical banner.
- `scripts/run-devices.sh:211` — sole `<<'PY'` heredoc; `:237-244` is the
  `if mode != "device":` Duo filter branch. **No edit needed.**
- `scripts/run-devices.sh:271-284` — zero-device gate, `!= "sim"` (duo already
  fail-fasts correctly once `RUN_MAC` defaults to 0; no edit).
- `scripts/run-devices.sh:287` — "no physical iPhone Duo found" notice is
  `== "sim"` only (duo correctly skips; no edit).
- `scripts/run-devices.sh:319` — sim leg guard `== "sim"` (duo skips; no edit).
- `scripts/run-devices.sh:432` / `:479` — watch leg `RUN_WATCH -eq 1`, macOS
  leg `RUN_MAC -eq 1` (duo defaults flip these off).
- `scripts/run-devices.sh:510-515` — summary label block (needs a duo branch).
- `scripts/run-devices.sh:531-533` — final toast.
- `scripts/test-run-devices.sh:53-58` `extract_filter`; `:64-127` filter
  assertions; `:191` `flow-no-devices.json`; `:193-208` `run_flow`; `:245-250`
  existing sim/device flow cases.
- Fixture `scripts/fixtures/devicectl-devices.json` — physical Duo is
  `CCCCCCCC-0000-0000-0000-000000000009` (`Fixture Duo Renamed`,
  productType `iPhone19,4`); no fixture change is needed.
- `~/dev/dotfiles/fish/functions/r.fish`:
  `function r --wraps=./scripts/run-devices.sh --description '…'; ./scripts/run-devices.sh $argv; end`.
- `~/dev/dotfiles/AGENTS.md` — direct pushes to `main` are allowed.

---

## Phase 1: `IOS_TARGET=duo` end-to-end in `run-devices.sh` + offline coverage

The walking skeleton: setting `IOS_TARGET=duo` discovers only the Duo, runs
only the physical device leg, skips sim/watch/macOS, and prints an honest
summary — proven offline by `scripts/test-run-devices.sh`.

### Changes

#### 1. Header docstring + env parsing — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Update the intro line (line 8) and the override block (lines 15-16) to document
the new value:

```bash
# iPhone Duo (via devicectl), install + launch the watch app on an Apple Watch
# simulator, and (by default) also build + launch it on the host Mac. Set
# IOS_TARGET=device to build + launch on every paired physical iPhone/iPad
# instead (the Duo is always deployed physically); IOS_TARGET=duo builds and
# launches on the physical Duo only.
```

```bash
#   IOS_TARGET=sim         # sim (default) → the regular iPhone/iPad legs run on
#                          # simulators; device → the old all-physical sweep;
#                          # duo → the physical iPhone Duo only (sim, watch and
#                          # macOS legs skipped unless RUN_WATCH/RUN_MAC opt in)
```

Replace the env-parsing block (lines 70-76) so `IOS_TARGET` is parsed first and
duo flips the leg defaults:

```bash
IOS_TARGET="${IOS_TARGET:-sim}"
# Duo-only mode: the physical Duo is the only leg. Applied before the
# RUN_WATCH/RUN_MAC defaults so an explicit RUN_WATCH=1 / RUN_MAC=1 opts back in.
if [[ "$IOS_TARGET" == "duo" ]]; then
    RUN_WATCH="${RUN_WATCH:-0}"
    RUN_MAC="${RUN_MAC:-0}"
fi
RUN_WATCH="${RUN_WATCH:-1}"
RUN_MAC="${RUN_MAC:-1}"
SIM_IPHONE="${SIM_IPHONE:-}"   # explicit UDID or device name; empty = worktree sim, else iPhone 17
SIM_IPAD="${SIM_IPAD:-}"       # explicit UDID or device name; empty = iPad (A16)
SIM_WATCH="${SIM_WATCH:-}"     # explicit UDID or device name; empty = Apple Watch Series 11 (46mm)
DUO_DEVICE_ID="${DUO_DEVICE_ID:-}"
```

#### 2. Discovery banner — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Duo uses the Duo banner (it discovers the same target as sim):

```bash
if [[ "$IOS_TARGET" == "sim" || "$IOS_TARGET" == "duo" ]]; then
    echo "==> Discovering the paired iPhone Duo…"
else
    echo "==> Discovering paired iPhone/iPad devices…"
fi
```

#### 3. Summary + final toast — `scripts/run-devices.sh`

**File**: `scripts/run-devices.sh`
**Action**: modify

Add the duo branch so the leg is never mislabelled as `iPhone/iPad (device)`
and no `0/0` sim line is printed (line 510):

```bash
if [[ "$IOS_TARGET" == "sim" ]]; then
    echo "  iPhone/iPad (sim): $SIM_LAUNCHED/$SIM_TOTAL launched"
    echo "  iPhone Duo (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
elif [[ "$IOS_TARGET" == "duo" ]]; then
    echo "  iPhone Duo (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
else
    echo "  iPhone/iPad (device): $IOS_LAUNCHED/${#DEVICES[@]} launched, $UNREACHABLE_COUNT unreachable"
fi
```

Drop the misleading `and 0 simulator(s)` from the duo toast (line 531):

```bash
if [[ "$IOS_TARGET" == "duo" ]]; then
    summary="Installed and launched on ${#DEVICES[@]} device(s)"
else
    summary="Installed and launched on ${#DEVICES[@]} device(s) and $SIM_LAUNCHED simulator(s)"
fi
[[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
[[ "$WATCH_LAUNCHED" -gt 0 ]] && summary="$summary and $WATCH_LAUNCHED Apple Watch(es)"
```

The watch/macOS summary lines (`Apple Watch (sim): skipped (RUN_WATCH=0)`,
`macOS: skipped (RUN_MAC=0)`) stay — they are the honest duo report.

#### 4. Offline coverage — `scripts/test-run-devices.sh`

**File**: `scripts/test-run-devices.sh`
**Action**: modify

Add a filter-level duo assertion after the sim-mode filter assertions
(around line 107), proving the new value reaches the shared `!= "device"`
branch:

```bash
# IOS_TARGET=duo reuses the sim filter semantics: only the physical Duo
# qualifies, and DUO_DEVICE_ID still wins.
python3 "$work/ios.py" "$FIXTURE" "$work/ios-duomode-unreachable.log" duo \
    > "$work/ios-duomode-out" 2>/dev/null
check "duo mode emits only the physical Duo" \
    "1" "$(grep -c '|Fixture Duo Renamed$' "$work/ios-duomode-out" || true)"
check "duo mode excludes the regular physical iPhone" \
    "0" "$(grep -c '|Fixture iPhone$' "$work/ios-duomode-out" || true)"
```

Add the happy + sad flow cases after the existing
`"IOS_TARGET=device restores the all-physical sweep"` case (line 248):

```bash
run_flow "IOS_TARGET=duo installs only the iPhone Duo" 0 \
    "iPhone Duo (device): 1/1 launched" "iPhone/iPad" \
    DEVICES_JSON_IN="$FIXTURE" IOS_TARGET=duo
check "duo mode boots no simulator" "0" \
    "$(grep -c '==> Booting the' "$work/flow-IOS_TARGET=duo installs only the iPhone Duo.log" || true)"
check "duo mode builds no watch app" "0" \
    "$(grep -c '==> Building SingleThreadWatch' "$work/flow-IOS_TARGET=duo installs only the iPhone Duo.log" || true)"
check "duo mode builds no macOS app" "0" \
    "$(grep -c 'for macOS' "$work/flow-IOS_TARGET=duo installs only the iPhone Duo.log" || true)"
check "duo mode reports the skipped watch leg" "1" \
    "$(grep -c 'Apple Watch (sim): skipped' "$work/flow-IOS_TARGET=duo installs only the iPhone Duo.log" || true)"
check "duo mode reports the skipped macOS leg" "1" \
    "$(grep -c 'macOS: skipped' "$work/flow-IOS_TARGET=duo installs only the iPhone Duo.log" || true)"
run_flow "IOS_TARGET=duo with no Duo fails fast" 1 \
    "No reachable iPhone/iPad found." "==> Booting the" \
    DEVICES_JSON_IN="$work/flow-no-devices.json" IOS_TARGET=duo
```

Notes for the implementer: `run_flow` env assignments follow the four
positional args (no `RUN_WATCH=0`/`RUN_MAC=0` — duo must supply those); the flow
log path is `$work/flow-$label.log`; the existing sim case asserts the Duo-only
filter still emits the Duo, so no fixture change is needed.

### Verification
#### Automated
- [x] `bash -n scripts/run-devices.sh` passes
- [x] `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` passes
- [x] `bash scripts/test-run-devices.sh` passes, including the two new duo flow cases and the duo filter assertions
- [x] `rg -n 'test-run-devices' Makefile scripts/test.sh` still returns nothing (no gate wiring needed)

#### Manual
- [ ] With the physical Duo paired and reachable:
  `IOS_TARGET=duo ./scripts/run-devices.sh` builds/installs/launches only the
  Duo, prints `iPhone Duo (device): 1/1 launched, 0 unreachable`, and shows no
  simulator boot, no watch build, no macOS build.
- [ ] With the Duo unpaired/unreachable, `IOS_TARGET=duo ./scripts/run-devices.sh`
  exits non-zero with `No reachable iPhone/iPad found.` (or the unreachable
  message) without touching sim/watch/macOS.
- [ ] `IOS_TARGET=duo RUN_WATCH=1 RUN_MAC=1 ./scripts/run-devices.sh` still
  allows the watch/macOS legs (the opt-back-in path).

---

## Phase 2: `rd.fish` Duo-only wrapper (dotfiles repo)

A separate repo and commit: `rd` wraps `run-devices.sh` with
`IOS_TARGET=duo`, mirroring `r.fish`.

### Changes

#### 1. New fish function — `~/dev/dotfiles/fish/functions/rd.fish`

**File**: `/Users/vardy/dev/dotfiles/fish/functions/rd.fish`
**Action**: create

```fish
function rd --wraps=./scripts/run-devices.sh --description 'alias rd=IOS_TARGET=duo ./scripts/run-devices.sh'
    env IOS_TARGET=duo ./scripts/run-devices.sh $argv
end
```

`env` scopes `IOS_TARGET` to the child process without leaking it into the
interactive session; `$argv` passes any extra args through (positional args do
not overwrite the env var). Do not add a matching `r`-style entry elsewhere.

#### 2. Commit on dotfiles `main`

This repo's `AGENTS.md` explicitly allows direct commits/pushes to `main`.
From `/Users/vardy/dev/dotfiles`:

```bash
git add fish/functions/rd.fish
git commit -m "feat(fish): add rd for the Duo-only run-devices mode"
git push
```

### Verification
#### Automated
- [x] `fish --no-execute /Users/vardy/dev/dotfiles/fish/functions/rd.fish` reports no syntax error
- [x] No dotfiles test targets exist (`ls /Users/vardy/dev/dotfiles` shows no `scripts/test.sh`); the wrapper holds no logic beyond one env var, so the Phase 1 flow tests are the behaviour coverage

#### Manual
- [ ] From a SingleThread worktree, `rd` builds/installs/launches only the Duo
  and prints the duo summary (same result as `IOS_TARGET=duo ./scripts/run-devices.sh`).
- [ ] `functions rd` shows the function loaded from
  `~/.config/fish/functions/rd.fish`.

---

## Post-plan gate (parent, after both phases commit)

- [ ] Run the full CI-identical gate via the `run-gate` skill
  (`./scripts/test.sh`: build + lint + Periphery + unit + UI) once after the
  phases commit. The change is shell-only, so this is a regression check.
- [ ] `./scripts/test-run-devices.sh` is not part of `scripts/test.sh`; run it
  directly in the gate worktree as well.
- [ ] Confirm the ticket branch has no `DELETEME` before merge
  (`git rm DELETEME`) and that the dotfiles commit is on `main` (not the ticket
  branch).
