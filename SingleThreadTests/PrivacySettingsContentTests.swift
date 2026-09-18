import Foundation
@testable import SingleThread
import SingleThreadCore
import Testing

@MainActor
struct PrivacySettingsContentTests {
    // MARK: Internal

    @Test
    func privacyGuideContentCoversAllDisclosures() {
        let sections = PrivacyGuideContent.sections(in: AppLanguage.english.locale)

        #expect(sections.count == 4)
        #expect(!PrivacyGuideContent.closingLine(in: AppLanguage.english.locale).isEmpty)

        for section in sections {
            #expect(!section.title.isEmpty)
            #expect(!section.body.isEmpty)
        }

        // The Unsplash proxy domain is a literal (never translated), so it marks the
        // background-disclosure section regardless of locale.
        #expect(sections.contains { $0.body.contains("vardy.cc") })
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        // The committed English copy is the canonical privacy commitment. Assert
        // the claims against the en-pinned lookup: the interface language now
        // pins resolution, so the closing line is independent of the host locale.
        let enClosing = String.en(
            "SingleThread has no analytics, no tracking, and no advertising.",
            bundle: .main)

        #expect(PrivacyGuideContent.closingLine(in: AppLanguage.english.locale) == enClosing)
        #expect(enClosing.contains("no analytics"))
        #expect(enClosing.contains("no tracking"))
        #expect(enClosing.contains("no advertising"))
        #expect(!PrivacyGuideContent.closingLine(in: AppLanguage.english.locale).isEmpty)
    }

    @Test
    func privacyGuideContentResolvesInEveryInterfaceLanguage() {
        for language in Self.interfaceLanguages {
            let sections = PrivacyGuideContent.sections(in: language.locale)
            let closingLine = PrivacyGuideContent.closingLine(in: language.locale)

            #expect(sections.count == 4, "\(language.rawValue) must resolve all four sections")
            #expect(!closingLine.isEmpty, "\(language.rawValue) closing line is empty")

            for section in sections {
                #expect(!section.title.isEmpty, "\(language.rawValue) \(section.id) title is empty")
                #expect(!section.body.isEmpty, "\(language.rawValue) \(section.id) body is empty")
            }
        }
    }

    @Test
    func privacyGuideContentNonEnglishValuesDifferFromEnglish() {
        let englishSections = PrivacyGuideContent.sections(in: AppLanguage.english.locale)
        let englishClosingLine = PrivacyGuideContent.closingLine(in: AppLanguage.english.locale)

        for language in Self.interfaceLanguages where language != .english {
            let sections = PrivacyGuideContent.sections(in: language.locale)

            for (index, section) in sections.enumerated() {
                #expect(
                    section.title != englishSections[index].title,
                    "\(language.rawValue) \(section.id) title is English-identity")
                #expect(
                    section.body != englishSections[index].body,
                    "\(language.rawValue) \(section.id) body is English-identity")
            }
            #expect(
                PrivacyGuideContent.closingLine(in: language.locale) != englishClosingLine,
                "\(language.rawValue) closing line is English-identity")
        }
    }

    // MARK: Private

    /// The six languages the `AppLanguage` picker offers (`.system` follows the
    /// device, so it is not an interface language).
    private static let interfaceLanguages = AppLanguage.allCases.filter { $0 != .system }
}
