# Research Findings

Sources inspected: `SingleThread/SingleThreadApp.swift`, `SingleThread/ContentView.swift`,
`SingleThread/ReminderStore.swift`, `SingleThread/ReminderFilter.swift`,
`SingleThreadTests/SingleThreadTests.swift`, `SingleThreadUITests/*.swift`,
`SingleThread.xcodeproj/project.pbxproj`.

## Q1: Trace the flow of reminder data from EventKit to the screen

### Findings
- **Store ownership/injection**: `SingleThreadApp` creates the store as `@State private var reminderStore = ReminderStore()` (`SingleThreadApp.swift:23`) and injects it into the environment at the `WindowGroup` via `.environment(reminderStore)` (`SingleThreadApp.swift:15-18`).
- **Fetch trigger 1**: `ContentView.body` calls `await reminderStore.load()` in `.task { }` on first appearance (`ContentView.swift:18-20`).
- **Fetch trigger 2**: `.onChange(of: scenePhase)` re-calls `reminderStore.load()` when the scene becomes `.active` (`ContentView.swift:21-27`).
- **Load steps** (`ReminderStore.load()`, `ReminderStore.swift:47-68`):
  1. If authorization is `.notDetermined`, waits for app active via `waitUntilActive()`, guards re-entrancy with `isRequestingAccess`, then requests full access (`ReminderStore.swift:48-56`).
  2. Maps `EKAuthorizationStatus` → app enum `ReminderAccessStatus` (`ReminderStore.swift:57`, mapping at `ReminderStore.swift:23-34`).
  3. If not authorized, clears `reminders` and returns (`ReminderStore.swift:58-61`).
  4. `eventStore.reset()` (`ReminderStore.swift:62`), builds predicate via `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` (`ReminderStore.swift:63-66`).
  5. Assigns fetch result to `reminders` (`ReminderStore.swift:67`).
- **Async bridge**: `fetchReminders(matching:)` wraps the callback-based `eventStore.fetchReminders(matching:completion:)` in `withCheckedContinuation`, coalescing nil to `[]` via `nonisolated(unsafe)` captured var (`ReminderStore.swift:90-99`).
- **Filter** (`ContentView.visibleReminders`, `ContentView.swift:35-51`): `compactMap` over `reminderStore.reminders`, dropping items where pure `dueStatus(...)` returns nil; builds a `VisibleReminder` with a resolved `dueDate` (`ContentView.swift:38-49`).
- **Sort**: `.sorted { $0.dueDate < $1.dueDate }` ascending (`ContentView.swift:50`).
- **Render** (`ContentView.reminderList`, `ContentView.swift:53-77`): `switch` on `accessStatus` → `ProgressView` / `ContentUnavailableView` (denied) / empty `ContentUnavailableView` / `List` + `ForEach` of `ReminderRow` (`ContentView.swift:55-75`).
- **Row render** (`ReminderRow`, `ContentView.swift:86-97`): `VStack` with title and formatted due date; red foreground when `.overdue` (`ContentView.swift:90-95`).

## Q2: EventKit APIs used for reading; mutation capabilities

