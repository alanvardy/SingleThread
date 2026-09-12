#if os(iOS)
    import EventKit
    @testable import SingleThread
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    /// Hop 6: the phone's `onRescheduleReminderReceived` → `ReminderStore` wiring
    /// that `AppViewModel.setupSyncService` installs, driven through the service's
    /// real delegate entry point. `--ui-testing` builds an `InMemoryEventStore`-backed
    /// store (one "Buy groceries" reminder, `loadsReminders: false`) while leaving
    /// `usesInMemoryStore == false`, so the live sync service is wired.
    ///
    /// Serialized: `--ui-testing` writes `AppGroup.defaults["enableActionButtons"]`
    /// and a `.standard` swipe-prompt key.
    @MainActor
    @Suite(.serialized)
    struct AppViewModelSyncWiringTests {
        @Test
        func rescheduleMessageReachesStoreThroughWiring() async throws {
            let appViewModel = AppViewModel(arguments: ["--ui-testing", "--ui-testing-noop-settle"])
            let service = try #require(appViewModel.syncService)
            let store = appViewModel.store
            let reminder = try #require(store.reminders.first)
            let identifier = reminder.calendarItemIdentifier

            service.session(
                WCSession.default,
                didReceiveMessage: [
                    "rescheduleReminderIdentifier": identifier,
                    "dueDateComponents": ["year": 2027, "month": 1, "day": 2]
                ])

            // The receive hook funnels onto MainActor through a spawned Task; pump
            // until the write lands (noop-settle removes the 200 ms production pad).
            for _ in 0 ..< 20 where store.reminders.first?.dueDateComponents?.year != 2027 {
                try await Task.sleep(for: .milliseconds(20))
            }

            #expect(store.reminders.first?.dueDateComponents?.year == 2027)
            #expect(store.reminders.first?.dueDateComponents?.month == 1)
            #expect(store.reminders.first?.dueDateComponents?.day == 2)
        }

        @Test
        func rescheduleMessageIsIgnoredWhenStoreHasNoMatchingIdentifier() async throws {
            let appViewModel = AppViewModel(arguments: ["--ui-testing", "--ui-testing-noop-settle"])
            let service = try #require(appViewModel.syncService)
            let store = appViewModel.store

            service.session(
                WCSession.default,
                didReceiveMessage: [
                    "rescheduleReminderIdentifier": "does-not-exist",
                    "dueDateComponents": ["year": 2027, "month": 1, "day": 2]
                ])

            try await Task.sleep(for: .milliseconds(50))
            #expect(store.reminders.first?.dueDateComponents == nil)
        }
    }
#endif
