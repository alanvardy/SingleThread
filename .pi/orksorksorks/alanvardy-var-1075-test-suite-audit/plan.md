# Implementation Plan — Test-Suite Audit (VAR-1075)

## Overview

Close the concrete coverage gaps where real logic and existing seams allow it —
watch `Show*State` preference holders, the widget's extracted pure logic, and
the AI-sort coordinator's trust/fallback branches — without adding a test target
or changing persistence semantics. Ship a written audit report naming the
remaining gaps as explicit non-goals.

**Phase order (from `structure.md`, unchanged):** 1 watch holders → 2 widget
extraction → 3 AI-sort coordinator → 4 report. No codegen, no migrations, no
schema version bumps.

### Guardrails (apply to every phase)

- No new Xcode target; `.swift` files need no pbxproj edit (synchronized groups).
- Unit-test names must **not** start with `test`/`testing`; classes are Swift
  Testing (`import Testing`, `@Test`). `SingleThreadWatchUITests` keeps `test…`.
- Run `make format` then `make lint` before each phase commit.
- Phase verification uses the build + targeted `-only-testing:` suites only.
  The full CI-identical gate (`scripts/test.sh`) runs **once** after Phases 1–3
  commit, via the `run-gate` skill — never `nohup` it ad-hoc.
- Do not touch `.pi/orksorksorks/**` files in source commits except the Phase 4
  report (the deliverable); `git status` before each commit.

---

## Phase 1: Walking skeleton — watch `Show*State` holders (test-only)

### Changes

#### 1. New test files under `SingleThreadWatchTests/`

**Action**: create four files, one per holder. Files:
`SingleThreadWatchTests/ShowDateStateTests.swift`,
`ShowListStateTests.swift`, `ShowRecurrenceStateTests.swift`,
`ShowAlarmsStateTests.swift`.

Each mirrors `ShowEnableActionButtonsStateTests.swift`, except the holders read
and write `UserDefaults.standard` (not `AppGroup.defaults`), so the helper only
clears `.standard`.

`ShowDateStateTests.swift` (the other three are identical with the noted
fallback and key):

```swift
import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch "show due date" holder: default-on when unset, true/false
/// round-trip, and persistence into `UserDefaults.standard` (where the holder
/// writes). Serialized because every test writes the same real key.
@MainActor
@Suite(.serialized)
struct ShowDateStateTests {
    // MARK: Internal

    @Test
    func unsetKeyDefaultsToOn() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(
            ShowDateState().isEnabled,
            "no persisted value means the show-date default-on")
    }

    @Test
    func persistedValueStaysOnInit() {
        defer { clearKey() }
        UserDefaults.standard.set(false, forKey: Self.key)
        #expect(
            !ShowDateState().isEnabled,
            "an explicitly toggled-off value overrides the default")
    }

    @Test
    func applyRoundTripsTrueAndFalse() {
        defer { clearKey() }
        let state = ShowDateState()
        state.apply(true)
        #expect(state.isEnabled, "apply republishes true through the state")
        state.apply(false)
        #expect(!state.isEnabled, "apply republishes false through the state")
    }

    @Test
    func applyPersistsToStandardDefaults() {
        defer { clearKey() }
        ShowDateState().apply(true)
        #expect(
            UserDefaults.standard.bool(forKey: Self.key),
            "apply persists into UserDefaults.standard, where the holder reads")
    }

    // MARK: Private

    private static let key = BoolPreferenceKey.showDate.rawValue

    private func clearKey() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
```

Per-file substitutions:

| File | Struct | Key | Fallback | `unsetKey…` name |
| --- | --- | --- | --- | --- |
| `ShowDateStateTests.swift` | `ShowDateStateTests` | `BoolPreferenceKey.showDate` | `true` | `unsetKeyDefaultsToOn` |
| `ShowListStateTests.swift` | `ShowListStateTests` | `BoolPreferenceKey.showList` | `false` | `unsetKeyDefaultsToOff` |
| `ShowRecurrenceStateTests.swift` | `ShowRecurrenceStateTests` | `BoolPreferenceKey.showRecurrence` | `true` | `unsetKeyDefaultsToOn` |
| `ShowAlarmsStateTests.swift` | `ShowAlarmsStateTests` | `BoolPreferenceKey.showAlarms` | `true` | `unsetKeyDefaultsToOn` |

For `ShowListStateTests` the `unsetKeyDefaultsToOff` body is:

```swift
        #expect(
            !ShowListState().isEnabled,
            "no persisted value means the show-list default-off")
```

