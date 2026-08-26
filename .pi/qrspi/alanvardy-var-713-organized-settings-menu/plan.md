# Implementation Plan

## Overview

Organize the single flat `SettingsView` `Form` into a root `List` menu with four themed sub-views, bound through a single `@Observable` `SettingsBindings` bag. Fix `showList` watch sync as a prerequisite slice, then extract UI groups one at a time.

---

## Phase 1: Show List Watch Sync

**What it delivers**: `showList` preference flows from phone to watch via the existing `pushAll()` combined-snapshot path, matching how `showDate`/`showRecurrence`/`showAlarms` already sync. No UI changes.

### Changes

#### 1. Add `showListStore` and `sendsShowList` to `SkippedReminderSyncService.init`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Insert new params after `showAlarmsStore` (line ~46):

```swift
public init(
    session: any SkipSyncSession,
    skipStore: SkippedReminderStore,
    excludeStore: ExcludedListStore = ExcludedListStore(),
    sortStore: SortOptionStore = SortOptionStore(),
    showUndatedStore: ShowUndatedRemindersPreference = ShowUndatedRemindersPreference(),
    showDateStore: ShowDatePreference = ShowDatePreference(),
    showRecurrenceStore: ShowRecurrencePreference = ShowRecurrencePreference(),
    showAlarmsStore: ShowAlarmsPreference = ShowAlarmsPreference(),
    showListStore: ShowListPreference = ShowListPreference(),  // NEW
    sendsShowDate: Bool = true,
    sendsShowRecurrence: Bool = true,
    sendsShowAlarms: Bool = true,
    sendsShowList: Bool = true) {                               // NEW

    // ... existing stores ...
    self.showListStore = showListStore                          // NEW
    self.sendsShowList = sendsShowList                          // NEW
}
```

Add stored properties alongside existing `sendsShow*` properties (after `sendsShowAlarms`, ~line 265):

```swift
private let showListStore: ShowListPreference      // NEW
private let sendsShowList: Bool                    // NEW
```

#### 2. Add `showList` PayloadKey
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

In `PayloadKey` enum (after `showAlarms`, ~line 251):

```swift
static let showList = "showList"  // NEW
```

#### 3. Include `showList` in `pushAll()`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

In `pushAll()` after the `sendsShowAlarms` block (~line 142):

```swift
if sendsShowList {                                    // NEW
    context[PayloadKey.showList] = showListStore.isEnabled  // NEW
}                                                     // NEW
```

#### 4. Decode `showList` in `apply(context:)`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

In `apply(context:)` after the `showAlarms` decode block (~line 295):

```swift
if let showList = context[PayloadKey.showList] as? Bool {  // NEW
    showListStore.set(showList)                              // NEW
    let handler = onShowListReceived                         // NEW
    handler?(showList)                                       // NEW
}                                                            // NEW
```

#### 5. Add `onShowListReceived` hook property
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

After the `onShowAlarmsReceived` property (~line 105):

```swift
/// Hook fired on the counterpart when the "show list" preference arrives
/// in an application context. Same write-once-before-activate /
/// `nonisolated(unsafe)` rationale as `onShowDateReceived`.
public nonisolated(unsafe) var onShowListReceived: ((Bool) -> Void)?
```

#### 6. Add `showList` comparison in `AppViewModel.handlePreferencesChanged()`
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In the `#if os(iOS)` block, `handlePreferencesChanged()` (~line 178):

```swift
// ADD after lastShowAlarms declaration (~line 194):
private var lastShowList = ShowListPreference().isEnabled

// In handlePreferencesChanged() body, add after currentShowAlarms:
let currentShowList = ShowListPreference().isEnabled          // NEW

// Update the OR condition:
if currentShowDate != lastShowDate
    || currentShowRecurrence != lastShowRecurrence
    || currentShowAlarms != lastShowAlarms
    || currentShowList != lastShowList {                      // NEW
    lastShowDate = currentShowDate
    lastShowRecurrence = currentShowRecurrence
    lastShowAlarms = currentShowAlarms
    lastShowList = currentShowList                            // NEW
    syncService?.pushAll()
}
```

#### 7. Add `sendsShowList: false` to watch-side service init
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

In `setupSyncService()` (~line 117), add to the existing `sendsShow*: false` chain:

```swift
let service = SkippedReminderSyncService(
    session: WCSession.default,
    skipStore: SkippedReminderStore(),
    showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
    showDateStore: ShowDatePreference(defaults: .standard),
    showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
    showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
    sendsShowDate: false, sendsShowRecurrence: false,
    sendsShowAlarms: false, sendsShowList: false)  // ← adds sendsShowList: false
```

