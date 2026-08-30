import EventKit
import Foundation

/// Transient in-memory holder for the most-recently completed reminder,
/// enabling a single-level undo. Lives per `ReminderStore` instance;
/// not persisted. Follows the `CompletionGlow` pattern: `@MainActor`,
/// `@Observable`, `final class`.
@MainActor
@Observable
public final class UndoStore {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// The most-recently completed reminder, if one has been retained and
    /// not yet cleared (by undo or by a subsequent completion overwrite).
    public private(set) var lastCompletedReminder: EKReminder?

    public var hasUndoableReminder: Bool {
        lastCompletedReminder != nil
    }

    /// Stashes the given reminder reference; overwrites any prior.
    public func retain(_ reminder: EKReminder) {
        lastCompletedReminder = reminder
    }

    /// Nils out the retained reference.
    public func clear() {
        lastCompletedReminder = nil
    }
}