Production files (`SingleThreadWatch/{ShowDate,ShowList,ShowRecurrence,ShowAlarms}State.swift`)
are **read-only** — no changes.

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadWatchTests/ShowDateStateTests` — 4 cases, exits 0 (non-zero on zero-match)
- [x] `scripts/test-one.sh SingleThreadWatchTests/ShowListStateTests` — 4 cases, exits 0
- [x] `scripts/test-one.sh SingleThreadWatchTests/ShowRecurrenceStateTests` — 4 cases, exits 0
- [x] `scripts/test-one.sh SingleThreadWatchTests/ShowAlarmsStateTests` — 4 cases, exits 0
- [x] `make watch-build` passes
- [x] `make format && make lint` clean

#### Manual
- [ ] Confirm each suite's four `@Test` cases are listed in the run output (not silently filtered to zero).
- [ ] Confirm no `test`-prefixed names survived `make format` (SwiftFormat strips `test` prefixes on unit tests).

---

## Phase 2: Widget logic extraction → Core tests (riskiest — front-loaded)

### Step 0 — feasibility spike (gate)

Read `SingleThreadWidget/NextThingWidget.swift` `makeEntry`. Pre-validated in
this plan: there are **three** genuinely pure, behavior-worthy units —
(a) four preference reads with distinct per-key fallbacks (`true`/`false`/`true`/`true`),
(b) the timeline refresh-date math (`refreshInterval = 5 * 60`), and
(c) the authorization gate (`EKAuthorizationStatus` → `.fullAccess` renders the
reminder, anything else renders `.noAccess`). **Spike passes → extract.**

If implementation finds otherwise (e.g. `makeEntry` was refactored since this
plan), stop, record the widget as a documented non-goal in Phase 4, and proceed
straight to Phase 3 — do not extract a thin surface.

### Changes

#### 1. New extracted logic

**File**: `SingleThreadCore/Sources/SingleThreadCore/NextThingWidgetLogic.swift`
**Action**: create

```swift
import EventKit
import Foundation

/// The four widget display preferences, resolved once from `UserDefaults`.
/// Extracted from `NextThingProvider.makeEntry` so the per-key fallbacks are
/// unit-testable without standing up a widget/app-extension test target.
public struct NextThingDisplayPreferences: Equatable, Sendable {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults) {
        showsDate = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showDate.rawValue,
            fallback: true).isEnabled
        showsList = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showList.rawValue,
            fallback: false).isEnabled
        showsRecurrence = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showRecurrence.rawValue,
            fallback: true).isEnabled
        showsAlarms = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showAlarms.rawValue,
            fallback: true).isEnabled
    }

    // MARK: Public

    public let showsDate: Bool
    public let showsList: Bool
    public let showsRecurrence: Bool
    public let showsAlarms: Bool
}

/// Pure widget logic extracted from `NextThingProvider`; the SwiftUI
/// `NextThingWidgetView` stays untested (no app-extension test target).
public enum NextThingWidgetLogic {
    // MARK: Public

    /// How soon to re-ask EventKit for a possibly-changed current reminder.
    /// Was 15 min; shortened so an out-of-band completion/deletion clears the
    /// widget sooner. This is the widget's entire staleness mechanism.
    public static let refreshInterval: TimeInterval = 5 * 60

    /// The timeline's next refresh date — the one piece of date math the widget owns.
    public static func nextRefreshDate(from date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }

    /// Reminders access is only usable at `.fullAccess`; anything else renders
    /// the widget's `.noAccess` state.
    public static func isAccessGranted(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }
}
```

Notes: `AppGroup.defaults` and `BoolPreferenceStore` are already `public` in
`SingleThreadCore`; `EKAuthorizationStatus` is already used in Core
(`ReminderStore.swift:276`), so this compiles for iOS/watchOS/macOS.

#### 2. Call site rewire

**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

- In `getTimeline`, replace `let refresh = Date().addingTimeInterval(Self.refreshInterval)`
  with `let refresh = NextThingWidgetLogic.nextRefreshDate(from: Date())`.
- Delete `private static let refreshInterval: TimeInterval = 5 * 60`.
- Replace the body of `makeEntry()`:

```swift
    @MainActor
    private static func makeEntry() async -> NextThingEntry {
        let date = Date()
        let preferences = NextThingDisplayPreferences()
        guard NextThingWidgetLogic.isAccessGranted(EKEventStore.authorizationStatus(for: .reminder)) else {
            return NextThingEntry(
                date: date,
                state: .noAccess,
                showsDate: preferences.showsDate,
                showsList: preferences.showsList,
                showsRecurrence: preferences.showsRecurrence,
                showsAlarms: preferences.showsAlarms)
        }
        let store = ReminderStore(loadsReminders: true)
        store.showsUndatedReminders = BoolPreferenceStore(
            key: BoolPreferenceKey.showUndatedReminders.rawValue,
            fallback: false).isEnabled
        store.setSortOption(SortOptionStore().load())
        await store.reload()
        return NextThingEntry(
            date: date,
            state: store.listContent,
            showsDate: preferences.showsDate,
            showsList: preferences.showsList,
            showsRecurrence: preferences.showsRecurrence,
            showsAlarms: preferences.showsAlarms)
    }
