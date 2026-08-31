# Implementation Plan

## Overview

Expand `ReminderPriority.level(for:)` to bucket the full RFC 5545 CalDAV priority range (1–4→high, 5→medium, 6–9→low), add a generation counter to close the skip-to-clear race, and add UI-level assertions for priority marker rendering on both platforms. Instrument on-device to confirm the hypothesis, then revert the instrumentation.

---

## Phase 1: Priority Mapping Fix

### Changes

#### 1. Expand `ReminderPriority.level(for:)` switch
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`
**Action**: modify

In `ReminderPriority.level(for:)` (line 50–58), change the switch cases:

```swift
// Before:
switch priority {
case 1: .high
case 5: .medium
case 9: .low
default: nil
}

// After:
switch priority {
case 1...4: .high
case 5:     .medium
case 6...9: .low
default:    nil
}
```

No other changes to this file. `marker(for:)`, `rank(for:)`, `level(forMarker:)`, and `Level.displayName` all delegate to `level(for:)` and require no edits.

#### 2. Update existing test: `levelIsNilForUnknownPriority`
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify

Rename the test function and change its assertion. The old assertion said priority 3 → `nil`; the new assertion says priority 3 → `.high`:

```swift
// Before (line ~120):
@Test
func levelIsNilForUnknownPriority() {
    #expect(ReminderPriority.level(for: 3) == nil)
}

// After:
@Test
func levelMapsHighForMidHighPriority() {
    #expect(ReminderPriority.level(for: 3) == .high)
}
```

#### 3. Add new boundary tests
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify

Add these test functions inside `struct ReminderPriorityTests`, after `levelMapsHighPriority`:

```swift
@Test
func levelMapsHighForBoundary() {
    #expect(ReminderPriority.level(for: 2) == .high)
    #expect(ReminderPriority.level(for: 4) == .high)
}

@Test
func levelMapsLowForMidLowPriority() {
    #expect(ReminderPriority.level(for: 6) == .low)
    #expect(ReminderPriority.level(for: 7) == .low)
}

@Test
func levelMapsLowForBoundary() {
    #expect(ReminderPriority.level(for: 8) == .low)
}
```

### Verification
#### Automated
- [x] `swift test --filter "ReminderPriorityTests"` passes (if using SPM directly) or `./scripts/test.sh` — unit tests only
- [x] `make lint` passes — no SwiftLint violations

#### Manual
- [ ] Run `make test SIM='platform=iOS Simulator,name=iPhone 17'` — confirm `testLevelMapsHighForMidHighPriority`, `testLevelMapsHighForBoundary`, `testLevelMapsLowForMidLowPriority`, `testLevelMapsLowForBoundary` all pass, and all existing priority tests still pass

---

## Phase 2: Display Model Integration & Temporary Instrumentation

### Changes

#### 1. Add temporary `os_log` instrumentation
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify

Add `import os` at the top (after the existing `import EventKit` and `import Foundation`):

```swift
import EventKit
import Foundation
import os
```

Inside `init(reminder:)`, after the `priorityMarker = ReminderPriority.marker(for: reminder.priority)` line, add:

```swift
if ![0, 1, 5, 9].contains(reminder.priority) {
    os_log(.debug, "ReminderDisplay: non-standard priority %d for reminder %{public}@",
           reminder.priority, reminder.calendarItemIdentifier)
}
```

#### 2. Add display-level tests for new priority ranges
**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify

Add these test functions inside `struct ReminderDisplayTests`, after the existing `mapsHighPriorityMarker` and `mapsEmptyMarkerForNoPriority` tests:

```swift
@Test
func mapsHighMarkerForPriority2() {
    let reminder = makeReminder(title: "P2")
    reminder.priority = 2
    #expect(ReminderDisplay(reminder: reminder).priorityMarker == "!!!")
}

@Test
func mapsHighMarkerForPriority4() {
    let reminder = makeReminder(title: "P4")
    reminder.priority = 4
    #expect(ReminderDisplay(reminder: reminder).priorityMarker == "!!!")
}

