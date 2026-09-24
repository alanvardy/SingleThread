# Test-Suite Audit Report — VAR-1075

Status: **Draft — pending full-gate confirmation.** This report is the
deliverable for Phase 4 of the test-suite audit. It records concrete gaps
closed in Phases 1–3, one finding left for user triage, and the remaining
gaps named as explicit non-goals. It does **not** claim the full CI-identical
gate has passed — that runs once after Phases 1–3 commit via the `run-gate`
skill, and the Phase 4 manual checkbox items are intentionally left unchecked.

Companion artifacts in this directory (`research.md`, `structure.md`,
`conventions.md`, `design.md`) contain the original audit basis. Every claim
below is tied to a `file:line` verified against the current checkout at the
time of writing.

---

## 1. Scope & method

This is a **bounded, logic-first audit**, not an exhaustive coverage
measurement. The work targets pure functions, state machines, persistence
round-trips, and view-model branch logic — the seams the codebase already
exposes. SwiftUI `View` bodies, trivial modifiers, and live external-model
paths are **not** test targets; they are enumerated as explicit non-goals in
section 5 with a one-line rationale each.

- **Value bar.** New tests must assert behavior, not self-consistency. The
  bar is set in `design.md` under "Design Decisions/1": a test must exercise
  a real behavior of the code under test. Asserting `isAvailable` about a
  ranker (the `FoundationModelsReminderRankerTests` pattern) does not meet
  the bar (`SingleThread/FoundationModelsReminderRanker.swift:12`).
- **No coverage threshold.** Line/statement coverage percentages were used
  only to *inform* prioritization. No coverage-threshold gate was introduced.
- **Q1/Q2 seams (from `research.md`).** The research question-1 seam is the
  Core's injectable single `init` on `ReminderStore` (`ReminderStore.swift`),
  the `EventKitStoring` protocol (`EventKitStoring.swift:8`), the in-memory
  fake (`InMemoryEventStore.swift`), launch-arg seams (`AppViewModel.swift`,
  `--seed` / `--ui-testing`), and the single cached `AppGroup.defaults`
  instance (`AppGroup.swift:26-27`). The research question-2 seam is the
  clean Core↔`*Tests.swift` mapping pattern in `SingleThreadTests` (most
  Core types have a matching suite), with the documented gaps clustering in
  iOS view/modifier files, the watch `Show*State` holders, and the widget.
- **No exhaustive per-file percentages.** The researchers explicitly did
  **not** compute exhaustive per-file coverage percentages (capped by the
  recon budget; 45 Core files / ~80 iOS test files were not exhaustively
  cross-mapped). See `research.md` "Open Areas". Q1/Q2 lists are the
  high-confidence gaps, not a complete diff.

---

## 2. Gaps closed

Three concrete gaps were closed across Phases 1–3, each independently landable
and leaving the tree green + lint-clean on its own commit.

### (a) Watch `Show*State` holders (Phase 1) — commit `59df56de`

Four previously-untested watch display-preference holders now have dedicated
Swift Testing suites:

| Source file (read-only) | New suite |
| --- | --- |
| `SingleThreadWatch/ShowDateState.swift` | `SingleThreadWatchTests/ShowDateStateTests.swift` |
| `SingleThreadWatch/ShowListState.swift` | `SingleThreadWatchTests/ShowListStateTests.swift` |
| `SingleThreadWatch/ShowRecurrenceState.swift` | `SingleThreadWatchTests/ShowRecurrenceStateTests.swift` |
| `SingleThreadWatch/ShowAlarmsState.swift` | `SingleThreadWatchTests/ShowAlarmsStateTests.swift` |

Each suite mirrors `ShowEnableActionButtonsStateTests.swift`, using
`@Suite(.serialized)` (every test writes the same real `UserDefaults` key).
The holders expose the shape this phase binds to: `@Observable final class`,
`init()` reading `preference.isEnabled`, and `apply(_ value: Bool)` persisting
via `BoolPreferenceStore` then publishing `isEnabled`
(`ShowDateState.swift:13-23`). No production code changed. The commit adds
232 test lines across the four files.

### (b) Widget logic extraction (Phase 2) — commit `a15b5f7f`

The widget's testable logic was extracted from
`SingleThreadWidget/NextThingWidget.swift` into a new pure
`SingleThreadCore` type so it is unit-testable without standing up an
app-extension test target:

