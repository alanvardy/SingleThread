# Conventions — Shared Factual Appendix

For Design/Structure/Plan. All paths relative to repo root; every fact carries a `file:line`.

## 1. Canonical commands

| Intent | Command | Where |
|---|---|---|
| Full CI-local gate (format, lint, build, Periphery, unit + UI on iOS sim, macOS, watch sim) | `./scripts/test.sh` (full mode) | `scripts/test.sh:196-296` |
| Unit only / UI only | `./scripts/test.sh --unit-only` / `--ui-only` | `test.sh:298-336` |
| Makefile wrappers | `make test` (= `--unit-only`) / `make ui-test` / `make check` (full) / `make mac-test` / `make watch-ui-test` / `make watch-test` | `Makefile:75-101` |
| Coverage bundle + xccov report | `make coverage` / `coverage-ui` / `coverage-all` → `build/Coverage*.xcresult` | `Makefile:37-73`; bundles `Makefile:10-12` |
| Format / lint / Periphery | `make format`, `make lint`, `make periphery` | `Makefile:106-114` |
| Test census (grep, not timer) | `./scripts/count_tests.sh` (JSON via `--write <file>`) | `scripts/count_tests.sh:7-43` |

- Per-test durations from an existing bundle: `xcrun xcresulttool get test-results tests --path <bundle>` (leaf schema: `durationInSeconds`, no per-test startTime). Summary: `get test-results summary`. Section durations: `get log --type action|build`.
- Only CI passes `-showBuildTimingSummary` (build steps only): `ci.yml:63,131,192,251,302,363,418`. Neither `scripts/test.sh` nor the Makefile captures any phase/step timing.

## 2. Test-suite inventory

### iOS unit — `SingleThreadTests/` (61 files, 470 `@Test`, Swift Testing)

| File | Covers | Platform gating / notes |
|---|---|---|
| `ReminderStoreTests.swift` | store: skip/complete/undo/delete/reschedule/reset-skip-count, reload + pending-completion pruning (suite `:15` + nested `:511,:720,:898`) | `UndoCompletionTests` `#if !os(watchOS)` (`:720`) |
| `ReminderStoreGateTests.swift` | freemium gate (count-at-100 × entitled truth table) | |
| `EventKitStoringTests.swift` | `FakeEventStore` write/lifecycle/available-lists suites (`:148,:355,:502`) | write suites `#if !os(watchOS)` |
| `ReminderSkipTests.swift` | skip-identifier add/prune/intersect, priority level/marker/displayName mapping | |
| `PendingCompletionLogicTests.swift` | pending-completion filtering/removal | |
| `SkippedReminderSyncServiceTests.swift` | WCSession sync push/receive, skip counts, exclusions, show-* prefs, isEntitled, delete/reschedule relay | |
| `EntitlementSyncTests.swift`, `EnableActionButtonsSyncTests.swift`, `EnableActionButtonsMigrationTests.swift` | sync-pushed entitlement/action-button keys on real UserDefaults | each serialized |
| `WatchSyncPipelineTests.swift` (watch target below also uses it) | write-pipeline sync | |
| `EntryPoint*` logic: `SortOptionTests`, `ReminderDateFilter` (via store), `ListContentTests`, `ReminderDisplayTests`, `ReminderDictationParserTests`, `CodeSpanFormatterTests`, `TranscriptionAccumulatorTests`, `ReminderRecurrenceFormatterTests`, `ReminderDeepLinkTests`, `ReminderIntentsTests`, `ActionMenuGateTests`, `BoolPreferenceStoreTests`, `BoolPreferenceKeyTests`, `CompletionCounterStoreTests`, `SkipCountStoreTests`, `UndoStoreTests`, `SwipePromptTests`, `ResumptionGateTests`, `PendingCompletionStoreTests` | pure logic layers | |
| `ContentViewModelTests`, `SettingsViewModelTests`, `DictationViewModel`-adjacent `MicrophoneToggleTests` | view-model behavior incl. URL-spy chains | |
| View/render: `CardPlateTests`, `CardPlateModifierTests`, `CardWidthTests`, `BackgroundCardTests` (iOS `#if os(iOS)`), `BackgroundPhotoLayerTests`, `RescheduleSheetTests`, `SettingsViewTests`, `SettingsCaptionTests`, `SettingsSubscreenLayoutTests`, `SettingsViewModelTests`, `AboutViewTests`, `PrivacySettingsContentTests`, `AppearanceModeTests`, `TextSizeTests`, `ShowAlarms/ShowDate/ShowRecurrenceTests`, `ColorCrossPlatformTests`, `BackgroundFadeTests` | view layout, bindings, rows, labels | UI tests excluded from SwiftFormat (`--exclude SingleThreadUITests`) |
| `BackgroundImageStoreTests` | wallpaper fetch/pin/refresh over fake URLSession + real temp-dir file I/O | serialized (`:8`) |
| `EntitlementStoreTests` | StoreKit `SKTestSession` liveness + entitlement seams; **no `buyProduct`** (FB22237318 comment `:48-54`) | serialized (`:8`) — one `SKTestSession` per process |
| `ReminderDictationTests`, `ActionButtonTests`, `CompletionGlowTests` | speech/dictation/action-glow with fakes | glow suites serialized (timing) |
| `UITestingSeedTests`, `AppGroupTests`, `AppInfoTests`, `StubBundle.swift`, `BackgroundTestFixtures.swift`, `LocalizationTestHelpers.swift`, `LocalizationTests`, `SingleThreadTests.swift` | seed parsing/reset, app-group keys, bundle stubs, localization, a11y extras | |

