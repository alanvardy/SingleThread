# Implementation Plan

## Overview

Surface reminder recurrence and alarm indicators on iOS card, watch, and widget views, with per-attribute display toggles synced phone→watch via the existing 6-step WatchConnectivity pipeline.

---

## Phase 1: Watch refactor to `ReminderDisplay`

### Changes

#### 1. `reminderDetails` signature + body
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Change `reminderDetails(_:)` from receiving `EKReminder` to receiving `ReminderDisplay`, replace all inline `EKReminder` field accesses with `display.*` properties, and add list-name rendering. Keep `priorityColor(_:)` and `ReminderPriority.level(forMarker:)` for the color lookup — they now consume `display.priorityMarker` instead of `reminder.priority`.

```swift
// BEFORE (lines 164–181):
private func reminderDetails(_ reminder: EKReminder) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let level = ReminderPriority.level(for: reminder.priority) {
                Text(ReminderPriority.marker(for: reminder.priority))
                    .font(.headline)
                    .foregroundStyle(priorityColor(level))
                    .accessibilityLabel("\(level.displayName) priority")
            }
            Text(reminder.title)
                .font(.headline)
        }
        if showDateState.isEnabled, let due = reminder.dueDateComponents?.date {
            Text(due, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let noteText = ReminderNotesFormatter.format(reminder.notes) {
            Text(noteText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

// AFTER:
private func reminderDetails(_ display: ReminderDisplay) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let level = ReminderPriority.level(forMarker: display.priorityMarker) {
                Text(display.priorityMarker)
                    .font(.headline)
                    .foregroundStyle(priorityColor(level))
                    .accessibilityLabel("\(level.displayName) priority")
            }
            Text(display.title)
                .font(.headline)
        }
        if showDateState.isEnabled, let due = display.dueDate {
            Text(due, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let listName = display.listName {
            Text(listName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let noteText = display.notes {
            Text(noteText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

#### 2. Call site in `reminderCard(_:)`
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Inside `reminderCard(_:)` (line ~140), compute `ReminderDisplay` from the `EKReminder` and pass it into `reminderDetails(_:)`:

```swift
// BEFORE (inside reminderCard):
ScrollView {
    reminderDetails(reminder)
}

// AFTER:
ScrollView {
    let display = ReminderDisplay(reminder: reminder)
    reminderDetails(display)
}
```

The `reminderCard(_:)` signature stays `(EKReminder) -> some View` — the `EKReminder` is only used here and for the store's `deleteCurrentReminder()` (which doesn't need the parameter). No other call-site changes needed since `reminderCard` is called from `reminderContent` which accesses `store.visibleReminders.first` directly.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` passes
- [x] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` compiles (watch target)

#### Manual
- [ ] Watch UI smoke test: displays reminder title, priority marker, due date, notes (same as before), plus a new list-name row below the title line
- [ ] Watch shows a `listName` row when the reminder has a calendar title
- [ ] Watch shows no list-name row when `listName` is nil

---

## Phase 2: `ReminderDisplay` fields + `ReminderRecurrenceFormatter`

### Changes

#### 1. New formatter
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift`
**Action**: create

```swift
import EventKit
import Foundation

/// Produces short human-readable recurrence summaries (e.g. "Daily",
/// "Every 2 weeks") from an `EKRecurrenceRule` array.
///
/// Only the **first** rule's frequency + interval is formatted. Complex
/// rules (end dates, set positions, day-of-week lists) return `nil`.
/// Empty/nil input also returns `nil`.
public enum ReminderRecurrenceFormatter {
    public static func format(_ rules: [EKRecurrenceRule]?) -> String? {
        guard let first = rules?.first else { return nil }
        let interval = first.interval
        switch first.frequency {
        case .daily:
            return interval > 1 ? "Every \(interval) days" : "Daily"
        case .weekly:
            return interval > 1 ? "Every \(interval) weeks" : "Weekly"
        case .monthly:
            return interval > 1 ? "Every \(interval) months" : "Monthly"
        case .yearly:
            return interval > 1 ? "Every \(interval) years" : "Yearly"
        @unknown default:
            return nil
        }
    }
}
```

#### 2. `ReminderDisplay` additions
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify

Add three new stored properties and update both init methods:

```swift
// New properties (after `listName`):
public let hasRecurrence: Bool
public let recurrenceSummary: String?
public let hasAlarms: Bool
```

