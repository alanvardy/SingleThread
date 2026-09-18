import Foundation
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

    var callCount: Int {
        lock.withLock { calls }
    }

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        lock.withLock { calls += 1 }
        return order
    }

    // MARK: Private

    private let order: [String]
    private let lock = NSLock()
    private var calls = 0
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
    // MARK: Internal

    var order: [String] {
        get { lock.withLock { storedOrder } }
        set { lock.withLock { storedOrder = newValue } }
    }

    var shouldThrow: Bool {
        get { lock.withLock { storedShouldThrow } }
        set { lock.withLock { storedShouldThrow = newValue } }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        let (order, shouldThrow) = lock.withLock { () -> ([String], Bool) in
            calls += 1
            return (storedOrder, storedShouldThrow)
        }
        if shouldThrow {
            throw AIRankingError.unavailable
        }
        return order
    }

    // MARK: Private

    private let lock = NSLock()
    private var storedOrder: [String] = []
    private var storedShouldThrow = false
    private var calls = 0
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
    // MARK: Internal

    var callCount: Int {
        lock.withLock { calls }
    }

    func rank(_: [AIReminderCandidate], rules _: String) async throws -> [String] {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if call == 1 {
            try await Task.sleep(for: .seconds(3600))
        }
        return order
    }

    // MARK: Private

    private let order: [String] = ["b", "a"]
    private let lock = NSLock()
    private var calls = 0
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
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(emitted == [["a": 0, "b": 1]], "good ranking is emitted")

        ranker.shouldThrow = true
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))
        coordinator.cancel()
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(emitted == [["a": 0, "b": 1]], "good ranking is emitted")

        ranker.shouldThrow = true
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(emitted.count == 1, "a thrown error emits nothing, retaining the previous ranking")

        ranker.shouldThrow = false
        ranker.order = ["b", "a"]
        coordinator.update(rules: "errands by due date", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))
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
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1)

        let three = [candidate("a"), candidate("b"), candidate("c")]
        coordinator.update(rules: "clients first", candidates: three)
        try? await Task.sleep(for: .milliseconds(1000))

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
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1, "the first request is parked in its block")

        coordinator.update(rules: "second", candidates: candidates)
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(emitted == [["b": 0, "a": 1]], "only the newer generation's ranking is emitted")
    }

    @Test
    func reranksWhenCandidateContentChanges() async {
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: [candidate("a"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1)

        // Same ids and rules, changed candidate content.
        coordinator.update(
            rules: "clients first",
            candidates: [candidate("a", title: "A renamed"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(ranker.callCount == 2, "a content-only change re-ranks the same ids")
        #expect(emitted.count == 2)
    }

    @Test
    func reranksWhenContentChangesInFlight() async {
        let ranker = BlockOnceRanker()
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        var emitted: [[String: Int]] = []
        coordinator.onRankingUpdated = { emitted.append($0) }

        coordinator.update(rules: "clients first", candidates: [candidate("a"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1, "the first request is parked in its block")

        coordinator.update(
            rules: "clients first",
            candidates: [candidate("a", title: "A renamed"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(ranker.callCount == 2, "a content change supersedes the in-flight request")
    }

    @Test
    func skipsRepeatedCompletedRequests() async {
        let ranker = CannedRanker(order: ["a", "b"])
        let coordinator = AISortCoordinator(ranker: ranker, debounce: .milliseconds(20))
        coordinator.onRankingUpdated = { _ in }

        coordinator.update(rules: "clients first", candidates: [candidate("a"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(ranker.callCount == 1)

        // An unrelated App-Group write re-issues identical input once settled.
        coordinator.update(rules: "clients first", candidates: [candidate("a"), candidate("b")])
        try? await Task.sleep(for: .milliseconds(1000))

        #expect(ranker.callCount == 1, "a completed identical request is not re-run")
    }

    // MARK: Private

    private func candidate(_ identifier: String, title: String? = nil) -> AIReminderCandidate {
        AIReminderCandidate(
            identifier: identifier,
            title: title ?? identifier.uppercased(),
            notes: nil,
            priority: 5,
            dueDate: nil,
            listTitle: nil)
    }
}
