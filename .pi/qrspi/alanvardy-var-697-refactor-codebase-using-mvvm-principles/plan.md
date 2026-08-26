# Implementation Plan

## Overview

Introduce an `@Observable @MainActor` ViewModel layer between SwiftUI views and `ReminderStore`, moving presentation state, `.onChange`/`.task` side effects, the dictation lifecycle, and the app-entry composition root out of the views. Each phase is an independently shippable vertical slice.

---

## Phase 1: Store-derived `allSkipped` (foundation)

Move the pure store-derived `allSkipped` predicate into `ReminderStore` and point both view surfaces at it.

### Changes

#### 1. Add `allSkipped` computed property to `ReminderStore`

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Insert after `visibleReminders` (after line 107):

```swift
/// `true` when reminders exist but are all skipped or excluded — i.e. nothing
/// to display in the current view despite a non-empty source list.
public var allSkipped: Bool {
    !reminders.isEmpty && visibleReminders.isEmpty
}
```

#### 2. Remove `allSkipped` from `ContentView`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete the private computed property at lines 253-255:
```swift
private var allSkipped: Bool {
    !store.reminders.isEmpty && store.visibleReminders.isEmpty
}
```

Replace all reads of `allSkipped` with `store.allSkipped`:
- Line ~323 (`if allSkipped {`) → `if store.allSkipped {`
- Line ~271 (`allSkipped` in `visibleReminders` → `store.allSkipped`)

#### 3. Remove `allSkipped` from `WatchReminderView`

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Delete the private computed property at lines 78-80:
```swift
private var allSkipped: Bool {
    store.visibleReminders.isEmpty && !store.reminders.isEmpty
}
```

Replace all reads of `allSkipped` with `store.allSkipped`:
- Line ~88 (`if allSkipped {`) → `if store.allSkipped {`
- Line ~224 (`let clearSkipped = allSkipped` in `refresh()`) → `let clearSkipped = store.allSkipped`

#### 4. Add `allSkipped` unit tests

**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add a new test section after the existing `// MARK: - hasHidden` section, before the `makeReminder` helpers:

```swift
// MARK: - allSkipped

@Test
func allSkippedTrueWhenRemindersExistButAllSkipped() {
    let rem = makeReminder(title: "A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [rem.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
    #expect(store.allSkipped)
}

@Test
func allSkippedFalseWhenRemindersEmpty() {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    #expect(!store.allSkipped)
}

@Test
func allSkippedFalseWhenVisibleRemindersExist() {
    let rem = makeReminder(title: "A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    #expect(!store.allSkipped)
}

@Test
func allSkippedTrueWhenAllExcluded() {
    let rem = makeReminder(title: "A", calendarTitle: "Work")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        excludedListTitles: ["Work"])
    #expect(store.allSkipped)
}
```

### Verification

#### Automated
- [x] `make test` passes — new `ReminderStoreTests.allSkipped*` truth-table tests green; all existing suites still pass
- [x] `make ui-test` passes — "No Reminders"/"All Done" labels render identically
- [x] `make watch-ui-test` passes — watch empty/skipped states render identically

#### Manual
- [ ] Run app on simulator: see a reminder, skip it, verify "All Done" appears
- [ ] Run watch app: skip a reminder, verify "All Done" appears

---

## Phase 2: `DictationViewModel` (dictation lifecycle)

Extract the 4 `@State` vars and `startDictation()` flow from `ContentView` into a dedicated ViewModel with an injectable `SpeechTranscribing` seam.

### Changes

#### 1. Create `DictationViewModel`

**File**: `SingleThread/DictationViewModel.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import Speech
import SwiftUI

@MainActor
@Observable
final class DictationViewModel {
    // MARK: Lifecycle

    init(
        speechTranscriber: any SpeechTranscribing,
        store: ReminderStore) {
        self.speechTranscriber = speechTranscriber
        self.store = store
    }

    // MARK: Internal

    private(set) var isDictating = false
    var dictationText = ""
    var dictationError: String?
    var creationFeedback: CreationFeedback?

    var canDictate: Bool {
        speechTranscriber.authorizationStatus == .authorized
            || speechTranscriber.authorizationStatus == .notDetermined
    }

    func startDictation() async {
        if speechTranscriber.authorizationStatus == .notDetermined {
            let status = await speechTranscriber.requestAuthorization()
            guard status == .authorized else {
                dictationError = "Speech recognition access is required."
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            dictationError = "Speech recognition access was denied."
            return
        }
        isDictating = true
        dictationText = ""
        dictationError = nil
        do {
            let result = try await speechTranscriber.transcribe { [weak self] text in
                self?.dictationText = text
            }
            let parsed = ReminderDictationParser.parse(result)
            if !parsed.title.isEmpty {
                let saved = await store.addReminder(
                    title: parsed.title,
                    notes: nil,
                    dueDate: parsed.dueDateComponents,
                    recurrenceRule: parsed.recurrenceRule)
                if saved {
                    creationFeedback = .success
                } else {
                    creationFeedback = .failure
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                creationFeedback = nil
            }
        } catch {
            dictationError = error.localizedDescription
        }
        isDictating = false
    }

    // MARK: Private

    private let speechTranscriber: any SpeechTranscribing
    private let store: ReminderStore
}
```

