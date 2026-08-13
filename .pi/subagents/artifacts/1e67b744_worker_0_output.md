## Q1: Trace of reminder data flow from EventKit to screen

The full path is: `SingleThreadApp` creates the store and injects it → `ContentView` triggers a load → `ReminderStore.load()` requests access and fetches incomplete reminders from `EKEventStore` → `ContentView.visibleReminders` filters and sorts them → `reminderList` renders them.

### Step 1 — Store creation and injection
- `SingleThreadApp` owns the store as `@State private var reminderStore = ReminderStore()` (`SingleThreadApp.swift:15`) and injects it into the environment with `.environment(reminderStore)` on the `WindowGroup` (`SingleThreadApp.swift:12-16`).
- `ReminderStore` holds the `EKEventStore` as `let eventStore = EKEventStore()` and the published state `private(set) var reminders: [EKReminder] = []` plus `accessStatus` (`ReminderStore.swift:40-43`). The class is `@MainActor @Observable` (`ReminderStore.swift:38-39`).

### Step 2 — Load trigger
- `ContentView.body` attaches `.task { await reminderStore.load() }` (`ContentView.swift:18-20`), so the first load runs when the view appears.
- A second trigger `.onChange(of: scenePhase)` calls `reminderStore.load()` again whenever the scene becomes `.active` (`ContentView.swift:21-27`).

### Step 3 — Authorization + fetch (`ReminderStore.load()`, `ReminderStore.swift:45-64`)
- If `EKEventStore.authorizationStatus(for: .reminder) == .notDetermined`, it waits for the app to be active (`waitUntilActive`), guards against re-entrancy via `isRequestingAccess`, then calls `requestFullAccess()` (`ReminderStore.swift:46-53`).
- It maps the raw `EKAuthorizationStatus` into the app's `ReminderAccessStatus` enum and stores it (`ReminderStore.swift:54`; mapping at `ReminderStore.swift:20-32`).
- If not `.authorized`, it clears `reminders` and returns (`ReminderStore.swift:55-58`).
- It calls `eventStore.reset()` (`ReminderStore.swift:59`), then builds the predicate with `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` (`ReminderStore.swift:60-63`).
- It assigns the fetch result directly to `reminders` (`ReminderStore.swift:64`).
- The actual read is `fetchReminders(matching:)`, which wraps the callback-based `eventStore.fetchReminders(matching:completion:)` in `withCheckedContinuation` and coalesces the optional array to `[]` (`ReminderStore.swift:66-82`).

### Step 4 — Filtering and sorting (`ContentView.visibleReminders`, `ContentView.swift:33-46`)
- Computes `now = Date()` and `calendar = Calendar.current` (`ContentView.swift:34-35`).
- `compactMap` over `reminderStore.reminders`; for each, it calls the pure `dueStatus(dueDateComponents:isCompleted:now:calendar:)` helper and drops the reminder if it returns `nil` (`ContentView.swift:36-43`).
- `dueStatus` returns `nil` when the reminder is completed, has no due date, or is due after today; otherwise `.overdue` (before start of today) or `.dueToday` (same day as today) (`ReminderFilter.swift:12-26`).
- The due date is materialized via `reminder.dueDateComponents.flatMap { calendar.date(from: $0) } ?? .distantFuture` (`ContentView.swift:41`).
- Each surviving item becomes a `VisibleReminder(reminder:status:dueDate:)` (`ContentView.swift:42`, struct at `ContentView.swift:74-78`).
- The result is sorted ascending by `dueDate` with `.sorted { $0.dueDate < $1.dueDate }` (`ContentView.swift:45`).

### Step 5 — Rendering (`ContentView.reminderList`, `ContentView.swift:48-72`)
- Switches on `reminderStore.accessStatus`:
  - `.notDetermined` → `ProgressView("Loading reminders…")` (`ContentView.swift:51-52`).
  - `.denied` → `ContentUnavailableView` prompting Settings (`ContentView.swift:53-57`).
  - `.authorized` → if `visibleReminders.isEmpty`, a `ContentUnavailableView("No overdue or due-today reminders", ...)`; otherwise a `List` (`ContentView.swift:58-71`).
- The `List` uses `ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier)` rendering one `ReminderRow` per item (`ContentView.swift:62-64`). On macOS a `navigationSplitViewColumnWidth` is applied (`ContentView.swift:66-68`).

### Step 6 — Row rendering (`ReminderRow`, `ContentView.swift:80-91`)
- Each row is a `VStack(alignment: .leading)` showing the reminder title (falling back to `"Untitled"`) and the due date formatted with `Date.FormatStyle(date: .numeric, time: .standard)` in `.caption` font (`ContentView.swift:82-88`).
- Foreground color is `Color.red` when `status == .overdue`, else `Color.primary` (`ContentView.swift:90`).

### Step 7 — Platform navigation wrapper (`NavigationViewWrapper`, `ContentView.swift:94-104`)
- `ContentView.body` wraps `reminderList` in `NavigationViewWrapper` (`ContentView.swift:14-16`).
- On macOS this renders a `NavigationSplitView` with a static `"Select a reminder"` detail; on iOS it renders the content directly without a navigation container (`ContentView.swift:97-103`).