# Implementation Plan

## Overview

Two unit tests prove that rescheduling a repeating reminder preserves its `recurrenceRules` — one at the `FakeEventStore` protocol seam, one at the `InMemoryEventStore` store-layer seam. No production code changes. The tests act as regression protection; the codebase's object-identity mutation pattern already preserves recurrence on every mutation path.

---

## Phase 1: Data-Access Layer — `FakeEventStore` Seam

### Changes

#### 1. Add `reschedulePreservesRecurrenceRules` test
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify — add one `@Test` in the `ReminderStoreWriteTests` suite

Insert after `rescheduleFailureReturnsFalse` (ends ~line 326):

```swift
@Test
func reschedulePreservesRecurrenceRules() async {
    let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
    let reminder = makeReminder(
        title: "Weekly standup",
        notes: nil,
        dueDate: DateComponents(year: 2025, month: 6, day: 1),
        recurrenceRule: rule)
    let fake = FakeEventStore(fetchResult: [reminder])
    let store = testStore(eventStore: fake)
    await store.reload()
    let due = DateComponents(year: 2027, month: 1, day: 2)

    let rescheduled = await store.rescheduleReminder(
        identifier: reminder.calendarItemIdentifier,
        to: due)

    #expect(rescheduled)
    #expect(fake.saved.last === reminder)
    #expect(fake.saved.last?.recurrenceRules?.count == 1)
    #expect(fake.saved.last?.dueDateComponents?.year == 2027)
}
```

**What it proves**: after `rescheduleReminder`, the same `EKReminder` object is saved, its recurrence rules survive unchanged, and the due date was actually updated (not a no-op).

### Verification

#### Automated
- [x] `make build SIM=platform=iOS Simulator,name=iPhone 17,OS=26` passes
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26' -only-testing:SingleThreadTests/ReminderStoreWriteTests -derivedDataPath DerivedData` — all 24 tests pass (23 existing + 1 new)

#### Manual
- [ ] Confirm the new test name appears green in Xcode Test Navigator under `ReminderStoreWriteTests`

---

## Phase 2: Store Layer — `InMemoryEventStore` Seam

### Changes

#### 1. Add `reschedulePreservesRecurrenceOnRepeatingReminder` test
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify — add one `@Test`

Insert after `rescheduleResetsSkipCount` (after the `#endif` block ending ~line 695):

```swift
@Test
func reschedulePreservesRecurrenceOnRepeatingReminder() async {
    let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
    let rem = makeReminder(
        title: "Weekly standup",
        notes: nil,
        dueDate: DateComponents(year: 2025, month: 6, day: 1),
        recurrenceRule: rule)
    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [rem]),
        loadsReminders: true,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        settle: noopSettle)
    let due = DateComponents(year: 2027, month: 1, day: 2)

    let rescheduled = await store.rescheduleReminder(
        identifier: rem.calendarItemIdentifier,
        to: due)

    #expect(rescheduled)
    // InMemoryEventStore.save appends without dedup; find by identifier, not by count.
    let found = store.reminders.first { $0.calendarItemIdentifier == rem.calendarItemIdentifier }
    #expect(found != nil)
    #expect(found?.recurrenceRules?.count == 1)
    #expect(found?.dueDateComponents?.year == 2027)
}
```

**What it proves**: after a full `rescheduleReminder` round-trip through `InMemoryEventStore` (including settle + reload), the reminder is findable by identifier, recurrence rules survive, and the due date updated.

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26' -only-testing:SingleThreadTests/ReminderStoreTests/reschedulePreservesRecurrenceOnRepeatingReminder -derivedDataPath DerivedData` passes
- [ ] Full suite: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26' -only-testing:SingleThreadTests/ReminderStoreTests -derivedDataPath DerivedData` — new + all existing tests pass

#### Manual
- [ ] Confirm the test name appears green in Xcode Test Navigator under `ReminderStoreTests`

---

## Phase 3: Final Gate

### Verification

#### Automated
- [ ] `./scripts/test.sh` — full CI-identical pipeline passes (format, lint, build, Periphery, unit + UI tests)

#### Manual
- [ ] On-device smoke: reschedule a repeating reminder in-app, open Apple Reminders, confirm it still shows the repeat badge with the new due date

---

## What's NOT in Scope (from design.md "What We're NOT Doing")

- No production code changes
- No UI tests
- No `UITestingSeed` or `--ui-testing` seam changes
- No watch time-dropping fix
- No recurrence gate on the reschedule button
- No series-vs-one-off logic