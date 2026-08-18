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

    /// Hook invoked after any mutation that changes the visible reminder set
    /// (complete, skip, add, or clear-skipped reload). Wired by the iOS app layer
    /// to reload widget timelines.
    public var onRemindersChanged: (() -> Void)?

    public var visibleReminders: [EKReminder] {
        reminders
            .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
            .sorted { ReminderSort.areInIncreasingOrder($0, $1) }
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
                print("Failed to complete reminder: \(error)")
            }
        #endif
    }

    public func completeCurrentReminder() async {
        guard let reminder = visibleReminders.first else { return }
        await completeReminder(identifier: reminder.calendarItemIdentifier)
    }

    /// Creates a new reminder in EventKit with the given title, notes, and optional due date.
    /// A recurrence rule (e.g. weekly on Sunday) can optionally be applied.
    /// Returns `true` if the save succeeded, `false` otherwise.
    /// On watchOS, EventKit is read-only, so this always returns `false`.
    @discardableResult
    public func addReminder(
        title: String,
        notes: String?,
        dueDate: DateComponents?,
        recurrenceRule: EKRecurrenceRule? = nil) async -> Bool {
        #if os(watchOS)
            return false
        #else
            let reminder = Self.makeReminder(
                title: title,
                notes: notes,
                dueDate: dueDate,
                eventStore: eventStore,
                recurrenceRule: recurrenceRule)
            do {
                try eventStore.save(reminder, commit: true)
                try? await Task.sleep(nanoseconds: 200_000_000)
                await reload()
                return true
            } catch {
                print("Failed to add reminder: \(error)")
                return false
            }
        #endif
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
            onRemindersChanged?()
        }
    }

    public func reload(clearSkipped: Bool = false) async {
        guard loadsReminders else { return }
        #if !os(watchOS)
            eventStore.refreshSourcesIfNecessary()
        #endif
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: ReminderDateFilter.overdueCutoff(),
            ending: ReminderDateFilter.endOfToday(),
            calendars: nil)
        let fetched: [EKReminder] = await fetchReminders(matching: predicate)
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
        onRemindersChanged?()
    }

    // MARK: Internal

    #if !os(watchOS)
        /// Builds a new `EKReminder` from the given fields. Extracted for testability.
        static func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            eventStore: EKEventStore,
            recurrenceRule: EKRecurrenceRule? = nil) -> EKReminder {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
            return reminder
        }
    #endif

    // MARK: Private

    private let eventStore: EKEventStore
    private let skipStore: SkippedReminderStore

    /// Bridges the EventKit completion-handler API to async/await.
    /// `fetchReminders(matching:)` performs its work off the main thread; this
    /// keeps the initial EventKit setup from blocking UI updates.
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

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