### Findings
- **Read APIs (all via `ReminderStore`)**:
  - `let eventStore = EKEventStore()` (`ReminderStore.swift:42`).
  - `EKEventStore.authorizationStatus(for: .reminder)` — twice in `load()` (`ReminderStore.swift:48`, `ReminderStore.swift:57`).
  - `eventStore.requestFullAccessToReminders { granted, _ in }` (`ReminderStore.swift:101-107`).
  - `eventStore.reset()` (`ReminderStore.swift:62`).
  - `eventStore.predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (`ReminderStore.swift:63-66`).
  - `eventStore.fetchReminders(matching:completion:)` (`ReminderStore.swift:93`).
- **EKReminder properties read by the view layer**: `dueDateComponents` (`ContentView.swift:41,47`), `isCompleted` (`ContentView.swift:42`), `calendarItemIdentifier` as `ForEach` id (`ContentView.swift:68`), `title` (`ContentView.swift:91`).
- **Mutation: none exists.** No calls to `EKEventStore.save(_:commit:)`, `remove(_:commit:)`, or `commit()` anywhere. `isCompleted` is only ever read and passed into the classifier (`ReminderFilter.swift:20`; `ContentView.swift:42`), never assigned. `reminders` is `private(set)` (`ReminderStore.swift:45`) and `ReminderStore` exposes no write method (only `eventStore`, `accessStatus`, `reminders`, `load()`).
- **Note**: full (read+write) access is *requested* (`requestFullAccessToReminders`, `ReminderStore.swift:103`), so write capability is granted at the permission level, but no write path is implemented.

## Q3: Ordering of presented reminders; notion of "current"/"first"

### Findings
- **No ordering at fetch**: the predicate passes nil date range and calendars (`ReminderStore.swift:63-66`); `fetchReminders` returns `reminders ?? []` in whatever order EventKit supplies (`ReminderStore.swift:90-99`).
- **Filter/map in view**: `visibleReminders` drops completed/no-due-date/future reminders, resolves each `dueDate` (default `.distantFuture` on failure) (`ContentView.swift:38-49`).
- **Explicit sort in view**: `.sorted { $0.dueDate < $1.dueDate }` — earliest due date first (`ContentView.swift:50`). `List`/`ForEach` preserves this order (`ContentView.swift:67-70`).
- **No "current"/"first" concept**: `ReminderStore` holds only `accessStatus` and `reminders` (`ReminderStore.swift:44-45`); `VisibleReminder` is a plain value struct (`ContentView.swift:80-84`); `ReminderRow` has no selection callback or state (`ContentView.swift:86-97`). macOS `NavigationSplitView` detail is a static `Text("Select a reminder")` with no `List(selection:)` or `NavigationLink` (`ContentView.swift:104-108`); iOS renders the bare list with no selection behavior (`ContentView.swift:109-111`).

## Q4: SwiftUI state and observation

### Findings
- **Observed object**: `ReminderStore` is `@MainActor @Observable final class` using the Observation framework (`import Observation`, `ReminderStore.swift:9,37-39`), not `ObservableObject`/`@Published`.
- **Observable state**: `private(set) var accessStatus` and `private(set) var reminders: [EKReminder]` (`ReminderStore.swift:44-45`). `eventStore` is a non-tracked `let` (`ReminderStore.swift:42`).
- **Injection**: owned at app root via `@State` (`SingleThreadApp.swift:23`), injected with `.environment(reminderStore)` (`SingleThreadApp.swift:18`), read with `@Environment(ReminderStore.self)` (`ContentView.swift:32`). Preview injects a fresh instance (`ContentView.swift:115-118`).
- **Re-render triggers**: Observation tracks property reads during body evaluation — `reminderStore.accessStatus` in the `switch` (`ContentView.swift:55`) and `reminderStore.reminders` in `visibleReminders` (`ContentView.swift:38`). Mutations in `load()` (`ReminderStore.swift:57,59,67`) invalidate dependent views.
- **Derived data**: `visibleReminders` is a computed property recomputed each render, not stored state (`ContentView.swift:35-51`).
- **Lifecycle-driven mutations**: `.task` (`ContentView.swift:18-20`) and `.onChange(of: scenePhase)` (`ContentView.swift:21-27`).
- **Concurrency context**: `@MainActor` on the store (`ReminderStore.swift:37`) plus project-level `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`project.pbxproj:425,470`); `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_VERSION = 6.0` (`project.pbxproj:424-428,469-473`).

## Q5: UI layout across iOS and macOS

### Findings
- **Scene**: single `WindowGroup { ContentView() }` for both platforms (`SingleThreadApp.swift:15-17`); no platform-conditional scene.
- **Navigation wrapper**: `ContentView.body` wraps content in `NavigationViewWrapper` (`ContentView.swift:14-17`), a private generic view (`ContentView.swift:99-113`):
  - macOS: `NavigationSplitView { content() } detail: { Text("Select a reminder") }` (`ContentView.swift:103-108`).
  - iOS/other: returns `content()` directly with no navigation container (`ContentView.swift:109-111`).
- **State switch** (`reminderList`, `ContentView.swift:53-77`):
  - `.notDetermined` → `ProgressView("Loading reminders…")` (`ContentView.swift:56-57`).
  - `.denied` → `ContentUnavailableView` (`ContentView.swift:58-62`).
  - `.authorized` empty → `ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")` (`ContentView.swift:64-65`).
  - `.authorized` non-empty → `List` + `ForEach(..., id: \.reminder.calendarItemIdentifier)` (`ContentView.swift:67-70`).
