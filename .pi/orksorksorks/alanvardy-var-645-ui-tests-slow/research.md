# Research Findings

Scope: test/build orchestration of the SingleThread Xcode project — `scripts/test.sh`,
`Makefile`, `.github/workflows/ci.yml`, `project.pbxproj`, XCTest UI suites, and the Swift
Testing unit suite. Each finding below carries a `file:line` reference.

---

## Q1: How are build/test invocations ordered & shaped across test.sh / Makefile / ci.yml?

### Findings

- **Two independent orchestration layers, not synonyms.** `scripts/test.sh` is the canonical
  local pipeline (format → lint → build → periphery → tests). `Makefile` largely delegates to
  it (`Makefile:67-68` `test:` → `./scripts/test.sh --unit-only`; `Makefile:70-71` `ui-test:` →
  `--ui-only`; `Makefile:84-85` `check:` → no-arg full run) while also exposing standalone
  `xcodebuild` targets (`build`, `watch-build`, `mac-build`, `mac-test`, `coverage*`,
  `watch-ui-test`). `.github/workflows/ci.yml` reimplements the same invocations as independent
  cache-restoring jobs; it does **not** call `test.sh` or `Makefile`.
- **Shared defaults** (identical across Makefile and test.sh):
  - `SIM = platform=iOS Simulator,name=iPhone 17` (`Makefile:1`, `test.sh:5`) — overridable.
  - `WATCH_SIM = generic/platform=watchOS Simulator` (`Makefile:2`, `test.sh:6`) for the plain
    watch build.
  - `WATCH_TEST_SIM = platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`
    (`Makefile:7`, `test.sh:11`) — concrete watch destination required for XCTests.
  - `MAC_SIM = platform=macOS` (`Makefile:8`, `test.sh:12`).
  - `DERIVED_DATA = DerivedData` (repo-root, `Makefile:9`, `test.sh:15`).
- **Full pipeline order in `scripts/test.sh`** (lines 135-253): SwiftFormat →
  `swiftlint --fix` → SwiftFormat `--lint` check → SwiftLint `--strict` → iOS `build-for-testing`
  (test.sh:180-184) → watch plain `build` (:188-192) → Periphery
  (`periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`,
  test.sh:196) → iOS unit `test-without-building -only-testing:SingleThreadTests`
  (test.sh:202-203) → iOS UI `test-without-building -only-testing:SingleThreadUITests`
  (test.sh:210-211) → watch `build-for-testing -only-testing:SingleThreadWatchUITests`
  (test.sh:219-220) + watch `test-without-building` (test.sh:224) → macOS `build`
  (test.sh:230-234) → macOS `test -only-testing:SingleThreadTests` (test.sh:240-242).
- **Cross-invocation build reuse in test.sh.** iOS builds **once** (`build-for-testing`) and
  reuses that artifact via `test-without-building` for **both** the unit and UI suites (lines
  183, 202-203, 210-211) — all sharing one `-derivedDataPath`. Watch builds twice (a non-test
  `build` at :188, then a test-purpose `build-for-testing` at :219); only the latter feeds the
  watch `test-without-building`. macOS uses plain `test` (build+run in one step), never
  `test-without-building`.
- **CI job split (ci.yml).** `unit-tests` (ci.yml:11-74), `ui-tests` (ci.yml:76-134),
  `mac-tests` (ci.yml:136-183), `lint` (ci.yml:185-233), `watch-ui-tests` (ci.yml:235-295).
  Each is an independent job with its **own build**: unit and UI iOS jobs each build
  `build-for-testing -only-testing:` their suite (ci.yml:53-55, 114-116), then
  `test-without-building` (ci.yml:61-64, 131-132). macOS builds with plain `build` (ci.yml:162-167)
  and tests with plain `test` (ci.yml:170-177) — no build reuse. Watch builds
  `build-for-testing` (ci.yml:275-280) then `test-without-building` (ci.yml:289-291).
