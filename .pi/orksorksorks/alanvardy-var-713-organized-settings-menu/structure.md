# Structure Outline

## Approach

Extract the single flat `SettingsView` `Form` into a root `List` menu pushing
four themed sub-views, bound through a single `@Observable` `SettingsBindings`
bag. Fix `showList` watch sync as an independent first slice. Each phase
crosses model/service/UI layers and is independently testable.

---

## Phase 1: Show List Watch Sync

**What it delivers**: `showList` preference flows from phone to watch via the
existing `pushAll()` combined-snapshot path, matching how `showDate` /
`showRecurrence` / `showAlarms` already sync. No UI changes — the toggle
already exists and persists to `AppGroup.defaults`.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThread/AppViewModel.swift`
- `SingleThreadWatchTests/WatchSyncPipelineTests.swift`

**Key changes**:
```swift
// SkippedReminderSyncService.swift — init (line ~28–53)
showListStore: ShowListPreference = ShowListPreference(),  // new param
sendsShowList: Bool = true,                                 // new param

// PayloadKey enum (line ~244)
static let showList = "showList"                            // new key

// pushAll() (line ~140, after sendsShowAlarms block)
if sendsShowList {
    context[PayloadKey.showList] = showListStore.isEnabled
}

// apply(context:) (line ~280, after showAlarms decode)
if let showList = context[PayloadKey.showList] as? Bool {
    showListStore.set(showList)
    let handler = onShowListReceived
    handler?(showList)
}

// new hook property (near onShowAlarmsReceived)
public nonisolated(unsafe) var onShowListReceived: ((Bool) -> Void)?
```

```swift
// AppViewModel.swift — handlePreferencesChanged() (line ~178)
// Add showList comparison alongside showDate/showRecurrence/showAlarms:
let currentShowList = ShowListPreference().isEnabled
// … include currentShowList != lastShowList in the OR condition
```

```swift
// WatchSyncPipelineTests.swift — new test functions
@Test func receiveAppliesShowList()  // decode + persist + hook fires
@Test func receiveAbsentShowListKeyIsNoOp()
@Test func showListSurvivesRelaunch()
@Test func pushAllFromWatchOmitsShowListWhenFlagged() // sendsShowList: false
```

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadWatchTests/WatchSyncPipelineTests
```
All WatchSyncPipelineTests pass. Existing unit + UI test suite still green.

---

## Phase 2: SettingsBindings Bag + Interface Sub-View

**What it delivers**: A single `@MainActor @Observable` `SettingsBindings`
class replaces the 15–17 `@Binding` props explosion in `SettingsView.init`.
The first sub-view (`InterfaceSettingsView`) is extracted, proving the
pattern works — especially `.onChange` with `@Observable` (the design's
highest-risk change). The user sees "Interface" as a `NavigationLink` row in
the root menu, pushing to the interface settings.

**Files**:
- `SingleThread/SettingsBindings.swift` (new)
- `SingleThread/InterfaceSettingsView.swift` (new)
- `SingleThread/SettingsView.swift` (modified: init accepts bag, body uses bag)
- `SingleThread/ContentView.swift` (modified: construction site)
- `SingleThreadTests/SettingsViewTests.swift` (modified: add focused test)

**Key changes**:
```swift
// SettingsBindings.swift (new)
@MainActor @Observable
final class SettingsBindings {
    var appearanceMode: AppearanceMode
    var textSize: TextSize
    #if os(iOS)
        var allowsLandscape: Bool
        var enableActionButtons: Bool
    #endif
    var showMicrophoneButton: Bool
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var showUndatedReminders: Bool
    var excludedLists: Set<String>
    var sortOption: SortOption
    var showDate: Bool
    var showList: Bool
    var showRecurrence: Bool
    var showAlarms: Bool

    // Mirror ContentView's @AppStorage defaults:
    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        // … etc, matching @AppStorage defaults exactly
    )
}
```