- `NextThingDisplayPreferences` — resolves the four per-key
  `BoolPreferenceStore` reads with their `t/f/t/t` fallbacks
  (`SingleThreadCore/Sources/SingleThreadCore/NextThingWidgetLogic.swift:7`).
- `NextThingWidgetLogic` — pure statics (refresh interval, next-refresh-date
  math, authorization → `.noAccess` gate)
  (`SingleThreadCore/Sources/SingleThreadCore/NextThingWidgetLogic.swift:39`).
- Covered by `SingleThreadTests/NextThingWidgetLogicTests.swift`
  (`refreshDateAddsInterval`, `displayPreferencesDefaultPerKeyFallbacks`,
  `displayPreferencesReadPersistedOverrides`, `accessDeniedYieldsNoAccess`).

The SwiftUI `NextThingWidgetView` remains intentionally untested
(`SingleThreadWidget/NextThingWidget.swift:107`) — see the non-goal in
section 5. The widget target already depends on `SingleThreadCore`, so no
new target and no pbxproj edit was needed. The commit is `+137/−35` across
three files (one source file moved logic out; `NextThingWidget.swift`
shrinks).

### (c) AI-sort coordinator trust/fallback (Phase 3) — commit `90c0095a`

A coverage diff against `SingleThreadTests/AISortCoordinatorTests.swift`
showed the coordinator's trust/fallback/debounce/generation surface is
already covered by existing cases (see section 3). Instead of adding the
proposed duplicates, Phase 3 added exactly two genuinely-uncovered
fallback-digest branches:

- `retriesIdenticalRequestAfterRuntimeFailure` — a runtime failure leaves
  `lastCompletedDigest` unset so identical input retries
  (`AISortCoordinatorTests.swift:516`).
- `reRanksAfterSilentFallbackClearsTheDigest` — a blank-rules fallback clears
  the digest so the same rules re-rank (`AISortCoordinatorTests.swift:543`).

Plus one fake ranker (`ErrorSwitchableRanker`) injected at the
`AIReminderRanking` protocol/coordinator boundary. The live
`FoundationModelsReminderRanker` is **never** invoked (see section 5).

---

## 3. Coverage-diff finding (Phase 3)

