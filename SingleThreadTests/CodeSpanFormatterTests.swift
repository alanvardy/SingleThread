import Foundation
import SingleThreadCore
import SwiftUI
import Testing

struct CodeSpanFormatterTests {
    // MARK: Empty / plain

    @Test
    func emptyStringReturnsEmptyAttributedString() {
        let result = CodeSpanFormatter.format("")
        #expect(result.characters.isEmpty)
    }

    @Test
    func plainTextReturnsUnstyledAttributedString() {
        let result = CodeSpanFormatter.format("Buy groceries")
        #expect(String(result.characters[...]) == "Buy groceries")
    }

    // MARK: Inline code

    @Test
    func inlineCodeStripsBackticks() {
        let result = CodeSpanFormatter.format("Use `map` here")
        #expect(String(result.characters[...]) == "Use map here")
    }

    @Test
    func singleInlineCodeOnly() {
        let result = CodeSpanFormatter.format("`code`")
        #expect(String(result.characters[...]) == "code")
    }

    // MARK: Fenced code

    @Test
    func fencedCodeStripsFences() {
        let result = CodeSpanFormatter.format("Before\n```\nlet x = 1\n```\nAfter")
        let text = String(result.characters[...])
        #expect(text.contains("let x = 1"))
        #expect(!text.contains("```"))
    }

    @Test
    func fencedCodeOnly() {
        let result = CodeSpanFormatter.format("```\ncode\n```")
        let text = String(result.characters[...])
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == "code")
    }

    // MARK: Multiple spans

    @Test
    func multipleCodeSpansInOneString() {
        let result = CodeSpanFormatter.format("Use `map` and `filter`")
        #expect(String(result.characters[...]) == "Use map and filter")
    }

    // MARK: Unmatched backticks

    @Test
    func unmatchedSingleBacktickRendersLiterally() {
        let result = CodeSpanFormatter.format("a ` b")
        #expect(String(result.characters[...]) == "a ` b")
    }

    @Test
    func doubleBacktickRendersLiterally() {
        // Two backticks is not a valid delimiter per the simple parsing rules.
        let result = CodeSpanFormatter.format("a `` b")
        #expect(String(result.characters[...]) == "a `` b")
    }

    @Test
    func unmatchedTripleFenceRendersRestAsCode() {
        // No closing fence: rest of string is code content, fences stripped.
        let result = CodeSpanFormatter.format("```\nunclosed")
        let text = String(result.characters[...])
        #expect(!text.contains("```"))
        #expect(text.contains("unclosed"))
    }

    // MARK: Boundaries

    @Test
    func backtickAtStartOfString() {
        let result = CodeSpanFormatter.format("`start` and end")
        #expect(String(result.characters[...]) == "start and end")
    }

    @Test
    func backtickAtEndOfString() {
        let result = CodeSpanFormatter.format("start and `end`")
        #expect(String(result.characters[...]) == "start and end")
    }

    // MARK: Nested / sequences

    @Test
    func fencedBlockWithInnerBackticksRenderedLiterally() {
        // Inner backticks inside a fenced block are treated literally —
        // no nesting recursion.
        let result = CodeSpanFormatter.format("```\ncode `x` more\n```")
        let text = String(result.characters[...])
        #expect(text.contains("code `x` more"))
        #expect(!text.contains("```"))
    }

    @Test
    func multipleSpansWithPlainTextBetween() {
        // Plain text between code spans is preserved in correct order.
        let result = CodeSpanFormatter.format("a `x` b `y` c")
        #expect(String(result.characters[...]) == "a x b y c")
    }

    // MARK: Attributes

    @Test
    func codeSpanHasBackgroundAttribute() {
        let result = CodeSpanFormatter.format("`code`")
        var foundBackground = false
        for run in result.runs where run.backgroundColor != nil {
            foundBackground = true
            break
        }
        #expect(foundBackground, "Code span should carry a background color attribute")
    }

    @Test
    func plainTextHasNoCodeAttributes() {
        let result = CodeSpanFormatter.format("plain `code` plain")
        // The plain runs should not have background color.
        for run in result.runs {
            let runText = String(result.characters[run.range])
            if runText == "plain " || runText == " plain" {
                #expect(run.backgroundColor == nil, "Plain text run should not have background color")
            }
        }
    }
}
