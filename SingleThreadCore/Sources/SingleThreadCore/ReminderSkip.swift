import Foundation

/// Pure logic for the skip exclusion list.
/// No UIKit, SwiftUI, or EventKit dependencies — fully unit-testable.
public nonisolated enum ReminderSkipLogic {
    /// Prunes stale identifiers and returns the effective skip list.
    ///
    /// - Parameter fetched: Identifiers of all currently-available reminders.
    /// - Parameter skipped: Previously-persisted skip list (may contain stale IDs).
    /// - Returns: The skip list with stale IDs removed, preserving only IDs still
    ///   present in `fetched`.
    public static func resolve(fetched: [String], skipped: [String]) -> [String] {
        let fetchedSet = Set(fetched)
        return Array(fetchedSet.intersection(skipped))
    }

    /// Returns the new skip list after skipping the given `identifier`.
    /// Calls through `resolve` to prune stale entries automatically.
    public static func skipping(
        _ identifier: String,
        fetched: [String],
        skipped: [String]) -> [String] {
        resolve(fetched: fetched, skipped: skipped + [identifier])
    }
}

/// Maps EKReminder priority values to a display level and an exclamation marker.
///
/// EventKit uses the standard CalDAV priority scheme: `0` = none, `1` = high,
/// `5` = medium, `9` = low.
public nonisolated enum ReminderPriority {
    public enum Level: Equatable, Sendable {
        case high
        case medium
        case low
    }

    /// Resolves the reminder's numeric priority into a display level.
    public static func level(for priority: Int) -> Level? {
        switch priority {
        case 1: .high
        case 5: .medium
        case 9: .low
        default: nil
        }
    }

    /// Returns the exclamation-marker prefix: `!!!` high, `!!` medium, `!` low,
    /// or empty when there is no priority.
    public static func marker(for priority: Int) -> String {
        switch level(for: priority) {
        case .high: "!!!"
        case .medium: "!!"
        case .low: "!"
        case nil: ""
        }
    }

    /// Ordinal used for sorting, lower sorts first. High (0) before medium (1)
    /// before low (2); `nil` for no priority (sorts after all prioritized).
    public static func rank(for priority: Int) -> Int? {
        switch level(for: priority) {
        case .high: 0
        case .medium: 1
        case .low: 2
        case nil: nil
        }
    }
}

/// Cleans and formats reminder notes for display.
public nonisolated enum ReminderNotesFormatter {
    // MARK: Public

    /// Returns the note text suitable for display, with known prefix artifacts removed.
    public static func format(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstScalar = trimmed.unicodeScalars.first else { return nil }
        if leadingPrefixChars.contains(firstScalar) {
            let cleaned = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        return trimmed
    }

    // MARK: Private

    /// Characters stripped when they appear as the first character of a note.
    private static let leadingPrefixChars: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "t")
        return set
    }()
}

/// Persists the skipped reminder identifiers in UserDefaults.
public struct SkippedReminderStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "skippedReminderIdentifiers") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func save(_ identifiers: [String]) {
        defaults.set(identifiers, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
