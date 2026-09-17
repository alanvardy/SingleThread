# Design Discussion — VAR-1031 "AI sort"

Owner decisions (this session): **A A A A A** — FoundationModels gated with a
deterministic fallback; AI returns a ranked identifier list; write-through
rule-text store with debounced re-rank; iOS-only AI with watch/widget
priority fallback; `.ai` stays selectable everywhere with an explanatory
footer when unavailable.

## Current State

- **Sort option** is one enum + one store in core: `SortOption: String,
  CaseIterable, Sendable` (`.priority/.dueDate/.title`) with
  `defaultsKey = "sortOption"` and `SortOptionStore(defaults: AppGroup.defaults)`
  load/save/fallback — `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift:6-43`.
- **Picker**: `FilterSortSettingsView.swift:20-27` — `Picker(selection:)` over
  `ForEach(SortOption.allCases, id: \.self)`, hosted from the settings sheet
  via `SingleThread/SettingsView.swift:96-97`.
- **Binding**: `SettingsBindings` is a per-sheet-open `@Observable` bag; the
  `sortOption` property is a store-backed computed property (getter
  `sortStore.load()`, setter `sortStore.save` inside `withMutation`) —
  `SingleThread/SettingsBindings.swift:89-98`, store instances `:160-181`.
  App-Group keys persist immediately; standard-suite keys are seeded/written
  back through `@AppStorage` (`ContentView+Settings.swift:8-65`).
- **Ordering**: `visibleReminders` filters, then
  `.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }` —
  `SingleThreadCore/.../ReminderStore.swift:155-161`; comparator
  `ReminderSort.swift:14-41`, a **synchronous** key-chain comparator per
  option. `setSortOption` is equality-guarded and fires
  `onSortOptionChanged`/`onRemindersChanged` (`ReminderStore.swift:420-425`).
- **Propagation**: `PreferenceHolder` mirror → `ContentView.swift:291-292` →
  `ContentViewModel.handleSortOption` (`:151-152`) → `store.setSortOption`.
  iOS pushes `sortOption` as a String `rawValue` in the WCSession
  applicationContext (`SkippedReminderSyncService.swift:217-224,455-459`);
  watch live-re-sorts (`WatchAppViewModel.swift:190-192`); the widget re-reads
  `SortOptionStore().load()` (`NextThingWidget.swift:77`).
- **No AI facility exists** beyond on-device Speech dictation
  (`ReminderDictation.swift:134`, `requiresOnDeviceRecognition = true`);
  no Foundation Models / SiriKit / Core ML / model assets / LLM clients
  anywhere (research Q2).
- **No freeform text input UI exists in any target** — freeform text enters
  only via dictation → `ReminderDictationParser`, `--seed` JSON, or fixtures
  (research Q3). `ReminderDictationParser.swift:59-99` is the only precedent
  for interpreting user-authored text.
- **No conditional control visibility in settings sheets** — the one explicit
  statement of the opposite principle is
  `BackgroundSettingsView.swift:5-13` ("the pin toggle stays visible even when
  Background is off"); conditional UI exists only at content level
  (`ContentView.swift:177`) and for a11y/UI-test seams.
- **Session probe (this session, SDK/Xcode 27.0):** `FoundationModels` ships
  in the iPhoneSimulator/macOS SDKs, `SystemLanguageModel`/`LanguageModelSession`
  are `@available(iOS 26.0, macOS 26.0, *)` and **unavailable on watchOS**;
  `import FoundationModels` + `if #available(iOS 26.0, *)` **type-checks at the
  repo's iOS 17.0 floor** (no floor change, `verify_deployment_target` counts
  untouched); on this host the model is `.available` and answered a prompt.
  CI runners are expected to report `.unavailable`.

## Desired End State

1. A fourth sort option, `SortOption.ai` (`rawValue == "ai"`), appears in the
   existing picker with a title/system image consistent with its siblings.
