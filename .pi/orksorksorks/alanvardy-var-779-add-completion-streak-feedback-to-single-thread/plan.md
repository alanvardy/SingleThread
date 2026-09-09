# Implementation Plan

## Overview

Add a transient "You've cleared N today" overlay on the single card, driven by a new per-calendar-day completion counter (`DailyCompletionStore`) that auto-rolls over at midnight. The overlay mirrors `CompletionGlow`'s trigger/auto-dismiss pattern, is preference-gated behind a `showCompletionMomentum` toggle, and is wired into `ReminderStore`'s existing complete/undo paths.

---

## Phase 1: `DailyCompletionStore` — persistence layer

### Changes

#### 1. New: `DailyCompletionStore.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/DailyCompletionStore.swift`
**Action**: create

```swift
import Foundation

/// Tracks today's completion count in App Group UserDefaults, resetting at
/// midnight (device-local `Calendar.current`). A lazy day-rollover on
/// `increment()` compares the stored start-of-day marker against today's
/// start-of-day — if they differ, the count resets to 1 and the marker is
/// updated. Day boundaries follow `ReminderDateFilter` semantics: device-local
/// only, no UTC, no timezone-agnostic tracking.
///
/// Production writes stay within `0...100` because `increment()` runs only
/// while `canMutate` is true (count < 100), `decrement()` clamps at 0, and
/// `resetForTesting()` writes 0. The `--seed` UI-test seam is the deliberate
/// exception — it writes `completionTodayCount` verbatim, unclamped.
public struct DailyCompletionStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        markerKey: String = Self.defaultsMarkerKey,
        countKey: String = Self.defaultsCountKey) {
        self.defaults = defaults
        self.markerKey = markerKey
        self.countKey = countKey
    }

    // MARK: Public

    /// Key for the start-of-day `TimeInterval` marker.
    public static let defaultsMarkerKey = "completionDayMarker"

    /// Key for today's completion count.
    public static let defaultsCountKey = "completionTodayCount"

    /// Today's completion count. Reads `UserDefaults.integer(forKey:)`,
    /// which returns 0 when the key is absent.
    public var todayCount: Int {
        defaults.integer(forKey: countKey)
    }

    /// The stored start-of-day `TimeInterval`. Returns 0 when absent.
    public var dayMarker: TimeInterval {
        defaults.double(forKey: markerKey)
    }

    /// Increments today's count by 1. On first call (or after midnight),
    /// resets the count to 1 and writes the new start-of-day marker.
    /// Otherwise increments normally.
    public func increment() {
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        if dayMarker != todayStart {
            defaults.set(1, forKey: countKey)
            defaults.set(todayStart, forKey: markerKey)
        } else {
            defaults.set(todayCount + 1, forKey: countKey)
        }
    }

    /// Decrements today's count by 1, clamping at zero.
    public func decrement() {
        let current = todayCount
        defaults.set(max(0, current - 1), forKey: countKey)
    }

    /// Resets both keys to 0. Test-only; not called in production.
    public func resetForTesting() {
        defaults.set(0, forKey: countKey)
        defaults.set(0, forKey: markerKey)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let markerKey: String
    private let countKey: String
}
```

**Rationale**: mirrors `CompletionCounterStore` exactly — struct with `let` properties, `AppGroup.defaults` default, separate keys for marker and count, non-mutating methods (since `UserDefaults.set(_:forKey:)` mutates the reference type, not the struct). The `increment()` method does lazy day-rollover: compare `dayMarker` against `Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate`.