```swift
// InterfaceSettingsView.swift (new)
struct InterfaceSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let viewModel: SettingsViewModel
    // No stored @Bindings — unwraps via $bindings.appearanceMode, etc.

    var body: some View {
        Form {
            Picker("Appearance", selection: $bindings.appearanceMode) { … }
            Picker("Text Size", selection: $bindings.textSize) { … }
            #if os(iOS)
                Toggle(isOn: $bindings.allowsLandscape) { … }
                    .onChange(of: bindings.allowsLandscape) { _, newValue in
                        viewModel.allowsLandscapeChanged(newValue)
                    }
            #endif
            Toggle(isOn: $bindings.showMicrophoneButton) { … }
            #if os(iOS)
                Toggle(isOn: $bindings.enableActionButtons) { … }
            #endif
        }
        .navigationTitle("Interface")
    }
}
```

```swift
// SettingsView.swift — init shrinks (platform-gated):
#if os(iOS)
    init(bindings: SettingsBindings, …)  // ~4 params instead of 17
#else
    init(bindings: SettingsBindings, …)  // ~3 params
#endif
// body: root Form (still, for now) uses $bindings.<key> and renders
// rows by delegating to sub-views via NavigationLink
```

**Verify**:
```fish
xcodebuild -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SettingsViewTests
```
Builds green. New `interfaceSettingsViewContainsExpectedRows` passes. The
existing `settingsViewContainsAllPreferenceRows` still passes (all other rows
still live in SettingsView body). Manual: tap "Interface" → see the four
rows, toggle "Allow landscape" → orientation locks.

**Key risk check**: Verify `.onChange(of: bindings.allowsLandscape)` fires
correctly on the `@Observable` property. If it doesn't, fall back to
`.onChange(of: [$bindings.allowsLandscape])` or observe the binding directly.
This is the design's single riskiest decision — resolved here on the smallest
sub-view before replicating the pattern.

---

## Phase 3: Reminder + Filtering & Sorting Sub-Views

**What it delivers**: Two more sub-views following the Phase 2 pattern.
`ReminderSettingsView` owns the three widget-reload `.onChange` hooks.
`FilterSortSettingsView` includes the `NavigationLink` to `ExcludedListsView`
(which moves into `FilterSortSettingsView.swift`). The user navigates to each
from the root menu.

**Files**:
- `SingleThread/ReminderSettingsView.swift` (new)
- `SingleThread/FilterSortSettingsView.swift` (new, includes ExcludedListsView)
- `SingleThread/SettingsView.swift` (modified: remove extracted rows from body)
- `SingleThreadTests/SettingsViewTests.swift` (modified: two more focused tests)

**Key changes**:
```swift
// ReminderSettingsView.swift (new)
struct ReminderSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle(isOn: $bindings.showDate) { Label("Show date", …) }
                #if os(iOS) || os(macOS)
                    .onChange(of: bindings.showDate) { _, _ in
                        viewModel.showPreferenceChanged()
                    }
                #endif
            Toggle(isOn: $bindings.showList) { Label("Show list", …) }
            Toggle(isOn: $bindings.showRecurrence) { Label("Recurrence indicator", …) }
                #if os(iOS) || os(macOS)
                    .onChange(of: bindings.showRecurrence) { _, _ in
                        viewModel.showPreferenceChanged()
                    }
                #endif
            Toggle(isOn: $bindings.showAlarms) { Label("Reminder alerts", …) }
                #if os(iOS) || os(macOS)
                    .onChange(of: bindings.showAlarms) { _, _ in
                        viewModel.showPreferenceChanged()
                    }
                #endif
        }
        .navigationTitle("Reminder")
    }
}

// FilterSortSettingsView.swift (new)
struct FilterSortSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let availableLists: [String]

    var body: some View {
        Form {
            Picker("Sort By", selection: $bindings.sortOption) { … }
            Toggle(isOn: $bindings.showUndatedReminders) { … }
            Section {
                NavigationLink {
                    ExcludedListsView(
                        excludedLists: $bindings.excludedLists,
                        availableLists: availableLists)
                } label: {
                    Label("Excluded Lists", systemImage: "eye.slash")
                }
            }
        }
        .navigationTitle("Filtering & Sorting")
    }
}
// ExcludedListsView moves into this file (stays a standalone struct)
```

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SettingsViewTests
```
Three focused tests pass: interface, reminder, filterSort. The original
`settingsViewContainsAllPreferenceRows` still passes (Background rows remain
in root body). Build green.

---

## Phase 4: Background Sub-View + Root List Menu

**What it delivers**: The final sub-view extracted. The root `Form` is
replaced by a `List` with four `NavigationLink` rows. The old
`settingsViewContainsAllPreferenceRows` test is retired; only the four
focused sub-view tests remain. The user sees a clean menu-of-menus with
icons.

**Files**:
- `SingleThread/BackgroundSettingsView.swift` (new)
- `SingleThread/SettingsView.swift` (rewritten: root List, cleanup)
- `SingleThreadTests/SettingsViewTests.swift` (modified: replace old test)

**Key changes**:
```swift
// BackgroundSettingsView.swift (new)
struct BackgroundSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let backgroundPhotographer: String?
    let backgroundPhotographerURL: URL?

    var body: some View {
        Form {
            Toggle(isOn: $bindings.backgroundEnabled) { Label("Background", …) }
            Picker("Background Fade", selection: $bindings.backgroundFadePercent) { … }
            Section {
            } footer: {
                // Photo credit footer (moved from root)
            }
        }
        .navigationTitle("Background")
    }
}