2. Selecting it reveals a rule-entry text box in the Filter & Sort sheet. The
   text is a rule description ("put anything mentioning a client first, then
   errands by due date"). Switching to another option hides the box; switching
   back, closing/reopening the sheet, and relaunching all restore the text.
3. On a device that can run it, the reminder list is reordered by on-device
   AI according to the rules, refreshed as the rules or the reminder set
   change. Ranking is stable while a new ranking is in flight — the list never
   flickers into an unordered state.
4. On a device that cannot run it (iOS 17–25, Apple Intelligence off, CI), the
   `.ai` option is selectable, the rule box still works and persists, and the
   list falls back to the deterministic `.priority` chain; a footer in the
   sheet explains this.
5. Watch and widget compile and behave: `.ai` arriving over sync or read from
   the store orders by the `.priority` chain (no AI, no new payload).
6. Verification: unit tests over the rank-cache ordering, the coordinator
   (fake ranker: happy path, thrown error, empty rules, option switch), the
   rules store round-trip, `.ai` in the sync payload, and the sheet's
   conditional row; `make format && make lint`; the full gate once via the
   `run-gate` skill.

## Patterns to Follow

Follow:
- **Store type per persisted value**: mirror `SortOptionStore`
  (`SortOption.swift:22-43`) exactly for `AISortRulesStore` —
  `init(defaults: UserDefaults = AppGroup.defaults, key: = ...)`, `load()`
  returning a default, `save(_:)`. App-Group only; never
  `UserDefaults.standard` (conventions §3).
- **Store-backed computed binding**: mirror the `sortOption` property shape
  (`SettingsBindings.swift:89-98`) so typing persists on every edit and a
  fresh bag on sheet reopen reads it back.
- **Notify-hook restoration**: `setSortOption` (`ReminderStore.swift:420-425`)
  and `onRemindersChanged` (`:106,131`) are the existing change signals; the
  coordinator hangs off the same hooks, wired in `AppViewModel` the same way
  as `store.onSortOptionChanged = { ... }` (`AppViewModel.swift:435-439`).
- **Injectable capability protocol**: pattern after
  `AuthorizationRequiring.swift:10-23` (`protocol` + a production conformer +
  fake conformers in tests, e.g. `ReminderDictationTests.swift:10-93`) so the
  AI call is testable without Apple Intelligence.
- **Deterministic harness**: `ReminderStore(eventStore: InMemoryEventStore(),
  loadsReminders: false, reminders:…, skippedIDs:…, excludedListTitles:…)`
  (`ReminderStore.swift:31-79`), as every ordering test uses
  (`ReminderStoreTests.swift:58-240`); `--seed` (`UITestingSeed.swift:8-37`)
  for UI-level flows.
- **Launch-arg seams**: add the new rules key to `resetPersistedState`
  (`UITestingSeed.swift:66-94`) beside `"sortOption"` so seeded UI runs start
  from a known state.
- **Swift Testing naming**: `@Test` names must not start with `test`/`testing`
  (conventions §4).

Do NOT follow:
- **The "never hide a control" rule** (`BackgroundSettingsView.swift:5-13`) —
  this ticket explicitly requires conditional visibility of the rule box.
  It is a deliberate, single deviation, scoped to the `.ai` row; the footer
  explaining unavailability is the compensation for hidden state.
- **Full-file rewrite of `ReminderSort`** — only the `.ai` branch is added;
  the three existing key chains (`ReminderSort.swift:16-33`) are untouched.
- Do not put a real model call inside `visibleReminders` or any view body:
  that path is synchronous and view-driven.

## Design Decisions

1. **AI facility: FoundationModels, availability-gated, with a deterministic
   fallback.** `#available(iOS 26.0, macOS 26.0, *)` **and**
   `SystemLanguageModel.default.availability == .available` gate the real
   call; otherwise ordering degrades to the `.priority` chain. Verified by
   probe that the gated import type-checks at the iOS 17.0 floor, so no
   deployment-target change and no `verify_deployment_target` edit.
2. **AI output shape: an ordered list of reminder identifiers.** The ranker
   receives `(identifier, title, notes?, priority, dueDate, list)` tuples plus
   the rule text and returns `[identifier]` (structured `@Generable` output).
   `ReminderStore` keeps `aiRanking: [String: Int]`; `visibleReminders` under
   `.ai` sorts by cached rank then falls through to the `.priority` chain for
   unranked ids (new reminders, ids the model omitted or invented). Ranking is
   **validated against known identifiers**: unknown ids dropped, duplicates
   deduped, missing ids appended deterministically.
3. **Persistence: `AISortRulesStore` in `AppGroup.defaults`, key
   `"aiSortRules"`, written on every edit.** The rule text survives option
   switches, sheet dismissal, and relaunch because the store, not the bag or
   the view, owns it. No "Apply" affordance.
4. **Re-rank trigger: debounced (~0.5 s) after the last edit, and on
   reminder-set / skip / exclusion changes while `.ai` is selected.** Calls
   are skipped entirely when `sortOption != .ai`, when rules are empty/blank,
   or when a request is already in flight for identical inputs (dedupe by a
   hash of inputs, mirroring the equality guard in `ReminderStore.swift:420`).
   The previous ranking stays applied until a new one arrives (no flicker);
   a thrown error or timeout leaves the previous ranking in place.
5. **Composition: core owns the contract, the app target owns the model.**
   `SingleThreadCore` gains the `SortOption.ai` case, `AISortRulesStore`, the
   rank cache on `ReminderStore`, a ranker protocol, and a `@MainActor`
   coordinator taking `any AIReminderRanking` (explicit `@MainActor` — the
   package does not enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
   conventions §6). The FoundationModels adapter lives in the iOS app target
   in one file (mirroring `ReminderDictation.swift` in the app next to the
   parser in core), so the availability gate and the SDK dependency stay at
   one edge.
6. **Watch/widget: no AI, no new payload.** `.ai` travels as `rawValue` like
   the other options; `ReminderSort` treats `.ai` as the `.priority` chain
   when no ranking is present, which is always the case off-iOS. Widget needs
   no change beyond compiling the new case.
7. **Unavailable-device UX: `.ai` stays selectable with a footer.** The row
   and the rule box render normally; a `Section` footer states that this
   device cannot run on-device AI and the list falls back to priority order.
   Reason string (`deviceNotEligible` / `appleIntelligenceNotEnabled` /
   `modelNotReady`) can refine the copy but is not required.
8. **Tests use a fake ranker; no test depends on Apple Intelligence.** A
   deterministic fake (canned ordering, plus throwing and never-completing
   variants) covers the coordinator, and `ReminderStore` tests set the rank
   cache directly. The real-model path gets at most one smoke test that
   `skip`s (or asserts nothing) when `availability != .available`, so CI stays
   green; the local host currently reports `.available`.
9. **No new UI test unless the visible flow can't be covered otherwise.**
   The conditional row + persistence is unit-testable at the
   `SettingsBindings`/store level (`SettingsViewTests.swift:191-192,374-400`
   precedent) and CI cannot produce AI ordering; the PR must state this
   justification explicitly (AGENTS.md UI-test policy).

## What We're NOT Doing

- Not raising the iOS 17.0 floor, not touching `verify_deployment_target`, not
  adding a new target or SDK package dependency.
- Not syncing rule text or AI rankings to the watch, and not adding AI to the
  watch or widget; no new WCSession payload keys.
- Not bundling a model, using Core ML, SiriKit, or a remote/cloud API.
- Not building a rule language, rule validation, rule preview, or an
  explanation UI — the rule text is opaque input to the model.
- Not changing the three existing sort options or their comparator chains, and
  not adding per-list or per-rule scoping.
- Not adding a separate settings screen/tab; the rule box lives in
  `FilterSortSettingsView`.
- Not creating child tickets — all work stays on this branch.
- Not adding a widget test target (none exists; conventions §4).

## Open Risks

1. **CI toolchain divergence (highest).** The gated import was verified only
   under local Xcode 27.0. If Xcode 26.6 rejects the import at a 17.0 floor,
   the fallback is to move the adapter behind a thin `@available` wrapper in
   the app target (already its location) and, if still rejected, to gate at
   the file level; raising the floor is out of scope and would need a
   re-decision. The Plan phase must compile-probe this under CI's toolchain
   shape before writing the adapter.
2. **Apple Intelligence availability is environment-dependent** (`.available`
   here, presumably `deviceNotEligible` on runners, unknown on iOS 26
   simulators). Any accidental dependency on the real model in a test makes
   the gate flaky — the fake is not optional.
3. **Model output is untrusted.** Hallucinated/omitted ids, non-stable
   ordering across identical inputs, guardrail refusals
   (`GenerationError`/`Refusal`), and multi-second latency are all expected;
   validation + previous-ranking retention + a bounded wait are required, and
   prompts must include the immutable identifier list rather than relying on
   the model to re-read titles.
4. **List-size limits.** Prompt size grows with the reminder count; very long
   lists (or long rule text) may exceed the model's context or degrade
   latency. The design accepts a "rank only what fits / fall back for the
   rest" behavior but the threshold is unproven — measure during
   implementation and, if needed, cap the ranked set and document it.
5. **Visible reorder churn.** Ranking changes can reorder the list mid-scroll;
   the debounce plus "retain previous ranking" mitigates but does not remove
   it. Worth a note in the PR; no animation work is planned.
6. **First freeform text-input UI in the app.** Keyboard focus, dismissal,
   Dynamic Type, and the a11y audit (`performAccessibilityAudit`) have no
   precedent here; the label/trait rules and the caption-padding rule in
   AGENTS.md apply, and local hit-region audit can fail where CI passes.
7. **Enum exhaustiveness.** Adding `.ai` will surface every `switch` over
   `SortOption` (comparator, sync decode, widget, watch) as a compile error;
   each site needs a deliberate `.ai` branch, which is wanted but is the main
   source of unexpected diff size.