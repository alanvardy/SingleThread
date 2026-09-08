# Conventions — SingleThread test/verify appendix

Shared factual appendix for Design/Structure/Plan. All paths relative to repo
root; verified against working tree at HEAD d216b6f. Do not re-open
`Makefile`, `scripts/test.sh`, or the test files for these facts; re-verify
anything you extend.

## Canonical commands

### Build / test / check (Makefile)
- `make build` — xcodebuild scheme SingleThread, `-destination '$(SIM)'` (default `platform=iOS Simulator,name=iPhone 17`, Makefile:4), Debug, `-derivedDataPath DerivedData`, `build-for-testing` (Makefile:24-26)
- `make watch-build` — scheme SingleThreadWatch, `$(WATCH_SIM)` = `generic/platform=watchOS Simulator` (Makefile:6, 28-30)
- `make test` → `./scripts/test.sh --unit-only` (Makefile:112-113)
- `make ui-test` → `./scripts/test.sh --ui-only` (Makefile:115-116)
- `make watch-test` — scheme SingleThreadWatch, `WATCH_TEST_SIM` (default `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`, Makefile:8), `-only-testing:SingleThreadWatchTests` (Makefile:133-134)
- `make watch-ui-test` — same but `-only-testing:SingleThreadWatchUITests` (Makefile:126-127)
- `make check` → `./scripts/test.sh` full pipeline (Makefile:142-143)
- `make mac-test` — macOS native `-only-testing:SingleThreadTests` (Makefile:34-36)
- `make periphery` — `periphery scan --strict -- -destination "$(SIM)"` (Makefile:148-149)
- `make lint` — `swiftformat --lint` on 8 dirs + `swiftlint lint --strict` (Makefile:144-146)
- `make format` — `swiftformat` same dirs + `swiftlint --fix` (Makefile:147)

### Full gate `scripts/test.sh` (CI-identical)
- Constants: `SIM` iPhone 17 (test.sh:9), `WATCH_SIM` generic watchOS (test.sh:10), `WATCH_TEST_SIM` "Apple Watch Series 11 (46mm)" (test.sh:15), `MAC_SIM platform=macOS` (test.sh:16)
- Full-mode order (test.sh): 211-217 iOS app build-for-testing → 219-224 watch build → 231-237 iOS UI test (`-only-testing:SingleThreadUITests`) → 239-244 watch build-for-testing (both watch suites) → 261-266 watch UI test → 269-274 watch unit test → 277-285 macOS native unit test (`-only-testing:SingleThreadTests`)
- `--unit-only`: single macOS-native run of `SingleThreadTests` (test.sh:292-297); `--ui-only`: iOS UI build + test (test.sh:306-320)
- Gate staging: phase workers use targeted `-only-testing:` suites only; the full gate runs once as a dedicated async gate subagent (run-gate skill)

### Coverage (Makefile:40-76)
- `make coverage` — `-enableCodeCoverage YES -only-testing:SingleThreadTests`, bundle `build/Coverage.xcresult`, `xcrun xccov view --report`
- `make coverage-ui` — `-only-testing:SingleThreadUITests`, `build/Coverage.UI.xcresult`
- `make coverage-all` — no filter, `build/Coverage.All.xcresult`
- No `-configuration` passed; bundles gitignored (`.gitignore:4,11,46`); **no coverage bundle or percentage has ever been recorded in-repo**

### Test counting (scripts/count_tests.sh)
- Live-greps, all numbers reproduce (fresh run: unit_tests 565 = iOS 521 + watch 44, expect 1197, require 73, mean 2.25, launches 3, unnamed_expect 1009); hardcoded per-line comments are **stale** (describe pre-slimming tree)
- `settle_sleeps` + `forced_400ms` patterns are **dead**: reference `eventKitSettleDelay` / literal `400_000_000` which do not exist anywhere; the real 200 ms settle is `ReminderStore.swift:39` (typealias `ReminderStoreSettle` 10-12)