Update `init(reminder:)` to map the new fields:

```swift
// In init(reminder:), add after listName = reminder.calendar?.title:
hasRecurrence = reminder.hasRecurrenceRules
recurrenceSummary = ReminderRecurrenceFormatter.format(reminder.recurrenceRules)
hasAlarms = reminder.hasAlarms
```

Add a second direct constructor with all 8 params (leave the 5-arg one for existing callers):

```swift
/// Full constructor for tests and previews that need the new fields.
public init(
    title: String,
    notes: String? = nil,
    dueDate: Date? = nil,
    priorityMarker: String = "",
    listName: String? = nil,
    hasRecurrence: Bool = false,
    recurrenceSummary: String? = nil,
    hasAlarms: Bool = false
) {
    self.title = title
    self.notes = notes
    self.dueDate = dueDate
    self.priorityMarker = priorityMarker
    self.listName = listName
    self.hasRecurrence = hasRecurrence
    self.recurrenceSummary = recurrenceSummary
    self.hasAlarms = hasAlarms
}
```

The existing 5-arg direct constructor should delegate to or be replaced by the 8-arg one with defaults. The simplest approach: keep the 5-arg `init(title:notes:dueDate:priorityMarker:listName:)` but have it call `self.init(title:notes:dueDate:priorityMarker:listName:hasRecurrence:recurrenceSummary:hasAlarms:)` with all new params defaulted. Since both inits need to fully init all stored properties, the cleanest pattern is one 8-arg init and a convenience 5-arg that calls it:

```swift
// Replace the 5-arg init body with delegation (no code duplication):
public init(
    title: String,
    notes: String? = nil,
    dueDate: Date? = nil,
    priorityMarker: String = "",
    listName: String? = nil
) {
    self.init(
        title: title,
        notes: notes,
        dueDate: dueDate,
        priorityMarker: priorityMarker,
        listName: listName,
        hasRecurrence: false,
        recurrenceSummary: nil,
        hasAlarms: false
    )
}
```

#### 3. New formatter tests
**File**: `SingleThreadTests/ReminderRecurrenceFormatterTests.swift`
**Action**: create

```swift
import EventKit
import SingleThreadCore
import Testing

struct ReminderRecurrenceFormatterTests {
    @Test
    func nilRulesReturnsNil() {
        #expect(ReminderRecurrenceFormatter.format(nil) == nil)
    }

    @Test
    func emptyRulesReturnsNil() {
        #expect(ReminderRecurrenceFormatter.format([]) == nil)
    }

    @Test
    func dailySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Daily")
    }

    @Test
    func dailyIntervalTwo() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Every 2 days")
    }

    @Test
    func weeklySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Weekly")
    }

    @Test
    func weeklyIntervalThree() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 3, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Every 3 weeks")
    }

    @Test
    func monthlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Monthly")
    }

    @Test
    func yearlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Yearly")
    }
}
```

#### 4. Extend `ReminderDisplayTests`
**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify

Add tests for the new fields:

```swift
@Test
func mapsHasRecurrenceTrue() {
    let reminder = makeReminder(title: "Milk")
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
    #expect(ReminderDisplay(reminder: reminder).hasRecurrence)
}

@Test
func mapsHasRecurrenceFalse() {
    #expect(!ReminderDisplay(reminder: makeReminder(title: "Milk")).hasRecurrence)
}

@Test
func mapsRecurrenceSummary() {
    let reminder = makeReminder(title: "Milk")
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
    #expect(ReminderDisplay(reminder: reminder).recurrenceSummary == "Daily")
}

@Test
func nilRecurrenceSummaryWhenNoRules() {
    #expect(ReminderDisplay(reminder: makeReminder(title: "Milk")).recurrenceSummary == nil)
}

@Test
func mapsHasAlarmsTrue() {
    let reminder = makeReminder(title: "Milk")
    reminder.addAlarm(EKAlarm(absoluteDate: Date()))
    #expect(ReminderDisplay(reminder: reminder).hasAlarms)
}

@Test
func mapsHasAlarmsFalse() {
    #expect(!ReminderDisplay(reminder: makeReminder(title: "Milk")).hasAlarms)
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — all `ReminderDisplayTests` and `ReminderRecurrenceFormatterTests` green
- [x] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` compiles

#### Manual
- [ ] None — this is pure model layer with no UI changes

---

## Phase 3: iOS display toggles

### Changes

