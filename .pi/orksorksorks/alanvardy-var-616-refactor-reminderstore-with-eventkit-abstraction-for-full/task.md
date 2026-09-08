# Task

The SingleThread app can only unit-test the pure-logic paths of `ReminderStore`
today; its save, fetch, reload, and access-request paths call `EKEventStore`
directly and therefore need real EventKit authorization to exercise. This task
introduces an injected EventKit abstraction — a protocol wrapping EventKit's
save/fetch/reload/authorization operations — and writes unit tests for
`completeReminder`, `addReminder`, `reload`, `start`, and `requestAccess`,
keeping all existing tests green and preserving runtime behavior exactly.