### iOS UI — `SingleThreadUITests/` (10 files, 52 XCTest)

| File | Covers |
|---|---|
| `SingleThreadUITestsFlows.swift` (29 tests, 33 launches incl. 3 relaunch-persistence trio) | skip, complete, delete, priority, All Done, deep link, settings navigation, about modal, background/pin + show-list/glow + swipe-prompt persistence, glow on/off, undo ×3, freemium gate ×4 (incl. pill-geometry and restore button) |
| `SingleThreadUITests.swift` | full a11y audit |
| `SingleThreadUITestsLaunchTests.swift` | launch + screenshot |
| `SingleThreadUITestsAppearanceLaunchTests.swift` (3) | cold-launch appearance, runtime toggle, device-follow — all `--no-reminders` |
| `ActionButtonsUITests.swift` (2) | action buttons render + a11y audit |
| `ActionMenuUITests.swift` (4) | action-menu Skip/Delete/Reschedule when toggle ON, direct swipe when OFF |
| `NotificationSchedulingUITests.swift` (4) | real UNUserNotificationCenter schedule-on-background / cancel-on-foreground / negatives via `--ui-testing-notifications` |
| `NotificationsUITests.swift` (2) | full notification flow incl. SpringBoard Allow, a11y audit of notifications settings |
| `NotificationsSettingsUITests.swift` (2) | toggle exists + interval picker options |
| `SkipNudgeUITests.swift` (4) | 6-skip nudge banner/delete/reschedule/deep link, iPad banner width |
| `SingleThreadUITestCase.swift` | base class: `launchSeeded`/`launchApp`, `flipToggle` poll (`:28-44`), `statusLabel` seam reader (`:98-107`) |

### Watch unit — `SingleThreadWatchTests/` (6 files, 38 `@Test`)

`ReminderStoreWatchTests.swift` (complete/pending/reschedule/skip on shared fixture), `ShowCompletionGlowStateTests.swift` (glow transition flags + real `.standard` key), `ShowEnableActionButtonsStateTests.swift` (toggle state round trip), `WatchAppViewModelTests.swift` (glow seam duration), `WatchReminderViewRegressionTests.swift` (view render), `WatchSyncPipelineTests.swift` (receive/send pipeline; `WatchEnableActionButtonsSyncTests` nested `:526`).

### Watch UI — `SingleThreadWatchUITests/` (3 files, 17 XCTest)

