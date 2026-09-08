# Implementation Plan

## Overview

Add a user-selectable "Sort By" preference (Priority / Due Date / Title) to the
settings screen so the choice controls `visibleReminders.first` everywhere it is
consumed — phone, macOS, widget, App Intents, and watch — defaulting to
`.priority` (today's behavior) so existing installs see no change.

---

## Phase 1: `SortOption` + option-aware comparator + `SortOptionStore`

Delivers the three orderings as pure, unit-tested Core logic plus the
persistence seam. No UI or store wiring yet — the comparator default is today's
behavior, so this lands with zero observable change.

### Changes

#### 1. New `SortOption` enum + `SortOptionStore`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift` (new)
**Action**: create

```swift
import Foundation

/// The user's preferred ordering for reminder display, persisted in the App
/// Group under ``defaultsKey``. Mirrors `ReminderPriority` (pure Core logic,
/// no SwiftUI); presentation lives in the app target.
public enum SortOption: String, CaseIterable, Sendable {
    /// Today's compound order: priority rank → due date → title.
    case priority
    /// Due date soonest-first (dated before undated) → title.
    case dueDate
    /// Case-insensitive title A→Z → due date.
    case title

    /// Single shared key used by `SortOptionStore`, the app's `@AppStorage`,
    /// and nowhere else as a raw literal.
    public static let defaultsKey = "sortOption"
}

/// Persists the sort option in UserDefaults, mirroring `SkippedReminderStore`.
public struct SortOptionStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = SortOption.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Loads the persisted option, falling back to `.priority` when the key is
    /// missing or holds an unrecognized raw value.
    public func load() -> SortOption {
        guard let raw = defaults.string(forKey: key), let option = SortOption(rawValue: raw) else {
            return .priority
        }
        return option
    }

    public func save(_ option: SortOption) {
        defaults.set(option.rawValue, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Option-aware comparator in `ReminderSort`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`
**Action**: modify (full rewrite of the 36-line file)

The three tiers become private helpers; the existing 2-arg comparator delegates
to `.priority`, preserving bit-for-bit the current ordering (rank → date →
title) so `titles(of:)` in the tests and any existing caller keep compiling.

```swift
import EventKit

/// Pure ordering for reminders across the user-selectable ``SortOption`` modes.
public nonisolated enum ReminderSort {
    /// Backward-compatible entry point: the legacy compound order
    /// (priority → due date → title), i.e. ``SortOption/priority``.
    public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        areInIncreasingOrder(lhs, rhs, using: .priority)
    }

    /// Option-aware comparator.
    public static func areInIncreasingOrder(
        _ lhs: EKReminder,
        _ rhs: EKReminder,
        using option: SortOption) -> Bool {
        switch option {
        case .priority:
            if let rank = comparePriorities(lhs, rhs) { return rank }
            if let date = compareDueDates(lhs, rhs) { return date }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .dueDate:
            if let date = compareDueDates(lhs, rhs) { return date }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .title:
            let comparison = titleComparison(lhs, rhs)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) { return date }
            return false
        }
    }

    // MARK: Private

    private static func comparePriorities(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool? {
        let lhsRank = ReminderPriority.rank(for: lhs.priority)
        let rhsRank = ReminderPriority.rank(for: rhs.priority)
        switch (lhsRank, rhsRank) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return nil
        }
    }

    private static func compareDueDates(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool? {
        let lhsDate = lhs.dueDateComponents?.date
        let rhsDate = rhs.dueDateComponents?.date
        switch (lhsDate, rhsDate) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return nil
        }
    }

    private static func titleComparison(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    }
}
```

#### 3. Tests
**File**: `SingleThreadTests/SortOptionTests.swift` (new)
**Action**: create — `SortOptionTests` (Core raw values/allCases/defaultsKey now;
presentation cases added in Phase 2) and `SortOptionStoreTests`.

```swift
import SingleThreadCore
import Testing

struct SortOptionTests {
    @Test
    func rawValuesMatchPayloadKeys() {
        #expect(SortOption.priority.rawValue == "priority")
        #expect(SortOption.dueDate.rawValue == "dueDate")
        #expect(SortOption.title.rawValue == "title")
    }

    @Test
    func allCasesCoverAllOptions() {
        #expect(SortOption.allCases == [.priority, .dueDate, .title])
    }

    @Test
    func defaultsKeyIsTheSharedConstant() {
        #expect(SortOption.defaultsKey == "sortOption")
    }
}

struct SortOptionStoreTests {
    @Test
    func loadsPriorityDefaultWhenMissing() {
        let store = SortOptionStore(defaults: .standard, key: "test-sort-missing-\(UUID().uuidString)")
        #expect(store.load() == .priority)
    }

    @Test
    func loadsPriorityDefaultWhenInvalid() {
        let key = "test-sort-invalid-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set("notAValue", forKey: key)
        let store = SortOptionStore(defaults: .standard, key: key)
        #expect(store.load() == .priority)
    }

    @Test
    func saveAndLoadRoundTrip() {
        let key = "test-sort-roundtrip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = SortOptionStore(defaults: .standard, key: key)
        store.save(.dueDate)
        #expect(store.load() == .dueDate)
    }
}
```

**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — add a `titles(of:using:)` helper next to the existing
`titles(of:)` (line ~297) and new `@Test`s in `ReminderSortTests`.

```swift
// new helper, alongside titles(of:):
private func titles(of reminders: [EKReminder], using option: SortOption) -> [String] {
    reminders.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: option) }.map(\.title)
}

// new tests in ReminderSortTests:
@Test
func priorityOptionMatchesLegacyComparator() {
    let a = makeReminder(title: "a", priority: 9, dateComponents: date(2))
    let b = makeReminder(title: "b", priority: 1)
    let viaPriority = [a, b].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .priority) }
        .map(\.title)
    let viaLegacy = [a, b].sorted { ReminderSort.areInIncreasingOrder($0, $1) }.map(\.title)
    #expect(viaPriority == viaLegacy)
}

@Test
func dueDateSortsSoonestFirstIgnoringPriority() {
    let lowSoon = makeReminder(title: "sooner", priority: 9, dateComponents: date(2))
    let highLater = makeReminder(title: "later", priority: 1, dateComponents: date(10))
    #expect(titles(of: [lowSoon, highLater], using: .dueDate) == ["sooner", "later"])
}

@Test
func dueDateSortsDatedBeforeUndated() {
    let undated = makeReminder(title: "undated")
    let dated = makeReminder(title: "dated", dateComponents: date(3))
    #expect(titles(of: [undated, dated], using: .dueDate) == ["dated", "undated"])
}

@Test
func titleSortIsCaseInsensitiveAlphabetical() {
    let zebra = makeReminder(title: "Zebra", priority: 1)   // priority ignored
    let apple = makeReminder(title: "apple", priority: 9)
    #expect(titles(of: [zebra, apple], using: .title) == ["apple", "Zebra"])
}

@Test
func titleSortBreaksTiesByDueDate() {
    let later = makeReminder(title: "Same", dateComponents: date(10))
    let sooner = makeReminder(title: "Same", dateComponents: date(2))
    let sorted = [later, sooner].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .title) }
    #expect(sorted[0].dueDateComponents?.day == 2)
    #expect(sorted[1].dueDateComponents?.day == 10)
}
```

### Verification

#### Automated
- [x] `make test` — all three comparators pass; the existing 2-arg `ReminderSortTests` cases are unchanged and still pass
- [x] `SortOptionTests` (`allCases`, raw values, `defaultsKey`) pass
- [x] `SortOptionStoreTests` (default-on-missing/invalid, round-trip) pass

#### Manual
- [ ] `make build` succeeds (no behavior change on device — reminders still order by priority → date → title)

---

## Phase 2: Store wiring + persistence + Settings picker (iPhone/macOS end-to-end)

User can choose a sort in Settings; the choice persists to the App Group and
`visibleReminders.first` re-sorts instantly on device.

### Changes

#### 1. `ReminderStore` learns the sort
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add three members and thread `sortOption` into `visibleReminders`:

```swift
// near the other public properties (after `authorizationStatus`):
/// The active sort ordering. Direct assignment (e.g. launch injection) does not
/// fire hooks; use `setSortOption` for user-initiated changes.
public var sortOption: SortOption = .priority

/// Hook fired when the user changes sort (watch push, Phase 4). Wired by the
/// app layer; Core never reads UserDefaults.
public var onSortOptionChanged: ((SortOption) -> Void)?

// in `visibleReminders`, replace the `.sorted` line:
.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }

// new method, place near the other public mutations:
/// Assigns a new sort option, firing hooks only on an actual change so a
/// redundant setting (or widget/intent process with nil hooks) is a no-op.
public func setSortOption(_ option: SortOption) {
    guard option != sortOption else { return }
    sortOption = option
    onSortOptionChanged?(option)
    onRemindersChanged?()
}
```

#### 2. Presentation properties in the app target
**File**: `SingleThread/SortOption+Presentation.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

// MARK: - SortOption presentation

/// SwiftUI presentation for the Core `SortOption`, mirroring `AppearanceMode`
/// / `TextSize` (Core stays SwiftUI-free; the app target owns `title`/`systemImage`).
extension SortOption {
    /// Human-readable label shown in the settings picker.
    var title: String {
        switch self {
        case .priority: "Priority"
        case .dueDate: "Due Date"
        case .title: "Title"
        }
    }

    /// SF Symbol shown alongside the label in the picker.
    var systemImage: String {
        switch self {
        case .priority: "exclamationmark.3"
        case .dueDate: "calendar"
        case .title: "textformat.abc"
        }
    }
}
```

#### 3. `ContentView` persists and applies the sort
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add an `@AppStorage` (App Group, so the widget can read it in Phase 3), an
`.onChange` bridging it to the store, and pass the binding into `SettingsView`.

```swift
// after `@AppStorage("showMicrophoneButton")` (line ~126):
@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)
private var sortOption = SortOption.priority
```

In `body`'s modifier chain, add the `.onChange` after `.task`:

```swift
.task {
    await store.start()
}
.onChange(of: sortOption) { _, newValue in
    store.setSortOption(newValue)
}
```

Pass `sortOption: $sortOption` to both `SettingsView` calls inside `.sheet`:

```swift
#if os(iOS)
    SettingsView(
        appearanceMode: $appearanceMode,
        textSize: $textSize,
        allowsLandscape: $allowsLandscape,
        showMicrophoneButton: $showMicrophoneButton,
        sortOption: $sortOption)
#else
    SettingsView(
        appearanceMode: $appearanceMode,
        textSize: $textSize,
        showMicrophoneButton: $showMicrophoneButton,
        sortOption: $sortOption)
#endif
```

#### 4. `SettingsView` gains the "Sort By" picker
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Add `sortOption` to both platform inits, a `@Binding` property, and a `Picker`
row (place it after "Text Size", before the iOS-only toggle):

```swift
// iOS init gains:           sortOption: Binding<SortOption>
// non-iOS init gains:       sortOption: Binding<SortOption>
// body of each init gains:  _sortOption = sortOption

// new row, after the "Text Size" Picker:
Picker("Sort By", selection: $sortOption) {
    ForEach(SortOption.allCases, id: \.self) { option in
        Label(option.title, systemImage: option.systemImage)
            .tag(option)
    }
}

// new property:
@Binding private var sortOption: SortOption
```

Update both `#Preview` blocks to pass `sortOption: .constant(.priority)`.

#### 5. `SingleThreadApp` injects the persisted option at launch
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Right after `self.store = store`, before any hook wiring, assign directly so no
hook fires at startup (no redundant widget reload / watch push):

```swift
self.store = store
store.sortOption = SortOptionStore().load()
```

### Verification

#### Automated
- [x] `make test` — new `SortOptionTests` presentation cases (`title`, `systemImage`) pass
- [x] `make test` — updated `SettingsViewTests` passes the binding and asserts `String(describing: view.body)` contains `"Sort By"`
- [x] `make test` — new `ReminderStoreTests` cases pass (see snippet below)
- [x] `make mac-build` — the non-iOS (now 4-binding) `SettingsView` init stays in sync and compiles

New `ReminderStoreTests` cases (in `ReminderStoreTests`, reuse the existing
file-private `makeReminder(title:priority:dateComponents:)`):

```swift
@Test
func setSortOptionReordersVisibleReminders() {
    let highLater = makeReminder(title: "HighLater", priority: 1, dateComponents: DateComponents(year: 2024, month: 1, day: 10))
    let lowSooner = makeReminder(title: "LowSooner", priority: 9, dateComponents: DateComponents(year: 2024, month: 1, day: 2))
    let store = ReminderStore(loadsReminders: false, reminders: [lowSooner, highLater], skippedIDs: [], authorizationStatus: .fullAccess)
    #expect(store.visibleReminders.map(\.title) == ["HighLater", "LowSooner"]) // default .priority
    store.setSortOption(.dueDate)
    #expect(store.visibleReminders.map(\.title) == ["LowSooner", "HighLater"])
}

@Test
func setSortOptionFiresBothHooks() {
    let rem = makeReminder(title: "A")
    let store = ReminderStore(loadsReminders: false, reminders: [rem], skippedIDs: [], authorizationStatus: .fullAccess)
    var received: SortOption?
    var remindersChanged = false
    store.onSortOptionChanged = { received = $0 }
    store.onRemindersChanged = { remindersChanged = true }
    store.setSortOption(.title)
    #expect(received == .title)
    #expect(remindersChanged)
}

@Test
func setSortOptionIsIdempotent() {
    let store = ReminderStore(loadsReminders: false, reminders: [], skippedIDs: [], authorizationStatus: .fullAccess)
    var fired = 0
    store.onSortOptionChanged = { _ in fired += 1 }
    store.setSortOption(.title)
    store.setSortOption(.title)
    store.setSortOption(.title)
    #expect(fired == 1)
}
```

Updated `SettingsViewTests` (both init branches gain `sortOption: .constant(.priority)`;
add one assertion):

```swift
#expect(bodyDescription.contains("Sort By"))
```

#### Manual
- [ ] Open Settings → "Sort By" → pick "Due Date" then "Title": the current-reminder card reorders immediately
- [ ] Quit and relaunch the app: the chosen sort persists
- [ ] With "Priority" selected, behavior is identical to before this change

---

## Phase 3: Widget + App Intents read the shared sort

The extension processes apply the persisted option before deriving `.first`, so
the widget and Complete/Skip actions stay consistent with the phone.

### Changes

#### 1. Widget provider applies the sort before reading `.first`
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — in `NextThingProvider.makeEntry`, between store creation and
`reload()` (line ~56):

```swift
let store = ReminderStore(loadsReminders: true)
store.setSortOption(SortOptionStore().load())
await store.reload()
```

#### 2. Both App Intents apply the sort before acting
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify — same two lines in `CompleteReminderIntent.perform()` and
`SkipReminderIntent.perform()`:

```swift
let store = ReminderStore(loadsReminders: true)
store.setSortOption(SortOptionStore().load())
await store.reload()
```

> Safe in these processes: `setSortOption`'s hooks are nil (no closure wiring
> exists in the widget/intent process), and the App Group entitlement on the
> widget makes `SortOptionStore().load()` read the phone-written value.

