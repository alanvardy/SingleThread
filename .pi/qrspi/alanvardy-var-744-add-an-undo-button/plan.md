# Implementation Plan — Undo Button (VAR-744)

## Overview

Add a single-level undo for the most-recent completion: a new `UndoStore` holds the `EKReminder` reference at complete-time, `ReminderStore.undoLastCompletion()` reverts it, and a `.topLeading` control-plate button in `ContentView` surfaces it — gated on both the retained reference and a new `showUndoButton` settings toggle. All layers tested independently before integration.

---

## Phase 1: UndoStore type

### Changes

#### 1.1 Create UndoStore
**File**: `SingleThreadCore/Sources/SingleThreadCore/UndoStore.swift`
**Action**: create

```swift
import EventKit
import Foundation

/// Transient in-memory holder for the most-recently completed reminder,
/// enabling a single-level undo. Lives per `ReminderStore` instance;
/// not persisted. Follows the `CompletionGlow` pattern: `@MainActor`,
/// `@Observable`, `final class`.
@MainActor
@Observable
public final class UndoStore {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// The most-recently completed reminder, if one has been retained and
    /// not yet cleared (by undo or by a subsequent completion overwrite).
    public private(set) var lastCompletedReminder: EKReminder?
    public var hasUndoableReminder: Bool { lastCompletedReminder != nil }

    /// Stashes the given reminder reference; overwrites any prior.
    public func retain(_ reminder: EKReminder) {
        lastCompletedReminder = reminder
    }

    /// Nils out the retained reference.
    public func clear() {
        lastCompletedReminder = nil
    }
}
```

#### 1.2 Create UndoStoreTests
**File**: `SingleThreadTests/UndoStoreTests.swift`
**Action**: create

```swift
import EventKit
import SingleThreadCore
import Testing

@MainActor
struct UndoStoreTests {
    // Uses a single shared EKEventStore (construction only, never saved).
    private let eventStore = EKEventStore()

    private func makeReminder() -> EKReminder {
        let rem = EKReminder(eventStore: eventStore)
        rem.title = "Test"
        return rem
    }

    @Test
    func hasUndoableReminderFalseInitially() {
        let store = UndoStore()
        #expect(!store.hasUndoableReminder)
        #expect(store.lastCompletedReminder == nil)
    }

    @Test
    func retainStoresReminder() {
        let store = UndoStore()
        let reminder = makeReminder()
        store.retain(reminder)
        #expect(store.lastCompletedReminder === reminder)
        #expect(store.hasUndoableReminder)
    }

    @Test
    func clearNilsReminder() {
        let store = UndoStore()
        store.retain(makeReminder())
        store.clear()
        #expect(store.lastCompletedReminder == nil)
        #expect(!store.hasUndoableReminder)
    }

    @Test
    func retainOverwritesPrevious() {
        let store = UndoStore()
        let first = makeReminder()
        let second = makeReminder()
        store.retain(first)
        store.retain(second)
        #expect(store.lastCompletedReminder === second)
        #expect(store.lastCompletedReminder !== first)
    }
}
```

### Verification
#### Automated
- [x] `swiftformat SingleThreadTests/UndoStoreTests.swift SingleThreadCore/Sources/SingleThreadCore/UndoStore.swift && swiftlint lint --strict` passes
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/UndoStoreTests` passes

#### Manual
- [ ] None needed (pure unit test)

---

## Phase 2: ReminderStore undo logic

### Changes

#### 2.1 Add decrement() to CompletionCounterStore
**File**: `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift`
**Action**: modify

**Change 1**: Replace the doc comment above `// MARK: Public` to remove "never decremented":

```swift
/// Tracks the lifetime completion count in App Group UserDefaults.
///
/// The counter starts at 0 and increments by exactly 1 per successful EventKit
/// save inside `ReminderStore.completeReminder`. It is only decremented by
/// undo; it is never reset in production. Tests inject UUID-keyed stores for
/// isolation.
```

