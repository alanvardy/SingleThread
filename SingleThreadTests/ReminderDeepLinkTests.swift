import Foundation
import SingleThreadCore
import Testing

struct ReminderDeepLinkTests {
    @Test
    func urlReturnsNilForEmptyIdentifier() {
        #expect(ReminderDeepLink.url(forReminderIdentifier: "") == nil)
    }

    @Test
    func urlReturnsCorrectScheme() {
        let url = ReminderDeepLink.url(forReminderIdentifier: "some-id")
        #expect(url != nil)
        #expect(url?.scheme == "x-apple-reminderkit")
    }

    @Test
    func urlEmbedsIdentifierInPath() {
        let identifier = "E0B6FFFB-F794-4E6C-8B58-ABD123456789"
        let url = ReminderDeepLink.url(forReminderIdentifier: identifier)
        #expect(url?.absoluteString == "x-apple-reminderkit://REMCDReminder/\(identifier)")
    }
}
