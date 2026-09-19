@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Reminder Display Row Tests

@MainActor
struct ReminderDisplayRowTests {
    @Test
    func captionCarriesListAndPriority() {
        let caption = ReminderDisplayRow.captionText(
            for: ReminderDisplay(title: "ship it", priorityMarker: "!!", listName: "Work"))

        #expect(caption.contains("Work"))
        #expect(caption.contains("!!"))
    }

    @Test
    func captionCarriesDueDate() {
        let caption = ReminderDisplayRow.captionText(
            for: ReminderDisplay(title: "ship it", dueDate: Date(timeIntervalSince1970: 0)))

        #expect(!caption.isEmpty)
    }

    @Test
    func captionOmitsAbsentParts() {
        let caption = ReminderDisplayRow.captionText(for: ReminderDisplay(title: "bare"))

        #expect(caption.isEmpty)
    }

    @Test
    func rowRendersItsTitle() {
        let view = ReminderDisplayRow(
            display: ReminderDisplay(title: "call the dentist"),
            font: .caption2)

        #expect(String(describing: view.body).contains("call the dentist"))
    }
}
