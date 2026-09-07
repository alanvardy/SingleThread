# Implementation Summary

## Overview

Two unit tests prove that rescheduling a repeating reminder preserves its `recurrenceRules` — one at the `FakeEventStore` protocol seam, one at the `InMemoryEventStore` store-layer seam. No production code changes. The tests act as regression protection for the codebase's object-identity mutation pattern, which already preserves recurrence on every mutation path.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `8ddcffa` | Data-Access Layer — FakeEventStore Seam |
| 2     | `8f2a5d6` | Store Layer — InMemoryEventStore Seam |
| 3     | `3cb809b` | Final Gate |

All commits pushed to `origin/alanvardy-var-795-careful-rescheduling-recurring-reminders`.

## Automated Checks

- [x] `make build` (iOS Simulator build-for-testing) passes
- [x] `ReminderStoreWriteTests` suite passes — including new `reschedulePreservesRecurrenceRules` (12/12; plan's "24 tests" count was stale — suite actually has 12)
- [x] `ReminderStoreSkipCountTests/reschedulePreservesRecurrenceOnRepeatingReminder` passes (11/11 suite)
- [x] Full `./scripts/test.sh` CI-identical gate passes — pass-equivalent locally (only the two known pre-existing macOS `EntitlementStoreTests` SKTestSession failures; CI mac-tests are green)
- [x] Both new tests pass on iPhone 17 simulator **and** macOS within the full gate
- [x] SwiftFormat + SwiftLint `--strict` clean (zero tracked-file modifications from the gate's format pass)

## Manual Verification Items (from the plan)

- [ ] Confirm the new test name `reschedulePreservesRecurrenceRules` appears green in Xcode Test Navigator under `ReminderStoreWriteTests`
- [ ] Confirm the new test name `reschedulePreservesRecurrenceOnRepeatingReminder` appears green in Xcode Test Navigator (under `ReminderStoreSkipCountTests`)
- [ ] On-device smoke: reschedule a repeating reminder in-app, open Apple Reminders, confirm it still shows the repeat badge with the new due date

## Plan Deviations & Observations (small, plan intent preserved)

1. **`makeReminder` helper mismatch (Phases 1 & 2)**: the plan's snippets called a free `makeReminder(title:notes:dueDate:recurrenceRule:)` that does not exist in either test file.
   - Phase 1 (`EventKitStoringTests.swift`): adapted using the suite's `makeReminder(title:)` then setting `dueDateComponents` and `addRecurrenceRule(rule)` directly.
   - Phase 2 (`ReminderStoreTests.swift`): adapted using the file-scoped `makeReminder(title:priority:dateComponents:)` then `addRecurrenceRule(rule)`.
   - All four assertions in each test (same-object saved / findable-by-identifier, recurrence count == 1, due year == 2027) preserved.
2. **Phase 2 suite path**: the plan's checkbox referenced `-only-testing:SingleThreadTests/ReminderStoreTests/...`, but the insertion point (after the `#endif` closing `rescheduleResetsSkipCount`) is in the `ReminderStoreSkipCountTests` suite — accurate path is `SingleThreadTests/ReminderStoreSkipCountTests/...`. Cosmetic; equivalent run passed under the accurate path.
3. **Test-count claim stale**: plan said "24 tests (23 existing + 1 new)" for `ReminderStoreWriteTests`; the suite actually has 12 (11 + 1). Not a failure.
4. **Destination `OS=26` is fuzzy**: this machine has iOS 26.5 and 27.0 runtimes only (no 26.0). Subagents pinned the exact, validated `OS=26.5` in all build/test destinations.
5. **Phase 3 gate** required 3 attempts on this shared machine due to sibling-session interference (external `pkill -9 -f xcodebuild` SIGKILLing run 1 mid-unit-tests; simulator contention stalling run 2 in the iOS UI-test stage). Run 3 passed clean (pass-equivalent). The recurrence tests passed in the full gate on both iPhone and macOS.

## What's NOT in scope (unchanged from design)

No production code changes, no UI tests, no `UITestingSeed`/`--ui-testing` changes, no watch time-dropping fix, no recurrence gate on the reschedule button, no series-vs-one-off logic.
