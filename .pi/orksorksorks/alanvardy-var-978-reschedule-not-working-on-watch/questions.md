# Research Questions

## Context

The codebase is a Swift iOS + watchOS reminder app with a shared core package. A reminder-reschedule action exists on the watch UI and is relayed over WatchConnectivity to the phone, where it writes to EventKit. Relevant areas: SingleThreadWatch (watch UI + app view model), SingleThreadCore (ReminderStore, SkippedReminderSyncService), SingleThread (iPhone app view model), and the four test suites.

## Questions

1. How does the watch reminder sheet UI invoke a reschedule, and what happens in the view model and the sheet when the action is confirmed? What state does the sheet hold (dates, flags), what does the confirm handler call, and what visible feedback does the UI produce? Focus: SingleThreadWatch/WatchReminderViewModel.swift and SingleThreadWatch/WatchReminderView.swift.

2. What exactly does ReminderStore.rescheduleReminder do on each platform target — the watch relay branch, the iOS EventKit write (find, mutate, save, reset skip count, settle, reload), and the return-value / error semantics of both branches? Focus: SingleThreadCore/ReminderStore.swift.

3. How does the SkippedReminderSyncService relay contract work — the requestRescheduleReminder payload construction, the message keys used, how an incoming message is decoded in the didReceiveMessage handler, the onRescheduleReminderReceived hook, and how service activation / WCSession delegate registration enables message flow? How do the same request/response message formats appear on the phone side? Focus: SingleThreadCore/SkippedReminderSyncService.swift and its tests.

4. How does the iPhone-side AppViewModel.setupSyncService wire its receive hooks — especially onRescheduleReminderReceived — and what guards or short-circuit conditions (WCSession.isSupported, in-memory store, activation ordering) constrain whether an incoming reschedule message reaches the EventKit write? Focus: SingleThread/AppViewModel.swift.

5. What existing tests and seams cover the reschedule chain — the individual test cases in RescheduleSyncTests, ReminderStoreWatchTests / ReminderStoreTests / EventKitStoringTests reschedule coverage, WatchReminderViewModelTests, the FakeSession / AppGroup.defaults / --ui-testing / --seed conveniences — and which hops of the chain does each drive versus leave unexercised?