- **macOS-only column width**: `.navigationSplitViewColumnWidth(min: 180, ideal: 200)` under `#if os(macOS)` (`ContentView.swift:72-74`).
- **Centering/placement primitives**: no explicit `Spacer`, `ZStack`, `.frame`, `.padding`, `.overlay`, or `.toolbar`. Centering relies on system containers (`ProgressView`, `ContentUnavailableView`, `List`, `NavigationSplitView`). Only explicit alignment is `VStack(alignment: .leading)` in `ReminderRow` (`ContentView.swift:90`).

## Q6: Testing — unit coverage, UI-test scaffold, pure vs coupled

### Findings
- **Unit tests** (`SingleThreadTests/SingleThreadTests.swift`): Swift Testing (`import Testing`, `@Test`, `#expect`) (`SingleThreadTests.swift:8-10`). Seven `@Test` methods, all targeting the single pure function `dueStatus` (`SingleThreadTests.swift:15-86`):
  - completed reminder excluded (`:15-23`); nil due date excluded (`:25-32`); yesterday 23:59 overdue (`:34-42`); today 00:00 due-today (`:44-52`); today 23:59 due-today (`:54-62`); tomorrow 00:00 excluded (`:64-72`); timezone-sensitive 00:30-not-overdue (`:74-86`).
  - Fixtures: GMT calendar and fixed "now" of 2026-08-12 12:00 UTC (`SingleThreadTests.swift:90-96`).
- **UI-test scaffold** (XCTest, boilerplate):
  - `SingleThreadUITests.swift`: `testExample` launches `XCUIApplication()` with no assertions (`:26-35`); `testLaunchPerformance` measures launch (`:37-43`).
  - `SingleThreadUITestsLaunchTests.swift`: `testLaunch` launches and attaches a "Launch Screen" screenshot (`:22-36`).
- **Pure vs coupled**:
  - Pure: `ReminderFilter.swift` (`import Foundation` only, `ReminderFilter.swift:8`); `DueStatus` enum (`:10-13`) and `dueStatus` free function (`:15-31`) both `nonisolated`. Only unit-tested component.
  - Coupled to EventKit: `ReminderStore.swift` (`import EventKit`, `:8`; holds `EKEventStore` `:42`, `[EKReminder]` `:45`, maps `EKAuthorizationStatus` `:23`). Not unit-tested.
  - Coupled to EventKit + view layer: `ContentView.swift` (`import EventKit`/`SwiftUI`, `:8-9`); `VisibleReminder` holds an `EKReminder` directly (`:80-84`). Not unit-tested.

## Cross-Cutting Observations
- The data path is a three-layer chain: `ReminderStore` (EventKit fetch, `ReminderStore.swift:47-68`) → `ContentView.visibleReminders` (pure-classifier filter + sort, `ContentView.swift:35-51`) → `ReminderRow` (render, `ContentView.swift:86-97`). The pure classifier `dueStatus` sits between store and view and is the sole tested logic.
- Only overdue and due-today *incomplete* reminders are shown; completed, undated, and future reminders are silently dropped (`ReminderFilter.swift:20-30`, `ContentView.swift:40-46`).
- The store is the only observable object; the view derives its display list at render time rather than caching filtered results (`ContentView.swift:35-51`).
- Platform differences are isolated to `NavigationViewWrapper` (`ContentView.swift:99-113`) and the macOS column-width modifier (`ContentView.swift:72-74`).
- The app requests full (read+write) Reminders access (`ReminderStore.swift:103`) but currently performs only reads — the write permission is unused.

## Open Areas
- Whether EventKit's fetch callback ordering is deterministic is not addressed in code; the array is only re-sorted in the view (`ContentView.swift:50`).
- No handling for reminders due after today (intentionally excluded by `dueStatus`, `ReminderFilter.swift:30`) — no "upcoming" section exists.
- The macOS "Select a reminder" detail pane is a static placeholder; no selection plumbing exists, so it cannot currently reflect a chosen reminder (`ContentView.swift:104-108`).
