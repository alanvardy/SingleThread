# Implementation Plan

## Overview

Add a `ShowCompletionGlowPreference` (a byte-for-byte sibling of `ShowDatePreference`), gate `completionGlow.trigger()` behind `.isEnabled` in both view models, surface a `Toggle("Completion glow", systemImage: "sparkles")` row in Reminder settings, and sync the preference phone→watch through the existing `SkippedReminderSyncService` pipeline. The glow stays enabled by default everywhere and is suppressed only after the user opts out.

> Note: `structure.md` uses "Stage"; this plan uses "Phase" for the same sequence. Phase order is preserved 1:1.

---

## Phase 1: Preference Struct (Core Model)

### Changes

#### 1. New preference struct
**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowCompletionGlowPreference.swift`
**Action**: create

```swift
import Foundation

/// Persists the user's "show completion glow" preference in UserDefaults.
///
/// Like `ShowDatePreference`, an absent key resolves to `true` (today's
/// always-on behavior) — `bool(forKey:)` would suppress the glow on first
/// launch. `nil` (missing key) therefore maps to `true`.
public struct ShowCompletionGlowPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showCompletionGlow") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether the completion glow is shown. `nil` (missing key) → `true`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

No `Package.swift` edit is needed — SPM auto-discovers files under `Sources/SingleThreadCore/`.

#### 2. New unit test suite
**File**: `SingleThreadTests/ShowCompletionGlowPreferenceTests.swift`
**Action**: create (mirrors `ShowDatePreferenceTests.swift` exactly)

```swift
import Foundation
import SingleThreadCore
import Testing

struct ShowCompletionGlowPreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }

    @Test
    func missingKeyIsNotFalse() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled != false)
    }
}
```

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/ShowCompletionGlowPreferenceTests` passes (4 tests)

#### Manual
- [ ] None (pure model; no UI surface yet)

---

## Phase 2: Settings Persistence Plumbing (iOS/macOS)

### Changes

#### 1. Add `showCompletionGlow` to `SettingsBindings`
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add a defaulted param + stored property (after `showAlarms`, keeping the show-* grouping):

```swift
    init(
        // … existing params unchanged …
        showAlarms: Bool = true,
        showCompletionGlow: Bool = true) {
        // … existing assignments unchanged …
        self.showAlarms = showAlarms
        self.showCompletionGlow = showCompletionGlow
    }

    // … existing properties unchanged …
    var showAlarms: Bool
    var showCompletionGlow: Bool
```

#### 2. Add `@AppStorage` mirror in `ContentView`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Next to the other show-* mirrors (after `showAlarms`, `ContentView.swift:181-183`):

```swift
    @AppStorage("showAlarms", store: AppGroup.defaults)
    private var showAlarms = true
    @AppStorage("showCompletionGlow", store: AppGroup.defaults)
    private var showCompletionGlow = true
```

#### 3. Write-back in the settings sheet
**File**: `SingleThread/ContentView.swift`
**Action**: modify

After `.onChange(of: bag.showAlarms) { _, new in showAlarms = new }` (the last write-back in the sheet, `ContentView.swift:149`):

```swift
                    .onChange(of: bag.showAlarms) { _, new in showAlarms = new }
                    .onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }
```

#### 4. Pass through in `makeSettingsBag()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In **both** `#if os(iOS)` and `#else` branches of `makeSettingsBag()` (lines ~488-517), append `showCompletionGlow: showCompletionGlow` after `showAlarms: showAlarms`.

#### 5. Structural unit test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add one test to the existing `SettingsViewTests` struct:

```swift
    @Test
    func settingsBindingsCarriesShowCompletionGlow() {
        let bag = SettingsBindings()
        #expect(bag.showCompletionGlow)                    // default enabled
        let off = SettingsBindings(showCompletionGlow: false)
        #expect(!off.showCompletionGlow)                   // explicit false round-trips
    }
```

