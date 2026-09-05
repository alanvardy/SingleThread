import EventKit
@testable import SingleThread
import SwiftUI
import Testing

/// Pins the `RescheduleSheet` picker logic: a reminder with a due time offers
/// hour+minute picking, a date-only reminder must not.
@MainActor
struct RescheduleSheetTests {
    // MARK: Internal

    // MARK: Tests

    @Test
    func dateOnlyReminderPicksDateWithoutTime() {
        let reminder = makeReminder(due: DateComponents(year: 2026, month: 9, day: 5))

        #expect(!RescheduleSheet.hasDueTime(reminder))
        #expect(RescheduleSheet.displayedComponents(hasDueTime: false) == [.date])
    }

    @Test
    func timedReminderPicksDateAndTime() {
        let reminder = makeReminder(due: DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 30))

        #expect(RescheduleSheet.hasDueTime(reminder))
        #expect(RescheduleSheet.displayedComponents(hasDueTime: true) == [.date, .hourAndMinute])
    }

    @Test
    func reminderWithoutDueDateIsDateOnly() {
        let reminder = makeReminder(due: nil)

        #expect(!RescheduleSheet.hasDueTime(reminder))
    }

    @Test
    func nilReminderIsDateOnly() {
        #expect(!RescheduleSheet.hasDueTime(nil))
    }

    @Test
    func writeBackMaskFollowsDueTime() {
        #expect(RescheduleSheet.dateComponentsMask(hasDueTime: false) == [.year, .month, .day])
        #expect(
            RescheduleSheet.dateComponentsMask(hasDueTime: true)
                == [.year, .month, .day, .hour, .minute])
    }

    // MARK: Private

    /// Construction-only reminder; never saved through EventKit.
    private func makeReminder(due: DateComponents?) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.dueDateComponents = due
        return reminder
    }
}