#### 2. Update `ContentView` to use `DictationViewModel`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Remove** the 4 `@State` vars (lines 235-238):
```swift
@State private var isDictating = false
@State private var dictationText = ""
@State private var dictationError: String?
@State private var creationFeedback: CreationFeedback?
```

**Remove** `canDictate` computed (lines 257-260) and `startDictation()` method (lines 521-558).

**Add** a `DictationViewModel` stored property and init parameter:
```swift
private let dictationViewModel: DictationViewModel
```

Update the three production inits to accept an optional `speechTranscriber` and construct `DictationViewModel`:
- `init(store:speechTranscriber:backgroundImage:)` — add `dictationViewModel = DictationViewModel(speechTranscriber: ..., store: store)`
- `init(loadsReminders:eventStore:speechTranscriber:backgroundImage:)` — add `dictationViewModel = DictationViewModel(speechTranscriber: ..., store: store)`
- `init(loadsReminders:reminders:skippedIDs:authorizationStatus:excludedListTitles:hasHidden:speechTranscriber:backgroundImage:)` — add `dictationViewModel = DictationViewModel(speechTranscriber: ..., store: store)`

**Replace** all reads in the body: `isDictating` → `dictationViewModel.isDictating`, `dictationText` → `dictationViewModel.dictationText`, `dictationError` → `dictationViewModel.dictationError`, `creationFeedback` → `dictationViewModel.creationFeedback`, `canDictate` → `dictationViewModel.canDictate`, `startDictation()` → `dictationViewModel.startDictation()`.

The mic button becomes:
```swift
Button {
    Task { await dictationViewModel.startDictation() }
} label: { ... }
```

#### 3. Rewrite `MicrophoneToggleTests` to use `DictationViewModel`

**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify

- Keep the `MicToggleFakeTranscriber` class unchanged
- Each test now constructs `DictationViewModel(speechTranscriber: fake, store: ...)` directly and asserts on `dictationViewModel.canDictate`
- The `settingsGearButtonIsPresent` test still constructs `ContentView` (it tests the gear button label, not dictation) — but now must pass `speechTranscriber` for `DictationViewModel` construction
- Tests that read body description: keep them but ensure they're still meaningful. The `micButtonHiddenWhenSpeechDenied` test should assert `!dictationViewModel.canDictate` directly plus keep the body-description assertion as a regression guard.

#### 4. Rewrite `ReminderDictationTests` to use `DictationViewModel`

**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify

- The `FakeSpeechTranscriber` class stays unchanged
- Rename the "ContentView integration" section to "DictationViewModel integration"
- Tests `contentViewCanInitWithFakeTranscriber` and `contentViewCanInitWithReminderStoreAndFakeTranscriber` become:
  - `dictationViewModelCanInitWithFakeTranscriber` — construct `DictationViewModel(speechTranscriber: fake, store: store)`, verify `canDictate` is `true`
  - `dictationViewModelCanInitWithStore` — construct with a seeded `ReminderStore`, verify `canDictate`
- Add a test that exercises `startDictation()` via the VM with `FakeSpeechTranscriber(transcriptionResult: "Buy milk")` and asserts `dictationText` flows through

### Verification

#### Automated
- [x] `make test` passes — `MicrophoneToggleTests` + `ReminderDictationTests` rewritten to use VM; all other suites green
- [x] `make build` — iOS app compiles
- [x] Confirm `ContentView` has NO `@State` dictation vars (`rg "@State.*(isDictating|dictationText|dictationError|creationFeedback)" SingleThread/ContentView.swift` returns nothing)

#### Manual
- [ ] On simulator, grant speech permission: tap mic, speak "buy milk tomorrow", verify reminder appears with creation-feedback checkmark

---

## Phase 3: `ContentViewModel` (main-view presentation + orchestration)

Move `ContentView`'s mixed-dependency presentation state and its `.task`/`.onChange` reactions into a `ContentViewModel`; `ContentView` becomes a display + event-forwarding shell.

### Changes

#### 1. Create `ContentViewModel`