```

`NextThingEntry` and `NextThingWidgetView` stay in the widget target; behavior is
unchanged (same reads, same fallbacks, same `.fullAccess`/`.noAccess` split).

#### 3. Core tests

**File**: `SingleThreadTests/NextThingWidgetLogicTests.swift`
**Action**: create

```swift
import EventKit
import Foundation
import SingleThreadCore
import Testing

/// Covers the pure logic extracted from the widget's `NextThingProvider`:
/// per-key preference fallbacks, the timeline refresh interval, and the
/// authorization gate. macOS-safe — EventKit is available in the macOS unit run.
@Suite
struct NextThingWidgetLogicTests {
    // MARK: Internal

    @Test
    func refreshDateAddsInterval() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            NextThingWidgetLogic.nextRefreshDate(from: base)
                == base.addingTimeInterval(300),
            "the timeline refresh is the fixed 5-minute interval")
    }

    @Test
    func displayPreferencesDefaultPerKeyFallbacks() {
        let preferences = NextThingDisplayPreferences(defaults: makeDefaults())
        #expect(preferences.showsDate, "showDate falls back to true")
        #expect(!preferences.showsList, "showList falls back to false")
        #expect(preferences.showsRecurrence, "showRecurrence falls back to true")
        #expect(preferences.showsAlarms, "showAlarms falls back to true")
    }

    @Test
    func displayPreferencesReadPersistedOverrides() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: BoolPreferenceKey.showDate.rawValue)
        defaults.set(true, forKey: BoolPreferenceKey.showList.rawValue)
        defaults.set(false, forKey: BoolPreferenceKey.showRecurrence.rawValue)
        defaults.set(false, forKey: BoolPreferenceKey.showAlarms.rawValue)

        let preferences = NextThingDisplayPreferences(defaults: defaults)

        #expect(!preferences.showsDate)
        #expect(preferences.showsList)
        #expect(!preferences.showsRecurrence)
        #expect(!preferences.showsAlarms)
    }

    @Test
    func accessDeniedYieldsNoAccess() {
        #expect(
            NextThingWidgetLogic.isAccessGranted(.fullAccess),
            "full access renders the reminder")
        #expect(!NextThingWidgetLogic.isAccessGranted(.denied))
        #expect(!NextThingWidgetLogic.isAccessGranted(.restricted))
        #expect(!NextThingWidgetLogic.isAccessGranted(.notDetermined))
    }

    // MARK: Private

    /// Fresh suite per call, so no cross-test/cross-run persistence leaks.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NextThingWidgetLogicTests.\(UUID().uuidString)")!
    }
}
```

The `NextThingWidgetLogicTests.swift` file needs no pbxproj edit
(synchronized groups) and no `#if os(...)` gate (EventKit and `UserDefaults`
are present in the macOS unit run).

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/NextThingWidgetLogicTests` — 4 cases, exits 0
- [x] `make build` passes (widget extension compiles + embeds)
- [x] `make format && make lint` clean
- [x] `make periphery` does **not** flag `NextThingDisplayPreferences` / `NextThingWidgetLogic` (both referenced by the widget)

#### Manual
- [ ] Build + run the iOS app, add the "Next Thing" widget to a simulator home screen, confirm it renders a reminder or the no-access message (unchanged behavior).
- [ ] Comment out one preference read in `NextThingDisplayPreferences` locally, confirm a unit case fails, then restore — proves the tests bind to the extraction.

---

## Phase 3: AI-sort coordinator trust/fallback (fake `AISortRanking`)

### Step 0 — coverage diff (PRE-RESOLVED by this plan)

`SingleThreadTests/AISortCoordinatorTests.swift` (20 `@Test` cases) already
covers every behavior the structure outline proposed adding. Do **not** add
duplicate tests. Mapping:

| Structure's proposed case | Already covered by |
| --- | --- |
| `untrustedFailureFiresOnRankingFailed()` | `reportsRuntimeFailureToObserver`, `retainsPreviousRankingWhenRankerThrows` |
| `fallbackErrorEmitsNoOrdering()` | `fallsBackWhenRankerUnavailable`, `doesNotReportUnavailableAsARuntimeFailure`, `retainsPreviousRankingWhenRankerThrows` |
| `repeatedIdenticalRulesDoNotReRank()` | `skipsIdenticalInputs`, `skipsRepeatedCompletedRequests` |
| `staleGenerationResultIsDiscarded()` | `ignoresStaleGeneration`, `reranksWhenContentChangesInFlight` |
| `digest` / candidate-content change | `reranksWhenCandidateContentChanges` |
| reconcile contract | `reconcilesUnknownAndMissingIds` |
| blank/unavailable silent paths | `silentPathsNeverReportFailures`, `skipsBlankRules` |

Two genuine uncovered branches remain (both are "the fallback clears the
digest" paths in `AISortCoordinator.update`): a runtime failure leaves
`lastCompletedDigest` unset so identical input retries, and a blank-rules
fallback clears `lastRequestedDigest`/`lastCompletedDigest` so the same rules
re-rank. Add exactly these two.

### Changes

#### 1. One fake + two tests in the existing suite

**File**: `SingleThreadTests/AISortCoordinatorTests.swift`
**Action**: modify (append a private fake in the Fakes section; two `@Test`
cases in `AISortCoordinatorTests`)

Fake (place beside `SwitchableRanker`, in the same private fakes section):

```swift
/// Throws a settable error, then succeeds once cleared — proves the
/// coordinator retries identical input after a failure (it leaves
/// `lastCompletedDigest` unset) and that a silent fallback re-arms re-ranking.
private final class ErrorSwitchableRanker: AIReminderRanking, @unchecked Sendable {
    // MARK: Internal

