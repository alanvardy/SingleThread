# Implementation Plan

## Overview

Add a presentation-only delay on the watchOS completion path so the reminder card stays visible behind the fading green glow, then transitions to the empty state after the glow finishes.

---

## Stage 1: ViewModel — Completion Transition State & Logic

### Changes

#### 1. Add transition properties to `WatchReminderViewModel`
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Add three new properties after the existing `isShowingRefreshConfirmation` (line 39):

```swift
/// When `true`, the completion glow is playing out and the card should
/// stay visible as a "ghost" even though the store is already empty.
var isShowingCompletionTransition = false

/// Snapshot of the reminder that was on screen when Complete was tapped.
/// Rendered during the transition so the card doesn't vanish mid-glow.
var transitionReminder: EKReminder?

/// Extra hold time beyond `completionGlow.duration` before the ghost card
/// is cleared. Test-configurable so unit tests can run near-instantly.
var completionTransitionBuffer: TimeInterval = 0.5
```

#### 2. Modify `completeCurrentReminder()`
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Replace the existing `completeCurrentReminder()` method (lines 47–52):

```swift
/// Completes the visible reminder and triggers the glow on success.
/// The view routes its Complete button through here so the success-only
/// glow gates on the store's actual completion result.
func completeCurrentReminder() async {
    if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled {
        completionGlow.trigger()
    }
}
```

With the new implementation:

```swift
/// Completes the visible reminder, captures a snapshot for the ghost card,
/// and triggers the glow. Holds the card visible for the full glow + buffer
/// before relinquishing to the empty-state branch.
func completeCurrentReminder() async {
    guard !isShowingCompletionTransition else { return }
    transitionReminder = store.visibleReminders.first
    if await store.completeCurrentReminder(),
       showCompletionGlowState.isEnabled {
        isShowingCompletionTransition = true
        completionGlow.trigger()
        let delay = completionGlow.duration + completionTransitionBuffer
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            if store.visibleReminders.isEmpty {
                isShowingCompletionTransition = false
                transitionReminder = nil
            }
        }
    } else {
        transitionReminder = nil
    }
}
```

