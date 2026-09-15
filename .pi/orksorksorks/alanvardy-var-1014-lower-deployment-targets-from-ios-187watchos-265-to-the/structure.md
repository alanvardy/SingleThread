# Structure Outline (re-scoped after rebase)

> **Re-scoped 2026-09-15.** `origin/main` (`53124c3e`, ticket VAR-1015) already
> landed the floor change this design targeted: pbxproj 8× iOS **17.0** / 6×
> watchOS **11.0** / 6× macOS 26.5, `Package.swift` `.iOS("17.0")`,
> `.watchOS("11.0")`, `.macOS("26.5")`, and a three-value gate
> (`DEPLOYMENT_TARGET_IOS|WATCHOS|MACOSX`). The `AppDelegateTests.swift:13`
> note is updated. **No phase below changes a floor value** — the remaining
> delta is *proof and runtime verification*, which the landed commit has none
> of (no probe evidence, no old-runtime run, no artifacts).

## Approach

The floors are landed but unproven: their correctness rests on SDK annotation
(EventKit `ios(17.0)/watchos(10.0)`) and an *unannotated* `@Observable` floor.
Each slice therefore cuts the same stack end to end — **temporarily set floors →
gate check → real build/run on the target runtime → captured evidence → restore
the landed values** — one platform per slice, each leaving the tree green at the
landed floors. Only one production file may change, and only for hardening:
`scripts/test.sh`'s collapsed literal-count guard.

## Phase 1: Walking skeleton — prove the iOS 17.0 floor with the red-probe ladder, on a real iOS 17.x simulator

**Outcome**: the ticket's central claim is *evidence* rather than annotation:
with iOS floors temporarily set to 16.0 the build fails with availability errors
naming the pinning API, and with the landed 17.0 the app builds, installs and
runs on an actual iOS 17.x runtime (not 26). If the 16.0 probe unexpectedly
compiles, the true floor is lower than 17.0 — a finding to report, not to hide.

**Files**: `SingleThread.xcodeproj/project.pbxproj` (8 `IPHONEOS_DEPLOYMENT_TARGET`
literals, Debug+Release: 765/815, 843/872, 900/924, 1009/1040) and
`SingleThreadCore/Package.swift:7` — **temporarily edited for the probe, then
restored via `git checkout --`**; probe logs written to the artifact directory.
`scripts/test.sh` is *not* modified in this phase.

**Key changes**: none permanent. Probe procedure only:
- set `IPHONEOS_DEPLOYMENT_TARGET = 16.0` ×8 and `.iOS("16.0")`;
- run with `DEPLOYMENT_TARGET_IOS=16.0 SIM='platform=iOS Simulator,id=<iOS 17.x udid>' bash scripts/test.sh --unit-only`;
- capture the raw compiler output, then `git checkout -- …pbxproj …Package.swift`.

**Prerequisite (risk front-loaded)**: download the lowest available iOS 17.x
runtime, create/boot a pre-iPhone-17 device type (iPhone 14/15 or SE 3rd gen),
record the UDID. If no 17.x runtime is installable, fall back to the strongest
available and **name the gap** in the PR. Do not touch `.simulator_id`.

**Contract** (consumed by Phase 2; nothing else): probe logs are named by the
floor tuple they were produced at (`probe-ios16.0-*.log`), and the landed
17.0/11.0/26.5 values are restored and re-verified green after every probe. No
Phase 2 step may rely on a temporarily modified tree.

**Tests**:
- red (drift): `DEPLOYMENT_TARGET_IOS=16.0 bash scripts/test.sh --unit-only`
  exits 1 at the gate before any build — proves the gate still bites.
- red (floor probe): the 16.0 build above; expect availability errors naming
  `@Observable` and/or `EKAuthorizationStatus.fullAccess` /
  `requestFullAccessToReminders`.
- green: `SIM='platform=iOS Simulator,id=<iOS 17.x udid>' make build`, then
  `SIM=… make ui-test` and `SIM=… scripts/test-one.sh SingleThreadTests/<suite>`
  for the suites this change touches.

**Verify**: probe log captured with a named pinning API; landed floors restored
and gate green at `17.0 / 11.0 / 26.5`; iOS 17.x build + targeted suites green.
Manual: install and smoke-launch on the iOS 17.x sim (EventKit prompt → list).

---

## Phase 2: watchOS 11.0 floor proven + runtime-verified on a real watchOS 11.x runtime

**Outcome**: the watch app builds, installs and runs on a watchOS 11.x runtime,
and the watchOS floor is proven: 9.0 fails with availability errors, 10.0 is a
recorded green-but-rejected data point (Series 6+ reach is unchanged either way).

