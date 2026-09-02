import Foundation
import SingleThreadCore
import SwiftUI
import Testing

struct CodeSpanFormatterTests {
    // MARK: Empty / plain

    @Test
    func emptyAndPlainText() {
        let empty = CodeSpanFormatter.format("")
        #expect(empty.characters.isEmpty, "empty input → empty attributed string")
        let plain = CodeSpanFormatter.format("Buy groceries")
        #expect(
            String(plain.characters[...]) == "Buy groceries",
            "plain text passes through unchanged")
    }

    // MARK: Inline code

    @Test(arguments: [
        ("Use `map` here", "Use map here"),
        ("`code`", "code"),
        ("Use `map` and `filter`", "Use map and filter"),
        ("`start` and end", "start and end"),
        ("start and `end`", "start and end"),
        ("a `x` b `y` c", "a x b y c")
    ])
    func inlineCodeStripsBackticks(_ pair: (input: String, expected: String)) {
        let result = CodeSpanFormatter.format(pair.input)
        #expect(String(result.characters[...]) == pair.expected, "\(pair.input) → \(pair.expected)")
    }

    // MARK: Fenced code

    @Test
    func fencedAndUnclosedFencesStripFencesKeepContent() {
        let fenced = CodeSpanFormatter.format("Before\n```\nlet x = 1\n```\nAfter")
        let fencedText = String(fenced.characters[...])
        #expect(fencedText.contains("let x = 1"), "fenced content preserved")
        #expect(!fencedText.contains("```"), "fences stripped")
        let only = CodeSpanFormatter.format("```\ncode\n```")
        #expect(
            String(only.characters[...]).trimmingCharacters(in: .whitespacesAndNewlines) == "code",
            "fenced-only block reduces to its content")
        let nested = CodeSpanFormatter.format("```\ncode `x` more\n```")
        let nestedText = String(nested.characters[...])
        #expect(nestedText.contains("code `x` more"), "inner backticks rendered literally")
        #expect(!nestedText.contains("```"), "outer fences still stripped")
        let unclosed = CodeSpanFormatter.format("```\nunclosed")
        let unclosedText = String(unclosed.characters[...])
        #expect(unclosedText.contains("unclosed"), "unclosed remainder treated as code content")
        #expect(!unclosedText.contains("```"), "unclosed opening fence still stripped")
    }

    // MARK: Unmatched backticks

    @Test(arguments: [
        ("a ` b", "a ` b"),
        ("a `` b", "a `` b")
    ])
    func unmatchedBackticksRenderLiterally(_ pair: (input: String, expected: String)) {
        let result = CodeSpanFormatter.format(pair.input)
        #expect(String(result.characters[...]) == pair.expected, "\(pair.input) renders literally")
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
