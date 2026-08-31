# Structure Outline

## Approach

Surgical fix to the single priority-mapping function (`ReminderPriority.level(for:)`) expanded from `{1,5,9}` to the full RFC 5545 range (`1…4 → high`, `5 → medium`, `6…9 → low`), plus a generation-counter to close the skip-to-clear race. Five horizontal layers, each tested green before moving up.

---

## Stage 1: Priority Mapping Fix

Expand `ReminderPriority.level(for:)` to bucket the full CalDAV priority range.
`marker(for:)`, `rank(for:)`, and `level(forMarker:)` all delegate to `level(for:)`, so
changing this one switch fixes display, sorting, and accessibility label mapping
across both platforms with no other code changes.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`

**Key changes**:
```swift
// ReminderPriority.level(for:) — before:
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
No signature changes. No new types. `marker(for:)`, `rank(for:)`, `level(forMarker:)`, and `Level.displayName` are unchanged.

**Tests** (in `SingleThreadTests/ReminderSkipTests.swift`):
- `levelIsNilForUnknownPriority` → rename to `levelMapsHighForMidHighPriority` and assert `level(for: 3) == .high` (replaces old assertion that 3 → nil)
- New: `levelMapsHighForBoundary` — `level(for: 2) == .high`, `level(for: 4) == .high`
- New: `levelMapsLowForMidLowPriority` — `level(for: 6) == .low`, `level(for: 7) == .low`
- New: `levelMapsLowForBoundary` — `level(for: 8) == .low`
- Existing tests for `1→high`, `5→medium`, `9→low`, `0→nil`, markers, and ranks all continue to pass unchanged

**Verify**: `./scripts/test.sh` — unit tests only; no UI changes yet

---

## Stage 2: Display Model Integration & Temporary Instrumentation

Wire the expanded mapping into `ReminderDisplay` tests to prove end-to-end
correctness through the display snapshot layer. Add a temporary `os_log` in
`ReminderDisplay.init(reminder:)` to confirm the CalDAV-range hypothesis
on-device before the fix merges.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
- `SingleThreadTests/ReminderDisplayTests.swift`

**Key changes**:
```swift
// ReminderDisplay.swift — add:
import os

// Inside init(reminder:), after priorityMarker assignment:
if ![0, 1, 5, 9].contains(reminder.priority) {
    os_log(.debug, "ReminderDisplay: non-standard priority %d for reminder %{public}@",
           reminder.priority, reminder.calendarItemIdentifier)
}
```

**Tests** (in `SingleThreadTests/ReminderDisplayTests.swift`):
- `mapsHighMarkerForPriority2` — priority 2 → `"!!!"`
- `mapsHighMarkerForPriority4` — priority 4 → `"!!!"`
- `mapsLowMarkerForPriority6` — priority 6 → `"!"`
- `mapsLowMarkerForPriority8` — priority 8 → `"!"`
- Existing `mapsHighPriorityMarker` (1), `mapsEmptyMarkerForNoPriority` (0), and all other tests pass unchanged

**Verify**:
1. `./scripts/test.sh` — unit tests green
2. Build to device, exercise the app, confirm `os_log` fires in Console.app (manual check)

---

## Stage 3: Skip Race Fix

Add a `skipGeneration` counter to `ReminderStore`. `skipCurrentReminder()`
captures the generation before the 200 ms sleep; `applySkipSet` becomes a no-op
if the generation has changed. `reload(clearSkipped: true)` increments the
generation, invalidating any pending skip.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
- `SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
```swift
// ReminderStore — new property:
private var skipGeneration: Int = 0

// skipCurrentReminder() — capture generation before sleep:
let capturedGeneration = skipGeneration
Task {
    try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
    applySkipSet(updated, generation: capturedGeneration)
}

// applySkipSet — becomes generation-gated:
private func applySkipSet(_ updated: [String], generation: Int) {
    guard generation == skipGeneration else { return }
    // … existing body unchanged
}

