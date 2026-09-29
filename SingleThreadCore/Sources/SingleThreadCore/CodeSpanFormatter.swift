import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Parses backtick-delimited text into `AttributedString` with subtle
/// background styling on code spans. Follows the same caseless-enum
/// pattern as `ReminderNotesFormatter`.
public nonisolated enum CodeSpanFormatter {
    // MARK: Public

    /// A single plain or backtick-delimited code span within a formatted
    /// string. Fences are stripped from `code` content; unmatched and double
    /// backticks remain literal text inside a `plain` segment.
    public enum Segment: Equatable, Sendable {
        case plain(String)
        case code(String)
    }

    /// Splits `text` into plain and backtick-delimited code segments.
    /// Fences are stripped; unmatched/double backticks stay literal plain text.
    public static func segments(in text: String) -> [Segment] {
        var segments: [Segment] = []
        var remainder = text[...]
        var pendingPlain = ""

        while !remainder.isEmpty {
            // Locate the next backtick anywhere in the remainder, so code
            // spans are found even when plain text precedes them.
            guard let nextFence = remainder.firstIndex(of: "`") else {
                // No more backticks: the rest is plain text.
                pendingPlain.append(contentsOf: remainder)
                break
            }

            // Flush the plain text leading up to this candidate fence.
            pendingPlain.append(contentsOf: remainder[..<nextFence])
            remainder = remainder[nextFence...]

            guard let codeSpan = extractCodeSpan(from: remainder) else {
                // Not a valid opener (e.g. double backtick or an unmatched
                // single backtick) — treat this backtick as literal text.
                pendingPlain.append("`")
                remainder = remainder.dropFirst()
                continue
            }

            if !pendingPlain.isEmpty {
                segments.append(.plain(pendingPlain))
                pendingPlain = ""
            }
            segments.append(.code(codeSpan.content))
            remainder = codeSpan.remainder
        }

        if !pendingPlain.isEmpty {
            segments.append(.plain(pendingPlain))
        }
        return segments
    }

    /// Returns an `AttributedString` where backtick-delimited spans are
    /// styled with a subtle background color; backtick fences are stripped
    /// from visible text.
    ///
    /// - Single backtick pairs `` `code` `` render as inline code.
    /// - Triple-backtick pairs ```` ```block``` ```` render as fenced code.
    /// - Unmatched single backticks render as literal text.
    /// - Unclosed fenced blocks (no closing ```) consume the remainder as
    ///   code content.
    public static func format(_ text: String) -> AttributedString {
        var result = AttributedString()
        for segment in segments(in: text) {
            switch segment {
            case let .plain(plain):
                result.append(AttributedString(plain))
            case let .code(content):
                var code = AttributedString(content)
                applyCodeAttributes(to: &code)
                result.append(code)
            }
        }
        return result
    }

    // MARK: Internal

    static func applyCodeAttributes(to attributed: inout AttributedString) {
        #if canImport(SwiftUI)
            // Subtle background using a platform-adaptive secondary system
            // background color. Falls back to gray opacity on platforms where
            // `secondarySystemBackground` is not available.
            //
            // Note: background styling requires SwiftUI. On platforms without
            // SwiftUI, code spans are fence-stripped but unstyled. A font is
            // intentionally not set here — code-span runs inherit the view-level
            // `.font()` modifier so sizing stays consistent with surrounding text.
            if let bgColor = platformSecondaryBackground() {
                attributed.backgroundColor = bgColor
            }
        #endif
    }

    // MARK: Private

    private struct CodeSpan {
        let content: String // backtick fences removed
        let remainder: Substring
    }

    /// Attempts to extract a code span from the start of `text`.
    /// Returns nil when no valid opening fence is found.
    private static func extractCodeSpan(from text: Substring) -> CodeSpan? {
        // Try triple-backtick fenced first (longest match).
        if let span = extractFenced(from: text) {
            return span
        }
        // Then single-backtick inline.
        if let span = extractInline(from: text) {
            return span
        }
        return nil
    }

    private static func extractFenced(from text: Substring) -> CodeSpan? {
        guard text.hasPrefix("```") else { return nil }
        let afterOpen = text.dropFirst(3)

        // Find the closing ``` anywhere in the remaining text.
        guard let closeRange = afterOpen.range(of: "```") else {
            // No closing fence: rest of string is code content.
            return CodeSpan(
                content: String(afterOpen),
                remainder: "")
        }

        let content = String(afterOpen[..<closeRange.lowerBound])
        let remainder = afterOpen[closeRange.upperBound...]
        return CodeSpan(content: content, remainder: remainder)
    }

    private static func extractInline(from text: Substring) -> CodeSpan? {
        guard text.hasPrefix("`") else { return nil }
        let afterOpen = text.dropFirst()

        // Double backtick (``) is not a valid inline opener — skip so the
        // literal backtick falls through as plain text. Triple backtick is
        // already handled by extractFenced (runs first).
        guard afterOpen.first != "`" else { return nil }

        guard let closeIdx = afterOpen.firstIndex(of: "`") else {
            // Unmatched: render literally (handled by caller skipping this span).
            return nil
        }

        let content = String(afterOpen[..<closeIdx])
        let remainder = afterOpen[afterOpen.index(after: closeIdx)...]
        return CodeSpan(content: content, remainder: remainder)
    }

    #if canImport(SwiftUI)
        private static func platformSecondaryBackground() -> SwiftUI.Color? {
            #if os(watchOS)
                // `.secondarySystemBackground` is unavailable on watchOS; use a subtle
                // gray overlay rather than a system background color.
                return SwiftUI.Color.gray.opacity(0.15)
            #elseif canImport(UIKit)
                // UIColor.secondarySystemBackground is available iOS 13+.
                return SwiftUI.Color(uiColor: .secondarySystemBackground)
            #elseif canImport(AppKit)
                // macOS has no `.secondarySystemBackground`; use the page background.
                return SwiftUI.Color(nsColor: .underPageBackgroundColor)
            #else
                // Fallback for platforms without UIKit/AppKit (unlikely but safe).
                return SwiftUI.Color.gray.opacity(0.15)
            #endif
        }
    #endif
}
