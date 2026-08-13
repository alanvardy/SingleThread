# Implementation Plan

## Overview

Replace the SwiftData/`Item` list with a live EventKit fetch: a `@MainActor @Observable` `ReminderStore` requests full Reminders access and fetches incomplete reminders, a pure classifier narrows them to overdue-or-today, and `ContentView` renders the sorted list. iOS + macOS only — visionOS is removed as a build target.

> **Two implementation notes resolved during planning** (verified by compiling against the actual SDKs):
> 1. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, but the test target does **not**. The pure classifier (`dueStatus` and `DueStatus`) must be declared `nonisolated` or the tests cannot call it synchronously.
> 2. `EKEventStore.fetchReminders(matching:)` has **no async variant** (the ObjC method returns `id`, so the importer only generates the completion-handler form). `ReminderStore` must bridge it with `withCheckedContinuation`. Also `authorizationStatus(for:)` is a **class** method: `EKEventStore.authorizationStatus(for: .reminder)`.

---

## Phase 1: Due-status classifier (pure, unit-tested)

### Changes

#### 1. Classifier — pure function + enum
**File**: `SingleThread/ReminderFilter.swift`
**Action**: create

```swift
import Foundation

nonisolated enum DueStatus {
    case overdue
    case dueToday
}

nonisolated func dueStatus(
    dueDateComponents: DateComponents?,
    isCompleted: Bool,
    now: Date,
    calendar: Calendar) -> DueStatus? {
    guard !isCompleted, let dueDateComponents, let dueDate = calendar.date(from: dueDateComponents) else {
        return nil
    }
    let startOfToday = calendar.startOfDay(for: now)
    if dueDate < startOfToday {
        return .overdue
    }
    if calendar.isDate(dueDate, inSameDayAs: startOfToday) {
        return .dueToday
    }
    return nil
}
```

Rationale: `nonisolated` on both declarations is **required** — under the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, a plain `enum`/`func` would be MainActor-isolated (its `==` conformance too), and the non-MainActor test target could not use it. No EventKit import — this file stays testable in isolation.

#### 2. Boundary tests
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: rewrite (replace the empty `example()`)

```swift
import Foundation
@testable import SingleThread
import Testing

struct SingleThreadTests {
    // MARK: Internal

    @Test func completedReminderIsExcluded() {
        let due = DateComponents(year: 2026, month: 8, day: 12)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: true,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func missingDueDateIsExcluded() {
        let status = dueStatus(
            dueDateComponents: nil,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func yesterdayEndOfDayIsOverdue() {
        let due = DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 59)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .overdue)
    }

    @Test func todayStartOfDayIsDueToday() {
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .dueToday)
    }

    @Test func todayEndOfDayIsDueToday() {
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 23, minute: 59)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .dueToday)
    }

    @Test func tomorrowStartOfDayIsExcluded() {
        let due = DateComponents(year: 2026, month: 8, day: 13, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func halfPastMidnightIsDueTodayNotOverdue() throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let localNowComponents = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 30)
        let localNow = try #require(localCalendar.date(from: localNowComponents))
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: localNow,
            calendar: localCalendar)
        #expect(status == .dueToday)
    }

    // MARK: Private

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))!
}
```

Notes: the reference `now` is 2026-08-12 12:00 UTC. The last test uses a UTC-8 calendar to pin the "00:30 local" edge — a reminder due 00:00 local with `now` at 00:30 local must be `.dueToday`, not `.overdue` (a naive `dueDate < now` instant comparison would wrongly report overdue). `#require` (not `!`) is used inside test functions to satisfy SwiftFormat's `noForceUnwrapInTests`; `!` in the static fixtures is not flagged. Import order (`Foundation`, `@testable import SingleThread`, `Testing`) satisfies SwiftLint's `sorted_imports`.

### Verification
#### Automated
- [x] `make test` passes (i.e. `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`)
- [x] `./scripts/test.sh` is green (format + build + tests + lint)

#### Manual
- [ ] None — rule is pinned entirely by the boundary tests above.

---

## Phase 2: Reminder access — permissions, entitlements, `ReminderStore`

### Changes

#### 1. Store
**File**: `SingleThread/ReminderStore.swift`
**Action**: create

```swift
import EventKit
import Observation

enum ReminderAccessStatus {
    case notDetermined
    case denied
    case authorized

    // MARK: Lifecycle

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied, .restricted, .writeOnly:
            self = .denied
        case .authorized, .fullAccess:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }
}

@MainActor
@Observable
final class ReminderStore {
    // MARK: Internal

    let eventStore = EKEventStore()

    private(set) var accessStatus = ReminderAccessStatus.notDetermined
    private(set) var reminders: [EKReminder] = []

    func load() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try? await eventStore.requestFullAccessToReminders()
        }
        accessStatus = ReminderAccessStatus(EKEventStore.authorizationStatus(for: .reminder))
        guard accessStatus == .authorized else {
            reminders = []
            return
        }
        eventStore.reset()
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil)
        reminders = await fetchReminders(matching: predicate)
    }

    // MARK: Private

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}
```