**File**: `SingleThread/ContentViewModel.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import Speech
import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

@MainActor
@Observable
final class ContentViewModel {
    // MARK: Lifecycle

    init(
        store: ReminderStore,
        backgroundImage: BackgroundImageStore,
        speechTranscriber: any SpeechTranscribing) {
        self.store = store
        self.backgroundImage = backgroundImage
        dictation = DictationViewModel(speechTranscriber: speechTranscriber, store: store)
    }

    // MARK: Internal

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let dictation: DictationViewModel

    #if os(iOS)
        var showsActionButtons: Bool {
            UserDefaults.standard.bool(forKey: "enableActionButtons")
                && store.visibleReminders.first != nil
        }
    #endif

    var backgroundDisplayed: Bool {
        UserDefaults.standard.bool(forKey: "backgroundEnabled")
            && backgroundImage.imageData != nil
    }

    /// Copy + icon describing why the reminder list has nothing to show.
    struct EmptyStateCopy {
        let title: String
        let systemImage: String
        let description: String
    }

    static func emptyStateCopy(hasHidden: Bool) -> EmptyStateCopy {
        if hasHidden {
            return EmptyStateCopy(
                title: "Nothing due",
                systemImage: "calendar",
                description: "Only today's and overdue reminders show here — pull to refresh.")
        }
        return EmptyStateCopy(
            title: "No Reminders",
            systemImage: "checklist",
            description: "You don't have any reminders yet.")
    }

    static func allDoneStateCopy() -> EmptyStateCopy {
        EmptyStateCopy(
            title: "All Done",
            systemImage: "checkmark.circle",
            description: "Pull to refresh to see all your reminders again.")
    }

    // MARK: - Task / onChange reactions

    func task(showUndatedReminders: Bool) async {
        store.showsUndatedReminders = showUndatedReminders
        await store.start()
        await backgroundImage.refreshIfNeeded(maxAge: 3600)
    }

    func handleShowUndatedReminders(_ value: Bool) {
        store.showsUndatedReminders = value
        Task { await store.reload() }
    }

    func handleSortOption(_ option: SortOption) {
        store.setSortOption(option)
    }

    func handleAppearanceMode(_ mode: AppearanceMode) {
        #if os(iOS)
            AppDelegate.applyAppearance(mode)
        #elseif os(macOS)
            MacAppDelegate.applyAppearance(mode)
        #endif
    }

    // MARK: Private
}
```

#### 2. Shrink `ContentView`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Remove**:
- `showsActionButtons` computed (lines 71-76) — now on `ContentViewModel`
- `backgroundDisplayed` computed (lines 78-80) — now on `ContentViewModel`
- `EmptyStateCopy` struct (lines 63-67) — now on `ContentViewModel`
- `emptyStateCopy(hasHidden:)` static func (lines 168-186) — now on `ContentViewModel`
- `allDoneStateCopy()` static func (lines 188-193) — now on `ContentViewModel`
- Inline `.task` body (lines 111-115) — delegate to VM
- Inline `.onChange(of: showUndatedReminders)` body (lines 116-119) — delegate to VM
- Inline `.onChange(of: sortOption)` body (lines 120-122) — delegate to VM
- Inline `.onChange(of: appearanceMode)` body (lines 123-128) — delegate to VM
- `var backgroundImage: BackgroundImageStore` stored property — now owned by VM
- `var store` stored property — now owned by VM (but ContentView still reads bindings from `viewModel.store`)
- `speechTranscriber` stored property — now on `DictationViewModel`
- All three public inits — consolidate to accept `ContentViewModel`

**Add** a single init:
```swift
init(viewModel: ContentViewModel) {
    self.viewModel = viewModel
}
```

Keep the preview-convenience inits for `#Preview` macros. These construct a `ReminderStore` and then wrap it in a `ContentViewModel`:
```swift
/// Pre-populates state for canvas previews.
init(
    loadsReminders: Bool,
    reminders: [EKReminder],
    skippedIDs: Set<String>,
    authorizationStatus: EKAuthorizationStatus,
    excludedListTitles: Set<String> = [],
    hasHidden: Bool = false,
    speechTranscriber: (any SpeechTranscribing)? = nil,
    backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: loadsReminders,
        reminders: reminders,
        skippedIDs: skippedIDs,
        authorizationStatus: authorizationStatus,
        excludedListTitles: excludedListTitles,
        hasHidden: hasHidden)
    viewModel = ContentViewModel(
        store: store,
        backgroundImage: backgroundImage,
        speechTranscriber: speechTranscriber ?? ReminderDictation())
}
```

**Add** private stored property:
```swift
private let viewModel: ContentViewModel
```

**Rewrite** `.task` and `.onChange` modifiers in the body to delegate:
```swift
.task {
    await viewModel.task(showUndatedReminders: showUndatedReminders)
}
.onChange(of: showUndatedReminders) { _, newValue in
    viewModel.handleShowUndatedReminders(newValue)
}
.onChange(of: sortOption) { _, newValue in
    viewModel.handleSortOption(newValue)
}
.onChange(of: appearanceMode) { _, newValue in
    viewModel.handleAppearanceMode(newValue)
}
```

