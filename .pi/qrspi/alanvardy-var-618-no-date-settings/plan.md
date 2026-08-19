# Implementation Plan

## Overview

Add a "Show tasks with no date" `Toggle` to the Settings screen. When ON, reminders
with `dueDateComponents == nil` appear in the phone app, on the watch, and in the
widget, interleaved with dated reminders by the existing priority/date/title sort.
When OFF, behavior is byte-for-byte today's.

---

## Phase 1: Phone app — toggle, fetch strategy, and persistence

Delivers the end-to-end user-visible feature on iOS/macOS: a Settings toggle that,
when flipped, makes undated reminders appear in the phone list, survive relaunch, and
revert byte-for-byte to today's behavior when off.

### Changes

#### 1. Date-window predicate helper

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift`
**Action**: modify

Add a new `static func` to the existing `ReminderDateFilter` enum, immediately after
`overdueCutoff`:

```swift
/// Returns `true` when a reminder is undated (`date == nil`) or its date falls
/// within the "today or overdue" window `[overdueCutoff, endOfToday]`.
static func isInCurrentWindow(
    _ date: Date?,
    calendar: Calendar = .current,
    now: Date = Date()) -> Bool {
    guard let date else { return true }
    return overdueCutoff(calendar: calendar, now: now) <= date
        && date <= endOfToday(calendar: calendar, now: now)
}
```

#### 2. `ReminderStore` — new flag + conditional fetch/filter

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a new public stored property next to the other public properties (after
`onRemindersChanged`):

```swift
/// When `true`, `reload()` fetches with a nil/nil date predicate and keeps
/// undated reminders plus dated reminders still inside the current window.
/// Each surface sets this before its own `reload()` (phone from the Settings
/// toggle, widget and watch from synced state).
public var showsUndatedReminders = false
```

Replace the entire `reload(clearSkipped:)` method with:

```swift
public func reload(clearSkipped: Bool = false) async {
    guard loadsReminders else { return }
    #if !os(watchOS)
        eventStore.refreshSourcesIfNecessary()
    #endif
    let startDate: Date?
    let endDate: Date?
    if showsUndatedReminders {
        startDate = nil
        endDate = nil
    } else {
        startDate = ReminderDateFilter.overdueCutoff()
        endDate = ReminderDateFilter.endOfToday()
    }
    let predicate = eventStore.predicateForIncompleteReminders(
        withDueDateStarting: startDate,
        ending: endDate,
        calendars: nil)
    let fetched: [EKReminder] = await fetchReminders(matching: predicate)
    let shown = showsUndatedReminders
        ? fetched.filter { ReminderDateFilter.isInCurrentWindow($0.dueDateComponents?.date) }
        : fetched
    reminders = shown
    if clearSkipped {
        skippedIDs = []
        skipStore.save([])
        onSkipSetChanged?([])
    } else {
        let resolved = ReminderSkipLogic.resolve(
            fetched: shown.map(\.calendarItemIdentifier),
            skipped: skipStore.load())
        skippedIDs = Set(resolved)
    }
    onRemindersChanged?()
}
```

Notes:
- The `EventKitStoring` protocol already takes `Date?`/`Date?` — no protocol change.
- `shown` (the filtered set) feeds both `reminders` and skip resolution, so skip
  pruning and the empty-state check see the same bounded set they do today. An
  out-of-window dated reminder fetched by the nil/nil predicate is pruned from the
  skip list exactly like today's out-of-window reminders.

#### 3. `ContentView` — `@AppStorage` + store plumbing

**File**: `SingleThread/ContentView.swift`
**Action**: modify

a) Add the `@AppStorage` next to `showMicrophoneButton` (note `store:` is
`AppGroup.defaults`, unlike the other four prefs which use `.standard` — this one is
load-bearing for the widget in Phase 2):

```swift
@AppStorage("showMicrophoneButton")
private var showMicrophoneButton = true

