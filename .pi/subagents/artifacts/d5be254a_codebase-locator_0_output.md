# Codebase Map: SingleThread (EventKit Reminders app)

## Project structure
- Root: `/Users/vardy/dev/alanvardy-var-553-show-one-issue`
- App sources: `SingleThread/` — only 4 Swift files: `SingleThreadApp.swift`, `ContentView.swift`, `ReminderStore.swift`, `ReminderFilter.swift`
- Tests: `SingleThreadTests/SingleThreadTests.swift` (Swift Testing), `SingleThreadUITests/` (XCTest, boilerplate only)
- Config: `.swiftlint.yml`, `.swiftformat`, `Makefile`, `scripts/test.sh`, `.github/workflows/ci.yml`
- `SingleThread.xcodeproj/project.pbxproj` uses `objectVersion = 77` (synchronized file groups — no pbxproj edits needed for new `.swift` files)

## 1. Fetch / filter / sort / render

### ReminderStore.swift
- `@MainActor @Observable final class ReminderStore` — lines 34-35
- `let eventStore = EKEventStore()` — line 39
- `private(set) var accessStatus` — line 44; `private(set) var reminders: [EKReminder]` — line 45
- `func load() async` — lines 47-67:
  - Requests full access only if `.notDetermined` (lines 48-58), guards against concurrent requests via `isRequestingAccess`
  - Sets `accessStatus` from `EKEventStore.authorizationStatus(for: .reminder)` (line 59)
  - `eventStore.reset()` (line 61) — mitigates empty-results-after-first-grant issue
  - `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` (lines 62-65) — fetches **all incomplete** reminders (no date range filter at EventKit level)
  - `fetchReminders(matching:)` (lines 90-99) bridges the completion-handler API to async via `withCheckedContinuation`
- `ReminderAccessStatus` enum (lines 16-33) maps `EKAuthorizationStatus` → `.notDetermined / .denied / .authorized`; `@unknown default` → `.denied`

### ReminderFilter.swift
- `nonisolated enum DueStatus { case overdue, case dueToday }` — lines 8-11
- `nonisolated func dueStatus(dueDateComponents:isCompleted:now:calendar:) -> DueStatus?` — lines 13-28
  - Returns `nil` (exclude) if `isCompleted`, no due date, or due date is in the future
  - `.overdue` if `dueDate < calendar.startOfDay(for: now)`
  - `.dueToday` if same day as `startOfDay`
  - Pure, testable, day-level granularity

### ContentView.swift
- `@Environment(ReminderStore.self) private var reminderStore` — line 27
- `@Environment(\.scenePhase) private var scenePhase` — line 28
- `.task { await reminderStore.load() }` — lines 15-17
- `.onChange(of: scenePhase)` → reload on `.active` — lines 18-24
- `visibleReminders: [VisibleReminder]` computed property — lines 30-48:
  - `compactMap` calls `dueStatus(...)`, builds `VisibleReminder(reminder:status:dueDate:)`, `dueDate` defaults to `.distantFuture` if nil
  - `.sorted { $0.dueDate < $1.dueDate }` ascending — line 47
- `reminderList` `@ViewBuilder` switch on `accessStatus` — lines 51-72:
  - `.notDetermined` → `ProgressView("Loading reminders…")`
  - `.denied` → `ContentUnavailableView("Reminders access denied", systemImage: "bell.slash", ...)`
  - `.authorized` + empty → `ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")`
  - `.authorized` + non-empty → `List { ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier) { ReminderRow(visible:) } }` (lines 60-63)
  - macOS column width via `#if os(macOS) .navigationSplitViewColumnWidth(min: 180, ideal: 200)` — lines 64-66
- `VisibleReminder` private struct — lines 78-82
- `ReminderRow` — lines 84-95: `VStack` with title (`?? "Untitled"`) + formatted due date; `.foregroundStyle(overdue ? .red : .primary)`
- `NavigationViewWrapper` — lines 97-109: macOS uses `NavigationSplitView { content } detail: { Text("Select a reminder") }`; iOS is just the content (no navigation container)

