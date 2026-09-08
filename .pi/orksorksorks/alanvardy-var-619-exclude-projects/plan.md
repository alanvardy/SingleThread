# Implementation Plan

## Overview

Add an "Excluded Projects" multi-select to `SettingsView` backed by a persisted, write-through title set in `ReminderStore`. Reminders whose calendar title is excluded are hidden from `visibleReminders` everywhere — phone, widget, and watch — with the excluded-title set persisting in App Group `UserDefaults` and syncing phone↔watch via WatchConnectivity.

---

## Phase 1: Core exclusion state + filtering

Persisted write-through set of excluded project titles owned by `ReminderStore`, plus the `visibleReminders` filter. No UI yet, fully unit-tested.

### Changes

#### 1. New `ExcludedProjectStore` (thin UserDefaults wrapper)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift`
**Action**: create

Mirror `SkippedReminderStore` (`ReminderSkip.swift:111-133`) exactly, including doc comment + `// MARK:` layout so `swiftformat --organizeDeclarations` is happy:

```swift
import Foundation

/// Persists the excluded-project titles in UserDefaults.
public struct ExcludedProjectStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedProjectTitles") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func save(_ titles: [String]) {
        defaults.set(titles, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. `ReminderStore` — state, hook, setter, filter, reload
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**2a. Production init** — add `excludeStore` (defaulted, after `skipStore` so existing labelled call sites are unaffected):

```swift
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        excludeStore: ExcludedProjectStore = ExcludedProjectStore(),
        loadsReminders: Bool = true) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.excludeStore = excludeStore
        self.loadsReminders = loadsReminders
    }
```

**2b. Preview/test init** — add `excludedProjectTitles: Set<String> = []` (defaulted so ~20 existing call sites in `ReminderStoreTests` and the watch preview init stay unchanged) and assign an inert `excludeStore`:

```swift
    public init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        excludedProjectTitles: Set<String> = [],
        authorizationStatus: EKAuthorizationStatus) {
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.excludedProjectTitles = excludedProjectTitles
        self.authorizationStatus = authorizationStatus
        eventStore = EKEventStore()
        skipStore = SkippedReminderStore()
        excludeStore = ExcludedProjectStore()
    }
```

**2c. Public state** — add `excludedProjectTitles` next to `skippedIDs`:

```swift
    public private(set) var skippedIDs: Set<String> = []
    public private(set) var excludedProjectTitles: Set<String> = []
```

**2d. Hook** — add after `onSkipSetChanged`:

```swift
    /// Hook invoked after any excluded-project mutation — passes the full excluded
    /// title array. Wired by each app layer to push exclusion changes via
    /// WatchConnectivity.
    public var onExcludedProjectsChanged: (([String]) -> Void)?
```

**2e. `visibleReminders`** — add the exclusion filter (nil calendar ⇒ title `""` ⇒ never excluded ⇒ always shown):

```swift
    public var visibleReminders: [EKReminder] {
        reminders
            .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
            .filter { !excludedProjectTitles.contains($0.calendar?.title ?? "") }
            .sorted { ReminderSort.areInIncreasingOrder($0, $1) }
    }
```

**2f. Setter** — add near the skip methods, write-through with no settle delay (mirror `applySkipSet` order: state → save → hooks):

```swift
    /// Replaces the excluded-project title set, persisting immediately and firing
    /// both `onExcludedProjectsChanged` and `onRemindersChanged`.
    public func setExcludedProjectTitles(_ titles: Set<String>) {
        excludedProjectTitles = titles
        let array = Array(titles)
        excludeStore.save(array)
        onExcludedProjectsChanged?(array)
        onRemindersChanged?()
    }
```

**2g. `reload()`** — load exclusions in the non-clear branch (load-on-reload, **no pruning** — orphaned titles linger harmlessly per design decision 1):

```swift
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: fetched.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
            excludedProjectTitles = Set(excludeStore.load())
        }
```

**2h. Private dependency** — declare alongside `skipStore`:

```swift
    private let eventStore: any EventKitStoring
    private let skipStore: SkippedReminderStore
    private let excludeStore: ExcludedProjectStore
```

#### 3. New store tests
**File**: `SingleThreadTests/ExcludedProjectStoreTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

