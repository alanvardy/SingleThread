@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Filtered Reminders List View Tests

@MainActor
struct FilteredRemindersListViewTests {
    @Test
    func filteredRemindersListViewRendersEveryDisplay() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "first", listName: "Work"),
            ReminderDisplay(title: "second", priorityMarker: "!!"),
            ReminderDisplay(title: "third", dueDate: Date(timeIntervalSince1970: 0))
        ])
        let bodyDescription = String(describing: view.body)

        for title in ["first", "second", "third"] {
            #expect(bodyDescription.contains(title))
        }
    }

    @Test
    func filteredRemindersListViewRendersOnlyWhatItIsGiven() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "kept")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("kept"))
        #expect(!bodyDescription.contains("skipped"), "the view renders the display list it is handed, nothing else")
    }
}