## 2. Marking complete via EventKit — **none exists**
- Grep across the repo confirms **no** `isCompleted = true`, `eventStore.save`, `commit`, `remove`, or EKReminder mutation code anywhere in app sources
- Only `isCompleted` **reads**: `ContentView.swift:42` (passed to `dueStatus`) and `ReminderFilter.swift:20` (`guard !isCompleted`)
- `ReminderStore` exposes `eventStore` (internal `let`, line 39) and `reminders` (`private(set)`, line 45) but has **no save/complete method**
- To mark complete, new code would need `reminder.isCompleted = true` + `try eventStore.save(reminder, commit: true)` (or `eventStore.remove(reminder, commit:)` for delete) — none present. The prior design doc (`.pi/qrspi/alanvardy-var-551-display-reminders/design.md:123,129`) explicitly scoped this as "display only: no create/complete/edit/delete".

## 3. UI state / navigation / selection
- **No single-item selection state** — `List`/`ForEach` have no `selection:` binding; no `NavigationLink`; no `@State` for a selected/current item
- **No animations** — no `withAnimation`, `.animation`, or transitions anywhere
- **No "current item" state** — only environment state is `reminderStore` (Observable) and `scenePhase`
- macOS detail pane is a **static** placeholder `Text("Select a reminder")` (ContentView.swift:104); iOS has no navigation wrapper at all
- Rendering state is derived purely from `reminderStore.reminders` + computed `visibleReminders`; no explicit user-driven UI state

## 4. Testing & conventions

### Unit tests — Swift Testing
- `SingleThreadTests/SingleThreadTests.swift` uses `import Testing`, `@Test`, `#expect`, `#require` (NOT XCTest)
- 8 tests (lines 15-91) cover only the pure `dueStatus` classifier: completed → nil; nil due date → nil; yesterday 23:59 → overdue; today 00:00 / 23:59 → dueToday; tomorrow → nil; timezone-aware half-past-midnight case
- Fixed calendar: Gregorian, UTC (lines 95-100); fixed `now` = 2026-08-12 12:00 UTC (line 102)
- Run via `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`

### UI tests — XCTest (boilerplate)
- `SingleThreadUITests/SingleThreadUITests.swift`: `testExample` (launch only) + `testLaunchPerformance` — no real assertions
- `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift`: launch + screenshot attachment

### .swiftlint.yml
- Included: `SingleThread`, `SingleThreadTests`, `SingleThreadUITests`
- Disabled (Swift Testing migration): `single_test_class`, `balanced_xctest_lifecycle`, `empty_xctest_method`, `final_test_case`, `multiple_closures_with_trailing_closure`, `type_name`
- Thresholds: `line_length` 120/150, `cyclomatic_complexity` 12/15, `type_body_length` 500/600, `file_length` 650/800
- `force_cast`/`force_try` warning-level; opt-in rules include `sorted_imports`, `trailing_closure`, `vertical_parameter_alignment_on_call`, `implicit_return`, `first_where`, etc.
- `identifier_name` exclusions: `id`, `e`, `d`, `rt`, `to`, `gvm` (min length 3 otherwise)

### .swiftformat
- `--swiftversion 6.0`; indent 4; `wraparguments before-first`; `wrapcollections before-first`; `closingparen same-line`
- Enables `blankLinesAroundMark`, `organizeDeclarations`, `preferSwiftTesting`
- Disables `andOperator`, `isEmpty`, `trailingClosures`, `trailingCommas`, `wrapMultilineStatementBraces`
- `--exclude SingleThreadUITests`

### Build settings (project.pbxproj)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (lines 425/470) — all async defaults to `@MainActor`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_VERSION = 6.0`
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (visionOS removed)
- Deployment targets: iOS + macOS both `26.5`
- `GENERATE_INFOPLIST_FILE = YES`; `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` set (line 402)
- `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = SingleThread/SingleThread.entitlements` — macOS only; entitlements file contains `com.apple.security.personal-information.calendars = true` (app-sandbox Calendar access)

## Notes / residual risks
- **AGENTS.md is stale** — its "Concurrency Model", "SwiftData", and "Project Layout" sections still describe the old SwiftData/`Item` app. The app has since been migrated to EventKit (`Item.swift` no longer exists; no `@Query`/`modelContext`/SwiftData in app sources). Treat AGENTS.md's SwiftData guidance as obsolete, but its build/lint/test and lint/format conventions are accurate and current.
- No `NSRemindersUsageDescription`-related issues: usage description key is present in pbxproj via `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`.