struct ExcludedProjectStoreTests {
    @Test
    func loadReturnsEmptyByDefault() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-empty-\(UUID().uuidString)")
        #expect(store.load().isEmpty)
    }

    @Test
    func saveRoundTripsTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-roundtrip-\(UUID().uuidString)")
        store.save(["Work", "Personal"])
        #expect(Set(store.load()) == ["Work", "Personal"])
    }

    @Test
    func saveReplacesExistingTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-replace-\(UUID().uuidString)")
        store.save(["A", "B"])
        store.save(["C"])
        #expect(Set(store.load()) == ["C"])
    }

    @Test
    func saveEmptyClearsTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-clear-\(UUID().uuidString)")
        store.save(["A"])
        store.save([])
        #expect(store.load().isEmpty)
    }

    @Test
    func storesAreIsolatedByKey() {
        let first = ExcludedProjectStore(defaults: .standard, key: "test-excluded-isolation-1-\(UUID().uuidString)")
        let second = ExcludedProjectStore(defaults: .standard, key: "test-excluded-isolation-2-\(UUID().uuidString)")
        first.save(["Work"])
        #expect(second.load().isEmpty)
    }
}
```

#### 4. `ReminderStoreTests` — filter + setter tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add a fixture that puts a titled calendar on the reminder (existing `makeReminder` leaves `calendar` nil):

```swift
private func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}
```

Add tests (in the `visibleReminders` section):

```swift
    @Test
    func visibleRemindersFiltersOutExcludedProjectTitles() {
        let excluded = makeReminder(title: "A", calendarTitle: "Work")
        let kept = makeReminder(title: "B", calendarTitle: "Personal")
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [excluded, kept],
            skippedIDs: [],
            excludedProjectTitles: ["Work"],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.map(\.title) == ["B"])
    }

    @Test
    func visibleRemindersKeepsNilCalendarReminders() {
        let noCalendar = makeReminder(title: "A") // calendar == nil
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [noCalendar],
            skippedIDs: [],
            excludedProjectTitles: ["Work"],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.count == 1)
    }

    @Test
    func visibleRemindersEmptyWhenAllProjectsExcluded() {
        let inProject = makeReminder(title: "A", calendarTitle: "Work")
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [inProject],
            skippedIDs: [],
            excludedProjectTitles: ["Work"],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.isEmpty)
    }

    @Test
    func setExcludedProjectTitlesPersistsAndFiresHooks() {
        let key = "test-excluded-\(UUID().uuidString)"
        let excludeStore = ExcludedProjectStore(defaults: .standard, key: key)
        let store = ReminderStore(excludeStore: excludeStore, loadsReminders: false)
        var changedTitles: [String]?
        var remindersChanged = false
        store.onExcludedProjectsChanged = { changedTitles = $0 }
        store.onRemindersChanged = { remindersChanged = true }

        store.setExcludedProjectTitles(["Work", "Personal"])

        #expect(store.excludedProjectTitles == ["Work", "Personal"])
        #expect(Set(excludeStore.load()) == ["Work", "Personal"])
        #expect(Set(changedTitles ?? []) == ["Work", "Personal"])
        #expect(remindersChanged)
    }
```

### Verification
#### Automated
- [x] `swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadWidget/ SingleThreadTests/ SingleThreadUITests/` then `swiftlint lint --strict` pass (new files/formats clean)
- [x] `make test` (i.e. `./scripts/test.sh --unit-only`) passes — new `ExcludedProjectStoreTests`, new `visibleReminders` filter cases, and `setExcludedProjectTitles` tests green

#### Manual
- [ ] `make build` compiles (both iOS and `#else`-compiled platform variants of `ReminderStore` + new store type)

---

## Phase 2: Project enumeration via the EventKit seam

Add `availableProjects` (sorted, deduplicated titles) populated during `reload()` from a new `EventKitStoring.calendars(for:)` requirement.

### Changes

#### 1. Protocol + real conformance
**File**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`
**Action**: modify

Add the requirement to the protocol (after `authorizationStatus`):

```swift
    func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus

    func calendars(for entityType: EKEntityType) -> [EKCalendar]
```

> **No method body is added to `extension EKEventStore`.** `EKEventStore` already implements the exact instance method `calendars(for:) -> [EKCalendar]` in the SDK, so it satisfies the requirement directly — the same way `refreshSourcesIfNecessary()` is satisfied without a wrapper. The design's "delegate to `self.calendars(for:)`" would be an invalid redeclaration / infinite recursion. If the compiler unexpectedly reports a missing witness, add a distinct-named wrapper instead rather than shadowing the SDK method.

#### 2. `ReminderStore.availableProjects`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**2a.** Add public state next to `excludedProjectTitles`:

```swift
    /// All reminder-list titles (sorted, deduplicated) the settings UI presents.
    public private(set) var availableProjects: [String] = []
