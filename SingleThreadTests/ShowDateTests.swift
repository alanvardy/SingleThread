import EventKit
@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct ShowDateTests {
    // MARK: Internal

    @Test
    func dateRowHiddenWhenShowDateDisabled() {
        let description = String(describing: makeCard(showDate: false).body)
        // The date row is the only `Text(_, style: .date)`; hiding it removes
        // the FormatStyleStorage. Title/notes are LocalizedTextStorage.
        #expect(!description.contains("FormatStyleStorage"))
    }

    @Test
    func dateRowShownWhenShowDateEnabled() {
        let description = String(describing: makeCard(showDate: true).body)
        #expect(description.contains("FormatStyleStorage"))
    }

    // MARK: Private

    private func makeCard(showDate: Bool) -> ReminderCardView {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Buy groceries"
        reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15)
        return ReminderCardView(reminder: reminder, showDate: showDate)
    }
}