#### 1. New preference types
**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowRecurrencePreference.swift`
**Action**: create

Follow `ShowDatePreference.swift:8-27` exactly — same shape, defaults key `"showRecurrence"`, missing-key default `true`:

```swift
import Foundation

/// Persists the user's "show recurrence" preference in UserDefaults.
/// An absent key resolves to `true` (show by default).
public struct ShowRecurrencePreference {
    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showRecurrence") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowAlarmsPreference.swift`
**Action**: create

Identical shape, key `"showAlarms"`, default `true`:

```swift
import Foundation

/// Persists the user's "show alarms" preference in UserDefaults.
/// An absent key resolves to `true` (show by default).
public struct ShowAlarmsPreference {
    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showAlarms") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. `@AppStorage` bindings in ContentView
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add two new `@AppStorage` properties in the `// MARK: Private` section (after `showList` at line ~225):

```swift
@AppStorage("showRecurrence", store: AppGroup.defaults)
private var showRecurrence = true

@AppStorage("showAlarms", store: AppGroup.defaults)
private var showAlarms = true
```

Update the `ReminderCardView` call site (line ~348) to pass the new flags:

```swift
ReminderCardView(
    display: ReminderDisplay(reminder: reminder),
    showDate: showDate,
    showList: showList,
    showRecurrence: showRecurrence,
    showAlarms: showAlarms,
    showsOverPhoto: backgroundDisplayed)
```

Update the iOS `SettingsView` sheet construction (line ~132) to pass the new bindings:

```swift
SettingsView(
    appearanceMode: $appearanceMode,
    textSize: $textSize,
    allowsLandscape: $allowsLandscape,
    enableActionButtons: $enableActionButtons,
    showMicrophoneButton: $showMicrophoneButton,
    backgroundEnabled: $backgroundEnabled,
    backgroundFadePercent: $backgroundFadePercent,
    backgroundPhotographer: backgroundImage.photographer,
    showUndatedReminders: $showUndatedReminders,
    excludedLists: excludedListsBinding,
    availableLists: store.availableLists,
    sortOption: $sortOption,
    showDate: $showDate,
    showList: $showList,
    showRecurrence: $showRecurrence,
    showAlarms: $showAlarms)
```

Update the macOS `SettingsView` sheet construction (line ~148) identically (add `showRecurrence: $showRecurrence, showAlarms: $showAlarms` at the end).

#### 3. `ReminderCardView` new params + rendering
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Add two new params to the init (after `showsOverPhoto`):

```swift
init(
    display: ReminderDisplay,
    showDate: Bool,
    showList: Bool = false,
    showRecurrence: Bool = true,
    showAlarms: Bool = true,
    showsOverPhoto: Bool = false) {
    self.display = display
    self.showDate = showDate
    self.showList = showList
    self.showRecurrence = showRecurrence
    self.showAlarms = showAlarms
    self.showsOverPhoto = showsOverPhoto
}
```

Add two new private stored properties:

```swift
private let showRecurrence: Bool
private let showAlarms: Bool
```

In `body`, add gated rows after the `showList` row (after line ~50) and before the notes row:

```swift
if showRecurrence, display.hasRecurrence {
    HStack(spacing: 4) {
        Image(systemName: "repeat")
        Text(display.recurrenceSummary ?? "Repeats")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
}
if showAlarms, display.hasAlarms {
    Image(systemName: "bell")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

#### 4. `SettingsView` new toggle rows + init params
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Add two new `Toggle` rows under the "Show" section, after "Show list" (line ~121):

```swift
Toggle(isOn: $showRecurrence) {
    Label("Recurrence indicator", systemImage: "repeat")
}
Toggle(isOn: $showAlarms) {
    Label("Reminder alerts", systemImage: "bell")
}
```

Add the `showRecurrence` and `showAlarms` bindings to both init signatures.

Add to iOS init (after `showList: Binding<Bool>`):

```swift
showRecurrence: Binding<Bool>,
showAlarms: Binding<Bool>
```

Add to macOS init (after `showList: Binding<Bool>`):

```swift
showRecurrence: Binding<Bool>,
showAlarms: Binding<Bool>
```

Add the `_showRecurrence` and `_showAlarms` property-wrappers in both initializer bodies (after `_showList = showList`):

```swift
_showRecurrence = showRecurrence
_showAlarms = showAlarms
```

Add two new `@Binding` properties in the struct body:

```swift
@Binding private var showRecurrence: Bool
@Binding private var showAlarms: Bool
```

#### 5. Seed reset keys
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

Add `"showRecurrence"` and `"showAlarms"` to the `persistedKeys` array (line ~67):

```swift
private static let persistedKeys = [
    "skippedReminderIdentifiers",
    "excludedListTitles",
    "showDate",
    "showList",
    "showRecurrence",
    "showAlarms",
    "showUndatedReminders",
    "sortOption",
    "showMicrophoneButton",
    "backgroundEnabled",
    "allowsLandscape",
    "textSize",
    "appearanceMode"
]
```

#### 6. New preference unit tests
**File**: `SingleThreadTests/ShowRecurrencePreferenceTests.swift`
**Action**: create

Following `ShowDatePreferenceTests.swift` pattern exactly:

```swift
import Foundation
import SingleThreadCore
import Testing

struct ShowRecurrencePreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }
}
```

**File**: `SingleThreadTests/ShowAlarmsPreferenceTests.swift`
**Action**: create

Identical structure, using `ShowAlarmsPreference` and key prefix `"showalarms-test-"`.

#### 7. View assertion tests for recurrence + alarms rendering
**File**: `SingleThreadTests/ShowRecurrenceTests.swift`
**Action**: create

Following `ShowDateTests.swift` pattern:

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowRecurrenceTests {
    @Test
    func recurrenceRowShownWhenEnabledAndHasRecurrence() {
        let description = String(describing: makeCard(showRecurrence: true, hasRecurrence: true).body)
        #expect(description.contains("repeat"))
    }

    @Test
    func recurrenceRowHiddenWhenDisabled() {
        let description = String(describing: makeCard(showRecurrence: false, hasRecurrence: true).body)
        #expect(!description.contains("repeat"))
    }

    @Test
    func recurrenceRowHiddenWhenNoRecurrence() {
        let description = String(describing: makeCard(showRecurrence: true, hasRecurrence: false).body)
        #expect(!description.contains("repeat"))
    }

    private func makeCard(showRecurrence: Bool, hasRecurrence: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(
                title: "Buy groceries",
                hasRecurrence: hasRecurrence,
                recurrenceSummary: hasRecurrence ? "Weekly" : nil),
            showDate: true,
            showRecurrence: showRecurrence)
    }
}
```

