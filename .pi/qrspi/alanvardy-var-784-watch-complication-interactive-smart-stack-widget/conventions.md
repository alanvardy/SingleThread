# Conventions — Shared Factual Appendix

For Design / Structure / Plan. Verified against HEAD (`467d098`). Core = `SingleThreadCore/Sources/SingleThreadCore/`.

## Canonical Commands

| Command | What it runs | Source |
|---|---|---|
| `make build` / `make test` / `make ui-test` / `make check` | build / `scripts/test.sh --unit-only` / `--ui-only` / full `scripts/test.sh` | `Makefile:75-79, 100-101` |
| `make watch-build` / `make watch-ui-test` / `make watch-test` | watch build (generic dest) / watch UI tests / watch unit tests | `Makefile:20-21, 84-90, 92-98` |
| `make lint` / `make format` / `make periphery` | SwiftLint strict / SwiftFormat / `periphery scan --strict` | `Makefile` (`.swiftlint.yml`, `.swiftformat`, `.periphery.yml`) |
| `make mac-test`, `make simverify`, `make coverage*` | macOS tests, sim pre-check, coverage | `Makefile:26, 15` (phonies) |
| `./scripts/test.sh` | Full CI-identical gate: formats? lints, builds iOS/watch/mac, deployment-target guard, unit + UI tests | `scripts/test.sh`; CI mirrors in `.github/workflows/ci.yml` |

- Simulator pinning: name-only destinations are ambiguous when multiple runtimes exist. `scripts/test.sh` resolves `SIM` (default `platform=iOS Simulator,name=iPhone 17`; `test.sh:5`) to a UDID (`resolve_sim_udid`, `test.sh:25-29`) and pre-boots (`test.sh:31-47`). Override with `SIM=platform=iOS Simulator,id=<UDID>` or `SIM=platform=iOS Simulator,name=iPhone 17,OS=<ver>`; CI uses `id=` everywhere.
- Watch sims: `WATCH_SIM="generic/platform=watchOS Simulator"` (compile-only build, `test.sh:6`); `WATCH_TEST_SIM` default `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (`test.sh:11`, `Makefile:7`, overridable with `,id=…`). CI cannot use name-based watch destinations — it creates a dedicated simulator (`ci.yml:391-401`).
- One `xcodebuild test` process at a time (simulator contention). On runner `Busy`/`RequestDenied`: prune stale `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`.
- Deployment-target guard: expected literals `18.7` iOS / `26.5` macOS+watchOS; counts 20 (`8 IPHONEOS + 6 MACOSX + 6 WATCHOS` in `project.pbxproj`) and 3 (`Package.swift:7-9`) — see `scripts/test.sh:110-117, 119-192`. Adding a target/platform platform must update these counts or the gate fails.
- DEBUG builds use `DEBUG_INFORMATION_FORMAT = dwarf`; Release switches to `dwarf-with-dsym` (project-wide `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).

## Test Suite Inventory

Unit tests use **Swift Testing** (`import Testing`, `@Test`; names must NOT start with `test`/`testing` — SwiftFormat strips them). UI tests use **XCTest** and keep `test…` names. Force-unwrapping is banned outside test files (relaxed in `SingleThreadTests/.swiftlint.yml`).

