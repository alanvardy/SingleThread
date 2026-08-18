import Foundation

/// Builds the URL that opens a specific reminder in Apple's Reminders app.
///
/// Uses the `x-apple-reminderkit://REMCDReminder/<id>` scheme (undocumented,
/// but widely used for deep-linking into Reminders). No UIKit, SwiftUI, or
/// EventKit dependencies — fully unit-testable.
public nonisolated enum ReminderDeepLink {
    /// Returns a URL that opens the Reminders app to the given reminder.
    ///
    /// - Parameter identifier: The `EKReminder.calendarItemIdentifier` for
    ///   the reminder to open.
    /// - Returns: The URL, or `nil` if the identifier is empty.
    public static func url(forReminderIdentifier identifier: String) -> URL? {
        guard !identifier.isEmpty else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(identifier)")
    }
}