**Replace** all body reads: `store.` → `viewModel.store.`, `backgroundImage.` → `viewModel.backgroundImage.`, `backgroundDisplayed` → `viewModel.backgroundDisplayed`, `allSkipped` → `viewModel.store.allSkipped`, `showsActionButtons` → `viewModel.showsActionButtons`, `Self.emptyStateCopy` → `ContentViewModel.emptyStateCopy`, `Self.allDoneStateCopy()` → `ContentViewModel.allDoneStateCopy()`, `canDictate` → `viewModel.dictation.canDictate`, `isDictating` → `viewModel.dictation.isDictating`, etc.

The `excludedListsBinding` stays in `ContentView` (reads `viewModel.store`).

All 14 `@AppStorage` wrappers stay in `ContentView` for `SettingsView` bindings.

The `.sheet` presentation stays as-is, but reads from `viewModel.store` for `excludedListsBinding` and `availableLists`.

#### 3. Rewrite `ActionButtonTests`

**File**: `SingleThreadTests/ActionButtonTests.swift`
**Action**: modify

- Delete the `ActionButtonFakeTranscriber` class
- Each test constructs `ContentViewModel(store: ..., backgroundImage: ..., speechTranscriber: ...)` with a fake transcriber, then asserts on `viewModel.showsActionButtons`
- Tests read `UserDefaults.standard` directly (same pattern as before) since `ContentViewModel.showsActionButtons` reads `UserDefaults.standard.bool(forKey: "enableActionButtons")`
- Remove `@testable import SingleThread` for view access; keep `import SingleThreadCore`

#### 4. Rewrite `BackgroundCardTests`

**File**: `SingleThreadTests/BackgroundCardTests.swift`
**Action**: modify

- Delete the `BackgroundCardFakeTranscriber` class
- Each test constructs `ContentViewModel(store: ..., backgroundImage: ..., speechTranscriber: ...)` and asserts on `viewModel.backgroundDisplayed`
- The `imageSurvivesContentViewRecreation` test moves from testing `ContentView` recreation to testing `ContentViewModel` property stability — it asserts that `backgroundDisplayed` is `true` on a VM constructed with a seeded `BackgroundImageStore`

#### 5. Rewrite `SingleThreadTests`

**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify

- `contentViewInitializesWithoutReminders`: construct `ContentViewModel`, verify no crash
- `contentViewBodyContainsRefreshableModifier`: keep as a `ContentView` test (the view still has the refreshable modifier)
- `contentViewEmptyStatesShowDistinctCopy`: change to assert on `ContentViewModel.emptyStateCopy(hasHidden:)` and `ContentViewModel.allDoneStateCopy()` instead of `ContentView.`
- `contentViewAllDoneShowsAllDoneCopy`: change to `ContentViewModel.allDoneStateCopy()`

### Verification

#### Automated
- [x] `make test` — `ActionButtonTests`, `BackgroundCardTests`, `SingleThreadTests` green; all other suites green
- [x] `make ui-test` — same launch args, same accessible labels, accessibility audit passes
- [x] `make build` — iOS + macOS compile

#### Manual
- [ ] Run app: Complete/Skip cluster shows when `enableActionButtons` is ON and reminder visible; mic button shows when OFF; background appears when enabled + photo loaded
- [ ] Toggle "Show undated reminders" — list refreshes; toggle "Sort By" — order changes; toggle "Appearance" — mode switches

---

## Phase 4: `SettingsViewModel` (settings reactions)

Move `SettingsView`'s 5 inline `.onChange` → `AppDelegate`/`WidgetCenter` reactions into a `SettingsViewModel`.

### Changes

#### 1. Create `SettingsViewModel`

**File**: `SingleThread/SettingsViewModel.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

@MainActor
@Observable
final class SettingsViewModel {

    // MARK: Internal

    #if os(iOS)
        func allowsLandscapeChanged(_ value: Bool) {
            AppDelegate.applyLock(allowsLandscape: value)
        }
    #endif

    #if os(iOS) || os(macOS)
        func showDateChanged(_ value: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        func showRecurrenceChanged(_ value: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        func showAlarmsChanged(_ value: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    #endif
}
```

#### 2. Update `SettingsView` to accept `SettingsViewModel`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

**Add** init parameter to both `#if os(iOS)` and `#else` init overloads, defaulted for previews:
```swift
viewModel: SettingsViewModel = SettingsViewModel()
```

**Add** stored property:
```swift
private let viewModel: SettingsViewModel
```

**Replace** inline `.onChange` closures:

Line ~171-172 (`allowsLandscape`):
```swift
// Before:
.onChange(of: allowsLandscape) { _, newValue in
    AppDelegate.applyLock(allowsLandscape: newValue)
}
// After:
.onChange(of: allowsLandscape) { _, newValue in
    viewModel.allowsLandscapeChanged(newValue)
}
```