#### 2. New: `DailyCompletionStoreTests.swift`
**File**: `SingleThreadTests/DailyCompletionStoreTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

@Suite(.serialized) struct DailyCompletionStoreTests {
    // Capture the suite so tests can write markers directly without
    // accessing private store properties.
    private let suite = UserDefaults(suiteName: "DailyCompletionStoreTests-\(UUID())")!

    // lazy var so it can reference `suite` (which must init first).
    // Store is `var` only for lazy initialization; all methods are
    // non-mutating (they call `UserDefaults.set` on the reference type).
    private lazy var store = DailyCompletionStore(
        defaults: suite,
        markerKey: "t_marker",
        countKey: "t_count")

    deinit {
        suite.removePersistentDomain(forName: "DailyCompletionStoreTests")
    }

    @Test func defaultsAreZero() {
        #expect(store.todayCount == 0)
        #expect(store.dayMarker == 0)
    }

    @Test func incrementSetsCountToOne() {
        store.increment()
        #expect(store.todayCount == 1)
        #expect(store.dayMarker == Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
    }

    @Test func incrementSameDay() {
        store.increment()
        store.increment()
        #expect(store.todayCount == 2)
    }

    @Test func dayRolloverResetsCount() {
        // Inject yesterday's marker via the shared suite so the next
        // increment triggers a day rollover.
        let yesterday = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ).timeIntervalSinceReferenceDate
        suite.set(yesterday, forKey: "t_marker")
        store.increment()
        #expect(store.todayCount == 1)
        #expect(store.dayMarker == Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
    }

    @Test func decrementClamps() {
        store.decrement()
        #expect(store.todayCount == 0)
    }

    @Test func decrementAfterIncrement() {
        store.increment()
        store.increment()
        store.decrement()
        #expect(store.todayCount == 1)
    }

    @Test func survivesRecreation() {
        store.increment()
        let recreated = DailyCompletionStore(
            defaults: suite,
            markerKey: "t_marker",
            countKey: "t_count")
        #expect(recreated.todayCount == 1)
    }

    @Test func perKeyIsolation() {
        store.increment()
        let isolated = DailyCompletionStore(
            defaults: suite,
            markerKey: "b_marker",
            countKey: "b_count")
        #expect(isolated.todayCount == 0)
        #expect(store.todayCount == 1)
    }

    @Test func resetForTesting() {
        store.increment()
        store.resetForTesting()
        #expect(store.todayCount == 0)
        #expect(store.dayMarker == 0)
    }
}
```

**Note on `store` mutability**: `DailyCompletionStore.increment()` and `decrement()` are non-mutating (they call `UserDefaults.set(_:forKey:)` which mutates the reference type, not the struct), so `let store` works fine. The `suite` is captured separately so the `dayRolloverResetsCount` and `survivesRecreation`/`perKeyIsolation` tests can write markers or create new stores on the same `UserDefaults` without accessing private store properties.

### Verification
#### Automated
- [x] `make build && xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:SingleThreadTests/DailyCompletionStoreTests` passes

#### Manual
- [ ] None — pure unit-test verification

---

## Phase 2: `ReminderStore` integration — business logic

### Changes

#### 1. Modify: `ReminderStore.swift` — init + properties
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add `dailyCompletion` parameter to init and a public read-only property.

**In `init` signature** (after `completionCounter: CompletionCounterStore = CompletionCounterStore(),`):
```swift
        dailyCompletion: DailyCompletionStore = DailyCompletionStore(),
        completionCounter: CompletionCounterStore = CompletionCounterStore(),
```

**In init body** (after `self.completionCounter = completionCounter`):
```swift
        self.dailyCompletion = dailyCompletion
```

**In the public properties section** (after `completionCounter`):
```swift
    /// Tracks today's completion count; incremented once per successful
    /// EventKit save in `completeReminder` (iOS branch only). Resets at
    /// midnight (device-local day boundary).
    public private(set) var dailyCompletion: DailyCompletionStore
```

**In `completeReminder` iOS branch** (after `completionCounter.increment()` at the line immediately following `completionCounter.increment()`):
```swift
                completionCounter.increment()
                dailyCompletion.increment()
```

**In `undoLastCompletion`** (after `completionCounter.decrement()`):
```swift
                completionCounter.decrement()
                dailyCompletion.decrement()
```

#### 2. Modify: `ReminderStoreTests.swift` — new integration tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add tests in the undo/completion section (near the existing `undoDecrementsCompletionCounter` and complete/undo tests, ~line 907-923). Test pattern: use `InMemoryEventStore` + `noopSettle` + `makeReminder`, assert `store.dailyCompletion.todayCount` directly.

