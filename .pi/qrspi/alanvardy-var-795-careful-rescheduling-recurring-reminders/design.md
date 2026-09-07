# Design Discussion

Branch: `alanvardy-var-795-careful-rescheduling-recurring-reminders`
Linear: VAR-795 — Careful rescheduling recurring reminders

## Current State

The app reschedules reminders by mutating `dueDateComponents` in place on the
fetched `EKReminder` object and saving it back to EventKit
(`ReminderStore.swift:363-368`). No code path reads, mutates, or clears
`recurrenceRules` on any existing reminder — the only `recurrenceRules`
assignment is inside `makeReminder` for brand-new reminders
(`EventKitStoring.swift:60-61`, `InMemoryEventStore.swift:103-118`).

**Recurrence structurally survives every mutation**: complete, undo, delete,
reschedule all operate on the same object reference last hydrated by `reload()`
(`ReminderStore.swift:439-…`). The delete-as-series doc comment
(`EventKitStoring.swift:31-32`) is the only series-vs-one-off statement in the
entire repo. Recurrence is read at exactly three display-only sites
(`ReminderCardView.swift:107`, `WatchReminderView.swift:345`,
`NextThingWidget.swift:212`); no action, store, or sync logic branches on it
(research Q4).

**The watch relay is identifier-addressed** — it ships only `calendarItemIdentifier`
+ up to five date-component ints (`SkippedReminderSyncService.swift:268-291`);
no reminder content (including recurrence rules) crosses the wire. The phone
mutates the same `EKReminder` by identifier on receipt
(`ReminderStore.swift:363-368`), so recurrence survives the relay structurally
as well.

**Test gap**: no test combines a repeating reminder with a reschedule. All
reschedule tests use title-only reminders; the `--seed` and `--ui-testing`
seams cannot express recurrence (`UITestingSeed.swift:123-126`,
`AppViewModel.swift:230-235`). The `FakeEventStore` and `InMemoryEventStore`
seams can build repeating reminders via `makeReminder(..., recurrenceRule:)`,
but no existing test exercises this with reschedule.

## Desired End State

A unit test proves that rescheduling a repeating reminder preserves its
`recurrenceRules` — the reminder stays repeating after the reschedule. The test
acts as regression protection; no production code changes are needed because the
codebase's object-identity mutation pattern already preserves recurrence.

**Verification**: the new test passes on both the `FakeEventStore` seam
(`EventKitStoringTests.swift`) and the `InMemoryEventStore` seam
(`ReminderStoreTests.swift`). The full gate `./scripts/test.sh` stays green.

## Patterns to Follow

- **Object-identity mutation**: mutate fields on the fetched `EKReminder` and
  re-save — same pattern as `complete` (`ReminderStore.swift:244-245`), `undo`
  (`ReminderStore.swift:276-277`), and the existing reschedule
  (`ReminderStore.swift:367-368`). Do not delete-then-recreate.

- **`FakeEventStore` seam** (`EventKitStoringTests.swift`): build a repeating
  reminder via `makeReminder(..., recurrenceRule:)` (:122-132), save, fetch,
  reschedule, assert `recurrenceRules` unchanged. Match the existing assertion
  style: `fake.saved.last === reminder` identity check (:315) and
  `recurrenceRules?.count == 1` content check (:223).

- **`InMemoryEventStore` seam** (`ReminderStoreTests.swift`): build via
  `store.addReminder(title:notes:dueDate:recurrenceRule:)` (:222), reschedule,
  assert recurrence survives. Account for the append-without-dedup behavior of
  `InMemoryEventStore.save` (`InMemoryEventStore.swift:87-89`) — after
  reschedule the seeded reminder appears twice in `allReminders`; the test
  should assert on the identified reminder, not on list count.

- **Swift Testing conventions**: `import Testing`, `@Test`, no `test`/`testing`
  prefix on function names; force-unwrapping allowed in test fixtures only
  (`SingleThreadTests/.swiftlint.yml`).

