@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowRecurrenceTests {
    // MARK: Internal

    @Test
    func recurrenceRowShownWhenEnabledAndHasRecurrence() {
        let description = String(describing: makeCard(showRecurrence: true, hasRecurrence: true).body)
        // The row's only text node carries the formatted summary, which the body
        // description surfaces. `Image(systemName:)` boxes as NamedImageProvider
        // and never prints the symbol name, so assert on the summary instead.
        #expect(description.contains("Weekly"))
    }

    @Test
    func recurrenceRowHiddenWhenDisabled() {
        let description = String(describing: makeCard(showRecurrence: false, hasRecurrence: true).body)
        #expect(!description.contains("Weekly"))
    }

    @Test
    func recurrenceRowHiddenWhenNoRecurrence() {
        let description = String(describing: makeCard(showRecurrence: true, hasRecurrence: false).body)
        #expect(!description.contains("Weekly"))
    }

    // MARK: Private

    private func makeCard(showRecurrence: Bool, hasRecurrence: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(
                title: "Buy groceries",
                hasRecurrence: hasRecurrence,
                recurrenceSummary: hasRecurrence ? "Weekly" : nil),
            showDate: true,
            showRecurrence: showRecurrence)
    }
}
