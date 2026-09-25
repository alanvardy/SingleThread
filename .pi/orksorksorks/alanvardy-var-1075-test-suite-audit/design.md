# Design Discussion — Test-Suite Audit (VAR-1075)

## Current State

The repo has a three-layer, well-seamed architecture. Research found the
seams are already strong; the gaps are coverage, not structure.

- **Core pure logic** (`ReminderSkip.swift:18`, `:56`, `:131`;
  `ReminderSort.swift:5`; `AIReminderRanking.swift:36`, `:77`, `:123-157`)
  is EK-free and directly unit-testable.
- **Stateful `ReminderStore`** (`ReminderStore.swift:16`) owns the
  `EKEventStore` behind `any EventKitStoring` (`:17-78`), with every
  persistence store injected and a no-op `settle` hook for tests.
- **Composition roots** (`AppViewModel.swift:17,31-69`;
  `WatchAppViewModel.swift:10`) select real vs. in-memory stores from launch
  args (`AppViewModel.swift:231-317`).
- **Seams**: `EventKitStoring.swift:8` / `InMemoryEventStore.swift:13`;
  `--seed` / `--ui-testing` (`AppViewModel.swift:246-317`);
  `AppGroup.defaults` (`AppGroup.swift:27-30`, single cached instance);
  preview/test `ReminderStore` injection.
- **Framework split**: `SingleThreadTests` and `SingleThreadWatchTests` are
  Swift Testing (`import Testing`, `@Test`); `SingleThreadUITests` and
  `SingleThreadWatchUITests` are XCTest. `SingleThreadTests` is the single
  combined iOS+macOS unit suite; platform selection is by whole-file/inline
  `#if os(...)` (`AppDelegateTests.swift:1`, `SettingsViewTests.swift:82`).

**Coverage reality** (research Q1/Q2 plus a targeted analyzer pass):

- Core has ~45 source files and ~54 unit-test files; most types have a
  matching `*Tests.swift`. The research "gap trio" is a false alarm:
  `ReminderDateFilter.swift:28` is covered by
  `SingleThreadTests.swift:173-248`, `ReminderIntentSupport.swift:30` by
  `ReminderIntentSupportTests.swift`, and `EntitlementState.swift:10` by
  `EntitlementSyncTests.swift:113-123`.
- **Widget** (`NextThingWidget.swift`, `SingleThreadWidgetBundle.swift`) is
  the only module with zero unit tests.
- **Watch** `ShowAlarmsState.swift:13`, `ShowDateState.swift:13`,
  `ShowListState.swift:13`, `ShowRecurrenceState.swift` are untested,
  structurally identical to the tested `ShowCompletionGlowState` /
  `ShowEnableActionButtonsState` holders, and reachable from
  `SingleThreadWatchTests` via `@testable import SingleThreadWatch`
  (`ShowCompletionGlowStateTests.swift:3`) with no pbxproj change.
- **`FoundationModelsReminderRankerTests.swift`** only asserts
  `isAvailable` self-consistency; real ranking is never invoked (the model
  is unavailable on CI, so it cannot be invoked deterministically).
- Remaining untested iOS files cluster in SwiftUI `View`/modifier bodies
  (`EmptyStateCard`, `ReminderCardView`, `ControlPlateModifier`, …) where a
  unit test asserts nothing real.

## Desired End State

A bounded, high-signal test-suite audit that:

1. Closes the concrete coverage gaps where pure/stateful logic actually
   exists — watch `Show*State` holders, the widget's extracted logic, and
   the AI-sort coordinator's trust/fallback seam.
2. Extracts the widget's testable logic into `SingleThreadCore` so it is
   testable without standing up an app-extension test target.
3. Ships a written audit report enumerating remaining gaps and risks as
   explicit non-goals/follow-ups.
4. Does **not** churn already-well-seamed source.

**Verification**: new suites are green under targeted `-only-testing:` runs
(`SingleThreadTests`, `SingleThreadWatchTests`), `make format` + `make lint`
clean, and the full CI-identical gate (`scripts/test.sh`, via the `run-gate`
skill) passes once after phases commit.

## Patterns to Follow

Follow (existing, good):

- **Core-pure-logic tests**: `ReminderSkipTests.swift`,
  `ReminderSortTests` (struct in `ReminderSkipTests.swift`),
  `ReminderDateFilterTests` in `SingleThreadTests.swift:173-248` —
  deterministic, no EventKit.
- **`InMemoryEventStore` injection**: `ReminderStoreTests.swift` (90+
  injections, `InMemoryEventStore()` + `loadsReminders: false` + pre-seeded
  `reminders/skippedIDs`); private fakes like
  `CompletedReturningEventStore` at `ReminderStoreTests.swift:1086`.
