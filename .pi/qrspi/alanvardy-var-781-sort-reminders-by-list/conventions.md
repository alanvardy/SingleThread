# Conventions — Shared Factual Appendix

Repo root: `/Users/vardy/dev/alanvardy-var-781-sort-reminders-by-list` (branch `alanvardy-var-781-sort-reminders-by-list`). All paths relative to repo root.

## Canonical commands

### Makefile targets (`Makefile`)
| Target | Command (effective) |
|---|---|
| `make build` | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build-for-testing` |
| `make watch-build` | `xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_SIM)' … build` |
| `make mac-build` | `xcodebuild -scheme SingleThread -destination 'platform=macOS' … CODE_SIGNING_ALLOWED=NO build` |
| `make mac-test` | macOS `test -only-testing:SingleThreadTests` |
| `make test` | `./scripts/test.sh --unit-only` |
| `make ui-test` | `./scripts/test.sh --ui-only` |
| `make check` | `./scripts/test.sh` (full gate) |
| `make watch-test` / `make watch-ui-test` | watch scheme, concrete `WATCH_TEST_SIM`, `-only-testing:SingleThreadWatchTests` / `…WatchUITests` |
| `make lint` | `swiftformat --lint <all dirs>` + `swiftlint lint --strict` |
| `make format` | `swiftformat <all dirs>` + `swiftlint --fix` |
| `make periphery` | `periphery scan --strict -- -destination "$SIM"` |
| `make coverage[-ui|-all]` | `xcodebuild … -enableCodeCoverage YES` + `xcrun xccov view` |
| `make clean` / `make simverify` | clean / `scripts/simverify.sh` |

Destination variables (`Makefile:1-7`): `SIM ?= platform=iOS Simulator,name=iPhone 17` (no OS pin — ambiguous with multiple runtimes; Override via `SIM='platform=iOS Simulator,id=<UDID>'`), `WATCH_SIM := generic/platform=watchOS Simulator`, `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`, `MAC_SIM := platform=macOS`. `export SIM`.

### `./scripts/test.sh` (CI-identical gate)
- Modes: `full` (default), `--unit-only`, `--ui-only` (`scripts/test.sh:120-140`).
- Pre-run: resolves a name-only `SIM` to a concrete UDID via `simctl list … grep -F "<name> ("` and pre-boots it (`scripts/test.sh:52-73`); prunes stale XCTest runner runtimes older than `RUNTIME_AGE_HOURS` (default 1h) (`:75-118`).
- Deployment-target consistency guard (`scripts/test.sh:141-241`): all `*_DEPLOYMENT_TARGET` literals must equal iOS `18.7` and macOS/watchOS `26.5` (20 pbxproj literals + 3 `Package.swift` platform floors); any drift fails the gate. `DEPLOYMENT_TARGET_IOS`/`DEPLOYMENT_TARGET_OTHER` env overrides exist.
- Full pipeline order (`scripts/test.sh:244-351`): swiftformat (write) → swiftformat `--lint` → `swiftlint lint --strict` → iOS `build-for-testing` → watch `build` → `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` → iOS unit tests (`-parallel-testing-enabled YES -maximum-test-execution-time-allowance 900`, `-only-testing:SingleThreadTests`, `test-without-building`) → UI tests (`-only-testing:SingleThreadUITests`) → watch build-for-testing + a local-only `lib_TestingInterop.dylib` embed fix for the watch UI runner (`scripts/test.sh:318-331`) → `-only-testing:SingleThreadWatchUITests` → `-only-testing:SingleThreadWatchTests` → macOS unit tests (`-only-testing:SingleThreadTests`, `CODE_SIGNING_ALLOWED=NO`).
- `.swiftformat:18` — `--exclude SingleThreadUITests` (UI tests are SwiftFormat-excluded; the Makefile still passes the dir for swiftlint).

### CI (`.github/workflows/ci.yml`)
- `macos-26` runners, `setup-xcode` pin `26.6`; four jobs each on a `matrix.device: ["iPhone 17", "iPad (A16)"]` (`ci.yml:22-27, 90-95, 154, 213`): build+unit, UI tests, watch tests, macOS. Simulator pre-boot from matrix device name (`ci.yml:48-52`); unit tests disable parallel simulator clones (`-maximum-concurrent-test-simulator-destinations 1`, `ci.yml:68-77`).