- **Verify**: `make build` → targeted `-only-testing:SingleThreadTests` for
  the affected suites → final full `./scripts/test.sh`.

## Design Decisions

1. **Verify-only approach**: write a unit test proving recurrence survives
   reschedule; no production code changes. The research found zero evidence
   that reschedule erases recurrence — the mutation pattern is identical to
   complete/undo, which work correctly. Shipping a test without a code change
   is the lowest-risk path.

2. **No recurrence gate on the reschedule button**: the reschedule action
   remains available for repeating reminders. The research shows recurrence is
   display-only and no code path mutates it. Hiding the button would remove
   functionality to prevent a hypothetical bug for which there is no evidence.

3. **Unit test only, no UI test**: the recurrence-survival behavior is a
   data-flow concern (does the model preserve its rules after a mutation?), not
   a UI interaction. The recurrence icon already has UI coverage via the
   `recurrenceLabel` accessibility identifier (`ReminderCardView.swift:115`).
   Adding a UI test would require updating the `--seed` seam to support
   recurrence — disproportionate cost for a model-level assertion.

4. **Two test sites**: add one test in `EventKitStoringTests.swift` (FakeEventStore
   seam, verifies the save path preserves rules) and one in
   `ReminderStoreTests.swift` (InMemoryEventStore seam, verifies the
   store-level reschedule method preserves rules through settle/reload). Two
   layers give confidence without duplication — they test different seams.

5. **Pre-existing watch time-dropping bug out of scope**: the watch reschedule
   sheet emits only `.year/.month/.day` (`WatchReminderView.swift:299-301`),
   dropping time-of-day even for timed reminders. This is real but unrelated to
   recurrence. File a follow-up ticket.

6. **No seed/UI-testing format changes**: the `ReminderSeed` struct
   (`UITestingSeed.swift:123-126`) and `--ui-testing` seam
   (`AppViewModel.swift:230-235`) remain recurrence-free. If a future UI test
   needs a repeating reminder, that change earns its own design discussion.

## What We're NOT Doing

- **NOT hiding the reschedule button** for repeating reminders — no evidence of
  breakage.
- **NOT adding a UI test** — the behavior is a model concern, not a UI
  interaction.
- **NOT fixing the watch time-dropping bug** — separate ticket, unrelated to
  recurrence.
- **NOT updating `UITestingSeed` or `--ui-testing` seams** to support
  recurrence — out of scope.
- **NOT adding recurrence checks to `ActionMenuGate`** — no gate logic needs
  to change.
- **NOT changing the watch relay format** — recurrence is never on the wire;
  this is intentional and correct for identifier-addressed mutation.
- **NOT adding delete-as-occurrence or series-aware logic** — the app
  intentionally treats all reminders (repeating or not) as single objects; the
  `EventKitStoring.remove` doc comment (`EventKitStoring.swift:31-32`)
  explicitly documents this.

## Open Risks

- **Real `EKEventStore` behavior unverified**: EventKit might advance or
  re-derive `dueDateComponents` for a recurring reminder after we rewrite it
  on save. No code path reads the recurrence rule at reschedule time, so the
  anchor-date semantics are opaque. The seam tests prove our code preserves
  rules, but the real store could surprise us. Mitigation: manual on-device
  smoke test (reschedule a repeating reminder in-app, verify it stays repeating
  in Apple Reminders) before merging.

- **`InMemoryEventStore` dedup on re-save**: `save` appends without dedup
  (`InMemoryEventStore.swift:87-89`); rescheduling a seeded reminder duplicates
  it in `allReminders`. The new test must not assert on `allReminders.count`
  post-reschedule — it must find the reminder by identifier and assert on that
  specific instance.

- **Watch card staleness after relay**: the watchOS store branch does no local
  reload after firing the relay hook (`ReminderStore.swift:358-362`); the card
  shows the old date until the next `reload()`. This is pre-existing and
  out of scope, but worth noting that a watch reschedule of a repeating
  reminder will show the old due date briefly — recurrence icon stays correct
  either way.