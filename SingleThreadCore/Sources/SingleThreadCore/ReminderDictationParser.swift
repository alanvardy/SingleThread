import EventKit
import Foundation

// MARK: - ReminderDictationParser

/// Natural-language date and recurrence detection for dictated reminder text.
/// Uses `NSDataDetector` to extract date expressions like "today",
/// "tomorrow", "next Monday", or "at 5pm", and strips them from the
/// title so the reminder title reads cleanly.
///
/// Also detects recurrence phrases like "every week", "every Monday",
/// "daily", "every 2 weeks", etc., and returns an `EKRecurrenceRule`
/// suitable for `EKReminder.recurrenceRules`.
public enum ReminderDictationParser {
    // MARK: Public

    /// Outcome of parsing a dictated string.
    public struct Result {
        // MARK: Lifecycle

        public init(
            title: String,
            dueDateComponents: DateComponents? = nil,
            recurrenceRule: EKRecurrenceRule? = nil) {
            self.title = title
            self.dueDateComponents = dueDateComponents
            self.recurrenceRule = recurrenceRule
        }

        // MARK: Public

        /// The title with the matched date phrase removed (or the original text if none found).
        public let title: String
        /// The matched date as `DateComponents`, suitable for `EKReminder.dueDateComponents`.
        public let dueDateComponents: DateComponents?
        /// A recurrence rule extracted from the text, suitable for `EKReminder.addRecurrenceRule(_:)`.
        public let recurrenceRule: EKRecurrenceRule?
    }

    /// Extracts a natural-language date and optional recurrence from the given
    /// text and returns a cleaned title along with the parsed components.
    ///
    /// Recurrence phrases ("every week", "every Monday", "daily", etc.) are
    /// detected first and stripped. Then date detection runs on the remaining
    /// text — so a weekday name left behind by recurrence stripping (e.g.
    /// "Monday" from "every Monday") is picked up as the first due date.
    ///
    /// If a recurrence phrase is present but no separate date expression
    /// remains, today (all-day) is used as the fallback due date because
    /// `EKReminder` requires `dueDateComponents` for recurrence to work.
    ///
    /// If multiple date expressions are found, the first one wins. If none
    /// are found, `dueDateComponents` is `nil` (or today for recurrence).
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

        // Step 1: Detect and strip recurrence phrase.
        let (afterRecurrence, rule) = detectRecurrence(in: trimmed)

        // Step 2: Detect date in the remaining text.
        guard let match = firstDateMatch(in: afterRecurrence) else {
            // No date found. If recurrence exists, fall back to today (required by EventKit).
            let dueDate: DateComponents? = if rule != nil {
                calendar.dateComponents([.year, .month, .day], from: Date())
            } else {
                nil
            }
            return Result(
                title: afterRecurrence,
                dueDateComponents: dueDate,
                recurrenceRule: rule)
        }

