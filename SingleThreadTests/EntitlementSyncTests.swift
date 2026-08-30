#if os(iOS) || os(watchOS)
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    /// Tests for the freemium keys synced through WatchConnectivity: the
    /// entitlement flag and the lifetime completion count. Lives in its own
    /// file so `SkippedReminderSyncServiceTests` stays within SwiftLint's
    /// file/type length limits. Reuses the target-level `FakeSession`.
    @MainActor
    @Suite(.serialized)
    struct EntitlementSyncTests {
        // MARK: Internal

        // MARK: - Entitlement push

        @Test
        func pushAllIncludesEntitledWhenFlagEnabled() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
            let entitlement = EntitlementStore()
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                sortStore: makeTestSortStore(),
                completionCounter: CompletionCounterStore(
                    defaults: .standard,
                    key: UUID().uuidString),
                entitlementStore: entitlement,
                sendsEntitled: true)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["isEntitled"] as? Bool == false)
            // The completion count is part of every full-context push.
            #expect(context["completionCount"] != nil)
        }

        @Test
        func pushAllExcludesEntitledWhenFlagDisabled() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                sortStore: makeTestSortStore(),
                completionCounter: CompletionCounterStore(
                    defaults: .standard,
                    key: UUID().uuidString),
                entitlementStore: EntitlementStore(),
                sendsEntitled: false)
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["isEntitled"] == nil)
            // The completion count is always sent — no gating flag.
            #expect(context["completionCount"] != nil)
        }

        @Test
        func applyDecodesEntitledAndFiresHook() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                sortStore: makeTestSortStore(),
                entitlementStore: EntitlementStore())
            var received: [Bool] = []
            service.onEntitlementReceived = { received.append($0) }

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["isEntitled": true])
            #expect(received == [true])
        }

        // MARK: - Completion-count sync

        @Test
        func pushAllSendsCompletionCount() throws {
            let fake = FakeSession()
            let key = UUID().uuidString
            UserDefaults.standard.set(42, forKey: key)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: UUID().uuidString),
                sortStore: makeTestSortStore(),
                completionCounter: CompletionCounterStore(defaults: .standard, key: key))
            service.pushAll()
            let context = try #require(fake.lastContext)
            #expect(context["completionCount"] as? Int == 42)
        }

        @Test
        func applyDecodesCompletionCountAndFiresHook() {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                sortStore: makeTestSortStore())
            var received: Int?
            service.onCompletionCountReceived = { received = $0 }

            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["completionCount": 42])
            #expect(received == 42)
        }

        // MARK: - EntitlementState

        @Test
        func entitlementStateApplySetsIsEnabled() {
            let state = EntitlementState()
            #expect(!state.isEnabled)
            state.apply(true)
            #expect(state.isEnabled)
            state.apply(false)
            #expect(!state.isEnabled)
        }

        // MARK: Private

        /// An isolated sort store that never touches `AppGroup.defaults`.
        private func makeTestSortStore() -> SortOptionStore {
            SortOptionStore(defaults: .standard, key: "test-sort-\(UUID().uuidString)")
        }
    }
#endif
