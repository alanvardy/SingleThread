import EventKit
import Foundation

/// Pure ordering for reminders across the user-selectable ``SortOption`` modes.
public nonisolated enum ReminderSort {
    // MARK: Public

    /// Backward-compatible entry point: the legacy compound order
    /// (priority → due date → title), i.e. ``SortOption/priority``.
    public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        areInIncreasingOrder(lhs, rhs, using: .priority)
    }

    /// Option-aware comparator. ``SortOption/default`` imposes no ordering and
    /// always returns `false`; every other option returns a strict weak order.
    public static func areInIncreasingOrder(
        _ lhs: EKReminder,
        _ rhs: EKReminder,
        using option: SortOption) -> Bool {
        switch option {
        case .priority, .ai:
            if let rank = comparePriorities(lhs, rhs) {
                return rank == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .dueDate:
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            if let rank = comparePriorities(lhs, rhs) {
                return rank == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .title:
            return titleComparison(lhs, rhs) == .orderedAscending
        case .default:
            return false
        }
    }

    // MARK: Private

    private static func comparePriorities(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult? {
        let lhsRank = ReminderPriority.rank(for: lhs.priority)
        let rhsRank = ReminderPriority.rank(for: rhs.priority)
        switch (lhsRank, rhsRank) {
        case let (.some(left), .some(right)) where left != right:
            return left < right ? .orderedAscending : .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        default:
            return nil
        }
    }

    private static func compareDueDates(
        _ lhs: EKReminder,
        _ rhs: EKReminder,
        calendar: Calendar = .current) -> ComparisonResult? {
        let lhsDate = lhs.dueDateComponents?.date
        let rhsDate = rhs.dueDateComponents?.date
        switch (lhsDate, rhsDate) {
        case let (.some(left), .some(right)):
            let lhsDay = calendar.startOfDay(for: left)
            let rhsDay = calendar.startOfDay(for: right)
            if lhsDay != rhsDay {
                return lhsDay < rhsDay ? .orderedAscending : .orderedDescending
            }
            // Same calendar day: fall through to priority then title.
            return nil
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        default:
            return nil
        }
    }

    private static func titleComparison(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    }
}
