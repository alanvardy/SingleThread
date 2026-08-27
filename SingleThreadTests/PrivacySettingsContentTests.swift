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

        let allText = (sections.map(\.body) + [PrivacyGuideContent.closingLine])
            .joined(separator: " ")

        #expect(allText.contains("vardy.cc"))
        #expect(allText.contains("Apple Watch"))
        #expect(allText.contains("never sent"))
        #expect(allText.contains("iCloud"))
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        let closing = PrivacyGuideContent.closingLine

        #expect(closing.contains("no analytics"))
        #expect(closing.contains("no tracking"))
        #expect(closing.contains("no advertising"))
    }
}
