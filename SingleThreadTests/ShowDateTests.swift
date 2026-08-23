@testable import SingleThread
import SingleThreadCore
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

    @Test
    func listRowShownWhenShowListEnabledAndListNamePresent() {
        let description = String(describing: makeCard(showDate: true, showList: true, listName: "Groceries").body)
        #expect(description.contains("Groceries"))
    }

    @Test
    func listRowHiddenWhenShowListDisabled() {
        let description = String(describing: makeCard(showDate: true, showList: false, listName: "Groceries").body)
        #expect(!description.contains("Groceries"))
    }

    @Test
    func listRowHiddenWhenListNameNil() {
        let nilName = String(describing: makeCard(showDate: true, showList: true, listName: nil).body)
        let named = String(describing: makeCard(showDate: true, showList: true, listName: "Errands").body)
        #expect(named.contains("Errands"))
        #expect(!nilName.contains("Errands"))
    }

    // MARK: Private

    private func makeCard(showDate: Bool, showList: Bool = false, listName: String? = nil)
        -> ReminderCardView {
        let dueDate = Calendar.current.date(from: DateComponents(year: 2024, month: 9, day: 15))
        return ReminderCardView(
            display: ReminderDisplay(
                title: "Buy groceries",
                dueDate: dueDate,
                listName: listName),
            showDate: showDate,
            showList: showList)
    }
}