> `ContentView.makeSettingsBag()` is `private` and is not unit-tested directly; its wiring is exercised end-to-end by the Phase 3 manual check and the Phase 6 relaunch UI test.

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` passes (existing + 1 new test; the only failure is a pre-existing unrelated `privacySettingsViewContainsExpectedContent` flake)
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` (full iOS unit suite) stays green — NOT run; see privacy-suite flake residual risk

#### Manual
- [ ] Build for simulator (`make build`); no warnings (warnings are errors).

---

## Phase 3: Settings UI (Toggle Row)

### Changes

#### 1. Add the toggle row to `ReminderSettingsView`
**File**: `SingleThread/ReminderSettingsView.swift`
**Action**: modify

Add a new `@Binding` and a `Toggle` row after "Reminder alerts" (**no** `.onChange` hook — the widget does not render the glow, so no timeline reload; this matches the existing `showList` row which also omits the hook):

```swift
    @Binding var showAlarms: Bool

    @Binding var showCompletionGlow: Bool

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            // … existing four toggles unchanged …
            Toggle(isOn: $showAlarms) {
                Label("Reminder alerts", systemImage: "bell")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: showAlarms) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $showCompletionGlow) {
                Label("Completion glow", systemImage: "sparkles")
            }
        }
        .navigationTitle("Reminder")
    }
```

Update the `#Preview` to add the new binding:

```swift
            showAlarms: .constant(true),
            showCompletionGlow: .constant(true),
            viewModel: SettingsViewModel())
```

#### 2. Thread the binding through `SettingsView`
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

At the `ReminderSettingsView` call site (line ~49-58):

```swift
                    ReminderSettingsView(
                        showDate: $bindings.showDate,
                        showList: $bindings.showList,
                        showRecurrence: $bindings.showRecurrence,
                        showAlarms: $bindings.showAlarms,
                        showCompletionGlow: $bindings.showCompletionGlow,
                        viewModel: viewModel)
```

No change to `SettingsView`'s own `init` (it carries the whole `SettingsBindings` bag).

#### 3. Update the structural test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

In `reminderSettingsViewContainsExpectedRows`, add the binding arg and the expected label:

```swift
        let view = ReminderSettingsView(
            showDate: .constant(true),
            showList: .constant(false),
            showRecurrence: .constant(true),
            showAlarms: .constant(true),
            showCompletionGlow: .constant(true),
            viewModel: SettingsViewModel())
        // …
        let expectedLabels = [
            "Show date", "Show list", "Recurrence indicator", "Reminder alerts", "Completion glow"
        ]
```

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` passes
- [ ] `make build` succeeds (iOS simulator build; warnings-as-errors)

#### Manual
- [ ] Run on simulator; open Settings → Reminder → confirm "Completion glow" toggle renders (default ON) alongside the four existing rows
- [ ] Flip it off, tap Done, re-open Settings → Reminder → toggle is still off (bag write-back + `@AppStorage` persistence)

---

## Phase 4: View-Model Gate (Behavior)

### Changes

#### 1. Gate the iOS/macOS trigger
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

Extend `init` (defaulted param keeps every existing call site compiling):

```swift
    init(
        store: ReminderStore,
        backgroundImage: BackgroundImageStore,
        speechTranscriber: any SpeechTranscribing,
        showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference()) {
        self.store = store
        self.backgroundImage = backgroundImage
        self.showCompletionGlow = showCompletionGlow
        dictation = DictationViewModel(speechTranscriber: speechTranscriber, store: store)
    }
```

Add the property (in the `// MARK: Internal` section) and gate the trigger:

```swift
    /// Preference read at trigger time so a settings toggle takes effect
    /// without rebuilding the view model.
    private let showCompletionGlow: ShowCompletionGlowPreference
```

```swift
    func completeCurrentReminder() async {
        if await store.completeCurrentReminder(), showCompletionGlow.isEnabled {
            completionGlow.trigger()
        }
    }
```

