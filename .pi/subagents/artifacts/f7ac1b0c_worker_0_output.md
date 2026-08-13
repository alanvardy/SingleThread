## Q2: EventKit APIs for reading reminders and mutation capabilities

### Reading APIs (all present)

The app reads reminders exclusively through an `EKEventStore` instance held by `ReminderStore`:

- `let eventStore = EKEventStore()` — the single EventKit store instance, `ReminderStore.swift:42`
- `EKEventStore.authorizationStatus(for: .reminder)` — checked twice during `load()`: to detect `.notDetermined` before prompting (`ReminderStore.swift:48`) and to set the app's `accessStatus` after any prompt (`ReminderStore.swift:57`)
- `EKAuthorizationStatus` — mapped to the app's `ReminderAccessStatus` enum in `ReminderAccessStatus.init(_:)` (`ReminderStore.swift:23-35`); `.denied`, `.restricted`, `.writeOnly` collapse to `.denied`, and `.authorized`, `.fullAccess` collapse to `.authorized`
- `eventStore.requestFullAccessToReminders { granted, _ in ... }` — prompts for read/write access, wrapped in a continuation (`ReminderStore.swift:103-107`)
- `eventStore.reset()` — clears cached store state before fetching (`ReminderStore.swift:62`)
- `eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` — builds the fetch predicate for incomplete reminders with no due-date range and no calendar filter (`ReminderStore.swift:63-66`)
- `eventStore.fetchReminders(matching: predicate) { reminders in ... }` — the callback-based fetch API, wrapped in `withCheckedContinuation` and stored into a `nonisolated(unsafe)` captured var (`ReminderStore.swift:90-98`)

The fetched `[EKReminder]` is stored in `private(set) var reminders` (`ReminderStore.swift:45`). The view layer then reads `EKReminder` properties directly:
- `reminder.dueDateComponents` (`ContentView.swift:41`, `ContentView.swift:47`)
- `reminder.isCompleted` (`ContentView.swift:42`)
- `reminder.calendarItemIdentifier` used as the `ForEach` id (`ContentView.swift:68`)
- `reminder.title` (`ContentView.swift:91`)
- `EKReminder` type is also referenced in the `VisibleReminder` struct (`ContentView.swift:81`)

### Mutation capabilities (none exist)

There is **no** code path that mutates a reminder and saves it back to the store:

- No call to `EKEventStore.save(_:commit:)`, `remove(_:commit:)`, or `commit()` anywhere in the codebase (grep for `save|commit|remove|complete` returned only the read paths listed above).
- `isCompleted` is only ever **read** and passed into the classifier (`ReminderFilter.swift:17,20`; `ContentView.swift:42`); it is never assigned (`isCompleted = ...` appears nowhere).
- `reminders` is `private(set)` (`ReminderStore.swift:45`), so no external type can write to the array.
- `ReminderStore` exposes only `eventStore`, `accessStatus`, `reminders`, and `load()`; there is no public method such as `markComplete(_:)`, `toggleCompleted`, or `update`.

The one place a write *could* be introduced is that `requestFullAccessToReminders` requests full (read+write) access (`ReminderStore.swift:103`), but the codebase currently performs no write operation through that permission.