- **Serialized Swift Testing for real-`UserDefaults` holders**:
  `ShowEnableActionButtonsStateTests.swift:8` and
  `ShowCompletionGlowStateTests.swift:12` both use `@Suite(.serialized)`
  because every test writes the same real key. New watch `Show*State`
  suites must do the same.
- **Protocol-seam fakes**: `FakeSession`
  (`SingleThreadTests/TestFixtures.swift:70`, os-gated), the `ReminderRanking`
  protocol (`AIReminderRanking.swift:36`) for a fake ranker.
- **Naming**: unit-test names must NOT start with `test`/`testing`
  (SwiftFormat strips the prefix); UI-test names keep `test…`.

Do NOT follow:

- Whole-file UI/XCTest suites as a model for new tests — unit tests are
  Swift Testing and belong in the unit targets.
- Adding a test target "because a module has none" — the widget's pure
  surface is too thin to justify the app-extension test-target cost
  (pbxproj IDs, scheme TestAction, `scripts/test.sh`, Makefile, CI matrix,
  plus an unproven `@testable import` of an app-extension product).
- Asserting only self-consistency (`FoundationModelsReminderRankerTests`'s
  `isAvailable` pattern) — every new test must assert behavior.

## Design Decisions

1. **Value bar — logic-first.** New tests target pure functions, state
   machines, persistence round-trips and view-model branch logic. SwiftUI
   `View` bodies and trivial modifiers are skipped and named in the report
   with a one-line rationale. Coverage numbers may *inform* prioritization
   but no line-coverage threshold gates the work.

2. **Widget — extract to Core.** Move the widget's testable logic
   (refresh-cadence/timeline-date math and entry construction from
   preference/authorization state) into a pure `SingleThreadCore` type that
   both the widget (already a `SingleThreadCore` dependency, pbxproj:357)
   and `SingleThreadTests` import. The SwiftUI `NextThingWidgetView` stays
   untested. No new target.

3. **Watch `Show*State` — test, then flag.** Add dedicated, `@Suite(.serialized)`
   Swift Testing files under `SingleThreadWatchTests/` mirroring
   `ShowEnableActionButtonsStateTests` (init-from-pref fallback, `apply`
   round-trip, persistence). Flag the `.standard` vs. `AppGroup.defaults`
   divergence from `ShowEnableActionButtonsState` as a finding for user
   triage; do NOT change persistence in this ticket (these look watch-local
   display prefs, not phone-shared values).

4. **Refactors — targeted only.** Source changes are limited to what a test
   requires: widget logic extraction (decision 2) and, if needed, an
   injection seam for the ranker. No broad View/ViewModel extraction; the
   `EventKitStoring` + injectable-`ReminderStore` seams already cover the
   testability surface.

5. **Bounding — phases + a written report.** Work is implemented in
   module-scoped phases (watch `Show*State`; widget extraction + Core tests;
   AI-sort coordinator trust/fallback via a fake `ReminderRanking`), each
   verified with targeted suites. The audit's output is a report artifact
   listing remaining gaps and risks. `FoundationModelsReminderRanker`'s
   real-model behavior is only ever exercised through a fake ranker at the
   protocol/coordinator boundary — never the live model.

## What We're NOT Doing

- No new test target (widget or otherwise) and no pbxproj/scheme/CI-matrix
  wiring.
- No tests for SwiftUI `View`/modifier bodies or for the widget's SwiftUI
  view.
- No attempt to invoke `FoundationModels` in tests; no CI-dependent AI
  behavior assertions.
- No persistence-semantics changes (AppGroup vs. `.standard`) — the
  divergence is reported, not fixed.
- No coverage-threshold gate; no exhaustive file-parity coverage.
- No child tickets; all work lands on the main ticket branch.
- No changes to already-covered Core "gap trio".

## Open Risks

- **Widget extraction scope**: `makeEntry` (`NextThingWidget.swift:61-96`)
  is `@MainActor` and reads preference stores + `EKEventStore` authorization
  status. Extracting only the pure parts may leave a thin, low-value surface;
  the plan must confirm the extracted type is meaningfully testable before
  committing to it. If not, widget logic becomes a documented non-goal.
- **Watch persistence divergence**: whether `showDate` / `showList` /
  `showRecurrence` / `showAlarms` are watch-local or phone-shared was not
  confirmed; if they are phone-shared, decision 3's "flag, don't fix" leaves
  a real bug open (reported, not silently deferred).
- **Ranker seam**: if `AISortCoordinator`'s trust/fallback paths are already
  fully covered by `AISortCoordinatorTests.swift` (23 matches), the
  fake-ranker work may reduce to a small number of added cases; the plan
  must diff existing coverage before writing new tests.
- **macOS unit phase**: `SingleThreadTests` runs on macOS too, so any new
  iOS-only test must declare `#if os(iOS)` (or be macOS-safe); three known
  local-only macOS `EntitlementStoreTests` failures are pre-existing and must
  not be debugged.