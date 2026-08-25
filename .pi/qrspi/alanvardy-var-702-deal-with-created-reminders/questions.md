# Research Questions

## Context
Focus on the test targets (`SingleThreadTests`, `SingleThreadUITests`, `SingleThreadWatchUITests`), the EventKit abstraction in the `SingleThreadCore` package (`ReminderStore`, `EventKitStoring`, `InMemoryEventStore`), and the CI workflow configuration.

## Questions
1. Which unit and UI test suites instantiate a real `EKEventStore` or `EKReminder`, which of their code paths call `save`/`addReminder`, and under what authorization conditions could those writes land in an actual Reminders database?
2. How is the `EventKitStoring` protocol designed, what does `InMemoryEventStore` implement versus omit, and where do tests fall back to the real `EKEventStore` because the in-memory fake doesn't cover a path?
3. What teardown/cleanup patterns exist across the test targets today, and how do the CI matrix jobs (iPhone/iPad simulators, parallel suites) isolate or share simulator state such as Reminders data, App Group defaults, and keychain?
4. How does `ReminderStore.addReminder` construct and persist an `EKReminder` — which fields are set (title, notes, calendar, due date) — and what APIs exist for fetching/removing reminders by title or creation date?
5. How do the `--seed` and `--ui-testing` launch-argument seams wire up `InMemoryEventStore` in the iOS app, and could equivalent seams apply to watch/widget entry points or to unit-test initialization of `ReminderStore`?
