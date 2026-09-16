# Verification record — VAR-1014 / PR #201

Phase 3 evidence record for the deployment-floor ticket: iOS 17.0 / watchOS 11.0 /
macOS 26.5 (landed by `53124c3e`, **no floor value changed by this ticket**).
The only production-file diff across all three phases is `scripts/test.sh`.

## 1. Verified floor tuple and gate state

- **Floors**: `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (×8 in `project.pbxproj`),
  `WATCHOS_DEPLOYMENT_TARGET = 11.0` (×6), `MACOSX_DEPLOYMENT_TARGET = 26.5` (×6);
  `Package.swift` `.iOS("17.0")` / `.watchOS("11.0")` / `.macOS("26.5")` (×1 each).
  Confirmed by `rg -c` (8/6/6 and 1/1/1) and by the clean gate log
  (`probe-gate-clean.log`).
- **Gate**: `verify_deployment_target()` in `scripts/test.sh` now uses
  per-platform literal counters (Phase 3 hardening). Clean-tree verdict:

  ```
  ✓ All deployment-target + package-floor literals match
    (iOS 17.0 × 8, watchOS 11.0 × 6, macOS 26.5 × 6; package .iOS 1, .watchOS 1, .macOS 1)
  ```

## 2. Observed probe floors (compile-time, red → the exact pinning APIs)

| Floor | Verdict | Exact API named by the compiler | Log |
|---|---|---|---|
| iOS 16.0 | **red** | `'Observable()' is only available in iOS 17.0 or newer` (`CompletionGlow.swift:12:2`); macro `'ObservationTracked()'` / `'ObservationIgnored()'` only available in iOS 17.0 or newer; `protocol 'EventKitStoring' requires 'requestFullAccessToReminders()' to be available in iOS 16.0 and newer` (`EventKitStoring.swift:45:1`) | `probe-ios16.0-build.log` |
| iOS 16.0 (gate drift) | **red** | `✗ IPHONEOS = 17.0 (expected 16.0)` + `❌ Deployment-target drift`, no build | `probe-ios16.0-drift-gate.log` |
| SPM consumer < package floor | **red** | `error: compiling for iOS 16.0, but module 'SingleThreadCore' has a minimum deployment target of iOS 17.0` (`NextThingWidget.swift:3:8` — SPM enforces the dependency floor at iOS 17.0) | `probe-ios16.0-package-floor.log` |
| watchOS 9.0 | **red** | `'Observable()' is only available in watchOS 10.0 or newer`; `'fullAccess' is only available in watchOS 10.0 or newer` (`InMemoryEventStore.swift:38:10` — EventKit `EKAuthorizationStatus.fullAccess`) | `probe-watchos9.0-build.log` |
| watchOS 10.0 | **green-but-rejected** | BUILD SUCCEEDED at deployment-target 10.0 (EventKit floors at `watchos(10.0)`, Observation at watchOS 10) — rejected as ship floor: buys only Apple Watch Series 4/5/SE (1st gen) reach, not a product goal (design decision 2) | `probe-watchos10.0-build.log` |

## 3. Gate hardening (Phase 3) — probes 3a–3d, red/green

All probes ran against the local worktree sim; each red probe was restored with
`git checkout --` and `git status --short` verified clean of floor files before
the next.

| Probe | Mutation | Verdict | Key line(s) in log |
|---|---|---|---|
| 3a `probe-gate-watchos-swap.log` | pbxproj line 965: `WATCHOS_DEPLOYMENT_TARGET = 11.0;` → `MACOSX_DEPLOYMENT_TARGET = 26.5;` (total still 20) | **red** (exit 1, no `==> Unit tests`) | `✗ WATCHOS literal count 5 (expected 6)` + `✗ MACOSX literal count 7 (expected 6)` + `❌ Deployment-target drift` — the old total-count guard would have **passed** this |
| 3b `probe-gate-literal-removed.log` | pbxproj line 965 deleted (total 19) | **red** (exit 1, no `==> Unit tests`) | `✗ WATCHOS literal count 5 (expected 6)` + `❌ Deployment-target drift` |
| 3c `probe-gate-package-removed.log` | `Package.swift` `.watchOS("11.0")` line deleted | **red** (exit 1, no `==> Unit tests`) | `✗ package .watchOS count 0 (expected 1)` + `❌ Deployment-target drift` |
| 3d `probe-gate-clean.log` | unchanged tree | **green** gate | `✓ All deployment-target + package-floor literals match` with the exact 8/6/6 + 1/1/1 tuple |

3d's unit run exited non-zero only from the **known local-only macOS failures**
(`EntitlementStoreTests.isEntitledSurvivesStoreRecreation`,
`initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` — pre-existing,
annotated, do not debug) plus a one-off flake
`SettingsViewTests.showMenuBarExtraRoundTripsThroughContentView` that **passed in
isolation** (21:04) and **passed** in the `make mac-test` rerun — environment
state pollution, unrelated to this diff (no test source changed).

## 4. macOS floor unchanged + macOS-listing correction

- `make mac-test` (`platform=macOS`, `MACOSX_DEPLOYMENT_TARGET` still 26.5):
  suite executed **with** the 3 known local-only `EntitlementStoreTests`
  failures annotated; `showMenuBarExtraRoundTripsThroughContentView` passed.
  Log: `probe-mac-test.log`.
- **Correction to the landed commit's claim** (`53124c3e`): the comment asserted
  "the store's macOS requirement derives from `IPHONEOS_DEPLOYMENT_TARGET`, not
  from `MACOSX_DEPLOYMENT_TARGET`" — **verified false**. The app target is a
  **native macOS build** (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`,
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, `MACOSX_DEPLOYMENT_TARGET = 26.5`, no
  Catalyst), so the Mac App Store listing derives from
  **`MACOSX_DEPLOYMENT_TARGET`**. `scripts/test.sh` header comment corrected.

