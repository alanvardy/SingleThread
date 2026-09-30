import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Detects `http(s)://` and `www.`-prefixed links in plain text and builds the
/// link-styled `AttributedString`. Backtick code spans keep code styling and
/// are never linked.
public nonisolated enum LinkFormatter {
    // MARK: Public

    /// Text with code spans styled and URLs carrying a `.link` attribute plus
    /// explicit accent foreground (no underline), so notes stay deterministic
    /// under `.foregroundStyle(.secondary)`.
    public static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for segment in CodeSpanFormatter.segments(in: text) {
            switch segment {
            case let .code(content):
                var code = AttributedString(content)
                CodeSpanFormatter.applyCodeAttributes(to: &code)
                result.append(code)
            case let .plain(plain):
                result.append(plainAttributed(plain))
            }
        }
        return result
    }

    /// Normalised URLs in document order — drives the accessibility custom actions.
    public static func links(in text: String) -> [URL] {
        var links: [URL] = []
        for segment in CodeSpanFormatter.segments(in: text) {
            switch segment {
            case .code:
                continue
            case let .plain(plain):
                links.append(contentsOf: detect(in: plain).map(\.url))
            }
        }
        return links
    }

    // MARK: Private

    private struct DetectedLink {
        let range: Range<String.Index>
        let url: URL
    }

    /// RFC 3986 unreserved + reserved + `%`. Any other scalar (whitespace, CJK,
    /// quotes) terminates the token.
    private static let urlCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")

    private static let prefixCandidates = ["http://", "https://", "www."]

    private static let alwaysTrimmed: Set<Character> = [".", ",", ";", ":", "!", "?"]
    private static let bracketPairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    private static let wordScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private static func detect(in plain: String) -> [DetectedLink] {
        var links: [DetectedLink] = []
        var searchStart = plain.startIndex
        while searchStart < plain.endIndex {
            guard let candidate = nextPrefix(in: plain, from: searchStart) else { break }
            var tokenEnd = candidate.start
            while tokenEnd < plain.endIndex,
                  let scalar = plain[tokenEnd].unicodeScalars.first,
                  urlCharacters.contains(scalar) {
                tokenEnd = plain.index(after: tokenEnd)
            }
            let token = String(plain[candidate.start ..< tokenEnd])
            let trimmed = trimTrailingPunctuation(token)
            if let url = normalise(trimmed, prefixedWithWWW: candidate.isWWW) {
                let end = plain.index(candidate.start, offsetBy: trimmed.count)
                links.append(DetectedLink(range: candidate.start ..< end, url: url))
            }
            searchStart = tokenEnd
        }
        return links
    }

    /// Earliest `http://` / `https://` / `www.` at or after `start`, case-insensitive.
    private static func nextPrefix(
        in plain: String,
        from start: String.Index) -> (start: String.Index, isWWW: Bool)? {
        var best: (start: String.Index, isWWW: Bool)?
        for prefix in prefixCandidates {
            let isWWW = prefix == "www."
            var searchStart = start
            while let range = plain.range(
                of: prefix, options: .caseInsensitive, range: searchStart ..< plain.endIndex) {
                if isWWW, !isTokenBoundary(in: plain, at: range.lowerBound) {
                    searchStart = range.upperBound
                    continue
                }
                if let best, range.lowerBound >= best.start {
                    break
                }
                best = (range.lowerBound, isWWW)
                break
            }
        }
        return best
    }

    /// True when the character before `index` is absent or not a word scalar, so
    /// a bare `www.` candidate starts a fresh token (`See www.x.com` links;
    /// `visitwww.x.com` does not).
    private static func isTokenBoundary(in plain: String, at index: String.Index) -> Bool {
        guard index > plain.startIndex else { return true }
        let previous = plain[plain.index(before: index)]
        return previous.unicodeScalars.allSatisfy {
            !wordScalars.contains($0)
        }
    }

    private static func normalise(_ token: String, prefixedWithWWW: Bool) -> URL? {
        if prefixedWithWWW {
            guard token.count > 4 else { return nil } // "www." + ≥1 char
            return URL(string: "https://" + token)
        }
        guard let schemeEnd = token.range(of: "://") else { return nil }
        let scheme = token[..<schemeEnd.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        let rest = token[schemeEnd.lowerBound...]
        guard rest.count > 3 else { return nil } // "://" + ≥1 char
        return URL(string: scheme + rest)
    }

    /// Drops trailing `.,;:!?` always, and `)]}` only when its opening bracket
    /// is outnumbered inside the token (keeps `…/Foo_(bar)`).
    private static func trimTrailingPunctuation(_ token: String) -> String {
        var characters = Array(token)
        while let last = characters.last {
            if alwaysTrimmed.contains(last) {
                characters.removeLast()
                continue
            }
            if let opener = bracketPairs[last],
               characters.filter({ $0 == opener }).count < characters.filter({ $0 == last }).count {
                characters.removeLast()
                continue
            }
            break
        }
        return String(characters)
    }

    private static func plainAttributed(_ plain: String) -> AttributedString {
        var result = AttributedString()
        var cursor = plain.startIndex
        for link in detect(in: plain) {
            if cursor < link.range.lowerBound {
                result.append(AttributedString(String(plain[cursor ..< link.range.lowerBound])))
            }
            var run = AttributedString(String(plain[link.range]))
            run.link = link.url
            #if canImport(SwiftUI)
                run.foregroundColor = .accentColor
                run.underlineStyle = nil
            #endif
            result.append(run)
            cursor = link.range.upperBound
        }
        if cursor < plain.endIndex {
            result.append(AttributedString(String(plain[cursor...])))
        }
        return result
    }
}
