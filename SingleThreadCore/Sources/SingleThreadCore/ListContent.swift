/// What a "list content" surface should render, resolved once by
/// `ReminderStore.listContent` instead of re-derived per target.
///
/// Pure Core logic, no SwiftUI — presentation lives in each app target.
public enum ListContent: Equatable, Sendable {
    /// The user hasn't granted full reminders access. Never returned by
    /// `ReminderStore.listContent` — surfaced directly by the widget's
    /// auth switch.
    case noAccess
    /// `hasHidden` is true when reminders exist but are out-of-window (or are
    /// undated while `showsUndatedReminders` is off).
    case empty(hasHidden: Bool)
    /// All loaded reminders are skipped or excluded — nothing to show despite
    /// a non-empty source list.
    case allDone
    /// A single visible reminder to render.
    case reminder(ReminderDisplay)
}
