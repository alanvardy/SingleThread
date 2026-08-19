import EventKit
import Foundation

// MARK: - EKReminder Sendable (retroactive)

/// EKReminder is a mutable, non-thread-safe EventKit class. This retroactive
/// conformance is load-bearing for two crossings:
///
/// 1. `ReminderStore.fetchReminders` resumes a
///    `CheckedContinuation<[EKReminder], Never>` from EventKit's completion
///    queue — `CheckedContinuation` requires its value to be `Sendable`.
/// 2. File-scoped `let` mock globals in targets that do not opt into
///    MainActor-default isolation (the watch/widget targets).
///
/// SAFETY INVARIANT: every `EKReminder` is created, mutated, and read only on the
/// `@MainActor` (`ReminderStore`, `ReminderSort`, and the views are all
/// MainActor-isolated). Never pass an `EKReminder` across a `Task.detached` or
/// `nonisolated` boundary.
///
/// REMOVAL PLAN: convert the continuation result to the Sendable `ReminderDisplay`
/// and replace the mock globals with Sendable value snapshots, then delete this
/// conformance.
extension EKReminder: @retroactive @unchecked Sendable {}

/// Computes the due-date boundary for the "today or overdue" filter.
nonisolated enum ReminderDateFilter {
    /// The last instant of today (23:59:59), so reminders due tomorrow are excluded.
    static func endOfToday(
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
    static func overdueCutoff(
        days: Int = 30,
        calendar: Calendar = .current,
        now: Date = Date()) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: startOfToday) else {
            return startOfToday
        }
        return cutoff
    }

    /// Returns `true` when a reminder is undated (`date == nil`) or its date falls
    /// within the "today or overdue" window `[overdueCutoff, endOfToday]`.
    static func isInCurrentWindow(
        _ date: Date?,
        calendar: Calendar = .current,
        now: Date = Date()) -> Bool {
        guard let date else { return true }
        return overdueCutoff(calendar: calendar, now: now) <= date
            && date <= endOfToday(calendar: calendar, now: now)
    }
}