```swift
    // MARK: Daily completion

    @Test func completeReminderIncrementsDailyCount() async {
        let store = storeWithDefaults(
            eventStore: InMemoryEventStore(reminders: [makeReminder("Buy milk")], calendars: []),
            settle: noopSettle)
        await store.start()
        await store.completeCurrentReminder()
        #expect(store.dailyCompletion.todayCount == 1)
    }

    @Test func completeReminderSameDayIncrements() async {
        let store = storeWithDefaults(
            eventStore: InMemoryEventStore(reminders: [makeReminder("A"), makeReminder("B")], calendars: []),
            settle: noopSettle)
        await store.start()
        await store.completeCurrentReminder()
        await store.completeCurrentReminder()
        #expect(store.dailyCompletion.todayCount == 2)
    }

    @Test func undoDecrementsDailyCount() async {
        let store = storeWithDefaults(
            eventStore: InMemoryEventStore(reminders: [makeReminder("Buy milk")], calendars: []),
            settle: noopSettle)
        await store.start()
        await store.completeCurrentReminder()
        await store.undoLastCompletion()
        #expect(store.dailyCompletion.todayCount == 0)
    }

    @Test func undoClampsDailyCountAtZero() async {
        let store = storeWithDefaults(
            eventStore: InMemoryEventStore(reminders: [makeReminder("Buy milk")], calendars: []),
            settle: noopSettle)
        await store.start()
        await store.undoLastCompletion() // nothing to undo
        #expect(store.dailyCompletion.todayCount == 0)
    }

    @Test func dailyCountSurvivesReload() async {
        let store = storeWithDefaults(
            eventStore: InMemoryEventStore(reminders: [makeReminder("Buy milk")], calendars: []),
            settle: noopSettle)
        await store.start()
        await store.completeCurrentReminder()
        await store.reload()
        #expect(store.dailyCompletion.todayCount == 1)
    }
```

**Note**: `storeWithDefaults` is an existing helper in `ReminderStoreTests` (check its signature — it accepts `eventStore`, `settle`, and other params). If it doesn't accept all needed params, use the direct `ReminderStore(...)` init. The `noopSettle` is `{ }` — the empty closure. `makeReminder` is the file-scope `TestFixtures.makeReminder`.

### Verification
#### Automated
- [x] `make build && xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:SingleThreadTests/ReminderStoreTests` passes (all existing + new daily completion tests)

#### Manual
- [ ] None — pure unit-test verification

---

## Phase 3: `CompletionMomentumOverlay` — presentation model

### Changes

#### 1. New: `CompletionMomentumOverlay.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/CompletionMomentumOverlay.swift`
**Action**: create

```swift
import Foundation

/// A transient overlay shown after a reminder is completed, displaying
/// "You've cleared N today". Owned by `ContentViewModel` and triggered
/// alongside `CompletionGlow` when a completion succeeds.
///
/// The overlay auto-dismisses: `trigger(count:)` sets `isActive = true` and
/// records the count, then after `duration` seconds a non-blocking task sets
/// `isActive` back to `false`. Re-triggering while active resets the timer.
///
/// Default duration is 2.0 s — longer than `CompletionGlow`'s 0.5 s so the
/// text is readable before it fades.
@MainActor
@Observable
public final class CompletionMomentumOverlay {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// `true` while the overlay should be visible in the view.
    public private(set) var isActive = false

    /// The count displayed while active (snapshotted at trigger time).
    public private(set) var todayCount = 0

    /// Seconds the overlay stays visible before auto-dismissing.
    /// Injectable for tests; default 2.0 s.
    public var duration: TimeInterval = 2.0

    /// Shows the overlay with the given count, resetting the auto-dismiss
    /// timer if already active. Calling this multiple times in quick
    /// succession keeps the overlay visible for the most recent `duration`
    /// from the last trigger.
    public func trigger(count: Int) {
        todayCount = count
        isActive = true
        dismissTask?.cancel()
        let seconds = duration
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.isActive = false
            } catch {
                // Cancelled by a newer trigger — that trigger owns the timer,
                // so leave `isActive` untouched.
            }
        }
    }

    // MARK: Private

    private var dismissTask: Task<Void, Never>?
}
```

#### 2. New: `CompletionMomentumOverlayTests.swift`
**File**: `SingleThreadTests/CompletionMomentumOverlayTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

@MainActor
struct CompletionMomentumOverlayTests {
    @Test func triggerSetsActiveAndCount() {
        let overlay = CompletionMomentumOverlay()
        overlay.trigger(count: 5)
        #expect(overlay.isActive)
        #expect(overlay.todayCount == 5)
    }

    @Test func autoDismissAfterDuration() async {
        let overlay = CompletionMomentumOverlay()
        overlay.duration = 0.05
        overlay.trigger(count: 3)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
        #expect(!overlay.isActive)
    }

    @Test func retriggerResetsTimer() async {
        let overlay = CompletionMomentumOverlay()
        overlay.duration = 0.05
        overlay.trigger(count: 1)
        try? await Task.sleep(nanoseconds: 30_000_000) // 0.03 s
        overlay.trigger(count: 2)
        try? await Task.sleep(nanoseconds: 60_000_000) // 0.06 s — after first timer would fire
        #expect(overlay.isActive)
        #expect(overlay.todayCount == 2)
    }

    @Test func defaultDuration() {
        let overlay = CompletionMomentumOverlay()
        #expect(overlay.duration == 2.0)
    }
}
```

