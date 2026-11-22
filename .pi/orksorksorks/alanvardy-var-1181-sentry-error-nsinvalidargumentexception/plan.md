# Implementation Plan

## Overview

Fix the unhandled `NSInvalidArgumentException` raised from `EKEventStore.save`
during reminder completion (SINGLETHREAD-3 / VAR-1181) by refusing to hand
EventKit a reminder it cannot key. The empty-`calendarItemIdentifier` case was
already guarded (VAR-1104); the remaining pre-save precondition a fetched
reminder can violate is a **nil `calendar`** — EventKit's internal save builds a
dictionary keyed by the reminder's calendar and raises on a nil key, an
Objective-C exception Swift's `catch` cannot intercept.

Ground truth established during recon:
- An unsaved `EKReminder(eventStore:)` gets a **non-empty** temp
  `calendarItemIdentifier` and a **nil** `calendar` (verified with a scratch
  Swift/EventKit run), so a nil-calendar reminder *does* reach `save` through
  `visibleReminders → completeReminder` — exactly the reported frame.
- The existing `completeReminderSkipsSaveWhenIdentifierIsEmpty` test passes for
  the wrong reason (the empty id never matches the reminder's temp UUID); it
  does not exercise the identifier guard. Not in scope to fix, but noted.
- A store-ownership (cross-EKEventStore) guard is **not** viable here: calendar
  instances are not identity-stable even within one store (verified), the app
  builds a single `EKEventStore` and only ever populates `reminders` from that
  store's `fetchReminders`, and a re-fetch check would break the store-seeded
  test harness. Property validation is the right mechanism.

The guard is a small private helper applied before every iOS `save` site, using
the existing `EventKitStoring` surface — no interface, schema, or dependency
change.

## Phase 1: Guard completion — the reported crash, end to end

### Changes

#### 1. Private pre-save validation helper + `completeReminder` guard
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add an iOS-only private helper in the class body (near the other private
helpers, e.g. beside `resetSkipCount(for:)`):

```swift
#if !os(watchOS)
    /// EventKit's `save` raises an uncatchable `NSInvalidArgumentException`
    /// (not a Swift `Error`) when a reminder has no key to save under — an
    /// empty `calendarItemIdentifier` or a nil `calendar`. Validate the
    /// reminder's own state before every save so a malformed object returns
    /// `false` instead of crashing the app.
    private func isSavable(_ reminder: EKReminder) -> Bool {
        !reminder.calendarItemIdentifier.isEmpty && reminder.calendar != nil
    }
#endif
```

In `completeReminder(identifier:)`'s iOS branch, replace the existing
empty-identifier guard (lines ~323-325) with the helper:

```swift
            // EventKit's `save` raises an uncatchable `NSInvalidArgumentException`
            // (`key cannot be nil`) when the reminder has no key to save under:
            // an empty identifier or a nil calendar. Refuse the save instead.
            guard isSavable(reminder) else { return false }
```

The guard sits before the `do` block, so `completionCounter.increment()`,
`dailyCompletion.increment()`, `undoStore.retain`, `resetSkipCount`, `settle()`
and `reload()` are all skipped when it trips.

#### 2. Test fixture for a persisted-like reminder
**File**: `SingleThreadTests/TestFixtures.swift`
**Action**: modify

```swift
/// A reminder that mirrors one already persisted in EventKit: non-empty
/// identifier and a calendar, so it is valid to hand to `save`. Construction
/// only — never saved through EventKit.
@MainActor
func makeSavedReminder(title: String) -> EKReminder {
    makeReminder(title: title, calendarTitle: "Reminders")
}
```

#### 3. Reproduction + updated completion tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add the two reproduction tests (red before the guard — the first would call
`InMemoryEventStore.save` once and return `true`):

