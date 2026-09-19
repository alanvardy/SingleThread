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
    ///
    /// Deliberately a single cached instance. `UserDefaults.didChangeNotification`
    /// is posted with the *changing* instance as its `object`, and this app's
    /// observers (`PreferenceHolder`, the AI-rules and watch-sync observers in
    /// `AppViewModel`) filter on `object: AppGroup.defaults`. As a computed
    /// property this returned a fresh `UserDefaults` per access, so those
    /// observers never matched a write and silently never fired — editing the AI
    /// sort rules did not re-rank, and App-Group preference changes did not
    /// refresh the main view. `UserDefaults` is documented thread-safe, hence
    /// `nonisolated(unsafe)`.
    public nonisolated(unsafe) static let defaults: UserDefaults =
        .init(suiteName: suiteName) ?? .standard
}
