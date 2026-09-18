import Foundation
import os

/// One reminder, flattened to the value data the ranker needs. `Sendable` so it
/// can cross into the ranking task; `Hashable` for the Phase-3 input digest.
public struct AIReminderCandidate: Sendable, Equatable, Hashable {
    // MARK: Lifecycle

    public init(
        identifier: String,
        title: String,
        notes: String?,
        priority: Int,
        dueDate: Date?,
        listTitle: String?) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.listTitle = listTitle
    }

    // MARK: Public

    public let identifier: String
    public let title: String
    public let notes: String?
    public let priority: Int
    public let dueDate: Date?
    public let listTitle: String?
}

/// Injectable ranking capability. Production is the app target's
/// FoundationModels adapter; tests use fakes.
public protocol AIReminderRanking: Sendable {
    /// Returns reminder identifiers best-first. The implementation must be
    /// treated as untrusted (Phase 3 reconciles the result).
    func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String]

    /// Whether this device can rank at all. Declared as a requirement so
    /// conformers' overrides dispatch through the existential the coordinator
    /// holds — an extension-only member would be statically dispatched to the
    /// default and never see a conformer's implementation.
    var isAvailable: Bool { get }
}

public extension AIReminderRanking {
    /// Defaults to `true` so fakes and other conformers need no change.
    nonisolated var isAvailable: Bool {
        true
    }
}

/// Errors the ranking layer can surface. The coordinator treats every error as
/// "keep the previous ranking".
public enum AIRankingError: Error, Equatable {
    case unavailable
}

/// Owns the in-flight ranking task and hands a validated identifier→rank map
/// back to the store. `@MainActor` is explicit — `SingleThreadCore` does not
/// enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (conventions §6).
@MainActor
public final class AISortCoordinator {
    // MARK: Lifecycle

    public init(ranker: any AIReminderRanking, debounce: Duration = .milliseconds(500)) {
        self.ranker = ranker
        self.debounce = debounce
    }

    // MARK: Public

    /// Set by `AppViewModel` to write the ranking into `ReminderStore`.
    public var onRankingUpdated: (([String: Int]) -> Void)?

    /// Drops invented identifiers, dedupes repeats, and appends omitted ones in
    /// the (identifier-sorted) candidate order. Exposed for direct unit testing.
    public static func reconcile(
        _ ranked: [String],
        against candidates: [AIReminderCandidate]) -> [String: Int] {
        let known = Set(candidates.map(\.identifier))
        var ordered: [String] = []
        var seen: Set<String> = []
        for identifier in ranked where known.contains(identifier) && seen.insert(identifier).inserted {
            ordered.append(identifier)
        }
        for candidate in candidates where seen.insert(candidate.identifier).inserted {
            ordered.append(candidate.identifier)
        }
        var ranking: [String: Int] = [:]
        for (index, identifier) in ordered.enumerated() {
            ranking[identifier] = index
        }
        return ranking
    }

    public func update(rules: String, candidates: [AIReminderCandidate]) {
        let trimmed = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ranker.isAvailable else {
            // Blank rules or no ranking capability: clear any stale ranking so
            // the list settles on the `.priority` chain.
            pending?.cancel()
            pending = nil
            lastRequestedDigest = nil
            lastCompletedDigest = nil
            emit([:])
            return
        }
        let digest = Self.digest(rules: trimmed, candidates: candidates)
        // Dedupe in-flight repeats, and completed repeats once idle, so an
        // unrelated App-Group write never re-runs the model for identical input.
        if pending != nil, digest == lastRequestedDigest {
            return
        }
        if pending == nil, digest == lastCompletedDigest {
            return
        }
        lastRequestedDigest = digest
        generation += 1
        let requestedGeneration = generation
        let requestedCandidates = candidates
        let requestedDigest = digest
        let wait = debounce
        pending?.cancel()
        pending = Task { [weak self, ranker] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            do {
                let ranked = try await ranker.rank(requestedCandidates, rules: trimmed)
                guard let self, generation == requestedGeneration else { return }
                pending = nil
                lastCompletedDigest = requestedDigest
                emit(Self.reconcile(ranked, against: requestedCandidates))
            } catch {
                guard let self, generation == requestedGeneration else { return }
                pending = nil
                // Retain the previous ranking and leave `lastCompletedDigest`
                // unset so an identical request is retried.
                Self.logger.error("AI ranking failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    // MARK: Internal

    /// Fingerprint of the full request inputs — rules plus every ranked
    /// candidate field — so a content change re-ranks; stable because
    /// `aiCandidates` is identifier-sorted.
    static func digest(rules: String, candidates: [AIReminderCandidate]) -> Int {
        var hasher = Hasher()
        hasher.combine(rules)
        for candidate in candidates {
            hasher.combine(candidate)
        }
        return hasher.finalize()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: "app.alanvardy.SingleThread", category: "AISort")

    private let ranker: any AIReminderRanking
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var lastRequestedDigest: Int?
    private var lastCompletedDigest: Int?
    private var generation = 0

    private func emit(_ ranking: [String: Int]) {
        onRankingUpdated?(ranking)
    }
}