(All other `SkippedReminderSyncService` call sites across the project get the default `showListStore: ShowListPreference()` and `sendsShowList: true` automatically — no changes needed.)

#### 8. Add new test functions to `WatchSyncPipelineTests`
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify

Add four new `@Test` functions inside `WatchSyncPipelineTests` struct, following the `receiveAppliesShowRecurrenceAndShowAlarms` / `showRecurrenceSurvivesRelaunch` pattern:

```swift
@Test
func receiveAppliesShowList() {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let showListStore = ShowListPreference(defaults: .standard, key: "wtest-sl-\(suffix)")
    showListStore.set(false)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-sl-ids-\(suffix)"),
        showListStore: showListStore)
    
    var showListValues: [Bool] = []
    service.onShowListReceived = { showListValues.append($0) }
    
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["showList": true])
    
    #expect(showListStore.isEnabled)
    #expect(showListValues == [true])
}

@Test
func receiveAbsentShowListKeyIsNoOp() {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let showListStore = ShowListPreference(defaults: .standard, key: "wtest-absent-sl-\(suffix)")
    showListStore.set(false)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-absent-sl-ids-\(suffix)"),
        showListStore: showListStore)
    
    var fired = false
    service.onShowListReceived = { _ in fired = true }
    
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])
    
    #expect(!showListStore.isEnabled)
    #expect(!fired)
}

@Test
func showListSurvivesRelaunch() {
    let key = "wtest-relaunch-sl-\(UUID().uuidString)"
    let fake = WatchFakeSession()
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
        showListStore: ShowListPreference(defaults: .standard, key: key))
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["showList": true])
    let freshStore = ShowListPreference(defaults: .standard, key: key)
    #expect(freshStore.isEnabled)
}

@Test
func pushAllFromWatchOmitsShowListWhenFlagged() throws {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-sl-skip-\(suffix)")
    skipStore.save(["A"])
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        excludeStore: ExcludedListStore(defaults: .standard, key: "wtest-push-sl-excl-\(suffix)"),
        sortStore: SortOptionStore(defaults: .standard, key: "wtest-push-sl-sort-\(suffix)"),
        showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-push-sl-und-\(suffix)"),
        showDateStore: ShowDatePreference(defaults: .standard, key: "wtest-push-sl-date-\(suffix)"),
        showListStore: ShowListPreference(defaults: .standard, key: "wtest-push-sl-\(suffix)"),
        sendsShowDate: false, sendsShowList: false)
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["showDate"] == nil)
    #expect(context["showList"] == nil)  // ← the new assertion
    #expect(context["showRecurrence"] != nil)
    #expect(context["showAlarms"] != nil)
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` — all WatchSyncPipelineTests pass
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all existing unit tests still green
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` — builds green

#### Manual
- [ ] No UI changes — the showList toggle already exists in Settings and persists to AppGroup. After this phase, toggling Show list on iPhone will push the value to a paired watch. Verify by checking that `showList` appears in the app context when a change triggers `pushAll()`.

---

## Phase 2: SettingsBindings Bag + Interface Sub-View

**What it delivers**: A single `@MainActor @Observable` `SettingsBindings` class replaces the 15–17 `@Binding` props in `SettingsView.init`. `InterfaceSettingsView` is extracted, proving the `@Observable` + `.onChange` pattern works. The root `Form` adds a `NavigationLink` to "Interface" while keeping inline rows temporarily (transitional — cleaned up in Phase 4).

### Changes

#### 1. Create `SettingsBindings` class
**File**: `SingleThread/SettingsBindings.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

/// Single bag of all @AppStorage-backed preference values, passed down from
/// SettingsView to sub-views via @Bindable. Owned by SettingsView; mirrors the
/// @AppStorage defaults from ContentView exactly.
@MainActor
@Observable
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

    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        #if os(iOS)
            allowsLandscape: Bool = true,
            enableActionButtons: Bool = false,
        #endif
        showMicrophoneButton: Bool = true,
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = 50,
        showUndatedReminders: Bool = false,
        excludedLists: Set<String> = [],
        sortOption: SortOption = .priority,
        showDate: Bool = true,
        showList: Bool = false,
        showRecurrence: Bool = true,
        showAlarms: Bool = true
    ) {
        self.appearanceMode = appearanceMode
        self.textSize = textSize
        #if os(iOS)
            self.allowsLandscape = allowsLandscape
            self.enableActionButtons = enableActionButtons
        #endif
        self.showMicrophoneButton = showMicrophoneButton
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.showUndatedReminders = showUndatedReminders
        self.excludedLists = excludedLists
        self.sortOption = sortOption
        self.showDate = showDate
        self.showList = showList
        self.showRecurrence = showRecurrence
        self.showAlarms = showAlarms
    }
}
```

#### 2. Create `InterfaceSettingsView`
**File**: `SingleThread/InterfaceSettingsView.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

