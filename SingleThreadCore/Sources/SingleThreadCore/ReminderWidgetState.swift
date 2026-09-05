import EventKit
import Foundation

/// The five possible states a widget surface renders. WidgetKit-free so every
/// surface (iOS today, watch next) shares one tested derivation.
public enum ReminderWidgetState: Equatable, Sendable {
    case noAccess
    case empty(hasHidden: Bool) // true when reminders exist but are out-of-window
    case allDone
    case reminder(ReminderDisplay)

    // MARK: Public

    /// Derives the state from a freshly-reloaded store. The caller builds the
    /// fresh store, sets `showsUndatedReminders`/`sortOption`, and passes the
    /// authorization gate in so `.noAccess` is testable without a real
    /// `EKEventStore` (production passes
    /// `EKEventStore.authorizationStatus(for: .reminder)`).
    @MainActor
    public static func makeWidgetState(
        store: ReminderStore,
        authorization: EKAuthorizationStatus) async -> Self {
        guard authorization == .fullAccess else { return .noAccess }
        await store.reload()
        if store.reminders.isEmpty {
            return .empty(hasHidden: store.hasHidden)
        }
        guard let current = store.visibleReminders.first else { return .allDone }
        return .reminder(ReminderDisplay(reminder: current))
    }
}
