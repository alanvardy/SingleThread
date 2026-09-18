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

    @Test
    func filteredRemindersListViewExplainsAnEmptySet() {
        let view = FilteredRemindersListView(displays: [])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("No reminders match the current filters."))
    }

    @Test
    func filteredRemindersListViewCaptionCarriesListAndPriority() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "ship it", priorityMarker: "!!", listName: "Work")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Work"))
        #expect(bodyDescription.contains("!!"))
    }

    @Test
    func filteredRemindersListViewOmitsAbsentCaptionParts() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "bare")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("bare"))
        #expect(!bodyDescription.contains(" · "), "a reminder with no list/date/priority gets no caption line")
    }
}
