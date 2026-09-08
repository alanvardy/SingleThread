# Conventions — shared factual appendix for Design/Structure/Plan

## Canonical commands (from `Makefile`)

| Command | Meaning | Ref |
|---|---|---|
| `make build` | xcodebuild build-for-testing, scheme SingleThread, iOS sim, Debug | `Makefile:17-19` |
| `make test` | `./scripts/test.sh --unit-only` | `Makefile:75-76` |
| `make ui-test` | `./scripts/test.sh --ui-only` | `Makefile:78-79` |
| `make check` | full gate: `./scripts/test.sh` (identical to CI) | `Makefile:100-101` |
| `make watch-build` | SingleThreadWatch, generic watchOS sim, build | `Makefile:20-21` |
| `make watch-test` | watch unit tests, concrete watch sim, `-only-testing:SingleThreadWatchTests` | `Makefile:92-98` |
| `make watch-ui-test` | watch UI tests, `-only-testing:SingleThreadWatchUITests` | `Makefile:84-90` |
| `make mac-build` / `mac-test` | macOS platform build / `-only-testing:SingleThreadTests` on macOS | `Makefile:23-27` |
| `make lint` | `swiftformat --lint` over 8 source/test dirs + `swiftlint lint --strict` | `Makefile:106-108` |
| `make format` | `swiftformat` + `swiftlint --fix` over same dirs | `Makefile:110-112` |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` | `Makefile:114-115` |
| `make coverage` / `coverage-ui` / `coverage-all` | xccov bundles, `-only-testing:SingleThreadTests` / `SingleThreadUITests` / all | `Makefile:37-73` |
| `make simverify` | `./scripts/simverify.sh` | `Makefile:81-82` |

- Simulator defaults: `SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); `WATCH_SIM` generic (`Makefile:2`); `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (`Makefile:7`); `MAC_SIM = platform=macOS` (`Makefile:8`).

## `scripts/test.sh` behavior (the gate Structure/Plan should respect)

- Destination pinning: resolves a name-only `SIM` to a concrete UDID because 4 runtimes make `name=iPhone 17` ambiguous (`scripts/test.sh:22-28`, `:41-44`); pre-boots the sim (`:34-35`, `:46-47`).
- Prunes stale `~/Library/Developer/XCTestDevices` runtimes older than `RUNTIME_AGE_HOURS` (default 1) — each UI run leaves a ~3 GB runtime Xcode never prunes (`:8-11`, prune helper after :49).
- Suites run (per phase, all with pinned destinations): `SingleThreadTests` (`:237`), `SingleThreadUITests` (`:245`), watch combined `SingleThreadWatchUITests` + `SingleThreadWatchTests` (`:254-255`), plus mac-only `SingleThreadTests` (`:292`). See also `scripts/test.sh:212-292`.
- **CI = `./scripts/test.sh` layout**: `.github/workflows/ci.yml:16-18,:62,:130,:191,:250,:312,:416-438` runs iOS unit, iOS UI, and watch matrix jobs; watch jobs use `generic/platform=watchOS Simulator` for build and a concrete watch sim for tests.
- CI runs iOS on both `iPhone 17` and `iPad (A16)` in a matrix; local default is iPhone 17 (AGENTS.md).

## Test-suite inventory

### Test targets (pbxproj `project.pbxproj:240-409`)
`SingleThreadTests` (:269), `SingleThreadUITests` (:294), `SingleThreadWatchUITests` (:364), `SingleThreadWatchTests` (:387), plus `SingleThreadWidget` app-extension (:340, iOS-only, pbxproj:17/:47). **No widget test target exists.**

### iOS unit tests (`SingleThreadTests/`, Swift Testing)

| File | Covers | Gating |
|---|---|---|
| `SingleThreadTests.swift` | Empty/all-done copy builders: `contentViewEmptyStatesShowDistinctCopy` :32-48, `contentViewAllDoneShowsAllDoneCopy` :51-56 | none |
| `ReminderStoreTests.swift` | Store predicates: `allSkippedReflectsState` :471-501, `hasHiddenReflectsSeedsAndSets` :438-465 | `#if !os(watchOS)` in spots :507,:628,:672,:683,:793,:879 |
| `ActionButtonTests.swift` | `buttonsHiddenWhenAllSkipped` :62 (action-button gate) | whole file `#if os(iOS)` :8-134 |
| `UITestingSeedTests.swift` | `--seed` parsing: `parsesHasHidden` :109, `hasHiddenDefaultsWhenAbsent` :120 | none |
| `SortOptionTests.swift` | `SortOption` rawValues :8-13, allCases :15-17, store round-trip `saveAndLoadRoundTrip` :62-66, defaults :46/:53 | none |
| `ReminderSkipTests.swift` | `ReminderPriority.Level` parameterized over raw priorities 0-9 + displayName/marker/rank :60-101 | none |
| `AppearanceModeTests.swift` | raw-value decode/fallback :55-70, allCases :74-75, platform maps :20-51 | per-test `#if os(iOS)`/`os(macOS)` |
| `TextSizeTests.swift` | allCases equality :33-34 | none |
| `LocalizationTests.swift` | every xcstrings catalog (Core/App/Watch/Widget) parsed, non-empty en values :27-50; catalogURL switch :222/:233 | none |
| `LocalizationTestHelpers.swift` | `String.en(_:bundle:table:)` pinned `Locale(identifier: "en")`, `Bundle.core` :5-34 | none |
| `MinimumDisplayDurationTests.swift` | parameterized elapsed→remaining table :10-16 | none |
| `EntitlementStoreTests.swift`, `CompletionCounterStoreTests.swift` | StoreKit/entitlement state save/load round-trips :12-80 / :9-90 | `EntitlementSyncTests`: whole file `#if os(iOS) \|\| os(watchOS)` (:1,:129) |
| `AppDelegateTests.swift`, `SkippedReminderSyncServiceTests.swift` | app-delegate / sync service | whole-file platform gating (`#if os(iOS)`; `#if os(iOS) \|\| os(watchOS)` :1,:587) |