// SettingsView.swift — body becomes:
NavigationStack {
    List {
        NavigationLink { InterfaceSettingsView(…) }
            label: { Label("Interface", systemImage: "paintpalette") }
        NavigationLink { ReminderSettingsView(…) }
            label: { Label("Reminder", systemImage: "bell.badge") }
        NavigationLink { FilterSortSettingsView(…) }
            label: { Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease") }
        NavigationLink { BackgroundSettingsView(…) }
            label: { Label("Background", systemImage: "photo.on.rectangle") }
    }
    .toolbar { … }  // "Done" button stays
}
.modifier(TextSizeModifier(textSize: bindings.textSize))
```

```swift
// SettingsViewTests.swift — replace settingsViewContainsAllPreferenceRows
// with backgroundSettingsViewContainsExpectedRows
@Test func backgroundSettingsViewContainsExpectedRows() { … }
// labels: "Background", "Background Fade", "Unsplash"
```

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests
```
All unit tests pass. Build green. Manual: settings opens to a clean four-row
menu; each row pushes to the correct sub-view; all toggles and pickers
function.

---

## Phase 5: UI Test Adjustments + Final Gate

**What it delivers**: UI tests updated for the new navigation structure.
Toggle-persistence relaunch tests now tap into sub-views instead of
swiping. Full `./scripts/test.sh` gate passes.

**Files**:
- `SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:
```swift
// testSettingsOpensAndShowsControls (line ~126)
// Before asserting Appearance / Text Size, navigate into Interface:
app.buttons["Settings"].tap()
app.staticTexts["Interface"].tap()
XCTAssertTrue(app.staticTexts["Appearance"].exists)
XCTAssertTrue(app.staticTexts["Text Size"].exists)
// Navigate back, tap into Reminder, verify "Show date"
app.navigationBars.buttons.firstMatch.tap() // back
app.staticTexts["Reminder"].tap()
XCTAssertTrue(app.staticTexts["Show date"].exists)

// testShowListTogglePersistsAcrossRelaunch (line ~177)
// Replace app.swipeUp() with navigation tap:
app.buttons["Settings"].tap()
app.staticTexts["Reminder"].tap()
let toggle = app.switches["Show list"]  // now visible without swipe
…

// testBackgroundToggleHidesAndPersistsAcrossRelaunch (line ~145)
// Replace direct toggle access with navigation tap:
app.buttons["Settings"].tap()
app.staticTexts["Background"].tap()
let toggle = app.switches["Background"]
…
```

**Verify**:
```fish
./scripts/test.sh
```
All green: format, lint, periphery, build, unit tests, UI tests (including
accessibility audit). No regressions.

---

## Testing Checkpoints

| After Phase | What must pass | Key manual check |
|---|---|---|
| 1 | `WatchSyncPipelineTests` + existing suite | — (no UI change) |
| 2 | Build + `SettingsViewTests` (old + new interface test) | Tap Interface, toggle landscape → lock |
| 3 | Build + SettingsViewTests (3 sub-view tests + old test) | Tap Reminder, toggle Show date → widget reload |
| 4 | All unit tests + build | Four-row menu visible, each pushes correctly |
| 5 | `./scripts/test.sh` | Full accessibility audit passes with `List` root |

If Phase 2 reveals the `@Observable` `.onChange` risk (no callback firing),
pause and either switch to `.onChange(of: [$bindings.allowsLandscape])` or
fall back to direct `@Binding` props on that sub-view. The other phases stay
valid — only the binding transport changes.