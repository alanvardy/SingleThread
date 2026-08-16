import EventKit

/// Pure ordering for reminders: first by priority (high > medium > low > none),
/// then by due date (soonest first). Reminders without a due date sort after
/// dated ones. Ties fall back to an alphabetic title comparison for stability.
public nonisolated enum ReminderSort {
    public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        let lhsRank = ReminderPriority.rank(for: lhs.priority)
        let rhsRank = ReminderPriority.rank(for: rhs.priority)
        switch (lhsRank, rhsRank) {
        case let (.some(a), .some(b)) where a != b:
            return a < b
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let lhsDate = lhs.dueDateComponents?.date
        let rhsDate = rhs.dueDateComponents?.date
        switch (lhsDate, rhsDate) {
        case let (.some(a), .some(b)) where a != b:
            return a < b
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
