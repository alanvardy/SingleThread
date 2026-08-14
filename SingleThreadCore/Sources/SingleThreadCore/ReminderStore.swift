import EventKit
import Foundation

@MainActor
@Observable
public final class ReminderStore {
    // MARK: Lifecycle

    // MARK: - Init

    /// Production init: uses real EventKit + UserDefaults.
    public init(
        eventStore: EKEventStore = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        loadsReminders: Bool = true) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.loadsReminders = loadsReminders
    }

    /// Preview/test init: pre-populate all state, never touches EventKit.
    public init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus) {
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.authorizationStatus = authorizationStatus
        eventStore = EKEventStore()
        skipStore = SkippedReminderStore()
    }

    // MARK: Public

    // MARK: - Public properties

    public private(set) var reminders: [EKReminder] = []
    public private(set) var skippedIDs: Set<String> = []
    public private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    public let loadsReminders: Bool

    /// Hook invoked after every skip/clear mutation — passes the full skip ID array.
    /// Wired by each app layer to push skip-set changes via WatchConnectivity (Phase 4).
    public var onSkipSetChanged: (([String]) -> Void)?

    /// Hook invoked when the user completes a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the completed reminder's identifier. Wired by
    /// the watch app layer to relay the completion to the iPhone via WatchConnectivity.
    public var onCompleteReminder: ((String) -> Void)?

    public var visibleReminders: [EKReminder] {
        reminders.filter { !skippedIDs.contains($0.calendarItemIdentifier) }
    }

    // MARK: - Public methods

    /// Kicks off authorization + loading. Call from `.task` in the view layer.
    public func start() async {
        guard loadsReminders else { return }
        let current = EKEventStore.authorizationStatus(for: .reminder)
        authorizationStatus = current
        if current == .fullAccess {
            await reload()
        } else {
            await requestAccess()
        }
    }

    /// Completes a specific reminder by identifier.
    ///
    /// On iOS: marks it done in EventKit and reloads. On watchOS (where EventKit is
    /// read-only): removes it locally and relays the completion to the iPhone via
    /// `onCompleteReminder`.
    public func completeReminder(identifier: String) async {
        #if os(watchOS)
            reminders.removeAll { $0.calendarItemIdentifier == identifier }
            onCompleteReminder?(identifier)
        #else
            guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return }
            do {
                reminder.isCompleted = true
                try eventStore.save(reminder, commit: true)
                try? await Task.sleep(nanoseconds: 200_000_000)
                await reload()
            } catch {
                print("[\(Date.now.timeIntervalSince1970)] complete error \(error)")
            }
        #endif
    }

    public func completeCurrentReminder() async {
        guard let reminder = visibleReminders.first else { return }
        await completeReminder(identifier: reminder.calendarItemIdentifier)
    }

    public func skipCurrentReminder() {
        guard let reminder = visibleReminders.first else { return }
        let fetchedIDs = reminders.map(\.calendarItemIdentifier)
        let updated = ReminderSkipLogic.skipping(
            reminder.calendarItemIdentifier,
            fetched: fetchedIDs,
            skipped: Array(skippedIDs))
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            skippedIDs = Set(updated)
            skipStore.save(updated)
            onSkipSetChanged?(updated)
        }
    }

    public func reload(clearSkipped: Bool = false) async {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: ReminderDateFilter.endOfToday(),
            calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.eventStore.fetchReminders(matching: predicate) { results in
                    continuation.resume(returning: results ?? [])
                }
            }
        }
        reminders = fetched
        if clearSkipped {
            skippedIDs = []
            skipStore.save([])
            onSkipSetChanged?([])
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: fetched.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
        }
    }

    // MARK: Private

    private let eventStore: EKEventStore
    private let skipStore: SkippedReminderStore

    private func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if granted {
                authorizationStatus = .fullAccess
                await reload()
            } else {
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }
}
