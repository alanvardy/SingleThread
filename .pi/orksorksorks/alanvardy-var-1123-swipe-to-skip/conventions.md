# Conventions & Commands — fact appendix for Design / Structure / Plan

Dense reference for build, test, lint, and platform gating. Paths relative to
repo root. Use this instead of re-reading `Makefile`, `scripts/test.sh`, and
the test trees.

## Canonical commands

### Make targets (`Makefile`)
- `make build` — `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build-for-testing` (`Makefile:28`).
- `make test` — `./scripts/test.sh --unit-only` (`Makefile:99`).
- `make ui-test` — `./scripts/test.sh --ui-only` (`Makefile:101`).
- `make check` — full `./scripts/test.sh` pipeline (`Makefile:109`).
- `make lint` — `swiftformat --lint <all source+test dirs>` then `swiftlint lint --strict` (`Makefile:115-117`).
- `make format` — `swiftformat <all dirs>` then `swiftlint --fix` (`Makefile:119-121`).
- `make periphery` — `periphery scan --strict -- -destination "$(SIM)"` (`Makefile:123-124`).
- `make watch-test` / `make watch-ui-test` — watch scheme test with `-only-testing:SingleThreadWatchTests` / `SingleThreadWatchUITests` (`Makefile:103-113`).
- `make mac-test` — `xcodebuild … -destination platform=macOS CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` (`Makefile:52`).
- Also `build`, `watch-build`, `mac-build`, `mac-run`, `mac-distribute`, `reset-storekit`, `coverage`, `coverage-ui`, `coverage-all`, `simverify`, `clean`.

### Destination resolution
- `SIM` precedence: explicit `SIM=` (command line/env) > this worktree's `.simulator_id` > shared default `platform=iOS Simulator,name=iPhone 17` (`Makefile:4-8`; `scripts/test.sh:63-77`).
- `scripts/test.sh` resolves a name-only `SIM` to a concrete UDID via `resolve_sim_udid` and pre-boots it (`test.sh:29-40,80-89,54-60`). An unanchored match can select the leftover "Gate iPhone 17" sim — the awk match is anchored to the line start (`test.sh:34-38`).
- Watch test destination defaults to `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`, resolved to a UDID before the watch stage; override with `WATCH_TEST_SIM='platform=watchOS Simulator,id=<udid>'` (`Makefile:12-21`, `test.sh:253-269`).

### Single-test runner
- `scripts/test-one.sh <Target/Suite/case>` — pins the simulator from `.simulator_id` and exits non-zero when the run matched **zero** cases (a zero-match `-only-testing:` prints "TEST SUCCEEDED" and exits 0). Bounds the run; the README of the repo's AGENTS.md recommends it for red-first checks.

## Full gate (`./scripts/test.sh`) — CI-identical pipeline order

Any argument omitted = full mode (`test.sh:78-95`).

1. `disk-clean` if installed (`test.sh:97-99`).
2. Deployment-target / package-floor drift guard: iOS 17.0, watchOS 11.0, macOS 26.5; iOS literals ×8, watchOS ×6; package `.iOS`/`.watchOS`/`.macOS` (`test.sh:100-219`; `verify_deployment_target`).
3. `verify_xcodebuild_wrapped` guard (`test.sh:221`).
4. `swiftformat` (auto-format) then `swiftlint --fix` (`test.sh:227-229`).
5. `swiftformat --lint` (`test.sh:232-233`).
6. `swiftlint lint --strict` (`test.sh:236-237`).
7. Warning-check self-test: `bash scripts/tests/warning-check/run.sh` (`test.sh:240-241`).
8. iOS build: `xcodebuild … build-for-testing` (`test.sh:244-249`).
9. Watch build (`test.sh:272-276`).
10. Periphery: `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` (`test.sh:279-280`) — uses the build index produced by step 8.
11. iOS **UI** tests: `test-without-building -only-testing:SingleThreadUITests` (`test.sh:283-288`).
12. Watch build-for-testing (UI + unit) + local `lib_TestingInterop.dylib` embed workaround (`test.sh:291-313`).
13. Watch UI tests (`test.sh:315-320`).
14. Watch unit tests (`test.sh:323-326`).
15. macOS unit tests: `xcodebuild … -destination platform=macOS CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` (`test.sh:329-338`).

Modes: `--unit-only` runs only macOS unit tests (`test.sh:341-352`); `--ui-only` builds + runs only iOS UI tests (`test.sh:355-372`).

## Lint / format config
- SwiftFormat config `.swiftformat`; runs over `SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/ SingleThreadWatchUITests/ SingleThreadWatchTests/`. iOS UI tests are excluded from formatting (`--exclude SingleThreadUITests`, per repo AGENTS.md).
- SwiftLint config `.swiftlint.yml`, run `--strict` (every warning is an error). Unit-test fixtures relax force-unwrap via `SingleThreadTests/.swiftlint.yml`.
- Unit-test names must not start with `test`/`testing` (SwiftFormat `preferSwiftTesting` strips them); UI-test (XCTest) names keep `test…`.

## Test-suite inventory (relevant to action/swipe surfaces)