@AppStorage("showUndatedReminders", store: AppGroup.defaults)
private var showUndatedReminders = false
```

b) Change `.task` and add `.onChange` (both share the store's flag so every existing
`reload()` caller — `start()`, completion, add, pull-to-refresh — inherits it):

```swift
.task {
    store.showsUndatedReminders = showUndatedReminders
    await store.start()
}
.onChange(of: showUndatedReminders) { _, newValue in
    store.showsUndatedReminders = newValue
    Task { await store.reload() }
}
```

c) Pass the new binding into both `SettingsView` initializer branches:

```swift
.sheet(isPresented: $isShowingSettings) {
    #if os(iOS)
        SettingsView(
            appearanceMode: $appearanceMode,
            textSize: $textSize,
            allowsLandscape: $allowsLandscape,
            showMicrophoneButton: $showMicrophoneButton,
            showUndatedReminders: $showUndatedReminders)
    #else
        SettingsView(
            appearanceMode: $appearanceMode,
            textSize: $textSize,
            showMicrophoneButton: $showMicrophoneButton,
            showUndatedReminders: $showUndatedReminders)
    #endif
}
```

#### 4. `SettingsView` — new `Toggle`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

a) Add `showUndatedReminders: Binding<Bool>` to both initializers:

```swift
#if os(iOS)
    init(
        appearanceMode: Binding<AppearanceMode>,
        textSize: Binding<TextSize>,
        allowsLandscape: Binding<Bool>,
        showMicrophoneButton: Binding<Bool>,
        showUndatedReminders: Binding<Bool>) {
        _appearanceMode = appearanceMode
        _textSize = textSize
        _allowsLandscape = allowsLandscape
        _showMicrophoneButton = showMicrophoneButton
        _showUndatedReminders = showUndatedReminders
    }
#else
    init(
        appearanceMode: Binding<AppearanceMode>,
        textSize: Binding<TextSize>,
        showMicrophoneButton: Binding<Bool>,
        showUndatedReminders: Binding<Bool>) {
        _appearanceMode = appearanceMode
        _textSize = textSize
        _showMicrophoneButton = showMicrophoneButton
        _showUndatedReminders = showUndatedReminders
    }
#endif
```

b) Add the `@Binding` property next to `showMicrophoneButton`:

```swift
@Binding private var showMicrophoneButton: Bool
@Binding private var showUndatedReminders: Bool
```

c) Add the `Toggle` after "Show Microphone":

```swift
Toggle(isOn: $showUndatedReminders) {
    Label("Show Undated", systemImage: "calendar.badge.minus")
}
```

d) Update both `#Preview` blocks to pass
`showUndatedReminders: .constant(false)` (and `.constant(true)` in "Dark + Extra
Large" for variety). All four preview call sites must be updated or the target will
not compile.

#### 5. `FakeEventStore` — record predicate dates

**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Add two recording properties and capture the arguments currently ignored:

```swift
private(set) var lastStartDate: Date?
private(set) var lastEndDate: Date?

func predicateForIncompleteReminders(
    withDueDateStarting startDate: Date?,
    ending endDate: Date?,
    calendars _: [EKCalendar]?) -> NSPredicate {
    lastStartDate = startDate
    lastEndDate = endDate
    return NSPredicate(value: true)
}
```

Add two `@Test`s to `ReminderStoreLifecycleTests` (same file):

```swift
@Test
func reloadDefaultUsesWindowPredicate() async {
    let fake = FakeEventStore(fetchResult: [makeReminder(title: "A")])
    let store = testStore(eventStore: fake)

    await store.reload()

    #expect(fake.lastStartDate != nil)
    #expect(fake.lastEndDate != nil)
}

@Test
func reloadWithShowsUndatedUsesNilPredicateAndFiltersWindow() async {
    let undated = makeReminder(title: "Undated")
    let inWindow = makeReminder(title: "Now")
    inWindow.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: Date())
    let outOfWindow = makeReminder(title: "Future")
    outOfWindow.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: Date().addingTimeInterval(40 * 86_400))
    let fake = FakeEventStore(fetchResult: [undated, inWindow, outOfWindow])
    let store = testStore(eventStore: fake)
    store.showsUndatedReminders = true

    await store.reload()

    #expect(fake.lastStartDate == nil)
    #expect(fake.lastEndDate == nil)
    #expect(store.reminders.map(\.title) == ["Undated", "Now"])
}
```

#### 6. `ReminderStore` default-value assertion

**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add one test documenting the new property's default (this file uses the
`loadsReminders: false` pre-populated init; the reload behavior itself must be tested
via `FakeEventStore` in step 5 because `reload` is a no-op under `loadsReminders:
false`):

