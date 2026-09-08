import EventKit
import SingleThreadCore
import WatchConnectivity

// MARK: - Shared watch EKEventStore + reminder builder

/// A single `EKEventStore` kept alive to back the test reminders. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

// MARK: - Fake session for testing

final class WatchFakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var pushShouldThrow = false

    func activate() {
        activated = true
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow {
            throw NSError(domain: "test", code: 1)
        }
        lastContext = applicationContext
    }

    func sendMessage(
        _: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler _: ((any Error) -> Void)?) {}
}