```

**2b.** Populate in `reload()` right after `reminders = fetched` (no `#if` — `calendars(for:)` is available on watchOS too):

```swift
        let fetched: [EKReminder] = await fetchReminders(matching: predicate)
        reminders = fetched
        availableProjects = Set(
            eventStore.calendars(for: .reminder)
                .map(\.title)
                .filter { !$0.isEmpty })
            .sorted()
```

#### 3. `FakeEventStore` conformance
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Add config + recording state and implement the new requirement:

```swift
    // (config, alongside `var fetchResult`)
    var returnedCalendars: [EKCalendar] = []
    // (recording, alongside `var refreshCallCount`)
    private(set) var calendarFetchCallCount = 0

    // (inside the EventKitStoring section)
    func calendars(for _: EKEntityType) -> [EKCalendar] {
        calendarFetchCallCount += 1
        return returnedCalendars
    }
```

Add a calendar fixture (alongside `makeReminder`):

```swift
private func makeCalendar(title: String) -> EKCalendar {
    let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
    calendar.title = title
    return calendar
}
```

Add a test suite (uses the existing `testStore(eventStore:)` helper):

```swift
@MainActor
@Suite(.serialized)
struct ReminderStoreAvailableProjectsTests {
    @Test
    func availableProjectsSortedAndDeduplicatedAfterReload() async {
        let fake = FakeEventStore()
        fake.returnedCalendars = [
            makeCalendar(title: "Work"),
            makeCalendar(title: "Personal"),
            makeCalendar(title: "work"),
            makeCalendar(title: "Work"),
            makeCalendar(title: ""),
        ]
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.availableProjects == ["Personal", "Work", "work"])
        #expect(fake.calendarFetchCallCount == 1)
    }

    @Test
    func availableProjectsEmptyWhenNoCalendars() async {
        let fake = FakeEventStore()
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.availableProjects.isEmpty)
        #expect(fake.calendarFetchCallCount == 1)
    }
}
```

> Note: dedup is by exact `String` equality only (case-sensitive), so `"Work"` and `"work"` are distinct — matches design's title-as-identity decision.

#### 4. `ReminderStoreTests` — default pin
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

```swift
    @Test
    func availableProjectsDefaultsToEmpty() {
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.availableProjects.isEmpty)
    }
```

### Verification
#### Automated
- [x] `make test` passes — new `ReminderStoreAvailableProjectsTests` (sorted/deduped, empty → `[]`, fetch counted) and `availableProjectsDefaultsToEmpty` green; existing `EventKitStoringTests` still compile with the expanded `FakeEventStore`

#### Manual
- [ ] `make build` compiles — confirms `EKEventStore` satisfies the new protocol requirement without a wrapper

---

## Phase 3: Settings UI (phone end-to-end)

"Projects" section listing available projects; toggling writes through `setExcludedProjectTitles`.

### Changes

#### 1. `SettingsView` — new bindings + section
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

**1a. Both initializers** — iOS 4→6 args, `#else` 3→5 args; add `excludedProjects` (binding) + `availableProjects` (value):

```swift
    #if os(iOS)
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            allowsLandscape: Binding<Bool>,
            showMicrophoneButton: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String]) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _allowsLandscape = allowsLandscape
            _showMicrophoneButton = showMicrophoneButton
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
        }
    #else
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            showMicrophoneButton: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String]) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _showMicrophoneButton = showMicrophoneButton
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
        }
    #endif
```

**1b. Property declarations**:

```swift
    @Binding private var excludedProjects: Set<String>
    private let availableProjects: [String]
```

Note: `excludedProjects: Binding<Set<String>>` is the only new `@Binding`; `availableProjects` is a plain `let` (read-only list).

**1c. Section** — append at the end of the `Form` (after the microphone toggle):

```swift
                Section("Excluded Projects") {
                    ForEach(availableProjects, id: \.self) { project in
                        Toggle(isOn: excludedBinding(for: project)) {
                            Text(project)
                        }
                    }
                }
```

**1d. Toggle binding helper** (private method):

```swift
    private func excludedBinding(for project: String) -> Binding<Bool> {
        Binding(
            get: { excludedProjects.contains(project) },
            set: { isExcluded in
                if isExcluded {
                    excludedProjects.insert(project)
                } else {
                    excludedProjects.remove(project)
                }
            })
    }
```

> Mutating the `Set` through the `@Binding` routes through `ContentView`'s binding setter → `store.setExcludedProjectTitles($0)`.

