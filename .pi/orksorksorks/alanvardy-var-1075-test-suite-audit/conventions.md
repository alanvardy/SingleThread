# Conventions — SingleThread test/build appendix

Shared factual reference for Design/Structure/Plan. All commands run from
repo root `/Users/vardy/dev/alanvardy-var-1075-test-suite-audit`.

## Canonical commands (Makefile + scripts/)

- `make build` — iOS build. `make watch-build` — watch build.
- `make test` — unit gate (`scripts/test.sh --unit-only`). `make ui-test` — UI gate (`--ui-only`). `make check` — full CI-identical gate (`scripts/test.sh`).
- `make lint` — `swiftformat --lint` + `swiftlint lint --strict`. `make format` — `swiftformat` + `swiftlint --fix`.
- `make periphery` — `periphery scan --strict` (reads stale DerivedData index — clean `DerivedData/` and rerun after branch switch).
- `make coverage` / `coverage-ui` / `coverage-all`. `make reset-storekit`. `make clean`.
- Gate pipeline order (`scripts/test.sh`): format → swiftlint → warning-check self-test → iOS build-for-testing → resolve/pin watch UDID + preboot → watch build → periphery → iOS UI tests → watch UI build+test+test → watch unit tests → macOS unit tests (`-only-testing:SingleThreadTests` on macOS native).
- Single test: `scripts/test-one.sh <Target/Suite/case>` (exits non-zero on zero-match — a zero-match `-only-testing:` prints `** TEST SUCCEEDED **` and exits 0).

## Destination pinning

- Precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default `name=iPhone 17` (`Makefile:1-5`, `scripts/test.sh:8-76`).
- Watch UI tests use `WATCH_TEST_SIM` (unpaired watch pinned by UDID).
- Version floors (`scripts/test.sh:143-152`): iOS 17.0, watchOS 11.0, macOS 26.5.
- One `xcodebuild test` process at a time; on `Busy`/`RequestDenied` shut down sims + kill orphaned `xcodebuild`/`xctest` (simulator-pairing skill).

## Test-suite inventory & platform gating