**File**: `SingleThreadTests/ShowAlarmsTests.swift`
**Action**: create

Identical pattern, checking for `"bell"` and using `hasAlarms`:

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowAlarmsTests {
    @Test
    func alarmsRowShownWhenEnabledAndHasAlarms() {
        let description = String(describing: makeCard(showAlarms: true, hasAlarms: true).body)
        #expect(description.contains("bell"))
    }

    @Test
    func alarmsRowHiddenWhenDisabled() {
        let description = String(describing: makeCard(showAlarms: false, hasAlarms: true).body)
        #expect(!description.contains("bell"))
    }

    @Test
    func alarmsRowHiddenWhenNoAlarms() {
        let description = String(describing: makeCard(showAlarms: true, hasAlarms: false).body)
        #expect(!description.contains("bell"))
    }

    private func makeCard(showAlarms: Bool, hasAlarms: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(
                title: "Buy groceries",
                hasAlarms: hasAlarms),
            showDate: true,
            showAlarms: showAlarms)
    }
}
```

#### 8. Extend `SettingsViewTests`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Update the `SettingsView` init calls in the test to include the new bindings (add `.constant(true)` for `showRecurrence` and `showAlarms` to both iOS and non-iOS branches). Add two new assertions:

```swift
#expect(bodyDescription.contains("Recurrence indicator"))
#expect(bodyDescription.contains("Reminder alerts"))
```

#### 9. Extend `UITestingSeed` tests if needed
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify (if it exists)

If the file exists, verify it still passes with the new `persistedKeys` entries. If no tests exercise `persistedKeys` directly, no changes needed.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all new tests pass, existing tests pass
- [x] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` compiles

#### Manual
- [ ] Launch app on iPhone 17 simulator: open Settings, confirm "Recurrence indicator" and "Reminder alerts" toggles appear under "Show" section, default to ON
- [ ] Create a test reminder with a recurrence rule (weekly) + alarm in Apple Reminders app → open SingleThread, confirm repeat icon + bell icon appear on card
- [ ] Toggle both settings OFF → confirm recurrence + alarm indicators disappear from card
- [ ] Toggle them back ON → confirm indicators reappear