`SingleThreadWatchUITestsFlows.swift` (14: card text, priority, excluded/live-exclusion, complete/skip, action menu, nudge, delete dialog, refresh, upgrade gate, glow hold), `SingleThreadWatchUITests.swift` (tap→confirmation dialog, a11y audit), `SingleThreadWatchUITestsLaunchTests.swift` (launch + screenshot).

## 3. Platform gating

- `#if os(watchOS)` / `#if !os(watchOS)`: `ReminderStore.swift` (sync service `SkippedReminderSyncService.swift:8` is `#if os(iOS)||os(watchOS)`), watch-only stores (`PendingCompletionStore.swift:8-14` doc), `EventKitStoring.swift:50` (save/remove/makeReminder iOS-only), `UndoCompletionTests` (`ReminderStoreTests.swift:720`), `EventKitStoringTests` write suites, `BackgroundCardTests` (`:43`, `#if os(iOS)`).
- Watch `AppGroup.defaults === UserDefaults.standard` (`AppGroup.swift:16-18`, `PendingCompletionStore.swift:8-14`) — watch unit + watch UI share one effective defaults domain.
- `SingleThreadCore` package has **no** `SWIFT_DEFAULT_ACTOR_ISOLATION`; iOS/watch app targets do (`MainActor` default). Test targets do not — annotate `@MainActor` explicitly (AGENTS.md).

## 4. Build/verify gotchas (research-surfaced)

- **Simulator dest pinning**: name-only `iPhone 17` is ambiguous with multiple runtimes — pin `,id=<UDID>`; `test.sh` resolves + pre-boots (`test.sh:23-32`); `SIM=` / `WATCH_TEST_SIM=` env overrides (`test.sh:5,11`).
- **One xcodebuild test process at a time**: `Busy`/`RequestDenied` → shutdown sims, kill orphaned `xcodebuild`/`xctest` (AGENTS.md). `cleanup_xctest_runtimes` prunes only >1 h old (`test.sh:54-84,104`).
- **Local watch-runner shim**: this machine's watch simruntime lacks `lib_TestingInterop.dylib`; `test.sh:256-266` copies it into the UI-test runner bundle (CI-native, no-op where present).
- **CI parallel policy is the opposite of local**: CI disables parallel testing with `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` (EventKit SIGTRAP teardowns + clone-connection timeouts, `ci.yml:68-77,136-146,257-266`); local enables it only on the iOS unit phase (`test.sh:234`). `-retry-tests-on-failure` is CI-only (`ci.yml:144,203,264,425`).
- **SwiftLint `--strict` = warnings are errors**; identifier min 3 chars (exceptions `id,e,d,rt,to,gvm`); unit-test names must not start with `test`/`testing` (SwiftFormat silently strips → phantom renames). UI XCTest names keep `test…` (UI tests SwiftFormat-excluded).
- **Watch CI creates a fresh unpaired watch simulator** (`ci.yml:392-406`); local uses `Apple Watch Series 11 (46mm)` (`test.sh:9-11`); `xcrun simctl pair` needed for paired-sim watch tests (simulator-pairing skill).
- **`Deployment-target guard`** in `test.sh:106-193` (20 pbxproj literals + 3 package literals) aborts mismatches before any build.
- **Force-unwrap banned outside test code**; test fixtures relax via `SingleThreadTests/.swiftlint.yml`.
- **Seams must round-trip through `AppGroup.defaults`, never `.standard`** — on iOS sim the suite always exists so the two diverge silently (AGENTS.md; `AppGroup.swift:16-18`).
- **`--ui-testing` ≠ `--seed` semantics**: `--seed` calls `resetPersistedState()` in the app each launch (isolation); `--ui-testing` relaunches deliberately skip it (persistence tests) — don't mix assumptions (`AppViewModel.swift:257-343`, `SingleThreadUITestCase.swift:22-35`).
- **No timing instrumentation**: no `measure(`/XCTMetric/`ContinuousClock`; per-test durations only via manual `xcresulttool` on bundles produced by `coverage*` targets or ad-hoc `-resultBundlePath` runs.