**1e. Previews** — both platform init calls gain `.constant([])` / `availableProjects: ["Work", "Personal"]` (note: iOS has two previews, non-iOS one).

#### 2. `ContentView` — wire the binding + preview init
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**2a. `.sheet`** — pass the new args (both `#if os(iOS)` and `#else` branches):

```swift
            #if os(iOS)
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    allowsLandscape: $allowsLandscape,
                    showMicrophoneButton: $showMicrophoneButton,
                    excludedProjects: excludedProjectsBinding,
                    availableProjects: store.availableProjects)
            #else
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    showMicrophoneButton: $showMicrophoneButton,
                    excludedProjects: excludedProjectsBinding,
                    availableProjects: store.availableProjects)
            #endif
```

**2b. Binding helper** (backed by the `@Observable` store, not `@AppStorage`):

```swift
    private var excludedProjectsBinding: Binding<Set<String>> {
        Binding(
            get: { store.excludedProjectTitles },
            set: { store.setExcludedProjectTitles($0) })
    }
```

**2c. Preview init** — add `excludedProjectTitles: Set<String> = []` and forward:

```swift
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        excludedProjectTitles: Set<String> = [],
        authorizationStatus: EKAuthorizationStatus,
        speechTranscriber: (any SpeechTranscribing)? = nil) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            excludedProjectTitles: excludedProjectTitles,
            authorizationStatus: authorizationStatus)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
    }
```

**2d. New preview** — showcase exclusion. Add a dedicated mock with a titled calendar (the existing `mockReminder` has `calendar == nil`, which would never be excluded):

```swift
private let mockReminderInProject: EKReminder = {
    let eventStore = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "Groceries"
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy milk"
    reminder.calendar = calendar
    return reminder
}()

#Preview("All Excluded") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminderInProject],
        skippedIDs: [],
        excludedProjectTitles: ["Groceries"],
        authorizationStatus: .fullAccess)
}
```

#### 3. `SettingsViewTests` — init args + assertion
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

```swift
        #if os(iOS)
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"])
        #else
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"])
        #endif

        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Text Size"))
        #expect(bodyDescription.contains("Microphone"))
        #expect(bodyDescription.contains("Excluded Projects"))
        #expect(bodyDescription.contains("Done"))
        #if os(iOS)
            #expect(bodyDescription.contains("Landscape"))
        #endif
```

### Verification
#### Automated
- [x] `make test` passes — updated `SettingsViewTests` green (new init args + "Excluded Projects" assertion)
- [x] `make build` compiles both platform `SettingsView` initializers and the `ContentView` `.sheet` branches

#### Manual
- [ ] Run in the `iPhone 17` simulator: Settings → "Excluded Projects" lists the reminder lists (matching Reminders app); toggle a project off → its next reminder disappears from the single-thread view immediately; relaunch → exclusion persists across launch

---

## Phase 4: Phone↔watch sync

Carry the excluded-title set alongside the skip set over WatchConnectivity so the watch filters `visibleReminders` locally.

### Changes

#### 1. `SkippedReminderSyncService` — new store, push, receive
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**1a. Init**:

```swift
        public init(
            session: any SkipSyncSession,
            skipStore: SkippedReminderStore,
            excludeStore: ExcludedProjectStore = ExcludedProjectStore()) {
            self.session = session
            self.skipStore = skipStore
            self.excludeStore = excludeStore
            super.init()
        }
```

**1b. Push method** (next to `pushSkipIDs`):

```swift
        /// Push the full excluded-project title array to the counterpart.
        public func pushExcludedProjectTitles(_ titles: [String]) {
            do {
                try session.updateApplicationContext([PayloadKey.excludedProjectTitles: titles])
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push excluded project titles: \(description, privacy: .public)")
            }
        }
```

**1c. Payload key**:

```swift
        private enum PayloadKey {
            static let skippedReminderIdentifiers = "skippedReminderIdentifiers"
            static let excludedProjectTitles = "excludedProjectTitles"
            static let completeReminderIdentifier = "completeReminderIdentifier"
        }
```

**1d. Receive** — restructure the early-return so the two keys are read independently:

