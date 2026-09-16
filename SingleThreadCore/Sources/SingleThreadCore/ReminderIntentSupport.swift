import AppIntents
import EventKit
import Foundation

/// What a reminder intent should say and return. Produced by the
/// `ReminderIntentSupport` factories so every message decision is unit-testable
/// without invoking `perform()`.
public enum ReminderIntentOutcome: Equatable, Sendable {
    /// Reminders access is not `.fullAccess`; an intent never prompts.
    case noAccess
    /// No visible reminder and the list is genuinely empty.
    case nothingToDo
    /// Reminders exist but are all skipped/excluded/hidden.
    case nothingLeftToDo
    /// The free-tier mutation cap is reached; the task exists but cannot be changed.
    case cannotMutate
    /// The EventKit write failed; the task exists but the change did not persist.
    case failed
    /// The next visible reminder's title.
    case next(String)
    /// The title of the reminder that was just completed.
    case completed(String)
    /// The title of the reminder that was just skipped.
    case skipped(String)
}

/// Shared, `@MainActor` construction + outcome/dialog logic for the three
/// discoverable reminder intents.
@MainActor
public enum ReminderIntentSupport {
    // MARK: Public

    /// Builds an already-reloaded store for an intent, or `nil` when access is
    /// not `.fullAccess`. Never prompts, never calls `start()`/`requestAccess()`.
    public static func makeStore(
        eventStore: any EventKitStoring,
        authorizationStatus: EKAuthorizationStatus,
        loadsReminders: Bool = true) async -> ReminderStore? {
        guard authorizationStatus == .fullAccess else { return nil }
        let store = ReminderStore(eventStore: eventStore, loadsReminders: loadsReminders)
        store.setSortOption(SortOptionStore().load())
        await store.reload()
        return store
    }

    public static func nextOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
        guard let title = store.visibleReminders.first?.title else {
            return noVisibleOutcome(for: store)
        }
        return .next(title)
    }

    /// Captures the visible title *before* mutating (completion filters it out),
    /// then awaits the durable save. Distinguishes an empty/hidden list from the
    /// free-tier cap (`.cannotMutate`) and a failed EventKit write (`.failed`).
    public static func completeOutcome(for store: ReminderStore) async -> ReminderIntentOutcome {
        guard let title = store.visibleReminders.first?.title else { return noVisibleOutcome(for: store) }
        guard store.canMutate else { return .cannotMutate }
        guard await store.completeCurrentReminder() else { return .failed }
        return .completed(title)
    }

    /// Skips the first visible reminder synchronously; the skip set is written
    /// before this returns (`skipCurrentReminderImmediately`, never the
    /// fire-and-forget `skipCurrentReminder`).
    public static func skipOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
        guard let title = store.visibleReminders.first?.title else { return noVisibleOutcome(for: store) }
        guard store.canMutate else { return .cannotMutate }
        // The skip write cannot throw; this guard is defensive against a skip
        // refused despite a visible, mutable reminder.
        guard store.skipCurrentReminderImmediately() else { return .failed }
        return .skipped(title)
    }

    /// The value returned to Shortcuts; every non-answer returns "".
    public static func value(for outcome: ReminderIntentOutcome) -> String {
        if case let .next(title) = outcome {
            return title
        }
        return ""
    }

    /// The only place intent message text is decided.
    public static func dialog(for outcome: ReminderIntentOutcome) -> LocalizedStringResource {
        switch outcome {
        case .noAccess:
            "Enable access in Settings to see your reminders." // existing App-catalog key
        case .nothingToDo:
            "There's nothing to do right now."
        case .nothingLeftToDo:
            "Everything is skipped for now."
        case .cannotMutate:
            "You've reached the free limit. Upgrade to keep going."
        case .failed:
            "Couldn't update that task. Please try again."
        case let .next(title):
            "Your next task is \(title)."
        case let .completed(title):
            "Marked \(title) as done."
        case let .skipped(title):
            "Skipped \(title)."
        }
    }

    // MARK: Private

    /// Distinguishes an empty list from one where reminders exist but nothing
    /// is visible (all skipped/excluded/hidden).
    private static func noVisibleOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
        store.allSkipped || store.hasHidden ? .nothingLeftToDo : .nothingToDo
    }
}
