//
//  ReminderStore.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import EventKit
import Observation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

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
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            await waitUntilActive()
            guard !isRequestingAccess else {
                return
            }
            isRequestingAccess = true
            _ = await requestFullAccess()
            isRequestingAccess = false
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

    func complete(_ reminder: EKReminder) async throws {
        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    // MARK: Private

    private static var didBecomeActiveNotification: Notification.Name {
        #if os(iOS)
            UIApplication.didBecomeActiveNotification
        #elseif os(macOS)
            NSApplication.didBecomeActiveNotification
        #endif
    }

    private static var isActive: Bool {
        #if os(iOS)
            UIApplication.shared.applicationState == .active
        #elseif os(macOS)
            NSApplication.shared.isActive
        #endif
    }

    private var isRequestingAccess = false

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

    private func requestFullAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func waitUntilActive() async {
        guard !Self.isActive else {
            return
        }
        for await _ in NotificationCenter.default.notifications(named: Self.didBecomeActiveNotification) {
            break
        }
    }
}