@Test
func mapsLowMarkerForPriority6() {
    let reminder = makeReminder(title: "P6")
    reminder.priority = 6
    #expect(ReminderDisplay(reminder: reminder).priorityMarker == "!")
}

@Test
func mapsLowMarkerForPriority8() {
    let reminder = makeReminder(title: "P8")
    reminder.priority = 8
    #expect(ReminderDisplay(reminder: reminder).priorityMarker == "!")
}
```

### Verification
#### Automated
- [ ] `./scripts/test.sh` — unit tests pass (Phase 1 + Phase 2 tests all green)
- [ ] `make lint` passes

#### Manual
- [ ] Build to physical device: `xcodebuild -scheme SingleThread -destination 'platform=iOS,name=<device>' -configuration Debug build`
- [ ] Exercise the app on-device for a few minutes (open, complete, skip, pull-to-refresh)
- [ ] Open Console.app, filter for `ReminderDisplay`, confirm `os_log` fires — if non-standard priorities appear, the CalDAV hypothesis is confirmed
- [ ] If no log entries appear after sustained use, the root cause may be elsewhere — stop here and escalate to the user

---

## Phase 3: Skip Race Fix

### Changes

#### 1. Add `skipGeneration` counter and generation-gate `applySkipSet`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a new property below the existing private properties (after `private let excludeStore: ExcludedListStore`):

```swift
private var skipGeneration: Int = 0
```

Modify `skipCurrentReminder()` to capture the generation before the sleep:

```swift
// Before:
public func skipCurrentReminder() {
    guard canMutate else { return }
    guard let reminder = visibleReminders.first else { return }
    let updated = updatedSkipSet(afterSkipping: reminder.calendarItemIdentifier)
    Task {
        try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
        applySkipSet(updated)
    }
}

// After:
public func skipCurrentReminder() {
    guard canMutate else { return }
    guard let reminder = visibleReminders.first else { return }
    let updated = updatedSkipSet(afterSkipping: reminder.calendarItemIdentifier)
    let capturedGeneration = skipGeneration
    Task {
        try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
        applySkipSet(updated, generation: capturedGeneration)
    }
}
```

Modify `applySkipSet` to accept an optional generation gate:

```swift
// Before:
private func applySkipSet(_ updated: [String]) {
    skippedIDs = Set(updated)
    skipStore.save(updated)
    onSkipSetChanged?(updated)
    onRemindersChanged?()
}

// After:
private func applySkipSet(_ updated: [String], generation: Int? = nil) {
    if let generation, generation != skipGeneration { return }
    skippedIDs = Set(updated)
    skipStore.save(updated)
    onSkipSetChanged?(updated)
    onRemindersChanged?()
}
```

Modify `reload(clearSkipped:)` to increment the generation before clearing:

```swift
// Inside reload(clearSkipped:), change the clearSkipped block:
// Before:
if clearSkipped {
    skippedIDs = []
    skipStore.save([])
    onSkipSetChanged?([])
}

