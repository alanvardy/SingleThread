import EventKit
import Foundation

/// Pure logic for the watch-side pending-completion set. No store access —
/// fully unit-testable in isolation.
nonisolated enum PendingCompletionLogic {
    /// Drops reminders whose identifier is still pending (the phone has not
    /// yet processed the watch's relayed completion).
    static func filtering(fetched: [EKReminder], pending: Set<String>) -> [EKReminder] {
        fetched.filter { !pending.contains($0.calendarItemIdentifier) }
    }

    /// Keeps only pending IDs that are still present in the fetch. IDs absent
    /// from `fetchedIdentifiers` have been completed by the phone and drain out.
    static func pruned(pending: Set<String>, fetchedIdentifiers: Set<String>) -> Set<String> {
        pending.intersection(fetchedIdentifiers)
    }

    /// Defensive net: drops any completed reminder that slipped through the
    /// incomplete predicate.
    static func removingCompleted(_ reminders: [EKReminder]) -> [EKReminder] {
        reminders.filter { !$0.isCompleted }
    }
}
