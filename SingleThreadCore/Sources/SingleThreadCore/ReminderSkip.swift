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
/// EventKit exposes the RFC 5545 priority range: `0` = none, `1...4` = high,
/// `5` = medium, `6...9` = low. Values outside `0...9` resolve to no priority.
public nonisolated enum ReminderPriority {
    public enum Level: CaseIterable, Equatable, Sendable {
        case high
        case medium
        case low

        // MARK: Public

        /// Human-readable name used for accessibility labels on priority markers.
        public var displayName: String {
            switch self {
            case .high: String(localized: "High", table: "Localizable", bundle: .module)
            case .medium: String(localized: "Medium", table: "Localizable", bundle: .module)
            case .low: String(localized: "Low", table: "Localizable", bundle: .module)
            }
        }

        /// Exclamation-marker prefix rendered for this level.
        public var marker: String {
            switch self {
            case .high: "!!!"
            case .medium: "!!"
            case .low: "!"
            }
        }
    }

    /// Resolves the reminder's numeric priority into a display level: `1...4`
    /// high, `5` medium, `6...9` low, and `nil` for `0` or out-of-range values.
    public static func level(for priority: Int) -> Level? {
        switch priority {
        case 1 ... 4: .high
        case 5: .medium
        case 6 ... 9: .low
        default: nil
        }
    }

    /// Resolves a priority marker (`!!!`, `!!`, `!`) back to its display level.
    public static func level(forMarker marker: String) -> Level? {
        Level.allCases.first { $0.marker == marker }
    }

    /// Returns the exclamation-marker prefix for the given priority, or empty
    /// when there is no priority.
    public static func marker(for priority: Int) -> String {
        level(for: priority)?.marker ?? ""
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
    /// Returns the note text suitable for display, with the known leading "t"
    /// artifact removed.
    ///
    /// EventKit/Siri occasionally prepends a stray lowercase "t" to a note's
    /// text before the real (capitalized) content — e.g. `"tBuy milk"`. Strip
    /// that artifact, but only when the "t" is followed by a word boundary
    /// (whitespace/newline), an uppercase letter, or the end of the string, so
    /// a legitimate note beginning with a lowercase "t" (`"take out trash"`)
    /// is left intact.
    public static func format(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }

        if first == Character("t") {
            let remainder = trimmed.dropFirst()
            let isArtifact = remainder.first.map { $0.isWhitespace || $0.isUppercase } ?? true
            if isArtifact {
                let cleaned = String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
        }
        return trimmed
    }
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
