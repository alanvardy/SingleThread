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
    }

    @Test
    func todayAtBeginningOfText() {
        let result = ReminderDictationParser.parse("Today buy groceries")
        #expect(result.title == "buy groceries")
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
    }

    // MARK: Tomorrow

    @Test
    func tomorrowExtractsDateAndStripsPhrase() {
        let result = ReminderDictationParser.parse("Call dentist tomorrow")
        #expect(result.title == "Call dentist")
        #expect(Calendar.current.isDateInTomorrow(from: result.dueDateComponents))
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
    }

    // MARK: Time

    @Test
    func timeOfDayExtractsHourAndMinute() {
        let result = ReminderDictationParser.parse("Team standup at 9am")
        #expect(result.title == "Team standup")
        #expect(result.dueDateComponents?.hour == 9)
        #expect(result.dueDateComponents?.minute == 0)
    }

    // MARK: Only date

    @Test
    func onlyDateReturnsEmptyTitle() {
        let result = ReminderDictationParser.parse("tomorrow")
        #expect(result.title.isEmpty)
        #expect(Calendar.current.isDateInTomorrow(from: result.dueDateComponents))
    }

    // MARK: Multiple dates — first wins

    @Test
    func multipleDatesUsesFirst() {
        let result = ReminderDictationParser.parse("Meeting today rescheduled to tomorrow")
        #expect(result.title == "Meeting rescheduled to tomorrow")
        #expect(Calendar.current.isDateInToday(from: result.dueDateComponents))
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
