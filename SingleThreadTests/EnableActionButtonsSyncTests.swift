#if os(iOS) || os(watchOS)
    import Foundation
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    /// Push/receive tests for the `enableActionButtons` preference. Lives in its
    /// own file so `SkippedReminderSyncServiceTests.swift` stays under the
    /// `file_length` threshold. Serialized because every test reads and writes
    /// the same real App Group key the service pushes in `pushAll()` and
    /// persists in `apply(context:)`; running them in parallel would let one
    /// test's write race another's assertion.
    @MainActor
    @Suite(.serialized)
    struct EnableActionButtonsSyncTests {
        @Test
        func pushAllIncludesEnableActionButtons() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-aab-push-ids-\(suffix)"))
            AppGroup.defaults.set(true, forKey: "enableActionButtons")
            defer { AppGroup.defaults.removeObject(forKey: "enableActionButtons") }
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect((context["enableActionButtons"] as? Bool) == true)
        }

        @Test
        func receiveEnableActionButtonsPersistsAndFiresHook() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-aab-recv-ids-\(suffix)"))
            var received: [Bool] = []
            service.onEnableActionButtonsReceived = { received.append($0) }
            defer {
                AppGroup.defaults.removeObject(forKey: "enableActionButtons")
                UserDefaults.standard.removeObject(forKey: "enableActionButtons")
            }
            service.session(WCSession.default, didReceiveApplicationContext: ["enableActionButtons": true])
            #expect(AppGroup.defaults.bool(forKey: "enableActionButtons")) // persisted
            #expect(received == [true]) // then notified
            // Absent key is a no-op for both persistence and the handler.
            AppGroup.defaults.removeObject(forKey: "enableActionButtons")
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])
            #expect(!AppGroup.defaults.bool(forKey: "enableActionButtons"))
            #expect(received == [true])
        }
    }
#endif
