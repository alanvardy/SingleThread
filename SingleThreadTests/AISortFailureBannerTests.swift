#if os(iOS)
    import Foundation
    @testable import SingleThread
    import SingleThreadCore
    import Testing

    /// Reports itself available and throws, then succeeds once `succeeds` is
    /// flipped — drives the AI failure banner and its dismissal without a live
    /// Foundation Models session (which a test host cannot provide).
    private final class FlakyRanker: AIReminderRanking, @unchecked Sendable {
        // MARK: Internal

        var succeeds: Bool {
            get { lock.withLock { storedSucceeds } }
            set { lock.withLock { storedSucceeds = newValue } }
        }

        var callCount: Int {
            lock.withLock { calls }
        }

        nonisolated var isAvailable: Bool {
            true
        }

        func rank(_ candidates: [AIReminderCandidate], rules _: String) async throws -> [String] {
            let shouldSucceed = lock.withLock { () -> Bool in
                calls += 1
                return storedSucceeds
            }
            guard shouldSucceed else { throw RankerCrashed() }
            return candidates.map(\.identifier)
        }

        // MARK: Private

        private let lock = NSLock()
        private var storedSucceeds = false
        private var calls = 0
    }

    /// Deliberately not `AIRankingError.unavailable`, so the coordinator reads it
    /// as a runtime failure rather than the documented fallback.
    private struct RankerCrashed: Error {}

    /// The runtime-failure banner raises: the `AppViewModel` flag, the
    /// `ContentView` gate that reads it, the store effect, and the retry path.
    ///
    /// Serialized: `--ui-testing` writes App Group / standard defaults, and these
    /// tests stage `AISortRulesStore` rules in the same shared suite.
    @MainActor
    @Suite(.serialized)
    struct AISortFailureBannerTests {
        // MARK: Internal

        @Test
        func runtimeFailureRaisesTheBannerAndSuccessDismissesIt() async {
            let ranker = FlakyRanker()
            let (appViewModel, previousRules) = await prepare(ranker: ranker)
            defer { restore(appViewModel, rules: previousRules) }
            let contentView = ContentView(
                viewModel: appViewModel.makeContentViewModel(),
                appViewModel: appViewModel)

            appViewModel.store.sortOption = .ai
            #expect(!contentView.showsAISortFailureBanner, "no banner before any ranking attempt")

            appViewModel.retryAIRanking()
            await waitUntil { appViewModel.aiSortFailed }

            #expect(appViewModel.aiSortFailed, "a throwing ranker raises the flag")
            #expect(contentView.showsAISortFailureBanner, "the ContentView gate reads the flag")
            #expect(appViewModel.store.aiRanking.isEmpty, "a failed ranking leaves no rank map")

            ranker.succeeds = true
            appViewModel.retryAIRanking()
            await waitUntil { !appViewModel.aiSortFailed && !appViewModel.store.aiRanking.isEmpty }

            #expect(!appViewModel.aiSortFailed, "the next settled ranking dismisses the banner")
            #expect(!contentView.showsAISortFailureBanner)
            #expect(!appViewModel.store.aiRanking.isEmpty, "the successful ranking lands in the store")
        }

        @Test
        func retryAfterFailureReachesTheRankerAgain() async {
            let ranker = FlakyRanker()
            let (appViewModel, previousRules) = await prepare(ranker: ranker)
            defer { restore(appViewModel, rules: previousRules) }

            appViewModel.store.sortOption = .ai
            appViewModel.retryAIRanking()
            await waitUntil { appViewModel.aiSortFailed }
            let attemptsAfterFailure = ranker.callCount

            ranker.succeeds = true
            appViewModel.retryAIRanking()
            await waitUntil { ranker.callCount == attemptsAfterFailure + 1 }

            #expect(
                ranker.callCount == attemptsAfterFailure + 1,
                "a failed request leaves lastCompletedDigest unset, so 'Try Again' is not deduped")
        }

        @Test
        func deselectingAISortDismissesTheBanner() async {
            let (appViewModel, previousRules) = await prepare(ranker: FlakyRanker())
            defer { restore(appViewModel, rules: previousRules) }

            appViewModel.store.sortOption = .ai
            appViewModel.retryAIRanking()
            await waitUntil { appViewModel.aiSortFailed }
            #expect(appViewModel.aiSortFailed)

            appViewModel.store.setSortOption(.priority)

            #expect(
                !appViewModel.aiSortFailed,
                "leaving AI sort drops the banner along with the ranking it describes")
        }

        @Test
        func failureBannerCarriesTheMessageAndRetryAffordance() {
            let contentView = ContentView(
                loadsReminders: false,
                eventStore: InMemoryEventStore())
            let description = String(describing: contentView.aiSortFailureBanner)

            #expect(description.contains(ContentView.aiSortFailureMessage.key))
            #expect(description.contains("Try Again"))
            #expect(!contentView.showsAISortFailureBanner, "no AppViewModel means no banner")
        }

        // MARK: Private

        /// Builds the model over the deterministic `--ui-testing` store, parks the
        /// sort option so the run starts from a known state, and stages non-blank
        /// rules in the shared App Group suite (what `refreshAIRanking` reads),
        /// then briefly drains that write's `UserDefaults.didChangeNotification`.
        /// The sort option is parked at `.priority`, so the save kicks no ranking
        /// — the drain is just to keep the test's own ranking attempt the only one.
        /// Returns the previous rules text for the caller's `defer`.
        private func prepare(ranker: any AIReminderRanking) async -> (AppViewModel, String) {
            // The debounce is shortened so the tests do not wait out the
            // production 500 ms.
            let model = AppViewModel(
                arguments: ["--ui-testing", "--ui-testing-noop-settle"],
                session: FakeSession(),
                ranker: ranker,
                aiRankingDebounce: .milliseconds(20))
            model.store.sortOption = .priority
            let previousRules = AISortRulesStore().load()
            AISortRulesStore().save("clients first")
            await drainMainActor(for: .milliseconds(300))
            return (model, previousRules)
        }

        /// Restores the staged rules and parks the sort option first, so the
        /// restore's own App-Group notification cannot kick a ranking into the
        /// next test.
        private func restore(_ appViewModel: AppViewModel, rules: String) {
            appViewModel.store.sortOption = .priority
            AISortRulesStore().save(rules)
        }

        /// Polls until `condition` holds (or `timeout` elapses). Under parallel Swift
        /// Testing the AppViewModel's debounced MainActor ranking can be delayed
        /// past any fixed sleep, so the tests must await the *condition*, not a
        /// duration.
        private func waitUntil(timeout: Duration = .seconds(20), _ condition: () -> Bool) async {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            while !condition(), clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        /// Gives queued MainActor work a bounded number of turns, for the few negative
        /// assertions that have no positive signal to poll on.
        private func drainMainActor(for duration: Duration = .milliseconds(300)) async {
            let clock = ContinuousClock()
            let deadline = clock.now + duration
            while clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }
#endif