        let hasTime = hasTimeSpecification(in: afterRecurrence, range: match.range)
        let dateComponents: DateComponents = if hasTime {
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: match.date)
        } else {
            calendar.dateComponents(
                [.year, .month, .day],
                from: match.date)
        }

        let cleanedTitle = stripMatch(afterRecurrence, range: match.range)
        return Result(
            title: cleanedTitle,
            dueDateComponents: dateComponents,
            recurrenceRule: rule)
    }

    // MARK: Private

    // MARK: Private — Recurrence Detection

    /// Weekday name → `EKWeekday` mapping.
    private static let weekdays: [String: EKWeekday] = [
        "sunday": .sunday,
        "monday": .monday,
        "tuesday": .tuesday,
        "wednesday": .wednesday,
        "thursday": .thursday,
        "friday": .friday,
        "saturday": .saturday
    ]

    /// "every Monday" — strips "every " prefix, keeps weekday for date detection.
    private static let everyWeekdayRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bevery\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            options: .caseInsensitive)

    /// "every week on Sunday" — strips "every week on ", keeps weekday.
    private static let everyWeekOnWeekdayRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bevery\s+week\s+on\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            options: .caseInsensitive)

    /// "every 2 weeks on Monday" — strips "every N weeks on ", keeps weekday.
    private static let everyWeeksOnWeekdayRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bevery\s+(\d+)\s+weeks?\s+on\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            options: .caseInsensitive)

    /// "every other day/week/month/year" — interval 2.
    private static let everyOtherRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bevery\s+other\s+(day|week|month|year)\b"#,
            options: .caseInsensitive)

    /// "every [N] day(s)/week(s)/month(s)/year(s)" — bare frequency with optional interval.
    private static let everyFrequencyRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bevery\s+(?:(\d+)\s+)?(days?|weeks?|months?|years?)\b"#,
            options: .caseInsensitive)

    /// "daily", "weekly", "monthly", "yearly", "annually".
    private static let synonymRegex = // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(daily|weekly|monthly|yearly|annually)\b"#,
            options: .caseInsensitive)

    // MARK: Private — Date Detection

    private static let connectors: Set<String> = ["at", "on", "by"]

    private static let dateDetector: NSDataDetector = // swiftlint:disable:next force_try
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Detects a recurrence phrase at the start of any word in the text,
    /// builds an `EKRecurrenceRule`, and returns the stripped text.
    /// Patterns are tried in priority order; the first match wins.
    /// Weekday-bearing patterns keep the weekday name in the text so
    /// `NSDataDetector` can pick it up as the first due date.
    private static func detectRecurrence(in text: String) -> (text: String, rule: EKRecurrenceRule?) {
        if let result = matchEveryWeekday(in: text) {
            return result
        }
        if let result = matchEveryWeekOnWeekday(in: text) {
            return result
        }
        if let result = matchEveryWeeksOnWeekday(in: text) {
            return result
        }
        if let result = matchEveryOther(in: text) {
            return result
        }
        if let result = matchEveryFrequency(in: text) {
            return result
        }
        if let result = matchSynonym(in: text) {
            return result
        }
        return (text, nil)
    }

    /// "every [weekday]" — e.g. "every Monday"
    private static func matchEveryWeekday(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: everyWeekdayRegex, in: text),
              let dayRange = Range(match.range(at: 1), in: text),
              let weekday = weekdays[text[dayRange].lowercased()] else { return nil }
        let stripped = stripPrefix(text, matchRange: match.range, keepRange: match.range(at: 1))
        return (stripped, weeklyRule(interval: 1, weekday: weekday))
    }

    /// "every week on [weekday]" — e.g. "every week on Sunday"
    private static func matchEveryWeekOnWeekday(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: everyWeekOnWeekdayRegex, in: text),
              let dayRange = Range(match.range(at: 1), in: text),
              let weekday = weekdays[text[dayRange].lowercased()] else { return nil }
        let stripped = stripPrefix(text, matchRange: match.range, keepRange: match.range(at: 1))
        return (stripped, weeklyRule(interval: 1, weekday: weekday))
    }

    /// "every N weeks on [weekday]" — e.g. "every 2 weeks on Monday"
    private static func matchEveryWeeksOnWeekday(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: everyWeeksOnWeekdayRegex, in: text),
              let intervalRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let interval = Int(text[intervalRange]),
              let weekday = weekdays[text[dayRange].lowercased()] else { return nil }
        let stripped = stripPrefix(text, matchRange: match.range, keepRange: match.range(at: 2))
        return (stripped, weeklyRule(interval: interval, weekday: weekday))
    }

    /// "every other day/week/month/year" — interval 2
    private static func matchEveryOther(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: everyOtherRegex, in: text),
              let unitRange = Range(match.range(at: 1), in: text),
              let frequency = frequency(for: text[unitRange]) else { return nil }
        let stripped = stripFullMatch(text, range: match.range)
        return (stripped, EKRecurrenceRule(recurrenceWith: frequency, interval: 2, end: nil))
    }

    /// "every [N] day(s)/week(s)/month(s)/year(s)" — bare frequency
    private static func matchEveryFrequency(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: everyFrequencyRegex, in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let frequency = frequency(for: text[unitRange]) else { return nil }
        var interval = 1
        if let intervalRange = Range(match.range(at: 1), in: text) {
            interval = Int(text[intervalRange]) ?? 1
        }
        let stripped = stripFullMatch(text, range: match.range)
        return (stripped, EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil))
    }

    /// "daily", "weekly", "monthly", "yearly", "annually"
    private static func matchSynonym(in text: String) -> (text: String, rule: EKRecurrenceRule?)? {
        guard let match = firstMatch(of: synonymRegex, in: text),
              let wordRange = Range(match.range(at: 1), in: text),
              let frequency = frequency(for: text[wordRange]) else { return nil }
        let stripped = stripFullMatch(text, range: match.range)
        return (stripped, EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
    }

    /// Runs the given regex against the text and returns the first match.
    private static func firstMatch(of regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: fullRange)
    }

    /// Builds a weekly recurrence rule for a specific weekday.
    private static func weeklyRule(interval: Int, weekday: EKWeekday) -> EKRecurrenceRule {
        let dofw = EKRecurrenceDayOfWeek(dayOfTheWeek: weekday, weekNumber: 0)
        return EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: interval,
            daysOfTheWeek: [dofw],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil)
    }

    /// Maps a frequency word ("day", "week", "daily", "annually", …) to an `EKRecurrenceFrequency`.
    private static func frequency(for word: Substring) -> EKRecurrenceFrequency? {
        switch word.lowercased() {
        case "day", "days", "daily": .daily
        case "week", "weeks", "weekly": .weekly
        case "month", "months", "monthly": .monthly
        case "year", "years", "yearly", "annually": .yearly
        default: nil
        }
    }

    /// Removes everything from `matchRange.location` up to (but not including)
    /// `keepRange`. Used when the weekday name must remain in the text for
    /// `NSDataDetector` to find.
    private static func stripPrefix(
        _ text: String,
        matchRange: NSRange,
        keepRange: NSRange) -> String {
        let prefixLen = keepRange.location - matchRange.location
        let stripRange = NSRange(location: matchRange.location, length: prefixLen)
        guard let swiftRange = Range(stripRange, in: text) else { return text }
        var result = text
        result.removeSubrange(swiftRange)
        return result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Removes the entire matched range from the text.
    private static func stripFullMatch(_ text: String, range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var result = text
        result.removeSubrange(swiftRange)
        return result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

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
