# Task

Fix a user-facing iOS crash in the "complete reminder" flow.

A user reports the app crashes on iPhone XR (iOS 18.7.10, build 18) every time
they swipe to complete a task. There are 4 TestFlight feedback zips on VAR-1104;
**all four are the identical crash** with the same comment ("swiped to complete
a task").

Crash signature (from `crashlog.crash` in the testflight_feedback zips):

```
Exception Type:  EXC_CRASH (SIGABRT)
Exception Reason: *** -[__NSDictionaryM setObject:forKeyedSubscript:]: key cannot be nil
Terminating Process: SingleThread
```

Full backtrace ends in app code as:

```
EventKit  EKEventStore.save(_:commit:)
SingleThread  EKEventStore.save(_:commit:)  (compiler-generated)
SingleThread  EKEventStore.save(_:commit:)  (protocol witness for EventKitStoring.save)
SingleThread  ReminderStore.completeReminder(identifier:)  (ReminderStore.swift:255)
SingleThread  ReminderStore.completeCurrentReminder()     (ReminderStore.swift:273)
SingleThread  ContentViewModel.completeCurrentReminder()  (ContentViewModel.swift:168)
```

So: completing a reminder calls `ReminderStore.completeReminder(identifier:)`
which performs an EventKit `save`. EventKit throws
`-[__NSDictionaryM setObject:forKeyedSubscript:]: key cannot be nil` when the
reminder's identifier/key is nil. The fix is in the completion save path in
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
(`completeReminder` ~line 294, called from `completeCurrentReminder` ~line 337,
which passes `reminder.calendarItemIdentifier`).

Reproduce, understand why the key can be nil (e.g. a reminder whose
`calendarItemIdentifier` is nil/missing), fix it (guard the save and/or handle
the nil-identifier reminder cleanly so it never reaches EventKit with a nil
key), and ship a unit test in `SingleThreadTests/ReminderStoreTests.swift`
that reproduces the reported symptom (completing a reminder with a
nil/empty identifier must not crash / must be handled).

## Why SMALL

All A–F hold: single deterministic bug with a fully-known call stack in one
module (`ReminderStore.swift` + its direct callers); 0–2 unknowns (root cause
clear from the dump; the only open question is why `calendarItemIdentifier`
is nil, answered by local inspection); no schema/migration, no new subsystem,
no design decision; fix follows the existing complete-reminder pattern; one
local unit test.

## Key files

- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` —
  `completeReminder` (~294) and `completeCurrentReminder` (~337); the
  EventKit save that throws.
- `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift` /
  `InMemoryEventStore.swift` — the `save(reminder, commit:)` interface.
- `SingleThread/ContentViewModel.swift` — `completeCurrentReminder` caller (cast
  and back-test surface).
- `SingleThreadTests/ReminderStoreTests.swift` — add the reproduction unit
  test here (Swift Testing).
- Source zips (4x `testflight_feedback*.zip`) attached to VAR-1104 if the
  backtrace needs re-verification.