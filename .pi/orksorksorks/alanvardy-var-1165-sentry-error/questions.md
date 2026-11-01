# Research Questions

## Context
Focus on the SingleThread iOS app's main-thread lifecycle: app launch and
`AppViewModel` construction, the WatchConnectivity sync service, the
EventKit/ReminderStore persistence layer and App Group `UserDefaults`, the AI
sorting coordinator, and the app's Sentry crash/hang-reporting setup. Also map
existing unit-test seams and conventions used to exercise these subsystems
without real system services.

## Questions
1. What synchronous work runs on the main thread during app launch and
   `AppViewModel` initialization, and what dependencies does that construction
   chain touch (stores, coordinators, sync services, observers)?
2. How does the WatchConnectivity sync service (`SkippedReminderSyncService`)
   operate: on which queues/actors its delegate callbacks run, how activation
   and payload handling unfold, and how it intersects the main actor?
3. How does the EventKit `ReminderStore` persistence path execute reads,
   writes, settle delays, and change observers, and what isolation or
   synchronization primitives guard them?
4. How is the AI sorting coordinator triggered and executed — debounce,
   observation wiring, ranker invocation, and the actor/queue on which
   ranking work runs?
5. How are App Group `UserDefaults` values and their change notifications read
   and observed across the app and watch, and what single-instance or
   notification-filtering constraints exist?
6. What is the current Sentry integration (bootstrap options, hang/watchdog
   tracking, scrubbing) and what in-app diagnostics or breadcrumbs exist around
   hangs?
7. What test seams and conventions exist for exercising WatchConnectivity,
   EventKit, App Group persistence, and main-actor coordinator behavior in
   unit tests, and how are targeted tests run?
