# Research Questions

## Context

Focus on the reschedule and recurrence plumbing across `SingleThreadCore/`
(`ReminderStore`, `EventKitStoring`, `EKEventStore`/`InMemoryEventStore`), the
iOS and watch view models and action-menu surfaces that invoke rescheduling,
the watch → phone reschedule relay (`SkippedReminderSyncService`), and the
unit/UI test suites that cover reschedule and recurrence.

## Questions

1. Trace the reschedule action end-to-end from every UI surface (iOS/macOS
   action menu, iPhone nudge sheet, watch action menu) through the view
   models to `ReminderStore.rescheduleReminder`: what exact sequence of
   operations does it perform on the `EKReminder` (field mutation, `save`,
   `resetSkipCount`, settle, reload), and does any path remove and recreate
   the reminder rather than mutating it in place?

2. What do `EKEventStore.save(reminder, commit:)` and the underlying EventKit
   adapter do for a reminder that has `recurrenceRules` — is the recurrence
   rule preserved through the save/round-trip, or re-derived? Are there code
   paths (reload, settle, completion, skip, dictation re-parse) that assemble
   a new `EKReminder` and could drop or rewrite `recurrenceRules`?

3. How is recurrence represented in the data model (`EKRecurrenceRule`,
   `recurrenceRules`), and where is it created, read, formatted, and
   displayed (`ReminderDisplay`, `ReminderRecurrenceFormatter`, card labels)?
   How do the completion, undo, skip, and delete flows interact with a
   repeating reminder — is there any next-occurrence generation or any logic
   that treats series reminders differently from one-off reminders?

4. Where — if anywhere — does behavior branch on a reminder having
   recurrence: UI visibility of actions (reschedule, delete, undo, skip),
   delete-as-series semantics in `EventKitStoring`, or store-level guards?

5. What do the existing unit and UI tests assert about reschedule and about
   recurrence (`RescheduleSheetTests`, `ReminderStoreTests`,
   `EventKitStoringTests`, `RescheduleSyncTests`, dictation recurrence tests,
   watch UI flows)? Which tests combine a repeating reminder with a
   reschedule, and how faithful is `InMemoryEventStore` at preserving
   `recurrenceRules` and due-date changes compared with the real EventKit
   store?

6. How does the watchOS reschedule request flow from
   `WatchReminderViewModel` through `SkippedReminderSyncService`
   (request/receive serialization) to the phone's `AppViewModel` and store —
   what reminder data is serialized across that relay, and could the relay
   reconstruct the reminder in a form that loses recurrence?