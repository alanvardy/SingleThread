import EventKit
import SingleThreadCore
import Testing

struct ReminderRecurrenceFormatterTests {
    // MARK: Internal

    @Test
    func nilOrEmptyRulesReturnsNil() {
        #expect(ReminderRecurrenceFormatter.format(nil) == nil, "nil rules → nil")
        #expect(ReminderRecurrenceFormatter.format([]) == nil, "empty rules → nil")
    }

    @Test
    func formatsKnownRules() {
        #expect(formatted(frequency: .daily, interval: 1) == String.en("Daily", bundle: .core), "daily × 1")
        #expect(formatted(frequency: .daily, interval: 2) == String.en("Every 2 days", bundle: .core), "daily × 2")
        #expect(formatted(frequency: .weekly, interval: 1) == String.en("Weekly", bundle: .core), "weekly × 1")
        #expect(formatted(frequency: .weekly, interval: 3) == String.en("Every 3 weeks", bundle: .core), "weekly × 3")
        #expect(formatted(frequency: .monthly, interval: 1) == String.en("Monthly", bundle: .core), "monthly × 1")
        #expect(formatted(frequency: .yearly, interval: 1) == String.en("Yearly", bundle: .core), "yearly × 1")
    }

    // MARK: Private

    private func formatted(frequency: EKRecurrenceFrequency, interval: Int) -> String? {
        let rule = EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil)
        return ReminderRecurrenceFormatter.format([rule])
    }
}