```swift
@Test
func completeReminderSkipsSaveWhenCalendarIsMissing() async {
    let eventStore = InMemoryEventStore()
    let reminder = makeReminder(title: "Calendarless") // non-empty id, nil calendar
    let store = ReminderStore(
        eventStore: eventStore,
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let completed = await store.completeReminder(identifier: reminder.calendarItemIdentifier)
    #expect(!completed, "a reminder with no calendar is not handed to EventKit save")
    #expect(eventStore.saveCallCount == 0, "save is never reached")
    #expect(!reminder.isCompleted, "the invalid reminder is left unmutated")
    #expect(!store.undoStore.hasUndoableReminder, "no undo side effect")
}

@Test
func completeCurrentReminderSkipsSaveWhenCalendarIsMissing() async {
    let eventStore = InMemoryEventStore()
    let reminder = makeReminder(title: "Calendarless")
    let store = ReminderStore(
        eventStore: eventStore,
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let completed = await store.completeCurrentReminder()
    #expect(!completed, "the reported entry point no-ops on an invalid reminder")
    #expect(eventStore.saveCallCount == 0, "save is never reached from completeCurrentReminder")
}
```

Update every completion happy-path test to seed a calendar-bearing reminder
(`makeSavedReminder(title:)`), otherwise the new guard blocks them:
- `completeCurrentReminderCompletesVisibleReminder` (~498)
- `completeCurrentReminderNoOpsWhenAllSkipped` (~484)
- `completeResetsSkipCount` (~785, in `ReminderStoreSkipCountTests`)
- `completeRetainsInUndoStore` (~903), `undoLastCompletionRevertsReminder`
  (~917), `undoLastCompletionClearsUndoStore` (~933),
  `secondCompleteOverwritesUndoStore` (~945), `undoDecrementsCompletionCounter`
  (~1001)
- `dailyCompletionStore(with:)` helper (~1088): attach
  `reminder.calendar = makeCalendar(title: "Reminders")` to each seeded reminder
- `completingSameReminderConcurrentlyDoesNotDoubleIncrement` (~1064): calendar
- `ReminderStoreGateTests.completeReminderIncrementsCounterOnSuccess`
- `CompletionGlowViewModelTests` (~55, 76, 88, 101) and
  `CompletionFlashViewModelTests` (~63): set
  `reminder.calendar = makeCalendar(title: "Reminders")` on the directly built
  `EKReminder(eventStore:)` instances (the gated / nothing-to-complete / skipped
  cases still pass but should carry a calendar so they keep testing their stated
  reason, not the guard).

Leave `completeReminderSkipsSaveWhenIdentifierIsEmpty` and
`completeReminderReturnsFalseWhenGated` as-is (they still return `false`).

#### 4. Update the write-path fake tests
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

- `completeReminderMarksSavedAndReloads` (~151): `makeSavedReminder(title: "Task")`.
- `completeReminderSaveErrorStaysSilentAndSkipsReload` (~170): same, so the
  test still reaches the save-error path.
- `undoLastCompletionSaveErrorClearsUndoStore` (~186): same.

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/UndoCompletionTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreGateTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreWriteTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/CompletionGlowViewModelTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/CompletionFlashViewModelTests` passes
- [x] `make format` then `make lint` pass (no `swiftformat`/`swiftlint --strict` findings)

#### Manual
- [ ] Confirm the two new tests fail on the pre-guard commit and pass after
      (red-first): the `saveCallCount == 0` assertion is the proof.
- [ ] No new Periphery finding: `isSavable` is used in the iOS build only and is
      hidden from watchOS by `#if !os(watchOS)`.

---

## Phase 2: Guard undo and reschedule save sites

### Changes

#### 1. `undoLastCompletion` guard
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

After `guard canMutate, let reminder = undoStore.lastCompletedReminder` and
before the `do` block:

```swift
            guard isSavable(reminder) else {
                // The retained reminder is unusable; drop it so the Undo button
                // disappears rather than repeatedly failing (mirrors the
                // save-error path below).
                undoStore.clear()
                return false
            }
```

#### 2. `rescheduleReminder` guard
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

After the `guard let reminder = reminders.first(where: { … })` and before the
`do` block:

```swift
            guard isSavable(reminder) else { return false }
```

#### 3. Tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`, `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Add sad-path tests:

```swift
@Test
func undoSkipsSaveWhenCalendarIsMissing() async {
    let eventStore = InMemoryEventStore()
    let reminder = makeReminder(title: "Calendarless")
    let store = ReminderStore(
        eventStore: eventStore,
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    store.undoStore.retain(reminder)
    let undone = await store.undoLastCompletion()
    #expect(!undone, "an unusable retained reminder cannot be undone")
    #expect(eventStore.saveCallCount == 0, "save is never reached")
    #expect(!store.undoStore.hasUndoableReminder, "the unusable reminder is dropped")
}

@Test
func rescheduleSkipsSaveWhenCalendarIsMissing() async {
    let eventStore = InMemoryEventStore()
    let reminder = makeReminder(title: "Calendarless")
    let store = ReminderStore(
        eventStore: eventStore,
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let rescheduled = await store.rescheduleReminder(
        identifier: reminder.calendarItemIdentifier,
        to: DateComponents(year: 2027, month: 1, day: 2))
    #expect(!rescheduled, "a reminder with no calendar cannot be rescheduled")
    #expect(eventStore.saveCallCount == 0, "save is never reached")
}
```

Update reschedule happy-path tests to calendar-bearing reminders:
`rescheduleResetsSkipCount` (~824), `reschedulePreservesRecurrenceOnRepeatingReminder`
(~846), and in `ReminderStoreWriteTests`:
`reschedulePersistsDueDateAndReloads` (~274), `rescheduleFailureReturnsFalse`
(~313, still must reach the throwing `save`), `reschedulePreservesRecurrenceRules`
(~331). Leave `rescheduleUnknownIdentifierIsNoop` as-is.

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreSkipCountTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/UndoCompletionTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreWriteTests` passes
- [x] `make format` then `make lint` pass

#### Manual
- [ ] Undo on a nil-calendar retained reminder returns `false`, does not
      decrement the counter, and clears the undo store exactly once.

---

## Phase 3: Guard the `addReminder` save site

`addReminder` builds a fresh reminder whose calendar comes from
`makeReminder` → `defaultCalendarForNewReminders()`, which the EventKit header
documents as **nullable** — a genuine nil-calendar source.

### Changes

#### 1. `addReminder` guard
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

After `let reminder = eventStore.makeReminder(...)` and before the `do` block in
the iOS branch:

```swift
            guard isSavable(reminder) else { return false }
```

#### 2. Tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`, `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Add a sad-path test using the fake's nil default calendar:

```swift
@Test
func addReminderReturnsFalseWhenCalendarIsMissing() async {
    let fake = FakeEventStore() // defaultCalendar defaults to nil
    let store = testStore(eventStore: fake)
    let added = await store.addReminder(title: "New", notes: nil, dueDate: nil)
    #expect(!added, "no default calendar → add reports failure instead of crashing")
    #expect(fake.saved.isEmpty, "save is never reached")
}
```

Update the add happy paths so a calendar exists:
- `ReminderStoreWriteTests.addReminderSavesAndReturnsTrue` (~206):
  `FakeEventStore(defaultCalendar: makeCalendar(title: "Reminders"))`.
- `ReminderStoreWriteTests.addReminderSaveErrorReturnsFalse` (~229): same, so it
  still reaches (and fails at) `save`.
- `ReminderStoreTests.addReminderSucceedsAndKeepsExistingReminders` (~319):
  `InMemoryEventStore(defaultCalendar: makeCalendar(title: "Reminders"))`.

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreWriteTests` passes
- [x] `make format` then `make lint` pass

#### Manual
- [ ] With no default calendar configured on the fake, `addReminder` returns
      `false` and records zero saves.

---

## Notes / boundaries

- Only the pre-save guards and their tests are in scope. `deleteReminder`
  (`eventStore.remove`) is untouched — the report is about `save`.
- In production the app uses a single `EKEventStore` and only repopulates
  `reminders` from its own `fetchReminders`, so a cross-store instance is
  structurally implausible; the nil-calendar property guard is the fix that
  matches the reachable invalid state. If the Sentry crash survives this change,
  a follow-up ticket should add an ownership lookup seam
  (`calendarItem(withIdentifier:)`) — deliberately not included here because it
  changes the `EventKitStoring` interface and would require re-seeding every
  store-backed test.
- Consequence of the guard: the plain `--ui-testing` seeded "Buy groceries"
  reminder has no calendar and will no longer complete. No UI test taps complete
  under plain `--ui-testing` (the complete UI tests use `--seed` with
  `"calendars":["Groceries"]`), so no UI test changes; a live-QA completion of
  that fixture would no-op rather than crash.
