# Structure Outline

## Approach

A bounded, logic-first test audit: add high-signal tests where real logic and
existing seams allow, extract only the widget's testable logic into
`SingleThreadCore` (the one source refactor), and ship a written report naming
the remaining gaps as explicit non-goals. No new test target, no SwiftUI view
tests, no persistence-semantics changes. Each phase is independently valuable
and leaves the tree green + lint-clean on its own commit.

Order is dependency → risk → value: the walking skeleton proves the ticket's
harness cheaply, the risky widget refactor is front-loaded (with a
feasibility spike so a dead end becomes a documented non-goal early), then the
lower-risk coverage depth, then the report.

---

## Phase 1: Walking skeleton — watch `Show*State` holders (test-only)

Four untested watch display-preference holders get dedicated suites. Proves
the end-to-end slice for this ticket: real production type → real
`BoolPreferenceStore`/`UserDefaults` persistence → behavior assertion →
targeted watch unit run green, using the existing `@Suite(.serialized)`
pattern. No production code changes.

**Files**: `SingleThreadWatch/{ShowDateState,ShowListState,ShowRecurrenceState,ShowAlarmsState}.swift`
(read-only), new `SingleThreadWatchTests/{ShowDateState,ShowListState,ShowRecurrenceState,ShowAlarmsState}Tests.swift`;
model `SingleThreadWatchTests/ShowEnableActionButtonsStateTests.swift`.

**Key changes** (production shape the tests bind to, unchanged):
- `@Observable final class ShowDateState { init(); private(set) var isEnabled: Bool; func apply(_ value: Bool) }`
  — same shape for List/Recurrence/Alarms; backed by
  `BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true)`
  (`showList` fallback `false`; recurrence/alarms `true`).

**Contract**: `BoolPreferenceKey.{showDate,showList,showRecurrence,showAlarms}`
raw keys + `fallback` defaults; these holders persist to `UserDefaults.standard`.
Phase 4's report depends on this fact (the `.standard` vs `AppGroup.defaults`
divergence is *recorded*, not fixed).

**Tests**: per holder, `unsetKeyDefaultsTo<fallback>()`, `persistedValueStaysOnInit()`,
`applyRoundTripsTrueAndFalse()`, `applyPersistsToStandardDefaults()` — 4 suites ×
4 cases; `@Suite(.serialized)` + a `clearKey()` helper because all tests write
the same real key (mirrors `ShowEnableActionButtonsStateTests`).

**Verify**: `scripts/test-one.sh SingleThreadWatchTests/ShowDateStateTests`
(and `…/ShowListStateTests`, `…/ShowRecurrenceStateTests`,
`…/ShowAlarmsStateTests`) all green; `make watch-build` passes.

---

## Phase 2: Widget logic extraction → Core tests (riskiest — front-loaded)

The widget has zero unit tests and no test seam. Extract its pure logic into a
new `SingleThreadCore` value type, keep the SwiftUI `NextThingWidgetView`
untested, and cover the extracted type from `SingleThreadTests`. No new target.

**Step 0 — feasibility spike (gate)**: read `makeEntry`
(`NextThingWidget.swift:61-96`) and confirm ≥3 genuinely pure, behavior-worthy
units (preference resolution with per-key fallbacks; refresh-date math;
authorization→`.noAccess` gate). If not, stop, record widget as a documented
non-goal in Phase 4, and proceed to Phase 3 — do not extract a thin surface.

**Files**: `SingleThreadWidget/NextThingWidget.swift` (modified — call site),
`SingleThreadCore/Sources/SingleThreadCore/NextThingWidgetLogic.swift` (new),
new `SingleThreadTests/NextThingWidgetLogicTests.swift`.

**Key changes**:
- `struct NextThingDisplayPreferences: Equatable, Sendable { showsDate, showsList, showsRecurrence, showsAlarms: Bool; init(defaults: UserDefaults) }` — resolves the four `BoolPreferenceStore` reads (fallbacks `t/f/t/t`).
- `enum NextThingWidgetLogic` — `static let refreshInterval: TimeInterval = 5*60`; `static func nextRefreshDate(from: Date) -> Date`; `static func isAccessGranted(_ status: EKAuthorizationStatus) -> Bool`.
- `NextThingProvider.makeEntry` builds the new type and keeps only the real `ReminderStore`/`reload()` call; `NextThingEntry` stays in the widget target.

**Contract**: `NextThingWidgetLogic` is pure and `SingleThreadCore`-public —
`SingleThreadTests` imports it, the widget target already depends on Core
(pbxproj:357). No new pbxproj entry (synchronized groups).

