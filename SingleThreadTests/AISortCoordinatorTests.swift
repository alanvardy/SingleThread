import SingleThreadCore
import Testing

// MARK: - Fakes

/// Records calls and returns a canned order (identifier order is dictionary-
/// literal: first occurrence wins, so a caller sees exactly the canned rank map).
private final class CannedRanker: AIReminderRanking, @unchecked Sendable {
    // MARK: Lifecycle

    init(order: [String]) {
        self.order = order
    }

    // MARK: Internal

    private(set) var callCount = 0

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        callCount += 1
        return order
    }

    // MARK: Private

    private let order: [String]
}

/// Always throws — proves errors leave the previous ranking in place.
private struct ThrowingRanker: AIReminderRanking {
    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        throw AIRankingError.unavailable
    }
}

/// Reports the ranker unavailable — the coordinator must clear any stale
/// ranking and never call `rank`.
private struct UnavailableRanker: AIReminderRanking {
    nonisolated var isAvailable: Bool {
        false
    }

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        throw AIRankingError.unavailable
    }
}

/// Serves a canned order and can be switched to throwing mid-test without
/// swapping the coordinator's ranker.
private final class SwitchableRanker: AIReminderRanking, @unchecked Sendable {
    var order: [String] = []
    var shouldThrow = false
    private(set) var callCount = 0

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        callCount += 1
        if shouldThrow {
            throw AIRankingError.unavailable
        }
        return order
    }
}

/// Never returns until cancelled — proves dedupe of in-flight requests without
/// racing a completion.
private struct NeverCompletingRanker: AIReminderRanking {
    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        try await Task.sleep(for: .seconds(3600))
        return []
    }
}

/// Blocks on the first call, resolves instantly afterwards — proves a stale
/// in-flight task cannot overwrite a newer generation's ranking.
private final class BlockOnceRanker: AIReminderRanking, @unchecked Sendable {
    var order: [String] = ["b", "a"]
    private(set) var callCount = 0

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        callCount += 1
        if callCount == 1 {
            try await Task.sleep(for: .seconds(3600))
        }
        return order
    }
}

// MARK: - AISortCoordinator

@MainActor
struct AISortCoordinatorTests {
    // MARK: Internal

    @Test
    func ranksWithFakeRanker() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["b", "a"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(emitted == [["b": 0, "a": 1]], "canned order becomes identifier → rank")
        #expect(ranker.callCount == 1)
    }

    @Test
    func retainsPreviousRankingWhenRankerThrows() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = SwitchableRanker()
        ranker.order = ["a", "b"]
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(emitted == [["a": 0, "b": 1]], "good ranking is emitted")

        ranker.shouldThrow = true
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(emitted.count == 1, "a thrown error emits nothing, retaining the previous ranking")
    }

    @Test
    func skipsBlankRules() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker)
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }
        let emptyRanking: [String: Int] = [:]

        coordinator.update(rules: "   ", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(emitted == [emptyRanking], "blank rules clear a stale ranking")
        #expect(ranker.callCount == 0, "the ranker is never called for blank rules")
    }

    @Test
    func fallsBackWhenRankerUnavailable() async {
        let candidates = [candidate("a"), candidate("b")]
        let coordinator = AISortCoordinator(ranker: UnavailableRanker())
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }
        let emptyRanking: [String: Int] = [:]

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(emitted == [emptyRanking], "unavailable ranking capability clears the ranking")
    }

    @Test
    func debouncesRapidEdits() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "first", candidates: candidates)
        coordinator.update(rules: "second", candidates: candidates)
        coordinator.update(rules: "third", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(ranker.callCount == 1, "rapid edits collapse into one ranking")
        #expect(emitted == [["a": 0, "b": 1]], "the trailing edit's ranking is emitted exactly once")
    }

    @Test
    func skipsIdenticalInputs() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(ranker.callCount == 1, "two synchronous identical updates produce one ranking call")
        #expect(emitted == [["a": 0, "b": 1]], "the deduplicated request emits exactly once")
    }

    @Test
    func cancelsInFlightRequest() async {
        let candidates = [candidate("a"), candidate("b")]
        let coordinator = AISortCoordinator(ranker: NeverCompletingRanker(), debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(50))
        coordinator.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(emitted.isEmpty, "a cancelled request never emits")
    }

    @Test
    func retainsRankingOnError() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = SwitchableRanker()
        ranker.order = ["a", "b"]
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(emitted == [["a": 0, "b": 1]], "good ranking is emitted")

        ranker.shouldThrow = true
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(emitted.count == 1, "a thrown error emits nothing, retaining the previous ranking")

        ranker.shouldThrow = false
        ranker.order = ["b", "a"]
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(
            emitted == [["a": 0, "b": 1], ["b": 0, "a": 1]],
            "a later successful update replaces the retained ranking")
    }

    @Test
    func reconcilesUnknownAndMissingIds() {
        let ranked = ["ghost", "b", "b", "a"]
        let candidates = [candidate("a"), candidate("b"), candidate("c")]
        let result = AISortCoordinator.reconcile(ranked, against: candidates)
        #expect(
            result == ["b": 0, "a": 1, "c": 2],
            "unknown ids dropped, repeats deduped, missing ids appended in candidate order")
    }

    @Test
    func reranksWhenRemindersChange() async {
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }
        let two = [candidate("a"), candidate("b")]

        coordinator.update(rules: "clients first", candidates: two)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(ranker.callCount == 1)

        let three = [candidate("a"), candidate("b"), candidate("c")]
        coordinator.update(rules: "clients first", candidates: three)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(ranker.callCount == 2, "a changed candidate set re-ranks the same rules")
        #expect(emitted.count == 2, "each distinct input digest emits once")
    }

    @Test
    func ignoresStaleGeneration() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = BlockOnceRanker()
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "first", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(ranker.callCount == 1, "the first request is parked in its block")

        coordinator.update(rules: "second", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(emitted == [["b": 0, "a": 1]], "only the newer generation's ranking is emitted")
    }

    // MARK: Private

    private func candidate(_ identifier: String) -> AIReminderCandidate {
        AIReminderCandidate(
            identifier: identifier,
            title: identifier.uppercased(),
            notes: nil,
            priority: 5,
            dueDate: nil,
            listTitle: nil)
    }
}
