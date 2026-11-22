# Implementation Summary

Fix for the unhandled `NSInvalidArgumentException` raised from `EKEventStore.save`
during reminder completion (SINGLETHREAD-3 / VAR-1181). Every iOS `save` site now
validates the reminder's own state (`isSavable`: non-empty `calendarItemIdentifier`
and non-nil `calendar`) before handing it to EventKit.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| chore | `be3ea0d7` | remove DELETEME marker (required ticket hygiene; see notes) |
| 1 | `e0b8b088` | Phase 1: Guard completion — the reported crash, end to end |
| 2 | `989e5d14` | Phase 2: Guard undo and reschedule save sites |
| 3 | `f79bfe27` | Phase 3: Guard the addReminder save site |

All commits pushed to `origin/alanvardy-var-1181-sentry-error-nsinvalidargumentexception`.
`DELETEME`, `plan.md` and `.pi/orksorksorks/` were never staged in the phase commits.

## Automated Checks

- [x] Phase 1: `ReminderStoreTests` (41), `UndoCompletionTests` (13), `ReminderStoreGateTests` (9), `ReminderStoreWriteTests` (12), `CompletionGlowViewModelTests` (5), `CompletionFlashViewModelTests` (2)
- [x] Phase 2: `ReminderStoreTests` (41), `ReminderStoreSkipCountTests` (12), `UndoCompletionTests` (14), `ReminderStoreWriteTests` (12)
- [x] Phase 3: `ReminderStoreTests` (41), `ReminderStoreWriteTests` (13), `ReminderStoreAvailableListsTests` (2), `ReminderStoreSkipCountTests` (12), `UndoCompletionTests` (14), `ReminderStoreGateTests` (9), `CompletionGlowViewModelTests` (5), `CompletionFlashViewModelTests` (2)
- [x] `make format` clean (248 files)
- [x] `make lint --strict` clean — 0 violations in 248 files
- [x] `scripts/test-one.sh` exits non-zero on a zero-match (used throughout; no suite silently matched zero)

The full CI-identical gate (`./scripts/test.sh` — build, warning check, Periphery,
unit + UI, both simulator matrix entries) has **not** been run; it belongs to the
review step. Given the store-unification change in Phase 3, the full gate is
recommended.

## Manual Verification Items (from the plan)

- [ ] Phase 1 red-first: confirm the two new tests fail on the pre-guard commit and
      pass after — the `saveCallCount == 0` assertion is the proof.
- [ ] Phase 1: no new Periphery finding — `isSavable` is used in the iOS build only
      and is hidden from watchOS by `#if !os(watchOS)` (now file-scope `private func`).
- [ ] Phase 2: undo on a nil-calendar retained reminder returns `false`, does not
      decrement the counter, and clears the undo store exactly once.
- [ ] Phase 3: with no default calendar configured on the fake, `addReminder`
      returns `false` and records zero saves.

## Divergences from the plan (all within the fix's intent)

1. **DELETEME removal committed first.** The branch bootstrap's `DELETEME` marker
   was left deleted-but-unstaged and blocked the pre-implementation rebase. It is
   required to be removed before merge (`AGENTS.md`), so it was committed as its own
   chore commit (`be3ea0d7`). Not a phase change.

2. **Phase 1 glow/flash fixtures.** The plan prescribed assigning
   `reminder.calendar = makeCalendar(title: "Reminders")` onto local
   `EKReminder(eventStore:)` instances. That cross-store assignment (calendar from
   `sharedTestEventStore`, reminder from a local `EKEventStore`) crashed EventKit.
   The child used the self-consistent `makeSavedReminder(title:)` fixture instead —
   same intent (non-empty id + calendar), no cross-store assignment.

3. **Phase 2 `isSavable` relocation.** Two new guards pushed `ReminderStore`'s class
   body to 502 lines, tripping `type_body_length` (warning 500; `--strict` makes it an
   error). Rather than add a `swiftlint:disable` (which itself trips
   `blanket_disable_command`), `isSavable` was moved from a class-private method to a
   file-scope `private func` (it uses no `self` state). Behaviour is unchanged; the
   class body is back under the threshold.

4. **Phase 3 test EventKit-store unification.** The plan's literal call sites
   (`FakeEventStore(defaultCalendar: makeCalendar(title: "Reminders"))`,
   `InMemoryEventStore(defaultCalendar: makeCalendar(title: "Reminders"))`) raised
   `NSInternalInconsistencyException: "Cannot copy an object with changes from one
   event store to another"` at `setCalendar:`, because `makeCalendar` built calendars
   on `sharedTestEventStore` while the fakes created reminders on different live
   `EKEventStore`s. Fix (approved by the parent): `InMemoryEventStore.sharedStore` is
   now `internal` (was `private`), `TestFixtures.sharedTestEventStore` aliases it, and
   `FakeEventStore.storeForReminderCreation` uses it — so every fixture reminder/
   calendar and both fakes share one store. `InMemoryEventStore.makeReminder`'s
   `defaultCalendar` identity semantics are unchanged. This is a broader
   test-infrastructure change than the plan anticipated; it is why the full gate
   matters.

## Notes / out of scope

- `completeReminderSkipsSaveWhenIdentifierIsEmpty` still passes for the reason the
  plan called out (the empty id never matches the reminder's temp UUID); it does not
  exercise the identifier guard. Left as-is per the plan.
- `deleteReminder` (`eventStore.remove`) is intentionally untouched — the report is
  about `save`.
- Consequence of the guard: a plain `--ui-testing` seeded reminder (no calendar) will
  no longer complete; it no-ops instead of crashing. No UI test taps complete under
  plain `--ui-testing`, so no UI test changes.
