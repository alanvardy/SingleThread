## Q6: How is the app tested — unit coverage, UI-test scaffold, and pure vs coupled components

### Unit tests

All unit tests live in `SingleThreadTests/SingleThreadTests.swift` and use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest (`SingleThreadTests.swift:8-10`).

There is exactly one test target with **7 `@Test` methods**, and every one of them exercises the single pure function `dueStatus` — nothing else in the app is unit-tested:

- `completedReminderIsExcluded` — completed reminder returns `nil` (`SingleThreadTests.swift:15-23`)
- `missingDueDateIsExcluded` — `nil` due-date components return `nil` (`SingleThreadTests.swift:25-32`)
- `yesterdayEndOfDayIsOverdue` — day before at 23:59 → `.overdue` (`SingleThreadTests.swift:34-42`)
- `todayStartOfDayIsDueToday` — today 00:00 → `.dueToday` (`SingleThreadTests.swift:44-52`)
- `todayEndOfDayIsDueToday` — today 23:59 → `.dueToday` (`SingleThreadTests.swift:54-62`)
- `tomorrowStartOfDayIsExcluded` — tomorrow 00:00 → `nil` (`SingleThreadTests.swift:64-72`)
- `halfPastMidnightIsDueTodayNotOverdue` — timezone-sensitive check (GMT-8) that 00:30 today does not classify a 00:00-due item as overdue (`SingleThreadTests.swift:74-86`)

Shared fixtures: a GMT `Calendar` and a fixed "now" of 2026-08-12 12:00 UTC are defined as private static constants (`SingleThreadTests.swift:90-96`).

### UI-test scaffold

Two XCTest UI-test files, both unmodified boilerplate from the Xcode template (still use `XCTest`, not Swift Testing):

- `SingleThreadUITests/SingleThreadUITests.swift`:
  - `setUpWithError` only sets `continueAfterFailure = false` (`SingleThreadUITests.swift:12-20`)
  - `tearDownWithError` is empty (`SingleThreadUITests.swift:22-24`)
  - `testExample` launches `XCUIApplication()` but contains **no assertions** (`SingleThreadUITests.swift:26-35`)
  - `testLaunchPerformance` measures launch time with `XCTApplicationLaunchMetric()` (`SingleThreadUITests.swift:37-43`)
- `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift`:
  - `runsForEachTargetApplicationUIConfiguration = true` (`SingleThreadUITestsLaunchTests.swift:14-16`)
  - `testLaunch` launches the app and attaches a screenshot named "Launch Screen" with `.keepAlways` lifetime (`SingleThreadUITestsLaunchTests.swift:22-36`)

### Pure vs coupled components

- **Pure** (no EventKit/SwiftUI dependency): `SingleThread/ReminderFilter.swift` — only `import Foundation` (`ReminderFilter.swift:8`). It defines the `DueStatus` enum (`ReminderFilter.swift:10-13`) and the free function `dueStatus` (`ReminderFilter.swift:15-31`), both marked `nonisolated`. This is the only component covered by unit tests.
- **Coupled to EventKit**: `SingleThread/ReminderStore.swift` — `import EventKit` (`ReminderStore.swift:8`); holds `let eventStore = EKEventStore()` (`ReminderStore.swift:42`), stores `[EKReminder]` (`ReminderStore.swift:45`), maps `EKAuthorizationStatus` in `ReminderAccessStatus.init` (`ReminderStore.swift:23`), and uses `predicateForIncompleteReminders` / `fetchReminders` / `requestFullAccessToReminders` (`ReminderStore.swift:63`, `93`, `103`). It is not unit-tested.
- **Coupled to the view layer** (and EventKit): `SingleThread/ContentView.swift` — `import EventKit` + `import SwiftUI` (`ContentView.swift:8-9`); the `VisibleReminder` struct directly holds an `EKReminder` (`ContentView.swift:80-84`), and the `ReminderRow` view reads `reminder.title` and `dueDateComponents` (`ContentView.swift:91-92`). Not unit-tested.

### Commands run / validation

I only inspected the code with `read`/`nl`/`git status`; no code changes were made (this is a read-only research answer). `git status --porcelain` shows no staged changes (`no-staged-files: true`).