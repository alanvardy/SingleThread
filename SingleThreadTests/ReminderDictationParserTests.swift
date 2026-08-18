import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

// MARK: - ReminderDictationParser

@MainActor
struct ReminderDictationParserTests {
    // MARK: No date

    @Test
    func plainTextReturnsAsTitle() {
        let result = ReminderDictationParser.parse("Buy groceries")
        #expect(result.title == "Buy groceries")
        #expect(result.dueDateComponents == nil)
    }

    @Test
    func emptyTextReturnsEmptyTitle() {
        let result = ReminderDictationParser.parse("   ")
        #expect(result.title.isEmpty)
        #expect(result.dueDateComponents == nil)
    }

    // MARK: Today

    @Test
    func todayExtractsDateAndStripsPhrase() {
        let result = ReminderDictationParser.parse("Buy groceries today")
        #expect(result.title == "Buy groceries")
        #expect(result.dueDateComponents != nil)
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == nil)
        #expect(result.dueDateComponents?.minute == nil)
    }

    @Test
    func todayAtBeginningOfText() {
        let result = ReminderDictationParser.parse("Today buy groceries")
        #expect(result.title == "buy groceries")
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == nil)
    }

    // MARK: Tomorrow

    @Test
    func tomorrowExtractsDateAndStripsPhrase() {
        let result = ReminderDictationParser.parse("Call dentist tomorrow")
        #expect(result.title == "Call dentist")
        #expect(Calendar.current.isDateInTomorrow(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == nil)
        #expect(result.dueDateComponents?.minute == nil)
    }

    // MARK: Specific day

    @Test
    func nextMondayExtractsFutureWeekday() {
        let result = ReminderDictationParser.parse("Submit report next Monday")
        #expect(result.title == "Submit report")
        #expect(result.dueDateComponents != nil)
        guard let components = result.dueDateComponents,
              let date = Calendar.current.date(from: components) else {
            Issue.record("Expected valid date components")
            return
        }
        let weekday = Calendar.current.component(.weekday, from: date)
        #expect(weekday == 2) // Monday is 2 in Gregorian
        #expect(date > Date())
        #expect(result.dueDateComponents?.hour == nil)
        #expect(result.dueDateComponents?.minute == nil)
    }

    // MARK: Time

    @Test
    func timeOfDayExtractsHourAndMinute() {
        let result = ReminderDictationParser.parse("Team standup at 9am")
        #expect(result.title == "Team standup")
        #expect(result.dueDateComponents?.hour == 9)
        #expect(result.dueDateComponents?.minute == 0)
    }

    @Test
    func todayWithExplicitTimeKeepsHourAndMinute() {
        let result = ReminderDictationParser.parse("Buy groceries today at 5pm")
        #expect(result.title == "Buy groceries")
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == 17)
        #expect(result.dueDateComponents?.minute == 0)
    }

    @Test
    func tomorrowWithExplicitTimeKeepsHourAndMinute() {
        let result = ReminderDictationParser.parse("Call dentist tomorrow at 9:30 am")
        #expect(result.title == "Call dentist")
        #expect(Calendar.current.isDateInTomorrow(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == 9)
        #expect(result.dueDateComponents?.minute == 30)
    }

    @Test
    func namedTimeNoonKeepsHourAndMinute() {
        let result = ReminderDictationParser.parse("Lunch at noon")
        #expect(result.title == "Lunch")
        #expect(result.dueDateComponents?.hour == 12)
        #expect(result.dueDateComponents?.minute == 0)
    }

    @Test
    func impliedTimeEveningKeepsHourAndMinute() {
        // NSDataDetector matches the entire phrase as a date expression
        let result = ReminderDictationParser.parse("Dinner this evening")
        #expect(result.title.isEmpty)
        #expect(result.dueDateComponents?.hour != nil)
    }

    @Test
    func impliedTimeTonightKeepsHourAndMinute() {
        let result = ReminderDictationParser.parse("Call mom tonight")
        #expect(result.title == "Call mom")
        #expect(result.dueDateComponents?.hour != nil)
    }

    // MARK: Only date

    @Test
    func onlyDateReturnsEmptyTitle() {
        let result = ReminderDictationParser.parse("tomorrow")
        #expect(result.title.isEmpty)
        #expect(Calendar.current.isDateInTomorrow(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == nil)
        #expect(result.dueDateComponents?.minute == nil)
    }

    // MARK: Multiple dates — first wins

    @Test
    func multipleDatesUsesFirst() {
        let result = ReminderDictationParser.parse("Meeting today rescheduled to tomorrow")
        #expect(result.title == "Meeting rescheduled to tomorrow")
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
    }

    // MARK: Recurrence — no recurrence

    @Test
    func plainTextHasNoRecurrence() {
        let result = ReminderDictationParser.parse("Buy groceries tomorrow")
        #expect(result.recurrenceRule == nil)
    }

    // MARK: Recurrence — bare frequencies

    @Test
    func everyWeekSetsWeeklyRecurrence() {
        let result = ReminderDictationParser.parse("Buy milk every week")
        #expect(result.title == "Buy milk")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 1)
        #expect(result.recurrenceRule?.daysOfTheWeek == nil)
        // No explicit date, so today (all-day) is the fallback due date.
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
        #expect(result.dueDateComponents?.hour == nil)
    }

    @Test
    func everyDaySetsDailyRecurrence() {
        let result = ReminderDictationParser.parse("Feed the cat every day")
        #expect(result.title == "Feed the cat")
        #expect(result.recurrenceRule?.frequency == .daily)
        #expect(result.recurrenceRule?.interval == 1)
    }

    @Test
    func everyMonthSetsMonthlyRecurrence() {
        let result = ReminderDictationParser.parse("Pay rent every month")
        #expect(result.title == "Pay rent")
        #expect(result.recurrenceRule?.frequency == .monthly)
        #expect(result.recurrenceRule?.interval == 1)
    }

    @Test
    func everyYearSetsYearlyRecurrence() {
        let result = ReminderDictationParser.parse("Anniversary every year")
        #expect(result.title == "Anniversary")
        #expect(result.recurrenceRule?.frequency == .yearly)
        #expect(result.recurrenceRule?.interval == 1)
    }

    // MARK: Recurrence — intervals

    @Test
    func everyTwoWeeksSetsWeeklyIntervalTwo() {
        let result = ReminderDictationParser.parse("Call mom every 2 weeks")
        #expect(result.title == "Call mom")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 2)
    }

    @Test
    func everyThreeDaysSetsDailyIntervalThree() {
        let result = ReminderDictationParser.parse("Take meds every 3 days")
        #expect(result.title == "Take meds")
        #expect(result.recurrenceRule?.frequency == .daily)
        #expect(result.recurrenceRule?.interval == 3)
    }

    @Test
    func everyOtherWeekSetsWeeklyIntervalTwo() {
        let result = ReminderDictationParser.parse("Take out trash every other week")
        #expect(result.title == "Take out trash")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 2)
    }

    // MARK: Recurrence — weekday-specific weekly

    @Test
    func everyWeekOnSundaySetsSundayRecurrence() {
        let result = ReminderDictationParser.parse("Buy milk every week on Sunday")
        #expect(result.title == "Buy milk")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 1)
        #expect(result.recurrenceRule?.daysOfTheWeek?.first?.dayOfTheWeek == .sunday)
        #expect(weekday(from: result.dueDateComponents) == 1) // Sunday
    }

    @Test
    func everyMondaySetsMondayRecurrence() {
        let result = ReminderDictationParser.parse("Submit report every Monday")
        #expect(result.title == "Submit report")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 1)
        #expect(result.recurrenceRule?.daysOfTheWeek?.first?.dayOfTheWeek == .monday)
        #expect(weekday(from: result.dueDateComponents) == 2) // Monday
    }

    @Test
    func everyTwoWeeksOnMondayKeepsIntervalAndDay() {
        let result = ReminderDictationParser.parse("Team sync every 2 weeks on Monday")
        #expect(result.title == "Team sync")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 2)
        #expect(result.recurrenceRule?.daysOfTheWeek?.first?.dayOfTheWeek == .monday)
        #expect(weekday(from: result.dueDateComponents) == 2) // Monday
    }

    // MARK: Recurrence — synonyms

    @Test
    func dailySetsDailyRecurrence() {
        let result = ReminderDictationParser.parse("Stretch daily")
        #expect(result.title == "Stretch")
        #expect(result.recurrenceRule?.frequency == .daily)
        #expect(result.recurrenceRule?.interval == 1)
    }

    @Test
    func weeklySetsWeeklyRecurrence() {
        let result = ReminderDictationParser.parse("Water plants weekly")
        #expect(result.title == "Water plants")
        #expect(result.recurrenceRule?.frequency == .weekly)
        #expect(result.recurrenceRule?.interval == 1)
    }

    @Test
    func monthlySetsMonthlyRecurrence() {
        let result = ReminderDictationParser.parse("Review budget monthly")
        #expect(result.title == "Review budget")
        #expect(result.recurrenceRule?.frequency == .monthly)
        #expect(result.recurrenceRule?.interval == 1)
    }

    @Test
    func annuallySetsYearlyRecurrence() {
        let result = ReminderDictationParser.parse("Renew passport annually")
        #expect(result.title == "Renew passport")
        #expect(result.recurrenceRule?.frequency == .yearly)
        #expect(result.recurrenceRule?.interval == 1)
    }

    // MARK: Recurrence — combined with time

    @Test
    func everyDayAtNineKeepsTimeAndDailyRecurrence() {
        let result = ReminderDictationParser.parse("Water plants every day at 9am")
        #expect(result.title == "Water plants")
        #expect(result.recurrenceRule?.frequency == .daily)
        #expect(result.recurrenceRule?.interval == 1)
        #expect(result.dueDateComponents?.hour == 9)
        #expect(result.dueDateComponents?.minute == 0)
    }

    // MARK: Recurrence — every other day / month / year

    @Test
    func everyOtherDaySetsDailyIntervalTwo() {
        let result = ReminderDictationParser.parse("Take meds every other day")
        #expect(result.title == "Take meds")
        #expect(result.recurrenceRule?.frequency == .daily)
        #expect(result.recurrenceRule?.interval == 2)
    }

    @Test
    func everyOtherMonthSetsMonthlyIntervalTwo() {
        let result = ReminderDictationParser.parse("Review budget every other month")
        #expect(result.title == "Review budget")
        #expect(result.recurrenceRule?.frequency == .monthly)
        #expect(result.recurrenceRule?.interval == 2)
    }

    @Test
    func everyOtherYearSetsYearlyIntervalTwo() {
        let result = ReminderDictationParser.parse("Renew passport every other year")
        #expect(result.title == "Renew passport")
        #expect(result.recurrenceRule?.frequency == .yearly)
        #expect(result.recurrenceRule?.interval == 2)
    }

    // MARK: Time — 24-hour format

    @Test
    func time24HourFormatExtractsHourAndMinute() {
        let result = ReminderDictationParser.parse("Meeting at 14:30")
        #expect(result.title == "Meeting")
        #expect(result.dueDateComponents?.hour == 14)
        #expect(result.dueDateComponents?.minute == 30)
    }
}

// MARK: - Helpers

private extension Calendar {
    func isDateInToday(from components: DateComponents?) -> Bool {
        guard let components, let date = date(from: components) else { return false }
        return isDateInToday(date)
    }

    func isDateInTomorrow(from components: DateComponents?) -> Bool {
        guard let components, let date = date(from: components) else { return false }
        return isDateInTomorrow(date)
    }
}

private func weekday(from components: DateComponents?) -> Int? {
    guard let components, let date = Calendar.current.date(from: components) else { return nil }
    return Calendar.current.component(.weekday, from: date)
}