Notes: `eventStore.reset()` after authorization mitigates the known "empty results right after first grant" issue. `requestFullAccessToReminders()` *is* async (`try? await`); `fetchReminders(matching:)` is **not** — hence the continuation bridge (see Overview note 2). The predicate with nil start/end returns all incomplete reminders; filtering is the view's job (Phase 3).

#### 2. Entitlements file
**File**: `SingleThread/SingleThread.entitlements`
**Action**: create

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.personal-information.calendars</key>
	<true/>
</dict>
</plist>
```

#### 3. Project settings — build setting + plist key
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: edit (both the Debug and Release app-target `XCBuildConfiguration` blocks — the two with `ENABLE_APP_SANDBOX = YES`)

Two insertions in **each** block:

a. After `CODE_SIGN_STYLE = Automatic;` add:
```
				CODE_SIGN_ENTITLEMENTS = SingleThread/SingleThread.entitlements;
```

b. After `GENERATE_INFOPLIST_FILE = YES;` add:
```
				INFOPLIST_KEY_NSRemindersFullAccessUsageDescription = "SingleThread shows your overdue and due-today reminders.";
```

Notes:
- The `.entitlements` file is **not** auto-discovered as a buildable source, but under `objectVersion = 77` the `PBXFileSystemSynchronizedRootGroup` for `SingleThread/` syncs it into the navigator automatically, and `CODE_SIGN_ENTITLEMENTS` is a path-based build setting — **no explicit `PBXFileReference` edit is required**. (This corrects a note in `structure.md`; the essential change is the build setting + the file existing at that path.)
- `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` is platform-universal, so no `[sdk=…]` suffix (unlike the existing iOS-only UI keys).

#### 4. App entry point — inject the store
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: edit (SwiftData still present this phase)

Replace `var body: some Scene` with the store-injecting version; keep `sharedModelContainer` for now:

```swift
    @State private var reminderStore = ReminderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(reminderStore)
        .modelContainer(sharedModelContainer)
    }
```

(Add `@State private var reminderStore = ReminderStore()` at the top of the struct, before `sharedModelContainer`.)

### Verification
#### Automated
- [x] iOS build: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- [x] macOS build: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug build`

#### Manual (macOS path is **not** covered by CI — verify by hand)
- [x] iOS launch → system TCC prompt for Reminders appears → grant → reminders populate (verified on device)
- [ ] macOS launch (sandboxed) → prompts for Reminders via the `com.apple.security.personal-information.calendars` entitlement → reminders populate

---

## Phase 3: Reminders list UI + remove SwiftData

### Changes

#### 1. ContentView — store-driven list
**File**: `SingleThread/ContentView.swift`
**Action**: rewrite

```swift
import EventKit
import SwiftUI

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        NavigationViewWrapper {
            List {
                ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier) { visible in
                    ReminderRow(visible: visible)
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            #endif
        }
        .task {
            await reminderStore.load()
        }
    }

    // MARK: Private

    @Environment(ReminderStore.self) private var reminderStore

    private var visibleReminders: [VisibleReminder] {
        let now = Date()
        let calendar = Calendar.current
        return reminderStore.reminders
            .compactMap { reminder -> VisibleReminder? in
                guard let status = dueStatus(
                    dueDateComponents: reminder.dueDateComponents,
                    isCompleted: reminder.isCompleted,
                    now: now,
                    calendar: calendar) else {
                    return nil
                }
                let dueDate = reminder.dueDateComponents.flatMap { calendar.date(from: $0) } ?? .distantFuture
                return VisibleReminder(reminder: reminder, status: status, dueDate: dueDate)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }
}

private struct VisibleReminder {
    let reminder: EKReminder
    let status: DueStatus
    let dueDate: Date
}

private struct ReminderRow: View {
    let visible: VisibleReminder

    var body: some View {
        VStack(alignment: .leading) {
            Text(visible.reminder.title ?? "Untitled")
            Text(visible.dueDate, format: Date.FormatStyle(date: .numeric, time: .standard))
                .font(.caption)
        }
        .foregroundStyle(visible.status == .overdue ? Color.red : Color.primary)
    }
}

private struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                content()
            } detail: {
                Text("Select a reminder")
            }
        #else
            content()
        #endif
    }
}

#Preview {
    ContentView()
        .environment(ReminderStore())
}
```

