# Research Questions

## Context

This repo is a Swift 6.0 app built with `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`, so most app-target code runs on the main actor by default. The
dictation feature (`SingleThread/ReminderDictation.swift`) bridges
callback-based Speech/AVFoundation APIs into Swift `async`/`await` using
`withCheckedContinuation` and `Task`, and its authorization status is consumed
by SwiftUI views. Trace how concurrency, authorization, and callback threading
work in and around this feature.

## Questions

1. How does `ReminderDictation.requestAuthorization()` transfer control between
   the callback-based `SFSpeechRecognizer.requestAuthorization` API and its
   `async` caller? Trace the `withCheckedContinuation` usage in
   `SingleThread/ReminderDictation.swift` (and the `transcribe` path for
   comparison), including which thread/queue the framework completion handler
   runs on, where `continuation.resume` is invoked, and how that interacts with
   the class's `@MainActor` isolation.

2. What does the crash's top frames mean in this codebase's concurrency
   configuration? The crashed thread shows `_dispatch_assert_queue_fail`,
   `dispatch_assert_queue`, `swift_task_isCurrentExecutorWithFlagsImpl`, then
   the `requestAuthorization()` completion closure. Explain how
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift 6 strict concurrency, and
   `@preconcurrency` imports shape executor checks at runtime, and what kinds
   of code paths trip a `swift_task_isCurrentExecutorWithFlagsImpl` assertion.

3. How is speech-recognition authorization initiated and consumed across the
   app? Trace where `requestAuthorization()` is called from (e.g.
   `ContentView.startDictation()`), how `authorizationStatus` is stored and
   observed, how the mic button's visibility/behavior depends on
   `.notDetermined`/`.authorized` states, and how `SpeechTranscribing`'s
   protocol members are declared and implemented.

4. What patterns exist elsewhere in the repo for hopping results from
   callback-based, non-MainActor framework APIs back onto the main actor?
   Look at how `ReminderStore` (EventKit), watch-connectivity sync, and any
   other `withCheckedContinuation`/`Task { @MainActor in }`/`nonisolated(unsafe)`
   call sites handle thread-to-actor handoffs, and what the established
   convention is for resuming a continuation that an `@MainActor`-isolated
   method is awaiting.

5. How is `ReminderDictation` covered by tests? Describe the `SpeechTranscribing`
   protocol seam, the fake transcriber used in
   `SingleThreadTests/ReminderDictationTests.swift` and
   `MicrophoneToggleTests.swift`, what unit tests exercise (authorization
   status, transcribe flows, mic gating), whether any test drives the real
   `requestAuthorization` continuation path, and how
   `SWIFT_DEFAULT_ACTOR_ISOLATION` differs between the app target and the test
   target.