### iOS UI tests (`SingleThreadUITests/`, XCTest)
- `SingleThreadUITestsFlows.swift` — empty/all-done ordering via `emptyStateTitle` id (emitted `EmptyStateCard.swift:28`): `testEmptyListShowsNoRemindersState` :34, `testNothingDueShowsWhenRemindersHidden` :43 (seed `{"reminders":[],"hasHidden":true}`, literal "Nothing due" :47), `testSkipAllShowsAllDoneState` :87, `testCompleteViaSwipeRemovesReminder` :149, `testDeleteViaContextMenuRemovesReminder` :167; cross-device completion :110; undo-button absence :590/:623/:634.
- `ActionButtonsUITests.swift` — `testActionButtonsRenderAndSkipAdvancesCard` :20 (allSkipped branch, comment "bottom bar disappears" :38 — not asserted), audit :46; in-method `#if os(iOS)` :57-60; `runsForEachTargetApplicationUIConfiguration = false` :10-15.
- `SingleThreadUITests.swift` — `testAccessibilityAudit` :31, runs under `--ui-testing` which renders the No Reminders branch (:35-36); CI env carve-out :44-56; `runsForEachTargetApplicationUIConfiguration = false` :16-21.
- `NotificationSchedulingUITests.swift` — `testNoScheduleWhenNoReminders` :109 (seed `{"reminders":[]}`); whole file `#if os(iOS)` :1-135.
- `NotificationsUITests.swift` — whole file `#if os(iOS)` :1-113.
- Seam: `SingleThreadUITestCase.swift` `launchSeeded(_:extra:)` :22; `--ui-testing` :10-11.