`AppViewModel.contentViewModel` needs **no change** — the default argument supplies `ShowCompletionGlowPreference()` (App Group-backed), which is exactly what production wants.

#### 2. New watch state holder
**File**: `SingleThreadWatch/ShowCompletionGlowState.swift`
**Action**: create (copy `ShowDateState.swift` exactly, swap the preference type + key)

```swift
import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "show completion glow" flag.
/// Replaces a former `@AppStorage` read-back; updates arrive through the
/// sync pipeline's explicit `onShowCompletionGlowReceived` callback.
@Observable
final class ShowCompletionGlowState {
    // MARK: Lifecycle

    init() {
        isEnabled = preference.isEnabled
    }

    // MARK: Internal

    private(set) var isEnabled: Bool

    /// Persists a received value and publishes it to observing views.
    func apply(_ value: Bool) {
        preference.set(value)
        isEnabled = value
    }

    // MARK: Private

    private let preference = ShowCompletionGlowPreference(defaults: .standard)
}
```

#### 3. Gate the watch trigger + accept the holder
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Add the init param, property, and gate:

```swift
    init(
        store: ReminderStore,
        showDateState: ShowDateState,
        showRecurrenceState: ShowRecurrenceState,
        showAlarmsState: ShowAlarmsState,
        showListState: ShowListState,
        showCompletionGlowState: ShowCompletionGlowState) {
        self.store = store
        self.showDateState = showDateState
        self.showRecurrenceState = showRecurrenceState
        self.showAlarmsState = showAlarmsState
        self.showListState = showListState
        self.showCompletionGlowState = showCompletionGlowState
    }
```

```swift
    let showListState: ShowListState
    let showCompletionGlowState: ShowCompletionGlowState
```

```swift
    func completeCurrentReminder() async {
        if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled {
            completionGlow.trigger()
        }
    }
```

#### 4. Wire the holder into the watch composition root
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

Add a property (next to the four existing states) and pass it into the factory:

```swift
    let showListState: ShowListState
    let showCompletionGlowState: ShowCompletionGlowState
```

```swift
        showListState = ShowListState()
        showCompletionGlowState = ShowCompletionGlowState()
```

```swift
    var reminderViewModel: WatchReminderViewModel {
        WatchReminderViewModel(
            store: store,
            showDateState: showDateState,
            showRecurrenceState: showRecurrenceState,
            showAlarmsState: showAlarmsState,
            showListState: showListState,
            showCompletionGlowState: showCompletionGlowState)
    }
```

#### 5. Update the watch view's convenience init (required for compilation)
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

The preview convenience init builds a `WatchReminderViewModel`; add the new param and pass it through:

```swift
        showListState: ShowListState = ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState = ShowCompletionGlowState()) {
        // …
        viewModel = WatchReminderViewModel(
            store: store,
            showDateState: showDateState,
            showRecurrenceState: showRecurrenceState,
            showAlarmsState: showAlarmsState,
            showListState: showListState,
            showCompletionGlowState: showCompletionGlowState)
    }
```

#### 6. iOS view-model tests (gate behavior)
**File**: `SingleThreadTests/CompletionGlowTests.swift`
**Action**: modify

Extend `CompletionGlowViewModelTests` with two tests and a preference-aware fixture. Add a `showCompletionGlow:` parameter to `makeViewModel`:

```swift
    @Test
    func glowStaysInactiveWhenPreferenceDisabled() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let disabled = ShowCompletionGlowPreference(
            defaults: .standard, key: "glow-disabled-\(UUID().uuidString)")
        disabled.set(false)
        let viewModel = makeViewModel(reminders: [reminder], showCompletionGlow: disabled)
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }

    @Test
    func glowTriggersWhenPreferenceEnabled() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let enabled = ShowCompletionGlowPreference(
            defaults: .standard, key: "glow-enabled-\(UUID().uuidString)")
        enabled.set(true)
        let viewModel = makeViewModel(reminders: [reminder], showCompletionGlow: enabled)
        await viewModel.completeCurrentReminder()
        #expect(viewModel.completionGlow.isActive)
    }

    private func makeViewModel(
        reminders: [EKReminder],
        skippedIDs: Set<String> = [],
        showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference()) -> ContentViewModel {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: .fullAccess)
        return ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: GlowFakeTranscriber(),
            showCompletionGlow: showCompletionGlow)
    }
```

