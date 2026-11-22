# Task

Fix the Sentry crash **SINGLETHREAD-3 / VAR-1181**: an unhandled
`NSInvalidArgumentException` thrown from `EKEventStore.save` during reminder
completion, reproducible in production build 1.4+21 (iOS 18.7.10, iPhone 11,8).

Reported stack:

```
EKEventStore.save
ReminderStore.completeReminder          (ReminderStore.swift:325)
ReminderStore.completeCurrentReminder   (ReminderStore.swift:342)   ← visibleReminders.first
ContentViewModel.completeCurrentReminder (ContentViewModel.swift:186)
ContentView.reminderList (ContentView.swift:484)
```

`save` is called inside the existing `do/catch` in `completeReminder`, yet the
exception escaped as an unhandled (non-`Error`) NSException — i.e. EventKit
raised an Objective-C exception (invalid argument to `save`), not a Swift
`Error`, so the current `catch` cannot intercept it. A previous ticket already
guarded one such case: an *empty `calendarItemIdentifier`* (nil key) — see the
`guard !identifier.isEmpty` + `ReminderStoreTests.completeReminderSkipsSaveWhenIdentifierIsEmpty`.
This crash reaches `save` on a reminder that is already looked up by a
non-empty identifier, so it is a **different** invalid-argument condition that
is still unguarded.

Goals:

1. Determine which precondition makes `EKEventStore.save` raise
   `NSInvalidArgumentException` for a reminder reached through
   `visibleReminders` → `completeReminder` (candidates to investigate: reminder
   whose `calendar` is nil / calendar removed or read-only, a detached or stale
   `EKReminder` instance from a previous `EKEventStore` after a store reset /
   `EKEventStoreChanged` refresh, an object that never round-tripped through
   `eventStore.calendarItem(withIdentifier:)`).
2. Add the pre-`save` guard(s) / validation so completion can never hand
   EventKit an invalid reminder — matching the existing guard pattern rather
   than relying on `catch` (which cannot catch NSException). Apply the same
   reasoning to the sibling `eventStore.save` call sites in
   `ReminderStore.swift` (undo-last-completion and the other two save paths)
   if they share the exposure; keep the change minimal and justified per site.
3. Return `false` (the documented contract: "false when the EventKit save
   failed") and avoid side effects (counter increments, undo retention, reload)
   when the guard trips.
4. Ship a unit test that reproduces the reported symptom first (a reminder that
   reaches `completeReminder` but must not be handed to `save`), then the fix —
   see the repo `AGENTS.md` bug-fix policy. Cover `completeCurrentReminder` as
   the reported entry point too, since the crash surfaced through it.

Non-goals: changing the completion UX, the undo flow's behaviour on success, or
the watchOS relay path.

# Why MEDIUM

Approach known (M1: one open question — which EventKit precondition is violated
— with an in-repo precedent to copy: the empty-identifier pre-save guard), and
no design decision (M2: no schema/migration, no new subsystem, no product
trade-off; a Swift-side guard is the only option since NSException cannot be
caught from Swift). Breadth trigger matched: **BROAD_TEST_SURFACE** — the fix
lands in the shared `SingleThreadCore` store's completion/save path that three
consumers depend on (iOS app, undo, watch relay via `onCompleteReminder`), and
the `save` sites are duplicated across `ReminderStore.swift`, so regressions are
not contained to one call site; reproduction is only reachable through a fake
store harness that models an invalid reminder.

# Key files

- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
  - `completeReminder(identifier:)` (~line 296; the `guard !identifier.isEmpty`
    precedent and `try eventStore.save(reminder, commit: true)` ~line 327)
  - `completeCurrentReminder()` (~line 343, `visibleReminders.first` — the
    reported crash frame)
  - `undoLastCompletion()` (~line 360 save site) and the other two
    `eventStore.save` calls (~lines 423, 453)
- `SingleThread/ContentViewModel.swift:186-189` — `completeCurrentReminder`
  caller (reported stack; likely no change needed)
- `SingleThread/ContentView.swift:~484` — reminder list action closure (reported
  stack; likely no change)
- Tests: `SingleThreadTests/ReminderStoreTests.swift` (`completeReminderSkipsSaveWhenIdentifierIsEmpty`
  ~line 526, `completeCurrentReminder*` ~lines 472-512) and
  `SingleThreadTests/EventKitStoringTests.swift` (~lines 151-190,
  `FakeEventStore` with `saveShouldThrow`)
- Shared test seams: `InMemoryEventStore`, `FakeEventStore`, `makeReminder(...)`
  (an unsaved `EKReminder` has no calendar — useful for reproducing an invalid
  save target)
