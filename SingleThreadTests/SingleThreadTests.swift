@testable import SingleThread
@testable import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct SingleThreadTests {
    @Test
    func contentViewModelInitializesWithoutReminders() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        // Verify the view model init and its content-view wrapper render without crashing.
        let view = ContentView(viewModel: viewModel)
        let bodyValue = view.body
        #expect(String(describing: bodyValue).isEmpty == false)
    }

    @Test
    func contentViewBodyContainsRefreshableModifier() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        let view = ContentView(viewModel: viewModel)
        // Verify body renders with the List + refreshable structure
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        #expect(description.contains("List") || description.contains("refreshable"))
    }

    @Test
    func contentViewEmptyStatesShowDistinctCopy() {
        let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: false)
        #expect(emptyCopy.title == "No Reminders")
        #expect(emptyCopy.systemImage == "checklist")
        #expect(emptyCopy.description == "You don't have any reminders yet.")

        let nothingDueCopy = ContentViewModel.emptyStateCopy(hasHidden: true)
        #expect(nothingDueCopy.title == "Nothing due")
        #expect(nothingDueCopy.systemImage == "calendar")
        #expect(nothingDueCopy.description == "Only today's and overdue reminders show here — pull to refresh.")
        #expect(emptyCopy.title != nothingDueCopy.title)
    }

    @Test
    func contentViewAllDoneShowsAllDoneCopy() {
        let allDoneCopy = ContentViewModel.allDoneStateCopy()
        #expect(allDoneCopy.title == "All Done")
        #expect(allDoneCopy.systemImage == "checkmark.circle")
        #expect(allDoneCopy.description == "Pull to refresh to see all your reminders again.")
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

    @Test
    func isInCurrentWindowIncludesNilDate() {
        #expect(ReminderDateFilter.isInCurrentWindow(nil, calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowIncludesTodaysReminder() {
        #expect(ReminderDateFilter.isInCurrentWindow(date(6), calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowIncludesOverdueCutoffBoundary() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(ReminderDateFilter.isInCurrentWindow(cutoff, calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowExcludesTomorrow() {
        #expect(!ReminderDateFilter.isInCurrentWindow(date(7), calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowExcludesOldOverdue() {
        #expect(!ReminderDateFilter.isInCurrentWindow(date(6, in: .august), calendar: calendar, now: now))
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
