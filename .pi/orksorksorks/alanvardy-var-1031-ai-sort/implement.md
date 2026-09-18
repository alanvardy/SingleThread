# Implementation Summary — VAR-1031 "AI sort"

All four plan phases implemented, verified, and committed on
`alanvardy-var-1031-ai-sort`. `.ai` is a fourth `SortOption` wired end to end:
a store-backed rule box (`AISortRulesStore` → `SettingsBindings.aiSortRules`) →
`AISortCoordinator` (core, fake-rankable, debounced + deduped + reconciled) →
`AISortRulesStore` (App Group) → `ReminderStore.aiRanking` rank cache consumed
by `visibleReminders`, with the `FoundationModelsReminderRanker` gated in one
app-target file. Unavailable devices keep `.ai` selectable, order by the
`.priority` chain, and explain why in the sheet footer. Watch/widget compile
and order by the `.priority` chain; `.ai` travels as `rawValue "ai"` only.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `7ec5e472` | Walking skeleton — AI reorders the list end to end |
| 2     | `3493585c` | Unsupported devices explain themselves and still work |
| 3     | `4b60d317` | Async robustness — debounce, dedupe, retention, validation |
| 4     | `7e17bf00` | Cross-surface parity, seams, and hardening |
| 4 fix | `0ec8668f` | Keep sync suite under SwiftLint `type_body_length` bound (moved `.ai` travel test to sibling suite) |
| docs  | `34e47df7` | Implementation artifacts (plan, conventions, research) |

Setup: the `DELETEME` bootstrap marker was removed (`dd1f4d45`, rebase
prerequisite) and the branch was rebased + force-synced to the current
`origin/main` before phase work.

## Automated Checks

- [x] `make format` clean across all phases (SwiftFormat idempotent)
- [x] iOS 17.0-floor gated-import probe green (`/tmp/fmprobe.swift`, exit 0)
- [x] `make build` green (iOS; compiles the gated adapter at the 17.0 floor)
- [x] AISortCoordinatorTests — 11/11 (Phase 2: 4 incl. `skipsBlankRules`, `fallsBackWhenRankerUnavailable`; Phase 3: +debounce/dedupe/retain/reconcile/re-rank/stale-generation/cancel)
- [x] FoundationModelsReminderRankerTests — `availabilityGateMatchesIsAvailable` green
- [x] AISortRulesStoreTests — 3/3 (empty default, round-trip, key)
- [x] ReminderStoreTests — 36/36 (incl. `aiOptionUsesRankingThenPriorityChain`, `aiFallsBackToPriorityChainWithoutRanking`)
- [x] SortOptionTests — incl. `.ai` rawValue/allCases/presentation assertions
- [x] ReminderSortTests — 12/12 (incl. `aiOptionMatchesPriorityChain`; the plan's selector `ReminderSkipTests` is the filename — the Swift Testing suite is `ReminderSortTests`)
- [x] SettingsViewTests — 18/18 (incl. `filterSortSettingsViewRendersAIRulesEditorWhenAISelected` (P1), `…FooterExplainsUnavailableAI`, `…HasNoAIEditorWhenAnotherOptionSelected` (P2))
- [x] LocalizationTests — 5/5 (4 new keys, six locales, `"AI"` exclusion)
- [x] UITestingSeedTests — 21/21 (incl. `resetsAISortRules`)
- [x] SkippedReminderSyncServiceTests — 36/36; `AISortOptionTravelTests.sortOptionAITravelsAsRawValue` 1/1 (send + receive round-trip of `"ai"`)
- [x] `make watch-test` — 54/54 watch unit cases (incl. `WatchSyncPipelineTests/aiSortOptionOrdersByPriorityChain` at the watch-floor)
- [x] `make lint` / `swiftlint --strict` clean (after deviations below)
- [x] `git rm DELETEME` — done at setup
- [ ] Full CI-identical gate (`./scripts/test.sh`) — launched ONCE via the
      `run-gate` skill (async gate subagent, managed worktree at branch tip
      `34e47df7`, 6h cap, `gate.md` report); **in flight — verdict pending**.
      The iOS-sim suites above were run against the exact pinned worktree sim
      and the branch contains no uncommitted changes, so the gate runs the
      committed tip.

  First gate run result (at `34e47df7`): **FAIL at Periphery, before test
  stages** — 2 findings, both real dead code in Phase-1 test files:
  `ThrowingRanker` (unused once Phase 2 switched the retention test to
  `SwitchableRanker`) and a redundant `import SingleThreadCore` in
  `FoundationModelsReminderRankerTests`. Fixed in `68d76909` (deleted the
  fake, dropped the import); Periphery re-run against the gate's exact
  invocation on a clean DerivedData → **exit 0**, and the coordinator +
  adapter suites re-verified green (11 + 1 cases). Gate re-launched at tip
  `68d76909`.

### Annotated (pre-existing local breakage, not caused by this branch)

- `make mac-build` — fails identically on `origin/main` (local Xcode 27.0 vs
  CI 26.6: entitlement-profile error without flags; `SkipSyncSession` unresolved
  with Debug+`CODE_SIGNING_ALLOWED=NO`). CI mac-tests are green. Not checked off
  (see plan.md) — a Phase-1 subagent's claim of "macOS native pass" was
  disproven from its own logs; all green suite runs were on the iOS simulator.
- Phase 2's `make test` (macOS native) — same root cause; macOS-only behavior
  is covered by the deterministic `availabilityGateMatchesIsAvailable` test and
  CI's mac-tests.
- Three `EntitlementStoreTests` on macOS native — known pre-existing (storekit
  skill); not applicable to the simulator-scoped verification used here.

### Deviations from plan.md (all small, intent preserved)

1. **Protocol shape (Phase 2)**: a protocol-extension-only `isAvailable` is
   statically dispatched through the `any AIReminderRanking` the coordinator
   holds — a conformer's same-named member is never consulted (verified with a
   standalone probe; Swift semantics). Fixed by declaring `var isAvailable: Bool
   { get }` as a required protocol member with the extension supplying the
   `true` default (dynamic witness dispatch). Without this the production
   adapter's override would have been silently ignored too.
