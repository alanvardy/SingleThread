# Design Discussion — VAR-643 Crash Report: MainActor executor assert on `requestAuthorization`

## Current State

`ReminderDictation.requestAuthorization()` is an `@MainActor` async method on the
`SpeechTranscribing` protocol (`SingleThread/ReminderDictation.swift:22-24`). Its body
resumes a `CheckedContinuation` **inline** inside `SFSpeechRecognizer.requestAuthorization`'s
completion handler, with no dispatch hop (`ReminderDictation.swift:39-41`):

```swift
let status = await withCheckedContinuation { continuation in
    SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)   // ← no @MainActor hop
    }
}
```

Apple does not guarantee that completion runs on the app's main dispatch queue (research
Q2). On the iPhone 11 Pro (iOS 18.7.10) it fired on a non-main queue; the Swift 6 runtime
asserted `dispatch_assert_queue` / `swift_task_isCurrentExecutorWithFlagsImpl` while
resuming the MainActor continuation → `EXC_BREAKPOINT (SIGTRAP)` ~7s after launch.

`authorizationStatus` is seeded synchronously in `init` (`ReminderDictation.swift:27-29`),
written only inside `requestAuthorization()` (`:44-45`), and consumed by
`ContentView.startDictation()` (`ContentView.swift:501-511`) and `canDictate`
(`ContentView.swift:233-236`).

## Desired End State

The authorization flow never aborts when the completion arrives off the main queue. All
callback-bridged async paths resume their continuation **on the MainActor**. A unit test
(Swift Testing) drives the real continuation path with a completion delivered from a
genuinely off-main (`Task.detached`) context — red before the fix, green after.

## Patterns to Follow

- **Extract-then-hop-then-resume — the established pattern.** The transcript path
  (`awaitFinalResult`) declares its completion `@Sendable` (`ReminderDictation.swift:151`),
  extracts Sendable values off-actor (`:152-157`), then `Task { @MainActor in … }` before
  resuming (`:158`) and before the timeout resume (`:178`). `requestAuthorization` must
  adopt this exact shape: extract `status` (Sendable-safe), hop to main, then resume. This
  is the single strongest precedent in the file.
- **ResumptionGate single-resume guard** (`ReminderDictation.swift:144-147`) — reuse the
  same single-resume gate shape wherever competing resume sources exist.
- **Fakeable protocol seam for callback-returning frameworks.** `EventKitStoring`
  (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:7-40`) abstracts
  `EKEventStore`; `InMemoryEventStore` fakes it and completes synchronously
  (`InMemoryEventStore.swift:39-45`). Use the same seam shape for the authorization bridge.
- **`Task { @MainActor }` hoisting of framework-owned callbacks in the app layer**
  (`SingleThreadApp.swift:37-44`, `SkippedReminderSyncService.swift:41-44`) — keep hoist
  placement consistent.

## Patterns NOT to Follow

- Do **not** copy the inline resume (`ReminderDictation.swift:41` and the analogous
  `ReminderStore.swift:373`). It is the crash source and conflicts with the extract-then-hop
  precedent already in the same file.
- Do **not** use a write-once-before-`activate` `nonisolated(unsafe)` hook
  (`SkippedReminderSyncService.swift:41-44`) for this per-call async bridge; those are for
  stable wiring edges, not one-shot resume.
- Do **not** add a `@retroactive @unchecked Sendable` conformance
  (`ReminderDateFilter.swift:19-23`) to paper over the missing hop; it is a
  bounded-duration retrofit, not the fix for an unhopped resume.

## Design Decisions

1. **Authorization resume fix — mirror `awaitFinalResult`.** Extract `status` inside the
   `@Sendable` completion, then `Task { @MainActor in continuation.resume(returning: status) }`.
   — Consistent with the proven pattern; removes the only inline no-hop resume in dictation.
2. **Shared bridge helper.** Extract a small private async helper (e.g. `resumeOnMainActor`)
   used by `requestAuthorization`, `awaitFinalResult`, and `ReminderStore.fetchReminders` so
   the off-main → main re-entrance is implemented once and unit-tested once, not pasted three
   times. Preserve single-resume semantics via a `ResumptionGate`.
3. **Also fix `fetchReminders`.** `SingleThreadCore/…/ReminderStore.swift:371-374` uses the
   identical inline no-hop resume from `EKEventStore.fetchReminders`' completion. Apply the
   same extract + hop. `EKReminder` already crosses the continuation boundary Sendable via the
   retrofit, so extraction is safe.
4. **Test seam (Option A).** Add a fakeable bridge so the authorization unit test can deliver
   the completion from an off-main `Task.detached` context, driving the real continuation path.
   Test the fixed helper (`requestAuthorization` or the shared helper) with an off-main
   completion: red on current code, green after the hop.

## What We're NOT Doing

- No UI test for the mic→authorization→denied flow. Authorization is not UI-drivable today
  (the `--seed` seam does not surface `ReminderDictation`), and AGENTS.md permits
  unit-test-only for speech. (User Q4 — skipped explicitly.)
- No `@retroactive @unchecked Sendable` conformance changes.
- No change to isolation configuration (`SWIFT_DEFAULT_ACTOR_ISOLATION` /
  per target). Root cause is a missing hop, not misconfiguration.
- No new public surface on `SpeechTranscribing` beyond what the seam requires; no change to
  `ContentView.startDictation()` behavior or thresholds.
- No change to recording lifecycle / teardown.

## Open Risks

- **Off-main delivery is not reproducible on real hardware in CI.** The seam's detached
  dispatch reproduces the queue mismatch deterministically, but we cannot observe the real
  device queue. Correctness rests on the pattern precedent (transcript path) + the seam unit
  test + review.
- **Double-resume / timeout interplay.** `awaitFinalResult` guards against callback+timeout
  double-resume. The refactor must preserve that or the fix could mask a device-fatal case.
- **`fetchReminders` is a separate shipped behavior.** Folding it in widens the unit-test
  surface; the `InMemoryEventStore` fake completes synchronously, so an off-main seam must be
  added to prove it.
- **Regression of the happy path.** The added hop introduces a small scheduling delay; confirm
  existing dictation tests do not rely on timing that now crosses a Task boundary.

## Next

Proceed to `/4_structure` once approved. Re-open the decisions if structure-phase findings
conflict with the Option-A choices above.