---

## Phase 4: Widget display

### Changes

#### 1. `NextThingEntry` additions + all constructors
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

Add two new properties to `NextThingEntry`:

```swift
let showsRecurrence: Bool
let showsAlarms: Bool
```

Update every `NextThingEntry(...)` constructor to include the new fields:

- `placeholder(in:)` (line ~30): add `showsRecurrence: true, showsAlarms: true`
- `getSnapshot` (line ~38): add `showsRecurrence: true, showsAlarms: true`
- `makeEntry()` (line ~56): each return adds `showsRecurrence: showsRecurrence, showsAlarms: showsAlarms` which are computed before the switch:
  ```swift
  let showsRecurrence = ShowRecurrencePreference().isEnabled
  let showsAlarms = ShowAlarmsPreference().isEnabled
  ```
- `#Preview` factory (line ~222): add `showsRecurrence: true, showsAlarms: true`

#### 2. `reminderView(_:)` gated rows
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

In `reminderView(_:)` (after the `entry.showsList` row, line ~178, before notes):

```swift
if entry.showsRecurrence, display.hasRecurrence {
    Label(display.recurrenceSummary ?? "Repeats", systemImage: "repeat")
        .font(.caption2)
}
if entry.showsAlarms, display.hasAlarms {
    Label("Alert", systemImage: "bell")
        .font(.caption2)
}
```

### Verification

#### Automated
- [ ] `xcodebuild build -scheme SingleThreadWidget -destination 'platform=iOS Simulator,name=iPhone 17'` compiles

#### Manual
- [ ] Build and run the widget on iPhone 17 simulator: confirm recurrence and alarm indicators appear when applicable
- [ ] Toggle recurrence/alarms off in Settings, wait up to 15 minutes for timeline refresh, confirm indicators disappear

---

## Phase 5: Watch sync + display

### Changes

#### 1. Payload keys + stores + push + receive
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add new `PayloadKey` cases (inside the private enum, after `showDate`):

```swift
static let showRecurrence = "showRecurrence"
static let showAlarms = "showAlarms"
```

Add two new store properties to init:

```swift
// In init(...), add after showDateStore:
showRecurrenceStore: ShowRecurrencePreference = ShowRecurrencePreference(),
showAlarmsStore: ShowAlarmsPreference = ShowAlarmsPreference()
```

Add two new private stored properties:

```swift
private let showRecurrenceStore: ShowRecurrencePreference
private let showAlarmsStore: ShowAlarmsPreference
```

Add to `pushAll()` context dictionary (after the `sendsShowDate` block):

```swift
context[PayloadKey.showRecurrence] = showRecurrenceStore.isEnabled
context[PayloadKey.showAlarms] = showAlarmsStore.isEnabled
```

Add to `apply(context:)` (after the `showDate` branch):

```swift
if let value = context[PayloadKey.showRecurrence] as? Bool {
    showRecurrenceStore.set(value)
    let handler = onShowRecurrenceReceived
    handler?(value)
}
if let value = context[PayloadKey.showAlarms] as? Bool {
    showAlarmsStore.set(value)
    let handler = onShowAlarmsReceived
    handler?(value)
}
```

Add two new `nonisolated(unsafe)` hook properties (after `onShowDateReceived`):

```swift
public nonisolated(unsafe) var onShowRecurrenceReceived: ((Bool) -> Void)?
public nonisolated(unsafe) var onShowAlarmsReceived: ((Bool) -> Void)?
```

#### 2. iOS sender wiring
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Update the `SkippedReminderSyncService` init (line ~29) to inject the two new stores:

```swift
let service = SkippedReminderSyncService(
    session: WCSession.default,
    skipStore: skipStore,
    showDateStore: ShowDatePreference(),
    showRecurrenceStore: ShowRecurrencePreference(),
    showAlarmsStore: ShowAlarmsPreference(),
    sendsShowDate: true)
```

Add two `@AppStorage` declarations and `onChange` handlers. After `@AppStorage("showDate", store: AppGroup.defaults) private var showDate = true` (line ~99):

```swift
@AppStorage("showRecurrence", store: AppGroup.defaults)
private var showRecurrence = true

@AppStorage("showAlarms", store: AppGroup.defaults)
private var showAlarms = true
```

Add `onChange` handlers in the `body` (alongside the existing `onChange(of: showDate)` at line ~81):

