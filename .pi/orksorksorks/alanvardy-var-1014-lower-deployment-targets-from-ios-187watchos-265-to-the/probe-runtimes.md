# Probe runtimes — Phase 1 (iOS 17.0 floor proof)

## Runtime availability investigation (2026-09-16)

**Attempted**: `xcodebuild -downloadPlatform iOS -buildVersion <v>` for every
candidate below. **Result**: the Xcode 27.0 (27A266a) download catalog serves
**only iOS 26.x / 27.x runtimes**; every pre-26 release was rejected:

| Version | Result |
|---|---|
| 17.0, 17.2, 17.4, 17.5, 17.5.1, 17.6, 17.6.1 | `not available for download` |
| 18.0, 18.2, 18.3, 18.4 | `not available for download` |
| 19.0, 20.0 | `not available for download` |
| 21.0, 22.0, 23.0, 24.0, 25.0 | `not available for download` |
| 26.0 (23A343) | ✅ served, downloaded (7.99 GB) |

No `iOS 17.x Simulator Runtime.dmg` exists locally to import via
`xcrun simctl runtime add`; no older Xcode app is installed. Xcode is
27.0 (`/Applications/Xcode.app` only), matching AGENTS.md's "Local Xcode
27.0 vs CI 26.6" note.

## ⚠️ NAMED VERIFICATION GAP

The task/design wants the app *runtime-verified on an actual pre-Liquid-Glass
OS* (iOS 17.x runtime). **No pre-26 iOS runtime is obtainable in this
environment** (catalog refuses all of 17.x–25.x; no importable .dmg; no older
Xcode). Per `plan.md` Phase 1 fallback, this is a **named gap**, not hidden:
- The compile-time red probes (1a/1b/1c) are **unaffected**: availability
  diagnostics come from SDK annotations + the deployment target, not from the
  sim runtime.
- The green runtime leg degrades to the **strongest available (oldest)**
  runtime: **iOS 26.0 (23A343)**, which is still Liquid-Glass line but older
  than the local default 26.5 — it verifies install/build/launch on a
  non-default-dot runtime only.
- A genuinely pre-Liquid-Glass (iOS ≤ 25.x) run remains unverified locally;
  the PR body (Phase 3) must state this gap.

## iOS 26.0 probe device