// After:
if clearSkipped {
    skipGeneration &+= 1
    skippedIDs = []
    skipStore.save([])
    onSkipSetChanged?([])
}
```

**`skipCurrentReminderImmediately()` is unchanged** — it calls `applySkipSet(updated)` with no generation argument, so the generation gate is a no-op. The widget path has no sleep, so the race doesn't apply there.

#### 2. Add skip-race unit test
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add this test function inside `struct ReminderStoreTests`, after the existing `skipCurrentReminderFiresRemindersChangedHook` test:

```swift
@Test
func skipCurrentReminderDiscardedAfterClearSkipped() async {
    let rem = makeReminder(title: "A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [rem]),
        loadsReminders: true,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess)

    store.skipCurrentReminder()
    await store.reload(clearSkipped: true)
    // Wait for the skip Task to complete its 200 ms sleep + apply.
    try? await Task.sleep(nanoseconds: 400_000_000)

    #expect(store.skippedIDs.isEmpty)
}
```

### Verification
#### Automated
- [ ] `./scripts/test.sh` — unit tests pass, including the new race-condition test
- [ ] `make lint` passes
- [ ] Existing gate tests in `ReminderStoreGateTests` continue to pass (skip with gating, skip without gating)

#### Manual
- [ ] iOS: Open app, skip a reminder, immediately pull-to-refresh with `clearSkipped`. The un-skipped reminder stays visible — it is NOT re-hidden by the stale skip Task. Repeat 3–5 times to confirm the race window is reliably closed.

---

## Phase 4: UI Test Assertions for Priority Rendering

### Changes

#### 1. Extend watchOS `--ui-testing` seam with priority parameter
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

In `uiTestingStore(arguments:)`, after the existing `--ui-testing-excluded-list` / `--ui-testing-live-excluded` flag parsing block and before the `let inMemoryStore = ...` line at the end, add parsing for `--ui-testing-priority`:

```swift
if let index = arguments.firstIndex(of: "--ui-testing-priority"),
   index + 1 < arguments.count,
   let priority = Int(arguments[index + 1]) {
    reminder.priority = priority
}
```

This goes right before the `let inMemoryStore = InMemoryEventStore(reminders: [reminder])` line (after the closing `}` of the excluded-list for loop). When the flag is absent, `reminder.priority` remains the existing default of `5`.

#### 2. Add iOS UI test for priority marker rendering
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add this test function inside `final class SingleThreadUITestsFlows`, after the existing `testSkipAdvancesToNextReminder` test:

```swift
@MainActor
func testPriorityMarkerRendersForMidRangeValue() {
    let seed = #"{"reminders":[{"title":"Urgent item","priority":3}]}"#
    let app = launchApp(seedJSON: seed)

    XCTAssertTrue(
        app.staticTexts["!!!"].waitForExistence(timeout: 5),
        "Priority-3 reminder should render the !!! marker")
}
```

#### 3. Add watchOS UI test for priority marker rendering
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify

Add this test function inside `final class SingleThreadWatchUITestsFlows`, after the existing `testCardShowsReminderTitleAndNotes` test:

```swift
@MainActor
func testPriorityMarkerRendersForMidRangeValue() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-priority", "7"]
    app.launch()

    XCTAssertTrue(
        app.staticTexts["!"].waitForExistence(timeout: 5),
        "Priority-7 reminder should render the ! marker")
}
```

### Verification
#### Automated
- [ ] `make ui-test SIM='platform=iOS Simulator,name=iPhone 17'` — all iOS UI tests pass, including `testPriorityMarkerRendersForMidRangeValue`
- [ ] `make ui-test SIM='platform=iOS Simulator,name=iPad (A16)'` — same
- [ ] Watch UI tests in CI (or locally if watch simulator is available)

#### Manual
- [ ] Run iOS UI tests and confirm the `"!!!"` marker appears on screen during `testPriorityMarkerRendersForMidRangeValue`
- [ ] Run watch UI tests and confirm the `"!"` marker appears

---

## Phase 5: Instrumentation Cleanup

### Changes

#### 1. Remove `os_log` and `import os`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify

Remove the three additions from Phase 2:

- Delete `import os` (the `import` line added in Phase 2)
- Delete the `if ![0, 1, 5, 9].contains(reminder.priority) { os_log(...) }` block

The file returns to its pre-Phase-2 shape. No other changes.

### Verification
#### Automated
- [ ] `./scripts/test.sh` — full gate green: format, lint, build, Periphery, unit tests, UI tests
- [ ] `make lint` passes — no unused import warning
- [ ] `make periphery` passes — no dead code detected (`os_log` removed, no stale symbols)

#### Manual
- [ ] Confirm `grep -r "os_log" SingleThreadCore/` returns no results (instrumentation fully removed)
- [ ] Confirm `grep -r "import os" SingleThreadCore/Sources/SingleThreadCore/` returns no results

---

## Testing Checkpoints

| Phase | Gate |
|-------|------|
| 1 — Priority Mapping | `make test` (unit tests only) |
| 2 — Display + Instrumentation | `make test` + on-device `os_log` confirmation |
| 3 — Skip Race Fix | `make test` (unit tests only) |
| 4 — UI Test Assertions | `make ui-test` (iOS + watchOS) |
| 5 — Instrumentation Cleanup | `./scripts/test.sh` (full gate) |