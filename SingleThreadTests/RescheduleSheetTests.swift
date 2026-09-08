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

    @Test
    func rescheduleSheetPutsLabelBesidePicker() {
        let sheet = RescheduleSheet(
            reminder: makeReminder(due: DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 30)),
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        // Literal label kept; label-less picker (Label == EmptyView) means no
        // duplicated "Reschedule to" coming from the picker itself.
        #expect(description.contains("Reschedule to"))
        #expect(description.contains("DatePicker<EmptyView"))
        #expect(description.contains("HStack<"))
    }

    @Test
    func dateOnlySheetStillRendersLabeledRow() {
        // Sad path: nil reminder → date-only fallback (no due time) still renders
        // the same centered row, pinning the no-due-time branch.
        let sheet = RescheduleSheet(
            reminder: nil,
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        #expect(description.contains("Reschedule to"))
        #expect(description.contains("DatePicker<EmptyView"))
        #expect(description.contains("AccessibilityAttachmentModifier"))
    }

    @Test
    func rescheduleSheetConfirmUsesProminentStyle() {
        let sheet = RescheduleSheet(
            reminder: nil,
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        // Stable token proven in SwipePromptTests.swift:52.
        #expect(description.contains("BorderedProminentButtonStyle"))
        // Native-chrome invariant: never routes through the shared modifier,
        // and centering is structural (no Spacer edge-push).
        #expect(!description.contains("SingleThreadButtonModifier"))
        #expect(!description.contains("Spacer"))
    }

    // MARK: Private

    /// Construction-only reminder; never saved through EventKit.
    private func makeReminder(due: DateComponents?) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.dueDateComponents = due
        return reminder
    }
}
