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
        // MARK: - Activation

        @Test
        func activateSetsDelegateAndActivates() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-activate")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.activate()
            #expect(fake.activated)
        }

        // MARK: - Skip-set push

        @Test
        func pushSkipIDsUpdatesApplicationContext() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.pushSkipIDs(["A", "B", "C"])
            let context = try #require(fake.lastContext)
            let ids = try #require(context["skippedReminderIdentifiers"] as? [String])
            #expect(Set(ids) == ["A", "B", "C"])
        }

        @Test
        func pushSkipIDsHandlesError() {
            let fake = FakeSession()
            fake.pushShouldThrow = true
            let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push-error")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            // Should not crash/throw — error is logged internally
            service.pushSkipIDs(["A"])
            #expect(Bool(true)) // reached without crashing
        }

        // MARK: - Skip-set receive

        @Test
        func receiveContextMergesIDs() {
            let fake = FakeSession()
            let key = "test-sync-receive-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            // Pre-populate local store with ["A"]
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            // Simulate receiving ["B", "C"] from counterpart
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["B", "C"]])
            let saved = store.load()
            #expect(Set(saved) == ["A", "B", "C"])
        }

        @Test
        func receiveContextHandlesEmptyPayload() {
            let fake = FakeSession()
            let key = "test-sync-receive-empty-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.session(WCSession.default, didReceiveApplicationContext: [:])
            #expect(store.load() == ["A"]) // unchanged
        }

        @Test
        func receiveContextHandlesMalformedPayload() {
            let fake = FakeSession()
            let key = "test-sync-receive-bad-\(UUID().uuidString)"
            let store = SkippedReminderStore(defaults: .standard, key: key)
            store.save(["A"])
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.session(WCSession.default, didReceiveApplicationContext: ["wrongKey": 42])
            #expect(store.load() == ["A"]) // unchanged
        }

        // MARK: - Completion relay

        @Test
        func requestCompleteReminderSendsMessage() throws {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-request")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            service.requestCompleteReminder("ABC")
            let message = try #require(fake.lastMessage)
            let identifier = try #require(message["completeReminderIdentifier"] as? String)
            #expect(identifier == "ABC")
        }

        @Test
        func receiveMessageTriggersCompletionHook() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-receive")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            var received: String?
            service.onCompleteReminderReceived = { received = $0 }
            service.session(WCSession.default, didReceiveMessage: ["completeReminderIdentifier": "XYZ"])
            #expect(received == "XYZ")
        }

        @Test
        func receiveMessageIgnoresMalformedPayload() {
            let fake = FakeSession()
            let store = SkippedReminderStore(defaults: .standard, key: "test-complete-bad")
            let service = SkippedReminderSyncService(session: fake, skipStore: store)
            var received = false
            service.onCompleteReminderReceived = { _ in received = true }
            service.session(WCSession.default, didReceiveMessage: ["wrongKey": 42])
            #expect(!received)
        }
    }
#endif
