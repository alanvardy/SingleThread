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
        let status = EKEventStore.authorizationStatus(for: .reminder)
        print("[ReminderStore] load() status=\(String(describing: status))")
        if status == .notDetermined {
            await waitUntilActive()
            guard !isRequestingAccess else {
                print("[ReminderStore] request already in flight, skipping")
                return
            }
            isRequestingAccess = true
            let granted = await requestFullAccess()
            isRequestingAccess = false
            print("[ReminderStore] request result granted=\(granted)")
        }
        accessStatus = ReminderAccessStatus(EKEventStore.authorizationStatus(for: .reminder))
        print("[ReminderStore] accessStatus=\(String(describing: accessStatus))")
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
        print("[ReminderStore] fetched \(reminders.count) reminders")
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
            eventStore.requestFullAccessToReminders { granted, error in
                print("[ReminderStore] request completion granted=\(granted) error=\(String(describing: error))")
                continuation.resume(returning: granted)
            }
        }
    }

    private func waitUntilActive() async {
        guard !Self.isActive else {
            print("[ReminderStore] already active, proceeding")
            return
        }
        print("[ReminderStore] waiting for didBecomeActive")
        for await _ in NotificationCenter.default.notifications(named: Self.didBecomeActiveNotification) {
            print("[ReminderStore] didBecomeActive received")
            break
        }
    }
}