### Verification

#### Automated
- [x] `make test` — unit tests build `SingleThreadCore` (both intents live there) and pass
- [x] `make build` — builds the embedded `SingleThreadWidget` appex with the new `setSortOption` call

#### Manual
- [ ] Change sort on iPhone → the widget's "Next Thing" shows the same first reminder (may take up to the 15-min refresh; pull the widget or wait)
- [ ] Trigger widget Complete/Skip → it targets the correctly-sorted first reminder

---

## Phase 4: Watch sync over the existing WatchConnectivity channel

The iPhone pushes the option alongside the skip list; the watch saves it via its
local `SortOptionStore()` (`.standard` fallback — no App Group entitlement) and
applies it through a new receive hook.

### Changes

#### 1. Extend the sync service with combined, atomic contexts
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add `sortStore` (default `SortOptionStore()`), `onSortOptionReceived`, and a
`sortOption` payload key; make **every** `updateApplicationContext` carry both
keys so a skip-only push can't clobber the sort value on the watch
(`updateApplicationContext` is latest-wins):

```swift
// init gains a trailing parameter:
public init(
    session: any SkipSyncSession,
    skipStore: SkippedReminderStore,
    sortStore: SortOptionStore = SortOptionStore()) {
    self.session = session
    self.skipStore = skipStore
    self.sortStore = sortStore
    super.init()
}

// new hook next to onCompleteReminderReceived (same nonisolated(unsafe) rationale):
public nonisolated(unsafe) var onSortOptionReceived: ((SortOption) -> Void)?

// pushSkipIDs now emits BOTH keys:
public func pushSkipIDs(_ ids: [String]) {
    do {
        try session.updateApplicationContext([
            PayloadKey.skippedReminderIdentifiers: ids,
            PayloadKey.sortOption: sortStore.load().rawValue,
        ])
    } catch { /* existing error log */ }
}

// new API:
public func pushSortOption(_ option: SortOption) {
    sortStore.save(option)
    do {
        try session.updateApplicationContext([
            PayloadKey.skippedReminderIdentifiers: skipStore.load(),
            PayloadKey.sortOption: option.rawValue,
        ])
    } catch { /* existing error log */ }
}

// didReceiveApplicationContext reads both keys (no early return):
public func session(
    _: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]) {
    if let receivedIDs = applicationContext[PayloadKey.skippedReminderIdentifiers] as? [String] {
        skipStore.save(receivedIDs)
    }
    if let rawValue = applicationContext[PayloadKey.sortOption] as? String,
       let option = SortOption(rawValue: rawValue) {
        sortStore.save(option)
        let handler = onSortOptionReceived
        handler?(option)
    }
}

// PayloadKey gains:
static let sortOption = "sortOption"

// new stored property:
private let sortStore: SortOptionStore
```

