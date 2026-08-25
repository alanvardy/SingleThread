@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowAlarmsTests {
    // MARK: Internal

    @Test
    func alarmsRowShownWhenEnabledAndHasAlarms() {
        let description = String(describing: makeCard(showAlarms: true, hasAlarms: true).body)
        // `Image(systemName:)` renders as NamedImageProvider and never prints the
        // symbol name. The card's only image (with no reminder data) is the bell,
        // so NamedImageProvider is a positive marker for an installed image.
        #expect(description.contains("NamedImageProvider"))
    }

    @Test
    func alarmsRowHiddenWhenDisabled() {
        let description = String(describing: makeCard(showAlarms: false, hasAlarms: true).body)
        #expect(!description.contains("NamedImageProvider"))
    }

    @Test
    func alarmsRowHiddenWhenNoAlarms() {
        let description = String(describing: makeCard(showAlarms: true, hasAlarms: false).body)
        #expect(!description.contains("NamedImageProvider"))
    }

    // MARK: Private

    private func makeCard(showAlarms: Bool, hasAlarms: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(title: "Buy groceries", hasAlarms: hasAlarms),
            showDate: true,
            showAlarms: showAlarms)
    }
}
