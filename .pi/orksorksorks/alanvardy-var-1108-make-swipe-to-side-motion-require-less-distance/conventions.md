# Conventions — build/test/lint/format/verify + test-suite inventory

Canonical commands and test-suite layout for the SingleThread monorepo
(`/Users/vardy/dev/SingleThread` git root; this worktree at
`~/dev/alanvardy-var-1108-...`). Dense references; gate consumers should rely
on this instead of re-reading the source tree.

## Canonical build/test/lint/format/verify commands

From `Makefile` (gate is `scripts/test.sh`):
- **Build**: `make build` — `xcodebuild -scheme SingleThread -destination
  '$(SIM)' -configuration Debug -derivedDataPath DerivedData
  build-for-testing` (Makefile `~40`).
- **Unit tests**: `make test` → `./scripts/test.sh --unit-only` (runs
  `test -only-testing:SingleThreadTests` on `platform=macOS`, i.e. macOS-native
  macOS, Makefile `~71` / test.sh `260-274`).
- **UI tests**: `make ui-test` → `./scripts/test.sh --ui-only` (iOS sim,
  `build-for-testing` then `test-without-building -only-testing:
  SingleThreadUITests`, test.sh `278-296`).
- **Full gate**: `./scripts/test.sh` (no arg) = formatter, SwiftFormat
  checkout, SwiftLint `--strict`, warning-check self-test, iOS build, watch
  build, Periphery, iOS UI tests, watch UI tests, watch unit tests, macOS unit
  tests (test.sh `213-268`). Run once, per-phase-gated subagents don't rerun it.
- **Watch UI / unit**: `make watch-ui-test` (`-only-testing:
  SingleThreadWatchUITests`) / `make watch-test` (`-only-testing:
  SingleThreadWatchTests`) (Makefile `~77-90`).
- **Lint**: `make lint` = `swiftformat --lint <all dirs>` then
  `swiftlint lint --strict` (Makefile `~96-98`). CI runs `--strict`, so every
  SwiftLint warning is an error.
- **Format**: `make format` = `swiftformat <all dirs>` then `swiftlint --fix`
  (Makefile `~100-102`). SwiftFormat strips `test`/`testing` prefixes from
  test names — unit tests must NOT start with `test`/`testing`.
- **Periphery** (unused-code scan): `make periphery` =
  `periphery scan --strict -- -destination "$(SIM)"` (Makefile `~105`); the
  gate uses `periphery scan --skip-build --index-store-path
  DerivedData/Index.noindex/DataStore --strict` (test.sh `~252`).
- **Coverage**: `make coverage` (iOS unit), `make coverage-ui` (iOS UI),
  `make coverage-all` (full) — `-enableCodeCoverage YES` (Makefile `~55-73`).
- **Single test via `scripts/test-one.sh <Target/Suite/case> [timeout]`** —
  pins destination, bounds the run, and **exits non-zero when zero cases ran**
  (a zero-match `-only-testing:` prints `TEST SUCCEEDED` and exits 0). Use for
  red-first checks / focused suites.
- **Targeted suite**: `xcodebuild -only-testing:SingleThreadTests` (Swift
  Testing) / `-only-testing:SingleThreadUITests` (XCTest, a11y audit).

## Destination pinning (critical)

- Precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared
  default (`platform=iOS Simulator,name=iPhone 17`).
- A bare `name=` iOS destination is ambiguous with multiple runtimes and can
  hang; an unanchored name match can select the leftover **`Gate iPhone 17`**
  sim. `scripts/test.sh` resolves names to a concrete UDID and pre-boots
  (`resolve_sim_udid`, `preboot_sim`, test.sh `33-63`).
- The iOS **app** is pinned in `.simulator_id`; `iPhone 17` default; `iPad
  (A16)` also supported. CI runs both in parallel matrix jobs.
- **One xcodebuild test process at a time.** On `Busy`/`RequestDenied`, shut
  down sims + kill orphaned `xcodebuild`/`xctest` (simulator-pairing skill).
- Watch UI tests need an **unpaired** watch pinned by UDID:
  `WATCH_TEST_SIM='platform=watchOS Simulator,id=<26.5-UDID>'`.
- macOS unit tests run on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO`.
- Local known-fail three `EntitlementStoreTests`: `isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` — pre-existing on
  this machine, annotate as such, don't debug. `make periphery` reads a stale
  build index after branch switches — clean `DerivedData/` first.
- Warning gate: any source-located compiler warning fails the gate; unfixable
  SDK warnings belong in `scripts/xcodebuild-warnings.allow` with a rationale.

## Test-suite inventory

All unit tests use **Swift Testing** (`import Testing`, `@Test`), not XCTest.
UI tests use XCTest. iOS unit tests run on macOS-native (no `#if os(...)`
gating on the phone target since the suite runs on host); UI/XCTest runs on the
iOS sim. Files relevant to the reminder-card / swipe / list area:

