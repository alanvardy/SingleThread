# Design Discussion

## Current State

SingleThread is a minimal SwiftUI + SwiftData template. Everything lives in three files:

- `Item.swift:10-20` — the only `@Model`, `final class Item` with a single
  persisted `var timestamp: Date` (`Item.swift:20`).
- `SingleThreadApp.swift:12-23` — builds a `sharedModelContainer` from
  `Schema([Item.self])`, `isStoredInMemoryOnly: false`, `fatalError` on failure
  (`:21`), and injects it via `.modelContainer(sharedModelContainer)` (`:26-29`).
- `ContentView.swift` — a `List` driven by `@Query private var items: [Item]`
  (`:46`), rows rendering `item.timestamp` via `Date.FormatStyle` (`:18`, `:20`),
  `addItem()` inserting `Item(timestamp: Date())` (`:48-53`), `deleteItems()`
  (`:55-61`), and an add/Edit toolbar (`:28-39`). `NavigationViewWrapper`
  (`:64-78`) is the one cross-platform shim: macOS gets a `NavigationSplitView`,
  everything else a bare passthrough.

There is **no** EventKit, no `EKEventStore`, no reminders code anywhere. No
`.entitlements` file exists, and no `INFOPLIST_KEY_NS*UsageDescription` keys are
set (`project.pbxproj:401-410` Debug / `:445-454` Release). `ENABLE_APP_SANDBOX
= YES` (`project.pbxproj:396`) is on, but with no entitlement to grant any
personal-data access. The date layer is just the `Item.timestamp` `Date`; there
are no `Calendar`, `DateComponents`, or comparison APIs in the codebase.

## Desired End State

The main list surfaces the user's **Reminders** — fetched live from the system
store via EventKit — instead of locally stored `Item` timestamps. Only reminders
that are **incomplete** and **overdue or due today** (day-level granularity)
appear, sorted ascending by due date, with overdue rows visually distinct.
The `Item` model and all SwiftData wiring are removed entirely.

Verify by:
- Build passes on the `iPhone 17` iOS simulator and a macOS destination.
- iOS launch → TCC prompt → list shows exactly the qualifying reminders.
- Denied / not-determined / no-qualifying-reminders states render a message.
- macOS (sandboxed) prompts and shows reminders in the `NavigationSplitView` sidebar.
- Swift Testing unit tests cover the classifier's boundary cases (below).
- `./scripts/test.sh` is green.

## Patterns to Follow

- **`#if os(...)` conditionals** — `ContentView.swift:25`, `:29`, `:68`; extend
  this for `#if os(iOS) || os(macOS)` guards around reminder code.
- **`NavigationViewWrapper`** (`ContentView.swift:64-78`) — keep it; it already
  gives macOS the split view and iOS a plain list. Update the stale
  `Text("Select an item")` detail (`:72`) to a reminder-neutral string.
- **Generated Info.plist via `INFOPLIST_KEY_*`** — add the reminders usage key as
  a build setting, matching how all other plist keys are declared
  (`project.pbxproj:401-410`).
- **Swift Testing** for unit tests (`SingleThreadTests.swift:7-15`) — but with
  real assertions, not the empty `example()` body.
- **Synchronized file groups** (`objectVersion = 77`, `project.pbxproj:6`) — new
  `.swift` files are auto-discovered; no pbxproj membership edits.
- **`@MainActor` default isolation** (project-level `SWIFT_DEFAULT_ACTOR_ISOLATION`)
  — the store is `@MainActor` without any `Task { @MainActor in }` wrapping.

Do **not** follow:
- The duplicated timestamp formatting at `ContentView.swift:18` vs `:20` — one
  shared row view.
- The inert App Groups toggle (`REGISTER_APP_GROUPS`, `project.pbxproj:418`)
  with no declared group — don't replicate "toggle without backing config".
- The empty test body (`SingleThreadTests.swift:7-15`).

## Design Decisions

1. **Data source — live EventKit fetch (no mirror)**: reminders are read from a
   single `EKEventStore` on demand; they are never written to SwiftData. The
   system store is the source of truth; the task only requires display, so a
   sync layer buys nothing and adds staleness/completion bugs.

