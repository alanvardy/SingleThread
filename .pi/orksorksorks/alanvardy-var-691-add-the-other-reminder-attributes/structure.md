# Structure Outline

## Approach

Refactor the watch to consume `ReminderDisplay` first (eliminating inline `EKReminder` formatting), then add recurrence + alarm fields to the shared struct, build iOS/widget/watch rendering behind individual display toggles, and sync the new preferences to watch via the existing 6-step pipeline. Every phase is independently testable end-to-end.

---

## Phase 1: Watch refactor to `ReminderDisplay`

Eliminate the watch’s duplicated `EKReminder` formatting by switching `WatchReminderView`’s rendering path to `ReminderDisplay`. The store stays for actions (complete/skip/delete/refresh) — only display changes. This also surfaces `listName` on watch for the first time.

**Files**: `SingleThreadWatch/WatchReminderView.swift`

**Key changes**:
- `reminderDetails(_:)` signature change:
  ```swift
  // Before
  private func reminderDetails(_ reminder: EKReminder) -> some View
  // After
  private func reminderDetails(_ display: ReminderDisplay) -> some View
  ```
- Call site: compute `ReminderDisplay(reminder: reminder)` where `reminderDetails(_:)` is invoked in `reminderCard(_:)`
- Replace inline `EKReminder` reads (`.title`, `.priority`, `.dueDateComponents?.date`, `.notes`) with `display.title`, `display.priorityMarker`, `display.dueDate`, `display.notes`
- Add `listName` rendering row (gated: `if let listName = display.listName`), matching `ReminderCardView`’s pattern
- `priorityMarker` now comes from `display.priorityMarker` (pre-formatted string) instead of `ReminderPriority.marker(for: reminder.priority)` — keep `ReminderPriority.level(forMarker:)` for color lookup

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` passes; watch UI smoke test shows same fields as before plus a list name row below the title line.

---

## Phase 2: `ReminderDisplay` fields + `ReminderRecurrenceFormatter`

Add `hasRecurrence`, `recurrenceSummary`, and `hasAlarms` to `ReminderDisplay` and create the formatter that produces the human-readable recurrence summary. No rendering yet — this is pure model layer.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`, `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift` (new), `SingleThreadTests/ReminderDisplayTests.swift`, `SingleThreadTests/ReminderRecurrenceFormatterTests.swift` (new)

**Key changes**:
- `ReminderRecurrenceFormatter` (new):
  ```swift
  public enum ReminderRecurrenceFormatter {
      /// Produces a short human-readable summary (e.g. "Daily", "Every 2 weeks")
      /// from the **first** recurrence rule. Returns nil when there are no rules
      /// or the first rule cannot be concisely described.
      public static func format(_ rules: [EKRecurrenceRule]?) -> String?
  }
  ```
  Maps `EKRecurrenceFrequency` + `interval` to localized strings:
  - `.daily`: "Daily" / "Every N days"
  - `.weekly`: "Weekly" / "Every N weeks"
  - `.monthly`: "Monthly" / "Every N months"
  - `.yearly`: "Yearly" / "Every N years"
  - Returns `nil` for empty/nil rules or unsupported patterns (end dates, set positions, etc.)

- `ReminderDisplay` additions:
  ```swift
  public let hasRecurrence: Bool
  public let recurrenceSummary: String?
  public let hasAlarms: Bool
  ```
  - `init(reminder:)` maps: `hasRecurrence = reminder.hasRecurrenceRules`, `recurrenceSummary = ReminderRecurrenceFormatter.format(reminder.recurrenceRules)`, `hasAlarms = reminder.hasAlarms`
  - `init(title:notes:dueDate:priorityMarker:listName:)` (direct constructor): new params default to `false`, `nil`, `false`
  - Add a second direct constructor with all 8 params (for tests/previews that need the new fields)

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes; new test suites cover:
- `ReminderRecurrenceFormatterTests`: daily/weekly/monthly/yearly strings, interval > 1, nil/empty rules, complex rules → nil
- `ReminderDisplayTests`: `hasRecurrence`/`hasAlarms` from real `EKReminder`, recurrence summary from first rule, nil summary for no rules

