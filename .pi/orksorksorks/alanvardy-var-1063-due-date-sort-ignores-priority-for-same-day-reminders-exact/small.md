# Task

Fix the `.dueDate` sort in `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift` so that priority is the secondary sort key for reminders sharing the same **calendar day** (not the same exact timestamp), matching the documented chain due date → priority → title.

**Problem:** `compareDueDates` compares `dueDateComponents?.date` — the exact timestamp — so priority is only consulted when two reminders have byte-identical due instants (e.g. two all-day entries). But the UI renders dates with the time omitted (`.date` style / `time: .omitted`), so two reminders both displaying "Sep 22" can carry different stored times (an all-day `00:00` local vs a timed `17:00`), and the earlier timestamp beats priority. To the user, "same due date" means *same day*, not the same instant.

**Proposed fix (from the ticket):** Day-bucket the comparator — compare `Calendar.startOfDay(dueDate)` first, then priority, then fall back to the exact time (or title) as a final deterministic key so same-day timed reminders keep a stable order.

## Why SMALL

Localized single-module comparator change following the existing sort-chain pattern; approach already specified by the ticket; no schema, no new subsystem, no design decision, few local tests.

## Key files / areas

- `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift` (78 lines) — `compareDueDates` (and the `.dueDate` comparator chain it feeds).
- `SingleThreadTests/` — Swift Testing unit tests for the sort (e.g. the existing `dueDateOptionSortsSoonestFirst` tie-break assertion must keep passing).

## Acceptance (from the ticket)

1. Unit test: two reminders on the same calendar day with different stored times, where the earlier one has lower priority, sort higher-priority first (reproduces the reported symptom).
2. Unit test: different days still sort soonest-first regardless of priority.
3. Existing `dueDateOptionSortsSoonestFirst` tie-break assertion keeps passing.