Lines ~198-199 (`showDate`):
```swift
// Before:
.onChange(of: showDate) { _, _ in
    WidgetCenter.shared.reloadAllTimelines()
}
// After:
.onChange(of: showDate) { _, newValue in
    viewModel.showDateChanged(newValue)
}
```

Lines ~209-210 (`showRecurrence`):
```swift
// Before:
.onChange(of: showRecurrence) { _, _ in
    WidgetCenter.shared.reloadAllTimelines()
}
// After:
.onChange(of: showRecurrence) { _, newValue in
    viewModel.showRecurrenceChanged(newValue)
}
```

Lines ~217-218 (`showAlarms`):
```swift
// Before:
.onChange(of: showAlarms) { _, _ in
    WidgetCenter.shared.reloadAllTimelines()
}
// After:
.onChange(of: showAlarms) { _, newValue in
    viewModel.showAlarmsChanged(newValue)
}
```

The previews don't need changes — the default parameter value works.

#### 3. Update `ContentView`'s `.sheet` to pass `SettingsViewModel`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

The `.sheet` presentation currently constructs `SettingsView(...)` with only bindings. Now also pass `viewModel: SettingsViewModel()` (a fresh instance is fine since its methods are pure delegations with no stored state).

#### 4. Create `SettingsViewModelTests`

**File**: `SingleThreadTests/SettingsViewModelTests.swift` (new)
**Action**: create

Since `WidgetCenter.shared.reloadAllTimelines()` and `AppDelegate.applyLock` are global side effects that can't be asserted in unit tests, the tests verify that the methods don't crash when called (smoke tests), and verify the ViewModel initializes correctly:

```swift
import SingleThread
import Testing

@MainActor
struct SettingsViewModelTests {
    @Test
    func initializesWithoutCrash() {
        let vm = SettingsViewModel()
        #expect(Bool(true))
    }

    #if os(iOS)
        @Test
        func allowsLandscapeChangedDoesNotCrash() {
            let vm = SettingsViewModel()
            vm.allowsLandscapeChanged(true)
            vm.allowsLandscapeChanged(false)
            #expect(Bool(true))
        }
    #endif

    #if os(iOS) || os(macOS)
        @Test
        func showDateChangedDoesNotCrash() {
            let vm = SettingsViewModel()
            vm.showDateChanged(true)
            #expect(Bool(true))
        }

        @Test
        func showRecurrenceChangedDoesNotCrash() {
            let vm = SettingsViewModel()
            vm.showRecurrenceChanged(false)
            #expect(Bool(true))
        }

        @Test
        func showAlarmsChangedDoesNotCrash() {
            let vm = SettingsViewModel()
            vm.showAlarmsChanged(true)
            #expect(Bool(true))
        }
    #endif
}
```

#### 5. Update existing `SettingsViewTests`

**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