---

## Phase 3: iOS display toggles

Add `ShowRecurrencePreference` / `ShowAlarmsPreference`, Settings toggles, and `ReminderCardView` rendering. This is the first phase where anything is user-visible on iOS.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ShowRecurrencePreference.swift` (new), `SingleThreadCore/Sources/SingleThreadCore/ShowAlarmsPreference.swift` (new), `SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`, `SingleThread/ReminderCardView.swift`, `SingleThreadTests/ShowRecurrencePreferenceTests.swift` (new), `SingleThreadTests/ShowAlarmsPreferenceTests.swift` (new), `SingleThreadTests/ShowRecurrenceTests.swift` (new), `SingleThreadTests/ShowAlarmsTests.swift` (new), `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `ShowRecurrencePreference` (new, follows `ShowDatePreference` pattern exactly):
  ```swift
  public struct ShowRecurrencePreference {
      public init(defaults: UserDefaults = AppGroup.defaults) { … }
      public var isEnabled: Bool  // missing-key default: true
      public func set(_ value: Bool)
      private let defaults: UserDefaults
      private let key = "showRecurrence"
  }
  ```
- `ShowAlarmsPreference` (new, identical shape, key `"showAlarms"`, default `true`)

- `ContentView.swift`: add `@AppStorage("showRecurrence", store: AppGroup.defaults) var showRecurrence = true` and `@AppStorage("showAlarms", store: AppGroup.defaults) var showAlarms = true` bindings; pass `showRecurrence: showRecurrence` and `showAlarms: showAlarms` to `ReminderCardView`

- `SettingsView.swift`: two new `Toggle` rows under "Show" section (`:115-121`):
  ```swift
  Toggle(isOn: $showRecurrence) {
      Label("Recurrence indicator", systemImage: "repeat")
  }
  Toggle(isOn: $showAlarms) {
      Label("Reminder alerts", systemImage: "bell")
  }
  ```
  No `onChange` / no `WidgetCenter` reload for either.

- `ReminderCardView.swift`: accept `showRecurrence: Bool`, `showAlarms: Bool` params; add rendering:
  ```swift
  if showRecurrence, display.hasRecurrence {
      HStack { Image(systemName: "repeat"); Text(display.recurrenceSummary ?? "Repeats") }
  }
  if showAlarms, display.hasAlarms {
      Image(systemName: "bell")
  }
  ```

**Verify**:
- `xcodebuild test … -only-testing:SingleThreadTests` — new preference tests (missing-key default = true, set/get roundtrip), view sentinel tests for card rendering gated by showRecurrence/showAlarms, SettingsView row presence
- `xcodebuild test … -only-testing:SingleThreadUITests` — UI test toggles both settings on/off and confirms card rows appear/disappear

---

## Phase 4: Widget display

Add `showsRecurrence` / `showsAlarms` flags to `NextThingEntry` and compact indicator rendering in `NextThingWidgetView`. No `WidgetCenter.reloadAllTimelines()` — the flags embed at timeline-build time.

**Files**: `SingleThreadWidget/NextThingWidget.swift`

**Key changes**:
- `NextThingEntry` additions:
  ```swift
  let showsRecurrence: Bool
  let showsAlarms: Bool
  ```
  Update all entry constructors (placeholder, snapshot, `makeEntry`, preview).

- `makeEntry()`: read `ShowRecurrencePreference().isEnabled` / `ShowAlarmsPreference().isEnabled` alongside the existing `showsDate`/`showsList` reads.

- `NextThingWidgetView.reminderView(_:)`: add compact indicator rows:
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

**Verify**: Build the widget target (`xcodebuild build -scheme SingleThreadWidget …`); manually run the widget — toggle recurrence/alarms off in Settings, wait for next widget refresh (≤15 min), confirm indicators disappear.

---

## Phase 5: Watch sync + display

Wire the new preferences through the 6-step sync pipeline so the watch receives them via WatchConnectivity, then render recurrence + alarms on watch via the already-refactored `ReminderDisplay` path (Phase 1).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, `SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/ShowRecurrenceState.swift` (new), `SingleThreadWatch/ShowAlarmsState.swift` (new), `SingleThreadWatch/WatchReminderView.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`, `SingleThreadWatchTests/WatchSyncPipelineTests.swift`