## Test-suite inventory

### unit: SingleThreadTests/ — Swift Testing (`@Suite`/`@Test`, NOT XCTest)
- **Fixture/helper files**: `BackgroundTestFixtures.swift` (jpegData), `LocalizationTestHelpers.swift` (`String.en(...)`, `Bundle.core`), `StubBundle.swift` (StubBundle), `ReminderStoreGateTests.swift` (noopSettle:8, makeStore:154, seededCounter:163, makeReminder:169, sharedTestEventStore:177)
- Largest files (lines): ReminderStoreTests 1143 (5 suites: ReminderStoreTests:15, SkipCountTests:511, UndoCompletionTests:748 `#if !os(watchOS)`, ReloadPendingCompletionTests:926, MakeReminderTests), SkippedReminderSyncServiceTests 660 (SkippedReminderSyncServiceTests + SkipCountSyncTests; `#if os(iOS) || os(watchOS)` at :1-4), EventKitStoringTests 581 (3 suites at 148/376/523, first two `#if !os(watchOS)`), BackgroundImageStoreTests 532, SettingsViewTests 432, LocalizationTests 359, ReminderDictationParserTests 351, ReminderDictationTests 332, MicrophoneToggleTests 323, ReminderSkipTests 284 (contains ReminderSortTests), ContentViewModelTests 283, SingleThreadTests 251 (contains ReminderDateFilter coverage), StaleReminderRecheckerTests 200, UITestingSeedTests 182 (16 `@Test`, `@Suite(.serialized)` :9)
- Platform gating in this dir: `#if os(iOS)` in ActionButtonTests; `#if !os(watchOS)` suites listed above; `#if os(macOS)` MenuBarExtraOptionsTests:7; `#if os(iOS) || os(watchOS)` SkippedReminderSyncServiceTests:1-4
- `file_length` disabled files: ReminderStoreTests.swift:8, SkippedReminderSyncServiceTests.swift:11 (also Core ReminderStore.swift:8, app ContentView.swift:8); threshold warn 650/err 800 (`.swiftlint.yml:33-35`)
- Force-unwrapping banned outside tests; fixtures relax via `SingleThreadTests/.swiftlint.yml`
- Test names must NOT start with `test`/`testing` (SwiftFormat strips → phantom diffs)

### unit: SingleThreadWatchTests/ — Swift Testing
- 8 files / 1,400 lines: WatchSyncPipelineTests 576 (WatchSyncPipelineTests + WatchEnableActionButtonsSyncTests:526; contains `WatchFakeSession` 9-29, `inListReminder` 568-576, `makeService` 478-521, `makePreference` 468-477), ShowCompletionGlowStateTests 284 (contains `sharedWatchEventStore`:11, `watchReminder` 15-20), WatchReminderViewModelTests 230 (`makeWatchReminderViewModel` 28-51), ReminderStoreWatchTests 173 (suite :26; `sharedWatchEventStore`:10, `watchReminder` 14-18), ShowEnableActionButtonsStateTests 63 (state-holder; `clearKey` 59-62), WatchReminderViewRegressionTests 46 (`canvasReminder` 19-26), WatchAppViewModelTests 28
- Gating: whole target runs only under `-only-testing:SingleThreadWatchTests` (make watch-test); no `#if os` in this dir
- Fixture idiom: per-file `sharedWatchEventStore`/`watchReminder` (file-private; "InMemoryEventStore.makeReminder is iOS-only" comment WatchReminderViewModelTests:11); key prefix `wtest-*` vs iOS `test-*`