```swift
@Test
func showsUndatedRemindersDefaultsToFalse() {
    let store = ReminderStore(loadsReminders: false)
    #expect(store.showsUndatedReminders == false)
}
```

#### 7. `ReminderDateFilterTests` — `isInCurrentWindow` cases

**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify

Add to `ReminderDateFilterTests` (reuses its existing `calendar`/`now`/`date(_:in:)`
helpers):

```swift
@Test
func isInCurrentWindowIncludesNilDate() {
    #expect(ReminderDateFilter.isInCurrentWindow(nil, calendar: calendar, now: now))
}

@Test
func isInCurrentWindowIncludesTodaysReminder() {
    #expect(ReminderDateFilter.isInCurrentWindow(date(6), calendar: calendar, now: now))
}

@Test
func isInCurrentWindowIncludesOverdueCutoffBoundary() {
    let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
    #expect(ReminderDateFilter.isInCurrentWindow(cutoff, calendar: calendar, now: now))
}

@Test
func isInCurrentWindowExcludesTomorrow() {
    #expect(!ReminderDateFilter.isInCurrentWindow(date(7), calendar: calendar, now: now))
}

@Test
func isInCurrentWindowExcludesOldOverdue() {
    #expect(!ReminderDateFilter.isInCurrentWindow(date(6, in: .august), calendar: calendar, now: now))
}
```

#### 8. `SettingsView` body-label assertion

**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Pass `showUndatedReminders: .constant(false)` in both `#if os(iOS)` / `#else`
branches of `settingsViewContainsAllPreferenceRows`, and add:

```swift
#expect(bodyDescription.contains("Show Undated"))
```

### Verification

#### Automated
- [x] `make format` applies cleanly; `make lint` passes (`swiftformat --lint` +
  `swiftlint lint --strict` with zero warnings).
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes (this covers the new
  `isInCurrentWindow`, `reload`, default-value, and SettingsView tests). Equivalent:
  `make test`.

#### Manual
- [ ] Run the app (Simulator "iPhone 17"). Create a reminder with no due date
  (e.g. via Reminders.app or the mic dictation phrase "buy milk" with no date).
  Confirm it is **absent** from the list with the toggle OFF.
- [ ] Open Settings, flip "Show Undated" ON. The undated reminder appears in the
  list, interleaved by priority/title; its date line is hidden.
- [ ] Flip OFF → the undated reminder disappears; dated reminders outside the
  30-day window never appear in either state.
- [ ] Relaunch the app → the toggle state persists (ON stays ON).

---

## Phase 2: Widget mirror — read the App Group flag

Makes `NextThingProvider` honor the same toggle by reading the shared App Group value
before its `reload()`. No new API — consumes the App Group persistence from Phase 1.

### Changes

#### 1. `NextThingProvider.makeEntry()` reads the flag

**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

In `makeEntry()`, set the fresh store's flag before `reload()`:

```swift
case .fullAccess:
    let store = ReminderStore(loadsReminders: true)
    store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
    await store.reload()
    // ...unchanged empty/allDone/reminder branching...
```

No other change: the existing `store.onRemindersChanged →
WidgetCenter.shared.reloadAllTimelines()` path (`SingleThreadApp.swift`) already
re-renders the widget after a phone toggle, and the widget's date-line rendering
already hides the line when `dueDate == nil`.

### Verification

#### Automated
- [ ] `make build` passes (builds the `SingleThread` scheme, which builds the
  embedded widget extension target).
- [ ] `make lint` passes.

#### Manual
- [ ] Toggle "Show Undated" ON on the phone; add an undated reminder; open the Today
  view (or glance) — the widget shows the undated reminder.
- [ ] Toggle OFF → the widget stops showing the undated reminder (may take up to the
  15-minute `.after` refresh or until a phone change triggers
  `reloadAllTimelines()`).

---

## Phase 3: Watch mirror — combined WatchConnectivity context

Pushes the toggle phone→watch as one combined `updateApplicationContext` (not a
second payload, which would clobber the skip IDs) and receives it on the watch.

### Changes

#### 1. Combined push + receive hook

**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

a) Add the receive hook next to `onCompleteReminderReceived`:

```swift
/// Hook invoked on the watch when the iPhone's "show undated reminders"
/// preference arrives in a combined application context. Passes the new value.
/// Same write-once-before-activate / `nonisolated(unsafe)` rationale as
/// `onCompleteReminderReceived`.
public nonisolated(unsafe) var onShowUndatedRemindersReceived: ((Bool) -> Void)?
```