**Change 2**: Add `decrement()` method after `increment()`:

```swift
    /// Decrements the counter by 1, clamping at zero so the count never
    /// goes negative. Only called by undo; not called in normal production.
    public func decrement() {
        let current = count
        defaults.set(max(0, current - 1), forKey: key)
    }
```

#### 2.2 Add UndoStore property to ReminderStore
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**Change 1**: In the `// MARK: - Public properties` section (around line 48, after the other public properties), add:

```swift
    /// Transient undo store — holds the most-recently completed reminder
    /// so the user can revert it. iOS-only; not persisted.
    public let undoStore = UndoStore()
```

#### 2.3 Add retain-on-complete
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**Change**: In `completeReminder(identifier:)`, in the `#else` (iOS) branch, add `undoStore.retain(reminder)` right before the settle sleep. Locate the line `try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)` (~line 180) and insert before it:

```swift
                reminder.isCompleted = true
                try eventStore.save(reminder, commit: true)
                completionCounter.increment()
                undoStore.retain(reminder)   // <-- NEW
                try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
```

#### 2.4 Add undoLastCompletion() method
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**Change**: Add the new method after `completeCurrentReminder()` (~line 194):

```swift
    /// Reverts the most-recent completion: sets `isCompleted = false` on
    /// the retained reminder, saves to EventKit, decrements the counter,
    /// clears the undo store, and reloads. Returns `false` when there is
    /// nothing to undo or mutation is gated.
    @discardableResult
    public func undoLastCompletion() async -> Bool {
        guard canMutate, let reminder = undoStore.lastCompletedReminder else {
            return false
        }
        do {
            reminder.isCompleted = false
            try eventStore.save(reminder, commit: true)
            completionCounter.decrement()
            undoStore.clear()
            try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
            await reload()
            return true
        } catch {
            Self.logger.error("Failed to undo completion: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
```

#### 2.5 Add CompletionCounterStore decrement tests
**File**: `SingleThreadTests/CompletionCounterStoreTests.swift`
**Action**: modify

**Add after `resetForTestingZeroesCounter` test**:

```swift
    @Test
    func decrementReducesCount() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        store.increment()
        store.increment()
        store.increment()
        #expect(store.count == 3)
        store.decrement()
        #expect(store.count == 2)
    }

    @Test
    func decrementDoesNotGoBelowZero() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        #expect(store.count == 0) // swiftlint:disable:this empty_count
        store.decrement()
        #expect(store.count == 0) // swiftlint:disable:this empty_count
    }
```

#### 2.6 Add ReminderStore undo tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

**Add a new `@Suite` at the end of the file (before `// MARK: - makeReminder test seam`)**:

```swift
// MARK: - Undo completion

#if !os(watchOS)
    @MainActor
    @Suite(.serialized)
    struct UndoCompletionTests {
        @Test
        func completeRetainsInUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(store.undoStore.hasUndoableReminder)
            #expect(store.undoStore.lastCompletedReminder === rem)
        }

        @Test
        func undoLastCompletionRevertsReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(rem.isCompleted)
            let undone = await store.undoLastCompletion()
            #expect(undone)
            #expect(!rem.isCompleted)
        }

        @Test
        func undoLastCompletionClearsUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            _ = await store.undoLastCompletion()
            #expect(!store.undoStore.hasUndoableReminder)
        }

        @Test
        func secondCompleteOverwritesUndoStore() async {
            let remA = makeReminder(title: "A")
            let remB = makeReminder(title: "B")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [remA, remB],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: remA.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remA)
            _ = await store.completeReminder(identifier: remB.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remB)
            // Undo B — A is gone permanently
            _ = await store.undoLastCompletion()
            #expect(!remB.isCompleted)
            #expect(remA.isCompleted) // A stays completed
        }

        @Test
        func undoReturnsFalseWhenNoRetainedReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoReturnsFalseWhenGated() async {
            let key = UUID().uuidString
            UserDefaults.standard.set(100, forKey: key)
            let counter = CompletionCounterStore(defaults: .standard, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter,
                entitlementStore: EntitlementStore(testingWithEntitled: false))
            // Manually stash a reminder (simulating a prior completion before
            // the gate closed; the complete itself would have been gated).
            store.undoStore.retain(rem)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoDecrementsCompletionCounter() async {
            let key = UUID().uuidString
            let defaults = UserDefaults.standard
            let counter = CompletionCounterStore(defaults: defaults, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(counter.count == 1)
            _ = await store.undoLastCompletion()
            #expect(counter.count == 0) // swiftlint:disable:this empty_count
        }
    }
#endif
```

