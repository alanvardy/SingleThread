# Structure Outline

## Approach

Test-only regression protection: prove that rescheduling a repeating reminder preserves its `recurrenceRules`. No production code changes — the object-identity mutation pattern already preserves recurrence on every code path. Two horizontal layers, each adding one test at a different seam, bottom-up from the data-access protocol to the store lifecycle.

---

## Stage 1: Data-Access Layer — `FakeEventStore` Seam

Proves that `ReminderStore.rescheduleReminder` preserves `recurrenceRules` through the `EventKitStoring` protocol boundary — the save happens, the same object is saved, and recurrence rules survive unchanged.

**Files**: `SingleThreadTests/EventKitStoringTests.swift` only

**Key changes**:
- One new `@Test` in `ReminderStoreWriteTests`:
  `func reschedulePreservesRecurrenceRules() async` — builds a repeating reminder via `makeReminder(title:notes:dueDate:recurrenceRule:)` → seeds `FakeEventStore(fetchResult:)` → reloads → reschedules → asserts recurrence survives

**Signatures consumed (existing, no changes)**:
- `FakeEventStore(fetchResult: [EKReminder])` — test seam (:95-135, mirrors production `makeReminder` including `addRecurrenceRule`)
- `FakeEventStore.saved: [EKReminder]` — records every `save(_:commit:)` call
- `makeReminder(title:notes:dueDate:recurrenceRule:) → EKReminder` — factory; mirrors `EventKitStoring.makeReminder`
- `testStore(eventStore:) → ReminderStore` — factory (:555-559)
- `store.rescheduleReminder(identifier:to:) → Bool` — method under test

**Assertions**:
1. `rescheduled == true` — save succeeded
2. `fake.saved.last === reminder` — same object, not a replacement
3. `fake.saved.last?.recurrenceRules?.count == 1` — rules survived the save
4. `fake.saved.last?.dueDateComponents?.year == …` — due date changed (guard against a no-op "pass")

**Sad path**: the existing `rescheduleUnknownIdentifierIsNoop` and `rescheduleFailureReturnsFalse` already cover the failure surface; no new sad-path test needed at this layer.

**Tests**: `reschedulePreservesRecurrenceRules` — one new test, happy path only (failure & unknown-id are covered by existing)
**Verify**: `make build SIM=platform=iOS Simulator,name=iPhone 17,OS=26` then `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26' -only-testing:SingleThreadTests/ReminderStoreWriteTests -derivedDataPath DerivedData`

---

## Stage 2: Store Layer — `InMemoryEventStore` Seam

Proves that `ReminderStore.rescheduleReminder` preserves recurrence through the full store lifecycle — settle, reload, and re-fetch — with the `InMemoryEventStore` seam that actually stores and returns reminders (unlike `FakeEventStore` which only records saves).

**Files**: `SingleThreadTests/ReminderStoreTests.swift` only

**Key changes**:
- One new `@Test` in an existing suite (e.g. `SkipCountStoreIntegrationTests` or a new `RescheduleRecurrenceTests`):
  `func reschedulePreservesRecurrenceOnRepeatingReminder() async` — seeds `InMemoryEventStore` with a repeating reminder → reschedules → finds by identifier → asserts recurrence survives the round-trip

**Signatures consumed (existing, no changes)**:
- `EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)` — recurrence rule constructor
- `InMemoryEventStore(reminders: [EKReminder])` — test seam with pre-seeded reminders
- `ReminderStore(eventStore:skipStore:loadsReminders:reminders:skippedIDs:authorizationStatus:settle:)` — store initializer
- `store.rescheduleReminder(identifier:to:) → Bool` — method under test
- `noopSettle: ReminderStoreSettle` — no-op settle (:12), used in existing `rescheduleResetsSkipCount`

**`InMemoryEventStore` quirk accounted for**: `save` appends without dedup (:87-89), so rescheduling a seeded reminder duplicates it in `allReminders`. The test must find the reminder by `calendarItemIdentifier` and assert on that specific instance — **never** assert on `store.reminders.count` post-reschedule.

**Assertions**:
1. `rescheduled == true` — reschedule succeeds
2. Find the reminder by identifier in `store.reminders`; `#expect` non-nil
3. `reminder.recurrenceRules?.count ==1` — rules survive the round-trip (after settle + reload)
4. `reminder.dueDateComponents?.year == 2027` — due date updated (guard against no-op)

**Sad path**: `InMemoryEventStore` has no save-throw path and reschedule-unknown-id is already covered by Stage 1; no new sad-path test.

**Tests**: `reschedulePreservesRecurrenceOnRepeatingReminder` — one new test, happy path
**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26' -only-testing:SingleThreadTests/ReminderStoreTests/reschedulePreservesRecurrenceOnRepeatingReminder -derivedDataPath DerivedData`

---

## Testing Checkpoints

| After Stage | Must be green |
|---|---|
| 1 — `FakeEventStore` seam | `-only-testing:SingleThreadTests/ReminderStoreWriteTests` — new + all 23 existing tests pass |
| 2 — `InMemoryEventStore` seam | `-only-testing:SingleThreadTests/ReminderStoreTests` — new + all existing tests pass (watch for the append-without-dedup quirk) |
| Final gate | `./scripts/test.sh` — full CI-identical pipeline (format, lint, build, Periphery, unit + UI) |

---

## What's NOT in Scope (from design.md "What We're NOT Doing")

- No production code changes — verify-only
- No UI tests — recurrence survival is a model concern
- No `UITestingSeed` or `--ui-testing` seam changes
- No watch time-dropping fix — separate ticket
- No recurrence gate on the reschedule button
- No series-vs-one-off logic