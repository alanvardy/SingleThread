#if os(iOS) || os(watchOS)
    import EventKit
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    // MARK: - Fake session for testing

    private final class FakeSession: SkipSyncSession {
        var activated = false
        var lastContext: [String: Any]?
        var lastMessage: [String: Any]?
        var pushShouldThrow = false

        func activate() {
            activated = true
        }

        func updateApplicationContext(_ applicationContext: [String: Any]) throws {
            if pushShouldThrow {
                throw NSError(domain: "test", code: 1)
            }
            lastContext = applicationContext
        }

        func sendMessage(
            _ message: [String: Any],
            replyHandler _: (([String: Any]) -> Void)?,
            errorHandler _: ((any Error) -> Void)?) {
            lastMessage = message
        }
    }

    @MainActor
    struct SkippedReminderSyncServiceTests {
        // MARK: Internal

        // MARK: - Activation

        @Test
        func activateSetsDelegateAndActivates() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-activate")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.activate()
            #expect(fake.activated)
        }

        // MARK: - Skip-set push

        @Test
        func pushAllSendsSkipIDs() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            store.save(["A", "B", "C"])
            service.pushAll()
            let context = try #require(fake.lastContext)
            let ids = try #require(context["skippedReminderIdentifiers"] as? [String])
            #expect(Set(ids) == ["A", "B", "C"])
        }

        @Test
        func pushHandlesError() {
            let fake = FakeSession()
            fake.pushShouldThrow = true
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push-error")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            // Should not crash/throw — error is logged internally
            service.pushAll()
            #expect(Bool(true)) // reached without crashing
        }

        // MARK: - Full-context push

        @Test
        func pushAllSendsFullFiveKeyShape() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-all-skip-\(suffix)")
            skipStore.save(["X"])
            let excludeStore = ExcludedListStore(defaults: .standard, key: "test-all-excl-\(suffix)")
            excludeStore.save(["Work"])
            let showUndatedStore = ShowUndatedRemindersPreference(defaults: .standard, key: "test-all-und-\(suffix)")
            showUndatedStore.save(true)
            let sortStore = SortOptionStore(defaults: .standard, key: "test-all-sort-\(suffix)")
            sortStore.save(.dueDate)
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-all-date-\(suffix)")
            showDateStore.set(false)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                excludeStore: excludeStore,
                sortStore: sortStore,
                showUndatedStore: showUndatedStore,
                showDateStore: showDateStore,
                sendsShowDate: true)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(Set(context["skippedReminderIdentifiers"] as? [String] ?? []) == ["X"])
            #expect(context["excludedListTitles"] as? [String] == ["Work"])
            #expect((context["showUndatedReminders"] as? Bool) == true)
            #expect(context["sortOption"] as? String == "dueDate")
            #expect((context["showDate"] as? Bool) == false)
        }

        // MARK: - Skip-set receive

        @Test
        func receiveContextFiresToggleHookAndKeepsSkipIDs() {
            let fake = FakeSession()
            let key = "test-sync-toggle-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            var received: [Bool] = []
            service.onShowUndatedRemindersReceived = { received.append($0) }
            service.session(
                WCSession.default,
                didReceiveApplicationContext: [
                    "skippedReminderIdentifiers": ["B"],
                    "showUndatedReminders": true
                ])
            #expect(received == [true])
            #expect(Set(store.load()) == ["B"])
        }

        @Test
        func receiveContextPersistsShowUndatedAndFiresHook() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let showUndatedStore = ShowUndatedRemindersPreference(
                defaults: .standard, key: "test-und-persist-\(suffix)")
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-und-persist-ids-\(suffix)"),
                showUndatedStore: showUndatedStore)
            var received: [Bool] = []
            service.onShowUndatedRemindersReceived = { received.append($0) }
            service.session(WCSession.default, didReceiveApplicationContext: ["showUndatedReminders": true])
            #expect(showUndatedStore.load()) // persisted (was hook-only before this phase)
            #expect(received == [true]) // still notified
        }

        @Test
        func showUndatedPersistsAcrossSimulatedRelaunch() {
            // Receive → throw the service away → a fresh store instance reads the value
            // back, proving the value survives process relaunch.
            let key = "test-und-relaunch-\(UUID().uuidString)"
            let fake = FakeSession()
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
                showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: key))
            service.session(WCSession.default, didReceiveApplicationContext: ["showUndatedReminders": true])
            let freshStore = ShowUndatedRemindersPreference(defaults: .standard, key: key)
            #expect(freshStore.load())
        }

        @Test
        func receiveContextFiresSkippedIdentifiersHandlerAfterPersisting() {
            let fake = FakeSession()
            let key = "test-skips-hook-\(UUID().uuidString)"
            let skipStore = SkippedReminderStore(defaults: .standard, key: key)
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore)
            var received: [[String]] = []
            service.onSkippedIdentifiersReceived = { received.append($0) }
            service.session(WCSession.default, didReceiveApplicationContext: [
                "skippedReminderIdentifiers": ["B", "C"]
            ])
            #expect(Set(skipStore.load()) == ["B", "C"]) // persisted first
            #expect(received == [["B", "C"]])
        }

        @Test
        func receiveContextFalsePropagates() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-toggle-false")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            var received: [Bool] = []
            service.onShowUndatedRemindersReceived = { received.append($0) }
            service.session(
                WCSession.default,
                didReceiveApplicationContext: [
                    "skippedReminderIdentifiers": [String](),
                    "showUndatedReminders": false
                ])
            #expect(received == [false])
            #expect(store.load().isEmpty)
        }

        @Test
        func receiveContextReplacesLocalIDs() {
            let fake = FakeSession()
            let key = "test-sync-receive-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            // Pre-populate local store with ["A"]
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            // The received context is the sender's full skip set — latest-wins, so
            // it replaces (not unions with) the local list.
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["B", "C"]])
            #expect(Set(store.load()) == ["B", "C"])
        }

        @Test
        func receiveContextClearPropagates() {
            let fake = FakeSession()
            let key = "test-sync-receive-clear-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A", "B"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            // An empty skip list is a legitimate "clear all skips" update and must
            // clear the local list rather than being ignored as a no-op.
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": [String]()])
            #expect(store.load().isEmpty)
        }

        @Test
        func receiveContextHandlesEmptyPayload() {
            let fake = FakeSession()
            let key = "test-sync-receive-empty-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.session(WCSession.default, didReceiveApplicationContext: [:])
            #expect(store.load() == ["A"]) // unchanged
        }

        @Test
        func receiveContextHandlesMalformedPayload() {
            let fake = FakeSession()
            let key = "test-sync-receive-bad-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.session(WCSession.default, didReceiveApplicationContext: ["wrongKey": 42])
            #expect(store.load() == ["A"]) // unchanged
        }

        // MARK: - Sort receive

        @Test
        func receiveContextSavesSortAndFiresHook() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-recv-skip-\(UUID().uuidString)")
            let sortStore = SortOptionStore(defaults: .standard, key: "test-recv-sort-\(UUID().uuidString)")
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
            var received: SortOption?
            service.onSortOptionReceived = { received = $0 }
            service.session(WCSession.default, didReceiveApplicationContext: [
                "skippedReminderIdentifiers": ["A"],
                "sortOption": "title"
            ])
            #expect(sortStore.load() == .title)
            #expect(received == .title)
        }

        @Test
        func receiveContextLeavesSortUnchangedOnMissingOrMalformedKey() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-recv-skip-bad-\(UUID().uuidString)")
            let sortStore = SortOptionStore(defaults: .standard, key: "test-recv-sort-bad-\(UUID().uuidString)")
            sortStore.save(.dueDate)
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
            var received = false
            service.onSortOptionReceived = { _ in received = true }
            service.session(WCSession.default, didReceiveApplicationContext: ["sortOption": "notAValue"])
            #expect(sortStore.load() == .dueDate) // unchanged
            #expect(!received)
            service.session(WCSession.default, didReceiveApplicationContext: [:])
            #expect(sortStore.load() == .dueDate) // unchanged
        }

        // MARK: - Completion relay

        @Test
        func requestCompleteReminderSendsMessage() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-request")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.requestCompleteReminder("ABC")
            let message = try #require(fake.lastMessage)
            let identifier = try #require(message["completeReminderIdentifier"] as? String)
            #expect(identifier == "ABC")
        }

        @Test
        func receiveMessageTriggersCompletionHook() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-receive")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            var received: String?
            service.onCompleteReminderReceived = { received = $0 }
            service.session(WCSession.default, didReceiveMessage: ["completeReminderIdentifier": "XYZ"])
            #expect(received == "XYZ")
        }

        @Test
        func receiveMessageIgnoresMalformedPayload() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-bad")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            var received = false
            service.onCompleteReminderReceived = { _ in received = true }
            service.session(WCSession.default, didReceiveMessage: ["wrongKey": 42])
            #expect(!received)
        }

        // MARK: - Delete relay

        @Test
        func requestDeleteReminderSendsMessage() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-delete-request")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.requestDeleteReminder("ABC")
            let message = try #require(fake.lastMessage)
            let identifier = try #require(message["deleteReminderIdentifier"] as? String)
            #expect(identifier == "ABC")
        }

        @Test
        func receiveMessageTriggersDeleteHook() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-delete-receive")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            var received: String?
            service.onDeleteReminderReceived = { received = $0 }
            service.session(WCSession.default, didReceiveMessage: ["deleteReminderIdentifier": "XYZ"])
            #expect(received == "XYZ")
        }

        @Test
        func receiveMessageIgnoringDeleteKeyIsNoOp() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-delete-bad")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            var received = false
            service.onDeleteReminderReceived = { _ in received = true }
            service.session(WCSession.default, didReceiveMessage: ["wrongKey": 42])
            #expect(!received)
        }

        // MARK: - Excluded-list push/receive

        @Test
        func pushAllCarriesExcludedListTitles() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-push-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excl-push-\(UUID().uuidString)")
            excludeStore.save(["Work", "Home"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.pushAll()

            let context = try #require(fake.lastContext)
            let titles = try #require(context["excludedListTitles"] as? [String])
            #expect(Set(titles) == ["Work", "Home"])
        }

        @Test
        func receiveContextReplacesLocalExcludedTitles() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-recv-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excl-recv-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["excludedListTitles": ["B", "C"]])

            #expect(Set(excludeStore.load()) == ["B", "C"])
        }

        @Test
        func receiveContextMissingExcludedTitleKeyIsNoOp() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-noop-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excl-noop-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            // A skip-only payload must not clobber exclusions (independent keys).
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

            #expect(excludeStore.load() == ["A"])
        }

        @Test
        func receivedExclusionRefreshFiltersVisibleReminders() {
            let fake = FakeSession()
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [
                    inListReminder(title: "A", list: "Work"),
                    inListReminder(title: "B", list: "Personal")
                ],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-excl-comp-skip-\(UUID().uuidString)"),
                excludeStore: ExcludedListStore(
                    defaults: .standard,
                    key: "test-excl-comp-excl-\(UUID().uuidString)"))
            // Wire the service's receive hook into the shared store, mirroring the app-layer wiring.
            service.onExcludedListTitlesReceived = { titles in
                store.refreshExcludedListTitles(Set(titles))
            }

            #expect(Set(store.visibleReminders.map(\.title)) == ["A", "B"]) // both visible before

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["excludedListTitles": ["Work"]])

            #expect(Set(store.visibleReminders.map(\.title)) == ["B"]) // "A" (Work) filtered
            #expect(Set(store.excludedListTitles) == ["Work"])
        }

        // MARK: - Show-date sync

        @Test
        func receiveContextWritesShowDate() {
            let fake = FakeSession()
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-sync-showdate-receive")
            showDateStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-receive-ids"),
                showDateStore: showDateStore)
            service.session(
                WCSession.default,
                didReceiveApplicationContext: [
                    "skippedReminderIdentifiers": ["A"],
                    "showDate": false
                ])
            #expect(showDateStore.isEnabled == false)
        }

        @Test
        func receiveContextMissingShowDateLeavesLocalUnchanged() {
            let fake = FakeSession()
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-sync-showdate-missing")
            showDateStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-missing-ids"),
                showDateStore: showDateStore)
            var fired = false
            service.onShowDateReceived = { _ in fired = true }
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["A"]])
            #expect(showDateStore.isEnabled) // unchanged
            #expect(!fired) // absent key is a no-op for the handler too
        }

        @Test
        func receiveContextFiresOnShowDateHandlerAndPersists() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-date-hook-\(suffix)")
            showDateStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-date-hook-ids-\(suffix)"),
                showDateStore: showDateStore)
            var received: [Bool] = []
            service.onShowDateReceived = { received.append($0) }
            service.session(WCSession.default, didReceiveApplicationContext: ["showDate": false])
            #expect(received == [false])
            #expect(!showDateStore.isEnabled)
        }

        @Test
        func sendsShowDateFalseOmitsKey() throws {
            let fake = FakeSession()
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-false"),
                showDateStore: ShowDatePreference(defaults: .standard, key: "test-sync-showdate-false-pref"),
                sendsShowDate: false)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["showDate"] == nil)
            // The other four keys must still travel when show-date is omitted.
            #expect(context["skippedReminderIdentifiers"] != nil)
            #expect(context["excludedListTitles"] != nil)
            #expect(context["showUndatedReminders"] != nil)
            #expect(context["sortOption"] != nil)
        }

        // MARK: Private

        /// An isolated sort store that never touches `AppGroup.defaults`.
        private func makeTestSortStore() -> SortOptionStore {
            SortOptionStore(defaults: .standard, key: "test-sort-store-\(UUID().uuidString)")
        }
    }

    /// Builds a reminder that lives in a calendar titled `list`, so exclusion
    /// filtering (which matches `calendar.title`) can be exercised.
    /// Construction only — never saved through EventKit.
    private func inListReminder(title: String, list: String) -> EKReminder {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = list
        reminder.calendar = calendar
        return reminder
    }
#endif
