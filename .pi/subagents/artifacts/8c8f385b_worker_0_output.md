# Q3: Reminder presentation order, and any notion of "current"/"first"

## How order is determined

Ordering is a three-stage pipeline, and the final sort happens only in the view layer.

1. **Fetch (no explicit ordering).** `ReminderStore.load()` builds a predicate with `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` (`ReminderStore.swift:63-66`) and assigns the result of `fetchReminders(matching:)` to `reminders` (`ReminderStore.swift:67`). `fetchReminders` just bridges the completion handler into an async array and returns `reminders ?? []` (`ReminderStore.swift:90-99`). No sort is applied here — the array is in whatever order EventKit returns.

2. **Filter + map + sort in the view.** `ContentView.visibleReminders` (`ContentView.swift:35-51`) transforms `reminderStore.reminders`:
   - `compactMap` drops reminders that `dueStatus(...)` returns nil for — i.e. completed reminders, reminders with no due date, and reminders that are neither overdue nor due today (`ContentView.swift:40-46`; classifier at `ReminderFilter.swift:20-30`).
   - Each survivor becomes a `VisibleReminder` with a computed `dueDate`, derived from `dueDateComponents` via `calendar.date(from:)` and defaulting to `.distantFuture` when that fails (`ContentView.swift:47-48`).
   - The array is then sorted **ascending by `dueDate`**: `.sorted { $0.dueDate < $1.dueDate }` (`ContentView.swift:50`). So the earliest due date is first.

3. **Rendered in array order.** The `List`/`ForEach` iterates `visibleReminders` directly (`ContentView.swift:67-70`), and `ForEach` preserves array order, so the earliest-due reminder appears at the top. `ReminderRow` renders each one as title + formatted due date (`ContentView.swift:86-96`).

## Notion of "current" or "first"

There is **no** notion of a "current" or "first" reminder anywhere in the codebase:

- `ReminderStore` holds only `accessStatus` and `reminders: [EKReminder]` (`ReminderStore.swift:44-45`). No `currentReminder`, selection, or index state.
- `VisibleReminder` is a plain value struct of `reminder`, `status`, `dueDate` (`ContentView.swift:80-84`) with no `isFirst`/`isCurrent` flag.
- `ReminderRow` is a passive display view with no selection callback or state (`ContentView.swift:86-96`).
- On macOS, `NavigationViewWrapper` wraps content in a `NavigationSplitView` whose detail pane is a static `Text("Select a reminder")` (`ContentView.swift:104-107`). Despite the placeholder text, there is **no** `@State` selection binding, no `List(selection:)`, and no `NavigationLink` — so no actual selection or first-reminder concept exists.
- On iOS, content is a plain `List` with no selection behavior at all (`ContentView.swift:109-111`).

A grep for `selection|current|first` across `SingleThread/` returns no matches other than the `.sorted`/`ForEach` hits — confirming none of these concepts exist in code.

## Acceptance Report