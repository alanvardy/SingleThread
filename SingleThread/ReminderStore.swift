//
//  ReminderStore.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import EventKit
import Observation

enum ReminderAccessStatus {
    case notDetermined
    case denied
    case authorized

    // MARK: Lifecycle

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied, .restricted, .writeOnly:
            self = .denied
        case .authorized, .fullAccess:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }
}

@MainActor
@Observable
final class ReminderStore {
    // MARK: Internal

    let eventStore = EKEventStore()

    private(set) var accessStatus = ReminderAccessStatus.notDetermined
    private(set) var reminders: [EKReminder] = []

    func load() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try? await eventStore.requestFullAccessToReminders()
        }
        accessStatus = ReminderAccessStatus(EKEventStore.authorizationStatus(for: .reminder))
        guard accessStatus == .authorized else {
            reminders = []
            return
        }
        eventStore.reset()
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil)
        reminders = await fetchReminders(matching: predicate)
    }

    // MARK: Private

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        nonisolated(unsafe) var result: [EKReminder] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                result = reminders ?? []
                continuation.resume()
            }
        }
        return result
    }
}