#### 2. iPhone pushes on change
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify — in the iOS `WCSession.isSupported()` block, next to the
existing `store.onSkipSetChanged` wiring:

```swift
store.onSortOptionChanged = { option in service.pushSortOption(option) }
```

#### 3. Watch loads persisted sort at launch and applies received sorts
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

```swift
self.store = store
// Restore the last-received sort (persisted to .standard on receive) so the
// watch shows the correct order even before the next context push arrives.
store.sortOption = SortOptionStore().load()

if WCSession.isSupported() {
    let service = SkippedReminderSyncService(
        session: WCSession.default,
        skipStore: SkippedReminderStore())
    // Set before activate() — same write-once-before-activate invariant as
    // onCompleteReminderReceived.
    service.onSortOptionReceived = { [weak store] option in
        store?.setSortOption(option)
    }
    service.activate()
    store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }
    store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
}
```

> Note: the watch does **not** set `store.onSortOptionChanged`, so receiving a
> sort never echoes a push back to the phone.

#### 4. Tests
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify — pass an explicit isolated `sortStore` to every existing
service construction (avoids touching `AppGroup.defaults` during tests), and add
the new cases below.

```swift
// Update each construction, e.g.:
let sortStore = SortOptionStore(defaults: .standard, key: "test-sync-sort-\(UUID().uuidString)")
let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: sortStore)

// New cases:

@Test
func pushSkipIDsIncludesSortOption() throws {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: "test-push-skip-\(UUID().uuidString)")
    let sortStore = SortOptionStore(defaults: .standard, key: "test-push-sort-\(UUID().uuidString)")
    sortStore.save(.dueDate)
    let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
    service.pushSkipIDs(["A"])
    let context = try #require(fake.lastContext)
    #expect(context["sortOption"] as? String == "dueDate")
    #expect(Set(context["skippedReminderIdentifiers"] as? [String] ?? []) == ["A"])
}

@Test
func pushSortOptionIncludesSkipIDs() throws {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: "test-push-sort-skip-\(UUID().uuidString)")
    skipStore.save(["X"])
    let sortStore = SortOptionStore(defaults: .standard, key: "test-push-sort-sort-\(UUID().uuidString)")
    let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
    service.pushSortOption(.title)
    let context = try #require(fake.lastContext)
    #expect(context["sortOption"] as? String == "title")
    #expect(Set(context["skippedReminderIdentifiers"] as? [String] ?? []) == ["X"])
}

@Test
func receiveContextSavesSortAndFiresHook() {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: "test-recv-skip-\(UUID().uuidString)")
    let sortStore = SortOptionStore(defaults: .standard, key: "test-recv-sort-\(UUID().uuidString)")
    let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
    var received: SortOption?
    service.onSortOptionReceived = { received = $0 }
    service.session(WCSession.default, didReceiveApplicationContext: [
        "skippedReminderIdentifiers": ["A"],
        "sortOption": "title",
    ])
    #expect(sortStore.load() == .title)
    #expect(received == .title)
}

@Test
func receiveContextLeavesSortUnchangedOnMissingOrMalformedKey() {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: "test-recv-skip-bad-\(UUID().uuidString)")
    let sortStore = SortOptionStore(defaults: .standard, key: "test-recv-sort-bad-\(UUID().uuidString)")
    sortStore.save(.dueDate)
    let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
    var received = false
    service.onSortOptionReceived = { _ in received = true }
    service.session(WCSession.default, didReceiveApplicationContext: ["sortOption": "notAValue"])
    #expect(sortStore.load() == .dueDate) // unchanged
    #expect(!received)
    service.session(WCSession.default, didReceiveApplicationContext: [:])
    #expect(sortStore.load() == .dueDate) // unchanged
}
```

