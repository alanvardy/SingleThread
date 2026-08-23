# Implementation Plan

## Overview

The reminder list name (calendar title) renders as secondary text beneath the existing
content on the iOS card and the home-screen widget, gated by a new default-off "Show list"
preference shared through `AppGroup.defaults`; along the way the iOS card switches its input
from raw `EKReminder` to `ReminderDisplay`, and Settings row labels are normalized to
sentence case.

---

## Phase 1: List name on the iOS card (via `ReminderDisplay`)

### Changes

#### 1. Add `listName` to `ReminderDisplay`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify

```swift
public init(reminder: EKReminder) {
    title = reminder.title
    notes = ReminderNotesFormatter.format(reminder.notes)
    dueDate = reminder.dueDateComponents?.date
    priorityMarker = ReminderPriority.marker(for: reminder.priority)
    listName = reminder.calendar?.title
}

/// Direct constructor for previews, placeholder entries, and tests.
public init(
    title: String,
    notes: String? = nil,
    dueDate: Date? = nil,
    priorityMarker: String = "",
    listName: String? = nil) {
    // ... existing assignments ...
    self.listName = listName
}

public let title: String
public let notes: String?
public let dueDate: Date?
public let priorityMarker: String
public let listName: String?
```

Existing call sites compile unchanged (`listName` defaults to `nil` in the direct init;
the `init(reminder:)` signature is unchanged).

#### 2. Swap `ReminderCardView` input from `EKReminder` to `ReminderDisplay`
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Replace the `import EventKit`-backed stored property with a `display` property; remove
`EventKit` import if no longer referenced. Body reads display fields instead of inline
formatting:

```swift
/// The reminder card content: priority marker + title, optional due-date and
/// list-name rows, and notes. ...
struct ReminderCardView: View {
    init(
        display: ReminderDisplay,
        showDate: Bool,
        showList: Bool = false,
        showsOverPhoto: Bool = false) {
        self.display = display
        self.showDate = showDate
        self.showList = showList
        self.showsOverPhoto = showsOverPhoto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let level = ReminderPriority.level(for: display.priorityMarker) { /* unchanged */ }
                Text(display.title)
                    .font(.title)
            }
            if showDate, let due = display.dueDate {
                Text(due, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showList, let listName = display.listName, !listName.isEmpty {
                Text(listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let noteText = display.notes {
                Text(noteText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        // ... accessibility/padding/background modifiers unchanged ...
    }

    private let display: ReminderDisplay
    private let showDate: Bool
    private let showList: Bool
    private let showsOverPhoto: Bool
}
```

Note: `ReminderPriority.level(for:)` currently takes the raw priority integer. Check its
signature — if it takes `Int`, keep the marker/level derivation inside `ReminderDisplay`
instead (add nothing new; `priorityMarker` is already derived there). If the marker→level
round-trip isn't possible from `ReminderDisplay` alone, add `priorityLevel` (or reuse
`level(for: marker)`) minimally so the color logic keeps working. Do not widen scope
beyond what's needed for compilation.

#### 3. Wrap the reminder at the call site
**File**: `SingleThread/ContentView.swift`
**Action**: modify (in `reminderList`, ~line 342)

```swift
if let reminder = store.visibleReminders.first {
    ReminderCardView(
        display: ReminderDisplay(reminder: reminder),
        showDate: showDate,
        showList: true,   // temporary literal until Phase 2 wires the preference
        showsOverPhoto: backgroundDisplayed)
        // ... modifiers unchanged; contextMenu/swipeActions keep using raw `reminder`
        //     (calendarItemIdentifier etc.) ...
```

This is the single call site of `ReminderCardView` in app code (macOS shares this branch).

#### 4. Update card snapshot-test factories
**File**: `SingleThreadTests/ShowDateTests.swift`
**Action**: modify

```swift
private func makeCard(showDate: Bool, showList: Bool = false, listName: String? = nil)
    -> ReminderCardView {
    ReminderCardView(
        display: ReminderDisplay(
            title: "Buy groceries",
            dueDate: dateAt(year: 2024, month: 9, day: 15),
            listName: listName),
        showDate: showDate,
        showList: showList)
}
```

(The factory previously built a real `EKReminder(eventStore:)`; replace with direct-init
`ReminderDisplay` — no EventKit dependency needed anymore.)

#### 5. Extend `ReminderDisplay` mapping tests
**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify

Add tests alongside the existing field-mapping tests:

```swift
@Test
func mapsListNameFromCalendarTitle() {
    let reminder = makeReminder(title: "Buy milk")
    let calendar = EKCalendar(for: .reminder, eventStore: reminder.eventStore)
    calendar.title = "Groceries"
    reminder.calendar = calendar
    #expect(ReminderDisplay(reminder: reminder).listName == "Groceries")
}

@Test
func mapsNilListNameWhenCalendarMissing() {
    #expect(ReminderDisplay(reminder: makeReminder(title: "Buy milk")).listName == nil)
}

// extend directConstructorStoresFields with:
//   listName: "Errands"  →  #expect(display.listName == "Errands")
```

