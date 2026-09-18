import Foundation

/// One reminder, flattened to the value data the ranker needs. `Sendable` so it
/// can cross into the ranking task; `Equatable` for the Phase-3 input digest.
public struct AIReminderCandidate: Sendable, Equatable {
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

    public init(ranker: any AIReminderRanking) {
        self.ranker = ranker
    }

    // MARK: Public

    /// Set by `AppViewModel` to write the ranking into `ReminderStore`.
    public var onRankingUpdated: (([String: Int]) -> Void)?

    public func update(rules: String, candidates: [AIReminderCandidate]) {
        let trimmed = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ranker.isAvailable else {
            // Blank rules or no ranking capability: clear any stale ranking so
            // the list settles on the `.priority` chain.
            pending?.cancel()
            pending = nil
            emit([:])
            return
        }
        pending?.cancel()
        pending = Task { [weak self, ranker] in
            do {
                let ranked = try await ranker.rank(candidates, rules: trimmed)
                guard let self else { return }
                pending = nil
                emit(Self.ranking(from: ranked))
            } catch {
                guard let self else { return }
                pending = nil
                // Retain the previous ranking.
            }
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    // MARK: Private

    private let ranker: any AIReminderRanking
    private var pending: Task<Void, Never>?

    /// First occurrence wins, so a duplicated identifier never overwrites an
    /// earlier (better) rank.
    private static func ranking(from identifiers: [String]) -> [String: Int] {
        var ranking: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() where ranking[identifier] == nil {
            ranking[identifier] = index
        }
        return ranking
    }

    private func emit(_ ranking: [String: Int]) {
        onRankingUpdated?(ranking)
    }
}
