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
    var lastMessage: [String: Any]?
    var pushShouldThrow = false

    /// Reachability the production request path branches on. Defaults to the
    /// happy path so every pre-existing test keeps taking `sendMessage`.
    var isReachable = true
    /// Recorded `transferUserInfo` deliveries (the unreachable fallback).
    var queuedUserInfo: [[String: Any]] = []
    /// When set, `sendMessage` reports it through `errorHandler` synchronously.
    var errorToThrow: (any Error)?

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
        _ message: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?) {
        lastMessage = message
        if let errorToThrow {
            errorHandler?(errorToThrow)
        }
    }

    /// Present at Stage 1 so the red test compiles; promoted to a
    /// `SkipSyncSession` requirement in Stage 2.
    func queueUserInfo(_ userInfo: [String: Any]) {
        queuedUserInfo.append(userInfo)
    }
}