### UI smoke: SingleThreadUITests/ — XCTest
- 2 files: `SingleThreadUITests.swift` (`testLaunchAndRenderSmoke`, `--ui-testing` launch at :28), `SingleThreadUITestCase.swift` (base class **entirely dead** — 0 references, nothing subclasses it; excluded from periphery via `.periphery.yml:15-16`)
- XCTest names KEEP `test…` (SwiftFormat-excluded: `--exclude SingleThreadUITests`)
- Launches with `["--ui-testing"]` (SingleThreadUITests.swift:28); launchSeeded = `["--seed", json, "--ui-testing-noop-settle", "--ui-testing-reduced-glow"]` (SingleThreadUITestCase.swift:23-25) — but the helper itself is unreferenced

### UI smoke: SingleThreadWatchUITests/ — XCTest
- 1 file: `SingleThreadWatchUITests.swift` (`--ui-testing` launch :35; priority marker assert 19-23); comment :30-31 relocated from deleted Flows file (var-819)
- Watch UI tests use a standalone (unpaired) watch sim; `scripts/test.sh` pins `WATCH_TEST_SIM` (test.sh:15)

### Accessibility
- `testAccessibilityAudit()` in iOS UI suite (XCTest); SwiftLint `accessibility_label_for_image`/`accessibility_trait_for_button`; local audit runs extra `.hitRegion`/`.dynamicType` strictness beyond CI — local-only failures possible

## Build/verify gotchas
- **Destination pinning**: name-only `iPhone 17` destination is ambiguous with multiple runtimes — pin `,OS=<ver>` or `,id=<UDID>`; never a bare `name=` hang; Makefile/test.sh accept `SIM=` override
- **One xcodebuild test process at a time** (simulator contention); on `Busy`/`RequestDenied`: `xcrun simctl shutdown all` + kill orphaned `xcodebuild`/`xctest`; pairing is troubleshooting-only
- **`make periphery` reads a stale build index after branch switches** — clean `DerivedData/` and rerun
- **Skipped-watch tests can hang with ambiguous watch sim names** — WATCH_TEST_SIM override (Makefile:7-8)
- All 27 `@Suite` are `@Suite(.serialized)` — no parallel unit suites; serialization reasons: real UserDefaults/AppGroup keys (ShowCompletionGlowStateTests 22-26, EnableActionButtonsSyncTests 9-12, ShowEnableActionButtonsStateTests 6-9, WatchSyncPipelineTests 521-525, ReminderStoreGateTests seededCounter 163-167), MainActor timing (CompletionGlowTests 10-12, ResumptionGateTests 6-10), shared file-scoped EKEventStore (ListContentTests:6, ReminderStoreGateTests:177, ReminderStoreWatchTests:24), host StoreKit (EntitlementStoreTests)
- **Known local-only macOS failures** (don't debug): `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary — CI green on fresh runners
- Real-time waits that tests tolerate: 200 ms settle (ReminderStore.swift:39, injectable via `settle:`/`--ui-testing-noop-settle`), glow auto-dismiss 0.5 s (CompletionGlow.swift:27-38) / 2.0 s `--ui-testing-glow` / 0.1 s `--ui-testing-reduced-glow`, ~1 s refreshMinimumDisplayDuration pad (WatchReminderViewModel.swift:96/118/156; awaited WatchReminderViewModelTests.swift:74), 5 s confirmation (ReminderDictation.swift:201)
- **Persisted values shared with the watch round-trip `AppGroup.defaults`** (suite `group.app.alanvardy.SingleThread`, AppGroup.swift:8), never `UserDefaults.standard` bare — on simulators the suite always exists so the two diverge; `resetPersistedState()` wipes 24 keys from BOTH (UITestingSeed.swift:62-70)
- SwiftLint runs `--strict` in CI (every warning = error); `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide (per-target overrides in pbxproj, never CLI)
- New test suites need explicit `-only-testing:` entries in `Makefile` `test`/`watch-test` targets AND `scripts/test.sh` (and CI matrix for new targets)
- Gate staging: full `./scripts/test.sh` runs exactly once per task, as a dedicated async gate subagent in a managed worktree (run-gate skill); workers verify with targeted `-only-testing:` suites only