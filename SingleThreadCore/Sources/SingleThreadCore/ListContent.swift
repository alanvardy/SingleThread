/// What a "list content" surface should render, resolved once by
/// `ReminderStore.listContent` instead of re-derived per target.
///
/// Pure Core logic, no SwiftUI — presentation lives in each app target.
public enum ListContent: Equatable, Sendable {
    case noAccess
    /// `hasHidden` is true when reminders exist but are out-of-window (or are
    /// undated while `showsUndatedReminders` is off).
    case empty(hasHidden: Bool)
    case allDone
    case reminder(ReminderDisplay)
}