### Verification

#### Automated
- [x] `make build` compiles the iOS app + widget extension with zero warnings
      (warnings are errors in this project)
- [x] `make test` (unit-only gate) passes
- [x] Targeted: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/ReminderDisplayTests -only-testing:SingleThreadTests/ShowDateTests` passes

#### Manual
- [ ] Run the app in the simulator: for a reminder in a named calendar, the card shows the
      list name beneath the due-date row in secondary style; a reminder with no calendar
      assignment shows no list-name row.

---

## Phase 2: "Show list" preference end-to-end

### Changes

#### 1. Typed preference wrapper (mirror of `ShowDatePreference`, inverted default)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowListPreference.swift`
**Action**: create

```swift
import Foundation

/// Persists the user's "show list" preference in UserDefaults (shared with the
/// widget via the App Group).
///
/// Unlike `ShowDatePreference`, an absent key resolves to `false`: the feature
/// is new, so missing state must preserve today's card look (no list name).
public struct ShowListPreference {
    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showList") {
        self.defaults = defaults
        self.key = key
    }

    /// Whether the list name is shown. Missing key → `false`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Wire the preference through `ContentView`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

- Add beside the other shared prefs (~line 219):

```swift
@AppStorage("showList", store: AppGroup.defaults)
private var showList = false
```

- Replace the Phase 1 temporary literal in `reminderList`: `showList: showList`
- Pass into the settings sheet — add `showList: $showList` to **both** the iOS and macOS
  `SettingsView(...)` calls.

#### 3. Add the Settings toggle row
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

- Add `showList: Binding<Bool>` parameter to both the iOS and macOS `init`s (place after
  `showDate` for consistency); assign `_showList = showList`.
- Add stored property: `@Binding private var showList: Bool`.
- Add the toggle row directly below the existing "Show Date" row (inside the Form, outside
  any `#if os(iOS)`):

```swift
Toggle(isOn: $showList) {
    Label("Show list", systemImage: "list.bullet")
}
```

- Update **all four** `#Preview` blocks (two iOS, two macOS) to pass
  `showList: .constant(false)` (or `.constant(true)` in one, for visual coverage).

#### 4. Reset the key under `--seed`
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

> Correction vs structure.md: `resetPersistedState()` lives here, not in
> `SingleThreadApp.swift`.

```swift
private static let persistedKeys = [
    "skippedReminderIdentifiers",
    "excludedProjectTitles",
    "showDate",
    "showList",          // ← add
    "showUndatedReminders",
    // ... rest unchanged
]
```

#### 5. Preference unit tests
**File**: `SingleThreadTests/ShowListPreferenceTests.swift`
**Action**: create (mirror `ShowDatePreferenceTests.swift` with inverted assertions)

Three tests, each with a fresh `"showlist-test-\(UUID().uuidString)"` key on
`UserDefaults.standard` and `defer` cleanup:
- `missingKeyDefaultsToDisabled` — `#expect(!preference.isEnabled)`
- `setTrueRoundTrips` — `set(true)` → `#expect(preference.isEnabled)`
- `setFalseRoundTrips` — `set(false)` → `#expect(!preference.isEnabled)`

#### 6. Settings row assertion
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify — add to both init branches: `showList: .constant(true)`; add assertion
`#expect(bodyDescription.contains("Show list"))`.

#### 7. Relaunch-persistence UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

New test modeled on `testBackgroundToggleHidesAndPersistsAcrossRelaunch`, but inverted
(default off → flipped on → stays on):

```swift
@MainActor
func testShowListTogglePersistsAcrossRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    app.buttons["Settings"].tap()

    let toggle = app.switches["Show list"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    XCTAssertEqual(toggle.value as? String, "0", "Show list should default to off")
    app.swipeUp()  // reveal lower rows if needed before flipping
    XCTAssertTrue(flipToggle(toggle, target: "1"), "Tapping should enable Show list")

    app.buttons["Done"].tap()
    app.terminate()

    let relaunched = XCUIApplication()
    relaunched.launchArguments = ["--ui-testing"]
    relaunched.launch()
    relaunched.buttons["Settings"].tap()
    let persistedToggle = relaunched.switches["Show list"]
    XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(persistedToggle.value as? String, "1",
        "Show-list-on should persist across relaunch")
}
```

(`--ui-testing`, not `--seed`: seeding wipes persisted keys via `resetPersistedState()`.)

### Verification

