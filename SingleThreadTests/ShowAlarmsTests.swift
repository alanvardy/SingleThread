@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct ShowAlarmsTests {
    // MARK: Internal

    @Test
    func alarmsRowFollowsPreferenceAndData() {
        let shown = String(describing: makeCard(showAlarms: true, hasAlarms: true).body)
        // `Image(systemName:)` renders as NamedImageProvider and never prints the
        // symbol name. The card's only image (with no reminder data) is the bell,
        // so NamedImageProvider is a positive marker for an installed image.
        #expect(shown.contains("NamedImageProvider"), "alarm row shown when enabled and alarms present")
        let disabled = String(describing: makeCard(showAlarms: false, hasAlarms: true).body)
        #expect(!disabled.contains("NamedImageProvider"), "alarm row hidden when showAlarms disabled")
        let none = String(describing: makeCard(showAlarms: true, hasAlarms: false).body)
        #expect(!none.contains("NamedImageProvider"), "alarm row hidden when no alarms")
    }

    // MARK: Private

    private func makeCard(showAlarms: Bool, hasAlarms: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(title: "Buy groceries", hasAlarms: hasAlarms),
            showDate: true,
            showAlarms: showAlarms)
    }
}
