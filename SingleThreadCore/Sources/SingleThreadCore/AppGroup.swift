import Foundation

/// Shared App Group container used to coordinate state between the app and its
/// widget extension. The suite carries UI preferences (`showDate`, `showList`,
/// `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders`,
/// `sortOption`) plus store-backed payloads (`skippedReminderIdentifiers`,
/// `excludedListTitles`, `completionCount`, `pendingCompletionIdentifiers`).
public enum AppGroup {
    /// The App Group identifier. Must match the value registered under the
    /// App Groups capability for both the app and widget targets.
    public static let suiteName = "group.app.alanvardy.SingleThread"

    /// `UserDefaults` backed by the shared App Group, falling back to
    /// `.standard` when the group is unavailable (watchOS, unregistered
    /// simulators, and previews).
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