**Tests**: `refreshDateAddsInterval()`, `displayPreferencesApplyPerKeyFallbacks()`
(write each key to a temp `UserDefaults` suite, assert all four),
`displayPreferencesReadPersistedOverrides()`, `accessDeniedYieldsNoAccess()`
(happy + sad). macOS-safe — no `#if os(...)` needed; if any new iOS-only case
appears, gate it `#if os(iOS)`.

**Verify**: `scripts/test-one.sh SingleThreadTests/NextThingWidgetLogicTests`
green; `make build` passes (widget extension still compiles/embeds).

---

## Phase 3: AI-sort coordinator trust/fallback (fake `AISortRanking`)

Exercise `AISortCoordinator`'s trust/fallback/generation behavior through an
injected fake ranker — never the live `FoundationModels` model.

**Step 0 — coverage diff (gate)**: pre-read `AISortCoordinatorTests.swift`
(23 matches) against the coordinator's contract; add only uncovered branches.
If fully covered, ship the report finding instead of duplicate tests.

**Files**: `SingleThreadTests/AISortCoordinatorTests.swift` (extend);
possibly `SingleThreadTests/TestFixtures.swift` (fake ranker) or a private fake
following `CompletedReturningEventStore` (`ReminderStoreTests.swift:1086`).

**Key changes**:
- `private struct FailingRanker: AIReminderRanking { let error: Error; var isAvailable: Bool { true }; func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] { throw error } }` + a controllable success/throw/stall fake.
- Cases for `AIRankingError` classification (`static func isFallback(_:)`), `onRankingFailed` firing on untrusted failure, no emit on fallback, and `digest`/generation skipping stale results.

**Contract**: `AIReminderRanking` protocol (`rank` throws, `isAvailable`) and
`AISortCoordinator.reconcile/digest/isFallback` statics — consumed, not changed.

**Tests**: `untrustedFailureFiresOnRankingFailed()`, `fallbackErrorEmitsNoOrdering()`,
`repeatedIdenticalRulesDoNotReRank()` (digest), `staleGenerationResultIsDiscarded()`
— happy + sad paths.

**Verify**: `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests` green;
`make lint` clean for the touched file.

---

## Phase 4: Audit report + hardening review (docs-only, final)

Ship the audit's deliverable: a written report enumerating remaining gaps and
risks as explicit non-goals/follow-ups. Depends on Phases 1–3 outcomes.

**Files**: `.pi/orksorksorks/alanvardy-var-1075-test-suite-audit/audit-report.md`
(new artifact; committed with the phase). Optional: one-paragraph pointer in
the PR description.

**Key content**:
- Gaps closed: watch `Show*State`, widget logic, AI-sort trust/fallback.
- Findings for user triage: watch `Show*State` persist to `UserDefaults.standard`
  while `ShowEnableActionButtonsState` uses `AppGroup.defaults` — is this
  divergent persistence intentional? (recorded, not fixed).
- Documented non-goals: SwiftUI `View`/modifier bodies (`EmptyStateCard`,
  `ReminderCardView`, `ControlPlateModifier`, …); widget SwiftUI view;
  live `FoundationModelsReminderRanker`; the false-alarm "gap trio"
  (`ReminderDateFilter`, `ReminderIntentSupport`, `EntitlementState` already
  covered transitively); widget-as-non-goal if the Phase 2 spike failed.
- Pre-existing local-only macOS `EntitlementStoreTests` failures (don't debug).

**Contract**: none — pure documentation.

**Tests**: none (no code). Keep the report's claims tied to file:line evidence.

**Verify**: report exists and names each non-goal with a rationale; no source
diff. Full CI-identical gate (`scripts/test.sh`, via the `run-gate` skill) runs
**once** after Phases 1–3 commit.

---

## Testing Checkpoints

- **After Phase 1**: the four watch `Show*State` suites + `make watch-build` green → advance.
- **After Phase 2 spike**: extraction is meaningfully testable (or explicitly reclassified as a non-goal) → advance.
- **After Phase 2**: `NextThingWidgetLogicTests` + `make build` green → advance.
- **After Phase 3**: extended `AISortCoordinatorTests` green, no duplicate coverage → advance.
- **After Phase 4**: report complete; run the full gate **once** via `run-gate` — do not `nohup` ad-hoc.
- **Never skip a failed slice**: a red suite stops advancement; completed slices stay independently landable.