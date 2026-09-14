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
        func pushAllOmitsNeverSetEnableActionButtons() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-aab-absent-\(suffix)"),
                enableActionButtonsStore: BoolPreferenceStore(
                    defaults: .standard, key: "test-aab-absent-pref-\(suffix)", fallback: true))
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(
                context["enableActionButtons"] == nil,
                "a never-set preference is omitted so the receiver keeps its own default-on")
        }

        @Test
        func pushAllSendsExplicitEnableActionButtonsOff() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let prefStore = BoolPreferenceStore(
                defaults: .standard, key: "test-aab-off-pref-\(suffix)", fallback: true)
            prefStore.set(false)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-aab-off-\(suffix)"),
                enableActionButtonsStore: prefStore)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(
                (context["enableActionButtons"] as? Bool) == false,
                "an explicit off is synced")
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
