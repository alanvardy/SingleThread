# Design Discussion

Ticket: VAR-1018 — App Intents for "What's Next", "Complete Current Task", "Skip Current Task".
Branch: `alanvardy-var-1018-app-intents`. All `file:line` refs are to the repo root.

## Current State

The repo already has **two widget-only App Intents** and **no system surface** for them.

- `CompleteReminderIntent` / `SkipReminderIntent` live in
  `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:7-50`. Both are
  `public struct … : AppIntent` with an explicit `@MainActor perform() async throws
  -> some IntentResult` (`:15-17,38-40`), an empty `public init()`, a `title`, and
  **`static let isDiscoverable = false`** (`:13,36`). Both return plain
  `.result()` — no dialog, no value (`:23,50`).
- Their only consumers are widget buttons: `Button(intent:)` in
  `SingleThreadWidget/NextThingWidget.swift:155-172`, rendered in the
  `.reminder(display)` case (`:237`). No `AppShortcutsProvider`,
  `commandsAppShortcuts`, or `INIntent` exists anywhere (`research.md` Q2) — the
  app-icon long-press / Siri / Shortcuts surface simply **does not exist**.
- The intent recipe is: fresh `ReminderStore(loadsReminders: true)` per
  `perform()` → `setSortOption(SortOptionStore().load())` → `await store.reload()`
  → mutate → return (`ReminderIntents.swift:18-23,41-46`). The widget's
  `makeEntry()` uses the same shape (`NextThingWidget.swift:61-91`) and is the
  repo's precedent for running outside the app lifecycle.
- `ReminderStore` is `@MainActor @Observable public final class`
  (`ReminderStore.swift:14-16`); Core has no `SWIFT_DEFAULT_ACTOR_ISOLATION`
  (`project.pbxproj:777,827` are app/watch only), so Core code must annotate
  `@MainActor` explicitly — the existing intents do.
- Mutation durability differs by operation:
  - `completeCurrentReminder()` → `completeReminder(identifier:)` sets
    `isCompleted`, `eventStore.save(reminder, commit: true)`, then **awaits
    `settle()` + `reload()`** before returning `true` (`:228-273`).
  - `skipCurrentReminder()` (`:393-414`) is sync `Void` and **fire-and-forget**:
    it spawns `Task { await settle(); … }` — unsafe if the process is suspended.
  - `skipCurrentReminderImmediately()` (`:434-449`) is sync `-> Bool` and writes
    through `applySkipSet` **before returning**; its doc comment (`:428-433`)
    states this is the WidgetKit-safe path precisely because the process may be
    suspended right after `perform()` returns.
- Empty/blocked states are already modelled: `visibleReminders` (`:155-162`),
  `allSkipped` (`:164-168`), `hasHidden` (`:71,119-124`), `listContent`
  (`:171-180`). `EKEventStore.authorizationStatus(for: .reminder)` is checked
  **inline, before** store construction in the widget (`NextThingWidget.swift:70`);
  intents never prompt and never call `start()`/`requestAccess()`.
- Dialog construction has **zero precedent** in the repo; only plain `.result()`
  is used (`ReminderIntents.swift:23,50`).

## Desired End State

Three intents, reachable from Siri, the Shortcuts app, Spotlight and the Home
Screen app-icon long-press menu, sharing the widget's store recipe:

1. **`WhatsNextIntent`** — no side effects; returns the current next task's title
   as a Shortcuts value plus a spoken dialog.
2. **`CompleteCurrentTaskIntent`** — re-fetches the current task at perform time,
   completes it, awaits the persist, returns a dialog naming what was completed.
3. **`SkipCurrentTaskIntent`** — same re-fetch, skips via the synchronous
   persist path, returns a dialog naming what was skipped.

All three re-fetch inside `perform()` (never cache), never prompt for
authorization, and always return a dialog — including the no-next-task and
no-access cases. Verified correct when: an app-icon long-press / Shortcuts run of
each intent mutates real Reminders and the widget/app reflect it; running on an
empty list speaks "nothing to do" rather than failing; running with denied
Reminders access speaks the access message rather than claiming the list is
empty; no intent crashes or hangs when the process is suspended after return.

## Patterns to Follow

Match these existing patterns:

- **Fresh store per invocation**: construct, `setSortOption(SortOptionStore().load())`,
  `await reload()` — `ReminderIntents.swift:18-23,41-46`, `NextThingWidget.swift:73-76`.
- **Authorization gate before building the store**, never prompting —
  `NextThingWidget.swift:70,82-88`; intents must mirror this (`research.md` Q3).
- **Awaited/synchronous persist before returning**: `completeReminder` awaits
  `settle()`+`reload()` (`ReminderStore.swift:260-273`); `skipCurrentReminderImmediately`
  writes before returning (`:434-449`).
- **Explicit `@MainActor`** on every intent entry point in Core — no default
  isolation there (`ReminderIntents.swift:15,38`; `project.pbxproj:777,827`).
- **IntentResult capability fidelity**: declared return-type protocols must match
  the `.result(...)` builder supplied, or the framework fatals at runtime
  (`research.md` Q4).
- Localized strings come from `LocalizedStringResource` literals; existing
  `title`s resolve from the app's `.main` catalog, not Core's
  (`ReminderIntentsTests.swift:12-25`).

Do **not** follow these:

- **`commandsAppShortcuts`** — not a real AppIntents API (`research.md` Q4). Use
  `AppShortcutsProvider` + `AppShortcut`.
- **`store.skipCurrentReminder()` from an intent** — fire-and-forget
  `Task` (`ReminderStore.swift:393-414`) loses the write if the process is
  suspended. Use the immediate variant.
- **The macOS `appCommands` path** (`SingleThread/SingleThreadApp+Commands.swift:28-42`):
  it calls the store directly inside `Task { @MainActor … }` and bypasses the
  intent structs entirely — not a model for user-facing intents, and macOS-only.
- **Config-only intent tests** (`ReminderIntentsTests.swift:12-25`): asserting
  `isDiscoverable == false` and title resolution is not coverage for new logic
  (repo AGENTS.md).
- **`start()` / `requestAccess()` from an intent** (`ReminderStore.swift:206-214,537-549`):
  view-layer lifecycle calls; prompting mid-Siri-turn can hang the turn.

## Design Decisions

1. **Three new intent structs; widget pair untouched.** Keep
   `CompleteReminderIntent`/`SkipReminderIntent` non-discoverable and unmodified,
   so widget taps keep their exact behavior. New types carry the ticket's names,
   dialogs and discoverability. Avoids regressing the widget contract and avoids
   a dialog firing from a widget tap.
2. **Intents in `SingleThreadCore`; the provider in the app target.** New
   intents go in `ReminderIntents.swift` (or a sibling file in Core) so they are
   unit-testable and consistent with today's placement. `AppShortcutsProvider`
   requires the app target, so a new `SingleThread/AppShortcuts.swift` holds only
   the `AppShortcut` registrations. *(Risk 2: packaged-intent eligibility is
   unverified; fallback is moving the intents into the app target if the provider
   cannot resolve them.)*
3. **Discoverability via `AppShortcutsProvider`** with one `AppShortcut` per
   intent, each phrase containing `\(.applicationName)`, plus `shortTitle` and
   `systemImageName`. This is the single documented route that covers Siri,
   Shortcuts, Spotlight **and** the app-icon long-press menu without user setup.
   No `UIApplicationShortcutItem` duplication.
4. **`WhatsNextIntent` returns a value**: declare
   `some IntentResult & ReturnsValue<String> & ProvidesDialog`, value = the
   reminder's title, dialog = the same sentence. No custom `AppEntity` in v1 —
   a `String` is directly consumable by downstream Shortcuts actions and needs no
   query/options plumbing.
5. **Distinguish "no access" from "no next task".** Check
   `EKEventStore.authorizationStatus(for: .reminder)` first (widget pattern,
   `NextThingWidget.swift:70`). Not `.fullAccess` → the access dialog, without
   building a store or prompting. Authorized but nothing visible → the
   "nothing to do" dialog. Both are successful `.result(dialog:)` outcomes, not
   throws.
6. **Complete and Skip return `some IntentResult & ProvidesDialog`** naming the
   task on success, and the "nothing to do" dialog on a `false` return from the
   store. No `throw` for the empty case: a throw in Shortcuts reads as an error,
   whereas "there was nothing to do" is a legitimate successful outcome.
