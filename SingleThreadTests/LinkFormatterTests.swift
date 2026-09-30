import Foundation
import SingleThreadCore
import SwiftUI
import Testing

/// Every URL detected by `LinkFormatter.links(in:)`, returned as `URL` objects
/// so assertions can rely on canonical equality rather than string rendering.
func detected(in text: String) -> [URL] {
    LinkFormatter.links(in: text)
}

struct LinkFormatterTests {
    // MARK: Explicit schemes

    @Test
    func detectsExplicitHTTPAndHTTPSLinks() throws {
        let https = detected(in: "see https://apple.com")
        #expect(try https == [#require(URL(string: "https://apple.com"))], "https scheme detected")
        let http = detected(in: "visit http://example.org now")
        #expect(try http == [#require(URL(string: "http://example.org"))], "http scheme detected")
        let multiple = detected(in: "a https://x.com b http://y.com c")
        #expect(
            try multiple == [#require(URL(string: "https://x.com")), #require(URL(string: "http://y.com"))],
            "multiple links returned in document order")
    }

    // MARK: www. prefix

    @Test
    func normalisesWWWWithoutScheme() throws {
        let links = detected(in: "check www.example.com today")
        #expect(
            try links == [#require(URL(string: "https://www.example.com"))],
            "www. prefix gets an explicit https scheme")
    }

    // MARK: Case insensitivity

    @Test
    func schemeMatchingIsCaseInsensitive() throws {
        #expect(
            try detected(in: "HTTP://Example.com") == [#require(URL(string: "http://Example.com"))],
            "uppercase scheme still detected and normalised to lowercase")
    }

    @Test
    func requiresWordBoundaryBeforeBareWWW() throws {
        #expect(
            detected(in: "visitwww.example.com").isEmpty,
            "www. embedded in a word is not a link")
        #expect(
            try detected(in: "(www.example.com)") == [#require(URL(string: "https://www.example.com"))],
            "www. after a non-word character is linked")
    }

    // MARK: Non-links

    @Test
    func ignoresBareDomainsEmailsAndPhoneNumbers() {
        #expect(detected(in: "example.com").isEmpty, "bare domain is not a link")
        #expect(detected(in: "mail a@b.com me").isEmpty, "email address is not a link")
        #expect(detected(in: "call +1 555 0100 soon").isEmpty, "phone number is not a link")
    }

    @Test
    func malformedSchemeOnlyIsNotALink() {
        #expect(detected(in: "http://").isEmpty, "bare http:// is not a link")
        #expect(detected(in: "www.").isEmpty, "bare www. is not a link")
    }

    // MARK: Token termination

    @Test
    func stopsLinksAtNonURLCharacters() throws {
        #expect(
            try detected(in: "https://x.comを参照") == [#require(URL(string: "https://x.com"))],
            "token stops before a non-URL scalar (CJK)")
    }

    // MARK: Trailing punctuation

    @Test
    func stripsTrailingUnbalancedPunctuation() throws {
        let parens = detected(in: "(https://x.com)")
        #expect(
            try parens == [#require(URL(string: "https://x.com"))],
            "closing paren stripped when its opener is outside the token")
        let parensAndDot = detected(in: "https://x.com).")
        #expect(
            try parensAndDot == [#require(URL(string: "https://x.com"))],
            "closing paren and period both stripped")
    }

    @Test
    func keepsBalancedBracketPunctuation() throws {
        let balanced = detected(in: "see https://en.wikipedia.org/wiki/Foo_(bar) for info")
        #expect(
            try balanced == [#require(URL(string: "https://en.wikipedia.org/wiki/Foo_(bar)"))],
            "balanced bracket pair stays part of the link")
    }

    // MARK: Code spans

    @Test
    func doesNotLinkInsideCodeSpans() {
        #expect(detected(in: "`https://x.com`").isEmpty, "code span is never linked")
        let result = LinkFormatter.attributed("`https://x.com`")
        var codeStyling = false
        for run in result.runs where run.backgroundColor != nil {
            codeStyling = true
            break
        }
        #expect(codeStyling, "code styling is preserved in the attributed result")
    }

    // MARK: Attributes

    @Test
    func appliesLinkAttributeToLinkRunsOnly() {
        let result = LinkFormatter.attributed("see https://x.com now")
        var linkRuns = 0
        var plainRuns = 0
        for run in result.runs {
            let runText = String(result.characters[run.range])
            if run.link != nil {
                linkRuns += 1
                #expect(runText == "https://x.com", "link run is exactly the URL")
            } else {
                plainRuns += 1
            }
        }
        #expect(linkRuns == 1, "exactly one run carries the link attribute")
        #expect(plainRuns == 2, "surrounding plain runs carry no link attribute")
    }

    /// Mixed scheme + bare-www links return in document order — the order the
    /// accessibility custom-action list is derived from.
    @Test
    func linksReturnedInDocumentOrderAcrossScopes() {
        let links = LinkFormatter.links(in: "a https://one.com b www.two.com")
        #expect(
            links.map(\.absoluteString)
                == ["https://one.com", "https://www.two.com"],
            "link list preserves document order")
    }
}