- **Device/destination matrix:**
  - iOS unit & UI: `platform=iOS Simulator,name=iPhone 17` **or** `iPad (A16)` — a CI `matrix`
    over both (ci.yml:16-17, 77-78). Locally the default is iPhone 17, overridable.
  - macOS unit: `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (ci.yml:162; test.sh:231).
  - Watch UI: by concrete name locally (`Apple Watch Series 11 (46mm)`), by generated `id`
    (`platform=watchOS Simulator,id=$WATCH_UDID`, ci.yml:286) in CI.
- **Both parallel matrix legs share one cache bucket** — the `derived-data-…` key is identical
  for the iPhone and iPad legs of each job (they run on separate runners; see Q3).

---

## Q2: What parallelism exists at the xcodebuild-test and workflow level?

### Findings

- **CI job-level matrix parallelism.** `unit-tests` and `ui-tests` both expand to a 2-device
  `strategy.matrix` (`iPhone 17`, `iPad (A16)`), ci.yml:16-17 and :76-78 — two parallel legs per
  job, running concurrently with the single-device `mac-tests`, `lint`, `watch-ui-tests` jobs.
  Documented in `AGENTS.md` and added by commit `87ee343` ("Run unit and UI tests on iPhone and
  iPad in parallel CI matrix").
- **PR-wide concurrency guard:** `concurrency: { group: ci-${github.ref},
  cancel-in-progress: true }` (ci.yml:3-9) so only the latest push's pipeline runs.
- **Build-target parallelism (non-test):**
  - `project.pbxproj:364` `BuildIndependentTargetsInParallel = 1` (project-level).
  - `SingleThread.xcscheme:6` and `SingleThreadWatch.xcscheme:6` `parallelizeBuildables = "YES"`.
  - XCTest targets marked `parallelizable = "YES"`:
    `SingleThread.xcscheme:48` (SingleThreadTests), `:59` (SingleThreadUITests),
    `SingleThreadWatch.xcscheme:34` (SingleThreadWatchUITests).
- **Parallel test-simulator-destination flags — iOS UI only (ci.yml:128-130):**
  - `-maximum-test-execution-time-allowance 900`
  - `-parallel-testing-enabled NO`
  - `-maximum-concurrent-test-simulator-destinations 1`
  - Comment (ci.yml:121-125) explains: on GitHub's virtualized macOS runners the iOS clone
    connection to `com.apple.instruments.deviceservice.lockdown` can time out (120 s) and stall
    the step; a single concurrent destination avoids the race. Added by commit `3743384`
    ("Disable parallel test clones for iOS UI tests").
  - Preceding root-cause: commit `da236fa` ("Remove parallel-testing-enabled YES to fix
    simulated flakiness") stripped a global `-parallel-testing-enabled YES` because parallel
    testing cloned iPhone 17 into `Clone 1/Clone 2` and the `.xctrunner` failed on CI
    (`Busy (Application failed preflight checks)` → `NSMachErrorDomain Code=-308 ipc/mig server
    died`).
- **`-maximum-test-execution-time-allowance 900`** also on the watch UI test step
  (ci.yml:289), added by commit `04b63cb` ("UI + watch UI tests reliable on CI") so a hung test
  fails cleanly instead of hitting the 45-minute step timeout.
- **Why watch UI is NOT given the parallel-clone disable.** The watch step runs against a
  **per-run dedicated standalone watch created on the runner** via
  `simctl create "CI Watch S11"` (ci.yml:255-259, commits `aaac741`) and binds the exact
  `platform=watchOS Simulator,id=…` destination (ci.yml:286). A single concrete per-run device
  never exhibits the iOS `Clone N of…` race, so only the time-allowance guard (not the
  parallel-disable) was carried over to the watch step. No explicit comment states this; it is
  inferred from the git chain and destination shape.
- **Local scripts/Makefile pass none of these flags.** Neither `-parallel-testing-enabled`,
  `-maximum-concurrent-…`, nor `-maximum-test-execution-time-allowance` appears in
  `scripts/test.sh` or `Makefile`. These protections are CI-only.

---

## Q3: How does DerivedData build-artifact caching/reuse currently work?

### Findings

- **`actions/cache@v4` key design (per job) — all target `github.workspace/DerivedData`:**
  - Unit-tests: key `derived-data-{os}-{xcodeVer}-{ref}-{sha}` of 8 roots (ci.yml:35),
    restore-keys `derived-data-{os}-{ver}-{ref}-` and `derived-data-{os}-{ver}-` (ci.yml:36-38).
  - ui-tests: identical key namespace `derived-data-…` (ci.yml:96) — same bucket as unit-tests but
    keyed with the same source hash.
  - mac-tests: separate prefix `derived-data-mac-…`, `hashFiles` **omits** UI-test sources
    (ci.yml:152, restore :154-155).
  - watch-ui: separate `watch-ui-derived-data-…` (ci.yml:251), `hashFiles` scoped to
    `SingleThreadWatch/**`, tests, core, pbxproj; restore-keys only `watch-ui-…-{os}-{ver}-`
    (ci.yml:252-253) — **none** of the `{ref}` fallback.
  - lint jobs: `mise-tools-…` key over `~/.local/share/mise` (ci.yml:203), not DerivedData.
  - Cache invalidation is entirely `hashFiles(…, project.pbxproj)` so any Swift/pbxproj edit
    rolls the source SHA and invalidates the entry.
- **`test-without-building` bridge** — a `build-for-testing` step writes into `DERIVED_DATA`,
  then a `test-without-building` step reads the same path (skips recompilation):
  - unit (build ci:50-55 / test ci:58-64), ui (ci:109-116 / ci:119-131), watch
    (ci:273-281 / ci:284-291). Same bridge locally (test.sh:180-184→:; :219-224).
  - **macOS is the exception:** uses plain `build` (ci:162-167) + plain `test` (ci:173-177) —
    no `test-without-building`, so the macOS leg recompiles.
- **Shared DerivedData path** — every `xcodebuild` gets `-derivedDataPath`; CI sets
  `DERIVED_DATA = github.workspace/DerivedData` (ci:20, 81, 137, 236); local is repo-relative
  `DerivedData`.
- **Adding a second consumer:** Periphery reuses the iOS build's index store locally
  (`periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore`,
  test.sh:196); CI lint instead runs `periphery scan --strict -- -destination "platform=iOS
  Simulator,name=iPhone 17"` (ci:230-231).
- **`.gitignore` exclusion** — `.gitignore:4` lists `DerivedData/` (fully git-ignored);
  `.gitignore:6` (next) `build/` (coverage bundles); `.gitignore:2` `xcuserdata/`.
- **Local persistence outside CI:**
  - `DerivedData/` persists locally between runs (gitignored); it is **never** pruned locally.
  - XCTest runtimes in `~/Library/Developer/XCTestDevices` are intentionally pruned by
    `cleanup_xctest_runtimes()` (test.sh:30-66) — see Q4.
  - Coverage bundles persist under `build/Coverage{,.UI,.All}.xcresult` (`Makefile:6-8`,
    `coverage*` targets `rm -rf` before regenerating).

---

## Q4: Trace the per-XCTest-UI-test-invocation duration

### Findings

- **XCTestDevicesRuntimes runtime — the dominant per-invocation cost.** Each UI test run creates
  a fresh runtime under `$HOME/Library/Developer/XCTestDevices` (~3 GB), which Xcode never prunes
  (test.sh:16, 18-19). It is per-invocation, never reused across launches; cost scales with the
  number of test-class launches.
- **Garbage collection** is manual only in `scripts/test.sh`: `cleanup_xctest_runtimes()`
  (test.sh:30-66). Default threshold `RUNTIME_AGE_HOURS = 1` (test.sh:15, 39); it iterates
  `"$RUNTIMES_DIR"/*` (test.sh:51), skips non-dirs/symlinks (:52-53), reads per-entry mtime via
  `stat -f '%m'` (:57), deletes entries older than cutoff (:60-61). Called unconditionally once,
  early, before any build (test.sh:130-133). Runs in all three modes. It deliberately only removes
  entries older than the threshold (test.sh:17-20, 127-129), and relies on APFS keeping open
  handles alive so in-flight parallel runs are never disturbed.
- **Simulator cold boot is a recognized dominant cost.** Comments in the iOS launch tests:
  `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift:11-16`
  ("on cold CI simulators the launch test is slow… pushes the whole UI suite past its step
  timeout") and `SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests.swift:11-15`
  ("Run once per launch configuration to keep the CI suite within its step timeout on cold
  virtualized simulator"). Also :31 "cold virtualized simulators".
- **Per-launch cost is unfixed-shot.** Every XCTest method constructs a fresh `XCUIApplication()`
  and calls `.launch()`; no app reuse across methods:
  - `SingleThreadUITests/SingleThreadUITests.swift:26-28`
  - `ActionButtonsUITests.swift:12, 29`
  - `SingleThreadUITestsLaunchTests.swift:25-31`
  - `SingleThreadUITestsAppearanceLaunchTests.swift:10, 35, 62, 93` (three methods each new)
  - `SingleThreadUITestsFlows.swift:22-31` — private `launchApp(seedJSON)` helper; every flow test
    calls it.
  - Watch: `SingleThreadWatchUITests.swift:16, 26`; `SingleThreadWatchUITestsFlows.swift:61-67`
    (`--ui-testing` helper); `SingleThreadWatchUITestsLaunchTests.swift:21`.
- **Launch-state seams (deterministic stores, avoiding EventKit/TCC):**
  - `--ui-testing` — iOS `SingleThreadApp.swift:130-142` seeds a real "Buy groceries" EKReminder
    with `loadsReminders:false` (:144-146), enables action buttons (:131); watch
    `SingleThreadWatchApp.swift:11-13, 63-67` builds `uiTestingStore()`.
  - `--seed '<json>'` — `UITestingSeed.fromLaunchArguments` (`SingleThreadApp.swift:109-121`)
    backs the `InMemoryEventStore`; `loadsReminders:true`, calls `resetPersistedState()` so no
    state leaks between launches. Used by `SingleThreadUITestsFlows.swift:22-33` for
    complete/delete/skip write flows.
  - `--no-reminders` — suppresses the Reminders TCC prompt during cold-launch appearance checks
    (`SingleThreadUITestsAppearanceLaunchTests.swift:26-27, 35, 62, 93`;
    `SingleThreadUITestsLaunchTests.swift:29`).
- **Launch multiplication via `runsForEachTargetApplicationUIConfiguration`:** XCTest default runs
  each method once per target-application UI configuration. Overrides:
  - iOS `SingleThreadUITestsLaunchTests.swift:17` → `false` (single-config launch, to stay under
    cold-CI step timeout; comment :11-13).
  - iOS `SingleThreadUITestsAppearanceLaunchTests.swift:17` → `false` (same rationale).
  - Watch `SingleThreadWatchUITestsLaunchTests.swift:6` → `true` — keeps the default multiplication,
    which the iOS launch test deliberately turned off.
  - The other iOS classes (`SingleThreadUITests`, `ActionButtonsUITests`, all of
    `SingleThreadUITestsFlows`) and watch flows do **not** override, so they run once per target
    application UI configuration — multiplying each class's fresh runtime + cold boot. The exact
    count of target UI configurations is not surfaced in sources.

---

## Q5 — Accessibility audit behavior under CI & gating of slow/hang-prone tests

### Findings

- **iOS main audit + CI reduction — `SingleThreadUITests/SingleThreadUITests.swift:17-55`:**
  `testAccessibilityAudit()` waits for a visible text on the `--ui-testing` empty store then audits.
  - Contrast is skipped outright (`textClipped`/contrast) — known false-positive source for
    system colors (line 30).
  - **CI gating (lines 32-48):** nested `#if os(iOS)` + runtime check
    `ProcessInfo.processInfo.environment["CI"] == "true"` (line 40). When `CI=true` it audits only
    `[.sufficientElementDescription, .trait]` — the cheap, non-rendering categories (line 42);
    locally it adds `[.dynamicType, .hitRegion, …]` (line 46). The comment (lines 33-36) explains
    that attempting `.dynamicType`/`.hitRegion` (full-tree rendering/scaling simulation) can hang
    indefinitely on GitHub's virtualized macOS runners. These categories are noted as still covered
    by unit suites (e.g., `SingleThreadTests/AppearanceModeTests.swift`).
  - The `#else os(macOS)` branch runs the default categories (line 51).
- **But the other two audits are NOT CI-reduced:**
  - `ActionButtonsUITests.swift:36-58` `testActionButtonsAccessibilityAudit()` — platform-gated
    `#if os(iOS)` → `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` (line 54),
    else defaults — but there is **no** `CI=true` gate. Full rendering-heavy traversal can run on
    CI for the action-buttons UI.
  - `SingleThreadWatchUITests.swift:27-40` `testAccessibilityAudit()` — `#if os(watchOS)` runs
    `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` (line 37); no CI gate.
- **CI flags that keep duration/hang in check (see Q2):** iOS step disables parallel simulator
  clones (`-parallel-testing-enabled NO`, `-maximum-concurrent-test-simulator-destinations 1`,
  ci.yml:129-130), sets `-maximum-test-execution-time-allowance 900` (ci.yml:128). Watch step sets
  `-maximum-test-execution-time-allowance 900` (ci.yml:289) but no parallel-disable.
- **TCC / Reminders prompt is avoided, not tested:**`--no-reminders` is used to suppress the
  Reminders TCC prompt on the launch/appearance paths
  (`SingleThreadUITestsAppearanceLaunchTests.swift:26-27, 35, 62, 93`;
  `SingleThreadUITestsLaunchTests.swift:29, 33`), so scene activation isn't blocked on a fresh
  install.
- **SwiftLint accessibility** — the only accessibility rules are opt-in
  `accessibility_label_for_image` / `accessibility_trait_for_button` (`.swiftlint.yml:45-46`); no
  audit/skip config in SwiftLint. The `CI=true` env var is set by the GitHub runner automatically
  (not written in ci.yml).

---

## Q6 — The unit-test side (SingleThreadTests, Swift Testing)

### Findings

- **Target definition** — `SingleThread.xcodeproj/project.pbxproj:264` `productType =
  "com.apple.product-type.bundle.unit-test"`, product `SingleThreadTests.xctest`.
  `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (pbxproj:695, 745, 770) — one target
  serves both iOS simulator and the separate macOS destination. Floors: `IPHONEOS_DEPLOYMENT_TARGET
  = 18.7`, `MACOSX_DEPLOYMENT_TARGET = 26.5` (pbxproj:685-688 etc.); `TEST_HOST`/`BUNDLE_LOADER`
  point at the built host app.
  File-system-synchronized, auto-file-discovery (no pbxproj edits for new `.swift`).
- **Suite ~284 tests** — 26 `.swift` files under `SingleThreadTests/` using Swift Testing style
  (`import Testing`, `@Test`, `@testable import`, `@MainActor`); `grep -rn "@Test"` yields
  284. Coverage across `ReminderStoreTests`, `ReminderSkipTests`, `ReminderDateFilterTests`,
  dictation/parsing, `EventKitStoringTests`, `AppGroupTests`, `SortOptionTests`,
  `AppearanceModeTests`, `UITestingSeedTests`, etc. The folder ships a relaxed
  `.swiftlint.yml` (force-unwrap exception for test fixtures).
- **Matrix & destinations:** CI `unit-tests` runs on a 2-device matrix (`iPhone 17`,
  `iPad (A16)`) with `build-for-testing`→ `test-without-building` (ci.yml:53-64); it also has a
  dedicated `mac-tests` job using `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, plain `build`+`test`
  (ci.yml:162-183). Locally `make test`/`make mac-test` mirror this split
  (`Makefile:17-30`, `Makefile:47-53`) and `scripts/test.sh` runs the suite **twice** in full mode
  — once on iOS after the main build (:203), once on macOS (:240-242).
- **Pipeline contribution:** The suite is a required CI gate; `make coverage` runs it with
  `-enableCodeCoverage YES -only-testing:SingleThreadTests` (Makefile:47-55) and `coverage-all`
  covers unit + UI. Its build is the same `build-for-testing` already produced for the iOS UI
  suite in test.sh full mode — so locally its incremental cost is the test run itself, not another
  build. In CI the `unit-tests` build is a separate job (also reused via `test-without-building`
  and the DerivedData cache), while the unit suite does not run on watchOS (WATCHOS absent
  from `SUPPORTED_PLATFORMS`).

---

## Q7 — Which XCTest/xcodebuild timing/resource options exist, and where limits sit

### Findings

- **`-showBuildTimingSummary`** — every build **step in CI only**: ci.yml:55 (unit),
  ci.yml:116 (ui), :166 (mac), :227 (lint watch build), :281 (watch UI). Not in Makefile, and
  not in test.sh (they omit all these flags). Also only referenced in stale plan/research artifacts
  under `.pi/qrspi/*` (e.g. `questions.md`), not repo-of-record.
- **`-maximum-test-execution-time-allowance 900`** — the only test-specific timing option, only
  on the two UI test steps: ci.yml:128 (iOS UI) and ci.yml:289 (watch UI).
- **`-parallel-testing-enabled NO` + `-maximum-concurrent-test-simulator-destinations 1`** —
  only in ci.yml:129-130 (iOS UI). See Q2.
- **Per-step wall-clock via Git timeouts (`timeout-duration`)**: unit Build 20 (ci:47),
  unit test 20 (:58), ui Build 20 (:108), ui test 45 (:119), mac build 20 (:158), mac test 20
  (:169), SwiftFormat/SwiftLint 5 (:213, :217), watch build 15 (:221), Periphery 10 (:230),
  watch build 20 (:273), watch test 45 (:284).
- **Simulator pre-boot (cache/boot steps)** — CI only, per simulator job:
  - iOS unit `Pre-boot simulator` ci:39-45 (`simctl list devices available` → `simctl boot` → `…
    -b`).
  - iOS UI `Pre-boot simulator` :100-106 (same).
  - watch :255-272 — creates standalone sim via `simctl create "CI Watch S11"`, then `simctl boot`
    + `bootstatus -b`.
  - Local mirror in `scripts/simverify.sh:13-21` (+ `simctl io … screenshot` at :38), explicitly
    "CI-identical gate; do not skip bootstatus -b". `scripts/test.sh` does **not** preboot — no
    `simctl` calls.
- **Source-level timing** — only per-element `XCUIElement.waitForExistence(timeout: N)` in UI
  tests (e.g. `SingleThreadUITestsAppearanceLaunchTests.swift:39, 70, 101` etc.) and the
  `runsForEachTargetApplicationUIConfiguration` override to cap launchers on cold sims.
- **Observing the limits if the UI suite were re-partitioned:** the current resource ceilings are
  the 45-min `timeout-minutes` (ci:119, :284), the 900s `-maximum-test-execution-time-allowance`
  (ci:128, :289), and the memory space implied by the ~3GB scrutest runtimes + XCTestDevices prune.
  Re-partitioning would surface those bounds at whatever sub-step inherits the (shared) 45-min /
  900s ceilings; there is no other per-partition limit knob in the repo today.

---

## Cross-Cutting Observations

### Opening summary

- **Two layers diverge on reuse.** Local `scripts/test.sh` reuses one iOS build for both unit + UI
  (shared -derivedDataPath + test-without-building), while CI splits unit and UI into separate
  jobs, each building its own artifact (but reusing across runs via the DerivedData cache). macOS
  is the odd one in both layers: always `build`+`test`, never `test-without-building`.
- **The real duration driver is test-launch count, not build time.** Each XCTest method launches a
  fresh `XCUIApplication()` into a ~3GB per-run simulator runtime; the number of configurations
  × runs multiplies it. The iOS launch tests deliberately drop
  `runsForEachTargetApplicationUIConfiguration` to `false` to stay under the CI step timeout; the
  watch launch test keeps `true`.
- **Parallelism exists at two scales that are orthogonal:** (a) build parallelism in the project
  (`BuildIndependentTargetsInParallel`, `parallelizeBuildables`) for targets to build concurrently,
  and (b) `xcodebuild` test-simulator cloning (`-parallel-check-enabled`), which iOS deliberately
  disabled. The CI matrix gives vertical parallelism across devices; the XCUITest clone knob is a
  horizontal, within-step parallelization that had to be turned off on virtualized runners.
- **The `CI=true` env carve-out is a deliberate, asymmetric optimization in source** — iOS main
  audit reduces scope under CI, while the ActionButtons and watch audits do not. Any UI
  repartitioning that changes which audit runs would or would not need to consider the `CI` env check.
- **caching/reuse: DerivedData is the single shared build artifact across all iOS jobs keyed by
  source-sha; the watch key omits the `{ref}`-bucket fallback.**

## Open Areas

- Exact count of "target-application UI configurations" (the per-config multiplier) is not stated
  anywhere in the sources — it determines how many launches the non-override classes produce.
- The precise wall-clock split between cold-boot, runtime creation, app launch, and audit traversal
  is not encoded in the repo; only the coarse comments and CI timeouts exist.
- Why `ActionButtonsUITests` and the watch audit skip the `CI=true` reduction is not explained by
  any comment.
- The watch key's missing `{ref}`-level fallback (ci.yml key) could theoretically restore a
  different-branch cache; it is noted here only as observed behavior, not analyzed.
- Repartitioning of the UI suite into finer slices is not present anywhere in the repo; the only
  knob controlling per-works timing today is `-maximum-test-execution-time-allowance` plus the
  45-min step timeout. WATCHOS target count and the exact pruning interaction (mtime vs open
  handles) are not exhaustively validated.

---

**Next:** run `/3_design`