2. **Remove SwiftData and `Item` entirely**: delete `Item.swift`; remove the
   `Schema`/`ModelContainer` in `SingleThreadApp.swift:12-23`, the
   `.modelContainer` (`:26-29`), and in `ContentView.swift` the `@Query` (`:46`),
   `modelContext` (`:45`), `addItem`/`deleteItems` (`:48-61`), toolbar (`:28-39`),
   and the `.modelContainer(for: Item.self, ...)` preview (`:80-83`). The app
   entry point becomes a plain `WindowGroup { ContentView() }`. The old Item
   store file is simply orphaned — no migration needed since we drop the model.

3. **Filtering rule (day-level, default semantics)**: include a reminder iff it
   is *incomplete* AND has a due date AND `dueDate < startOfToday` (overdue) OR
   `dueDate` falls on today. Exclude completed reminders and reminders with no
   due date. Overdue is computed with day granularity via
   `Calendar.startOfDay(for: now)` — a reminder due today at any time is "due
   today," never overdue.

4. **List composition — single reminders list**: `ForEach` over reminders; each
   row shows title + due-date text. Overdue rows get a distinct style (e.g.
   `.foregroundStyle(.red)` or a badge). Sorted ascending by due date. No
   sections/grouping (Items are gone, and Overdue-vs-Today grouping is deferred).

5. **Access layer — `ReminderStore`**: a `@MainActor @Observable final class`
   owning one shared `EKEventStore`, exposing an access state
   (`.notDetermined / .denied / .authorized`) and `var reminders: [EKReminder]`,
   plus an async `load()` that calls `requestFullAccessToReminders()` (min target
   26.5 ≫ iOS 17 / macOS 14) and fetches. Injected via `.environment(...)`.

6. **Pure, testable classifier**: extract the overdue/today rule into a
   standalone pure function `dueStatus(dueDate:isCompleted:now:calendar:)` (or a
   small enum) living in its own file, so Swift Testing can cover it without any
   EventKit dependency. `ReminderStore` is a thin EventKit wrapper, exercised
   manually/visually rather than unit-tested.

7. **Permissions (iOS + macOS)**:
   - Add `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` to both Debug and
     Release app configs (generated plist; there are currently no `NS*` keys).
   - Add `SingleThread/SingleThread.entitlements` with
     `com.apple.security.personal-information.calendars` (the documented
     entitlement for Reminders on sandboxed macOS) and wire `CODE_SIGN_ENTITLEMENTS`.
     The iOS slice ignores this macOS-only entitlement harmlessly.

8. **Platform scope — iOS + macOS**: guard reminder-specific code behind
   `#if os(iOS) || os(macOS)`; the visionOS slice compiles but renders a
   "not supported on this device" empty state. EventKit does compile on
   visionOS, but it is out of scope this iteration (and there is a known
   empty-reminders report on Vision Pro).

9. **Refresh strategy**: load once on appear (`.task`) and re-load on foreground
   (`.onChange(of: scenePhase)` → `.active`). One shared store instance for the
   app's lifetime.

10. **Display-only rows**: no complete/edit/create/delete actions, no toolbar.
    This is the "for now" scope; interaction can be layered on later.

## What We're NOT Doing

- No SwiftData mirroring/caching of reminders.
- No create / complete / edit / delete of reminders (display only, for now).
- No visionOS reminder support this iteration.
- No deep-linking into the Reminders app (rows are non-interactive).
- No Overdue-vs-Today sections or other grouping beyond one sorted list.
- No migration path for the old `Item` store — it is dropped with the model.
- No calendar *event* access — reminders only (full-access reminder scope).
- No App Group / cross-device sync of app-owned data.

## Open Risks

- **First-grant empty results**: EventKit can return stale/empty data right after
  authorization; mitigate with a single shared `EKEventStore` and a
  `store.reset()` after granting.
- **macOS not covered by CI**: `Makefile`/`scripts/test.sh`/`ci.yml` only build
  and test the iOS simulator; the macOS entitlement path needs manual
  verification.
- **App Review friction on macOS**: a reminders-only app declaring the
  "Calendars" entitlement may be questioned (it is the officially required key).
- **Day boundary / time zone**: "today" depends on the device calendar and
  timezone; a reminder due at 00:30 local time is an edge case the classifier
  tests should pin down.
- **TCC prompts are not automatable**: permission denial/approval flows can't be
  covered by the existing UI-test scaffold.
- **Removing SwiftData touches the app entry point**: ensure no dangling
  `.modelContainer`/`@Query`/`modelContext` references remain after deletion.