Notes: one shared `ReminderRow` view (title + due date); overdue rows styled `.red`. `NavigationViewWrapper` is kept, with the stale `"Select an item"` detail updated to `"Select a reminder"`. `visibleReminders` filters via the Phase 1 `dueStatus`, sorts ascending by due date. `calendarItemIdentifier` is the stable `ForEach` id. `addItem`/`deleteItems`, `@Query`, `modelContext`, and the toolbar are all gone.

#### 2. App entry point — drop SwiftData
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: edit — full final form

```swift
import SwiftUI

@main
struct SingleThreadApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(reminderStore)
    }

    // MARK: Private

    @State private var reminderStore = ReminderStore()
}
```

(Remove `import SwiftData`, `sharedModelContainer`, `Schema`, `ModelConfiguration`, and the `.modelContainer` modifier.)

#### 3. Item model
**File**: `SingleThread/Item.swift`
**Action**: delete

The old SwiftData store is simply orphaned; no migration is needed since the model is dropped entirely.

### Verification
#### Automated
- [x] `./scripts/test.sh` is green (build + tests + SwiftFormat lint + SwiftLint strict)
- [x] No dangling SwiftData: `grep -rE 'Item|@Query|modelContext' SingleThread/` returns nothing

#### Manual
- [x] iOS launch → grant Reminders → list shows exactly the incomplete overdue-or-today reminders, ascending by due date, overdue rows in red

---

## Phase 4: Access states, refresh, remove visionOS

### Changes

#### 1. ContentView — state rendering + foreground refresh (no platform guard)
**File**: `SingleThread/ContentView.swift`
**Action**: edit (three edits; helper structs and `#Preview` from Phase 3 unchanged)

**Edit 1 — replace `var body`** with the state-aware version (no `#if` guard — only iOS + macOS are built):

```swift
    var body: some View {
        NavigationViewWrapper {
            reminderList
        }
        .task {
            await reminderStore.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await reminderStore.load()
                }
            }
        }
    }
```

**Edit 2 — add `scenePhase`** to the `// MARK: Private` properties (next to the existing `@Environment(ReminderStore.self)`):

```swift
    @Environment(\.scenePhase) private var scenePhase
```

**Edit 3 — add the `reminderList` computed view** (after `visibleReminders`):

```swift
    @ViewBuilder
    private var reminderList: some View {
        switch reminderStore.accessStatus {
        case .notDetermined:
            ProgressView()
        case .denied:
            ContentUnavailableView(
                "Reminders access denied",
                systemImage: "bell.slash",
                description: Text("Enable Reminders access in Settings."))
        case .authorized:
            if visibleReminders.isEmpty {
                ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier) { visible in
                        ReminderRow(visible: visible)
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #endif
            }
        }
    }
```

Notes:
- `NavigationViewWrapper` keeps its own `#if os(macOS)` for the `NavigationSplitView` — that's an iOS/macOS difference, still needed.
- `#Preview` stays `.environment(ReminderStore())`. EventKit isn't stub-able in previews, so the preview renders the `.notDetermined` (`ProgressView`) state — acceptable.
- `Task { await reminderStore.load() }` has no `@MainActor` annotation — redundant under the project's default MainActor isolation.

#### 2. Project — remove visionOS as a target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: edit (app, test, and UI-test targets × Debug/Release = 6 build-configuration blocks)

In every block, apply all three of these:

a. `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator";` → `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";`

b. `TARGETED_DEVICE_FAMILY = "1,2,7";` → `TARGETED_DEVICE_FAMILY = "1,2";`

c. Delete the line `XROS_DEPLOYMENT_TARGET = 26.5;`

(Each of the three lines appears 6 times total — once per block.)

### Verification
#### Automated
- [x] iOS: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- [x] macOS: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug build`
- [x] `./scripts/test.sh` is green

#### Manual
- [ ] Deny Reminders access → "Reminders access denied" message renders
- [ ] Grant with no overdue/today reminders → "No overdue or due-today reminders" message renders
- [ ] Grant with qualifying reminders → list renders; background the app, complete a reminder in Reminders, foreground → list refreshes without relaunch

---

## Testing Checkpoints (summary)

- **After P1**: classifier tests green under `./scripts/test.sh`; rule pinned at day boundaries including the 00:30-local edge.
- **After P2**: iOS + macOS builds; TCC prompt and fetch verified manually; macOS entitlement wired (manual-only, not in CI).
- **After P3**: `./scripts/test.sh` green with zero SwiftData/`Item` references; list renders real reminders.
- **After P4**: iOS + macOS build; denied/empty/refresh states render correctly.
