# Structure Outline

Ticket: VAR-1018 — App Intents for "What's Next", "Complete Current Task", "Skip Current Task".
Branch: `alanvardy-var-1018-app-intents`. Refs are to `design.md` / `research.md` / `conventions.md`.

## Approach

Add three discoverable intents in `SingleThreadCore` (beside the existing
widget pair, which stays untouched) plus one `AppShortcutsProvider` in the app
target that registers them for Siri/Shortcuts/Spotlight/app-icon long-press.
Each `perform()` is a thin presentation shim: it resolves authorization, builds
a fresh reloaded store, asks a shared `@MainActor` support function for an
outcome, and maps that outcome to `.result(value:dialog:)`.

**One refinement to `design.md` 9/10.** The design's helper returns a store
or `nil`; that alone leaves `perform()` bodies untestable. Structure adds a
`ReminderIntentOutcome` value that the support functions produce from a store,
so *all* message/no-next-task logic is unit-testable and `perform()` keeps only
the un-unit-testable `.result(...)` fidelity mapping. `makeStore` therefore
takes the authorization status as a **parameter** (a pure function) rather than
reading `EKEventStore` statically — required anyway, since
`InMemoryEventStore` hardcodes `.fullAccess` (`InMemoryEventStore.swift:37`),
which resolves design Risk 7. Design decisions 1–8 are unchanged.

Slicing is **risk-first**: the walking skeleton is the read-only intent, because
registering an AppShortcut for an SPM-packaged intent is the single unvalidated
integration (design Risk 2) — if it fails, the fallback (move the structs into
the app target) reshapes every later slice, so it must be proven first.

## Phase 1: Walking skeleton — `WhatsNextIntent` reachable from the system