> The disabled case seeds a UUID-keyed `.standard` preference via `.set(false)`, mirroring the existing `InMemoryEventStore` + fake-transcriber seams — no real `AppGroup.defaults` is touched.

#### 7. Watch state + gate tests
**File**: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`
**Action**: create

Requires `@testable import SingleThreadWatch` (the test target already has a `PBXTargetDependency` on the app target and the app has `ENABLE_TESTABILITY = YES`). Covers the holder semantics and the watch gate:

```swift
import SingleThreadCore
import Testing
@testable import SingleThreadWatch

@MainActor
struct ShowCompletionGlowStateTests {
    @Test
    func initialValueFromPreference() {
        // The holder hardcodes `.standard` + key "showCompletionGlow"; seed that.
        UserDefaults.standard.set(false, forKey: "showCompletionGlow")
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        let state = ShowCompletionGlowState()
        #expect(!state.isEnabled)
    }

    @Test
    func applyPersists() {
        let state = ShowCompletionGlowState()
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        state.apply(false)
        #expect(!ShowCompletionGlowPreference(defaults: .standard).isEnabled)
    }

    @Test
    func applyRepublishes() {
        let state = ShowCompletionGlowState()
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        #expect(state.isEnabled)          // default
        state.apply(false)
        #expect(!state.isEnabled)         // republished
        state.apply(true)
        #expect(state.isEnabled)
    }

    @Test
    func watchGateSuppressesGlowWhenDisabled() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let glowState = ShowCompletionGlowState()
        glowState.apply(false)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: glowState)
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }
}
```

> **Fallback**: if `@testable import SingleThreadWatch` fails to link (unexpected given the existing dependency), keep only the state-holder tests that use Core types, and note that the watch gate is identical to the iOS gate already proven by `CompletionGlowViewModelTests`. Do not add a new test target — that requires pbxproj + scheme wiring (out of scope per AGENTS.md).

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/CompletionGlowViewModelTests` passes (existing + 2 new)
- [ ] `make watch-test` passes (watch unit target; `ShowCompletionGlowStateTests` new)
- [ ] `xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS Simulator' -configuration Debug build` succeeds (watch app compiles with the new holder/param)

#### Manual
- [ ] iOS: complete a reminder with the default setting — glow still flashes; disable "Completion glow" in Settings, complete again — no flash

---

## Phase 5: Phone→Watch Sync (Transport)

### Changes

#### 1. Extend the sync service
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add two defaulted params at the end of `init`, two stored properties, a hook, a payload key, and the push/apply wiring:

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
            showListStore: ShowListPreference = ShowListPreference(),
            showCompletionGlowStore: ShowCompletionGlowPreference = ShowCompletionGlowPreference(),
            sendsShowDate: Bool = true,
            sendsShowRecurrence: Bool = true,
            sendsShowAlarms: Bool = true,
            sendsShowList: Bool = true,
            sendsShowCompletionGlow: Bool = true) {
            // … existing assignments unchanged …
            self.showListStore = showListStore
            self.showCompletionGlowStore = showCompletionGlowStore
            self.sendsShowList = sendsShowList
            self.sendsShowCompletionGlow = sendsShowCompletionGlow
            super.init()
        }
