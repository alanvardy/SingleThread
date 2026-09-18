import Foundation
import SingleThreadCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// On-device ranking of reminders through Apple's Foundation Models framework.
/// The model exists only on iOS/macOS 26+, and only when Apple Intelligence is
/// enabled and ready; everywhere else `rank` throws and the store keeps the
/// deterministic `.priority` chain.
nonisolated struct FoundationModelsReminderRanker: AIReminderRanking {
    enum Availability: Sendable, Equatable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    nonisolated static var availability: Availability {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return .available
                case let .unavailable(reason):
                    switch reason {
                    case .deviceNotEligible: return .deviceNotEligible
                    case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
                    case .modelNotReady: return .modelNotReady
                    @unknown default: return .modelNotReady
                    }
                @unknown default:
                    return .modelNotReady
                }
            }
            return .deviceNotEligible
        #else
            return .deviceNotEligible
        #endif
    }

    nonisolated static var isAvailable: Bool {
        availability == .available
    }

    nonisolated var isAvailable: Bool {
        Self.isAvailable
    }

    /// Immutable identifier list + rule text; the model is never asked to
    /// re-read titles it can get wrong.
    nonisolated static func prompt(candidates: [AIReminderCandidate], rules: String) -> String {
        let list = candidates.map { candidate -> String in
            var parts = ["id: \(candidate.identifier)", "title: \(candidate.title)"]
            if let notes = candidate.notes, !notes.isEmpty {
                parts.append("notes: \(notes)")
            }
            if candidate.priority > 0 {
                parts.append("priority: \(candidate.priority)")
            }
            if let due = candidate.dueDate {
                parts.append("due: \(due.formatted(date: .abbreviated, time: .shortened))")
            }
            if let listTitle = candidate.listTitle {
                parts.append("list: \(listTitle)")
            }
            return "- " + parts.joined(separator: ", ")
        }.joined(separator: "\n")
        return """
        Sort these reminders. Rules: \(rules)
        Return every id exactly once, best first.

        \(list)
        """
    }

    nonisolated func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, macOS 26.0, *),
                  SystemLanguageModel.default.availability == .available else {
                throw AIRankingError.unavailable
            }
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: Self.prompt(candidates: candidates, rules: rules),
                generating: RankedIdentifiers.self)
            return response.content.identifiers
        #else
            throw AIRankingError.unavailable
        #endif
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    nonisolated struct RankedIdentifiers {
        @Guide(description: "Reminder identifiers in ranked order, best first")
        var identifiers: [String]
    }
#endif
