#if os(iOS) || os(watchOS)
    import Foundation
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    /// Push/receive tests for the `appLanguage` preference synced over the
    /// WatchConnectivity application-context payload. Lives in its own file so
    /// `SkippedReminderSyncServiceTests.swift` stays under the `file_length`
    /// threshold. Serialized because the `apply(context:)` path persists real
    /// App Group keys and writing them in parallel would race another test's
    /// assertions.
    @MainActor
    @Suite(.serialized)
    struct AppLanguageSyncTests {
        @Test
        func pushPayloadCarriesLanguageWhenSet() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let pref = AppLanguagePreference(defaults: .standard, key: "test-applang-push-\(suffix)")
            pref.setRawValue("de")
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-ids-\(suffix)"),
                appLanguageStore: pref, sendsAppLanguage: true)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect((context["appLanguage"] as? String) == "de")
        }

        @Test
        func pushPayloadOmitsLanguageWhenNeverSet() throws {
            // sendsAppLanguage false (the watch configuration) → key absent; a fresh
            // device keeps its own stored/system value.
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-abs-\(suffix)"))
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["appLanguage"] == nil)
        }

        @Test
        func applyContextPersistsLanguageAndFiresHook() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let pref = AppLanguagePreference(defaults: .standard, key: "test-applang-recv-\(suffix)")
            defer { UserDefaults.standard.removeObject(forKey: "test-applang-recv-\(suffix)") }
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-recvids-\(suffix)"),
                appLanguageStore: pref)
            var received: [AppLanguage] = []
            service.onAppLanguageReceived = { received.append($0) }
            service.session(WCSession.default, didReceiveApplicationContext: ["appLanguage": "ja"])
            #expect(pref.load() == .japanese) // persisted
            #expect(received == [.japanese]) // then notified
            service.session(WCSession.default, didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])
            #expect(received == [.japanese]) // absent key is a no-op
        }
    }
#endif