```

New hook (same doc rationale as `onShowDateReceived`):

```swift
        /// Hook fired on the counterpart when the "show completion glow" preference
        /// arrives in an application context. Passes the received value. Same
        /// write-once-before-activate / `nonisolated(unsafe)` rationale as
        /// `onShowDateReceived`.
        public nonisolated(unsafe) var onShowCompletionGlowReceived: ((Bool) -> Void)?
```

`pushAll()` (after the `sendsShowList` block):

```swift
                if sendsShowList {
                    context[PayloadKey.showList] = showListStore.isEnabled
                }
                if sendsShowCompletionGlow {
                    context[PayloadKey.showCompletionGlow] = showCompletionGlowStore.isEnabled
                }
```

`apply(context:)` (after the `showList` block):

```swift
            if let showList = context[PayloadKey.showList] as? Bool {
                showListStore.set(showList)
                let handler = onShowListReceived
                handler?(showList)
            }
            if let showCompletionGlow = context[PayloadKey.showCompletionGlow] as? Bool {
                showCompletionGlowStore.set(showCompletionGlow)
                let handler = onShowCompletionGlowReceived
                handler?(showCompletionGlow)
            }
```

Stored properties + `PayloadKey`:

```swift
        private let showListStore: ShowListPreference
        private let showCompletionGlowStore: ShowCompletionGlowPreference
        private let sendsShowList: Bool
        private let sendsShowCompletionGlow: Bool
```

```swift
            static let showList = "showList"
            static let showCompletionGlow = "showCompletionGlow"
```

#### 2. iPhone-side send wiring
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

- In `init` (iOS branch, `SkippedReminderSyncService(...)` call at line ~28): add `showCompletionGlowStore: ShowCompletionGlowPreference(),` (next to `showDateStore`).
- In `handlePreferencesChanged()`: add the current-value read + diff + baseline:

```swift
            let currentShowList = ShowListPreference().isEnabled
            let currentShowCompletionGlow = ShowCompletionGlowPreference().isEnabled
            if currentShowDate != lastShowDate
                || currentShowRecurrence != lastShowRecurrence
                || currentShowAlarms != lastShowAlarms
                || currentShowList != lastShowList
                || currentShowCompletionGlow != lastShowCompletionGlow {
                lastShowDate = currentShowDate
                lastShowRecurrence = currentShowRecurrence
                lastShowAlarms = currentShowAlarms
                lastShowList = currentShowList
                lastShowCompletionGlow = currentShowCompletionGlow
                syncService?.pushAll()
            }
```

```swift
        private var lastShowList = ShowListPreference().isEnabled
        private var lastShowCompletionGlow = ShowCompletionGlowPreference().isEnabled
```

#### 3. Watch-side receive wiring
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

In `setupSyncService(arguments:)`, add the store + flag + hook (watch is receive-only, like the other four):

```swift
        let showListState = showListState
        let showCompletionGlowState = showCompletionGlowState
        let service = SkippedReminderSyncService(
            session: WCSession.default,
            skipStore: SkippedReminderStore(),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
            showDateStore: ShowDatePreference(defaults: .standard),
            showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
            showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
            showListStore: ShowListPreference(defaults: .standard),
            showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard),
            sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false, sendsShowList: false,
            sendsShowCompletionGlow: false)
        // …
        service.onShowListReceived = { [weak showListState] value in
            Task { @MainActor in showListState?.apply(value) }
        }
        service.onShowCompletionGlowReceived = { [weak showCompletionGlowState] value in
            Task { @MainActor in showCompletionGlowState?.apply(value) }
        }