// reload(clearSkipped: true) — increment before clearing:
if clearSkipped {
    skipGeneration &+= 1
    // … existing clear body unchanged
}
```
`skipCurrentReminderImmediately()` (widget path, no sleep) is unchanged and
does not take a generation — the race doesn't apply there.

**Tests** (in `SingleThreadTests/ReminderStoreTests.swift`):
- `skipCurrentReminderDiscardedAfterClearSkipped` — call `skipCurrentReminder()`, immediately call `reload(clearSkipped: true)`, await the skip's `Task`, assert `skippedIDs` is empty (the reminder is NOT re-hidden)
- Existing skip tests (`skipCurrentReminderUpdatesSkippedIDs`, `skipCurrentReminderFiresRemindersChangedHook`, gating tests in `ReminderStoreGateTests`) all pass unchanged

**Verify**: `./scripts/test.sh` — unit tests green

---

## Stage 4: UI Test Assertions for Priority Rendering

Add UI-level assertions that priority markers render on screen. iOS uses the
existing `--seed` seam; watchOS extends the `--ui-testing` seam with an
optional priority parameter.

**Files**:
- `SingleThreadUITests/SingleThreadUITestsFlows.swift`
- `SingleThreadWatch/WatchAppViewModel.swift`
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`

**Key changes**:

*Watch seam* — `WatchAppViewModel.uiTestingStore(arguments:)`:
```swift
// After existing --ui-testing-* flag parsing, add:
if let index = arguments.firstIndex(of: "--ui-testing-priority"),
   index + 1 < arguments.count,
   let priority = Int(arguments[index + 1]) {
    reminder.priority = priority
}
```
Existing default (`priority = 5`) unchanged when flag absent.

*iOS UI test* — extend `testSkipAdvancesToNextReminder` or add a new test:
```swift
// Seed a priority-3 reminder and assert the marker renders:
let seed = #"{"reminders":[{"title":"Urgent item","priority":3}]}"#
let app = launchApp(seedJSON: seed)
XCTAssertTrue(app.staticTexts["!!!"].waitForExistence(timeout: 5))
```

*Watch UI test* — new test:
```swift
func testPriorityMarkerRenders() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-priority", "7"]
    app.launch()
    XCTAssertTrue(app.staticTexts["!"].waitForExistence(timeout: 5))
}
```

**Tests**:
- iOS: `testPriorityMarkerRendersForMidRangeValue` — seeds priority 3, asserts `"!!!"` exists
- watchOS: `testPriorityMarkerRendersForMidRangeValue` — seeds priority 7, asserts `"!"` exists
- Existing UI tests continue to pass (priority 1 and 9 in `testSkipAdvancesToNextReminder` still render correctly)

**Verify**:
```bash
make ui-test SIM='platform=iOS Simulator,name=iPhone 17'
make ui-test SIM='platform=iOS Simulator,name=iPad (A16)'
# Watch UI tests (if CI matrix supports them locally; otherwise CI gate)
```

---

## Stage 5: Instrumentation Cleanup

Remove the temporary `os_log` and `import os` added in Stage 2. The
hypothesis is confirmed, the fix is proven, the log is no longer needed.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`

**Key changes**:
- Remove `import os`
- Remove the `if ![0, 1, 5, 9].contains(…) { os_log(…) }` block

**Tests**: No new tests needed. All existing tests continue to pass.

**Verify**: `./scripts/test.sh` — full gate green

---

## Testing Checkpoints

| Stage | Gate |
|-------|------|
| 1 — Priority Mapping | `make test` (unit tests only) |
| 2 — Display + Instrumentation | `make test` + on-device `os_log` confirmation |
| 3 — Skip Race Fix | `make test` (unit tests only) |
| 4 — UI Test Assertions | `make ui-test` (iOS + watchOS) |
| 5 — Instrumentation Cleanup | `./scripts/test.sh` (full gate) |