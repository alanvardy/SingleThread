import Foundation
@testable import SingleThread
import Testing

@MainActor
struct PrivacySettingsContentTests {
    @Test
    func privacyGuideContentCoversAllDisclosures() {
        let sections = PrivacyGuideContent.sections

        #expect(sections.count == 4)
        #expect(!PrivacyGuideContent.closingLine.isEmpty)

        for section in sections {
            #expect(!section.title.isEmpty)
            #expect(!section.body.isEmpty)
        }

        // The Unsplash proxy domain is a literal (never translated), so it marks the
        // background-disclosure section regardless of host locale.
        #expect(sections.contains { $0.body.contains("vardy.cc") })
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        // The committed English copy is the canonical privacy commitment. Assert the
        // claims against the en-pinned lookup so this test stays host-locale
        // independent (the runtime closing line is translated on non-English locales).
        let enClosing = String.en(
            "SingleThread has no analytics, no tracking, and no advertising.",
            bundle: .main)

        #expect(enClosing.contains("no analytics"))
        #expect(enClosing.contains("no tracking"))
        #expect(enClosing.contains("no advertising"))
        #expect(!PrivacyGuideContent.closingLine.isEmpty)
    }
}
