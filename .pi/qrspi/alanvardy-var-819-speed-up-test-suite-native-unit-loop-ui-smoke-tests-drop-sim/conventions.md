# Conventions — shared factual appendix

## Canonical commands (Makefile / scripts / CI)

- `make test` → `./scripts/test.sh --unit-only` (`Makefile:78-79`) — iOS Simulator unit slice only.
- `make ui-test` → `./scripts/test.sh --ui-only` (`Makefile:81-82`) — iOS Simulator UI slice only.
- `make check` → `./scripts/test.sh` full pipeline (`Makefile:103-104`).
- `./scripts/test.sh full|--unit-only|--ui-only` — full: format → fmt-check → swiftlint → iOS build → watch build → periphery → iOS unit → iOS UI → watch build(concrete) → dylib fix → watch UI → watch unit → macOS unit (`scripts/test.sh:196-295`). Modes slice only the iOS half (`:300-341`); pre-boot, runtime cleanup, deploy-target guard always run (`:104,:194`).
- Standalone Makefile invocations (not via test.sh): `make build` (`:17` iOS Debug build-for-testing), `watch-build` (`:20`), `mac-build` (`:23`), `mac-test` (`:26` `CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests`), `simverify` (`:84` → `scripts/simverify.sh`), `watch-ui-test` (`:87-93`), `watch-test` (`:95-101`), `coverage`/`coverage-ui`/`coverage-all` (`:40-75`, `-enableCodeCoverage YES` + `-resultBundlePath`), `lint`/`format`/`periphery` (`:109-119`), `clean`/`reset-storekit`/`mac-distribute`/`mac-run`.
- Periphery: `make periphery` passes `--strict -- -destination "$SIM"` (`Makefile:112-116`); `test.sh` phase 6 uses `--skip-build --index-store-path DerivedData/Index.noindex/DataStore` (`scripts/test.sh:227`). Note: `make periphery` reads a stale index after branch switches — clean `DerivedData/` first.
- Lint/format gates: `swiftformat` (`.swiftformat`) + `swiftlint lint --strict` (`scripts/test.sh:197-207`); swiftlint runs `--strict` so every warning is an error.
- CI (`ci.yml`, push to main only `:3-5`) never calls `test.sh` — raw xcodebuild, 7 jobs: unit-tests, ui-tests-flows, ui-tests-launch-appearance, ui-tests-audits, mac-tests, lint, watch-ui-tests. Each iOS job pre-boots its own matrix sim; `watch-ui-tests` creates+boots a standalone unpaired "CI Watch S11" (`:429-445`).

## Test-suite inventory

### `SingleThreadTests/` (Swift Testing, `import Testing`, `@Test`) — 520 `@Test` (496 plain + 24 parameterized)
- Single target `project.pbxproj:269-290`, `SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx"` → compiles for **both** iOS Sim and macOS. Runs at `scripts/test.sh:230-237` (iOS sim, `-parallel-testing-enabled YES`) and `:285-291` (macOS, `CODE_SIGNING_ALLOWED=NO test`), CI `ci.yml:78` and `:309-311` (mac: `test` action + `CODE_SIGNING_ALLOWED=NO`).
- **Whole-file platform gates (line 1)**:
  - `#if os(iOS)`: `AppDelegateTests.swift:1` (UIKit), `BackgroundCardTests.swift:8`.
  - `#if os(macOS)`: `MacOSActionButtonChromeTests.swift:1`, `MenuBarExtraOptionsTests.swift:1`.
  - `#if os(iOS) || os(watchOS)`: `EntitlementSyncTests.swift:1`, `RescheduleSyncTests.swift:1`, `SkippedReminderSyncServiceTests.swift:1`, `EnableActionButtonsSyncTests.swift:1` (WatchConnectivity, 48 `@Test` total; effectively iOS-only in this target).
- **In-file gates**: `AppearanceModeTests.swift:18-27/31-40`, `MicrophoneToggleTests.swift:232,270`, `SettingsViewTests.swift` (many), `SettingsSubscreenLayoutTests.swift:13,25`, `AboutViewTests.swift:26`, `ReminderStoreTests.swift:557,673`, `SingleThreadTests.swift:44,61,84,108,129`.
- Notable: `EntitlementStoreTests.swift` (host-store-sensitive; `hostStoreKitIsClean` `:91-106` reads real `Transaction.currentEntitlements` under unsigned macOS run). Real-EK fixtures: `EventKitStoringTests.swift:141,557,562,570`, `ReminderStoreTests.swift:1109,1122`, `ReminderStoreGateTests.swift:168`.
- **No runtime skip facilities anywhere** (`@available`, `.skip`/`.enabled`, `XCTSkip` all absent).

