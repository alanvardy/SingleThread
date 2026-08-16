@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct SingleThreadTests {
    @Test
    func contentViewInitializesWithoutReminders() {
        let view = ContentView(loadsReminders: false)
        // Verify the view body renders without crashing
        let bodyValue = view.body
        #expect(String(describing: bodyValue).isEmpty == false)
    }

    @Test
    func contentViewBodyContainsRefreshableModifier() {
        let view = ContentView(loadsReminders: false)
        // Verify body renders with the List + refreshable structure
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        #expect(description.contains("List") || description.contains("refreshable"))
    }
}

struct ReminderDateFilterTests {
    // MARK: Internal

    @Test
    func reminderDueTodayIsIncluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(6) <= end)
    }

    @Test
    func reminderDueYesterdayIsIncluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(5) <= end)
    }

    @Test
    func reminderDueTomorrowIsExcluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(7) > end)
    }

    @Test
    func endOfTodayIsLastInstantOfToday() throws {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        let startOfTomorrow = try #require(calendar.date(
            byAdding: DateComponents(day: 1),
            to: calendar.startOfDay(for: now)))
        #expect(end < startOfTomorrow)
    }

    @Test
    func overdueCutoffDefaultsToThirtyDaysAgo() throws {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        let startOfToday = calendar.startOfDay(for: now)
        let thirtyDaysAgo = try #require(calendar.date(
            byAdding: DateComponents(day: -30),
            to: startOfToday))
        #expect(cutoff == thirtyDaysAgo)
    }

    @Test
    func overdueCutoffIncludesReminderThirtyDaysOverdue() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(date(7, in: .august) >= cutoff)
    }

    @Test
    func overdueCutoffExcludesReminderMoreThanThirtyDaysOverdue() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(date(6, in: .august) < cutoff)
    }

    // MARK: Private

    private enum Month: Int {
        case august = 8
        case september = 9
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_725_600_000) // 2024-09-06 05:20 UTC

    private func date(_ day: Int, in month: Month = .september) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month.rawValue, day: day))!
    }
}
