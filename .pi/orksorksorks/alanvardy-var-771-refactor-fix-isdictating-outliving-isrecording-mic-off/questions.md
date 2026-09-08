# Research Questions

## Context

The dictation subsystem spans two `@MainActor @Observable` classes in the iOS
app target (`SingleThread/DictationViewModel.swift` and
`SingleThread/ReminderDictation.swift`), their injection points
(`AppViewModel.makeContentViewModel`, `ContentViewModel.init`, previews), the
SwiftUI surface that renders dictation state (`SingleThread/ContentView.swift`,
bottom-bar / action-cluster region), and the Swift Testing suite that exercises
the flow (`SingleThreadTests/ReminderDictationTests.swift`,
`MicrophoneToggleTests.swift`). Two boolean flags — `isDictating` on the view
model and `isRecording` on the recorder — are written and cleared in different
phases of one async flow, and only one of them is read by production UI.
Research should map how these flags and their neighbors are written, cleared,
read, and rendered across every exit path, and what test infrastructure exists
to observe them.

## Questions

1. **Flag lifecycles and the complete flow**: Trace the full dictation flow from
   the `micButton` tap to the final clearing of `isDictating` — including
   `DictationViewModel.startDictation()` and `ReminderDictation.transcribe()` —
   and enumerate *every* write and read site of `isDictating` (`:@"=true"`,
   `:@"=false"`) and `isRecording` (set true at `:@"=true"`, cleared inside
   `tearDownRecording()`), with file:line. Which exit paths (success, parse
   failure, `store.addReminder` returning false, thrown errors, the 5 s
   timeout, auth-denied early returns) reach which flag-clearing statements,
   and does any path leave either flag set? Where exactly do the parse,
   add-reminder, `creationFeedback`, and feedback-window steps sit relative to
   the two flags' lifetimes?

2. **UI rendering derivation and precedence**: How does `ContentView` decide
   what the bottom-bar / dictation area renders from the dictation-state
   properties (`dictationError`, `creationFeedback`, `isDictating`,
   `dictationText`, `canDictate`, `showMicrophoneButton`, authorization
   status)? Walk the branch chain (~`ContentView.swift:653-701`) in order:
   which property gates which sub-view, what are the precedence rules when
   several are non-nil/non-default at once, and is any rendered element driven
   by more than one flag simultaneously (e.g. the pulsing `recordingIndicator`
   under the `isDictating` branch)? Does any production code read
   `isRecording` directly?

3. **Post-transcribe tail, timing, and task lifetime**: What exactly happens
   between `transcribe` returning and `isDictating = false` in
   `startDictation()` — the order and approximate durations of parsing,
   `addReminder`, `creationFeedback` assignment, and the ~1 s feedback
   sleep — and how is that tail structured (do/catch placement, unstructured
   `Task` from the view)? Can an in-flight `startDictation` be cancelled or
   outlived: is there a `deinit`, `.onDisappear`, scene-phase handler, or
   backgrounding hook that touches dictation state or the task, and what
   happens if the user taps the mic again during the tail (re-entry guards,
   `.alreadyRecording`)?

4. **Teardown and state-reset conventions**: How does `ReminderDictation` reset
   its audio state and flags across all exit paths — the `defer { tearDownRecording() }`,
   the `prepareRecording()` throw path, the timeout-task guard, and the single
   `isRecording = false` write — and what other state do those paths reset
   (engine, tap, request, recognition task, audio session)? What teardown /
   cleanup conventions exist elsewhere in the app for paired or transient
   flags (e.g. `defer` blocks, `deinit`, `.onDisappear`, guard-based clears,
   watch completion-transition flags), and how are audio-session and
   authorzation-state refreshes (`refreshAuthorizationStatus`, scene-active
   handling) kept coherent with recording state?

5. **Test seams for the async dictation flow**: How do the dictation tests
   (`ReminderDictationTests.swift`, `MicrophoneToggleTests.swift`) inject and
   drive the flow — `FakeSpeechTranscriber` (preset results/errors, partials
   delivered with 50 ms sleeps, its own `isRecording` mirror), the detached
   `AuthorizationRequiring` seam, `InMemoryEventStore` + `ReminderStore(loadsReminders:)`,
   and real `Task.sleep` usage — and what do they assert and *when* (before,
   during, or only after the flow completes)? Is there any existing pattern in
   the test suite for observing or asserting state *inside* an async window
   (continuations, expectations, injected clocks, or timing tolerances), or
   for asserting that a state combination never occurs?

6. **Non-injectable audio dependencies**: Which parts of the recording path are
   not injectable — `ensureMicrophoneAccess()` (`AVCaptureDevice`), the
   `AVAudioSession` configuration, engine/tap setup — and how do the current
   tests (and the `AuthorizationRequiring` protocols) work around or bypass
   them? How is the microphone/permission half of the flow represented in the
   view model vs the recorder, and what does `refreshAuthorizationStatus` /
   the authorization-state lifecycle cover?