```

#### 4. iOS sync tests
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Add four tests (mirror the show-date tests):

```swift
        @Test
        func pushAllIncludesShowCompletionGlowWhenEnabled() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let glowStore = ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-push-\(suffix)")
            glowStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-glow-push-ids-\(suffix)"),
                showCompletionGlowStore: glowStore,
                sendsShowCompletionGlow: true)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect((context["showCompletionGlow"] as? Bool) == true)
        }

        @Test
        func pushAllOmitsShowCompletionGlowWhenDisabled() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-glow-omit-ids-\(suffix)"),
                showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-omit-\(suffix)"),
                sendsShowCompletionGlow: false)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["showCompletionGlow"] == nil)
        }

        @Test
        func receiveShowCompletionGlowApplies() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let glowStore = ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-recv-\(suffix)")
            glowStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-glow-recv-ids-\(suffix)"),
                showCompletionGlowStore: glowStore)
            service.session(WCSession.default, didReceiveApplicationContext: ["showCompletionGlow": false])
            #expect(!glowStore.isEnabled)
        }

        @Test
        func receiveShowCompletionGlowFiresHook() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-glow-hook-ids-\(suffix)"),
                showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-hook-\(suffix)"))
            var received: [Bool] = []
            service.onShowCompletionGlowReceived = { received.append($0) }
            service.session(WCSession.default, didReceiveApplicationContext: ["showCompletionGlow": false])
            #expect(received == [false])
        }
```

#### 5. Watch sync pipeline tests
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify

Add a receive test + relaunch-survival test:

```swift
    @Test
    func receiveAppliesShowCompletionGlow() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let glowStore = ShowCompletionGlowPreference(defaults: .standard, key: "wtest-glow-\(suffix)")
        glowStore.set(true)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-glow-ids-\(suffix)"),
            showCompletionGlowStore: glowStore)

        var values: [Bool] = []
        service.onShowCompletionGlowReceived = { values.append($0) }

        service.session(WCSession.default, didReceiveApplicationContext: ["showCompletionGlow": false])

        #expect(!glowStore.isEnabled)
        #expect(values == [false])
    }

    @Test
    func showCompletionGlowSurvivesRelaunch() {
        let key = "wtest-relaunch-glow-\(UUID().uuidString)"
        let fake = WatchFakeSession()
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
            showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard, key: key))
        service.session(WCSession.default, didReceiveApplicationContext: ["showCompletionGlow": false])
        let freshStore = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(!freshStore.isEnabled)
    }
```

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests` passes
- [ ] `make watch-test` passes (incl. `WatchSyncPipelineTests` additions)
- [ ] `make lint` passes (SwiftFormat + SwiftLint `--strict`)

#### Manual
- [ ] (Optional, needs paired devices) Toggle off on iPhone → watch's glow is suppressed after the context push; toggle on → glow returns

---

## Phase 6: UI Tests

### Changes

#### 1. Reset the new key in the seed harness (test isolation)
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

Add `"showCompletionGlow"` to `persistedKeys` so `--seed` launches start clean:

```swift
    private static let persistedKeys = [
        "skippedReminderIdentifiers",
        "excludedListTitles",
        "showDate",
        "showList",
        "showRecurrence",
        "showAlarms",
        "showCompletionGlow",
        "showUndatedReminders",
        // … remaining keys unchanged …
    ]
```

#### 2. UI-test observability seam (needed — see note below)
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In the `contentViewModel` computed property, hold the glow open long enough for an XCUITest to observe it:

```swift
    var contentViewModel: ContentViewModel {
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: backgroundImage,
            speechTranscriber: ReminderDictation())
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-glow") {
            // UI-test seam: keep the glow visible long enough for a
            // deterministic `exists` assertion (production duration is 0.25 s).
            viewModel.completionGlow.duration = 2.0
        }
        return viewModel
    }
```

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Expose the otherwise `accessibilityHidden` overlay to the accessibility tree only during the glow UI test. Add `import Foundation` at the top (for `ProcessInfo`) if the compiler requires it, then:

```swift
    private var completionGlowOverlay: some View {
        Color.green
            .opacity(0.3)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(!isGlowUITesting)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("completionGlowOverlay")
            .accessibilityLabel("Completion glow")
            .transition(.opacity)
    }

    /// True only for the completion-glow UI test; production always hides the
    /// overlay from accessibility (unchanged behavior for real users).
    private var isGlowUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")
    }
```