The structure outline proposed four new AI-sort test cases
(`untrustedFailureFiresOnRankingFailed`, `fallbackErrorEmitsNoOrdering`,
`repeatedIdenticalRulesDoNotReRank`, `staleGenerationResultIsDiscarded`).
Pre-reading `AISortCoordinatorTests.swift` showed **every one is already a
duplicate** of an existing case (structure.md explicitly sanctioned
"if fully covered, ship the report finding instead of duplicate tests").
Mapping (structure's proposed case → existing coverage):

| Structure's proposed case | Already covered by |
| --- | --- |
| `untrustedFailureFiresOnRankingFailed()` | `reportsRuntimeFailureToObserver` (`AISortCoordinatorTests.swift:358`), `retainsPreviousRankingWhenRankerThrows` (`:207`) |
| `fallbackErrorEmitsNoOrdering()` | `fallsBackWhenRankerUnavailable` (`:245`), `doesNotReportUnavailableAsARuntimeFailure` (`:374`), `retainsPreviousRankingWhenRankerThrows` (`:207`) |
| `repeatedIdenticalRulesDoNotReRank()` | `skipsIdenticalInputs` (`:276`), `skipsRepeatedCompletedRequests` (`:499`) |
| `staleGenerationResultIsDiscarded()` | `ignoresStaleGeneration` (`:441`), `reranksWhenContentChangesInFlight` (`:480`) |
| `digest` / candidate-content change | `reranksWhenCandidateContentChanges` (`:459`) |
| reconcile contract | `reconcilesUnknownAndMissingIds` (`:411`) |
| blank/unavailable silent paths | `silentPathsNeverReportFailures` (`:392`), `skipsBlankRules` (`:229`) |

Two genuine uncovered branches remained — both are the "the fallback clears
the digest" paths in `AISortCoordinator.update` — and were added:

- `retriesIdenticalRequestAfterRuntimeFailure` (`AISortCoordinatorTests.swift:516`)
- `reRanksAfterSilentFallbackClearsTheDigest` (`AISortCoordinatorTests.swift:543`)

No duplicate tests were written; no production code changed
(`AISortCoordinator` / `AIReminderRanking` are consumed only).

---

## 4. Finding for user triage (recorded, not fixed)

**Watch `Show*State` persistence diverges between `UserDefaults.standard` and
`AppGroup.defaults`. Five of the six watch display-preference holders persist
to `UserDefaults.standard`:**

| Holder | Store |
| --- | --- |
| `ShowDateState.swift:28-29` | `BoolPreferenceStore(defaults: .standard, …)` |
| `ShowListState.swift:29` | `BoolPreferenceStore(defaults: .standard, …)` |
| `ShowRecurrenceState.swift:29` | `BoolPreferenceStore(defaults: .standard, …)` |
| `ShowAlarmsState.swift:29` | `BoolPreferenceStore(defaults: .standard, …)` |
| `ShowCompletionGlowState.swift:27-28` | `BoolPreferenceStore(defaults: .standard, …)` |

…while `ShowEnableActionButtonsState` reads and writes `AppGroup.defaults`:

- read: `ShowEnableActionButtonsState.swift:17-19` — builds a
  `BoolPreferenceStore(key: enableActionButtons, fallback: true)` whose
  default store is `AppGroup.defaults` (falls back to `.standard` when the
  group is absent).
- write: `ShowEnableActionButtonsState.swift:27-28` —
  `AppGroup.defaults.set(value, forKey: …)`.

The watch sync pipeline also persists the received mirror values to
`.standard`: `WatchAppViewModel.swift:232-243` builds the sync service's
`BoolPreferenceStore`s (showUndated, showDate, showRecurrence, showAlarms,
showList, showCompletionGlow) all with `defaults: .standard`, so the wire and
the `Show*State` holders agree **except** for the enable-action-buttons flag,
which is the one value that reads/writes `AppGroup.defaults`.

**Why it diverges (recording, not advocating a fix):** `AppGroup.defaults`
is a suite-named `UserDefaults` (`AppGroup.swift:26-27`). On a real watch the
suite does not exist, so `AppGroup.defaults` falls back to `.standard` and
the two stores **converge**. On a simulator the suite **does** exist, so
`AppGroup.defaults` and `.standard` are distinct and silently **diverge** —
the exact scenario the repo's AGENTS.md warns about at `AGENTS.md:61`
("Every persisted value shared with the watch must round-trip through
`AppGroup.defaults`").

**Question for the user: intentional or a latent bug?** Were the four
`show*` display preferences intended to be phone-shared (round-tripping via
`AppGroup.defaults`), or are they genuinely watch-local (correct as-is on
`.standard`, matching the sync stores)? Phase 1 tested the holders' actual
store (`UserDefaults.standard`) and deliberately did **not** change
persistence semantics. This ticket leaves the divergence **recorded, not
fixed** (per `design.md` "What We're NOT Doing": no persistence-semantics
change).

---

## 5. Documented non-goals (one-line rationale each)

- **SwiftUI `View` / `ViewModifier` bodies** — a unit test asserts nothing
  real over pure SwiftUI layout/paint code, so they are skipped:
  - `SingleThread/EmptyStateCard.swift:11` (`struct EmptyStateCard: View`) — presentational; no branchable logic.
  - `SingleThread/ReminderCardView.swift:10` (`struct ReminderCardView: View`) — presentational reminder chrome.
  - `SingleThread/ControlPlateModifier.swift:12` (`struct ControlPlateModifier: ViewModifier`) — cosmetic modifier; trivial.
  - `SingleThread/BackgroundSettingsView.swift:9` (`struct BackgroundSettingsView: View`) — declarative picker UI.
  - `SingleThread/ExcludedListsView.swift:8` (`struct ExcludedListsView: View`) — list rendering over an already-tested value.
  - `SingleThread/NotificationsSettingsView.swift:6` (`struct NotificationsSettingsView: View`) — declarative toggles.
  - `SingleThread/PurchaseSettingsView.swift:12` (`struct PurchaseSettingsView: View`) — StoreKit-driven chrome; entitlement logic lives in `EntitlementStore`.
  - `SingleThread/SettingsBindings.swift:24` (`final class SettingsBindings`) — UI-state bindings, not domain logic.
  - `SingleThread/TextSizeModifier.swift:8` (`struct TextSizeModifier: ViewModifier`) — trivial style modifier.
  - `SingleThread/CreationFeedback.swift:8` (`enum CreationFeedback`) — view-state enum; no branchable behavior beyond UI.
  - `SingleThread/AuthorizationRequiring.swift:10` (`protocol AuthorizationRequiring`) — a protocol seam, not an implementation to test.
- **The widget's SwiftUI view** — `SingleThreadWidget/NextThingWidget.swift:107` (`struct NextThingWidgetView: View`) stays untested: testing it would require an app-extension test target (pbxproj IDs, scheme wiring, `scripts/test.sh`, `Makefile`, CI matrix) for a thin SwiftUI surface; its logic was instead extracted and covered in Core (section 2b).
- **The live `FoundationModelsReminderRanker`** — `SingleThread/FoundationModelsReminderRanker.swift:12` (`nonisolated struct FoundationModelsReminderRanker: AIReminderRanking`): the Foundation model is unavailable on CI, so real ranking cannot be invoked deterministically. It is exercised only through a fake ranker at the `AIReminderRanking` protocol / `AISortCoordinator` boundary (Phase 3). The existing `FoundationModelsReminderRankerTests` only asserts `isAvailable` self-consistency and is not a model-behavior test.
- **The false-alarm "gap trio"** — three research-listed "gaps" are already covered transitively and need **no** new tests:
  - `ReminderDateFilter` → `SingleThreadTests.swift:173` (`struct ReminderDateFilterTests`).
  - `ReminderIntentSupport` → `SingleThreadTests/ReminderIntentSupportTests.swift:14` (`struct ReminderIntentSupportTests`).
  - `EntitlementState` → `SingleThreadTests/EntitlementSyncTests.swift:113-123` (`entitlementStateApplySetsIsEnabled`).
- **No new test target** — the widget-enabling surface was covered by extracting logic into the existing `SingleThreadCore` package and `SingleThreadTests` suite, avoiding pbxproj/scheme/CI-matrix wiring (per `design.md` "Do NOT follow").
- **No persistence-semantics change** — the `AppGroup.defaults` vs `.standard` divergence (section 4) is reported, not fixed.
- **No coverage-threshold gate** — no percentage line-count gate was introduced; coverage informed prioritization only.

**Phase 2 spike outcome included:** the widget-feasibility spike (**passed**,
so the widget is a gap closed, not a non-goal). `makeEntry` exposed ≥3
genuinely pure, behavior-worthy units (per-key preference resolution,
refresh-date math, authorization → `.noAccess` gate), so the logic was
extracted to Core rather than reclassified as a non-goal (this is the
`NextThingWidgetLogic.swift` / `NextThingDisplayPreferences.swift` work in
section 2b).

---

## 6. Pre-existing local-only failure (do not debug)

Three macOS `SingleThreadTests/EntitlementStoreTests.swift` cases fail locally
and are green on CI — **annotate, do not debug**:

- `isEntitledSurvivesStoreRecreation` (`EntitlementStoreTests.swift:42`)
- `initialRefreshSettlesResolvedFlag` (`EntitlementStoreTests.swift:76`)
- `hostStoreKitIsClean` (canary) (`EntitlementStoreTests.swift:91`)

These are a known local-environment artifact (storekit/simulator state on
this macOS checkout) and are not caused by the audit diff. They are recorded
in AGENTS.md under "Before Committing". None of Phases 1–3 touched
`EntitlementStoreTests.swift`, and no new test in this audit exercises
`HostStoreKit`/StoreKit persistence.

---

## Non-goal / coverage summary at a glance

- **Closed:** 4 watch `Show*State` suites · widget logic → `SingleThreadCore`
  + `NextThingWidgetLogicTests` · 2 AI-sort fallback digest branches.
- **Recorded, not fixed:** `Show*State` `.standard` vs `ShowEnableActionButtons`
  `AppGroup.defaults` divergence.
- **Documented non-goals:** SwiftUI `View`/modifier bodies (11 files), widget
  SwiftUI view, live `FoundationModelsReminderRanker`, the false-alarm gap
  trio, no new test target, no persistence-semantics change, no
  coverage-threshold gate.
- **No source churn from the audit's decisions beyond:** the single widget
  extraction (Phase 2) and the two AI-sort test branches (Phase 3). Phase 1
  and Phase 4 add tests/docs only.