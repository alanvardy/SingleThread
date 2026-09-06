# Conventions — shared factual appendix

For Design/Structure/Plan. Verified against the working tree on branch `alanvardy-var-800-clear-stale-reminders`.

## Canonical commands

From `Makefile` and `scripts/test.sh` (identical to CI `.github/workflows/ci.yml`):

| Command | What it runs | Source |
|---|---|---|
| `./scripts/test.sh` (no args) | Full gate: SwiftFormat lint → SwiftLint `--strict` → iOS build-for-testing → watch build → Periphery `--skip-build --strict` → iOS unit tests → iOS UI tests → watch UI tests → watch unit tests → macOS unit tests | `scripts/test.sh:200-331` |
| `./scripts/test.sh --unit-only` / `--ui-only` | Unit-only / UI-only subsets | `scripts/test.sh:293-345` |
| `make build` | iOS Debug `build-for-testing` | `Makefile:15-17` |
| `make watch-build` | watchOS Debug build (`generic/platform=watchOS Simulator`) | `Makefile:19-21` |
| `make mac-build` / `mac-test` / `mac-run` | macOS Debug build / unit tests (`-only-testing:SingleThreadTests`, `CODE_SIGNING_ALLOWED=NO`) / run | `Makefile:23-35` |
| `make test` / `make ui-test` / `watch-test` / `watch-ui-test` | Wrappers over `scripts/test.sh` / targeted watch suites | `Makefile:53-71` |
| `make lint` | `swiftformat --lint <all 8 source/test dirs>` (UI tests excluded) + `swiftlint lint --strict` | `Makefile:77-80`, `.swiftformat:16` (`--exclude SingleThreadUITests`) |
| `make format` | `swiftformat <dirs>` + `swiftlint --fix` | `Makefile:82-85` |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` | `Makefile:87-88` |
| `make coverage` / `coverage-ui` / `coverage-all` | xccov reports via result bundles | `Makefile:37-52` |
| `make check` | full `./scripts/test.sh` | `Makefile:74-75` |
| `make simverify` | `scripts/simverify.sh` | `Makefile:76` |

- CI matrix (`ci.yml`): `unit-tests`, `ui-tests-flows`, `ui-tests-launch`, `ui-tests-appearance`, `ui-tests-actions` all run `iPhone 17` × `iPad (A16)`; iOS UI classes are split into 3 disjoint `-only-testing:` groups via env `UI_GROUP_A/B/C_ONLY_TESTING` (`ci.yml:13-18`). `watch-build` + `watch-ui-tests` jobs create a **standalone** watch simulator with a deterministic id (`ci.yml:391-406`). `macos-unit-tests` job at `ci.yml:323` (`SIM=platform=macOS`).
- Deployment floors: `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, watchOS/macOS `= 26.5`, Package.swift literals `.iOS 18.7 / .watchOS 26.5 / .macOS 26.5` — enforced by a consistency guard in `scripts/test.sh:107-187`.

## Test-suite inventory

**Unit tests = Swift Testing** (`import Testing`, `@Test`) — 72 files in `SingleThreadTests/`; **UI tests = XCTest** (`SingleThreadUITests/`, `SingleThreadWatchUITests/`; watch unit tests `SingleThreadWatchTests/` also Swift Testing). No `import XCTest` in `SingleThreadTests`.

### SingleThreadTests/ (iOS + macOS + watch-shared unit tests) — 9070 lines total
| File(s) | Covers | Platform gating |
|---|---|---|
| `ReminderStoreTests.swift` (largest) | reload/refetch matrix on `InMemoryEventStore`; complete/skip/delete/undo/add/reschedule; `skipCurrentReminderRefetchesAndDropsCompletedReminder` (`:283-312`, "completed on another device"); `reloadDefensivelyDropsCompletedReminder` (`:979-990`); pending-completion reload suite (`:900-990`); MakeReminder (`:1006-1093`); `noopSettle` at `:12` | `#if os(iOS) \|\| os(watchOS)` at `:557`; `#if !os(watchOS)` at `:672, :718, :883, :1004` |
| `ReminderStoreGateTests.swift` | canMutate × complete/skip/delete gating | — |
| `ListContentTests.swift`, `PendingCompletionLogicTests.swift`, `ReminderSkipTests.swift` | listContent resolution; pure pending logic (incl. completed-reminder drop `:22-25`); skip reconcile/prune | — |
| `ContentViewModelTests.swift` | `refreshManual` re-entrancy/min-display/clear-skipped | — |
| `EventKitStoringTests.swift` | `FakeEventStore` write-path fetch-count assertions; `deleteReminderWhileSkippedPrunesSkipIDOnReload` (`:222-236`) | — |
| `SkippedReminderSyncServiceTests.swift`, `RescheduleSyncTests.swift`, `EnableActionButtonsSyncTests.swift`, `EntitlementSyncTests.swift` | sync pipeline with `FakeSession`; payload capture/echo; AppGroup round-trips | `#if os(iOS) \|\| os(watchOS)` (file top, e.g. `SkippedReminderSyncServiceTests.swift:1`) |
| `AppDelegateTests.swift`, `BackgroundCardTests.swift`, `ActionButtonTests.swift`, `AppearanceModeTests.swift` | app-delegate / platform-specific chrome | `#if os(iOS)` / `#if os(macOS)` at file top |
| `MacOSActionButtonChromeTests.swift`, `MenuBarExtraOptionsTests.swift` | macOS action buttons / menu-bar extra | `#if os(macOS)` (file top) |
| `UITestingSeedTests.swift` | `--seed` parse/materialize/render; `resetPersistedState` | — |
| `SettingsViewTests.swift`, `SettingsViewModelTests.swift`, `SettingsSubscreenLayoutTests.swift`, `AboutViewTests.swift`, `SingleThreadTests.swift`, `MicrophoneToggleTests.swift`, `AppearanceModeTests.swift` | per-platform settings UI | inline `#if os(iOS)` / `#if os(macOS)` blocks |
| ~45 remaining files | one-file-per-feature logic tests (preference stores, formatters, sort, glow, dictation, undo, notification schedule, etc.) | — |