### SingleThreadTests/ — unit (Swift Testing, `import Testing`, `@Test`), runs on iOS AND macOS
The single combined iOS+macOS unit suite; platform via whole-file/inline `#if os(...)`.
- Whole-file gated (line 1): `os(iOS)` — `AppDelegateTests.swift:1`, `BackgroundCardTests.swift:8`, `AISortFailureBannerTests.swift:1`; `os(macOS)` — `MenuBarExtraPreferenceTests.swift:1`, `MacOSActionButtonChromeTests.swift:1`; `os(iOS) || os(watchOS)` — `RescheduleSyncTests.swift:1`, `SkippedReminderSyncServiceTests.swift:1`, `EntitlementSyncTests.swift:1`, `AppLanguageSyncTests.swift:1`, `EnableActionButtonsSyncTests.swift:1`.
- Inline `#if os(macOS)`: `SettingsViewTests.swift:82,209,293,433`, `SettingsSubscreenLayoutTests.swift:13/25`, `AboutViewTests.swift:26`, `MicrophoneToggleTests.swift:196/234`.
- `TestFixtures.swift:70` gates `FakeSession` behind `os(iOS) || os(watchOS)`.
- Known local-only macOS failures (don't debug): `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` (CI mac green).
- Coverage highlights: `ReminderStoreTests.swift` (74 `@Test`, ~1300 lines, 90+ InMemoryEventStore injections, private `CompletedReturningEventStore` fake at `:1086`); `ReminderSkipTests.swift` (+ `ReminderSortTests` struct); `AISortCoordinatorTests.swift`; `AppGroupTests.swift` (`defaultsIsAStableInstance` guard); `UITestingSeedTests.swift`.

### SingleThreadUITests/ — iOS UI (XCTest, XCUIApplication, `[--ui-testing]`) at `SingleThreadUITests.swift:28`
Single file; launch/render smoke + `testAccessibilityAudit` (`performAccessibilityAudit`). SwiftFormat-excluded; keeps `test…` names. Empty `#else` mac branch so bundle compiles on macOS.

### SingleThreadWatchTests/ — watch unit (Swift Testing), separate watch scheme, 0 whole-file gates
7 files: `WatchAppViewModelTests.swift`, `WatchReminderViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`, `WatchSyncPipelineTests.swift` (`:13-406`), `ReminderStoreWatchTests.swift`, `ShowCompletionGlowStateTests.swift`, `ShowEnableActionButtonsStateTests.swift`, + `TestFixtures.swift:1-7` (`sharedWatchEventStore`, reminder builder).

### SingleThreadWatchUITests/ — watch UI (XCTest, `[--ui-testing]`) at `SingleThreadWatchUITests.swift:35`
Single file (NOT SwiftFormat-excluded; still keeps XCTest `test…` names).

## Core seams referenced by tests

- `EventKitStoring.swift:8` protocol seam (`:45` `EKEventStore: EventKitStoring` adapter; non-watchOS methods `#if !os(watchOS)` `:49-63`).
- `InMemoryEventStore.swift:13` in-memory fake (deps `reminders, calendars, deliverCompletionOffMain, saveError, defaultCalendar` `:17-32`; records `requestFullAccessCallCount:40`, `saveCallCount:42`; `saveError:44`; mirrors `predicateForIncompleteReminders` `:84`).
- `AppGroup.defaults` (`AppGroup.swift:27-30`) single cached `UserDefaults` instance — shared-with-watch persistence MUST round-trip here (never `UserDefaults.standard`); guarded by `defaultsIsAStableInstance`.
- Launch-arg seams (`AppViewModel.swift:231-317`): `--seed '<json>'` (via `UITestingSeed.fromLaunchArguments`, `:246`), `--ui-testing` (+ `-glow/-reduced-glow/-noop-settle/-app-language <raw>/-notifications`), `--no-reminders`. Watch variants in `WatchAppViewModel.swift:7-170,295`.
- `ReminderStore.swift:22-45` single injectable init (`eventStore`, `loadsReminders:false`, pre-seeded `reminders/skippedIDs/pendingCompletions/authorizationStatus/excludedListTitles/hasHidden`, `settle` hook no-op in tests; production settle = 200 ms sleep). ReminderStore has NO AppGroup param (persistence via injected stores).

## Build/verify gotchas

- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; scope per-target overrides in pbxproj, never CLI (conflicts with SPM `-suppress-warnings`). Gate fails on any source-located compiler warning.
- SwiftLint `--strict` in CI — every warning is an error; `swiftlint lint --strict` before commit.
- Unit-test names must NOT start with `test`/`testing` (SwiftFormat strips them under `make format`); UI-test names keep `test…`. Variable names ≥ 3 chars (`identifier_name` exceptions: `id`, `e`, `d`, `rt`, `to`, `gvm`).
- Force-unwrapping banned outside test code; test fixtures relax via `SingleThreadTests/.swiftlint.yml`.
- New `.swift` file needs no pbxproj edit (synchronized groups). A **new test target** needs pbxproj object IDs, scheme TestAction wiring, `-only-testing` entries in `scripts/test.sh`, `Makefile test` target, and CI matrix entries.
- Pre-existing failure on `origin/main` (diff didn't touch) → verify via `git blame`/CI; never `git stash` to baseline (spans branches) — use `git show origin/main:<path>` or throwaway worktree.
- Watch UI runner needs `lib_TestingInterop.dylib` embedded locally (watch-UI stage) — handled by `scripts/test.sh`; XCTest runtimes pruned via `cleanup_xctest_runtimes`.
- Local Xcode 27.0 vs CI 26.6 can diverge on `$`-projection-only `@State` (periphery) — see periphery skill.
- `@MainActor` isolation is project-wide only on iOS app + watch app targets; Core/widget/test targets need explicit `@MainActor` annotations where needed.
- Persisted values shared with the watch must round-trip through `AppGroup.defaults`; `--seed`/`--ui-testing` seams included.
- Gate stages: phase subagents verify with build + targeted `-only-testing:` suites only; full CI-identical gate runs ONCE via the run-gate skill after phases commit — never nohup it ad-hoc.