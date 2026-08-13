## Q5: UI layout across iOS and macOS

### Entry point and scene wrapper
- `SingleThreadApp` uses a `WindowGroup { ContentView() }` at `SingleThreadApp.swift:15-17`, with the store injected via `.environment(reminderStore)` at `SingleThreadApp.swift:18`. This is a single scene for both platforms; there is no platform-conditional scene.

### Top-level navigation wrapper
- `ContentView.body` wraps its content in `NavigationViewWrapper` at `ContentView.swift:14-17`.
- `NavigationViewWrapper<Content: View>` is a private generic wrapper at `ContentView.swift:99-113`. It is platform-conditional:
  - On **macOS**: `NavigationSplitView { content() } detail: { Text("Select a reminder") }` at `ContentView.swift:103-108` — a two-column split view with a static "Select a reminder" detail placeholder.
  - On **iOS (and other non-macOS platforms)**: the content is returned directly with no navigation container at `ContentView.swift:109-111`.

### The list / state switch
- `reminderList` is a `@ViewBuilder` computed property at `ContentView.swift:53-77` that switches on `reminderStore.accessStatus`:
  - `.notDetermined` → `ProgressView("Loading reminders…")` at `ContentView.swift:56-57`.
  - `.denied` → `ContentUnavailableView("Reminders access denied", systemImage: "bell.slash", description: ...)` at `ContentView.swift:58-62`.
  - `.authorized` → either an empty state or the list:
    - Empty state: `ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")` at `ContentView.swift:64-65`.
    - Non-empty: a `List` with `ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier)` rendering `ReminderRow` at `ContentView.swift:67-70`.
- On macOS only, the `List` gets `.navigationSplitViewColumnWidth(min: 180, ideal: 200)` at `ContentView.swift:72-74`, inside a `#if os(macOS)` block.

### Row layout
- `ReminderRow` is a private `View` at `ContentView.swift:86-97`. It is a `VStack(alignment: .leading)` containing:
  - A title `Text(visible.reminder.title ?? "Untitled")` at `ContentView.swift:90-91`.
  - A due-date `Text` with `Date.FormatStyle(date: .numeric, time: .standard)` and `.font(.caption)` at `ContentView.swift:92-93`.
  - Row-level `.foregroundStyle(visible.status == .overdue ? Color.red : Color.primary)` at `ContentView.swift:95`.

### Layout primitives for centering / placing controls
- **Centering**: There is no explicit `Spacer()`, `.frame(maxWidth:)`, `ZStack`, or `.padding()` anywhere in the view layer. The only centering/placement primitives in use are the system-provided containers:
  - `ProgressView` (a centered spinner + label) at `ContentView.swift:57`.
  - `ContentUnavailableView` (system-standard empty-state layout, centered) at `ContentView.swift:59` and `ContentView.swift:65`.
  - `List` / `NavigationSplitView` (system-managed layout).
- **Alignment primitive**: `VStack(alignment: .leading)` at `ContentView.swift:90` is the only explicit alignment modifier.
- No `.safeAreaInset`, `.overlay`, `.toolbar`, `.buttonStyle`, or custom spacing/positioning modifiers exist in the current code.

### Preview
- A single `#Preview` for `ContentView` injects a fresh `ReminderStore()` via `.environment` at `ContentView.swift:115-118`; it is not platform-conditional.

### Key facts summary
- iOS: bare content (list or state view) with no navigation wrapper — `ContentView.swift:109-111`.
- macOS: two-column `NavigationSplitView` with static detail + min/ideal column width — `ContentView.swift:103-108`, `ContentView.swift:72-74`.
- Empty/loading/denied states use `ProgressView` and `ContentUnavailableView` — `ContentView.swift:56-65`.
- No custom centering/layout scaffolding beyond system containers and one `VStack(alignment: .leading)`.