```swift
.onChange(of: showRecurrence) { _, _ in
    syncService?.pushAll()
}
.onChange(of: showAlarms) { _, _ in
    syncService?.pushAll()
}
```

#### 3. Watch state wrappers
**File**: `SingleThreadWatch/ShowRecurrenceState.swift`
**Action**: create

Following `SingleThreadWatch/ShowDateState.swift` exactly:

```swift
import SingleThreadCore
import SwiftUI

@Observable
final class ShowRecurrenceState {
    init() {
        isEnabled = preference.isEnabled
    }

    private(set) var isEnabled: Bool

    func apply(_ value: Bool) {
        preference.set(value)
        isEnabled = value
    }

    private let preference = ShowRecurrencePreference(defaults: .standard)
}
```

**File**: `SingleThreadWatch/ShowAlarmsState.swift`
**Action**: create

Identical shape, using `ShowAlarmsPreference`.

#### 4. Watch app wiring
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

Add two new state properties (alongside `showDateState`):

```swift
private let showRecurrenceState = ShowRecurrenceState()
private let showAlarmsState = ShowAlarmsState()
```

Update `SkippedReminderSyncService` init (line ~31) to pass the new stores:

```swift
let service = SkippedReminderSyncService(
    session: WCSession.default,
    skipStore: SkippedReminderStore(),
    showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
    showDateStore: ShowDatePreference(defaults: .standard),
    showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
    showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
    sendsShowDate: false)
```

Add receive hooks before `service.activate()` (after `onShowDateReceived`, line ~45):

```swift
service.onShowRecurrenceReceived = { [weak showRecurrenceState] value in
    showRecurrenceState?.apply(value)
}
service.onShowAlarmsReceived = { [weak showAlarmsState] value in
    showAlarmsState?.apply(value)
}
```

Update `WatchReminderView` construction (line ~85) to pass the new state wrappers:

```swift
WatchReminderView(
    store: store,
    showDateState: showDateState,
    showRecurrenceState: showRecurrenceState,
    showAlarmsState: showAlarmsState)
```

#### 5. Watch rendering
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Add two new state params to the `init` (already has `showDateState`):

```swift
init(store: ReminderStore,
     showDateState: ShowDateState = ShowDateState(),
     showRecurrenceState: ShowRecurrenceState = ShowRecurrenceState(),
     showAlarmsState: ShowAlarmsState = ShowAlarmsState()) {
    self.store = store
    self.showDateState = showDateState
    self.showRecurrenceState = showRecurrenceState
    self.showAlarmsState = showAlarmsState
}
```

Add two new private stored properties:

```swift
private let showRecurrenceState: ShowRecurrenceState
private let showAlarmsState: ShowAlarmsState
```

In `reminderDetails(_:)` (now accepting `ReminderDisplay` from Phase 1), add gated rows after the list-name row and before notes:

