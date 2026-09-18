# Structure Outline

## Approach

Add a third platform leg to `scripts/run-devices.sh` — discovery (physical
watch filter) → build (`generic/platform=watchOS`, signed) → install → launch
→ summary — in the existing inline style, no refactor. Because no watch leg has
ever been built or installed anywhere in the repo, the slices are ordered
**hardware-independent build first** (today's watch tunnel is `disconnected`),
then the hardware-gated install/launch, then hardening. The one genuinely
horizontal piece (a second discovery filter sharing the same `list devices -j`
call) is folded into slice 1 rather than run as its own layer.

## Phase 1: Walking skeleton — discover, diagnose, and build the watch app

A `./scripts/run-devices.sh` run now (a) lists the paired **physical** Apple
Watch and excludes the four watch sims, (b) names a tunnel-down watch as
unreachable with the wrist/iPhone hint, and (c) produces a signed
`SingleThreadWatch.app` for a real device at the `Debug-watchos` product path.
Green tests prove the filter contract and the build/product-path contract;
this is the thinnest valuable path that is verifiable **without** the watch
being reachable today.

**Files**: `scripts/run-devices.sh`
**Key changes**:
- Defaults block (`:25-35`) — new/touched vars:
  - `RUN_WATCH="${RUN_WATCH:-1}"`, `WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${BUNDLE_ID}.watchkitapp}"`
  - `WATCH_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos/SingleThreadWatch.app"`
  - `DEVICES_JSON_IN` (optional seam: a saved `list devices -j` fixture; empty ⇒ live call, unchanged)
- Header comment (`:9-23`) — document `RUN_WATCH`, `WATCH_BUNDLE_ID`, the
  watch prerequisite (wrist + paired iPhone unlocked on this network) and
  `DEVICES_JSON_IN`.
- Second inline python filter after the iOS one (`:47-88` shape), reading the
  same `$DEVICES_JSON` and emitting `identifier|name` to stdout → `WATCH_DEVICES`:
  keep `platform=="watchOS"` **and** `deviceType=="appleWatch"` **and**
  `reality=="physical"` **and** `developerModeStatus=="enabled"`;
  reachable ⇔ `properties.connection.state == "connected" &&
  connectionProperties.pairingState == "paired"`; unreachable names → `$UNREACHABLE_LOG`.
- Build leg (between the iOS and macOS legs): when `RUN_WATCH=1` **and** a
  physical watch was discovered (reachability irrelevant — a build needs no
  watch), run
  `xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS' -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" -allowProvisioningUpdates build`;
  nonzero ⇒ named message ("no provisioning profile for `…watchkitapp` — sign in
  to Xcode with team 6NWX2DHB9Q and retry"); missing `$WATCH_APP_PATH` ⇒ loud
  failure printing the path (never a silent no-op).
- `failures` seeded with the unreachable-watch count (mirrors `:109-112`).

**Contract**: `WATCH_DEVICES` holds `identifier|name` per *reachable physical*
watch (`identifier` = CoreDevice pairing UUID, never udid/name);
`$WATCH_APP_PATH` exists after a successful build for a signed `.app`;
watch failures are expressed only through `failures`. Later slices read these,
not the filter's internals.

**Tests**: no shell test target exists (design's exclusion) — verification is
`bash -n scripts/run-devices.sh`, then manual runs on this Mac:
1. `RUN_WATCH=0 ./scripts/run-devices.sh` → zero watch output, exit unchanged from today.
2. `RUN_WATCH=1 RUN_MAC=0 ./scripts/run-devices.sh` → "Apple Watch Ultra" named
   unreachable with the wrist/iPhone hint, **no** `Probe Watch S9` / `LocalTest
   Watch` / `CI Watch S11-local` line, exit 1, and the watch build still ran.
3. Filter golden check against a captured fixture:
   `xcrun devicectl list devices -j /tmp/var1044-devices.json` then
   `DEVICES_JSON_IN=/tmp/var1044-devices.json …` → exactly one watch line.

**Verify**: the three runs above, plus
`ls -d DerivedData/Build/Products/Debug-watchos/SingleThreadWatch.app` and
`codesign -dv --verbose=2 <path>` (team `6NWX2DHB9Q`), and confirming the
iPhone/iPad product from the same `DerivedData` is still intact.

---

## Phase 2: Install + launch on the wrist (hardware-gated)

With the watch reachable, the run installs `$WATCH_APP_PATH` onto it and
launches `$WATCH_BUNDLE_ID`, reporting which launch flag form worked; a
reachable watch that fails install/launch counts as a failed step.

**Files**: `scripts/run-devices.sh`
**Key changes**:
- Per-watch loop over `WATCH_DEVICES`, guarded by `RUN_WATCH=1` and
  `[[ -d "$WATCH_APP_PATH" ]]`:
  - `xcrun devicectl device install app --device "$watch_id" "$WATCH_APP_PATH"`
  - `xcrun devicectl device process launch --terminate-existing --activate --device "$watch_id" "$WATCH_BUNDLE_ID"`,
    retried once as `… --terminate-existing --device "$watch_id" "$WATCH_BUNDLE_ID"`;
    `WATCH_LAUNCH_FORM` records the form that exited 0, both failing ⇒ failure.
- Unreachable watches are never install targets (they are already counted in
  Phase 1); the message must not re-attempt and must not surface a raw 4016.

**Contract**: `WATCH_LAUNCH_FORM` (`--terminate-existing --activate` |
`--terminate-existing` | `none`) is the observable Phase-3 summary input;
install/launch failures only ever increment `failures`.

**Tests**: manual hardware run (watch on the wrist, paired iPhone nearby and
unlocked): ✅ summary + the launch-form line; and the sad path `RUN_WATCH=1`
with the watch off the wrist → named unreachable, exit 1, zero install attempts.

**Verify**: the two runs above, and `xcrun devicectl device info details
--device <watch-identifier>` showing the new build. **UNVALIDATED** — the
direct-to-watch install of a `SKIP_INSTALL=YES` companion-embedded bundle has
never succeeded here; this run is a merge gate, and Design Decision 1 must be
revisited if it fails.

---

## Phase 3: Hardening — summary, wording, and a hardware-free filter check

The summary enumerates per-platform outcomes (n iOS devices, watch
launched/skipped/unreachable, macOS), every failure path names a cause and a
fix, `RUN_WATCH=0` is a clean skip, and the watch filter can be re-verified
from a saved inventory with no hardware attached.

**Files**: `scripts/run-devices.sh`; optionally `scripts/test-run-devices.sh`
+ `.pi/`-free fixture `scripts/fixtures/devicectl-devices.json` (decision D3).
**Key changes**:
- Summary block (`:174-182`): one line per platform; watch line distinguishes
  `0 watches found (not a failure)` → `unreachable` → `failed`.
- Exact hint strings for: tunnel down (`state != connected`), product missing,
  signing/profile failure, launch-flag fallback taken, devicectl exit 4016.
- `DEVICES_JSON_IN` documented as a dev seam; optional assertion script
  (`bash -n`, `shellcheck`, fixture → expected `WATCH_DEVICES`/unreachable sets).

**Contract**: stable summary line format; the fixture seam's input format is
`devicectl list devices -j` output verbatim.

**Tests**: the full 2×2 matrix `RUN_WATCH×RUN_MAC` with the watch reachable and
disconnected, plus the fixture assertions; `shellcheck scripts/run-devices.sh`.
**Verify**: `shellcheck` clean + the matrix, then the single full
`./scripts/test.sh` gate via the `run-gate` skill (which today never exercises
this script — expect no new failures).

## Testing Checkpoints

- After Phase 1: `bash -n` clean; runs (1)(2)(3) behave as specified; `Debug-watchos/SingleThreadWatch.app` exists and is signed; iOS/macOS legs unchanged.
- After Phase 2: a hardware run with the watch reachable ends ✅ and prints the working launch form; disconnected-watch run exits 1 with no install attempt. **Do not proceed without the ✅** — it is the ticket's UNVALIDATED gate.
- After Phase 3: shellcheck + the RUN_WATCH/RUN_MAC matrix green, `RUN_WATCH=0` leaves prior behaviour byte-for-byte; then one full `./scripts/test.sh` gate.

## Decisions needed before plan

- **D1 (exit semantics for an unreachable watch)** — ⭐ **Continue, count as a
  failed step, exit non-zero at the end** (matches how the iOS leg already
  treats *some* unreachable devices at `:109-112`, and keeps iPhone/iPad/mac
  useful while the watch is on the charger). Alternative: abort everything
  before the iOS build, mirroring the zero-reachable-device path at `:96-98`.
- **D2 (build gating)** — ⭐ **Build whenever `RUN_WATCH=1` and a physical watch
  was discovered, regardless of tunnel state**, so the `Debug-watchos` path and
  signing are exercisable today. Alternative: gate the build on reachability,
  which would leave the build unverifiable until the watch tunnels up.
- **D3 (testability)** — ⭐ **Add the `DEVICES_JSON_IN` fixture seam** (a saved
  inventory + a few shell assertions) so the filter has a red-first check
  without hardware and without a unit-test target. Alternative: design's
  literal "manual hardware run only" — accepted, but then no filter regression
  can be caught except by eye.