**Files**: `SingleThread.xcodeproj/project.pbxproj` (6 `WATCHOS_DEPLOYMENT_TARGET`
literals: 965/993, 1077/1099, 1123/1147) and `SingleThreadCore/Package.swift:8` —
temporarily edited for the probes, then restored; probe logs in the artifact
directory. `scripts/test.sh` unmodified.

**Key changes**: none permanent. Probe procedure as Phase 1, at watchOS 9.0 and
10.0, with `WATCH_TEST_SIM=` pinned to the older-runtime watch device.

**Contract**: unchanged from Phase 1 — consumes only the probe-log convention
and the landed floor tuple.

**Tests**:
- red (floor probe): watchOS 9.0 → expect availability failure naming
  `@Observable`/EventKit; restore.
- red (drift): `DEPLOYMENT_TARGET_WATCHOS=10.0 bash scripts/test.sh --unit-only`
  → exit 1 at the gate.
- green: `WATCH_SIM=… make watch-build`, `WATCH_TEST_SIM=… make watch-test`, and
  `make watch-ui-test` if pairing the older watch runtime works. The
  `lib_TestingInterop.dylib` workaround (`scripts/test.sh:271-288`) is
  26.5-specific — determine whether it is needed or harmful on 11.x and record
  which.

**Verify**: watchOS 9.0 red log + 10.0 green log captured; watch build and watch
suites green on the 11.x runtime; landed floors restored, gate green. Manual:
install and smoke-launch the watch app on the watchOS 11.x sim.

---

## Phase 3: Hardening — gate count guard, evidence record, full gate

**Outcome**: the gate detects *per-platform* literal drift (not just value
drift), the paper trail states the verified floors and corrects the landed
commit's macOS claim, and the full CI-identical gate is green.

**Files**: `scripts/test.sh` (`verify_deployment_target()`, `:143-225`); PR body /
artifact record; no other production file.

**Key changes**:
- `verify_deployment_target()` — split the collapsed `other_target` counter into
  `watchos_target` / `macos_target` and guard each against its own count
  (`EXPECTED_IOS_LITERALS=8`, `EXPECTED_WATCHOS_LITERALS=6`,
  `EXPECTED_MACOS_LITERALS=6`, `EXPECTED_PACKAGE_LITERALS=3`, plus per-platform
  package counts). Today a watchOS literal swapped for a macOS one still totals
  20 and passes — this closes that hole. Values and defaults stay as landed.
- Record: correct `53124c3e`'s claim that the Mac listing "derives from
  `IPHONEOS_DEPLOYMENT_TARGET`" — **verified false** here: the app target is a
  native macOS build (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`,
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, `MACOSX_DEPLOYMENT_TARGET = 26.5`, no
  Catalyst), so the Mac App Store listing still requires macOS 26.5.

**Contract**: floors and gate defaults frozen — Phase 3 adds detection, never a
new floor value.

**Tests**: drift probes for the new guards (remove/swap one literal → exit 1;
correct tree → exit 0); `make mac-test` confirms the unchanged macOS 26.5 floor.
Clean `DerivedData/` (pbxproj/index staleness) then the full `./scripts/test.sh`
**once** via the `run-gate` skill (async gate subagent, managed worktree,
multi-hour timeout) — never an ad-hoc `nohup`. CI is authoritative.

**Verify**: full gate green; CI green; PR body states the observed probe floors,
the verified tuple, the macOS-listing correction, and any *named* verification
gap (e.g. no installable iOS 17.x / watchOS 11.x runtime).

---

## Testing Checkpoints

After Phase 1: iOS 16.0 probe red log captured, landed floors restored and gate
green, iOS 17.x build + targeted suites + smoke launch green. After Phase 2:
watchOS 9.0 red / 10.0 green logs captured, watch build + suites green on the
11.x runtime, landed floors restored and gate green. After Phase 3: new
per-platform count guards red/green-proven, `./scripts/test.sh` via `run-gate`
green, CI green. Never advance on a red checkpoint, and never leave the tree
carrying a probe value.

## Deliberately not in this structure

- Lowering the **macOS** floor (still 26.5) or verifying it — CI is `macos-26`
  only, so a lower macOS floor is unverifiable here.
- Runtime `#available`/`@available` branches, Liquid Glass work, CI runner or
  matrix changes, new test targets, or a `docs/` OS-requirement page.
- Re-editing floor values: they are landed on `main`; if a probe disproves them,
  that is a design-level finding to raise before any further edit.