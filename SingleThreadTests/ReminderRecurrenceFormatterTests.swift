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
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Daily", bundle: .core))
    }

    @Test
    func dailyIntervalTwo() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Every \(2) days", bundle: .core))
    }

    @Test
    func recurrenceUsesPluralAwareLookup() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Every \(2) days", bundle: .core))
    }

    @Test
    func weeklySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Weekly", bundle: .core))
    }

    @Test
    func weeklyIntervalThree() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 3, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Every \(3) weeks", bundle: .core))
    }

    @Test
    func monthlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Monthly", bundle: .core))
    }

    @Test
    func yearlySingle() {
        let rule = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en("Yearly", bundle: .core))
    }
}
