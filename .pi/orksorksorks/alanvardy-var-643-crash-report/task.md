# Task — Crash report (VAR-643)

The iOS app "SingleThread" shipped to TestFlight crashed ~7 seconds after launch on
an iPhone 11 Pro (iOS 18.7.10). The crash is an `EXC_BREAKPOINT (SIGTRAP)` on
Thread 2: `_dispatch_assert_queue_fail` ← `dispatch_assert_queue` ←
`swift_task_isCurrentExecutorWithFlagsImpl` ←
`ReminderDictation.requestAuthorization()`, whose `SFSpeechRecognizer.requestAuthorization`
completion callback fires from a non-main dispatch queue (TCC) and trips a MainActor
executor assertion.

Investigate and fix the crash so the app no longer aborts on the MainActor-executor
assert when speech-recognition authorization is requested. The fix should be covered
by the appropriate tests.