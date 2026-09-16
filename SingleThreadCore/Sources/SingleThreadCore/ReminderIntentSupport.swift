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
    /// The next visible reminder's title.
    case next(String)
}

/// Shared, `@MainActor` construction + outcome/dialog logic for the three
/// discoverable reminder intents.
@MainActor
public enum ReminderIntentSupport {
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
            return .nothingToDo
        }
        return .next(title)
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
        case let .next(title):
            "Your next task is \(title)."
        }
    }
}
