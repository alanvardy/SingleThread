# Task

The dictation error message "No speech was detected." (and the other dictation
errors shown in the same place) currently stays visible forever once it
appears. It must disappear automatically after a couple of seconds, matching
the existing transient-feedback behaviour used for reminder creation.

Scope: `DictationViewModel.dictationError` is set in `startDictation()` and
rendered in `ContentView.bottomBar`. Add an auto-expiry (e.g. a
`Task.sleep`-based clear, mirroring how `creationFeedback` is cleared with
`CreationFeedback.displayDuration`) so the error text clears itself after a
short delay. Ensure a new error restarts/extends the timer and that a stale
timer cannot clear a newer error. Add unit-test coverage in
`SingleThreadTests/ReminderDictationTests.swift` (happy path: error clears
after the delay; sad path: a newer error is not cleared by an older timer).

## Why SMALL

A–F hold: one module (`SingleThread` app target), ~2–3 files, an existing
pattern (`creationFeedback` + `CreationFeedback.displayDuration` sleep-then-nil)
to copy; no schema, no new subsystem, no shared/convention code, no design
decision, and only local unit tests.

## Key files (if the recon found any)

- `SingleThread/DictationViewModel.swift` — owns `dictationError`; set in
  `startDictation()` (auth-denied branches and the `catch`), cleared at the
  start of a new dictation.
- `SingleThread/ContentView.swift:743` — `bottomBar` renders
  `viewModel.dictation.dictationError` as red caption text.
- `SingleThread/CreationFeedback.swift:17` — `displayDuration` (1.0s) and the
  existing sleep-then-clear pattern in `DictationViewModel.startDictation()`.
- `SingleThread/ReminderDictation.swift:216` — `DictationError` enum
  (`noSpeechDetected` etc.) producing the localized strings.
- `SingleThreadTests/ReminderDictationTests.swift` — existing
  `DictationViewModel` tests (e.g. `startDictationAddsReminderAndFlowsText`,
  `dictationError == nil` assertions) to extend.
