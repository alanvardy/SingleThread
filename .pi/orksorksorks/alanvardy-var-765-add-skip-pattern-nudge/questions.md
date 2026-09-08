# Research Questions

## Context

Focus on the SingleThread reminder app: the reminder cycle / skip mechanics in
`SingleThreadCore` (`ReminderStore.swift`, `ReminderSkip.swift`), persistence via
the App Group `UserDefaults` suite and launch-argument seams, user-facing
interaction idioms on the iOS and watchOS surfaces, cross-device sync, and the
unit/UI test infrastructure. The codebase has four surface targets (iOS app,
watchOS app, widget, macOS-ish entry points) plus a portable Core package.

## Questions

1. **Skip mechanics**: How does skipping a reminder work end-to-end across the
   iOS app, watchOS app, and widget intents — what code paths trigger it, what
   state does a skip produce (and in what shape), and how does the skip set
   interact with `visibleReminders`, refresh, and the generation/clear logic in
   `ReminderStore`?

2. **Per-reminder state persistence**: What patterns exist for persisting
   per-reminder state in the shared App Group `UserDefaults` suite — what keys
   are stored, what data shapes do the stores use (e.g. `SkippedReminderStore`),
   and how do launch-argument seams (`--seed`, `--ui-testing`) read, write, and
   reset persisted state?

3. **Prompt / multi-choice UI idioms**: What user-facing interaction idioms
   exist today for presenting a prompt with multiple actions to the user on the
   iOS and watchOS surfaces (dialogs, confirmation sheets, context menus, swipe
   actions, in-band prompt views), and how is user-facing copy localized?

4. **Existing reminder operations**: Which reminder operations already exist
   (delete, edit, complete, and anything that modifies due dates, recurrence, or
   splits a reminder into parts), where are they implemented, and how are delete
   flows surfaced in the iOS and watchOS UIs?

5. **Ordering, cycling, and time windows**: How is the "current" reminder
   determined and cycled — how does sorting (`ReminderSort`), the due-date
   window filtering (`ReminderDateFilter`), and the skip set combine in
   `visibleReminders`, and what happens to skipped reminders on pull-to-refresh
   or all-done states?

6. **Cross-device sync**: How is skip state synchronized between the phone and
   watch via WatchConnectivity — what is the sync contract (payload shape,
   latest-wins semantics), which hooks fire on skip-set changes, and how are
   sync pushes/receives tested?

7. **Testing infrastructure**: How are unit tests for store and skip logic
   structured (event-store and defaults injection, deterministic settle), how do
   UI tests drive deterministic reminder flows (seed JSON schema, launch args,
   accessibility identifiers, a11y audit), and which fixtures/helpers exist for
   skip-related flows in the unit, iOS UI, and watch UI test targets?