/// Interface preferences: appearance, text size, and platform-gated
/// orientation + action button toggles. Bound through the shared
/// @Observable SettingsBindings bag.
struct InterfaceSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker("Appearance", selection: $bindings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            Picker("Text Size", selection: $bindings.textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            }
            #if os(iOS)
                Toggle(isOn: $bindings.allowsLandscape) {
                    Label("Allow landscape", systemImage: "rectangle.landscape.rotate")
                }
                .onChange(of: bindings.allowsLandscape) { _, newValue in
                    viewModel.allowsLandscapeChanged(newValue)
                }
            #endif
            Toggle(isOn: $bindings.showMicrophoneButton) {
                Label("Show microphone", systemImage: "microphone")
            }
            #if os(iOS)
                Toggle(isOn: $bindings.enableActionButtons) {
                    Label("Show action buttons", systemImage: "hand.tap")
                }
            #endif
        }
        .navigationTitle("Interface")
    }
}

// MARK: - Previews

#if os(iOS)
    #Preview("Default") {
        NavigationStack {
            InterfaceSettingsView(
                bindings: SettingsBindings(),
                viewModel: SettingsViewModel())
        }
    }
#else
    #Preview("Default") {
        NavigationStack {
            InterfaceSettingsView(
                bindings: SettingsBindings(),
                viewModel: SettingsViewModel())
        }
    }
#endif
```

#### 3. Rewrite `SettingsView` init to accept `SettingsBindings`
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace both platform-gated inits (lines ~77–154) with a single init:

```swift
struct SettingsView: View {
    // MARK: Lifecycle

    init(
        bindings: SettingsBindings,
        backgroundPhotographer: String?,
        backgroundPhotographerURL: URL?,
        availableLists: [String],
        viewModel: SettingsViewModel = SettingsViewModel()
    ) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.backgroundPhotographer = backgroundPhotographer
        self.backgroundPhotographerURL = backgroundPhotographerURL
        self.availableLists = availableLists
    }
```

Replace all `@Binding private var` properties (lines ~267–282) with:

```swift
    // MARK: Private

    @Bindable private var bindings: SettingsBindings
    @Environment(\.dismiss) private var dismiss
    private let viewModel: SettingsViewModel
    private let backgroundPhotographer: String?
    private let backgroundPhotographerURL: URL?
    private let availableLists: [String]
```

Update body to use `$bindings.<key>` instead of `$<key>` for all rows. Add a `NavigationLink` to Interface at the top of the Form, while keeping the inline Interface rows underneath (transitional):

```swift
var body: some View {
    NavigationStack {
        Form {
            // NEW: NavigationLink to Interface sub-view (transitional)
            Section {
                NavigationLink {
                    InterfaceSettingsView(
                        bindings: bindings,
                        viewModel: viewModel)
                } label: {
                    Label("Interface", systemImage: "paintpalette")
                }
            }
            // Existing rows — all updated to $bindings.<key>:
            Picker("Appearance", selection: $bindings.appearanceMode) { ... }
            Picker("Text Size", selection: $bindings.textSize) { ... }
            // ... all other rows unchanged except $prop → $bindings.prop ...
        }
        .toolbar { ... }  // "Done" stays, uses dismiss()
    }
    .modifier(TextSizeModifier(textSize: bindings.textSize))
}
```

Previews: Update both `#Preview` blocks to construct `SettingsBindings` instead of passing 15–17 `Binding` constants.

#### 4. Update `ContentView` settings sheet construction
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Replace the two platform-gated `SettingsView(...)` construction blocks (~lines 92–115) with a single bag-based construction:

