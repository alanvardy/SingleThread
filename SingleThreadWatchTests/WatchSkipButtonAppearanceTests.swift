import SingleThreadCore
@testable import SingleThreadWatch
import Testing

struct WatchSkipButtonAppearanceTests {
    @Test
    func actionMenuOpenShowsEllipsisAndMoreLabel() {
        #expect(WatchSkipButtonAppearance.systemImage(opensActionMenu: true) == "ellipsis.circle.fill")
        #expect(WatchSkipButtonAppearance.accessibilityLabel(opensActionMenu: true) == SharedStrings.moreAction)
    }

    @Test
    func directSkipShowsSlashAndSkipReminderLabel() {
        #expect(WatchSkipButtonAppearance.systemImage(opensActionMenu: false) == "circle.slash")
        #expect(WatchSkipButtonAppearance.accessibilityLabel(opensActionMenu: false) == SharedStrings.skipReminderAccessibility)
    }
}