### Verification
#### Automated
- [x] `make build && xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:SingleThreadTests/CompletionMomentumOverlayTests` passes

#### Manual
- [ ] None — pure unit-test verification

---

## Phase 4: Preference gating + `ContentViewModel` trigger + `ContentView` render

### Changes

#### 4a: Preference key
**File**: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift`
**Action**: modify

Add a new case inside the enum, after `showCompletionGlow`:

```swift
    /// "showCompletionMomentum" — fallback: true
    case showCompletionMomentum
```

#### 4b: SettingsBindings computed property
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add a computed property mirroring `showCompletionGlow`:

At the top of the App-Group preferences section (after `showCompletionGlow`), add:

```swift
    var showCompletionMomentum: Bool {
        get {
            access(keyPath: \.showCompletionMomentum)
            return showCompletionMomentumPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showCompletionMomentum) {
                showCompletionMomentumPreference.set(newValue)
            }
        }
    }
```

At the bottom, in the Private section (after `showCompletionGlowPreference`), add:

```swift
    private let showCompletionMomentumPreference = BoolPreferenceStore(
        key: BoolPreferenceKey.showCompletionMomentum.rawValue,
        fallback: true)
```

#### 4c: ReminderSettingsView toggle
**File**: `SingleThread/ReminderSettingsView.swift`
**Action**: modify

Add a `@Binding var showCompletionMomentum: Bool` parameter and a Toggle.

**Add to the struct's property list** (after `@Binding var showCompletionGlow: Bool`):
```swift
    @Binding var showCompletionMomentum: Bool
```

**Add Toggle after the showCompletionGlow toggle** (after the closing `}` of the glow Toggle's trailing closure):
```swift
            Toggle(isOn: $showCompletionMomentum) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Completion Momentum")
                        SettingsCaption(text: "Show \"You've cleared N today\" after completing a reminder.")
                    }
                } icon: {
                    Image(systemName: "flame")
                }
            }
            .accessibilityIdentifier("showCompletionMomentumToggle")
```

**Update the preview** (add `showCompletionMomentum: .constant(true)`):
```swift
#Preview("Default") {
    NavigationStack {
        ReminderSettingsView(
            showDate: .constant(true),
            showList: .constant(false),
            showRecurrence: .constant(true),
            showAlarms: .constant(true),
            showCompletionGlow: .constant(true),
            showCompletionMomentum: .constant(true),
            viewModel: SettingsViewModel())
    }
}
```

#### 4d: SettingsView wiring
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Add `showCompletionMomentum: $bindings.showCompletionMomentum` to the `ReminderSettingsView` init call (after `showCompletionGlow: $bindings.showCompletionGlow,`):

```swift
                        ReminderSettingsView(
                            showDate: $bindings.showDate,
                            showList: $bindings.showList,
                            showRecurrence: $bindings.showRecurrence,
                            showAlarms: $bindings.showAlarms,
                            showCompletionGlow: $bindings.showCompletionGlow,
                            showCompletionMomentum: $bindings.showCompletionMomentum,
                            viewModel: viewModel)
```

#### 4e: ContentViewModel trigger
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

**Add a new init parameter** (after `showCompletionGlow`):
```swift
        showCompletionMomentum: BoolPreferenceStore = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionMomentum.rawValue,
            fallback: true),
```

**Add the `completionMomentum` property** (after `completionGlow`):
```swift
    /// Drives the transient "You've cleared N today" overlay after a
    /// successful completion.
    let completionMomentum = CompletionMomentumOverlay()
```

**Add the private preference store** (after `showCompletionGlow`):
```swift
    private let showCompletionMomentum: BoolPreferenceStore
```

**Update `completeCurrentReminder`** to trigger the momentum overlay:

```swift
    func completeCurrentReminder() async {
        if await store.completeCurrentReminder() {
            if showCompletionGlow.isEnabled { completionGlow.trigger() }
            if showCompletionMomentum.isEnabled {
                completionMomentum.trigger(count: store.dailyCompletion.todayCount)
            }
        }
    }