```swift
        public func session(
            _: WCSession,
            didReceiveApplicationContext applicationContext: [String: Any]) {
            // Latest-wins: `updateApplicationContext` transmits the sender's full
            // set, so the received array is authoritative. Replacing (rather than
            // unioning) local values makes a "clear" update ([]) propagate.
            // ReminderStore.reload() prunes stale skip IDs on the next fetch.
            // The two keys are independent — pushSkipIDs and
            // pushExcludedProjectTitles each send a separate application context,
            // so one key may be present without the other.
            if let receivedIDs = applicationContext[PayloadKey.skippedReminderIdentifiers] as? [String] {
                skipStore.save(receivedIDs)
            }
            if let receivedTitles = applicationContext[PayloadKey.excludedProjectTitles] as? [String] {
                excludeStore.save(receivedTitles)
            }
        }
```

**1e. Private dependency**:

```swift
        private let session: any SkipSyncSession
        private let skipStore: SkippedReminderStore
        private let excludeStore: ExcludedProjectStore
```

#### 2. Wire phone hooks
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

After `store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }` (`:34`), add:

```swift
                store.onExcludedProjectsChanged = { titles in service.pushExcludedProjectTitles(titles) }
```

(No change to the `SkippedReminderSyncService(...)` construction — `excludeStore` defaults to `ExcludedProjectStore()` → `AppGroup.defaults` on iOS.)

#### 3. Wire watch hooks
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

After `store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }` (`:19`), add:

```swift
            store.onExcludedProjectsChanged = { titles in service.pushExcludedProjectTitles(titles) }
```

#### 4. Sync tests
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Add (inside the existing `SkippedReminderSyncServiceTests` struct; uses the existing `FakeSession`):

```swift
        // MARK: - Excluded-project push/receive

        @Test
        func pushExcludedProjectTitlesUpdatesApplicationContext() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-push-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-push-\(UUID().uuidString)")
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.pushExcludedProjectTitles(["Work", "Home"])

            let context = try #require(fake.lastContext)
            let titles = try #require(context["excludedProjectTitles"] as? [String])
            #expect(Set(titles) == ["Work", "Home"])
        }

        @Test
        func receiveContextReplacesLocalExcludedTitles() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-recv-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-recv-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["excludedProjectTitles": ["B", "C"]])

            #expect(Set(excludeStore.load()) == ["B", "C"])
        }

        @Test
        func receiveContextMissingExcludedTitleKeyIsNoOp() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-noop-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-noop-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            // A skip-only payload must not clobber exclusions (independent keys).
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

            #expect(excludeStore.load() == ["A"])
        }
```

> Existing receive tests construct the service with `skipStore` only — `excludeStore` defaults to `ExcludedProjectStore()` (App Group), but those payloads carry no `excludedProjectTitles` key, so no cross-write occurs. They remain green. The new `receiveContextMissingExcludedTitleKeyIsNoOp` test uses an isolated `excludeStore` to assert this explicitly.

### Verification
#### Automated
- [x] `make test` passes — new push/receive/no-op sync tests green; all existing `SkippedReminderSyncServiceTests` unchanged and green
- [x] `make build` and `make watch-build` (`xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS Simulator' build`) compile both app entries

#### Manual
- [ ] Exclude a project on the phone → watch hides the reminder after WatchConnectivity delivers the context (watch `visibleReminders` filters locally)
- [ ] Widget with all projects excluded shows `.allDone` (All Done), not a crash — `NextThingWidget.swift` nil-checks `visibleReminders.first`

---

## Final Verification

- [x] `./scripts/test.sh` (full CI pipeline) green: format → SwiftFormat lint → SwiftLint `--strict` → iOS build → watch build → Periphery `--strict` → unit tests → UI/accessibility tests → macOS build + unit tests
- [x] No new Periphery dead-code warnings (e.g. `pushExcludedProjectTitles`, `onExcludedProjectsChanged`, `setExcludedProjectTitles`, `availableProjects` are all referenced from app layers/tests)

---

## Deviations from the structure outline

1. **`EventKitStoring` conformance (Phase 2)**: the structure said to add an `EKEventStore.calendars(for:)` method body "delegating to `self.calendars(for:)`". That would be an invalid redeclaration (and infinite recursion) — the SDK already provides an instance `calendars(for:)` with the exact signature, so the requirement is satisfied without any wrapper (same as the existing `refreshSourcesIfNecessary`). The plan instead documents this and provides a fallback if the compiler disagrees.

2. **Defaulted init parameters (Phases 1 & 3)**: `excludedProjectTitles` is given a default `[]` on both the `ReminderStore` preview/test init and the `ContentView` preview init, rather than a required parameter. This avoids churning ~20 existing `ReminderStore` test call sites and the watch preview init, which the structure's file lists did not mention. Previews/tests that need it pass it explicitly.