### iOS + macOS unit tests — `SingleThreadTests/` (~50 files, `make test` / CI `SingleThreadTests` job)
- `ReminderStoreTests.swift` — core store pipeline; injects `InMemoryEventStore` + `noopSettle` (`:10-12, 293, 323, 352`); nil-calendar never excluded (`:97`); `loadsReminders:false` no-op asserts (`:434-435`).
- `ReminderStoreGateTests.swift` — `canMutate` gates (`noopSettle` `:6-8`, gate tests `:82, 117, 131`).
- `EventKitStoringTests.swift` — `EventKitStoring` contract incl. `loadsRemindersFalseMakesReadPathsNoOps` (`:421`).
- `SkippedReminderSyncServiceTests.swift` — sync service with fake `SkipSyncSession`.
- `ReminderIntentsTests.swift` — intent titles from app/widget bundle, not Core (`:8-28`).
- `ReminderDisplayTests.swift`, `ReminderSkipTests.swift` (`:57-102`), `ReminderRecurrenceFormatterTests.swift`, `CodeSpanFormatterTests.swift`, `PendingCompletionLogicTests.swift`, `PendingCompletionStoreTests.swift` — formatter/model logic.
- Store/persistence: `SkippedReminderStore`-adjacent coverage in `ReminderSkipTests`; `CompletionCounterStoreTests`, `EntitlementStoreTests`, `ExcludedListStoreTests`, `UndoStoreTests`, `SortOptionTests`, `Show*PreferenceTests`, `AppGroupTests`.
- State/UI logic: `SettingsViewModelTests`, `ContentViewModel`-adjacent `ActionButtonTests`, `SwipePromptTests`, `TextSizeTests`, `AppearanceModeTests`, `BackgroundImageStoreTests`, `BackgroundCardTests`/`BackgroundFadeTests`/`BackgroundPhotoLayerTests`/`CardPlateModifierTests`/`CardPlateTests`, `MicrophoneToggleTests`, `ReminderDictationTests`/`ReminderDictationParserTests`/`TranscriptionAccumulatorTests`, `ReminderDeepLinkTests`, `ShowDateTests`/`ShowRecurrenceTests`/`ShowAlarmsTests`, `CompletionGlowTests`, `MinimumDisplayDurationTests`, `ResumptionGateTests`, `PrivacySettingsContentTests`, `AboutViewTests`, `AppInfoTests`/`AppDelegateTests`, `EntitlementSyncTests`.
- Localization: `LocalizationTests.swift` (enumerates all four catalogs `:105-124`, six languages `:93-103`), helpers in `LocalizationTestHelpers.swift` (`String.en(_:bundle:)`, `Bundle.core`), `StubBundle.swift`.
- `UITestingSeedTests.swift` — `--seed` JSON seam.
- Platform note: whole `SingleThreadTests/` runs on iOS+macOS (targets set both platforms + TEST_HOST to the app; `project.pbxproj:850, 879`).

### iOS UI tests — `SingleThreadUITests/` (XCTest, `make ui-test`)
- `SingleThreadUITestCase.swift` — launch helpers: `launchApp(arguments:)`, `launchSeeded(_:extra:)` (`--seed` + extras), `flipToggle`, `assertTogglePersists`.
- `SingleThreadUITestsFlows.swift` — main flows; priority-marker via `--seed` priority (`:76-85`), code-block rendering (`:317-342`).
- `ActionButtonsUITests`, `NotificationsUITests`/`NotificationSchedulingUITests`/`NotificationsSettingsUITests`, `*AppearanceLaunchTests`/`*LaunchTests`, `SingleThreadUITests.swift`.
- Accessibilty: `testAccessibilityAudit()` (`performAccessibilityAudit`) included; local audit adds `.hitRegion`/`.dynamicType` strictness beyond CI.

### watchOS unit tests — `SingleThreadWatchTests/` (`make watch-test` / CI `watch-ui-tests` job)
- `ReminderStoreWatchTests.swift` — pending-completion suite (`@Suite(.serialized)`, isolated custom-key `.standard` stores + defer cleanup `:15-21`; shared file-scoped `EKEventStore()` fixture `:12`): insert/persist `:25-42`, hide-on-reload `:44-63`, no-op-missing `:66-81`, preserves-prior `:84-103`, helper `pendingStore(key:)` `:114-116`.
- `WatchAppViewModelTests.swift` — composition root (stable lazy `reminderViewModel` `:14-20`).
- `WatchSyncPipelineTests.swift` — sync hooks via fake session.
- `ShowCompletionGlowStateTests.swift`, `WatchReminderViewRegressionTests.swift` (priority marker `:41`).
- Platform gating: watch test targets are `SDKROOT watchos` only (`project.pbxproj:1114-1147`); Core code compiled for watchOS is exercised here (`#if os(watchOS)` branches).

### watchOS UI tests — `SingleThreadWatchUITests/` (`make watch-ui-test` / CI `watch-ui-tests` job)
- `SingleThreadWatchUITestsFlows.swift` — flows driven by `--ui-testing` launch args; keys: card title/notes (`:24-33`), priority marker (`:37-52`), excluded-list (`:55-67`), live-exclusion (`:71-83`), no-access rendering (`:46-52, 102`), empty-state ids `emptyStateTitle`/`refreshButton` (`:58, 108-112`), glow ghost window (`:165-197`).
- `SingleThreadWatchUITestsLaunchTests.swift`, `SingleThreadWatchUITests.swift`.