### Verification
#### Automated
- [x] `swiftformat SingleThreadCore/ SingleThreadTests/ && swiftlint lint --strict` passes
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/ReminderStoreTests -only-testing:SingleThreadTests/ReminderStoreGateTests -only-testing:SingleThreadTests/CompletionCounterStoreTests` passes

#### Manual
- [ ] None needed

---

## Phase 3: Settings toggle plumbing

### Changes

#### 3.1 Add `showUndoButton` to `SettingsBindings`
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

**Change 1**: Add `showUndoButton` property (after `showSwipePrompt`):

```swift
    var showSwipePrompt: Bool
    #if os(iOS)
        var showUndoButton: Bool
    #endif
```

**Change 2**: Add `showUndoButton` init parameter (after `showSwipePrompt: Bool = true,`):

```swift
        showSwipePrompt: Bool = true,
        #if os(iOS)
            showUndoButton: Bool = true,
        #endif
        showMicrophoneButton: Bool = true,
```

**Change 3**: Assign in init body (after `self.showSwipePrompt = showSwipePrompt`):

```swift
        self.showSwipePrompt = showSwipePrompt
        #if os(iOS)
            self.showUndoButton = showUndoButton
        #endif
```

Note: The `#if os(iOS)` can't go inside the parameter list, but the property access is gated on iOS. Since the struct is declared `@Observable` and properties are just stored, declare the property as `var showUndoButton: Bool` unconditionally (matching the `allowsLandscape` / `enableActionButtons` pattern in this file — those are declared unconditionally despite being iOS-only in `ContentView`). The init default of `true` is harmless on macOS.

**Correction to structure outline**: Declare `showUndoButton: Bool` unconditionally (like `allowsLandscape` and `enableActionButtons`) to avoid `#if` in property list. Gate only the Toggle row in `InterfaceSettingsView`.

#### 3.2 Add `showUndoButton` `@AppStorage` to `ContentView`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Change 1**: After `enableActionButtons` block (~line 175), add:

```swift
    #if os(iOS)
        @AppStorage("showUndoButton")
        private var showUndoButton = true
    #endif
```

#### 3.3 Wire `showUndoButton` in sheet `.onChange` block
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Change**: After `.onChange(of: bag.showSwipePrompt) ...` (~line 126), add:

```swift
                    .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
```

Inside the `#if os(iOS)` block that already gates the other iOS-only onChange lines. Check whether `showSwipePrompt`'s onChange is inside the `#if os(iOS)` block — if so, add the new line inside the same block. If it's after the `#endif`, place it right after.

#### 3.4 Add `showUndoButton` to `makeSettingsBag()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Change**: In `makeSettingsBag()`, add `showUndoButton: showUndoButton` after `showSwipePrompt: showSwipePrompt` in the `#if os(iOS)` branch.

#### 3.5 Add Toggle row to `InterfaceSettingsView`
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

**Change 1**: Add binding declaration (after `showSwipePrompt` binding):

```swift
    #if os(iOS)
        @Binding var showSwipePrompt: Bool
    #endif

    #if os(iOS)
        @Binding var showUndoButton: Bool
    #endif
```

**Change 2**: Add Toggle row inside `#if os(iOS)` block (after `showSwipePrompt` Toggle):