2. **Footer copy (Phase 2)**: SwiftUI `SettingsCaption` takes a
   `LocalizedStringKey`; a computed `String` won't convert, and the plan's
   single literal exceeds the 120-char strict width. Built via
   `LocalizedStringKey("…" + "…" + "…")` (runtime value == the exact catalog
   key, six locales preserved).
3. **SwiftLint strictness**: plan snippets `== ""` → `.isEmpty`;
   `ReminderStoreTests` wrapped to the 500-line body bound; the sync suite's
   new `.ai` travel test lives in sibling suite `AISortOptionTravelTests`
   because `type_body_length` cannot be scoped-disabled at struct level here
   (`file_length` blanket disable mirrors `ReminderStoreTests` precedent).
4. **Phase 1 subagent pre-implemented Phase 2's adapter availability surface**
   (enum `Availability`, `availability`, `isAvailable`) — harmless, tests
   green, Phase 2's adapter diff reduced to a verification.
5. **`ReminderSkipTests` → `ReminderSortTests`** selector (the plan's was the
   filename; the Swift Testing suite struct is `ReminderSortTests`).
6. **Completion-count shift**: the `completionCount` entry in
   `UITestingSeed.persistedKeys` was already present at HEAD; only `aiSortRules`
   was added.
7. **No new UI test** (design decision 9 + AGENTS.md UI-test policy): CI cannot
   produce an AI ranking; the conditional row, footer, and persistence are
   covered at `SettingsViewTests`/`AISortRulesStore`/sync level, and reaching
   the settings sheet in the UI-test target would buy no coverage the unit
   suites lack. Accessibility covered by the manual inspector pass below.
8. **`skipsIdenticalInputs`/`ignoresStaleGeneration` fakes**: the plan's
   `NeverCompletingRanker` cannot observe a dedupe through a single coordinator
   (the ranker is a `let`), so dedupe is proven with a counted fake and
   stale-generation with a `BlockOnceRanker`; `NeverCompletingRanker` earns its
   keep in `cancelsInFlightRequest`.

## Observations for later (not implemented per plan discipline)

- The coordinator's dedupe guard requires an in-flight task (`pending != nil`)
  — a completed identical request re-ranks; harmless because AppGroup-write
  triggers are equality-guarded at the store, but worth knowing.
- `Localizable.xcstrings` keys for the two footer captions are maintained
  manually (extractionState manual); the unavailable-device copy lives in one
  `LocalizedStringKey` runtime concatenation.
- Sim launch flakiness ("SingleThread encountered an error", zero cases) occurs
  ~1-in-5 fresh-clone runs after many consecutive suite runs; a sim
  shutdown/boot clears it. No code-level cause found.

## Manual Verification Items (from the plan)

- [ ] Run the app on the current host (model `.available`); launch with
      `--seed '{"reminders":[{"title":"Client email","priority":1},{"title":"Buy milk","priority":9}]}'`;
      Settings → Filtering & Sorting → select **AI**; a rule box appears; type
      "clients first"; the list reorders on-device within a second.
- [ ] Switch to **Priority** → box hides; switch back to **AI** → the typed rule
      is still there; dismiss and reopen the sheet → still there.
- [ ] Relaunch the app → the rule text persists (App Group).
- [ ] Footer reads "This device can't run on-device AI…" whenever the host
      reports `availability != .available`; on the current host it reads the
      "On-device AI applies these rules." copy.
- [ ] With the model off, selecting **AI** leaves the list in priority order but
      the rule box still edits and persists.
- [ ] Type a long rule quickly: the list updates once, ~0.5 s after the last
      keystroke, and never flashes into an unordered state.
- [ ] Force a ranker failure (temporarily point `AppViewModel` at a throwing
      test ranker or disable the model): the list keeps its previous order.
- [ ] Skip a reminder and toggle an excluded list while **AI** is selected: the
      list re-ranks.
- [ ] Run a seeded UI session with `--seed` and select **AI**: the option
      persists, the editor accepts text, and the list orders by priority.
- [ ] Pair a watch (or run the watch simulator): selecting **AI** on the phone
      leaves the watch list in priority order and does not disturb the sync
      payload beyond `"sortOption": "ai"`.
- [ ] Accessibility Inspector pass over the Filter & Sort sheet: the editor has
      a label, the picker row keeps its trait, Dynamic Type at the largest
      setting does not clip the footer.