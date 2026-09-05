import EventKit

/// Pure ordering for reminders across the user-selectable ``SortOption`` modes.
public nonisolated enum ReminderSort {
    // MARK: Public

    /// Backward-compatible entry point: the legacy compound order
    /// (priority → due date → title), i.e. ``SortOption/priority``.
    public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        areInIncreasingOrder(lhs, rhs, using: .priority)
    }

    /// Option-aware comparator.
    public static func areInIncreasingOrder(
        _ lhs: EKReminder,
        _ rhs: EKReminder,
        using option: SortOption) -> Bool {
        switch option {
        case .priority:
            if let rank = comparePriorities(lhs, rhs) {
                return rank == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .dueDate:
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
        case .title:
            let comparison = titleComparison(lhs, rhs)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
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

    private static func compareDueDates(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult? {
        let lhsDate = lhs.dueDateComponents?.date
        let rhsDate = rhs.dueDateComponents?.date
        switch (lhsDate, rhsDate) {
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

    private static func compareLists(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult? {
        let lhsList = lhs.calendar?.title
        let rhsList = rhs.calendar?.title
        switch (lhsList, rhsList) {
        case let (.some(left), .some(right)):
            let comparison = left.localizedCaseInsensitiveCompare(right)
            return comparison == .orderedSame ? nil : comparison
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return nil
        }
    }

    private static func titleComparison(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    }
}
