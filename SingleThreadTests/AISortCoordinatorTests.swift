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

// MARK: - AISortCoordinator

@MainActor
struct AISortCoordinatorTests {
    // MARK: Internal

    @Test
    func ranksWithFakeRanker() async {
        let candidates = [candidate("a"), candidate("b")]
        let ranker = CannedRanker(order: ["b", "a"])
        let coordinator = AISortCoordinator(ranker: ranker)
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
        let coordinator = AISortCoordinator(ranker: ranker)
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
