# Conventions — shared factual appendix

Canonical commands, test inventory, and build/verify gotchas. Line refs verified against the working tree.

## Canonical verify commands

- Full gate (identical to CI): `./scripts/test.sh` (formats, lints, builds, Periphery, unit + UI tests, SwiftFormat + SwiftLint). Flags: `--unit-only`, `--ui-only` (`scripts/test.sh:88-96`).
- Quick loops via make (`Makefile`):
  - `make build` — `xcodebuild build-for-testing`, Debug, `-destination '$(SIM)'` (`Makefile:17-18`)
  - `make test` — iOS unit tests (`Makefile:75`), `make ui-test` (`Makefile:78`), `make mac-build` (`Makefile:24`), `make mac-test` — unit only, `-destination '$(MAC_SIM)'` (`Makefile:26-27`), `make mac-run` (`Makefile:30`)
  - `make lint` (SwiftLint `--strict`), `make format` (SwiftFormat), `make periphery` (Periphery `--strict` scan)
- Destinations: `SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); `MAC_SIM := platform=macOS` (`Makefile:8`); `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (`Makefile:7`). Override with `SIM=`.
- Targeted suites: `xcodebuild … -only-testing:SingleThreadTests` (Swift Testing, iOS + macOS) / `-only-testing:SingleThreadUITests` (XCTest, iOS only) / `-only-testing:SingleThreadWatchUITests` / `-only-testing:SingleThreadWatchTests` (`scripts/test.sh:232-255, :288-292`).
- macOS unit tests: `platform=macOS`, `-only-testing:SingleThreadTests` (`Makefile:26-27`; `scripts/test.sh:288-292`; CI `ci.yml:270, :297, :308`).

## Test-suite inventory

### SingleThreadTests/ (Swift Testing; runs on iOS sim AND on macOS via `-only-testing:SingleThreadTests`)

Settings surface & backing prefs:
- `SettingsViewTests.swift` — SettingsView rows + sub-view row labels via `String(describing: view.body)`; bag round-trips (showCompletionGlow/showSwipePrompt/showUndoButton). Contains in-test `#if os(iOS)` variants (`:57, :79`) — not whole-file gated.
- `SettingsViewModelTests.swift`, `AboutViewTests.swift`, `PrivacySettingsContentTests.swift` — settings-adjacent views.
- Preference round-trip suite (AppStorage defaultAndRoundTrips): `ShowAlarmsPreferenceTests.swift:7`, `ShowCompletionGlowPreferenceTests.swift:7`, `ShowDatePreferenceTests.swift:7`, `ShowListPreferenceTests.swift:7` (disabled-by-default variant), `ShowRecurrencePreferenceTests.swift:7`.
- `UITestingSeedTests.swift` — `--seed` parser + `resetPersistedState` coverage.

Core/content (grouped by name): store & persistence — `ReminderStoreTests`, `EventKitStoringTests`, `ReminderSkipTests`, `ExcludedListStoreTests`, `UndoStoreTests`, `PendingCompletionStoreTests`, `PendingCompletionLogicTests`, `CompletionCounterStoreTests`, `EntitlementStoreTests`, `EntitlementSyncTests`, `SkippedReminderSyncServiceTests`, `AppGroupTests`; state gates — `ReminderStoreGateTests`, `ResumptionGateTests`; display/UI logic — `ReminderDisplayTests`, `BackgroundCardTests`, `BackgroundFadeTests`, `BackgroundPhotoLayerTests`, `BackgroundImageStoreTests`, `CompletionGlowTests`, `SwipePromptTests`, `CardPlateTests`, `CardPlateModifierTests`, `MicrophoneToggleTests`, `MinimumDisplayDurationTests`, `TextSizeTests`, `SortOptionTests`, `AppearanceModeTests`, `ColorCrossPlatformTests`, `ActionButtonTests`; parsing — `ReminderDictationTests`, `ReminderDictationParserTests`, `CodeSpanFormatterTests`, `ReminderRecurrenceFormatterTests`, `TranscriptionAccumulatorTests`; app — `AppDelegateTests`, `AppInfoTests`, `ReminderDeepLinkTests`, `ReminderIntentsTests`; localization — `LocalizationTests` (+ `LocalizationTestHelpers.swift`); fixtures — `BackgroundTestFixtures.swift`, `StubBundle.swift`.

### SingleThreadUITests/ (XCTest; iOS simulators only — never macOS)

- `SingleThreadUITestCase.swift` — helpers: `launchApp` `:24-27`, `launchSeeded` `:29-31` (`--seed`), `flipToggle` `:35-43`, `assertTogglePersists` `:45-52`.
- `SingleThreadUITestsFlows.swift` — main settings flows (row navigation, background/pin persistence, reminder toggles, glow, swipe prompt, undo, purchase row/sheet) `:185, :222, :262, :327, :386, :429, :517, :594, :689, :704`.
- `SingleThreadUITests.swift` — accessibility audit (`:27`); `SingleThreadUITestsLaunchTests.swift` — launch; `SingleThreadUITestsAppearanceLaunchTests.swift` — appearance picker flows (`:60, :94`); `ActionButtonsUITests.swift` — action buttons.
- Notifications (not in CI `-only-testing:` fragments — local `make ui-test` only): `NotificationsUITests.swift` (full flow `:47`, a11y audit `:103`), `NotificationsSettingsUITests.swift` (toggle `:6`, interval picker `:23`), `NotificationSchedulingUITests.swift` (`:40, :64, :90, :113`).

### Watch tests (`SingleThreadWatchUITests/`, `SingleThreadWatchTests/`)

- UI: `SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift` — driven by `--ui-testing` seam (docs: AGENTS.md).
- Unit: `ReminderStoreWatchTests.swift`, `ShowCompletionGlowStateTests.swift`, `WatchAppViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`, `WatchSyncPipelineTests.swift`.

## Build/verify gotchas

- **Destination pinning**: name-only destinations hang with multiple runtimes — pin `,OS=` or `,id=` (`scripts/test.sh:41-47` resolves UDID + preboots). Default sim `iPhone 17`; CI matrix adds `iPad (A16)` (ci.yml `:25-27, :93-95, :154-156, :213`).
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied`, prune stale `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned xcodebuild/xctest. CI emits `-maximum-concurrent-test-simulator-destinations 1` for the audit job (ci.yml ~`:237`).
- **macOS = unit tests only**: `SingleThreadUITests` has no macOS destination anywhere (Makefile/test.sh/CI). `SettingsViewTests` does run on native macOS.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide (`AGENTS.md`) — warnings fail builds; scope overrides in pbxproj, never CLI flags.
- Unit-test names must NOT start with `test`/`testing` (SwiftFormat strips/renames them); XCTest UI-test names keep `test…` and are SwiftFormat-excluded.
- SwiftLint `--strict`: every warning is an error; identifiers ≥ 3 chars.
- Settings sheet is never auto-presented by launch args — UI tests always tap `settingsButton` (`ContentView.swift:171`); `--seed` resets persisted prefs for deterministic defaults (`UITestingSeed.swift:69-90`); `--ui-testing` = in-memory store + no EventKit prompt (`AppViewModel.swift:245-275`).
- Persistence shared with watch must round-trip through `AppGroup.defaults` (App Group suite), never `UserDefaults.standard` (`AppGroup.swift`; AGENTS.md).
- Test/verify order after changes: `make format` → `make lint` → `make build` → targeted `-only-testing:` suites; the full `./scripts/test.sh` runs once by the parent after phases commit.