7. **Success/failure signal**: `completeCurrentReminder()` returns `Bool`
   (`false` = nothing visible / gated / save failed) and
   `skipCurrentReminderImmediately()` returns `Bool`. Both feed the dialog; no
   new store API is needed.
8. **Skip uses `skipCurrentReminderImmediately()`** (synchronous,
   persisted-before-return, `ReminderStore.swift:434-449`) rather than the
   fire-and-forget `skipCurrentReminder()`. This is how the ticket's
   "await the save before returning" is satisfied for skip — the write is
   durable before `perform()` returns, matching the WidgetKit hazard note at
   `:428-433`. Complete is literally awaited via `settle()`+`reload()`.
9. **Extract a shared `@MainActor` construction helper in Core**, e.g.
   `ReminderIntentSupport.makeStore(eventStore:authorizationStatus:) async ->
   ReminderStore?` returning `nil` when not `.fullAccess`, encapsulating
   authorization check + `setSortOption` + `reload()`. The three new intents use
   it; the two existing widget intents stay as they are to keep this diff
   focused. Exact signature is a planning detail; the contract is: *nil means
   speak the access dialog, otherwise an already-reloaded store*.
10. **Test strategy**: unit-test the helper's authorized/denied branches and each
    intent's dialog/no-next-task logic through the existing `InMemoryEventStore`
    + `authorizationStatus` injection seams (`ReminderStore.swift:20-56`), and
    extend `ReminderIntentsTests.swift` with title/dialog/return-type assertions
    for the three new types. The Siri/Shortcuts/app-icon invocation itself stays
    manual (Shortcuts app + app-icon long-press), per the ticket — no UI test,
    because there is no UI-test seam for the system invocation.

## What We're NOT Doing

- Not making the widget intents discoverable, and not rewriting them to share
  the helper (that refactor is a separate cleanup).
- Not adding `openAppWhenRun`, `ForegroundContinuableIntent`, or any
  background→foreground hand-off; all three intents stay background-only.
- Not adding a custom `AppEntity`, a parameterized intent, or an entity query.
- Not adding `UIApplicationShortcutItem` / a bespoke long-press menu.
- Not changing `ReminderStore`'s public API beyond the new helper.
- Not adding UI tests (no UI-test seam exists for Shortcuts/Siri invocation).
- Not adding `WidgetCenter.reloadAllTimelines()` from the intents: Core has no
  WidgetKit dependency today, and the widget's 5-minute `.after` refresh policy
  (`NextThingWidget.swift:46-56`) already bounds staleness. *(See Risk 3.)*
- Not adding new dependencies, targets, or pbxproj object IDs; new `.swift` files
  need no pbxproj edit (synchronized file groups).

## Open Risks

1. **"Await the save" for skip is synchronous, not literally awaited.** The
   requirement is satisfied by `skipCurrentReminderImmediately()` writing before
   return; confirm reviewers accept that reading.
2. **`AppShortcutsProvider` eligibility for an SPM-packaged intent is
   UNVALIDATED.** No precedent exists in the repo (`research.md` Q4 "Open
   Areas"). The plan must verify by compiling; fallback is moving the three
   intent structs into the app target (and duplicating or re-exporting them for
   tests).
3. **Widget/app staleness after a Siri-triggered mutation.** Nothing calls
   `WidgetCenter.shared.reloadAllTimelines()` from the intent path (it is wired
   only in `AppViewModel.swift:36-44`), so the widget can show the old task for up
   to its 5-minute refresh window. Accepted for v1; revisit if it reads as a bug.
4. **`shortcutTileColor` / newer-SDK `AppShortcut` requirements** may be
   mandatory under local Xcode 27.0 but not CI 26.6. Verify by compiling on both.
5. **Localization**: dialog strings will be `LocalizedStringResource` literals
   added to the app's `.main` catalog; Core's catalog does not hold intent keys
   (`ReminderIntentsTests.swift:15-16`). Missing catalog entries degrade to
   literal English, not a build failure — manual check needed.
6. **Titles must not collide with the existing "Complete Reminder"/"Skip
   Reminder"** or Siri may disambiguate between two similar app commands. New
   titles use the ticket's "Complete Current Task"/"Skip Current Task" wording.
7. **Not-authorized path depends on `EventKitStoring` exposing
   `authorizationStatus`** so tests can inject `.denied`. Verify in planning;
   `InMemoryEventStore` must support the same status seam as `ReminderStore`.