```swift
.sheet(isPresented: $isShowingSettings) {
    let bag = SettingsBindings(
        appearanceMode: appearanceMode,
        textSize: textSize,
        #if os(iOS)
            allowsLandscape: allowsLandscape,
            enableActionButtons: enableActionButtons,
        #endif
        showMicrophoneButton: showMicrophoneButton,
        backgroundEnabled: backgroundEnabled,
        backgroundFadePercent: backgroundFadePercent,
        showUndatedReminders: showUndatedReminders,
        excludedLists: excludedListsBinding.wrappedValue,
        sortOption: sortOption,
        showDate: showDate,
        showList: showList,
        showRecurrence: showRecurrence,
        showAlarms: showAlarms
    )
    SettingsView(
        bindings: bag,
        backgroundPhotographer: viewModel.backgroundImage.photographer,
        backgroundPhotographerURL: viewModel.backgroundImage.photographerURL,
        availableLists: viewModel.store.availableLists,
        viewModel: SettingsViewModel())
}
```

**Note**: `excludedLists` is NOT `@AppStorage` — it's a computed `Binding<Set<String>>` backed by `viewModel.store.excludedListTitles`. The binding is a read of exclusion state at sheet-open time, consistent with the existing behavior; the binding in `SettingsBindings` is mutated via the binding, but the `set` side of ContentView's `excludedListsBinding` is what persists it. This is safe because the ExcludedListsView writes through `$bindings.excludedLists` and ContentView reads the snapshot at sheet-open — the only mutation path for excluded lists goes through the store anyway. We'll maintain the existing write path: `excludedListsBinding` setter calls `viewModel.setExcludedListTitles()` which persists + fires sync hooks. The bag's `excludedLists` property serves only as a conduit; ContentView's `excludedListsBinding` remains unused after the bag is populated.

Wait — `excludedListsBinding` is a two-way binding. Currently it's passed as `$excludedLists` directly to `SettingsView` which passes it to `ExcludedListsView`. With the bag, ExcludedListsView modifies `$bindings.excludedLists` but there's no path to call `viewModel.setExcludedListTitles()`. 

**Fix**: Add `onChange(of: bindings.excludedLists)` to `FilterSortSettingsView` (in Phase 3) that calls `viewModel.setExcludedListTitles()` via a new closure. Or better: keep `excludedListsBinding` out of the bag and pass it separately to `FilterSortSettingsView`.

Actually, the cleanest approach: keep `excludedListsBinding` as a separate param on `FilterSortSettingsView` only. `SettingsBindings` does NOT hold `excludedLists`. The bag holds the `@AppStorage` preferences only. `excludedLists` stays out of the bag and is passed directly to `FilterSortSettingsView` via `Binding<Set<String>>`.

**Revised SettingsBindings**: Remove `excludedLists` from the class entirely. The `ExcludedListsView` inside `FilterSortSettingsView` receives `Binding<Set<String>>` directly as a separate param.

#### 5. Add focused test for `InterfaceSettingsView`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add new test function:

```swift
@Test
func interfaceSettingsViewContainsExpectedRows() {
    let view = InterfaceSettingsView(
        bindings: SettingsBindings(),
        viewModel: SettingsViewModel())
    let bodyDescription = String(describing: view.body)

    var expectedLabels = [
        "Appearance", "Text Size", "Show microphone"
    ]
    #if os(iOS)
        expectedLabels += ["Allow landscape", "Show action buttons"]
    #endif
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }
}
```

Update the existing `settingsViewContainsAllPreferenceRows` to remove Interface labels from `commonLabels`:

```swift
// Remove from commonLabels: "Appearance", "Text Size", "Show microphone"
// Updated list:
let commonLabels = [
    "Sort By", "Background", "Background Fade", "Unsplash",
    "Show undated reminders", "Show date", "Show list",
    "Recurrence indicator", "Reminder alerts", "Excluded Lists", "Done"
]
// Remove iOS-only: "Allow landscape", "Show action buttons" (no longer in commonLabels)
#if os(iOS)
    // No iOS-only additions needed for this phase
#endif
```

Also update the `settingsView()` helper to construct via `SettingsBindings` instead of 15–17 `Binding` constants.

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` — builds green
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` — both old (updated) and new test pass
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all unit tests green

#### Manual
- [ ] Open settings → "Interface" NavigationLink visible at top → tap pushes to Interface sub-view showing Appearance, Text Size, Show microphone, and (iOS) Allow landscape + Show action buttons
- [ ] **Risk check**: Toggle "Allow landscape" in Interface sub-view → verify orientation lock applies. If `.onChange(of: bindings.allowsLandscape)` does NOT fire, switch to `.onChange(of: [$bindings.allowsLandscape])` or pass `allowsLandscape` as a direct `@Binding` to this sub-view only (fallback)