### `SingleThreadUITests/` (XCTest) — 23 methods / 9 files (+2 empty classes)
- iOS-only target (`SUPPORTED_PLATFORMS="iphoneos iphonesimulator"`), run locally `scripts/test.sh:240-245`.
- Files: `SingleThreadUITests.swift` (1), `SingleThreadUITestsLaunchTests.swift` (1, screenshot only), `SingleThreadUITestsAppearanceLaunchTests.swift` (3, `--no-reminders`), `SingleThreadUITestsFlows.swift` (12, `--seed`), `ActionButtonsUITests.swift` (2), `NotificationsSettingsUITests.swift` (2), `NotificationsUITests.swift` (1, `#if os(iOS)` file), `SkipNudgeUITests.swift` (1, iPad geometry), `ActionMenuUITests.swift` (0, empty), `NotificationSchedulingUITests.swift` (0, empty, `#if os(iOS)`).
- `runsForEachTargetApplicationUIConfiguration = false` in: `SingleThreadUITests.swift:18-19`, `SingleThreadUITestsLaunchTests.swift:17-18`, `SingleThreadUITestsAppearanceLaunchTests.swift:17-18`, `ActionButtonsUITests.swift:11-12`; default `true` elsewhere (incl. Flows).
- Launch: `SingleThreadUITestCase.swift:13` `launchApp`, `:21` `launchSeeded` (`--seed <json> --ui-testing-noop-settle --ui-testing-reduced-glow`), `:49` `assertTogglePersists` (relaunch `--ui-testing`), `:65` `statusLabel`.
- a11y audit sites: `SingleThreadUITests.swift:53-64` (CI carve-out — CI=[.sufficientElementDescription,.trait]; local iOS adds .dynamicType,.hitRegion; macOS default), `ActionButtonsUITests.swift:71,75`, `NotificationsUITests.swift:14`, `SingleThreadWatchUITests.swift:18`.

### `SingleThreadWatchTests/` (Swift Testing) — 44 `@Test` / 7 files
- Watch-only target (`watchos watchsimulator`), **no `#if os(...)` gates** in the files (target-level gating). Files: `ReminderStoreWatchTests` (6), `ShowCompletionGlowStateTests` (10), `ShowEnableActionButtonsStateTests` (4), `WatchAppViewModelTests` (2), `WatchReminderViewModelTests` (6), `WatchReminderViewRegressionTests` (1), `WatchSyncPipelineTests` (15). Run: local `scripts/test.sh:277-282`, CI `ci.yml:467-472`.

### `SingleThreadWatchUITests/` (XCTest) — 15 methods / 3 files
- `SingleThreadWatchUITests.swift` (1 audit), `SingleThreadWatchUITestsFlows.swift` (13; private `launchApp()` `:298-304`), `SingleThreadWatchUITestsLaunchTests.swift` (1; `runsForEach = true` `:6-7`, only explicit true in repo).
- Run: local `scripts/test.sh:248-255` (build-for-testing with both watch filters) → `:269-274` (UI run) → `:277-282` (unit run); CI `ci.yml:447-465` (build-for-testing + UI test; unit separate at `:467-472`).

## Build/verify gotchas

- **Destination pinning**: name-only `iPhone 17` is ambiguous with multiple runtimes → hangs. `scripts/test.sh:22-48` resolves name→UDID (`simctl list devices available | grep -F "$name ("`) and rewrites `SIM` to `id=…`; `make` accepts `SIM=`. CI pins by matrix name (booted per job); watch pinned by `id=$WATCH_UDID` after `simctl create`.
- **One xcodebuild test process at a time** (simulator contention). Local `Busy`/`RequestDenied` → `xcrun simctl shutdown all` + kill orphaned `xcodebuild`/`xctest`. CI enforces via `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` on all 4 iOS jobs (`ci.yml:78-79,:151-152,:221-222,:291-292`); watch job has neither.
- **Simulator pre-boot**: `scripts/test.sh:33-35` (`simctl boot` + `bootstatus -b`); CI per-job pre-boot `ci.yml:51-55` etc. Watch sim is NOT pre-booted by `test.sh` (xcodebuild brings it up); local watch runs may need pairing (`simulator-pairing` skill) — CI creates a standalone unpaired watch (`ci.yml:429-440`).
- **Watch dylib injection (local only)**: `scripts/test.sh:256-268` copies Xcode's `lib_TestingInterop.dylib` into `$DERIVED_DATA/Build/Products/Debug-watchsimulator/SingleThreadWatchUITests-Runner.app/Frameworks/` — this machine's watchOS 26.5 simruntime lacks it; CI's ships it. Run path is `Debug-watchsimulator` (not iOS).
- **macOS passes**: `CODE_SIGNING_ALLOWED=NO` always (`scripts/test.sh:291`, `Makefile`, `ci.yml:299,309`); unsigned bundle → real host StoreKit entitlements visible to `hostStoreKitIsClean`; real host EK store (TCC-gated) backs `EKEventStore()` fixtures. Known pre-existing local failures: `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` (CI mac-tests green on fresh runners — don't debug; annotate).
- **Unit-test naming**: Swift Testing names must NOT start with `test`/`testing` (SwiftFormat strips them). XCTest (UI) names keep `test…`. Force-unwrapping banned outside test code (`SingleThreadTests/.swiftlint.yml` relaxes).
- **XCTest runtimes**: each UI test run leaves ~3 GB runtime under `~/Library/Developer/XCTestDevices`; `scripts/test.sh:52-83` prunes >`RUNTIME_AGE_HOURS` (default 1) old ones.
- **Debug build only**: `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental builds fast; Release uses `dwarf-with-dsym`.
- **Deploy-target guard**: `scripts/test.sh:110-192` fails unless pbxproj has 20 matching `IPHONEOS=18.7`/other=26.5 literals and Package.swift has 3 matching `.iOS()/.watchOS()/.macOS()` floors.
- **CI env override**: `DEVELOPMENT_TEAM=` (empty) appended in every CI job; DerivedData cached per job with `hashFiles` on source dirs (mac cache excludes UI test dirs `ci.yml:319-327`).
- **Test counts**: source `@Test` = 520 (SingleThreadTests), 44 (watch unit); executed counts (e.g. 564 in VAR-790) exceed source counts due to `@Test(arguments:)` expansion.