### Verification

#### Automated
- [x] `make watch-build` — watch app compiles with the new wiring
- [x] `make test` — updated `SkippedReminderSyncServiceTests` (combined push/receive, malformed/missing sort key) pass

#### Manual
- [ ] Change sort on iPhone → the Apple Watch companion shows the same first reminder
- [ ] Skip a reminder on the watch → the phone's skip list still syncs (and its sort is not reverted)

---

## Testing Checkpoints

- **After Phase 1**: all three comparators pass unit tests; existing 2-arg sort tests unchanged; `SortOptionStore` round-trips with `.priority` default.
- **After Phase 2**: Settings shows "Sort By"; picking an option re-sorts the card and persists across relaunch; `setSortOption` is idempotent and fires `onSortOptionChanged` + `onRemindersChanged`.
- **After Phase 3**: widget + intents compile and honor the persisted option; widget Skip/Complete target the correctly-sorted first reminder.
- **After Phase 4**: watch builds; sync service tests cover combined push and receive; iPhone→watch sort change propagates.

## Notes & Carried Risks

- **Idempotent `setSortOption`** avoids a redundant `onRemindersChanged`
  (widget-timeline reload + watch push) on every launch. Launch injection uses a
  direct property assignment, not `setSortOption`, so no hook fires at startup.
- **Combined atomic context**: `updateApplicationContext` is latest-wins; both
  push methods emit both keys, so a skip-only push no longer drops the sort value
  on the watch. (The symmetric watch→phone skip push carries the watch's last
  received sort; since the watch only echoes what the phone sent, the only
  divergence window is an in-flight race where the phone changes sort while a
  watch skip is pending — self-corrects on the next phone-side `setSortOption`.)
- **macOS guard**: the sync service is already `#if os(iOS) || os(watchOS)`;
  macOS compiles via the same `@AppStorage`+`SortOptionStore` read (macOS holds
  the App Group entitlement) and has no `onSortOptionChanged` subscriber.
- **Watch read-only EventKit**: the watch applies the sort only to its own fetch;
  if fetch sets diverge, "first" can still differ even with a shared sort.
- **`systemImage` now tested**: unlike the existing `AppearanceMode`/`TextSize`
  gap, `SortOption.title`/`systemImage` get explicit coverage in Phase 2.
- Out of scope (per design): sort direction, Created/Modified key, per-list
  ordering, and any EventKit eligibility-window change.