### SingleThreadWatchTests/ (watch unit tests — separate target, built/tested only on watchOS)
`ReminderStoreWatchTests.swift` (watch read-only complete/delete/reschedule + pending hide/not-resurrect `:55-66`), `WatchSyncPipelineTests.swift` (`WatchFakeSession`, phone-context → store behavior, AppGroup validation `:403-424`), `WatchAppViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`, `ShowCompletionGlowStateTests.swift`, `ShowEnableActionButtonsStateTests.swift`. No `#if` gating — the target is watch-only by construction.

### SingleThreadUITests/ (XCTest, iOS)
`SingleThreadUITestCase.swift` (launch helper: `launchSeeded = --seed <json> --ui-testing-noop-settle --ui-testing-reduced-glow`, `:22-32`); `SingleThreadUITestsLaunchTests`, `SingleThreadUITestsAppearanceLaunchTests`; `SingleThreadUITestsFlows.swift` (seeded end-to-end; cross-device-completion simulation `:51-99`); `SingleThreadUITests.swift`; `ActionButtonsUITests`, `ActionMenuUITests`, `SkipNudgeUITests`, `NotificationSchedulingUITests` + `NotificationsUITests` + `NotificationsSettingsUITests` (the three notification files are `#if os(iOS)`).

### SingleThreadWatchUITests/ (XCTest, watch)
`SingleThreadWatchUITestsLaunchTests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITests.swift`. Requires a **concrete** paired/standalone watch simulator (`WATCH_TEST_SIM`, `scripts/test.sh:11`); CI creates a standalone watch sim (`ci.yml:391-406`).

## Build/verify gotchas (from `scripts/test.sh`, `Makefile`, AGENTS.md)
- **Destination pinning**: name-only `iPhone 17` is ambiguous with 4 runtimes — `scripts/test.sh` resolves to UDID via `xcrun simctl list devices available` and pre-boots (`scripts/test.sh:31-49`); pass `SIM='platform=iOS Simulator,id=<udid>'` or `SIM='platform=iOS Simulator,name=iPhone 17,OS=<ver>'` to override. Same for watch: `WATCH_TEST_SIM` defaults to `name=Apple Watch Series 11 (46mm)`, override with `,id=`.
- **One xcodebuild/test process at a time** (simulator contention); CI disables parallel simulator clones (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`, `ci.yml:75-82`) due to clone-connection timeouts and EventKit teardown SIGTRAPs.
- **XCTest runtime cleanup**: each UI run leaves ~3 GB in `~/Library/Developer/XCTestDevices`; `scripts/test.sh` prunes entries older than `RUNTIME_AGE_HOURS` (default 1, `scripts/test.sh:11-13, 53-79`).
- **Local-only watch runner fix**: this machine's watchOS 26.5 simruntime is missing `lib_TestingInterop.dylib`; the gate embeds the Xcode-side lib into the UI-test runner Frameworks (no-op on CI, `scripts/test.sh:256-270`).
- **Debug builds use `dwarf`** for speed (`DEBUG_INFORMATION_FORMAT = dwarf`); release uses `dwarf-with-dsym`.
- **Warnings-as-errors** project-wide (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`) and SwiftLint `--strict` — every warning fails.
- **SwiftFormat renames tests**: unit-test names must not start with `test`/`testing` (SwiftFormat strips the prefix, silently renames under `make format`); UI-test (XCTest) names keep `test…` — UI tests are SwiftFormat-excluded (`.swiftformat:16`). Force-unwrapping banned outside tests; relaxed only by `SingleThreadTests/.swiftlint.yml`.
- **Periphery** scans the build's index store (`periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` in test.sh; `periphery scan --strict` via Makefile re-runs with a destination).
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only on the app + watch targets** (`project.pbxproj:777, :827, :961, :989`) — Core/widget/test targets need explicit `@MainActor`; do not wrap app/watch code in `Task { @MainActor in }` (redundant).
- **Every persisted value shared with the watch must round-trip `AppGroup.defaults`** (suite `group.app.alanvardy.SingleThread`, `AppGroup.swift:9-22`), never `UserDefaults.standard` — the suite always exists on simulator so they diverge silently. Includes `--ui-testing`/`--seed` seams (`AppViewModel.makeStore`, `AppViewModel.swift:203-253, :264-318`).
- **StoreKit product id** single source of truth: `EntitlementStore.unlockProductID`; keep `Products.storekit` + scheme `StoreKitConfigurationFileReference` in sync.
- **CI-identical gate runs ONCE** (by the parent or a final phase, post-commit) — phase workers verify with build + targeted `-only-testing:` suites only, to stay within run caps.