| File (SingleThreadTests/) | Coverage |
|---|---|
| `SwipePromptTests.swift` | The focused swipe-prompt suite: `promptShownWhenEnabled` (`:7`), `promptHiddenWhenDisabled` (`:37`), `dismissButtonHasAccessibilityLabel` (`:44`), via `String(describing: view.body)` reflection; `makeCard(showSwipePrompt:)` helper (`:58-63`). |
| `SettingsViewTests.swift` | `settingsBindingsCarriesShowSwipePrompt` (`:29`) default-true / false round-trip (`:31-33`); "Show swipe prompt" caption render (`:121,134-136`). |
| `ReminderDisplayRowTests.swift` | `captionCarriesListAndPriority`/`captionCarriesDueDate`/`captionOmitsAbsentParts`/`rowRendersItsTitle` (`:11,17,23,29`) — card caption/row text. |
| `ShowAlarmsTests.swift` / `ShowDateTests.swift` / `ShowRecurrenceTests.swift` | Construct `ReminderCardView` directly with `.constant` bindings; individual card fields (`:25-26` / `:34-36` / `:25-26`). |
| `FilteredRemindersListViewTests.swift` | `filteredRemindersListViewRendersEveryDisplay` (`:9`), `...RendersOnlyWhatItIsGiven` (`:25`). |
| `ReminderStoreTests.swift` | Domain list/ordering; stores built with `loadsReminders: false` (e.g. `:27-29,41-43,52-54`) or `InMemoryEventStore()` (`:149`). |
| `UITestingSeedTests.swift` | `--seed` seams: `fromLaunchArguments` malformed/no-JSON/absent→nil (`:180-183`); seeded `InMemoryEventStore` (`:186`); `resetPersistedStateClearsShowSwipePrompt` (`:220-223`). |
| `CardPlateModifierTests.swift` / `BackgroundCardTests.swift` | Plate composition / empty-state/plate/swipe-prompt visual rhythm. |
| `ContentViewModelTests.swift` / `AppViewModelSyncWiringTests.swift` / `ListContentTests.swift` | ViewModel pumping, swipe-prompt persisted-key wiring, list-content state machine (`:.allDone`/`.empty`/`.reminder`). |
| `Accessibility-adjacent` | `TestFixtures.swift`, `LocalizationTestHelpers.swift`, `StubBundle.swift` — shared fixtures/seams. |

| File (SingleThreadUITests/) | Coverage |
|---|---|
| `SingleThreadUITests.swift` | XCTest: `testLaunchAndRenderSmoke` (`:26`) seeds via `--ui-testing` + `--seed` JSON `InMemoryEventStore`, asserts cards/complete/skip/dictate buttons/priority marker via `app.staticTexts`/`app.buttons` (`:43-67`), iOS a11y audit (`:68-77`); language-switch tests; launches with `app.launchArguments = ["--ui-testing"]` (`:38,82,154`). **No test performs a swipe gesture, asserts the swipe prompt in-app, or drives scroll/`.refreshable`** — grep for `swipe|Swipe` here returns no matches. |

## Build/verify gotchas surfaced by research

- New **unit-test names must not start with `test`/`testing`** (SwiftFormat
  strips them). UI-test (XCTest) names keep `test…` and are SwiftFormat-excluded.
- Force-unwrapping is banned outside test code; `SingleThreadTests/.swiftlint.yml`
  relaxes it for fixtures.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; scope per-target pbxproj
  overrides if ever needed — never CLI flags.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the iOS app + watch targets
  (Async funcs default `@MainActor`); `SingleThreadCore`, widget, test targets
  do NOT enable it — annotate `@MainActor` explicitly there.
- New `.swift` files need no pbxproj edit (synchronized file groups). A **new
  test target** needs pbxproj object IDs, scheme TestAction wiring, a
  `-only-testing` entry in `scripts/test.sh`, and CI matrix entries — see
  `Makefile` `test`/`ui-test` and test.sh mode sections before adding one.
- Performance keeps `DEBUG_INFORMATION_FORMAT = dwarf` on debug builds (fast
  incremental); release switches to `dwarf-with-dsym`.
- `verify_deployment_target` (test.sh `~170-200`) enforces settled iOS 17.0 /
  watchOS 11.0 / macOS 26.5 floors — don't touch floors without updating the
  literal counts.