---

## Phase 3: Reminder + Filtering & Sorting Sub-Views

**What it delivers**: Two more sub-views. `ReminderSettingsView` owns the three widget-reload `.onChange` hooks. `FilterSortSettingsView` includes the `NavigationLink` to `ExcludedListsView`. Both bound through `SettingsBindings`.

### Changes

#### 1. Create `ReminderSettingsView`
**File**: `SingleThread/ReminderSettingsView.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

/// Widget-reload-affecting display preferences: show date, show list,
/// recurrence indicator, and reminder alerts.
struct ReminderSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle(isOn: $bindings.showDate) {
                Label("Show date", systemImage: "calendar")
            }
            #if os(iOS) || os(macOS)
                .onChange(of: bindings.showDate) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
            Toggle(isOn: $bindings.showList) {
                Label("Show list", systemImage: "list.bullet")
            }
            Toggle(isOn: $bindings.showRecurrence) {
                Label("Recurrence indicator", systemImage: "repeat")
            }
            #if os(iOS) || os(macOS)
                .onChange(of: bindings.showRecurrence) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
            Toggle(isOn: $bindings.showAlarms) {
                Label("Reminder alerts", systemImage: "bell")
            }
            #if os(iOS) || os(macOS)
                .onChange(of: bindings.showAlarms) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
        }
        .navigationTitle("Reminder")
    }
}

// MARK: - Previews

#if os(iOS)
    #Preview("Default") {
        NavigationStack {
            ReminderSettingsView(
                bindings: SettingsBindings(),
                viewModel: SettingsViewModel())
        }
    }
#else
    #Preview("Default") {
        NavigationStack {
            ReminderSettingsView(
                bindings: SettingsBindings(),
                viewModel: SettingsViewModel())
        }
    }
#endif
```

#### 2. Create `FilterSortSettingsView` (includes `ExcludedListsView`)
**File**: `SingleThread/FilterSortSettingsView.swift` (new)
**Action**: create

Move `ExcludedListsView` into this file (no other changes to it). Add the new FilterSortSettingsView:

```swift
import SingleThreadCore
import SwiftUI

// MARK: - ExcludedListsView

/// (moved from SettingsView.swift verbatim — no code changes)
struct ExcludedListsView: View { ... }

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, show-undated toggle,
/// and the Excluded Lists sub-menu.
struct FilterSortSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let availableLists: [String]
    /// Binding to the store-backed excluded list set (NOT @AppStorage).
    @Binding var excludedLists: Set<String>

    var body: some View {
        Form {
            Picker("Sort By", selection: $bindings.sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            Toggle(isOn: $bindings.showUndatedReminders) {
                Label("Show undated reminders", systemImage: "calendar.badge.minus")
            }
            Section {
                NavigationLink {
                    ExcludedListsView(
                        excludedLists: $excludedLists,
                        availableLists: availableLists)
                } label: {
                    Label("Excluded Lists", systemImage: "eye.slash")
                }
            }
        }
        .navigationTitle("Filtering & Sorting")
    }
}

// MARK: - Previews

...  // standard preview blocks
```

#### 3. Update `SettingsView` body — add NavigationLinks for Reminder and FilterSort
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Add two more `NavigationLink` rows in the root `Form` (next to the Interface one added in Phase 2), but keep the inline rows until Phase 4. The NavigationLinks go into the same `Section` as Interface:

```swift
Section {
    NavigationLink {
        InterfaceSettingsView(bindings: bindings, viewModel: viewModel)
    } label: { Label("Interface", systemImage: "paintpalette") }
    NavigationLink {
        ReminderSettingsView(bindings: bindings, viewModel: viewModel)
    } label: { Label("Reminder", systemImage: "bell.badge") }
    NavigationLink {
        FilterSortSettingsView(
            bindings: bindings,
            availableLists: availableLists,
            excludedLists: $excludedListsBinding)
    } label: { Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease") }
}
```

SettingsView needs `excludedListsBinding` as a param. Add it back to init:

```swift
init(
    bindings: SettingsBindings,
    backgroundPhotographer: String?,
    backgroundPhotographerURL: URL?,
    availableLists: [String],
    excludedLists: Binding<Set<String>>,  // NEW: passed through to FilterSortSettingsView
    viewModel: SettingsViewModel = SettingsViewModel()
)
```

Remove `excludedLists` from `SettingsBindings` (it was added in Phase 2 plan; never needed — `excludedLists` stays as a separate `Binding`).