> **Why this seam exists**: the glow is `accessibilityHidden(true)` and transient (0.25 s), so an XCUITest cannot otherwise observe it. Gating exposure + duration on `--ui-testing-glow` keeps production behavior (accessibility-hidden, 0.25 s) completely unchanged. This resolves the design's "UI test determinism" open risk.

#### 3. Add the three UI tests
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (append to the existing class — do **not** create a new class, which would need CI group wiring)

```swift
    // MARK: - Completion glow

    /// Uses `--ui-testing` (not `--seed`) for both launches: seeding calls
    /// `resetPersistedState()` and would wipe the key under test.
    @MainActor
    func testCompletionGlowTogglePersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3))
        app.staticTexts["Reminder"].tap()
        let toggle = app.switches["Completion glow"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "Completion glow should default to on")
        XCTAssertTrue(flipToggle(toggle, target: "0"), "Tapping should disable the glow")

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.staticTexts["Reminder"].tap()
        let persistedToggle = relaunched.switches["Completion glow"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(persistedToggle.value as? String, "0", "Completion-glow-off should persist across relaunch")
    }

    @MainActor
    func testCompletionGlowDoesNotAppearWhenDisabled() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        app.launchArguments.append("--ui-testing-glow")
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Disable the glow, then complete the only reminder.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3))
        app.staticTexts["Reminder"].tap()
        let toggle = app.switches["Completion glow"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertTrue(flipToggle(toggle, target: "0"), "Tapping should disable the glow")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        app.staticTexts["Buy groceries"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(app.staticTexts["No Reminders"].waitForExistence(timeout: 5), "Completing should empty the list")
        // The overlay must never appear once the preference is off.
        XCTAssertFalse(app.otherElements["completionGlowOverlay"].exists, "Glow should be suppressed when disabled")
    }

    @MainActor
    func testCompletionGlowFlashesWhenEnabled() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        app.launchArguments.append("--ui-testing-glow")
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        app.staticTexts["Buy groceries"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // Glow duration is extended to 2 s under the seam, so `waitForExistence`
        // is deterministic.
        XCTAssertTrue(
            app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3),
            "Glow overlay should flash briefly after completion")
    }
```

> `launchApp(seedJSON:)` sets `launchArguments = ["--seed", json]`; appending `--ui-testing-glow` after it is fine because `UITestingSeed.fromLaunchArguments` only reads the argument at `index + 1` of `--seed`.

### Verification
#### Automated
- [ ] `make ui-test` passes (runs `SingleThreadUITests`; the three new tests ride `SingleThreadUITestsFlows`, already in CI's `UI_GROUP_B`)
- [ ] `./scripts/test.sh` passes the full gate (format, lint, build, periphery, iOS unit + UI tests, watch build + UI tests, macOS build + unit tests)

#### Manual
- [ ] Run the app on simulator; toggle "Completion glow" off and confirm no green flash on complete; toggle on and confirm the flash returns

---

## Cross-Phase Verification Checklist

| After Phase | Command(s) that must pass |
|---|---|
| 1 | `xcodebuild test … -only-testing:SingleThreadTests/ShowCompletionGlowPreferenceTests` |
| 2 | `xcodebuild test … -only-testing:SingleThreadTests` (full iOS unit) |
| 3 | `make build` + `xcodebuild test … -only-testing:SingleThreadTests/SettingsViewTests` |
| 4 | `xcodebuild test … -only-testing:SingleThreadTests/CompletionGlowViewModelTests` + `make watch-test` |
| 5 | `xcodebuild test … -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests` + `make watch-test` |
| 6 | `./scripts/test.sh` (full gate) |

Final gate before marking done: `make format && make lint && ./scripts/test.sh && make watch-test`.

> **Resume note**: if context resets mid-implementation, run `./scripts/test.sh` and confirm only the current and prior phases are green; any failure in a prior phase is a regression.
