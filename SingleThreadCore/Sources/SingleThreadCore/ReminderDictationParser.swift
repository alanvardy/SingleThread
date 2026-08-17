import Foundation

// MARK: - ReminderDictationParser

/// Natural-language date detection for dictated reminder text.
/// Uses `NSDataDetector` to extract date expressions like "today",
/// "tomorrow", "next Monday", or "at 5pm", and strips them from the
/// title so the reminder title reads cleanly.
public enum ReminderDictationParser {
    // MARK: Public

    /// Outcome of parsing a dictated string.
    public struct Result {
        /// The title with the matched date phrase removed (or the original text if none found).
        public let title: String
        /// The matched date as `DateComponents`, suitable for `EKReminder.dueDateComponents`.
        public let dueDateComponents: DateComponents?
    }

    /// Extracts a natural-language date from the given text and returns a
    /// cleaned title along with the parsed date components.
    ///
    /// If multiple date expressions are found, the first one wins. If none
    /// are found, `dueDateComponents` is `nil` and the title is returned as-is.
    ///
    /// When the matched date phrase contains no time-of-day specification
    /// (e.g. "today", "tomorrow", "next Monday"), only year/month/day are
    /// extracted so the reminder behaves as an all-day item. When the
    /// phrase does include a time (e.g. "9am", "noon", "this evening",
    /// "at 5pm"), hour and minute are included as well.
    public static func parse(
        _ text: String,
        calendar: Calendar = .current) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = firstDateMatch(in: trimmed) else {
            return Result(title: trimmed, dueDateComponents: nil)
        }

        let hasTime = hasTimeSpecification(in: trimmed, range: match.range)
        let dateComponents: DateComponents = if hasTime {
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: match.date)
        } else {
            calendar.dateComponents(
                [.year, .month, .day],
                from: match.date)
        }

        let cleanedTitle = stripMatch(trimmed, range: match.range)
        return Result(title: cleanedTitle, dueDateComponents: dateComponents)
    }

    // MARK: Private

    private static let connectors: Set<String> = ["at", "on", "by"]

    private static let dateDetector: NSDataDetector = // swiftlint:disable:next force_try
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static func firstDateMatch(in text: String) -> (range: NSRange, date: Date)? {
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = dateDetector.matches(in: text, options: [], range: fullRange)
        guard let first = matches.first, let date = first.date else { return nil }
        return (range: first.range, date: date)
    }

    /// Returns whether the matched date phrase contains a time-of-day
    /// specification — a numeric time like "9am" / "5:30 pm", a named time
    /// like "noon" or "midnight", or an implied time-of-day word like
    /// "morning", "afternoon", "evening", or "tonight".
    private static func hasTimeSpecification(in text: String, range: NSRange) -> Bool {
        guard let swiftRange = Range(range, in: text) else { return false }
        let matched = String(text[swiftRange])

        // Numeric time with am/pm: "9am", "5:30pm", "5 p.m."
        let ampmPattern = /\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)/.ignoresCase()
        if matched.contains(ampmPattern) {
            return true
        }

        // 24-hour minute-precision: "14:30", "9:15"
        let hourMinutePattern = /\d{1,2}:\d{2}/
        if matched.contains(hourMinutePattern) {
            return true
        }

        // Named time markers and time-of-day words
        let timeWords: Set = [
            "noon", "midnight",
            "morning", "afternoon", "evening", "tonight"
        ]
        let words = matched.lowercased().split(whereSeparator: \.isWhitespace)
        for word in words where timeWords.contains(String(word)) {
            return true
        }

        return false
    }

    /// Removes the matched date phrase and cleans up the remainder:
    /// collapses whitespace and drops a dangling connector word ("at", "on",
    /// "by") left behind when a bare time was matched.
    private static func stripMatch(_ text: String, range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var result = text
        result.removeSubrange(swiftRange)

        var words = result.split(whereSeparator: \.isWhitespace)
        if let last = words.last, connectors.contains(last.lowercased()) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}
