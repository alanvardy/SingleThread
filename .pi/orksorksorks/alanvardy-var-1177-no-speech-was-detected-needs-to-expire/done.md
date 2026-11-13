# Done

- **What was built**: `DictationViewModel.dictationError` now auto-expires after
  `dictationErrorDisplayDuration` (2.0s). All error mutations route through
  `showDictationError(_:)` / `clearDictationError()`, which schedule a
  generation-guarded `Task.sleep`-then-clear. A newer error cancels the pending
  timer and bumps the generation, so a stale timer cannot clear a newer error.
  `creationFeedback` and the `ContentView.bottomBar` render path are untouched.
- **Commit SHA(s)**: `e5e85222` — "Expire dictation errors after a short delay"
  (pushed to `alanvardy-var-1177-no-speech-was-detected-needs-to-expire`, PR #253).
- **Verification**:
  - `make format` — clean (261 files)
  - `make lint` — 0 violations, 0 serious (248 files)
  - `./scripts/test-one.sh SingleThreadTests/ReminderDictationTests` — 16 cases passed
    (includes new `dictationErrorClearsAfterDelay` happy path and
    `staleTimerDoesNotClearNewerDictationError` sad path)
  - `./scripts/test-one.sh SingleThreadTests/MicrophoneToggleTests` — 19 cases passed
    (confirms the defaulted `errorDisplayDuration` init param preserves the other
    `DictationViewModel` call site)
- **Reviewer findings**: No blockers. Two optional nits deferred:
  1. The sad-path test proves the stale-timer *outcome* but exercises the
     cancellation path more than the generation guard (the guard is
     defense-in-depth for the cancel-after-sleep race, hard to hit deterministically).
  2. The completed `dictationErrorClearTask` reference is not nil'd after it fires
     (harmless; `clearDictationError()` nils it).
- **Remaining manual items**: The unrelated `DELETEME` scaffold deletion is
  still uncommitted in the working tree — remove/commit it before merge per the
  ticket-teardown rules. Full CI gate (`./scripts/test.sh`) still needs to run
  once via the `run-gate` skill before merge. On-device/manual check: trigger a
  dictation error (e.g. no speech) and confirm the red caption clears after ~2s.