b) Replace `pushSkipIDs(_:)` with a combined push:

```swift
/// Push the full skip array plus the "show undated reminders" flag to the
/// counterpart as one latest-wins application context.
public func push(_ skipIDs: [String], showUndatedReminders: Bool) {
    do {
        try session.updateApplicationContext([
            PayloadKey.skippedReminderIdentifiers: skipIDs,
            PayloadKey.showUndatedReminders: showUndatedReminders,
        ])
    } catch {
        let description = error.localizedDescription
        Self.logger.error("Failed to push sync context: \(description, privacy: .public)")
    }
}
```

c) Read both keys in `didReceiveApplicationContext` (replace the single
`guard … else { return }` so a missing key no longer short-circuits the other):

```swift
public func session(
    _: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]) {
    if let receivedIDs = applicationContext[PayloadKey.skippedReminderIdentifiers] as? [String] {
        skipStore.save(receivedIDs)
    }
    if let received = applicationContext[PayloadKey.showUndatedReminders] as? Bool {
        onShowUndatedRemindersReceived?(received)
    }
}
```

d) Add the new payload key:

```swift
private enum PayloadKey {
    static let skippedReminderIdentifiers = "skippedReminderIdentifiers"
    static let completeReminderIdentifier = "completeReminderIdentifier"
    static let showUndatedReminders = "showUndatedReminders"
}
```

#### 2. `ReminderStore` — change-observation hook

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Replace the Phase 1 property with a `didSet`-observing version, and add the hook:

```swift
public var showsUndatedReminders = false {
    didSet {
        guard showsUndatedReminders != oldValue else { return }
        onShowUndatedRemindersChanged?(showsUndatedReminders)
    }
}

/// Hook invoked when `showsUndatedReminders` changes. Wired by the iPhone app
/// layer to push the combined sync context to the watch.
public var onShowUndatedRemindersChanged: ((Bool) -> Void)?
```

(`didSet`/`oldValue` on `@Observable` properties is supported by SE-0395 and current
Xcode 16+/Swift 6 toolchains; this project's Swift 6.0 mode also fires on equal
assignments, hence the explicit `oldValue` guard to avoid redundant pushes. If a
local toolchain rejects the observer, fall back to firing `onShowUndatedRemindersChanged`
from the two assignment sites in `ContentView`'s `.task`/`.onChange` instead.)

#### 3. Phone wiring — combined push on both changes

**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Replace the `#if os(iOS)` sync block (hoist `skipStore` into a local so the toggle
hook can read the *persisted* skip list — at `.task` launch time the in-memory
`store.skippedIDs` is still empty, and pushing `[]` would clobber the watch's skip
list before `reload()` resolves it):

```swift
#if os(iOS)
    if WCSession.isSupported() {
        let skipStore = SkippedReminderStore()
        let service = SkippedReminderSyncService(
            session: WCSession.default,
            skipStore: skipStore)
        // Assign the handler before activating (same invariant as today).
        service.onCompleteReminderReceived = { [weak store] identifier in
            Task { await store?.completeReminder(identifier: identifier) }
        }
        service.activate()
        store.onSkipSetChanged = { ids in
            service.push(ids, showUndatedReminders: store.showsUndatedReminders)
        }
        store.onShowUndatedRemindersChanged = { newValue in
            service.push(skipStore.load(), showUndatedReminders: newValue)
        }
        store.onCompleteReminder = { identifier in
            service.requestCompleteReminder(identifier)
        }
    }
#endif
```

(The `onShowUndatedRemindersChanged` hook uses `skipStore.load()` rather than
`store.skippedIDs` specifically so the launch-time `.task` assignment pushes the
persisted skip list, not the not-yet-resolved empty in-memory set.)

#### 4. Watch wiring — receive the toggle + combined push

**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

```swift
if WCSession.isSupported() {
    let service = SkippedReminderSyncService(
        session: WCSession.default,
        skipStore: SkippedReminderStore())
    service.onShowUndatedRemindersReceived = { [weak store] value in
        Task {
            store?.showsUndatedReminders = value
            await store?.reload()
        }
    }
    service.activate()
    store.onSkipSetChanged = { ids in
        service.push(ids, showUndatedReminders: store.showsUndatedReminders)
    }
    store.onCompleteReminder = { identifier in
        service.requestCompleteReminder(identifier)
    }
}
```

The watch never wires `onShowUndatedRemindersChanged`, so receiving the toggle and
setting the flag does not echo a push back (no ping-pong).

#### 5. Sync-service tests — combined context

**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

a) Update the two existing `pushSkipIDs…` tests to the combined API:

```swift
@Test
func pushUpdatesApplicationContext() throws {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push")
    let service = SkippedReminderSyncService(session: fake, skipStore: store)
    service.push(["A", "B", "C"], showUndatedReminders: false)
    let context = try #require(fake.lastContext)
    let ids = try #require(context["skippedReminderIdentifiers"] as? [String])
    #expect(Set(ids) == ["A", "B", "C"])
}

@Test
func pushHandlesError() {
    let fake = FakeSession()
    fake.pushShouldThrow = true
    let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push-error")
    let service = SkippedReminderSyncService(session: fake, skipStore: store)
    service.push(["A"], showUndatedReminders: false)
    #expect(Bool(true))
}
```

b) Add combined-context and toggle-receive tests:

```swift
@Test
func pushCarriesCombinedContext() throws {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-sync-combined")
    let service = SkippedReminderSyncService(session: fake, skipStore: store)
    service.push(["A"], showUndatedReminders: true)
    let context = try #require(fake.lastContext)
    let flag = try #require(context["showUndatedReminders"] as? Bool)
    #expect(flag)
}

@Test
func receiveContextFiresToggleHookAndKeepsSkipIDs() {
    let fake = FakeSession()
    let key = "test-sync-toggle-\(UUID().uuidString)"
    let store = SkippedReminderStore(defaults: .standard, key: key)
    store.save(["A"])
    let service = SkippedReminderSyncService(session: fake, skipStore: store)
    var received: Bool?
    service.onShowUndatedRemindersReceived = { received = $0 }
    service.session(
        WCSession.default,
        didReceiveApplicationContext: [
            "skippedReminderIdentifiers": ["B"],
            "showUndatedReminders": true,
        ])
    #expect(received == true)
    #expect(Set(store.load()) == ["B"])
}

@Test
func receiveContextFalsePropagates() {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-sync-toggle-false")
    let service = SkippedReminderSyncService(session: fake, skipStore: store)
    var received: Bool?
    service.onShowUndatedRemindersReceived = { received = $0 }
    service.session(
        WCSession.default,
        didReceiveApplicationContext: [
            "skippedReminderIdentifiers": [String](),
            "showUndatedReminders": false,
        ])
    #expect(received == false)
    #expect(store.load().isEmpty)
}
```

The three existing receive tests (`receiveContextReplacesLocalIDs`,
`receiveContextClearPropagates`, `receiveContextHandlesEmptyPayload`,
`receiveContextHandlesMalformedPayload`) remain valid — the new `if let` guards
preserve the skip-store behavior for empty/malformed payloads.

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes (extended
  `SkippedReminderSyncServiceTests` included).
- [ ] `make watch-build` passes (compiles the watch app + its combined-push wiring).

#### Manual
- [ ] Toggle ON on the phone → the undated reminder appears on the watch within a few
  seconds (via `updateApplicationContext`).
- [ ] Skip a reminder on the phone → the combined context still carries both keys; the
  watch's skip list is **not** clobbered.
- [ ] With toggle ON and a skip present, relaunch the phone → the watch receives the
  combined context with the persisted skip list intact.
- [ ] Turn the watch off and on (or reconnect) → it converges via
  `updateApplicationContext` auto-delivery, same as skip IDs do today.

---

## Testing Checkpoints

- **After Phase 1**: unit suite green; phone app toggles undated reminders in/out,
  persists across relaunch; dated reminders outside the window never appear.
- **After Phase 2**: `make build` + `make lint` green; widget reflects the same toggle
  as the phone via the App Group.
- **After Phase 3**: full suite green; watch mirrors the phone toggle; skip sync and
  toggle sync share one coherent latest-wins context.
- **Final gate**: [ ] `./scripts/test.sh` passes (format, lint, iOS build, watch build,
  Periphery, unit tests, UI tests + accessibility audit, macOS build + unit tests) —
  identical to CI.