```

#### 4f: ContentView render
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add a second overlay near the existing glow overlay. The glow overlay is at `.overlay { if viewModel.completionGlow.isActive { completionGlowOverlay } }` (near line 553-562). Add a new overlay below it:

```swift
        .overlay {
            if viewModel.completionMomentum.isActive {
                completionMomentumOverlay
            }
        }
```

And add the `completionMomentumOverlay` computed property near `completionGlowOverlay`:

```swift
    /// Subtle foreground text overlay shown after a successful completion,
    /// displaying "You've cleared N today". Passes touches through; hidden
    /// from the accessibility tree like the glow (rapid re-triggers would be
    /// noisy for VoiceOver).
    private var completionMomentumOverlay: some View {
        Text("You've cleared \(viewModel.completionMomentum.todayCount) today")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
```

**Position the overlay on the card, not full-screen**: The glow is a full-screen background tint — the momentum overlay is card-centric. Wrap it in the card's coordinate space. The most natural placement: inside the card's own `.overlay(alignment: .bottom)`, just above the card's bottom edge. However, the card is rendered inside `listContent` switch branches. The simplest approach that mirrors the glow pattern: add it as a sibling `.overlay` on the top-level `body` view, positioned at the card's approximate location. **Better approach**: add it as a `.overlay(alignment: .bottom)` on the card's containing view inside each `listContent` branch. But since the card is rendered in multiple places (`.reminder`, `.allDone`, `.empty`), this is fragile.

**Simplest correct approach**: add the overlay at the same level as the glow overlay (`.overlay` on the root). The glow is full-screen; the momentum overlay is positioned near the bottom of the card using `.overlay(alignment: .bottom)` with a fixed offset from the bottom safe area. Since there's a single card plus a bottom bar, placing it above the bottom bar is reliable.

**Updated approach — add to the existing `.overlay` chain** (after the glow overlay):

```swift
        .overlay(alignment: .bottom) {
            if viewModel.completionMomentum.isActive {
                completionMomentumOverlay
                    .padding(.bottom, 80) // clear the bottom bar
            }
        }
```

And update the `.animation` modifier to also track `completionMomentum.isActive`:

```swift
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
```

Change to:

```swift
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionMomentum.isActive)
```

### Verification
#### Automated
- [ ] `make build` succeeds (iOS) — confirms all wiring compiles

#### Manual
- [ ] Launch in simulator, complete a reminder → overlay appears showing "You've cleared 1 today", auto-dismisses after ~2 s
- [ ] Complete again → overlay shows "You've cleared 2 today"
- [ ] Toggle off "Completion Momentum" in Settings → Reminder → complete → no overlay
- [ ] Toggle back on → overlay reappears
- [ ] Coexists with glow: both fire on completion, glow is background tint, overlay is foreground text — no visual collision

---

## Phase 5: Seed/reset seams — testing infrastructure

### Changes

#### 5a: UITestingSeed payload + CodingKeys
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

**Add to `SeedPayload` struct** (after `var entitlementUnresolved: Bool = false`):
```swift
    var completionDayMarker: TimeInterval?
    var completionTodayCount: Int?
```

**Add to `init(from decoder:)`** (after `entitlementUnresolved`):
```swift
        completionDayMarker = try container.decodeIfPresent(TimeInterval.self, forKey: .completionDayMarker)
        completionTodayCount = try container.decodeIfPresent(Int.self, forKey: .completionTodayCount)
```

**Add to `CodingKeys` enum** (after `entitlementUnresolved`):
```swift
        case completionDayMarker, completionTodayCount
```

**Add to `materialize() -> UITestingSeed`** — actually, `materialize()` returns `UITestingSeed` which doesn't currently have these fields. Add them to the `UITestingSeed` struct and its init:

Add to `UITestingSeed` properties (after `entitlementUnresolved`):
```swift
    public let completionDayMarker: TimeInterval?
    public let completionTodayCount: Int?
```

Add to `UITestingSeed` init (after `entitlementUnresolved`):
```swift
        completionDayMarker: TimeInterval? = nil,
        completionTodayCount: Int? = nil,
```

Add to `materialize()` return (after `entitlementUnresolved`):
```swift
            completionDayMarker: completionDayMarker,
            completionTodayCount: completionTodayCount,
```

**Add to `persistedKeys` array** (after `"completionCount"`):
```swift
        "completionDayMarker",
        "completionTodayCount",