### Widget — no tests
- `SingleThreadWidget/` has no unit or UI test target and no test seam (`NextThingWidget.swift:62-110` builds a real store; no launch args).

## Test Seams (shared vocabulary)

- `--seed '<json>'` (iOS) — `UITestingSeed` (`Core/UITestingSeed.swift:44-57`, schema `:8-26`: reminders/calendars/excludedLists/completionCount/isEntitled/hasHidden/entitlementUnresolved); consumed in `AppViewModel.makeStore` `:234` / `seededStore` `:290-348`; writes `completionCount` to App Group (`:300-303`).
- `--ui-testing` (iOS) — `AppViewModel.swift:244-274` (single reminder, `InMemoryEventStore.makeReminder`, `--reset-glow-preference`/`--reset-swipe-preference`, `enableActionButtons`).
- `--ui-testing` (watch) — `WatchAppViewModel.swift:14-16` + `uiTestingStore` `:96-135`; sub-flags `--ui-testing-priority <n>` (`:102-111`), `--ui-testing-excluded-list <title>` / `--ui-testing-live-excluded <title>` (`:120-135`; live delivers a real context 5 s after launch via `scheduleUITestLiveExcludedDelivery` `:236-244`), `--ui-testing-gated` (`:21-28`, seeds `completionCount = freemiumCap` in `AppGroup.defaults`), `--ui-testing-glow` / `--ui-testing-glow-disabled` (`:43-58`, duration 2.0 s).
- `settle:` injection — `ReminderStoreSettle` (`Core/ReminderStore.swift:7`); production default 200 ms (`:33`); tests inject `noopSettle`.
- `InMemoryEventStore` — the universal `EventKitStoring` fake (`Core/InMemoryEventStore.swift`): `.fullAccess`, incomplete-only fetches, optional off-main delivery, iOS-only `makeReminder` against a shared process store.

## Build/Verify Gotchas (research-confirmed)
- **Destination pinning**: bare `name=` hangs with 4 runtimes — pin `,OS=` or `,id=`; CI pins `id=`; `SIM=` override exists everywhere.
- **One test process at a time**; prune `XCTestDevices`/shutdown sims/kill orphans on `Busy`/`RequestDenied`.
- **Deployment-target guard**: `scripts/test.sh:114-192` hard-fails on literal drift (new target/platform must update counts 20/3).
- **Deployment floors**: iOS 18.7 / macOS 26.5 / watchOS 26.5 (`project.pbxproj` + `Core/Package.swift:7-9`) — shared Core code must compile for all three.
- **App Group vs `.standard`**: every persisted value shared with the watch must round-trip through `AppGroup.defaults` (`UserDefaults(suiteName:)`, `Core/AppGroup.swift:11-17`), never `UserDefaults.standard` alone — they silently diverge on simulator. On watchOS the suite is unavailable and falls back to `.standard` explicitly via `AppGroup.defaults`.
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only on app/watch targets (not Core/widget/tests — annotate explicitly there); Swift 6 mode; `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Core `ReminderStore` is `@MainActor @Observable`.
- **Lint/format**: `swiftformat` (repo `.swiftformat`) + `swiftlint lint --strict` (opt-in rules list in `.swiftlint.yml`; `identifier_name` ≥3 chars with listed exceptions). UI tests are SwiftFormat-excluded (`--exclude SingleThreadUITests`).
- **Watch scheme/test wiring**: `SingleThreadWatch.xcscheme` owns watch unit + UI tests; iOS scheme owns iOS tests. New test *targets* need pbxproj IDs + scheme TestAction + `-only-testing` entries in `scripts/test.sh` + CI matrix — flag in design.
- **StoreKit**: single product id `EntitlementStore.unlockProductID`; `Products.storekit` + scheme's StoreKit config must stay in sync.
- **Periphery**: `make periphery` scans the index store; `.periphery.yml` config at repo root.