### Unit — `SingleThreadTests/` (Swift Testing: `import Testing`, `@Test`)
| File | Covers | Gating |
|---|---|---|
| `SwipeGestureDecisionTests.swift` | `SwipeGesture.outcome(for:)`/`revealedOutcome(forOffset:)`: threshold, direction, vertical dominance (`:10-56`) | none |
| `SwipeToActModifierTests.swift` | `SwipeRevealPanel` label/anchor via reflection (`:11-40`) | none |
| `SwipePromptTests.swift` | swipe hint caption visibility + dismiss a11y label (`:9-37`) | none |
| `ActionMenuGateTests.swift` | `ActionMenuGate.showsActionMenu` 2×2×2 truth table (`:10`) | none |
| `ActionButtonTests.swift` | `ContentViewModel.showsActionButtons` gate + cold-open ordering (`:21-62`) | `#if os(iOS) || os(macOS)` (`:8`) |
| `EnableActionButtonsMigrationTests.swift` | `.standard` → AppGroup migration (`:13-29`) | `@Suite(.serialized)` (`:11`) |
| `EnableActionButtonsSyncTests.swift` | WatchConnectivity push/receive for the toggle (`:20-49`) | `#if os(iOS) || os(watchOS)` (`:1`), `.serialized` (`:14`) |
| `AppViewModelSyncWiringTests.swift` | AppViewModel sync wiring | — |
| `BoolPreferenceKeyTests.swift` | key registry incl. `enableActionButtons` (`:14`) | — |
| `SettingsViewTests.swift` | settings render incl. toggle (`:54,120`) | — |
| `MacOSActionButtonChromeTests.swift` | macOS action-button chrome | `#if os(macOS)` (`:1`) |
| `RescheduleSheetTests.swift` | reschedule date/time, write-back mask, label placement (`:12-79`) | — |
| `AppLanguageTests.swift` | shared-key localization map, incl. `SharedStrings.skipAction` all 6 locales (`:50-82`) | — |
| `SingleThreadTests.swift` | cross-cutting, incl. `rescheduleStringResolvesInGerman` (`:163-170`), sheet native-chrome (`:147-151`) | — |
| `LocalizationTests.swift` / `LocalizationTestHelpers.swift` | localization harness | — |

Corpus: ~100 unit files in `SingleThreadTests/` (full list via `ls SingleThreadTests`).

### Unit — `SingleThreadWatchTests/` (Swift Testing)
| File | Covers | Gating |
|---|---|---|
| `ShowEnableActionButtonsStateTests.swift` | watch toggle holder read/persist/apply (`:10-37`) | `@Suite(.serialized)` (`:12`) |
| `WatchSyncPipelineTests.swift` | watch sync pipeline incl. enable-toggle (`:398-437`) | — |
| `WatchReminderViewRegressionTests.swift` | watch action-view regressions | — |
| `WatchReminderViewModelTests.swift` | watch reminder VM state (`isShowingActionMenu`, etc.) | — |
| `ReminderStoreWatchTests.swift`, `ShowAlarmsStateTests.swift`, `ShowCompletionGlowStateTests.swift`, `ShowDateStateTests.swift`, `ShowListStateTests.swift`, `ShowRecurrenceStateTests.swift`, `WatchAppViewModelTests.swift` | watch feature state holders | — |

### UI — XCTest
- `SingleThreadUITests/SingleThreadUITests.swift` — smoke (`:23`, a11y audit `.sufficientElementDescription`, `.trait` at `:59`; `.dynamicType`/`.hitRegion` excluded at `:53-58`), `testOverThresholdSwipeCompletesReminder` (`:73`, `--seed` + `--ui-testing-noop-settle`, 110pt drag), language tests (`:140`,`:187`).
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — render smoke only (`:11`).

### Test seams
- iOS write-flow UI tests use `--ui-testing` / `--seed '<json>'` backed by `InMemoryEventStore` (repo AGENTS.md; `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`, `enableActionButtons` seed at `:100`).
- Watch uses the existing `--ui-testing` launch-arg seam.
- App Group values (incl. launch-arg seams) must round-trip through `AppGroup.defaults`, never `UserDefaults.standard`.

## Build / verify gotchas
- **One `xcodebuild` test process at a time**; on `Busy`/`RequestDenied`, shut down sims and kill orphaned `xcodebuild`/`xctest` (repo AGENTS.md "Build & Test").
- **Watch UI tests need an unpaired watch pinned by UDID**: `WATCH_TEST_SIM='platform=watchOS Simulator,id=<26.5-UDID>'`; pairing details in the `simulator-pairing` skill.
- **Local Xcode 27.0 vs CI 26.6** divergence: 27 misses `$`-projection-only `@State` (CI-green) — see the `periphery` skill; `make periphery` reads a stale build index after branch switches (clean `DerivedData/` and rerun first).
- **Warning gate**: any source-located compiler warning (`<path>:<line>:<col>: warning:`) fails the gate in any build. Unfixable toolchain/SDK diagnostics go in `scripts/xcodebuild-warnings.allow` with a one-line rationale; never silence via `Package.swift` flags or CLI `SWIFT_TREAT_WARNINGS_AS_ERRORS` overrides. Checker fixtures: `scripts/tests/warning-check/`.
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide** — scope per-target overrides in `project.pbxproj`, never CLI flags.
- **Concurrency model**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the iOS app and watch app targets only (not `SingleThreadCore`, widget, or test targets); Swift 6 language mode (`SWIFT_VERSION = 6.0`) with `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- **New test suites** must be added to `Makefile`'s `test` target and `scripts/test.sh` if they need explicit `-only-testing` filters (repo AGENTS.md).
- **New `.swift` file needs no pbxproj edit** (synchronized file groups); a new test **target** does.
- **Gate staging** (repo AGENTS.md): phase subagents verify with build + targeted `-only-testing:` suites; the full `./scripts/test.sh` runs ONCE after phases commit via the `run-gate` skill — never `nohup` it.
- Known local-only pre-existing failures: three macOS `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — annotate, don't debug.