```

#### 5b: AppViewModel seededStore wiring
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In `seededStore`, after the `completionCount` write (`AppGroup.defaults.set(seed.completionCount, forKey: "completionCount")`), add the daily completion seed writes (mirroring the completionCount verbatim pattern):

```swift
        // Seed the daily completion counter and day marker (verbatim, unclamped)
        // so UI tests can stage specific day-rollover and count scenarios.
        if let completionDayMarker = seed.completionDayMarker {
            AppGroup.defaults.set(completionDayMarker, forKey: DailyCompletionStore.defaultsMarkerKey)
        }
        if let completionTodayCount = seed.completionTodayCount {
            AppGroup.defaults.set(completionTodayCount, forKey: DailyCompletionStore.defaultsCountKey)
        }
```

Also, in the `seededStore`'s `ReminderStore` init, add `dailyCompletion` — since the store reads from `AppGroup.defaults` on construction, the seed writes above must happen BEFORE the `ReminderStore` init. They already do (seed writes are at the top of `seededStore`). Add the `dailyCompletion` parameter to the `ReminderStore` init:

```swift
        let store = if useNoopSettle {
            ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: !emptyWithHidden,
                hasHidden: seed.hasHidden,
                dailyCompletion: DailyCompletionStore(defaults: AppGroup.defaults),
                completionCounter: CompletionCounterStore(
                    defaults: AppGroup.defaults,
                    key: "completionCount"),
                entitlementStore: entitlementStore) {}
        } else {
            ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: !emptyWithHidden,
                hasHidden: seed.hasHidden,
                dailyCompletion: DailyCompletionStore(defaults: AppGroup.defaults),
                completionCounter: CompletionCounterStore(
                    defaults: AppGroup.defaults,
                    key: "completionCount"),
                entitlementStore: entitlementStore)
        }
```

#### 5c: UITestingSeedTests
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

Add three new tests:

```swift
    @Test func seedParsesDailyCompletion() throws {
        let json = """
        {"reminders":[{"title":"A"}],"completionTodayCount":5,"completionDayMarker":750000000.0}
        """
        let seed = try #require(UITestingSeed.fromLaunchArguments(["--seed", json]))
        #expect(seed.completionTodayCount == 5)
        #expect(seed.completionDayMarker == 750000000.0)
    }

    @Test func resetClearsDailyCompletion() {
        AppGroup.defaults.set(5, forKey: DailyCompletionStore.defaultsCountKey)
        AppGroup.defaults.set(750000000.0, forKey: DailyCompletionStore.defaultsMarkerKey)
        UITestingSeed.resetPersistedState()
        #expect(AppGroup.defaults.integer(forKey: DailyCompletionStore.defaultsCountKey) == 0)
        #expect(AppGroup.defaults.double(forKey: DailyCompletionStore.defaultsMarkerKey) == 0.0)
    }

    @Test func seedDailyCountUnclamped() throws {
        let json = """
        {"reminders":[{"title":"A"}],"completionTodayCount":250}
        """
        let seed = try #require(UITestingSeed.fromLaunchArguments(["--seed", json]))
        #expect(seed.completionTodayCount == 250)
    }
```

### Verification
#### Automated
- [ ] `make build && xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:SingleThreadTests/UITestingSeedTests` passes

#### Manual
- [ ] None — pure unit-test verification

---

## Testing Checkpoints

| Stage | Checkpoint — must be green before advancing |
|-------|---------------------------------------------|
| 1 | `DailyCompletionStoreTests` — all 9 tests pass |
| 2 | `ReminderStoreTests` — new daily-completion tests + existing suite pass |
| 3 | `CompletionMomentumOverlayTests` — all 4 tests pass |
| 4 | `make build` succeeds + sim-check overlay visible/correct |
| 5 | `UITestingSeedTests` — new seed tests + existing suite pass |

### Full-gate verification

After Stage 5 commits, launch the full `./scripts/test.sh` gate via the
`run-gate` skill (one async gate subagent in a worktree). This covers
`make format`, `make lint`, `make build`, `make periphery`, and the full unit
+ UI test suite. No new watch keys or UI tests are added, so the watch and UI
test suites are expected to pass unchanged.

---

## Not in scope (explicit)

- No watch sync keys, `PayloadKey` additions, `pushAll`/`apply` hooks, or
  `Show*State` holders
- No `completionCount` (lifetime) changes
- No haptics, sounds, or toasts
- No streak logic, day-history, or "longest streak" records
- No persistent badge on the card
- No UTC/timezone-independent day tracking
- No UI tests (overlay is transient; unit tests cover the model + integration;
  sim-check covers the visual)