@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowDateTests {
    // MARK: Internal

    @Test
    func dateAndListRowsFollowPreferences() {
        let noDate = String(describing: makeCard(showDate: false).body)
        #expect(
            !noDate.contains("FormatStyleStorage"),
            "date row hidden when showDate disabled")
        let withDate = String(describing: makeCard(showDate: true).body)
        #expect(
            withDate.contains("FormatStyleStorage"),
            "date row shown when showDate enabled")

        let listShown = String(describing: makeCard(showDate: true, showList: true, listName: "Groceries").body)
        #expect(listShown.contains("Groceries"), "list row shown when showList enabled and list named")
        let listHidden = String(describing: makeCard(showDate: true, showList: false, listName: "Groceries").body)
        #expect(!listHidden.contains("Groceries"), "list row hidden when showList disabled")
        let nilName = String(describing: makeCard(showDate: true, showList: true, listName: nil).body)
        let named = String(describing: makeCard(showDate: true, showList: true, listName: "Errands").body)
        #expect(named.contains("Errands"), "named card renders the list row")
        #expect(!nilName.contains("Errands"), "nil list name hides the list row")
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