```swift
if showRecurrenceState.isEnabled, display.hasRecurrence {
    Label(display.recurrenceSummary ?? "Repeats", systemImage: "repeat")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
if showAlarmsState.isEnabled, display.hasAlarms {
    Label("Alert", systemImage: "bell")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

Update the public preview-prefilling initializer to accept and store the new state wrappers:

```swift
init(
    loadsReminders: Bool,
    reminders: [EKReminder],
    skippedIDs: Set<String>,
    authorizationStatus: EKAuthorizationStatus,
    hasHidden: Bool = false,
    showDateState: ShowDateState = ShowDateState(),
    showRecurrenceState: ShowRecurrenceState = ShowRecurrenceState(),
    showAlarmsState: ShowAlarmsState = ShowAlarmsState()) {
    store = ReminderStore(
        loadsReminders: loadsReminders,
        reminders: reminders,
        skippedIDs: skippedIDs,
        authorizationStatus: authorizationStatus,
        hasHidden: hasHidden)
    self.showDateState = showDateState
    self.showRecurrenceState = showRecurrenceState
    self.showAlarmsState = showAlarmsState
}
```

#### 6. Extend `WatchSyncPipelineTests`
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify

Extend `pushAllFromWatchOmitsShowDate` to also assert the new keys are present (the watch with `sendsShowDate: false` still pushes other keys — verify `showRecurrence` and `showAlarms` are in the context since they have no sends-flag gating).

Add a new test `receiveAppliesShowRecurrenceAndShowAlarms`:

```swift
@Test
func receiveAppliesShowRecurrenceAndShowAlarms() {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let showRecurrenceStore = ShowRecurrencePreference(defaults: .standard, key: "wtest-rec-\(suffix)")
    let showAlarmsStore = ShowAlarmsPreference(defaults: .standard, key: "wtest-alarm-\(suffix)")
    showRecurrenceStore.set(false)
    showAlarmsStore.set(false)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-ids-\(suffix)"),
        showRecurrenceStore: showRecurrenceStore,
        showAlarmsStore: showAlarmsStore)

    var recurrenceValues: [Bool] = []
    var alarmValues: [Bool] = []
    service.onShowRecurrenceReceived = { recurrenceValues.append($0) }
    service.onShowAlarmsReceived = { alarmValues.append($0) }

    service.session(
        WCSession.default,
        didReceiveApplicationContext: [
            "showRecurrence": true,
            "showAlarms": true
        ])

    #expect(showRecurrenceStore.isEnabled)
    #expect(showAlarmsStore.isEnabled)
    #expect(recurrenceValues == [true])
    #expect(alarmValues == [true])
}
```

Add a new test `receiveAbsentRecurrenceAndAlarmsKeysAreNoOps`:

```swift
@Test
func receiveAbsentRecurrenceAndAlarmsKeysAreNoOps() {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let showRecurrenceStore = ShowRecurrencePreference(defaults: .standard, key: "wtest-absent-rec-\(suffix)")
    let showAlarmsStore = ShowAlarmsPreference(defaults: .standard, key: "wtest-absent-alarm-\(suffix)")
    showRecurrenceStore.set(false)
    showAlarmsStore.set(false)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-absent-ids-\(suffix)"),
        showRecurrenceStore: showRecurrenceStore,
        showAlarmsStore: showAlarmsStore)

    var fired = false
    service.onShowRecurrenceReceived = { _ in fired = true }
    service.onShowAlarmsReceived = { _ in fired = true }

    // Push only skip IDs — recurrence and alarms keys absent
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

    #expect(!showRecurrenceStore.isEnabled) // unchanged
    #expect(!showAlarmsStore.isEnabled) // unchanged
    #expect(!fired)
}
```

Add a new test for relaunch persistence on both new prefs:

```swift
@Test
func showRecurrenceSurvivesRelaunch() {
    let key = "wtest-relaunch-rec-\(UUID().uuidString)"
    let fake = WatchFakeSession()
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
        showRecurrenceStore: ShowRecurrencePreference(defaults: .standard, key: key))
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["showRecurrence": false])
    let freshStore = ShowRecurrencePreference(defaults: .standard, key: key)
    #expect(!freshStore.isEnabled)
}

@Test
func showAlarmsSurvivesRelaunch() {
    let key = "wtest-relaunch-alarm-\(UUID().uuidString)"
    let fake = WatchFakeSession()
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
        showAlarmsStore: ShowAlarmsPreference(defaults: .standard, key: key))
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["showAlarms": false])
    let freshStore = ShowAlarmsPreference(defaults: .standard, key: key)
    #expect(!freshStore.isEnabled)
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` — all new and existing `WatchSyncPipelineTests` pass
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` compiles (all targets including watch)
- [ ] `./scripts/test.sh` gate passes (format → lint → build → Periphery → unit tests → UI tests)

#### Manual
- [ ] Build and run on paired iPhone + Watch simulator: toggle both settings on iOS, confirm watch reflects changes within seconds via WatchConnectivity
- [ ] On watch: recurrence row appears when reminder has recurrence, disappears when `showRecurrence` toggled off
- [ ] On watch: alarm row appears when reminder has alarm, disappears when `showAlarms` toggled off

---

## Testing Checkpoints Summary

| After phase | What holds |
|---|---|
| **1** | Watch compiles and renders through `ReminderDisplay`; list name appears on watch; existing watch tests pass |
| **2** | `ReminderDisplay` carries `hasRecurrence`, `recurrenceSummary`, `hasAlarms`; formatter returns correct strings; all `SingleThreadTests` pass |
| **3** | iOS Settings has two new toggles (default on); toggling hides/shows recurrence + alarm rows on card; view-sentinel tests confirm |
| **4** | Widget entry carries the two new flags; widget rendering reflects them on next refresh; widget target compiles |
| **5** | Toggling on iOS pushes to watch; watch state wrappers persist + publish; watch rows gate correctly; `WatchSyncPipelineTests` cover push + receive |