```swift
                Toggle(isOn: $showSwipePrompt) {
                    Label("Show swipe prompt", systemImage: "arrow.left.arrow.right")
                }
                Toggle(isOn: $showUndoButton) {
                    Label("Show undo button", systemImage: "arrow.uturn.backward")
                }
```

**Change 3**: Update preview to include `showUndoButton` in the `#if os(iOS)` branch:

```swift
                enableActionButtons: .constant(false),
                showSwipePrompt: .constant(true),
                showUndoButton: .constant(true),
```

#### 3.6 Add `showUndoButton` to `UITestingSeed.persistedKeys`
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

**Change**: Add `"showUndoButton"` to the `persistedKeys` array (~line 56). Add it after `"backgroundFadePercent"` (which is also `.standard`-backed). The array currently has 19 entries; this will be the 20th.

```swift
        "backgroundEnabled",
        "backgroundFadePercent",
        "showUndoButton",
        "allowsLandscape",
```

#### 3.7 Add `showUndoButton` binding test to `SettingsViewTests`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

**Add a test after `settingsBindingsCarriesShowSwipePrompt`**:

```swift
    @Test
    func settingsBindingsCarriesShowUndoButton() {
        let bag = SettingsBindings()
        #expect(bag.showUndoButton) // default enabled
        let off = SettingsBindings(showUndoButton: false)
        #expect(!off.showUndoButton) // explicit false round-trips
    }
```

**Also** update `interfaceSettingsViewContainsExpectedRows` to include "Show undo button" in the expected labels:

```swift
    #if os(iOS)
        expectedLabels += ["Allow landscape", "Show action buttons", "Show swipe prompt", "Show undo button"]
    #endif
```

### Verification
#### Automated
- [x] `swiftformat SingleThread/ SingleThreadTests/ SingleThreadCore/ && swiftlint lint --strict` passes
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` passes
- [x] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds (catches `#if` mismatch)

#### Manual
- [ ] Open Settings → Interface, verify "Show undo button" toggle appears and defaults ON

---

## Phase 4: UI button in ContentView

### Changes

#### 4.1 Add undo forwarding method to `ContentViewModel`
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

**Change**: Add new method in the `// MARK: - Store mutation forwarding` section, after `deleteCurrentReminder()`:

```swift
    /// Forwards to ``ReminderStore/undoLastCompletion()``.
    /// No glow trigger — the reappearing reminder is its own feedback.
    func undoLastCompletion() async {
        await store.undoLastCompletion()
    }
```

#### 4.2 Add undo button overlay to `ContentView`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Change**: Add `.overlay(alignment: .topLeading)` after the gear overlay block (after the `.padding(.trailing, 12)` closing `}` of the gear overlay, before `.overlay { if viewModel.completionGlow.isActive`):

```swift
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            if viewModel.store.undoStore.hasUndoableReminder, showUndoButton, viewModel.store.canMutate {
                Button {
                    Task { await viewModel.undoLastCompletion() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .controlPlate()
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo completion")
                .accessibilityAddTraits(.isButton)
                .padding(.top, 8)
                .padding(.leading, 12)
            }
        }
        #endif
```

### Verification
#### Automated
- [ ] `swiftformat SingleThread/ && swiftlint lint --strict` passes
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds

#### Manual
- [ ] Launch app, complete a reminder (via swipe or action button), confirm undo button appears top-left
- [ ] Tap undo button, confirm reminder reappears and undo button disappears
- [ ] Open Settings → Interface, flip "Show undo button" off, dismiss, confirm button stays hidden after completing a reminder
- [ ] Flip toggle back on, complete reminder, confirm button reappears

---

## Phase 5: UI tests

### Changes

#### 5.1 Add undo flow UI tests
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

**Add a new `// MARK: - Undo` section before `// MARK: - Freemium gate` (before `testUpgradePromptAppearsWhenGated`)**:

```swift
    // MARK: - Undo

    @MainActor
    func testUndoButtonAppearsAfterCompleteAndUndoRemovesReminder() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the reminder via action button.
        let completeButton = app.buttons["Complete reminder"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()

        // Undo button should appear after completion.
        let undoButton = app.buttons["Undo completion"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3), "Undo button should appear after completing a reminder")

        // Tap undo.
        undoButton.tap()

        // Reminder should reappear.
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 3), "Reminder should reappear after undo")

        // Undo button should disappear.
        XCTAssertFalse(undoButton.exists, "Undo button should disappear after undoing")
    }

    @MainActor
    func testUndoButtonHiddenWhenToggleOff() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the reminder to make undo button appear.
        let completeButton = app.buttons["Complete reminder"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()

        let undoButton = app.buttons["Undo completion"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))

        // Open settings, navigate to Interface, flip showUndoButton off.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3))
        app.staticTexts["Interface"].tap()

        let showUndoToggle = app.switches["Show undo button"]
        XCTAssertTrue(showUndoToggle.waitForExistence(timeout: 3))
        let flipped = flipToggle(showUndoToggle, target: "0")
        XCTAssertTrue(flipped, "Show undo button toggle should be off")

        // Dismiss settings.
        app.buttons["Done"].tap()

        // Undo button should be gone.
        XCTAssertFalse(undoButton.exists, "Undo button should be hidden when toggle is off")
    }

    @MainActor
    func testUndoButtonDoesNotAppearWithoutCompletion() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Undo button should not exist on fresh launch.
        XCTAssertFalse(app.buttons["Undo completion"].exists, "Undo button should not appear without a completion")
    }
```

### Verification
#### Automated
- [ ] `swiftformat SingleThreadUITests/ && swiftlint lint --strict` passes
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes (includes existing accessibility audit + three new undo tests)

#### Manual
- [ ] Run `./scripts/test.sh` — full gate must be green

---

## Testing Checkpoints (summary)

1. **Phase 1 complete**: `xcodebuild test ... -only-testing:SingleThreadTests/UndoStoreTests` green
2. **Phase 2 complete**: `xcodebuild test ... -only-testing:SingleThreadTests/ReminderStoreTests -only-testing:SingleThreadTests/ReminderStoreGateTests -only-testing:SingleThreadTests/CompletionCounterStoreTests` green
3. **Phase 3 complete**: `xcodebuild test ... -only-testing:SingleThreadTests/SettingsViewTests` green + Debug build succeeds
4. **Phase 4 complete**: Debug build succeeds + manual smoke test passes
5. **Phase 5 complete**: `xcodebuild test ... -only-testing:SingleThreadUITests` green
6. **Final gate**: `./scripts/test.sh` green

---

## Implementation Order Notes

- **Phase 1 (UndoStore)** and **Phase 3 (Settings toggle)** are independent — Phase 3 can run in parallel with Phase 1 if desired.
- **Phase 2** depends on Phase 1 (needs `UndoStore` type).
- **Phase 4** depends on Phases 2 and 3.
- **Phase 5** depends on Phase 4.

---

## Decisions Resolved

- **`persistedKeys` entry** (from structure open decisions): **Added** `"showUndoButton"` to `UITestingSeed.persistedKeys`. Rationale: `enableActionButtons` (identical pattern — `.standard`, iOS-only, no watch sync) is already in `persistedKeys`. Without this entry, `resetPersistedState()` wouldn't clear it between seed runs, creating cross-test leakage. No relaunch-persistence UI test is added in Phase 5 (the toggle-off test flips within one launch), so this is a correctness measure for existing seed-based tests, not a new test requirement.

- **Counter decrement**: **Included** in Phase 2. The design flags that non-decrementing undo at count=100 would leave the user gated after undoing. `decrement()` clamps at zero via `max(0, count - 1)`.

- **Undo gating on `canMutate`**: **Both layers gated** — the UI hides the button AND the store method checks `canMutate`. Defense in depth; the `canMutate` check in the overlay also saves the visual jarring of a tap that does nothing.