#### 3. Add transition-state unit tests
**File**: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`
**Action**: modify

Add seven new `@Test` functions to the existing `@Suite(.serialized) struct ShowCompletionGlowStateTests`. These use the same fixture pattern already present in the file (`sharedWatchEventStore`, `watchReminder()`, `InMemoryEventStore`).

**Test 1 — `transitionFlagStartsFalse`**:

```swift
@Test
func transitionFlagStartsFalse() {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    #expect(!viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder == nil)
}
```

**Test 2 — `transitionFlagSetOnSuccessfulComplete`**:

```swift
@Test
func transitionFlagSetOnSuccessfulComplete() async {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    await viewModel.completeCurrentReminder()
    #expect(viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder != nil)
}
```

**Test 3 — `transitionFlagNotSetWhenGlowDisabled`**:

```swift
@Test
func transitionFlagNotSetWhenGlowDisabled() async {
    let glowState = ShowCompletionGlowState()
    defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
    glowState.apply(false)
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: glowState)
    await viewModel.completeCurrentReminder()
    #expect(!viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder == nil)
}
```

**Test 4 — `transitionFlagNotSetWhenNothingToComplete`**:

```swift
@Test
func transitionFlagNotSetWhenNothingToComplete() async {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    await viewModel.completeCurrentReminder()
    #expect(!viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder == nil)
}
```

**Test 5 — `doubleTapIsNoOp`**:

```swift
@Test
func doubleTapIsNoOp() async {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    await viewModel.completeCurrentReminder()
    #expect(viewModel.isShowingCompletionTransition)
    // Second call while transition is active exits immediately.
    let wasActive = viewModel.completionGlow.isActive
    await viewModel.completeCurrentReminder()
    #expect(wasActive == viewModel.completionGlow.isActive, "Glow should not re-trigger on double-tap")
}
```

**Test 6 — `transitionFlagClearsAfterDelay`**:

Uses fast durations so the test doesn't sleep for seconds:

```swift
@Test
func transitionFlagClearsAfterDelay() async {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    viewModel.completionGlow.duration = 0.05
    viewModel.completionTransitionBuffer = 0.01
    await viewModel.completeCurrentReminder()
    #expect(viewModel.isShowingCompletionTransition)
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s > 0.05 + 0.01
    #expect(!viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder == nil)
}
```

**Test 7 — `transitionFlagStaysSetIfStoreRepopulated`**:

```swift
@Test
func transitionFlagStaysSetIfStoreRepopulated() async {
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [watchReminder()],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState())
    viewModel.completionGlow.duration = 0.05
    viewModel.completionTransitionBuffer = 0.01
    await viewModel.completeCurrentReminder()
    #expect(viewModel.isShowingCompletionTransition)
    // Inject a new reminder before the delay elapses.
    let newReminder = watchReminder()
    newReminder.title = "New reminder"
    store.reminders.append(newReminder)
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s > 0.05 + 0.01
    // Flag stays set because visibleReminders is no longer empty.
    #expect(viewModel.isShowingCompletionTransition)
    #expect(viewModel.transitionReminder != nil)
}
```

**Note**: Test 7 accesses `store.reminders.append(...)` directly. `ReminderStore.reminders` is `public private(set) var` — verify it's settable from `@testable import SingleThreadWatch`. If the property access level prevents direct mutation from the test target, use an alternative approach: create a second `ReminderStore` with a reminder pre-populated and replace the view model's store reference, or add a test-only helper. The structure's intent is to test the store-check-before-clearing guard.

### Verification

#### Automated
- [x] `make watch-test` passes (all 7 new tests green, existing tests unchanged)
- [x] `make build` passes (iOS scheme builds without regressions)

#### Manual
- [ ] No view changes yet — the flag exists but nothing reads it. Build and run the watch app in the simulator via `make watch-build` to confirm it compiles.

---

## Stage 2: View — Ghost-Card Branch Gating

### Changes

#### 1. Add transition branch in `reminderContent`
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In `reminderContent` (beginning at line 76), insert a new first branch in the `ZStack` before the `allSkipped` check. The existing branches are at lines 78–83:

```swift
ZStack {
    if viewModel.store.allSkipped {
        allDoneState
    } else if let reminder = viewModel.store.visibleReminders.first {
        reminderCard(reminder)
    } else {
        noRemindersState
    }
```

Replace that block with:

```swift
ZStack {
    if viewModel.isShowingCompletionTransition,
       let reminder = viewModel.transitionReminder {
        reminderCard(reminder)
    } else if viewModel.store.allSkipped {
        allDoneState
    } else if let reminder = viewModel.store.visibleReminders.first {
        reminderCard(reminder)
    } else {
        noRemindersState
    }
```

No other changes to the view. The glow overlay (lines 91–95) and its `.animation` (lines 96–98) continue to render above whichever branch is active. The action buttons on the ghost card are naturally no-op: Complete hits the guard in Stage 1, Skip finds no visible reminder.

### Verification

#### Automated
- [ ] `make watch-ui-test` passes — all existing watch UI tests green (no regressions):
  - `testCardShowsReminderTitleAndNotes`
  - `testCompleteRemovesReminder`
  - `testCompletionGlowFlashesWhenEnabled`
  - `testCompletionGlowDoesNotAppearWhenDisabled`
  - `testSkipShowsAllDoneState`
  - `testDeleteViaConfirmationDialogRemovesReminder`
  - `testExcludedListDoesNotRenderReminder`
  - `testLiveExclusionHidesReminderWithoutRelaunch`
  - `testRefreshPresentOnNoRemindersState`

#### Manual
- [ ] `make watch-build` succeeds
- [ ] Run the watch app in simulator: complete a reminder and confirm:
  - The card does **not** vanish instantly
  - The green glow fades over the card
  - The empty state ("No Reminders") appears after ~1 second
- [ ] Spot-check skip and delete — both still work without visual regressions

---

## Stage 3: UI Tests — Post-Completion Timing Verification

### Changes

#### 1. Add timing-assertion UI test
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify

Add a new test function after the existing `testCompletionGlowFlashesWhenEnabled` (ends at line 177). Place it before the `// MARK: Private` section:

```swift
@MainActor
func testCompleteHoldsCardDuringGlow() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    let complete = app.buttons["Complete reminder"]
    XCTAssertTrue(complete.waitForExistence(timeout: 3))
    complete.tap()

    // Card must stay visible during the glow (2 s glow + 0.5 s buffer = 2.5 s).
    // Assert the card text is still present immediately after the tap —
    // it must NOT disappear in under 1 s.
    XCTAssertTrue(
        app.staticTexts["Buy groceries"].waitForExistence(timeout: 1),
        "Card should persist during the post-completion glow")

    // Glow overlay must be present (existing assertion, preserved).
    XCTAssertTrue(
        app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3))

    // After the full delay (2.0 + 0.5 = 2.5 s), the empty state must appear.
    // Generous timeout accounts for CI executor variance.
    XCTAssertTrue(
        app.staticTexts["No Reminders"].waitForExistence(timeout: 8),
        "After the glow fades, the No Reminders state should appear")
}
```

The existing `testCompleteRemovesReminder` (no `--ui-testing-glow`) is unchanged — that test asserts `No Reminders` appears after complete, which still works (production delay is 0.50 + 0.50 = 1.0 s, well within the existing 5 s timeout).

### Verification

#### Automated
- [ ] `make watch-ui-test` passes — new test green + all existing tests green
- [ ] `make build` + `make watch-build` both compile cleanly
- [ ] `./scripts/test.sh` — full CI gate passes (format, lint, build, periphery, unit tests, iOS UI tests, watch UI tests, macOS build + tests)

#### Manual
- [ ] Run the full gate locally: `./scripts/test.sh`
- [ ] No Periphery warnings for unused declarations (the new properties are read by the view and tests)

---

## Testing Checkpoints

1. **After Stage 1**: `make watch-test` → `SingleThreadWatchTests` green (7 new tests pass; all existing tests unchanged)
2. **After Stage 2**: `make watch-ui-test` → all existing watch UI tests green (no regressions) + manual glance at simulator
3. **After Stage 3**: `make watch-ui-test` → new timing test green + all existing tests green; `./scripts/test.sh` → full gate green