## Build/verify gotchas
- **Name-only `iPhone 17` destination is ambiguous** with multiple runtimes — pin `,id=<UDID>` or `,OS=<ver>` (AGENTS.md; `scripts/test.sh:52-73` auto-resolves in the gate itself).
- **One xcodebuild test process at a time** locally (simulator contention); on `Busy`/`RequestDenied` runner-launch failures: `xcrun simctl shutdown all` + kill orphaned xcodebuild/xctest. Watch UI tests need a paired sim: `xcrun simctl pair <watchUDID> <phoneUDID>`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide — warnings fail everywhere; scope per-target overrides in pbxproj, never CLI flags.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch app targets (don't wrap in `Task { @MainActor in }`); `SingleThreadCore` package, widget, intents, and test targets need explicit `@MainActor`. Swift 6 language mode; `SWIFT_APPROACHABLE_CONCURRENCY = YES` on app targets.
- **App Group, never `.standard`** for anything shared with the watch: `AppGroup.defaults` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:16-18`) — includes `--ui-testing`/`--seed` seams. On simulator the suite always exists so the two diverge silently.
- SwiftLint `--strict` (35 opt-in rules incl. a11y); `identifier_name` ≥ 3 chars (exceptions `id`/`e`/`d`/`rt`/`to`/`gvm`). Force-unwraps banned outside tests.
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat's `preferSwiftTesting` strips the prefix and silently renames functions under `make format` (phantom diffs). UI-test names keep `test…`.
- SwiftFormat rules: enables `blankLinesAroundMark`/`organizeDeclarations`/`preferSwiftTesting`; disables `andOperator`/`isEmpty`/`trailingClosures`/`trailingCommas`/`wrapMultilineStatementBraces` (`.swiftformat`).
- New `.swift` files are auto-discovered (synchronized groups, `objectVersion = 77`) — no pbxproj edits. New *targets* need full pbxproj + scheme + `-only-testing` + CI matrix changes.
- UI tests: querying and swipes can race the card-transition animation; `testSkipAdvancesToNextReminder` uses `swipeLeft()` on the card then waits for the next title (`SingleThreadUITestsFlows.swift:61-69`).
- Test-fixture `EKEventStore`: `makeReminder(title:priority:dateComponents:)` constructions never saved (`ReminderSkipTests.swift:204-205`); `sharedTestEventStore` at `ReminderStoreTests.swift:1096`.
- Local-only simulator quirks: watchOS 26.5 sim runtime missing `lib_TestingInterop.dylib` → gate embeds it from Xcode (`scripts/test.sh:318-331`); XCTest runner runtimes (~3 GB each) accumulate under `~/Library/Developer/XCTestDevices` and are pruned by the gate.

## Test-suite inventory

### `SingleThreadTests/` (Swift Testing, iOS unit — `-Only-testing:SingleThreadTests`)
| File | Covers |
|---|---|
| `ReminderSkipTests.swift` | `ReminderSortTests` (:134-225) — comparator chains per option, option==legacy, date/title tiers; `ReminderPriorityTests` (:57-) — rank ladder; skip logic |
| `ReminderStoreTests.swift` | `visibleReminders` ordering/exclusion (:20-108), availableLists (:111-119), excluded-title set/refresh hooks (:127-164), `setSortOptionReordersAndNotifies` (:168-217), skip persistence, gate |
| `SortOptionTests.swift` | raw values, allCases order, defaultsKey, presentation titles/icons, `SortOptionStore` fallback/round-trip |
| `EventKitStoringTests.swift` | `InMemoryEventStore`/real-store parity, raw fetch order (:454-467), availableLists dedup (:505-529) |
| `ExcludedListStoreTests.swift` | load/save round-trip, replace-not-union |
| `ReminderDisplayTests.swift` | `listName` follows calendar (:60-71) |
| `BoolPreferenceStoreTests.swift` / `BoolPreferenceKeyTests.swift` | bool pref read/write, keys |
| `SkippedReminderSyncServiceTests.swift` | context push/pop payloads (see also watch suite) |
| `SettingsViewTests.swift` | `settingsViewContainsNavigationLinkLabels` (:28-58), `filterSortSettingsViewContainsExpectedRows` (:165-189, body-string reflection, macOS branch :182-187) |
| `SettingsViewModelTests.swift` | smoke test |
| `ListContentTests.swift` | `ListContent` states |
| `UITestingSeedTests.swift` | seed schema / reset behavior |
| `ContentViewModelTests.swift` | view-model State; **no `handleSortOption` test** |
| `AppGroupTests.swift`, `CompletionCounterStoreTests.swift`, `EntitlementStoreTests.swift`, `SkipCountStoreTests.swift`, `PendingCompletion*`, `UndoStoreTests.swift`, `ShowDate/ShowRecurrence/ShowAlarms/ShowCompletionGlowTests.swift`, `MicrophoneToggleTests.swift`, `LocalizationTests.swift`, `ReminderDictationTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `Background*`, `CardPlate*`, `AppearanceModeTests.swift`, `TextSizeTests.swift`, `RescheduleSheetTests/RescheduleSyncTests/EnableActionButtonsSyncTests/EntitlementSyncTests`, `SwipePromptTests`, `PendingCompletionLogicTests`, `ReminderIntentsTests`, `ReminderDeepLinkTests`, `TranscriptionAccumulatorTests`, `CodeSpanFormatterTests`, `URLOpeningTests`, `PrivacySettingsContentTests`, `AboutViewTests`, `AppDelegateTests`, `AppInfoTests`, `MinimumDisplayDurationTests`, `ResumptionGateTests`, `ReminderStoreGateTests`, `ActionButtonTests`, `ActionMenuGateTests`, `BackgroundFadeTests`, `ColorCrossPlatformTests`, `StubBundle`, `LocalizationTestHelpers`, `SingleThreadTests.swift` (suite) | misc unit coverage |
Watch note: unit tests use `import Testing` / `@Test`; names without `test` prefix.

### `SingleThreadUITests/` (XCTest, iOS UI — `-Only-testing:SingleThreadUITests`)
| File | Covers |
|---|---|
| `SingleThreadUITestCase.swift` | `launchSeeded(_:extra:)` (:29-31), `launchApp(arguments:)` (:16-26), `assertTogglePersists` (:45-55) |
| `SingleThreadUITestsFlows.swift` | `testListShowsSeededReminder` (:23-31), `testSkipAdvancesToNextReminder` (:54-72, **only direct order assertion**), `testPriorityMarker…` (:74-85), cross-device completion (:110-147), complete/delete swipes (:149-182), `testSettingsOpensAndShowsControls` (:222-251) |
| `ActionButtonsUITests.swift`, `ActionMenuUITests.swift`, `SkipNudgeUITests.swift` | action buttons/action menu/skip-nudge flows (`--ui-testing` seam for action buttons) |
| `NotificationsUITests.swift`, `NotificationsSettingsUITests.swift`, `NotificationSchedulingUITests.swift` | notification settings/intervals |
| `SingleThreadUITestsAppearanceLaunchTests.swift` | appearance picker (:48-116), launch/text-size picker |
| `SingleThreadUITestsLaunchTests.swift` | launch/deeplink |

### `SingleThreadWatchTests/` (Swift Testing, watch unit — `-Only-testing:SingleThreadWatchTests`)
`WatchSyncPipelineTests.swift` (sort transport push/receive/absent-key, :47-170), `ReminderStoreWatchTests.swift`, `WatchAppViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`, `ShowCompletionGlowStateTests.swift`, `ShowEnableActionButtonsStateTests.swift`.

### `SingleThreadWatchUITests/` (XCTest, watch UI — `-only-testing:SingleThreadWatchUITests`)
`SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift` (all use the watch `--ui-testing` seam).

## Seams
- `--seed '<json>'` iOS UI-test seam: `UITestingSeed.swift` schema (`reminders[].title/notes/priority`; top-level `calendars`/`excludedLists`/`completionCount`/`skipCounts`/`isEntitled`/`hasHidden`/`entitlementUnresolved`); consumed `AppViewModel.swift:244-349`; resets 24 persisted keys incl. `sortOption` on every launch.
- Watch `--ui-testing` seam: legacy arg-driven fake-store mode (used by `ActionButtonsUITests`-style flows; watch UI tests use it).
- iOS deep-link "View in Reminders" via reminder id (`ContentViewModel.swift:201`).