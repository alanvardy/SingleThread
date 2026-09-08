# Project Conventions — SingleThread

## Canonical commands

- **Full CI-identical gate (only via `run-gate` skill, worktree)**: `./scripts/test.sh` — formats, lints (`swiftlint --strict`), builds iOS (`build-for-testing`) + watch, Periphery, then UI tests (iOS + watch), watch unit tests, macOS unit tests (`scripts/test.sh:110-218`). Modes: `--unit-only` (macOS native `SingleThreadTests`), `--ui-only` (`scripts/test.sh:267-322`).
- **Makefile targets** (`Makefile`): `make build` (iOS sim, Debug, `build-for-testing` :11-13), `make watch-build` (:15-17), `make test` = `test.sh --unit-only`, `make ui-test` = `--ui-only`, `make watch-test` / `make watch-ui-test` (single-demand watch suites :73-100), `make mac-test` (:21-23), `make check` = full `test.sh`, `make lint` (`swiftformat --lint` + `swiftlint lint --strict` :104-107), `make format` (:109-112), `make periphery` (`periphery scan --strict -- -destination "$SIM"` :114-118), `make simverify` / `make coverage*`.
- **Destination pinning**: `SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); default `WATCH_TEST_SIM` = `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (watch XCTests require a concrete device). Name-only iOS is ambiguous with multiple runtimes — `scripts/test.sh:33-42` resolves to `,id=<UDID>` and pre-boots; the Makefile does not, so pass `SIM='platform=iOS Simulator,id=…'` or `SIM=…,OS=<ver>` for ad-hoc runs. Override via `SIM=` / `WATCH_TEST_SIM=` env.
- **Targeted suites**: `xcodebuild -scheme SingleThread -destination "$SIM" -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests` (iOS sim) or `platform=macOS` + `CODE_SIGNING_ALLOWED=NO` for macOS-native unit tests (`scripts/test.sh:253-260`). Swift Testing filter syntax: `-only-testing:SingleThreadTests/RescheduleSheetTests` (class) or `.../rescheduleSheetTextButtonsKeepNativeChrome` (single test); XCTest: `-only-testing:SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke`.
- **Parallelism constraints**: one xcodebuild test process at a time (simulator contention); CI disables parallel sim clones (`ci.yml:90-103, 145-157` — `-maximum-concurrent-test-simulator-destinations 1`). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all` + kill orphaned `xcodebuild`/`xctest`. Watch UI tests use a standalone (unpaired) watch sim — CI creates one (`ci.yml:211-229`); pairing (`xcrun simctl pair`) is only a troubleshooting step.
- **XCTest runtime cleanup**: `scripts/test.sh:44-75` prunes stale runtimes in `~/Library/Developer/XCTestDevices` older than `RUNTIME_AGE_HOURS` (default 1); each UI run leaves a ~3 GB runtime.
- **Deployment-target guard**: `verify_deployment_target` in `scripts/test.sh:80-208` — 20 `*_DEPLOYMENT_TARGET` literals in `SingleThread.xcodeproj/project.pbxproj` + 3 package floors in `SingleThreadCore/Package.swift` must match (iOS 18.7; macOS/watchOS 26.5).
- **CI jobs** (`ci.yml`): `unit-tests` (matrix iPhone 17 + iPad (A16), iOS sim :6-126), `ui-tests-smoke` (iPhone 17, `testLaunchAndRenderSmoke` only :128-189), `mac-tests` (macOS-native unit :191-240), `lint` (swiftformat + swiftlint --strict + watch build + periphery :242-285), `watch-ui-tests` (fresh unpaired watch sim :287-369). Xcode 26.6 (`setup-xcode` :21).
- **Local-only pre-existing failures** (macOS `EntitlementStoreTests`): `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` — green on CI fresh runners; don't debug.
- **Periphery**: `make periphery` reads a stale build index after branch switches — clean `DerivedData/` and rerun. Full gate uses `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` (`scripts/test.sh:167-169`).
- **Watch UI runner local fix**: `scripts/test.sh:183-196` embeds `lib_TestingInterop.dylib` (from `/Applications/Xcode.app/.../WatchSimulator.platform/.../usr/lib/`) into the watch UI test runner — local gate only, CI runtime already includes it.

## Test-suite inventory

### SingleThreadTests (Swift Testing; runs macOS-native AND iOS-sim in CI)
- `RescheduleSheetTests.swift:1-47` — iOS sheet static helpers only (hasDueTime/displayedComponents/dateComponentsMask); no View construction.
- `SingleThreadTests.swift:142-151` — `rescheduleSheetTextButtonsKeepNativeChrome`: full `ContentView` + `String(describing: view.actionMenuRescheduleSheet)` contains `"Cancel"`, not `"SingleThreadButtonModifier"`.
- `ContentViewModelTests.swift:70-78` — nudge-sheet openInReminders URL test. `ReminderStoreTests.swift:732,754` — reschedule skip-count/recurrence. `EventKitStoringTests.swift:274-345` — reschedule persistence. `RescheduleSyncTests.swift:11-97` — watch→phone relay. `ReminderDictationParserTests.swift:142-143` — dictation text.
- View-structure assertion pattern (sibling suites): `SingleThreadButtonModifierTests.swift:14`, `MacOSActionButtonChromeTests.swift:14-39`, `SettingsCaptionTests.swift:10`, `SwipePromptTests.swift:12` — all `String(describing:)` + `.contains(...)`.
- Many suite files covering the rest of the app (settings, preferences, completion, storage, UI helpers); see `ls SingleThreadTests/`.

### SingleThreadUITests (XCTest, iOS simulator; SwiftFormat-excluded)
- `SingleThreadUITests.swift` — single `testLaunchAndRenderSmoke` (launch `--ui-testing`, wait for staticTexts with `waitForExistence(timeout: 5)`); no reschedule coverage.

### SingleThreadWatchTests (Swift Testing, watch sim)
- `ReminderStoreWatchTests.swift:96-149` — reschedule relay hook fires / gated no-op. Others cover VM/state logic (`WatchAppViewModelTests`, `WatchReminderViewModelTests`, `WatchReminderViewRegressionTests`, `ShowEnableActionButtonsStateTests`, `ShowCompletionGlowStateTests`, `WatchSyncPipelineTests`). **No reschedule view tests.**

### SingleThreadWatchUITests (XCTest, watch sim)
- `SingleThreadWatchUITests.swift:11-39` — `testLaunchAndRenderSmoke` + `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` (:26-27); queries identifiers as `app.staticTexts[...]`.

## Build/verify gotchas

- `--ui-testing` / `--seed '<json>'` launch-arg seams back tests; `--seed` (via `InMemoryEventStore`) is the standard deterministic-write seam for iOS UI tests (see AGENTS.md).
- SwiftFormat excludes only `SingleThreadUITests` (`.swiftformat` `--exclude`), not `SingleThreadWatchUITests` — watch XCTest names keep `test…`.
- Unit-test (Swift Testing) names must NOT start with `test`/`testing` (SwiftFormat's organizeDeclarations strips the prefix and silently renames — phantom diffs).
- `swiftlint lint --strict` treats every warning as error; variable names ≥ 3 chars (exceptions `id`, `e`, `d`, `rt`, `to`, `gvm`); force-unwrapping banned outside tests (`SingleThreadTests/.swiftlint.yml` relaxes).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; scope overrides in pbxproj, never CLI.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch app targets (async fns default `@MainActor`); `SingleThreadCore`/widget/test targets do NOT — annotate `@MainActor` explicitly there.
- Persisted values shared with watch must round-trip via `AppGroup.defaults` (`UserDefaults(suiteName:)`), never `UserDefaults.standard`.
- New `.swift` files are auto-discovered (synchronized groups, `objectVersion = 77`); new test targets need pbxproj + scheme + `-only-testing` in `scripts/test.sh` + CI matrix entries.
- One gate re-run policy: full `./scripts/test.sh` runs once via the `run-gate` skill; phase subagents verify with targeted `-only-testing:` suites only.