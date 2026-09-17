# Structure Outline

## Approach

Add `.ai` as a fourth `SortOption` and build the feature as one vertical spine:
a store-backed rule text box in `FilterSortSettingsView` → `AISortRulesStore`
(App Group) → a `@MainActor` `AISortCoordinator` in core driving an injectable
`AIReminderRanking` → a `ReminderStore.aiRanking` rank cache consulted by
`visibleReminders`. The FoundationModels adapter is the only new SDK surface,
kept to one file in the iOS app target behind an availability gate; every other
layer is core and testable with a fake ranker.

---

## Phase 1: Walking skeleton — AI reorders the list end to end

The user selects **AI** in the picker, a rule box appears, types a rule, and the
reminder list reorders by on-device AI when the model is available — or by the
`.priority` chain when it is not. Thin on purpose: ranking fires on each change
(no debounce), the previous order is simply replaced, and there is no footer.
Green tests prove the adapter availability gate, the coordinator against a fake
ranker, `.ai` ordering, and the rules store round-trip. This is the one
genuinely horizontal piece (new SDK through both targets), but it is a single
green commit, not a layer milestone.

**Files**: `SingleThreadCore/.../SortOption.swift`,
`SingleThreadCore/.../AISortRulesStore.swift` (new),
`SingleThreadCore/.../AIReminderRanking.swift` (new: protocol + coordinator),
`SingleThreadCore/.../ReminderStore.swift`,
`SingleThreadCore/.../ReminderSort.swift`,
`SingleThread/FoundationModelsReminderRanker.swift` (new),
`SingleThread/FilterSortSettingsView.swift`, `SingleThread/SettingsBindings.swift`,
`SingleThread/AppViewModel.swift`

**Key changes**:
- `SortOption` — add `case ai` (`rawValue "ai"`), `title`, `systemImage`; every
  `switch` over the enum (comparator, presentation) now needs a deliberate `.ai`
  branch — this is the main expected diff.
- `AISortRulesStore` — `init(defaults: UserDefaults = AppGroup.defaults, key: String = "aiSortRules")`, `load() -> String`, `save(_:)` (mirrors `SortOptionStore`).
- `struct AIReminderCandidate: Sendable, Equatable { identifier: String, title: String, notes: String?, priority: Int, dueDate: Date?, listTitle: String? }`
- `protocol AIReminderRanking: Sendable { func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] }`
- `@MainActor final class AISortCoordinator { init(ranker: any AIReminderRanking); var onRankingUpdated: (([String: Int]) -> Void)?; func update(rules: String, candidates: [AIReminderCandidate]); func cancel() }`
- `ReminderStore` — `func setAIRanking(_ ranking: [String: Int])`; `.ai` branch in `visibleReminders` (rank ascending, unranked ids fall through to the `.priority` chain).
- `ReminderSort` — `.ai` resolves to the `.priority` chain (the off-iOS case).
- `FoundationModelsReminderRanker` — `#available(iOS 26.0, macOS 26.0, *)` + `SystemLanguageModel.default.availability == .available`; `@Generable` ordered-id output; throws a typed error when unavailable.
- `SettingsBindings` — store-backed `var aiSortRules: String` (getter `load()`, setter `save` inside `withMutation`), mirroring the existing `sortOption` property.
- `FilterSortSettingsView` — `TextEditor(text: $bindings.aiSortRules)` in a `Section` rendered only when `sortOption == .ai`.
- `AppViewModel` — construct the coordinator with the real ranker; wire `onRankingUpdated` → `store.setAIRanking`; call `coordinator.update(...)` from `onSortOptionChanged` / `onRemindersChanged`.

**Contract** (later slices consume, never internals): `AIReminderRanking`,
`AISortRulesStore`, `SortOption.ai`, `ReminderStore.setAIRanking(_:)`,
`AISortCoordinator.update(rules:candidates:)` / `onRankingUpdated`.

**Tests**: new `AISortCoordinatorTests` (`ranksWithFakeRanker`, `retainsPreviousRankingWhenRankerThrows`), `AISortRulesStoreTests` (round-trip + default + App-Group key), `ReminderStoreTests` `.ai` ordering (`aiOptionUsesRankingThenPriorityChain`), `SortOptionTests` (`ai` rawValue/allCases/presentation), `ReminderSortTests` `.ai` matches the priority chain.
**Verify**: `make build` compiles the gated adapter under the local toolchain, then `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests/` and the ordering suites; manual check on the current host (model `.available`) that typing a rule visibly reorders a seeded list. **Checkpoint**: the CI-toolchain compile probe (per `swiftui-sdk`) is run *before* writing the adapter — if the gated import is rejected, stop and re-decide with the user.

---

## Phase 2: Unsupported devices explain themselves and still work

On a device without Apple Intelligence (iOS 17–25, Apple Intelligence off, CI),
`.ai` remains selectable, the rule box persists as usual, the list orders by the
`.priority` chain, and a footer states that this device cannot run on-device AI.
Blank rules behave identically (no model call). The `availability` reason
(`deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`) refines
the copy but is not required.