- Device: `Probe iPhone 15 (26.0)`
- UDID: **`DD998B17-B378-4CD2-8D51-6A89FE96ABB0`**
- Runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-0` (26.0 — 23A343)
- Device type: `com.apple.CoreSimulator.SimDeviceType.iPhone-15`
- Booted: yes

```
IOS17_SIM='platform=iOS Simulator,id=DD998B17-B378-4CD2-8D51-6A89FE96ABB0'
```

(The plan's `IOS17_SIM` name is retained for drop-in substitution in commands;
the underlying runtime is 26.0, not 17.x — see the named gap above.)

## Smoke-launch outcome (iOS 26.0 sim)

Bundle id `app.alanvardy.SingleThread`, built at landed floors (17.0/11.0/26.5)
and installed into the `Probe iPhone 15 (26.0)` device. Observed via
`simctl launch` + `log show`:

- App launches and stays alive (`launchctl list` shows
  `UIKitApplication:app.alanvardy.SingleThread` with exit state 0; no crash).
- **EventKit authorization prompt appears**: SpringBoard log shows
  `Received request to activate alertItem: <SBUserNotificationAlert … title: "SingleThread" would like to access your Reminders…>` and the app log
  shows `(EventKit) Requesting full access to reminders`.
- Prompt **grant** path (`simctl privacy … grant reminders` then relaunch):
  app relaunches, fetches reminder lists (`REMStore Invocation`,
  `FETCH START {name: REMEventKitBridgingDataViewInvocation_fetchLists}`), and
  stays alive — the reminder-list path renders without crash. (Deny path not
  exercised; grant path confirmed enough for the smoke goal on the degraded
  runtime.)
- Screenshots saved locally at `/tmp/launch-26.png`, `/tmp/launch-26b.png`,
  `/tmp/launch-26-granted.png` (not committed).

Caveat (repeat of the named gap): this is iOS **26.0**, not a pre-Liquid-Glass
runtime — it validates the launch/authorization/fetch path on a non-default
(older) dot release only.

## Green suite-run detail

Plan step 6 names `scripts/test-one.sh SingleThreadTests/EventKitStoringTests`,
but there is no suite with that name: `SingleThreadTests/EventKitStoringTests.swift`
contains `ReminderStoreWriteTests` (12 ran), `ReminderStoreLifecycleTests` (9 ran)
and `ReminderStoreAvailableListsTests` (2 ran) — plus `ReminderStoreTests` (34 ran).
Each printed `ok: N case(s) ran` with N > 0, satisfying the plan's intent. The
raw plan spelling `…/EventKitStoringTests` matches zero cases and exits 1;
the real suite names were used instead.

---

# Probe runtimes — Phase 2 (watchOS 11.0 floor proof)

## Runtime availability investigation (2026-09-16)

**Attempted**: `xcodebuild -downloadPlatform watchOS -buildVersion <v>` for the
candidates below. **Result**: same as Phase 1 — the Xcode 27.0 (27A266a)
download catalog serves **only watchOS 26.x / 27.x runtimes**; every pre-26
release was rejected:

| Version | Result |
|---|---|
| 11.5, 17.5, 18.0, 25.0 | `not available for download` (exit 70) |
| 26.0 (23R353) | ✅ served, downloaded (3.83 GB), installed |

No `watchOS 11.x Simulator Runtime` exists locally to import; no older Xcode
is installed.

## ⚠️ NAMED VERIFICATION GAP (watchOS)

The task/design wants the watch app *runtime-verified on a watchOS 11.x
runtime*. **No watchOS < 26 runtime is obtainable in this environment**
(catalog refuses 11.5/17.5/18.0/25.0; no importable .dmg; no older Xcode).
Per `plan.md` Phase 2 fallback, this is a **named gap**, not hidden:
- The compile-time red probes (2a/2b/2c) are **unaffected**: availability
  diagnostics come from SDK annotations + the deployment target, not the sim
  runtime.
- The green runtime leg degrades to the **strongest available (oldest)**
  watchOS runtime: **watchOS 26.0 (23R353)**, which verifies
  build/install/launch on a non-default-dot runtime only.
- A genuinely watchOS ≤ 25.x run remains unverified locally; the PR body
  (Phase 3) must state this gap.

## watchOS 26.0 probe device

- Device: `Probe Watch S9 (26.0)`
- UDID: **`09529744-E7F1-415A-8C4D-89BE648E4F61`**
- Runtime: `com.apple.CoreSimulator.SimRuntime.watchOS-26-0` (26.0 — 23R353)
- Device type: `com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-45mm`
- Booted: no (booted on demand for watch-test / UI runs)

```
WATCH_PROBE_SIM='platform=watchOS Simulator,id=09529744-E7F1-415A-8C4D-89BE648E4F61'
```

(The plan's `WATCH11_SIM` name is intentionally **not** used — the runtime is
26.0, not 11.x; it is named `WATCH_PROBE_SIM` to keep the gap honest.)

## Phase 2 probe results (watchOS floor ladder)

### Probe 2a — gate drift (red, no build)

`env DEPLOYMENT_TARGET_WATCHOS=10.0 bash scripts/test.sh --unit-only` → exit 1
at `verify_deployment_target()`, before any build:

```
✗ WATCHOS = 11.0 (expected 10.0)   ×6 + ✗ package .watchOS = 11.0 (expected 10.0)
❌ Deployment-target drift …
```

No `==> Unit tests` line in the log. Evidence: `probe-watchos10.0-drift-gate.log`.

### Probe 2b — watchOS 9.0 (red; exact pinning APIs)

pbxproj 6×9.0 + Package.swift `.watchOS("9.0")`, then
`env DEPLOYMENT_TARGET_WATCHOS=9.0 make watch-build` → **BUILD FAILED**. The
exact availability diagnostics (target `arm64-apple-watchos9.0-simulator`):

- `'Observable()' is only available in watchOS 10.0 or newer`
  (`CompletionGlow.swift:12`, `EntitlementState.swift:9`, …)
- macro expansions `'ObservationTracked()'` / `'ObservationIgnored()'` are only
  available in watchOS 10.0 or newer (from `@Observable`)
- `'fullAccess' is only available in watchOS 10.0 or newer`
  (`InMemoryEventStore.swift:38` — EventKit `EKAuthorizationStatus.fullAccess`)

**Pinning APIs: Observation's `@Observable` macro and EventKit's
`EKAuthorizationStatus.fullAccess` — both floor at watchOS 10.0.** Evidence:
`probe-watchos9.0-build.log`.

### Probe 2c — watchOS 10.0 (green-but-rejected data point)

pbxproj 6×10.0 + `.watchOS("10.0")`, then
`env DEPLOYMENT_TARGET_WATCHOS=10.0 make watch-build` → **BUILD SUCCEEDED**
(target `arm64-apple-watchos11.0`→`watchos10.0-simulator`, deployment-target 10.0).
No 10.0 availability error — the true compile floor is 10.0
(EventKit `watchos(10.0)`, Observation watchOS 10), exactly as the design predicted.

**Why rejected as the ship floor**: design decision 2 — dropping 11.0 → 10.0
buys only Apple Watch Series 4/5/SE (1st gen) reach, which is not a product
goal; the landing stays at watchOS 11.0 (Series 6+ reach unchanged). Evidence:
`probe-watchos10.0-build.log`.

### Landed-floor gate + runtime verification (watchOS 26.0 degraded runtime)

- `probe-watchos-landed-gate.log`: `✓ All deployment-target + package-floor
  literals match` `(iOS 17.0 × 8, watchOS 11.0 + macOS 26.5 × 12, package .iOS 1,
  package other 2)`; only the 3 known local-only macOS `EntitlementStoreTests`
  failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
  `hostStoreKitIsClean`).
- `make watch-build` at landed 11.0 (generic dest) → **BUILD SUCCEEDED**
  (`probe-watchos-landed-watch-build.log`).
- `make watch-test` (`WATCH_TEST_SIM=…id=09529744-…`) on `Probe Watch S9 (26.0)`
  → **TEST SUCCEEDED**, suites ran on `Clone 1 of Probe Watch S9 (26.0)`
  (`probe-watchos-watch-test.log`).
- `make watch-ui-test` on the probe watch **unmodified** (paired with the Phase 1
  IOS17_SIM phone DD998B17-…, pair id 5EAA9B61-1E69-46BA-8AEC-8F8B8B57C36A)
  → **TEST SUCCEEDED on the first attempt**: runner launched on
  `Clone 1 of Probe iPhone 15 (26.0) - SingleThreadWatchUITests-Runner`,
  `testLaunchAndRenderSmoke()` passed (8.6 s)
  (`probe-watchos-watch-ui-test-1.log`).

### `lib_TestingInterop.dylib` verdict (watchOS 26.0 runtime): **NOT NEEDED**

The 26.0 `watchOS` simruntime does not reproduce the 26.5 defect: the watch UI
runner launched and passed unmodified (no `Library not loaded:
@rpath/lib_TestingInterop.dylib` crash, no `cp` applied). The
`scripts/test.sh` bundling workaround (needed on the 26.5 runtime) is a
26.5-specific environment defect — on 26.0 it is a no-op / unnecessary. The
workaround is **not needed** on this runtime (and remains untouched — Phase 3's
file).

### Smoke launch outcome (watchOS 26.0 sim)

Bundle id `app.alanvardy.SingleThread.watchkitapp`, built at landed floors
(17.0/11.0/26.5), installed into the `Probe Watch S9 (26.0)` device:

- `simctl install` OK (listapps shows the bundle + data container).
- `simctl launch … watchkitapp` returned PID 88068, exit 0; repeat launches
  return the **same PID** (original instance still alive — no crash-respawn).
- No CrashReporter artifacts for the app on the device; device trace shows the
  app registered/launched via InstallCoordination with no crash record.
- The same bundle passed `SingleThreadWatchUITests.testLaunchAndRenderSmoke()`
  on the paired sim (8.6 s) — renders without crashing.

Caveat (named gap): this is watchOS **26.0**, not 11.x — it validates
build/install/launch/render on a non-default (older) dot runtime only; a real
watchOS 11.x (or any ≤ 25.x) run remains unverified (see the named gap above).