#if os(iOS) || os(watchOS)
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
        func pushUpdatesApplicationContext() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push")
            let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
            service.push(["A", "B", "C"], showUndatedReminders: false)
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
            service.push(["A"], showUndatedReminders: false)
            #expect(Bool(true)) // reached without crashing
        }

        @Test
        func pushCarriesCombinedContext() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-combined")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.push(["A"], showUndatedReminders: true)
            let context = try #require(fake.lastContext)
            let flag = try #require(context["showUndatedReminders"] as? Bool)
            #expect(flag)
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

        // MARK: - Sort push

        @Test
        func pushSkipIDsIncludesSortOption() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-push-skip-\(UUID().uuidString)")
            let sortStore = SortOptionStore(defaults: .standard, key: "test-push-sort-\(UUID().uuidString)")
            sortStore.save(.dueDate)
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
            service.push(["A"], showUndatedReminders: false)
            let context = try #require(fake.lastContext)
            #expect(context["sortOption"] as? String == "dueDate")
            #expect(Set(context["skippedReminderIdentifiers"] as? [String] ?? []) == ["A"])
        }

        @Test
        func pushSortOptionIncludesSkipIDs() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-push-sort-skip-\(UUID().uuidString)")
            skipStore.save(["X"])
            let sortStore = SortOptionStore(defaults: .standard, key: "test-push-sort-sort-\(UUID().uuidString)")
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, sortStore: sortStore)
            service.pushSortOption(.title)
            let context = try #require(fake.lastContext)
            #expect(context["sortOption"] as? String == "title")
            #expect(Set(context["skippedReminderIdentifiers"] as? [String] ?? []) == ["X"])
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

        // MARK: - Excluded-project push/receive

        @Test
        func pushExcludedProjectTitlesUpdatesApplicationContext() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-push-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-push-\(UUID().uuidString)")
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.pushExcludedProjectTitles(["Work", "Home"])

            let context = try #require(fake.lastContext)
            let titles = try #require(context["excludedProjectTitles"] as? [String])
            #expect(Set(titles) == ["Work", "Home"])
        }

        @Test
        func receiveContextReplacesLocalExcludedTitles() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-recv-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-recv-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["excludedProjectTitles": ["B", "C"]])

            #expect(Set(excludeStore.load()) == ["B", "C"])
        }

        @Test
        func receiveContextMissingExcludedTitleKeyIsNoOp() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-noop-skip-\(UUID().uuidString)")
            let excludeStore = ExcludedProjectStore(defaults: .standard, key: "test-excl-noop-\(UUID().uuidString)")
            excludeStore.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

            // A skip-only payload must not clobber exclusions (independent keys).
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

            #expect(excludeStore.load() == ["A"])
        }

        // MARK: Private

        /// An isolated sort store that never touches `AppGroup.defaults`.
        private func makeTestSortStore() -> SortOptionStore {
            SortOptionStore(defaults: .standard, key: "test-sort-store-\(UUID().uuidString)")
        }
    }
#endif
