import EventKit
import SingleThreadCore
import Testing

struct ReminderRecurrenceFormatterTests {
    @Test
    func nilRulesReturnsNil() {
        #expect(ReminderRecurrenceFormatter.format(nil) == nil)
    }

    @Test
    func emptyRulesReturnsNil() {
        #expect(ReminderRecurrenceFormatter.format([]) == nil)
    }

    @Test
    func dailySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Daily")
    }

    @Test
    func dailyIntervalTwo() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Every 2 days")
    }

    @Test
    func weeklySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Weekly")
    }

    @Test
    func weeklyIntervalThree() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 3, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Every 3 weeks")
    }

    @Test
    func monthlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Monthly")
    }

    @Test
    func yearlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == "Yearly")
    }
}