#### Automated
- [ ] `make test` passes (includes `ShowListPreferenceTests`, updated `SettingsViewTests`)
- [ ] Targeted UI test: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testShowListTogglePersistsAcrossRelaunch` passes

#### Manual
- [ ] Settings → toggle "Show list" off (default): the list-name row disappears from the
      iOS card even when the reminder belongs to a named calendar
- [ ] Toggle on: the row reappears without an app restart

---

## Phase 3: Widget honors the same preference

### Changes

#### 1. Entry gains `showsList`
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

```swift
struct NextThingEntry: TimelineEntry {
    // ... existing State enum ...
    let date: Date
    let state: State
    let showsDate: Bool
    let showsList: Bool
}
```

Populate at **every** initializer site:
- `placeholder(in:)` and `getSnapshot` → `showsList: true`
- `makeEntry()` — compute once next to `showsDate`:
  `let showsList = ShowListPreference().isEnabled`, then pass `showsList: showsList` in
  all four returns (empty, allDone guard-fallback, reminder, noAccess)
- All three `#Preview` timelines → add `showsList:` (use `true` in the "Reminder" preview
  and give its display `listName: "Groceries"`; `true` in "No Access"/"All Done")

#### 2. Render the list name near the date line
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify (in `reminderView(_:)`)

```swift
if entry.showsDate, let dueDate = display.dueDate {
    Text(dueDate, style: .date)
        .font(.caption)
        .foregroundStyle(.secondary)
}
if entry.showsList, let listName = display.listName, !listName.isEmpty {
    Text(listName)
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

No refresh wiring added: the provider re-reads `AppGroup.defaults` at timeline build time
(same as `showsDate`), per design decision 6.

### Verification

#### Automated
- [ ] `make build` — widget extension compiles with zero warnings
- [ ] `make test` passes

#### Manual
- [ ] Xcode canvas previews of `NextThingWidget`: "Reminder" preview shows "Groceries"
      under the date; setting `showsList: false` hides it
- [ ] On simulator: add the widget to the home screen; toggling "Show list" in the iOS app
      then rebuilding the timeline (widget refresh / re-add) shows/hides the list name —
      both surfaces read the single `showList` App Group key

---

## Phase 4: Sentence-case label normalization

### Changes

#### 1. Rename visible labels (storage keys unchanged)
**File**: `SingleThread/SettingsView.swift`
**Action**: modify — five label strings in the Form:

| Old | New |
|---|---|
| `Label("Allow Landscape", systemImage: "rectangle.landscape.rotate")` | `"Allow landscape"` |
| `Label("Show Microphone", systemImage: "microphone")` | `"Show microphone"` |
| `Label("Enable action buttons", systemImage: "hand.tap")` | `"Show action buttons"` |
| `Label("Show Undated", systemImage: "calendar.badge.minus")` | `"Show undated reminders"` |
| `Label("Show Date", systemImage: "calendar")` | `"Show date"` |

Section headers ("Appearance", "Text Size", "Sort By", "Background", "Background Fade",
"Excluded Projects") stay as-is per design decision 4.

#### 2. Update unit-test assertions
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

```swift
#expect(bodyDescription.contains("Show undated reminders"))
#expect(bodyDescription.contains("Show date"))
#expect(bodyDescription.contains("Show list"))
#if os(iOS)
    #expect(bodyDescription.contains("Allow landscape"))
    #expect(bodyDescription.contains("Show action buttons"))
#endif
```

(`contains("Microphone")` / `contains("Landscape")` substrings still match the renamed
labels, but tighten them to the exact new strings anyway so casing regressions are caught.)

#### 3. Update text-matched XCUI queries
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify — line ~138:

```swift
XCTAssertTrue(
    app.staticTexts["Show date"].waitForExistence(timeout: 3),
    "Settings should show Show date (after scrolling)")
```

Grep confirms these are the only test/XCUI references to the renamed strings (verified:
`rg "Show Date|Allow Landscape|Show Microphone|Enable action buttons|Show Undated"` over
`SingleThreadTests/`, `SingleThreadUITests/`, `SingleThreadWatch/` matches only the sites
above). Re-run this grep during implementation in case Phase 2–3 additions introduced new
matches (e.g. the new "Show list" row must not be confused by a broad "Show" query — it
isn't, queries match full strings).

### Verification

#### Automated
- [ ] `./scripts/test.sh` — full CI-equivalent gate passes (format, lint, build, Periphery,
      unit tests, UI tests incl. accessibility audit)
- [ ] `grep -rn "Show Undated\|Enable action buttons\|Allow Landscape\|Show Microphone\"" SingleThread*/ SingleThreadTests/ SingleThreadUITests/` returns no matches

#### Manual
- [ ] Settings rows read sentence-cased on iPhone; macOS branch (same bindings, ungated
      rows) renders sensibly

---

## Testing Checkpoints (from structure.md)

- **After Phase 1**: `ReminderDisplayTests` covers `listName` mapping; card snapshot tests
  cover list-name row shown-with-data / hidden-when-nil; no remaining `EKReminder` inputs to
  `ReminderCardView` anywhere (`rg -n "ReminderCardView\\(" ` shows only the
  `display:` signature).
- **After Phase 2**: `showList` round-trips, defaults `false` on missing key, resets under
  `--seed`, persists across relaunch in the UI test, and gates the card row.
- **After Phase 3**: Widget renders list name iff shared pref is on AND data exists; both
  surfaces read the single `showList` App Group key.
- **After Phase 4**: Full CI-equivalent gate green; no test references old label strings.
