import SingleThreadCore
import Testing

// MARK: - WatchReminderPresentation

struct WatchReminderPresentationTests {
    // MARK: Default state

    @Test
    func startsCollapsed() {
        let presentation = WatchReminderPresentation()
        #expect(!presentation.isExpanded)
        #expect(presentation.allowsCrownRefresh)
    }

    // MARK: Toggle

    @Test
    func toggleExpandsAndDisablesCrownRefresh() {
        var presentation = WatchReminderPresentation()
        presentation.toggle()
        #expect(presentation.isExpanded)
        #expect(!presentation.allowsCrownRefresh)
    }

    @Test
    func togglingTwiceReturnsToCollapsed() {
        var presentation = WatchReminderPresentation()
        presentation.toggle()
        presentation.toggle()
        #expect(!presentation.isExpanded)
        #expect(presentation.allowsCrownRefresh)
    }
}
