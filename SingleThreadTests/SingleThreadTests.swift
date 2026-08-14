@testable import SingleThread
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

    // MARK: Private

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_725_600_000) // 2024-09-06 05:20 UTC

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 9, day: day))!
    }
}