**Files**: `SingleThread/FoundationModelsReminderRanker.swift` (expose
`static var availability: Availability` + `static var isAvailable: Bool`),
`SingleThreadCore/.../AIReminderRanking.swift` (coordinator no-ops when rules
are blank or no ranker is available), `SingleThread/SettingsBindings.swift`
(pass availability through), `SingleThread/FilterSortSettingsView.swift`
(`Section` footer + `.ai` row rendering).

**Key changes**:
- `enum Availability { case available, deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady }` — app adapter.
- `AISortCoordinator.update` guards: `rules.trimmed.isEmpty` → resolve to empty ranking; unavailable ranker → leave `.priority` chain.
- Footer view: fixed explanatory copy, reason-mapped when available.

**Contract**: `FoundationModelsReminderRanker.isAvailable` / `.availability`;
the coordinator's "no ranking ⇒ priority chain" guarantee.

**Tests**: `AISortCoordinatorTests` (`skipsRankingWhenRulesBlank`, `fallsBackWhenRankerUnavailable`), `SettingsViewTests` footer/row construction for `.ai` (precedent `:191-192`), ordering fallback in `ReminderStoreTests`.
**Verify**: `make test` (macOS native, where the model is unavailable — exercises the exact CI path); manual check of the footer copy.

---

## Phase 3: Async robustness — debounce, dedupe, retention, validation

Typing no longer re-ranks per keystroke; the previous order stays until a new
ranking arrives (the list never flickers unordered); a thrown error, guardrail
refusal, or timeout leaves the last good ranking; hallucinated or omitted
identifiers are reconciled (unknown dropped, duplicates deduped, missing ids
appended deterministically); and changes to the reminder set, skips, or excluded
lists re-rank while `.ai` is selected.

**Files**: `SingleThreadCore/.../AIReminderRanking.swift` (debounce task,
input-hash dedupe, generation counter, validation), `SingleThreadCore/.../ReminderStore.swift`
(notify hooks already fire on skip/exclusion changes),
`SingleThread/AppViewModel.swift` (call `update` from every relevant hook).

**Key changes**:
- `AISortCoordinator` — `init(ranker: any AIReminderRanking, debounce: Duration = .milliseconds(500))`; `func update(rules:candidates:)` cancels/replaces a pending task; skips identical `(rules, candidateDigest)` inputs; ignores stale generations.
- `func reconcile(_ ranked: [String], against candidates: [AIReminderCandidate]) -> [String: Int]` — drop unknowns, dedupe, append missing. (Exposed for direct unit test.)
- No mutation of `aiRanking` until a ranking validates.

**Contract**: the reconciliation rule and "latest-generation-wins" semantics.

**Tests**: `AISortCoordinatorTests` — fakes `NeverCompletingRanker`, `ThrowingRanker`, `CannedRanker`: `debouncesRapidEdits`, `skipsIdenticalInputs`, `retainsRankingOnError`, `reconcilesUnknownAndMissingIds`, `reranksWhenRemindersChange`.

**Verify**: `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests/`; manual check that typing is smooth and an induced ranker error does not reorder the list.

---

## Phase 4: Cross-surface parity, seams, and hardening

`.ai` reaches the watch and widget as its `rawValue` with **no new payload**, and
both order by the `.priority` chain (no ranking is ever present off-iOS).
Seeded UI runs start from a known state (`"aiSortRules"` wiped alongside
`"sortOption"`). The new text box passes the accessibility audit and Dynamic
Type, and list-size/prompt-size behavior is measured and documented.

**Files**: `SingleThreadCore/.../UITestingSeed.swift` (`resetPersistedState` adds
`"aiSortRules"`), `SingleThreadTests/SkippedReminderSyncServiceTests.swift`,
`SingleThreadWatchTests/WatchSyncPipelineTests.swift`, `SingleThreadUITests/`
audit config (only if needed), `SingleThread/FilterSortSettingsView.swift`
(a11y labels/traits, caption padding), PR notes.

**Key changes**:
- `UITestingSeed.resetPersistedState` — include the new App-Group key.
- No production watch/widget source change (design decision 6) — verify only.
- `--seed` UI runs exercise `.ai` as a selected option without AI.

**Contract**: none new; this slice only guarantees the existing `rawValue` sync
contract holds for `.ai`.

**Tests**: `UITestingSeedTests` (`resetsAISortRules`), `SkippedReminderSyncServiceTests` (`sortOptionAITravelsAsRawValue`), `WatchSyncPipelineTests` (`.ai` orders by priority), a11y audit for the `.ai` sheet row.
**Verify**: `make lint` + `make format`, targeted suites, then the full gate ONCE via the `run-gate` skill.

---

## Testing Checkpoints

- After Phase 1: `make build` + adapter compile probe + coordinator/ordering/store suites green. **No later phase starts until the SDK integration compiles at the 17.0 floor.**
- After Phase 2: `make test` green on macOS native (unavailable path) + footer tests.
- After Phase 3: coordinator robustness suites green; no duplicate in-flight calls, no flicker on error.
- After Phase 4: `make lint` clean, cross-surface sync/seed tests green, then one `run-gate` full pipeline. **Re-run the gate only through `run-gate`, never ad-hoc.**

**Not covered by a slice (deliberate)**: no UI test for AI ordering — CI cannot
produce a model; the conditional row and persistence are unit-tested at the
`SettingsBindings`/store level and the PR must state this justification.
