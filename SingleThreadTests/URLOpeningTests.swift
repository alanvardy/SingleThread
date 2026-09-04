@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct URLOpeningTests {
    @Test
    func spyRecordsOpenedURL() throws {
        let spy = URLOpeningSpy()
        let url = try #require(URL(string: "x-apple-reminderkit://REMCDReminder/test"))
        spy.open(url)
        #expect(spy.lastOpenedURL?.absoluteString == "x-apple-reminderkit://REMCDReminder/test")
    }

    @Test
    func spyAccumulatesMultipleOpens() throws {
        let spy = URLOpeningSpy()
        try spy.open(#require(URL(string: "a://1")))
        try spy.open(#require(URL(string: "a://2")))
        #expect(spy.openedURLs.count == 2)
    }

    @Test
    func systemURLOpenerForwards() throws {
        let flag = URLFlag()
        let action = OpenURLAction { url in
            flag.opened = true
            flag.url = url
            return .handled
        }
        let opener = SystemURLOpener(action: action)
        let url = try #require(URL(string: "x-apple-reminderkit://REMCDReminder/E0B6FFFB"))
        opener.open(url)
        #expect(flag.opened)
        #expect(flag.url?.absoluteString == "x-apple-reminderkit://REMCDReminder/E0B6FFFB")
    }
}

/// Tiny `@MainActor` holder so the synchronous `OpenURLAction` handler can
/// record the forwarded URL. Reference-type holder is safe because the handler
/// runs synchronously on `@MainActor`.
@MainActor
private final class URLFlag {
    var opened = false
    var url: URL?
}