    var order: [String] {
        get { lock.withLock { storedOrder } }
        set { lock.withLock { storedOrder = newValue } }
    }

    var error: Error? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        let (order, error) = lock.withLock { () -> ([String], Error?) in
            calls += 1
            return (storedOrder, storedError)
        }
        if let error {
            throw error
        }
        return order
    }

    // MARK: Private

    private let lock = NSLock()
    private var storedOrder: [String] = []
    private var storedError: Error?
    private var calls = 0
}
```

Tests (add after `skipsRepeatedCompletedRequests`):

```swift
    @Test
    func retriesIdenticalRequestAfterRuntimeFailure() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = ErrorSwitchableRanker()
        ranker.order = ["a", "b"]
        ranker.error = RankerCrashed()
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }
        coordinator.onRankingFailed = { _ in }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1)
        #expect(emitted.isEmpty, "a runtime failure retains the previous ranking")

        ranker.error = nil
        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(
            ranker.callCount == 2,
            "a failed request leaves no completed digest, so identical input retries")
        #expect(emitted == [["a": 0, "b": 1]], "the retry emits the ranking")
    }

    @Test
    func reRanksAfterSilentFallbackClearsTheDigest() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1)

        coordinator.update(rules: "   ", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1, "blank rules never reach the ranker")

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(
            ranker.callCount == 2,
            "the fallback cleared the digest, so the same rules re-rank")
        #expect(emitted.count == 3, "blank fallback emits [:] and the re-rank emits its ordering")
    }
```

No production code changes. `AIReminderRanking`, `AIRankingError`,
`AISortCoordinator` are consumed only.

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests` — 22 cases, exits 0
- [x] `make lint` clean for the touched file
- [x] `git diff --stat` shows only `SingleThreadTests/AISortCoordinatorTests.swift` changed (no production code)

#### Manual
- [ ] Confirm the two new case names do not duplicate existing test names in the file (`rg -n 'func (retries|reRanks)'`).

---

## Phase 4: Audit report + hardening review (docs-only, final)

### Changes

#### 1. The report artifact

**File**: `.pi/orksorksorks/alanvardy-var-1075-test-suite-audit/audit-report.md`
**Action**: create; commit with the phase (it is the deliverable, not a step artifact)

Required sections and content (each claim tied to `file:line`):

1. **Scope & method** — bounded, logic-first audit; value bar; no coverage
   threshold. Summarize `research.md` Q1/Q2 seams and note that exhaustive
   per-file coverage percentages were not computed.
