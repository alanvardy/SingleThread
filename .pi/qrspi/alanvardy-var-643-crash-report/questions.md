# Research Questions

## Context

The repo is a Swift 6 iOS/watchOS app ("SingleThread") that uses Swift's actor-model
concurrency. In `SingleThread/ReminderDictation.swift`, an `@MainActor` async method
resumes a `CheckedContinuation` directly from a `SFSpeechRecognizer.requestAuthorization`
completion callback. On device, that callback is delivered on a non-main dispatch
queue, and a MainActor executor assertion aborts the process. Explore how the
callback-returning framework APIs are bridged to the actor model, how the concurrency
configuration is set up per target, and how the repo's other callback-bridging paths
are structured and tested.

## Questions

1. How does `ReminderDictation.requestAuthorization()` transfer control from the
   `SFSpeechRecognizer` completion callback back to the `async` caller, and where is
   it invoked/consumed? Trace the authorization status value from its seed through
   its use by the UI.

2. What do the crash report's top frames (`_dispatch_assert_queue_fail`,
   `dispatch_assert_queue`, `swift_task_isCurrentExecutorWithFlagsImpl`, the
   `ReminderDictation.requestAuthorization()` closure, `TCC`) indicate about the
   executing queue/thread? What is known (from docs or code) about which queue
   speech/Speech-recognition framework callbacks run on?

3. How is Swift concurrency and actor isolation configured per target (iOS app,
   tests, UI tests, watch app, widget, and the SingleThreadCore package)? Where are
   `SWIFT_DEFAULT_ACTOR_ISOLATION`, `SWIFT_APPROACHABLE_CONCURRENCY`,
   `SWIFT_TREAT_WARNINGS_AS_ERRORS`, and `SWIFT_VERSION` set, and what does each do?

4. What patterns exist across the codebase for resuming a continuation — or
   re-rooting a framework/EventKit callback onto the main actor (e.g. inline
   `withCheckedContinuation` resume, explicit `Task { @MainActor in }` hops,
   `nonisolated(unsafe)` hooks, `@retroactive @unchecked Sendable` extensions)?
   Which are documented as running on which queue/thread?

5. How is the dictation/authorization flow exercised interactively (mic visibility
   gating, `startDictation`, error/denied states), and through which protocol seams
   and fakes are authorization/recording behaviors driven in tests? Is the real
   `ReminderDictation` continuation path covered by any test?