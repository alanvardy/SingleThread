import EventKit
import Foundation

extension EKReminder: @retroactive @unchecked Sendable {}

/// Computes the due-date boundary for the "today or overdue" filter.
public nonisolated enum ReminderDateFilter {
    /// The last instant of today (23:59:59), so reminders due tomorrow are excluded.
    public static func endOfToday(
        calendar: Calendar = .current,
        now: Date = Date()) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return startOfToday
        }
        return tomorrow.addingTimeInterval(-1)
    }

    /// The start of the "today or overdue" window: `days` days before today, at
    /// the start of that day. Reminders overdue by more than `days` are excluded
    /// so the EventKit fetch stays bounded.
    public static func overdueCutoff(
        days: Int = 30,
        calendar: Calendar = .current,
        now: Date = Date()) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: startOfToday) else {
            return startOfToday
        }
        return cutoff
    }
}