2. **Gaps closed** —
   - Watch `Show*State`: four new suites over
     `SingleThreadWatch/{ShowDate,ShowList,ShowRecurrence,ShowAlarms}State.swift`.
   - Widget: `NextThingWidgetLogic` / `NextThingDisplayPreferences` extracted to
     `SingleThreadCore` and covered by `SingleThreadTests/NextThingWidgetLogicTests.swift`;
     `NextThingWidgetView` intentionally untested.
   - AI-sort coordinator: coverage diff showed the trust/fallback/debounce/
     generation surface already covered by `AISortCoordinatorTests.swift`; two
     missing fallback-digest branches added.
3. **Coverage-diff finding** — the Phase 3 mapping table (structure's four
   proposed cases → existing tests) and the two added branches.
4. **Finding for user triage (recorded, not fixed)** — five of six watch
   `Show*State` holders persist to `UserDefaults.standard`
   (`ShowDateState.swift:28-29`, `ShowListState.swift`, `ShowRecurrenceState.swift`,
   `ShowAlarmsState.swift`, `ShowCompletionGlowState.swift:27-28`), while
   `ShowEnableActionButtonsState` reads/writes `AppGroup.defaults`
   (`ShowEnableActionButtonsState.swift:16-18,27`) and the watch sync stores in
   `WatchAppViewModel.swift:232-246` use `.standard`. On a real watch
   `AppGroup.defaults` falls back to `.standard` (they converge); on simulator
   the suite exists (they diverge). Ask: intentional or a latent bug? (AGENTS
   "Every persisted value shared with the watch must round-trip through
   `AppGroup.defaults`".)
5. **Documented non-goals** (one-line rationale each) — SwiftUI `View`/modifier
   bodies (`EmptyStateCard`, `ReminderCardView`, `ControlPlateModifier`,
   `BackgroundSettingsView`, `ExcludedListsView`, `NotificationsSettingsView`,
   `PurchaseSettingsView`, `SettingsBindings`, `TextSizeModifier`,
   `CreationFeedback`, `AuthorizationRequiring`); the widget's SwiftUI view;
   the live `FoundationModelsReminderRanker` (model unavailable on CI —
   exercised only through a fake ranker at the protocol/coordinator boundary);
   the false-alarm gap trio (`ReminderDateFilter` via `SingleThreadTests.swift:173-248`,
   `ReminderIntentSupport` via `ReminderIntentSupportTests.swift`,
   `EntitlementState` via `EntitlementSyncTests.swift:113-123`); no new test
   target; no persistence-semantics change; no coverage-threshold gate. Include
   the Phase 2 spike outcome (passed → extraction, not a non-goal).
6. **Pre-existing local-only failure** — three macOS `EntitlementStoreTests`
   (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
   `hostStoreKitIsClean` canary) fail locally, green on CI; do not debug.

Optional: one paragraph in the PR description pointing at the report.

### Verification
#### Automated
- [x] `git diff --name-only` for the phase shows only `audit-report.md` (no source diff)
- [x] `rg -c 'file:line'`-style check: every non-goal/finding cites a path (manual read)

#### Manual
- [ ] Report names each non-goal with a rationale (read it end-to-end).
- [ ] Run the full CI-identical gate **once** via the `run-gate` skill (`./scripts/test.sh` through the gate subagent — never `nohup`).
- [ ] Check `git status` before the phase commit so no `.pi/orksorksorks/` step artifact is folded in besides `audit-report.md`.

---

## Testing Checkpoints

- **After Phase 1**: the four watch suites + `make watch-build` green → commit → advance.
- **After Phase 2 spike**: extraction is meaningfully testable (validated in this plan) → proceed; if it fails at implementation time, reclassify the widget as a non-goal and go to Phase 3.
- **After Phase 2**: `NextThingWidgetLogicTests` + `make build` green → commit → advance.
- **After Phase 3**: extended `AISortCoordinatorTests` green with no duplicate coverage → commit → advance.
- **After Phase 4**: report complete; run the full gate **once** via `run-gate`.
- **Never skip a failed slice**: a red suite stops advancement; completed slices stay independently landable.

---

## Deviations from `structure.md`

1. **Phase 1 test-case names** are concrete (`unsetKeyDefaultsToOn` /
   `unsetKeyDefaultsToOff`) instead of the generic `unsetKeyDefaultsTo<fallback>()`,
   and each suite clears only `UserDefaults.standard` (the holders' actual
   store) rather than `AppGroup.defaults`.
2. **Phase 3** is pre-resolved by the coverage diff in this plan: the four
   proposed test names are duplicates of existing cases, so the phase adds two
   genuinely uncovered fallback-digest branches plus one fake, and ships the
   mapping (structure explicitly sanctioned this: "If fully covered, ship the
   report finding instead of duplicate tests"). Phase 2's spike likewise passes
   on inspected source, so the widget is extracted rather than reclassified.