#### 4. Remove `ExcludedListsView` from `SettingsView.swift`
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Delete the `ExcludedListsView` struct definition (lines ~13–72). It now lives in `FilterSortSettingsView.swift`.

#### 5. Update `ContentView` — add `excludedListsBinding` passthrough
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the sheet construction, pass `excludedLists: excludedListsBinding` (the computed `Binding<Set<String>>`) as a separate param to `SettingsView`:

```swift
SettingsView(
    bindings: bag,
    backgroundPhotographer: ...,
    backgroundPhotographerURL: ...,
    availableLists: ...,
    excludedLists: excludedListsBinding,  // NEW: replaces bag.excludedLists
    viewModel: SettingsViewModel())
```

#### 6. Add focused tests
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add two new test functions:

```swift
@Test
func reminderSettingsViewContainsExpectedRows() {
    let view = ReminderSettingsView(
        bindings: SettingsBindings(),
        viewModel: SettingsViewModel())
    let bodyDescription = String(describing: view.body)
    let expectedLabels = [
        "Show date", "Show list", "Recurrence indicator", "Reminder alerts"
    ]
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }
}

@Test
func filterSortSettingsViewContainsExpectedRows() {
    let view = FilterSortSettingsView(
        bindings: SettingsBindings(),
        availableLists: ["Work"],
        excludedLists: .constant([]))
    let bodyDescription = String(describing: view.body)
    let expectedLabels = [
        "Sort By", "Show undated reminders", "Excluded Lists"
    ]
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }
}
```

Update `settingsViewContainsAllPreferenceRows` to remove the labels that moved to Reminder and FilterSort sub-views:

```swift
// Remaining commonLabels (Background group only):
let commonLabels = [
    "Background", "Background Fade", "Unsplash", "Done"
]
// No iOS-only labels remain
```

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` — builds green
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` — all four focused tests pass, old test (Background-only) passes
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all unit tests green

#### Manual
- [ ] Settings menu shows "Interface", "Reminder", "Filtering & Sorting" NavigationLinks
- [ ] Tap Reminder → Show date / Show list / Recurrence indicator / Reminder alerts toggles visible
- [ ] Tap Filtering & Sorting → Sort By picker, Show undated toggle, Excluded Lists NavigationLink visible
- [ ] Toggle Show date → widget reload fires (verify WidgetKit console or check widget timeline)

---

## Phase 4: Background Sub-View + Root List Menu

**What it delivers**: Final sub-view extracted. Root `Form` replaced by `List` with four `NavigationLink` rows. SettingsView shrinks to ~120 lines. The old `settingsViewContainsAllPreferenceRows` test is retired.

### Changes

#### 1. Create `BackgroundSettingsView`
**File**: `SingleThread/BackgroundSettingsView.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

/// Background preferences: toggle, fade percentage, and Unsplash photo credit.
struct BackgroundSettingsView: View {
    @Bindable var bindings: SettingsBindings
    let backgroundPhotographer: String?
    let backgroundPhotographerURL: URL?

    var body: some View {
        Form {
            Toggle(isOn: $bindings.backgroundEnabled) {
                Label("Background", systemImage: "photo")
            }
            Picker("Background Fade", selection: $bindings.backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            Section {
            } footer: {
                if let backgroundPhotographer {
                    if let backgroundPhotographerURL {
                        Link(
                            "Photo by \(backgroundPhotographer) on Unsplash",
                            destination: backgroundPhotographerURL)
                    } else {
                        Text("Photo by \(backgroundPhotographer) on Unsplash")
                    }
                }
            }
        }
        .navigationTitle("Background")
    }
}

// MARK: - Previews

#if os(iOS)
    #Preview("Default") {
        NavigationStack {
            BackgroundSettingsView(
                bindings: SettingsBindings(),
                backgroundPhotographer: "NEOM",
                backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"))
        }
    }
#else
    #Preview("Default") {
        NavigationStack {
            BackgroundSettingsView(
                bindings: SettingsBindings(),
                backgroundPhotographer: "NEOM",
                backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"))
        }
    }
#endif
```

#### 2. Rewrite `SettingsView` body — List root, remove inline rows
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace the entire `Form` body with a `List` of four `NavigationLink` rows:

```swift
var body: some View {
    NavigationStack {
        List {
            NavigationLink {
                InterfaceSettingsView(bindings: bindings, viewModel: viewModel)
            } label: {
                Label("Interface", systemImage: "paintpalette")
            }
            NavigationLink {
                ReminderSettingsView(bindings: bindings, viewModel: viewModel)
            } label: {
                Label("Reminder", systemImage: "bell.badge")
            }
            NavigationLink {
                FilterSortSettingsView(
                    bindings: bindings,
                    availableLists: availableLists,
                    excludedLists: $excludedLists)
            } label: {
                Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease")
            }
            NavigationLink {
                BackgroundSettingsView(
                    bindings: bindings,
                    backgroundPhotographer: backgroundPhotographer,
                    backgroundPhotographerURL: backgroundPhotographerURL)
            } label: {
                Label("Background", systemImage: "photo.on.rectangle")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
    .modifier(TextSizeModifier(textSize: bindings.textSize))
}
```

Remove `@Bindable` from the stored property — with the root List there are no inline bindings needed on `SettingsView` itself. The `bindings` is just a regular stored property passed to sub-views:

```swift
private var bindings: SettingsBindings  // (no longer @Bindable — no inline bindings in root body)
```

#### 3. Update `SettingsView` init — add `excludedLists` binding param
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

```swift
init(
    bindings: SettingsBindings,
    backgroundPhotographer: String?,
    backgroundPhotographerURL: URL?,
    availableLists: [String],
    excludedLists: Binding<Set<String>>,
    viewModel: SettingsViewModel = SettingsViewModel()
) {
    self.bindings = bindings
    self.viewModel = viewModel
    self.backgroundPhotographer = backgroundPhotographer
    self.backgroundPhotographerURL = backgroundPhotographerURL
    self.availableLists = availableLists
    _excludedLists = excludedLists
}

// ...

@Binding private var excludedLists: Set<String>  // ← kept for FilterSortSettingsView passthrough
```

#### 4. Add focused test for `BackgroundSettingsView`, retire old monolithic test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Delete `settingsViewContainsAllPreferenceRows` test function. Delete `settingsView()` helper. Add:

```swift
@Test
func backgroundSettingsViewContainsExpectedRows() {
    let view = BackgroundSettingsView(
        bindings: SettingsBindings(),
        backgroundPhotographer: "NEOM",
        backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom")!)
    let bodyDescription = String(describing: view.body)
    let expectedLabels = ["Background", "Background Fade", "Unsplash"]
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }
}
```

#### 5. Update previews in `SettingsView.swift`
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace the old 17-arg / 15-arg preview blocks with bag-based construction:

```swift
#if os(iOS)
    #Preview("Default") {
        SettingsView(
            bindings: SettingsBindings(),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"),
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]))
    }
#else
    #Preview("Default") {
        SettingsView(
            bindings: SettingsBindings(),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"),
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]))
    }
#endif
```

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` — builds green
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all unit tests pass (four focused SettingsViewTests + all other test suites)
- [x] `make periphery` — no new dead code warnings

#### Manual
- [ ] Settings opens to a clean four-row menu with icons: Interface, Reminder, Filtering & Sorting, Background
- [ ] Each row pushes to correct sub-view
- [ ] Done button dismisses the sheet
- [ ] All toggles, pickers, and Excluded Lists functionality unchanged
- [ ] TextSizeModifier applies to all pushed sub-views (scaled text)

---

## Phase 5: UI Test Adjustments + Final Gate

**What it delivers**: UI tests updated for the new navigation structure. Toggle-persistence relaunch tests navigate into sub-views instead of swiping. Full `./scripts/test.sh` gate passes.

### Changes

#### 1. `testSettingsOpensAndShowsControls` — navigate into sub-views
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Replace the current implementation (~lines 126–139):

```swift
@MainActor
func testSettingsOpensAndShowsControls() {
    let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()

    // Navigate into Interface sub-view
    XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3))
    app.staticTexts["Interface"].tap()
    XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Text Size"].waitForExistence(timeout: 2))

    // Back to root, then into Reminder
    app.navigationBars.buttons.firstMatch.tap()
    app.staticTexts["Reminder"].tap()
    XCTAssertTrue(app.staticTexts["Show date"].waitForExistence(timeout: 2))
    
    // Back to root, then into Filtering & Sorting
    app.navigationBars.buttons.firstMatch.tap()
    app.staticTexts["Filtering & Sorting"].tap()
    XCTAssertTrue(app.staticTexts["Sort By"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Excluded Lists"].waitForExistence(timeout: 2))
}
```

#### 2. `testBackgroundToggleHidesAndPersistsAcrossRelaunch` — navigate into Background
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Replace `app.switches["Background"]` direct access with navigation tap:

```swift
@MainActor
func testBackgroundToggleHidesAndPersistsAcrossRelaunch() {
    let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()

    // Navigate into Background sub-view (replaces swipeUp)
    app.staticTexts["Background"].tap()
    let toggle = app.switches["Background"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    XCTAssertEqual(toggle.value as? String, "1", "Background should default to on")
    XCTAssertTrue(flipToggle(toggle), "Tapping should hide the background")

    app.buttons["Done"].tap()
    app.terminate()

    let relaunched = XCUIApplication()
    relaunched.launchArguments = ["--ui-testing"]
    relaunched.launch()
    relaunched.buttons["Settings"].tap()
    relaunched.staticTexts["Background"].tap()  // ← navigate into sub-view
    let persistedToggle = relaunched.switches["Background"]
    XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(
        persistedToggle.value as? String, "0",
        "Background-off should persist across relaunch")
}
```

#### 3. `testShowListTogglePersistsAcrossRelaunch` — navigate into Reminder
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Replace `app.swipeUp()` with navigation tap:

```swift
@MainActor
func testShowListTogglePersistsAcrossRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    app.buttons["Settings"].tap()

    // Navigate into Reminder sub-view (replaces swipeUp)
    app.staticTexts["Reminder"].tap()
    let toggle = app.switches["Show list"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    XCTAssertEqual(toggle.value as? String, "0", "Show list should default to off")
    XCTAssertTrue(flipToggle(toggle, target: "1"), "Tapping should enable Show list")

    app.buttons["Done"].tap()
    app.terminate()

    let relaunched = XCUIApplication()
    relaunched.launchArguments = ["--ui-testing"]
    relaunched.launch()
    relaunched.buttons["Settings"].tap()
    relaunched.staticTexts["Reminder"].tap()  // ← navigate into sub-view
    let persistedToggle = relaunched.switches["Show list"]
    XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(
        persistedToggle.value as? String, "1",
        "Show-list-on should persist across relaunch")
}
```

### Verification

#### Automated
- [ ] `./scripts/test.sh` — full CI pipeline passes: format, lint, periphery, build, unit tests, UI tests (including accessibility audit)
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` — all UI tests pass

#### Manual
- [ ] Settings menu renders four rows, each navigable
- [ ] Background toggle persistence survives relaunch
- [ ] Show list toggle persistence survives relaunch
- [ ] Accessibility audit passes with `List` root (run `testAccessibilityAudit`)

---

## Testing Checkpoints

| After Phase | What must pass | Key manual check |
|---|---|---|
| 1 | `WatchSyncPipelineTests` + existing unit/UI suites | showList appears in sync payload |
| 2 | Build + `SettingsViewTests` (updated old + new interface test) | Tap Interface, toggle landscape → lock |
| 3 | Build + SettingsViewTests (3 sub-view tests + truncated old test) | Tap Reminder, toggle Show date → widget reload |
| 4 | All unit tests + build | Four-row menu visible, each pushes correctly |
| 5 | `./scripts/test.sh` | Full accessibility audit passes with `List` root |

## Risk Mitigations

### `@Observable` `.onChange` risk (Phase 2)

If `.onChange(of: bindings.allowsLandscape)` does not fire when the toggle changes, the fallback is **not** to revert the entire bag. Instead, isolate the risk by passing `allowsLandscape` as a direct `@Binding` to `InterfaceSettingsView` only:

```swift
// Fallback: hybrid approach
struct InterfaceSettingsView: View {
    @Bindable var bindings: SettingsBindings   // for most preferences
    @Binding var allowsLandscape: Bool          // direct @Binding for .onChange
    let viewModel: SettingsViewModel
    
    // ...
}
```

This is verified first (Phase 2) because it's the only risky change. The other phases just replicate the proven pattern.

### `List` vs `Form` accessibility audit (Phase 4–5)

If `testAccessibilityAudit` fails with the `List` root, wrap the `List` with `.accessibilityIdentifier("Settings Menu")` and check if the audit failure is a new issue vs an existing one. The `List` provides the same semantic grouping as `Form` in this context (a single selection of navigation rows), so this is unlikely to cause audit failures.

### UI test `swipeUp()` removed (Phase 5)

All `swipeUp()` calls in settings tests are replaced with navigation taps (`app.staticTexts["<Group>"].tap()`). If any swipe-dependent tests were missed, the `testSettingsOpensAndShowsControls` test will reveal them. Each toggle-persistence test navigates to its group explicitly.