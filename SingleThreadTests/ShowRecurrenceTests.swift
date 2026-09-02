@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowRecurrenceTests {
    // MARK: Internal

    @Test
    func recurrenceRowFollowsPreferenceAndData() {
        let shown = String(describing: makeCard(showRecurrence: true, hasRecurrence: true).body)
        // The row's only text node carries the formatted summary, which the body
        // description surfaces. `Image(systemName:)` boxes as NamedImageProvider
        // and never prints the symbol name, so assert on the summary instead.
        #expect(shown.contains("Weekly"), "recurrence row shown when enabled and recurrence present")
        let disabled = String(describing: makeCard(showRecurrence: false, hasRecurrence: true).body)
        #expect(!disabled.contains("Weekly"), "recurrence row hidden when showRecurrence disabled")
        let none = String(describing: makeCard(showRecurrence: true, hasRecurrence: false).body)
        #expect(!none.contains("Weekly"), "recurrence row hidden when no recurrence")
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
