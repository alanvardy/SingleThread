# Design Discussion — VAR-626: Add Delete

## Current State

- The app can only **complete** (mark done in EventKit) or **skip** (hide via a
  persisted skip list) a reminder. There is no way to remove one entirely.
- `EventKitStoring` (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:8`)
  is the single write seam into EventKit. It exposes only `save(_ reminder: EKReminder,
  commit: Bool) throws` (`EventKitStoring.swift:29`) — **no removal counterpart**.
  Write ops are gated `#if !os(watchOS)` (`EventKitStoring.swift:27`).
- Every reminder mutation funnels through `ReminderStore` (`@MainActor @Observable`,
  `ReminderStore.swift:5`): `completeReminder` (`:121`) is mutate-and-save
  (`isCompleted = true` → `save(commit: true)` → 200 ms settle → `reload()`),
  plus `skipCurrentReminder(Immediately)` (`:173`/`:198`) and `addReminder` (`:148`).
  Each ends in `reload()` → `onRemindersChanged?()`.
- `visibleReminders` (`:95`) filters by skip list + excluded projects, sorts, and is
  the de-facto "current reminder": iOS card + swipe/contextMenu, macOS `actionButtons`,
  watch card, and widget all render `.first`.
- Cross-surface relay: watch completes locally (`reminders.removeAll`, `:123`) + fires
  `onCompleteReminder` (`:54`) → `SkippedReminderSyncService.requestCompleteReminder`
  → iPhone (`SkippedReminderSyncService.swift:190` area), with new `PayloadKey`s
  (`SkippedReminderSyncService.swift:230`). iOS wires these hooks in
  `SingleThreadApp.swift:35–46`; watch wires its side in `SingleThreadWatchApp.swift:29`.
- Skipped IDs are pruned during `reload()` via `ReminderSkipLogic.resolve`
  (`ReminderStore.swift:229`), so gone reminders already drop out of the skip list.

## Desired End State

- User can permanently delete the current reminder. Delete removes the `EKReminder`
  from EventKit via a new seam primitive:
  **`EKEventStore.removeReminder(_: EKReminder, commit: Bool) throws`**
  (`EKEventStore.h:370` — iOS/macOS only, `__WATCHOS_PROHIBITED`). It deletes the whole
  object, so on a recurring reminder it removes **the entire series** (no per-occurrence
  `span`, unlike `removeEvent:`).
- Exposed as: iOS `.contextMenu` item; macOS plain button in the `actionButtons` row
  (no shortcut); watch button relayed to the iPhone. Omitted from the widget. No
  confirmation dialog on any surface.
- After delete the reminder disappears from every surface; the skip list self-cleans
  on next `reload()`. Covered by unit tests (removal recorded + reload) and the
  accessibility audit (labels/traits on the new buttons).

## Patterns to Follow

- **Mutation → settle → reload → hook.** Mirror `completeReminder`'s structure:
  `guard` the fetched instance, mutate, `save`/`remove(commit:true)`, settle 200 ms
  (`ReminderStore.swift:279`), `reload()`, and let `reload()` fire `onRemindersChanged`
  (`ReminderStore.swift:226`). Log errors via `Self.logger.error` and skip reload on
  failure (`:127–131`).
- **Seam + gated write op.** Add `remove(_ reminder, commit:) throws` to
  `EventKitStoring` inside the existing `#if !os(watchOS)` block (`EventKitStoring.swift:27`),
  and implement it in the `EKEventStore` extension (`:41`) as a thin call to
  `removeReminder:`. This mirrors how `save` is surfaced so the watch target still
  compiles.
- **Skip-list self-clean on reload.** No delete-specific skip handling needed —
  `ReminderSkipLogic.resolve` (`ReminderStore.swift:109`) already drops the deleted
  ID on the next fetch.
- **watchOS local + relay.** Mirror `completeReminder`'s watch branch
  (`ReminderStore.swift:121–`126,`:). Delete on watch removes locally and fires a new
  `onDeleteReminder` hook; wire it to the sync service like `onCompleteReminder`
  (`SingleThreadApp.swift:46`, `SingleThreadWatchApp.swift:29`).
- **Button composition + accessibility.** Follow the established shape: `Label(title,
  systemImage:)` + `.tint(...)`; macOS adds `.accessibilityLabel(...)` +
  `.accessibilityAddTraits(.isButton)` (`ContentView.swift:201–203`). Use a trash icon
  and `.red` tint to signal destructiveness.
- **Recording fake.** Add a recording `remove(_:)/removed:[EKReminder]/lastRemoveCommit`
  (and a `removeShouldThrow`) to `FakeEventStore` beside `save`
  (`EventKitStoringTests.swift:93–97`), and cover happy + error paths like the
  existing write tests (`:127–158`).

## Patterns to NOT Follow

- **`Save` for delete.** Do not try to "delete" by saving; EventKit has no tombstone
  semantics — use the real `removeReminder` API.
- Swipe-actions don't currently contain Delete (decision-driven, see below); do not
  retro-fit the trailing swipe.
- The widget's unconfirmed one-tap `AppIntent` shape (es-cheque `UnchequeReminderIntent`,
  `ReminderIntents.swift:30`) is exactly why we omit Delete from that surface — do not
  add a `DeleteReminderIntent`.

## Design Decisions

1. **iOS placement: contextMenu only.** Delete joins "View in Reminders" in the iOS
   `.contextMenu` (`ContentView.swift:277`) as a trash-tinted row. Lower accidental
   delete risk than a swipe edge; stays discoverable. (Choice 1b.)
2. **No confirmation anywhere.** Delete is intentionally unguarded per the user's
   guidance — consistent with how Complete/Skip already act without confirmations.
   (Choice 2)
3. **macOS: plain button, no shortcut.** Add Delete to the `actionButtons` HStack
   (`ContentView.swift:191`), red tint, no `.keyboardShortcut`, with accessibility
   label/traits. A destructive key is avoidable. (Choice 3b)
4. **Watch: relayed; widget: omitted.** Watch adds a Delete button (red) that routes
   through the store's watch branch → new `onDeleteReminder` hook →
   `requestDeleteReminder` → iPhone. The widget keeps only Complete/Skip to avoid an
   unconfirmed one-tap permanent delete. (Choice 4b)
5. **Delete removes the entire recurring series.** EventKit's reminder API has no
   per-occurrence removal, so a recurring reminder is deleted as one series. (Choice 5)

## What We're NOT Doing

- No swipe-edge Delete on iOS; Delete lives only in the context menu.
- No Delete on the **widget** extension (pace single removal of ephemeral items).
- No confirmation dialogs / undo / toasts for delete anywhere.
- No per-occurrence recurrence deletion (unsupported by `EKEventStore`).
- No new skip-list keys or tombstone persistence — the existing `resolve` pruning
  handles cleanup.
- No changes to the completion predicate, sort, or date-window logic.

## Open Risks

- **SwiftUI contextMenu on touch:** a deeper placement of Delete in the iOS context
  menu (Menu)+may need XCTest/iOS coverage to confirm hit region + label surfacing.
- **`removeReminder` Swift Qdomain:** the method exists in the header
  (`EKEventStore.h:74`) but must be usable from Swift in SwiftUI 6 — verify quickly
  in the Debug build.
- **Watch delete ordering:** mirror the existing (again `handledOrder`)
  completion-path; the receive-side handler assignment is not yet a header
  (`onCompleteReminderReceived`'s removal-plan clean-up) — pick one and stay consistent.
- **Skip-list edge:** if a reminder is deleted **while skipped**, its skip ID is
  pruned on the next `reload()`; confirm that leaves no stale ID in the watch's
  pushed context.

## Open Questions After Research

- **Watch app wiring:** `SingleThreadWatchApp.swift:29` wires `onCompleteReminder`
  to `requestCompleteReminder`, but does **not** set `onCompleteReminderReceived`
  (the local watch completion just removes + relays). Decide whether delete
  likewise stays local-only on watch or also needs receive-side handling (most
  likely local-only + relay, same as complete).

Next: run `/4_structure`