**Key changes**:

1. **Payload keys** — `SkippedReminderSyncService.PayloadKey`:
   ```swift
   static let showRecurrence = "showRecurrence"
   static let showAlarms = "showAlarms"
   ```

2. **Service init + stores** — inject `ShowRecurrencePreference` / `ShowAlarmsPreference`:
   ```swift
   // added to SkippedReminderSyncService init params:
   showRecurrenceStore: ShowRecurrencePreference = ShowRecurrencePreference(),
   showAlarmsStore: ShowAlarmsPreference = ShowAlarmsPreference(),
   ```
   Store as private `let` properties. No `sends*` flags — always pushed.

3. **`pushAll()`** — add to context dictionary:
   ```swift
   PayloadKey.showRecurrence: showRecurrenceStore.isEnabled,
   PayloadKey.showAlarms: showAlarmsStore.isEnabled,
   ```

4. **`apply(context:)`** — two new receive branches following the `showDate` pattern:
   ```swift
   if let value = context[PayloadKey.showRecurrence] as? Bool { … }
   if let value = context[PayloadKey.showAlarms] as? Bool { … }
   ```
   Plus `onShowRecurrenceReceived` / `onShowAlarmsReceived` hooks.

5. **Hooks** — new `nonisolated(unsafe)` properties:
   ```swift
   public nonisolated(unsafe) var onShowRecurrenceReceived: ((Bool) -> Void)?
   public nonisolated(unsafe) var onShowAlarmsReceived: ((Bool) -> Void)?
   ```

6. **iOS sender** — `SingleThreadApp.swift`: inject new stores into `SkippedReminderSyncService` init; add `onChange(of: showRecurrence)` / `onChange(of: showAlarms)` → `syncService?.pushAll()`.

7. **Watch state wrappers** — new files following `ShowDateState` pattern:
   ```swift
   @Observable final class ShowRecurrenceState {
       init() { isEnabled = preference.isEnabled }
       private(set) var isEnabled: Bool
       func apply(_ value: Bool) { preference.set(value); isEnabled = value }
       private let preference = ShowRecurrencePreference(defaults: .standard)
   }
   // ShowAlarmsState — identical shape
   ```

8. **Watch app wiring** — `SingleThreadWatchApp.swift`: add `showRecurrenceState` / `showAlarmsState` properties; set `onShowRecurrenceReceived` / `onShowAlarmsReceived` before `activate()`; pass state wrappers to `WatchReminderView`.

9. **Watch rendering** — `WatchReminderView`: accept `showRecurrenceState: ShowRecurrenceState`, `showAlarmsState: ShowAlarmsState`; in `reminderDetails(_:)` add gated rows:
   ```swift
   if showRecurrenceState.isEnabled, display.hasRecurrence { … }
   if showAlarmsState.isEnabled, display.hasAlarms { … }
   ```

**Verify**:
- `xcodebuild test … -only-testing:SingleThreadWatchTests` — `WatchSyncPipelineTests`: push asserts new keys in context; receive asserts store + callback for each; absent-key no-ops; relaunch persistence
- Watch UI test: toggle both settings on iOS, confirm watch receives change within seconds via WatchConnectivity, rows appear/disappear

---

## Testing Checkpoints

| After phase | What holds |
|---|---|
| **1** | Watch compiles and renders through `ReminderDisplay`; list name appears on watch; existing watch tests pass |
| **2** | `ReminderDisplay` carries `hasRecurrence`, `recurrenceSummary`, `hasAlarms`; formatter returns correct strings; all `SingleThreadTests` pass |
| **3** | iOS Settings has two new toggles (default on); toggling hides/shows recurrence + alarm rows on card; UI tests confirm |
| **4** | Widget entry carries the two new flags; widget rendering reflects them on next refresh |
| **5** | Toggling on iOS pushes to watch; watch state wrappers persist + publish; watch rows gate correctly; `WatchSyncPipelineTests` cover push + receive |