### Watch tests
- UI (`SingleThreadWatchUITestsFlows.swift`) — asserts `emptyStateTitle` only (never literal copy): excluded-list→All Done :39, live-exclusion :58, complete→No Reminders :76, skip→All Done :92, delete :108, Refresh button on empty :127, glow-hold :166. `SingleThreadWatchUITests.swift` — `testTapRevealsConfirmationDialog` :9, audit :30 (`#if os(watchOS)` :46-48); freemium gate `testUpgradeOniPhoneShowsWhenGated` :146-163.
- Unit (`SingleThreadWatchTests/`) — `ShowCompletionGlowStateTests.swift` (transition-state prerequisites, `@Suite(.serialized)` :26, tests :32-222), `WatchAppViewModelTests.swift` (:21 glow seam), `ReminderStoreWatchTests.swift`, `WatchSyncPipelineTests.swift` (:379 decode switch), `WatchReminderViewRegressionTests.swift` (:31 display fields). **No unit test asserts view-level all-done/empty branch order.**

### Launch-arg seams for deterministic UI states
- iOS: `--seed '<json>'` (`SingleThreadCore/.../UITestingSeed.swift` — fields `reminders`, `calendars`, `excludedLists`, `completionCount`, `isEntitled`, `entitlementUnresolved`, `hasHidden` :39/:111/:128/:155/:166; consumed `SingleThread/AppViewModel.swift:235/:280/:291`), `--ui-testing` (AppViewModel.swift:245 seeds 1 reminder, :275 `loadsReminders=false`), `--ui-testing-glow` (ContentView.swift:279), `--ui-testing-notifications`.
- Watch: `--ui-testing` (WatchAppViewModel.swift:14-16, store :96-140), `--ui-testing-gated` (:26), `--ui-testing-glow` / `--ui-testing-glow-disabled` (:48-53), `--ui-testing-priority <n>` (:107-111), `--ui-testing-excluded-list` / `--ui-testing-live-excluded` (:120-134). **No `--seed` on watch.**

## Build/verify gotchas surfaced by research
- **One xcodebuild test process at a time** (simulator contention); on `Busy`/`RequestDenied` prune `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned xcodebuild/xctest. Don't retry identical invocations blindly; verify dest pins with `,OS=<ver>` or `,id=<UDID>` — bare `name=iPhone 17` hangs with 4 runtimes (`scripts/test.sh:22-28`).
- **Exhaustive switches are compile-forced, not lint-forced**: `make lint` (`Makefile:106-108`) + SwiftLint `--strict` (CI `ci.yml:354`) never flag missing switch cases; only `xcodebuild` (`error: switch must be exhaustive`). New shared-enum cases therefore break every no-default consumer at build time — Design/Plan must enumerate those sites (see `research.md` Q4 list).
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat strips them under `make format`. Convention: `contentViewEmptyStatesShowDistinctCopy` etc. UI (XCTest) names keep `test…` (UI tests SwiftFormat-excluded).
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`** project-wide; app/watch targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Core/widget/tests don't — annotate explicitly there).
- **Persisted values shared with watch must round-trip through `AppGroup.defaults`** (UserDefaults suite), never `UserDefaults.standard` — the sim suite always exists so the two diverge silently.
- **Staging verification**: phase workers verify with build + targeted `-only-testing:` suites only; the full `./scripts/test.sh` gate runs once, by the parent, after phases commit (multi-hour runtime; AGENTS.md).
- `DEBUG_INFORMATION_FORMAT = dwarf` (Debug) keeps incremental builds fast; `deriveData` lands in `DerivedData/` (`Makefile:9`).
- New `.swift` files are auto-discovered (synchronized groups, `objectVersion = 77`); a new **test target** requires pbxproj IDs, scheme TestAction wiring, `-only-testing` entries, CI matrix changes — flag in design.
- Local a11y audit is stricter than CI (`.hitRegion`, `.dynamicType` categories) — a local hit-region failure can be local-only.