## 5. Runtime versions actually used (degraded leg) and smoke outcomes

| Platform | Runtime used | Device (UDID) | Outcome |
|---|---|---|---|
| iOS | **iOS 26.0** (23A343) — the Xcode 27.0 (27A266a) download catalog refuses every pre-26 build (17.0–25.0 all `not available for download`) | `Probe iPhone 15 (26.0)` — `DD998B17-B378-4CD2-8D51-6A89FE96ABB0` (`IOS17_SIM`) | App launches and stays alive (exit state 0, no crash); EventKit prompt appears (`"SingleThread" would like to access your Reminders…`); grant path fetches reminder lists (`FETCH START {name: REMEventKitBridgingDataViewInvocation_fetchLists}`); screenshots saved at `/tmp/launch-26*.png` (not committed) |
| watchOS | **watchOS 26.0** (23R353) — same catalog limitation | `Probe Watch S9 (26.0)` — `09529744-E7F1-415A-8C4D-89BE648E4F61` (`WATCH_PROBE_SIM`) | `watch-build`/`watch-test`/`watch-ui-test` all TEST SUCCEEDED on the probe watch (paired with the phase-1 phone, pair `5EAA9B61-…`); smoke launch returns stable PID (no crash-respawn), no CrashReporter artifacts |

`lib_TestingInterop.dylib` verdict: **NOT needed on watchOS 26.0** — the
`scripts/test.sh` bundling workaround exists because the **26.5** simruntime is
missing the lib; on 26.0 the watch UI runner launched and passed **unmodified**
(first attempt, `testLaunchAndRenderSmoke()` 8.6 s, no `Library not loaded`
crash). The workaround block is a 26.5-specific defect and is **untouched** by
this ticket.

## 6. ⚠️ Named verification gaps (stated in the PR body, not hidden)

1. **Xcode 27.0's download catalog serves no pre-26 iOS/watchOS runtime** —
   `xcodebuild -downloadPlatform` rejects 17.x–25.x for both platforms; no
   importable `.dmg`; no older Xcode installed. A genuine iOS 17.x / watchOS
   11.x (or any ≤ 25.x) **runtime** run is impossible in this environment.
2. The **runtime leg therefore degrades to iOS 26.0 / watchOS 26.0** (the
   strongest available older-than-default dot release). The **compile-time**
   red probes are unaffected (availability diagnostics come from SDK
   annotations + the deployment target, not the sim runtime).
3. The EventKit **deny** path of the iOS smoke was not exercised (grant path
   confirmed); watch smoke confirmed launch/render, not full interaction.
4. Gate subagent verdict + CI on PR #201: **pending** — the full
   `./scripts/test.sh` runs once via the `run-gate` skill after this commit
   (parent step), and CI then adjudicates.

## 7. Commit covered by the gate

- HEAD at the time of writing: `df53dc62` (Phase 2).
- SHA of the Phase 3 commit this record accompanies: `42196cea` (recorded when
  this record was finalized). The gate covers the **branch tip at launch** — the
  parent captures `git rev-parse --short HEAD` when the gate subagent starts.