The user long-presses the app icon (or asks Siri / opens Shortcuts) and gets the
current next task's title back, spoken and usable as a Shortcuts value; on an
empty list or denied Reminders access they get a spoken message instead of a
failure. Green tests + a manual long-press run prove the whole pipeline:
authorization gate → fresh store → real EventKit read → sorted `visibleReminders.first`
→ dialog + value → system surface.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntentSupport.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`,
`SingleThread/AppShortcuts.swift` (new),
`SingleThreadTests/ReminderIntentSupportTests.swift` (new),
`SingleThreadTests/ReminderIntentsTests.swift`.

**Key changes**:

- `@MainActor public enum ReminderIntentSupport` — new:
  - `static func makeStore(eventStore: any EventKitStoring, authorizationStatus: EKAuthorizationStatus, loadsReminders: Bool = true) async -> ReminderStore?`
    — `nil` ⇔ `authorizationStatus != .fullAccess` (no store built, never prompts,
    never `start()`/`requestAccess()`); otherwise `ReminderStore(loadsReminders:)`
    + `setSortOption(SortOptionStore().load())` + `await reload()`.
  - `static func nextOutcome(for store: ReminderStore) -> ReminderIntentOutcome`
  - `static func dialog(for outcome: ReminderIntentOutcome) -> LocalizedStringResource`
  - `static func value(for outcome: ReminderIntentOutcome) -> String` (empty string for non-answers)
- `@MainActor public enum ReminderIntentOutcome: Equatable` — new:
  `.noAccess`, `.nothingToDo`, `.next(String)` (`.completed`/`.skipped` land in Phases 2/3).
- `public struct WhatsNextIntent: AppIntent` — new: `static var title: LocalizedStringResource = "What's Next"`,
  `static var isDiscoverable = true`,
  `@MainActor public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog`.
- `struct SingleThreadShortcuts: AppShortcutsProvider` — new, app target:
  `static var appShortcuts: [AppShortcut] { [AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next in \(.applicationName)"], …)] }`.

**Contract**: `makeStore` returning `nil` means "speak `dialog(for: .noAccess)`";
`ReminderIntentOutcome` is *the* interface every later intent consumes;
`dialog(for:)`/`value(for:)` are the only place message text is decided.
Because the declared return type is `ReturnsValue<String> & ProvidesDialog`,
**every** path supplies both — non-answers return `value: ""` with their dialog
(result-builder fidelity is a runtime fatal, research Q4).

**Tests**: `ReminderIntentSupportTests.makeStoreReturnsNilWhenAccessDenied` (sad),
`makeStoreReturnsReloadedStoreWhenAuthorized` (happy `visibleReminders` non-empty),
`makeStoreDoesNotPromptWhenNotAuthorized` (sad: `InMemoryEventStore` untouched),
`nextOutcomeNamesTheFirstVisibleReminder` (happy: seeded priority sort),
`nextOutcomeIsNothingToDoWhenAllSkipped` (sad), `nextOutcomeIsNothingToDoWhenEmpty` (sad);
`ReminderIntentsTests.whatsNextIntentIsDiscoverable` + `whatsNextIntentTitleResolves`.

**Verify**: `make test` (`-only-testing:SingleThreadTests`, macOS native — also
compiles the app target, so the provider must compile) and `make build`.
Manual: app-icon long-press shows "What's Next" and running it speaks the task;
repeat with a seeded empty list and with Reminders access denied.

---

## Phase 2: `CompleteCurrentTaskIntent` — complete from the system surface

Siri/Shortcuts/app-icon completes the current task for real: the intent
re-fetches at perform time, awaits the durable save, and names what it completed
("Marked *Buy milk* as done"); with nothing visible it says so rather than
erroring.

**Files**: `ReminderIntents.swift`, `SingleThread/AppShortcuts.swift`,
`ReminderIntentSupport.swift`, `ReminderIntentSupportTests.swift`, `ReminderIntentsTests.swift`.

**Key changes**:

- `ReminderIntentOutcome` gains `.completed(String)`.
- `static func completeOutcome(for store: ReminderStore) async -> ReminderIntentOutcome` —
  captures `store.visibleReminders.first?.title` **before** the mutation
  (after completion it is filtered out), then guards `store.canMutate`
  (`false` ⇒ `.cannotMutate`) and awaits `store.completeCurrentReminder()`
  (`false` ⇒ `.failed`). No `throw` for the empty case (design decision 6, revised in review).
- `public struct CompleteCurrentTaskIntent: AppIntent` — new, `isDiscoverable = true`,
  `title = "Complete Current Task"` (distinct from the widget's "Complete Reminder", Risk 6),
  `perform() async throws -> some IntentResult & ProvidesDialog`.
- `dialog(for:)` gains the `.completed` case; `SingleThreadShortcuts.appShortcuts` gains the second entry.

**Contract**: `.completed(title)` carries the task name captured pre-mutation;
the second `AppShortcut` follows Phase 1's shape exactly (no new provider mechanism).

**Tests**: `completeOutcomeNamesTheCompletedTask` (happy),
`completeOutcomeIsNothingToDoWhenEmpty` (sad),
`completeOutcomeReportsFreeLimitWhenMutationGated` (sad: freemium cap via injected `EntitlementStore`),
`completeOutcomeReportsFailureWhenSaveThrows` (sad: EventKit save error),
`completeOutcomePersistsThroughInMemoryEventStore` (happy: `saveCallCount == 1` and the reminder is completed),
`completeCurrentTaskIntentIsDiscoverable`.

**Verify**: `make test` + `make build`; manual: run the shortcut from Shortcuts
and from the app-icon long-press, confirm the Reminders item flips and the
widget/app reflect it.

---

## Phase 3: `SkipCurrentTaskIntent` — skip with a durable write

Siri/Shortcuts/app-icon skips the current task and names it; the write is
persisted **before** `perform()` returns (the `skipCurrentReminderImmediately()`
path, design decision 8), so a suspend-after-return cannot lose it.

**Files**: `ReminderIntents.swift`, `SingleThread/AppShortcuts.swift`,
`ReminderIntentSupport.swift`, `ReminderIntentSupportTests.swift`, `ReminderIntentsTests.swift`.

**Key changes**:

- `ReminderIntentOutcome` gains `.skipped(String)`.
- `static func skipOutcome(for store: ReminderStore) -> ReminderIntentOutcome` — **sync**,
  captures the pre-skip title, guards `store.canMutate` (`false` ⇒ `.cannotMutate`),
  then calls `skipCurrentReminderImmediately()` (never the fire-and-forget
  `skipCurrentReminder()`); a refused skip ⇒ `.failed`.
- `public struct SkipCurrentTaskIntent: AppIntent` — new, `isDiscoverable = true`,
  `title = "Skip Current Task"`, `perform() async throws -> some IntentResult & ProvidesDialog`.
- Third `AppShortcut`; `dialog(for:)` gains `.skipped`.

**Contract**: `.skipped(title)` names the skipped task; the skip path is
synchronous by contract — no `await` between the mutation and the returned dialog.

**Tests**: `skipOutcomeNamesTheSkippedTask` (happy),
`skipOutcomeIsNothingToDoWhenEmpty` (sad),
`skipOutcomeReportsFreeLimitWhenMutationGated` (sad),
`skipOutcomePersistsSkipSetBeforeReturning` (happy: both in-memory `skippedIDs` and the
injected `SkippedReminderStore` contain the id after the call — the durability assertion),
`skipCurrentTaskIntentIsDiscoverable`.

**Verify**: `make test` + `make build`; manual: app-icon long-press skip, then
relaunch the app and confirm the task is still skipped.

---

## Phase 4: Hardening — accurate messages, localization, SDK compatibility

The spoken answers stop being one-size-fits-all and the surfaces are verified
against both toolchains: an all-skipped list says so instead of claiming there is
nothing to do; dialog and shortcut strings are real catalog entries that render
localized (not raw English) on a non-English device.

**Files**: `ReminderIntentSupport.swift`, `ReminderIntents.swift`,
`SingleThread/AppShortcuts.swift`, `SingleThread/Resources/Localizable.xcstrings`,
`ReminderIntentSupportTests.swift`.

**Key changes**:

- `ReminderIntentOutcome` gains a distinct case for "everything is skipped/hidden"
  (derived from `allSkipped` / `listContent == .empty(hasHidden:)`, `ReminderStore.swift:164-180`)
  so `nextOutcome`/`completeOutcome`/`skipOutcome` return it in place of `.nothingToDo`;
  `dialog(for:)` maps all three states distinctly. *(Post-review, the enum also
  carries `.cannotMutate` for the freemium cap and `.failed` for a failed write.)*
- `Localizable.xcstrings` gains the new dialog + `shortTitle` entries (Core's
  catalog does not hold AppIntent keys, `ReminderIntentsTests.swift:15-16`); phrases
  gain variants, each still containing `\(.applicationName)`.
- `shortcutTileColor` / newer-SDK `AppShortcut` requirements verified by compiling
  on local Xcode 27.0 **and** the CI 26.6 floor (design Risk 4); add only what
  both accept.

**Contract**: outcome-to-message mapping is now total over every outcome state; no
caller constructs message text.

**Tests**: `nextOutcomeReportsNothingLeftToDoWhenAllSkipped` (sad),
`nextOutcomeDistinguishesHiddenFromEmpty` (sad),
`everyOutcomeHasANonEmptyDialog` (happy, exhaustive over the enum),
`intentTitlesDoNotCollideWithWidgetIntentTitles` (sad path for Risk 6).

**Verify**: `make test`, `make build`, `make format`, `make lint`; plus the
`run-gate` skill once, after the phases commit. Manual: non-English device locale
renders translated dialogs; iOS build under Xcode 26.6 accepts the provider.

---

## Testing Checkpoints

- After Phase 1: `ReminderIntentSupportTests` + `ReminderIntentsTests` green,
  `make build` green, and the app-icon long-press menu **actually shows** "What's
  Next" — if it does not, stop and apply design Risk 2's fallback (move the
  intent structs into the app target) before Phase 2, because the fallback
  changes every later slice's file list.
- After Phase 2: Phase 1 tests still green (no contract break) + complete-path
  tests green; a real completion through Shortcuts observed in the Reminders app.
- After Phase 3: all earlier tests green + the post-relaunch durability check
  observed; `.skipped`/`.completed` dialogs both exercised manually.
- After Phase 4: no new outcome case left without a dialog test; both Xcode
  versions compile; the full `./scripts/test.sh` gate runs once via `run-gate`.
- Not covered by any local gate (manual only, per design): Siri phrasing,
  Spotlight, and the app-icon menu on a physical device. No UI test is added —
  no UI-test seam exists for system intent invocation.