The existing test constructs `SettingsView` directly with `.constant` bindings. Add the default `viewModel:` parameter (it's already defaulted, so no change needed). Verify the body description still contains all expected labels.

### Verification

#### Automated
- [x] `make test` — `SettingsViewTests` + new `SettingsViewModelTests` pass; all other suites green
- [x] `make build` — iOS + macOS compile
- [x] `make ui-test` — accessibility audit passes; widget timeline reload fires (no visible regression)

#### Manual
- [ ] Open Settings, toggle "Allow landscape" — orientation lock updates
- [ ] Toggle "Show date" in Settings — widget preview refreshes

---

## Phase 5: `AppViewModel` (iOS/macOS composition root)

Move `SingleThreadApp.init`'s composition-root logic into an `AppViewModel`. Eliminate the duplicate `@AppStorage` keys for sync observation.

### Changes

#### 1. Create `AppViewModel`

**File**: `SingleThread/AppViewModel.swift` (new)
**Action**: create

```swift
import Foundation
import SingleThreadCore
import SwiftUI
#if os(iOS)
    import EventKit
    import WatchConnectivity
#endif
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

@MainActor
@Observable
final class AppViewModel {
    // MARK: Lifecycle

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let (store, usesInMemory) = Self.makeStore(arguments: arguments)
        self.store = store
        usesInMemoryStore = usesInMemory
        store.sortOption = SortOptionStore().load()

        #if os(iOS)
            if WCSession.isSupported(), !usesInMemoryStore {
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: SkippedReminderStore(),
                    showDateStore: ShowDatePreference(),
                    showRecurrenceStore: ShowRecurrencePreference(),
                    showAlarmsStore: ShowAlarmsPreference(),
                    sendsShowDate: true)
                service.onCompleteReminderReceived = { [weak store] identifier in
                    Task { await store?.completeReminder(identifier: identifier) }
                }
                service.onDeleteReminderReceived = { [weak store] identifier in
                    Task { await store?.deleteReminder(identifier: identifier) }
                }
                service.onExcludedListTitlesReceived = { [weak store] titles in
                    store?.refreshExcludedListTitles(Set(titles))
                }
                service.activate()
                syncService = service
                store.onSkipSetChanged = { _ in service.pushAll() }
                store.onShowUndatedRemindersChanged = { _ in service.pushAll() }
                store.onExcludedListsChanged = { _ in service.pushAll() }
                store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
                store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
                store.onSortOptionChanged = { option in
                    SortOptionStore().save(option)
                    service.pushAll()
                }
            }
        #endif
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = {
                WidgetCenter.shared.reloadAllTimelines()
            }
        #endif
        backgroundImage = BackgroundImageStore()

        // Observe showDate/showRecurrence/showAlarms changes in AppGroup.defaults
        // so syncService.pushAll() fires without duplicating @AppStorage keys.
        #if os(iOS)
            setupSyncObservation()
        #endif
    }

    // MARK: Internal

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let usesInMemoryStore: Bool
    #if os(iOS)
        private(set) var syncService: SkippedReminderSyncService?
    #endif

    var contentViewModel: ContentViewModel {
        ContentViewModel(
            store: store,
            backgroundImage: backgroundImage,
            speechTranscriber: ReminderDictation())
    }

    // MARK: Private

    #if os(iOS)
        private func setupSyncObservation() {
            let center = NotificationCenter.default
            var lastShowDate = ShowDatePreference().isEnabled
            var lastShowRecurrence = ShowRecurrencePreference().isEnabled
            var lastShowAlarms = ShowAlarmsPreference().isEnabled
            // Use a token stored on the VM so observation lives as long as the VM.
            // NotificationCenter observation is removed when the token is deallocated.
            syncDefaultsObserver = center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: AppGroup.defaults,
                queue: .main) { [weak self] _ in
                    guard let self else { return }
                    let currentShowDate = ShowDatePreference().isEnabled
                    let currentShowRecurrence = ShowRecurrencePreference().isEnabled
                    let currentShowAlarms = ShowAlarmsPreference().isEnabled
                    if currentShowDate != lastShowDate
                        || currentShowRecurrence != lastShowRecurrence
                        || currentShowAlarms != lastShowAlarms {
                        lastShowDate = currentShowDate
                        lastShowRecurrence = currentShowRecurrence
                        lastShowAlarms = currentShowAlarms
                        self.syncService?.pushAll()
                    }
                }
        }

        private var syncDefaultsObserver: NSObjectProtocol?
    #endif

    /// Builds the app's ``ReminderStore`` from launch arguments.
    private static func makeStore(arguments: [String]) -> (store: ReminderStore, usesInMemory: Bool) {
        if let seed = UITestingSeed.fromLaunchArguments(arguments) {
            UITestingSeed.resetPersistedState()
            let inMemoryStore = InMemoryEventStore(
                reminders: seed.reminders,
                calendars: seed.calendars,
                defaultCalendar: seed.calendars.first)
            let store = ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: true)
            if !seed.excludedListTitles.isEmpty {
                store.setExcludedListTitles(seed.excludedListTitles)
            }
            return (store, true)
        }
        #if os(iOS)
            if arguments.contains("--ui-testing") {
                UserDefaults.standard.set(true, forKey: "enableActionButtons")
                let scratchStore = EKEventStore()
                let reminder = EKReminder(eventStore: scratchStore)
                reminder.title = "Buy groceries"
                reminder.priority = 5
                reminder.notes = "Don't forget the milk"
                let inMemoryStore = InMemoryEventStore(
                    reminders: [reminder],
                    calendars: [])
                return (ReminderStore(
                    eventStore: inMemoryStore,
                    loadsReminders: false,
                    reminders: [reminder],
                    skippedIDs: [],
                    authorizationStatus: .fullAccess), false)
            }
        #endif
        let loads = !arguments.contains("--ui-testing")
            && !arguments.contains("--no-reminders")
        return (ReminderStore(loadsReminders: loads), false)
    }
}
```

#### 2. Shrink `SingleThreadApp`

**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

**Remove**:
- `makeStore(arguments:)` static method (lines 132-176) — moved into `AppViewModel`
- All hook wiring code in `init()` (lines 24-72) — moved into `AppViewModel.init`
- `store.sortOption = SortOptionStore().load()` (line 20) — moved into `AppViewModel.init`
- `backgroundImage = BackgroundImageStore()` (line 74) — moved into `AppViewModel.init`
- The three duplicate `@AppStorage` wrappers (lines 111-118) — replaced by `AppViewModel`'s `UserDefaults` observation
- The three `.onChange(of: showDate/showRecurrence/showAlarms)` (lines 83-93) — replaced by `AppViewModel`'s observation
- `store`, `usesInMemoryStore`, `backgroundImage`, `syncService` stored properties — now in `AppViewModel`

**Replace** `init()`:
```swift
init() {
    viewModel = AppViewModel()
}
```

**Replace** `var body`:
```swift
var body: some Scene {
    WindowGroup {
        ContentView(viewModel: viewModel.contentViewModel)
    }
}
```

**Keep**:
- `@UIApplicationDelegateAdaptor(AppDelegate.self)` and `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` — stay on the App struct
- Single stored property: `private let viewModel: AppViewModel`

### Verification

#### Automated
- [ ] `make test` — `SkippedReminderSyncServiceTests` still pass; all unit test suites green
- [ ] `make ui-test` — all flows + accessibility audit pass unchanged
- [ ] `make watch-ui-test` — sync: phone push → watch applies

#### Manual
- [ ] Toggle "Show date" in Settings on the phone, confirm the watch card updates without relaunch (requires paired watch simulator or device)
- [ ] `--seed` UI test launch: run `make ui-test` and verify the seeded store path still works

---

## Phase 6: Watch ViewModels (watchOS mirror)

Mirror the iOS slices on watchOS: a `WatchReminderViewModel` for presentation + refresh, and a `WatchAppViewModel` for the watch composition root.

### Changes

#### 1. Create `WatchReminderViewModel`

**File**: `SingleThreadWatch/WatchReminderViewModel.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

@MainActor
@Observable
final class WatchReminderViewModel {
    // MARK: Lifecycle

    init(
        store: ReminderStore,
        showDateState: ShowDateState,
        showRecurrenceState: ShowRecurrenceState,
        showAlarmsState: ShowAlarmsState) {
        self.store = store
        self.showDateState = showDateState
        self.showRecurrenceState = showRecurrenceState
        self.showAlarmsState = showAlarmsState
    }

    // MARK: Internal

    let store: ReminderStore
    let showDateState: ShowDateState
    let showRecurrenceState: ShowRecurrenceState
    let showAlarmsState: ShowAlarmsState

    var isRefreshing = false
    var isShowingRefreshConfirmation = false

    func task() async {
        await store.start()
    }

    func refresh(clearSkipped: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let startedAt = Date()
        await store.reload(clearSkipped: clearSkipped)
        let remaining = WatchReminderViewModel.refreshMinimumDisplayDuration
            - Date().timeIntervalSince(startedAt)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        isRefreshing = false
    }

    // MARK: Private

    private static let refreshMinimumDisplayDuration: TimeInterval = 1
}
```

#### 2. Update `WatchReminderView`

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

**Remove**:
- `isRefreshing` and `isShowingRefreshConfirmation` `@State` vars (lines 70-71)
- `refreshMinimumDisplayDuration` static constant (line 65)
- Inline `refresh()` method (lines 224-230)

**Add** init parameter and stored property:
```swift
private let viewModel: WatchReminderViewModel
```

**Update** the existing inits to construct `WatchReminderViewModel`:
- `init(store:showDateState:showRecurrenceState:showAlarmsState:)` — create `WatchReminderViewModel(store:showDateState:showRecurrenceState:showAlarmsState:)`
- `init(loadsReminders:reminders:skippedIDs:authorizationStatus:hasHidden:showDateState:showRecurrenceState:showAlarmsState:)` — create store then wrap in VM

**Replace** all reads:
- `.task { await store.start() }` → `.task { await viewModel.task() }`
- `store.` → `viewModel.store.`
- `isRefreshing` → `viewModel.isRefreshing`
- `isShowingRefreshConfirmation` → `viewModel.isShowingRefreshConfirmation`
- `showDateState` → `viewModel.showDateState`
- `showRecurrenceState` → `viewModel.showRecurrenceState`
- `showAlarmsState` → `viewModel.showAlarmsState`
- `refresh()` → `await viewModel.refresh(clearSkipped:)`
- `allSkipped` → `viewModel.store.allSkipped`

The `refresh()` call site in `refreshButton`:
```swift
Button("Refresh") {
    Task { await viewModel.refresh(clearSkipped: viewModel.store.allSkipped) }
}
```

The `onTapGesture` + `confirmationDialog` "Refresh" button:
```swift
Button("Refresh") {
    Task { await viewModel.refresh(clearSkipped: viewModel.store.allSkipped) }
}
```

#### 3. Create `WatchAppViewModel`

**File**: `SingleThreadWatch/WatchAppViewModel.swift` (new)
**Action**: create

```swift
import EventKit
import SingleThreadCore
import SwiftUI
import WatchConnectivity

@MainActor
final class WatchAppViewModel {
    // MARK: Lifecycle

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let isUITesting = arguments.contains("--ui-testing")
        let store: ReminderStore = if isUITesting {
            Self.uiTestingStore(arguments: arguments)
        } else {
            ReminderStore(loadsReminders: true)
        }
        self.store = store
        store.sortOption = SortOptionStore().load()
        store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).load()

        showDateState = ShowDateState()
        showRecurrenceState = ShowRecurrenceState()
        showAlarmsState = ShowAlarmsState()

        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore(),
                showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
                showDateStore: ShowDatePreference(defaults: .standard),
                showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
                showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
                sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false)
            service.onShowUndatedRemindersReceived = { [weak store] value in
                Task {
                    store?.showsUndatedReminders = value
                    await store?.reload()
                }
            }
            service.onSkippedIdentifiersReceived = { [weak store] _ in
                Task { await store?.reload() }
            }
            service.onShowDateReceived = { [weak showDateState] value in showDateState?.apply(value) }
            service.onShowRecurrenceReceived = { [weak showRecurrenceState] value in showRecurrenceState?.apply(value) }
            service.onShowAlarmsReceived = { [weak showAlarmsState] value in showAlarmsState?.apply(value) }
            service.onSortOptionReceived = { [weak store] option in store?.setSortOption(option) }
            service.onExcludedListTitlesReceived = { [weak store] titles in
                store?.refreshExcludedListTitles(Set(titles))
            }
            service.activate()
            store.onSkipSetChanged = { _ in service.pushAll() }
            store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }

            if let index = arguments.firstIndex(of: "--ui-testing-live-excluded"),
               index + 1 < arguments.count {
                let list = arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    service.session(
                        WCSession.default,
                        didReceiveApplicationContext: ["excludedListTitles": [list]])
                }
            }
        }
    }

    // MARK: Internal

    let store: ReminderStore
    let showDateState: ShowDateState
    let showRecurrenceState: ShowRecurrenceState
    let showAlarmsState: ShowAlarmsState

    var reminderViewModel: WatchReminderViewModel {
        WatchReminderViewModel(
            store: store,
            showDateState: showDateState,
            showRecurrenceState: showRecurrenceState,
            showAlarmsState: showAlarmsState)
    }

    // MARK: Private

    private static func uiTestingStore(arguments: [String]) -> ReminderStore {
        let scratchStore = EKEventStore()
        let reminder = EKReminder(eventStore: scratchStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        for flag in ["--ui-testing-excluded-list", "--ui-testing-live-excluded"] {
            guard let index = arguments.firstIndex(of: flag),
                  index + 1 < arguments.count else { continue }
            let list = arguments[index + 1]
            let calendar = EKCalendar(for: .reminder, eventStore: scratchStore)
            calendar.title = list
            reminder.calendar = calendar
            let inMemoryStore = InMemoryEventStore(reminders: [reminder])
            return ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                excludedListTitles: flag == "--ui-testing-excluded-list" ? [list] : [])
        }
        let inMemoryStore = InMemoryEventStore(reminders: [reminder])
        return ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }
}
```

#### 4. Shrink `SingleThreadWatchApp`

**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

**Remove** everything from `init()` (lines 10-72) except the single line that creates the VM.
**Remove** `uiTestingStore(arguments:)` method (lines 89-125).
**Remove** stored properties: `showDateState`, `showRecurrenceState`, `showAlarmsState`, `store`.

**Replace** `init()`:
```swift
init() {
    viewModel = WatchAppViewModel()
}
```

**Replace** `var body`:
```swift
var body: some Scene {
    WindowGroup {
        WatchReminderView(viewModel: viewModel.reminderViewModel)
    }
}
```

**Keep** only: `private let viewModel: WatchAppViewModel`

### Verification

#### Automated
- [ ] `make watch-build` — compiles without errors
- [ ] `make watch-ui-test` — same launch args, same labels, passes
- [ ] `./scripts/test.sh` — full gate: format + lint + build + periphery + unit + iOS UI + watch UI

#### Manual
- [ ] Run watch app in simulator: reminder card renders, skip/complete works, refresh shows spinner
- [ ] End-to-end sync: phone push → watch app updates without relaunch

---

## Testing Checkpoints (copied from structure)

- **After Phase 1** — `ReminderStore.allSkipped` exists and both views read it; `ReminderStoreTests` covers the truth table; all existing suites still green.
- **After Phase 2** — dictation state machine lives in `DictationViewModel`; `MicrophoneToggleTests` + `ReminderDictationTests` construct the VM directly with `FakeTranscriber`; `ContentView` has no `@State` dictation vars.
- **After Phase 3** — `ContentView` has no computed presentation props and no inline `.task`/`.onChange` bodies; `ActionButtonTests`/`BackgroundCardTests`/`SingleThreadTests` assert on `ContentViewModel`; UI labels unchanged.
- **After Phase 4** — `SettingsView` has no inline `AppDelegate`/`WidgetCenter` `.onChange` calls; reactions live in `SettingsViewModel`.
- **After Phase 5** — `SingleThreadApp.init` only constructs `AppViewModel`; duplicate `@AppStorage` sync keys removed; sync + widget reload behavior unchanged end-to-end.
- **After Phase 6** — watch views/app are shells; `./scripts/test.sh` fully green (the definitive gate).