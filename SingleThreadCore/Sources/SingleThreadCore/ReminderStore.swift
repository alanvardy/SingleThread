import EventKit
import Foundation
import os

@MainActor
@Observable
public final class ReminderStore {
    // MARK: Lifecycle

    // MARK: - Init

    /// Production init: uses real EventKit + UserDefaults.
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        excludeStore: ExcludedProjectStore = ExcludedProjectStore(),
        loadsReminders: Bool = true) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.excludeStore = excludeStore
        self.loadsReminders = loadsReminders
    }

    /// Preview/test init: pre-populate all state, never touches EventKit.
    public init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        excludedProjectTitles: Set<String> = [],
        hasHidden: Bool = false) {
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.excludedProjectTitles = excludedProjectTitles
        self.authorizationStatus = authorizationStatus
        self.hasHidden = hasHidden
        eventStore = EKEventStore()
        skipStore = SkippedReminderStore()
        excludeStore = ExcludedProjectStore()
    }

    // MARK: Public

    // MARK: - Public properties

    public private(set) var reminders: [EKReminder] = []
    public private(set) var skippedIDs: Set<String> = []
    public private(set) var excludedProjectTitles: Set<String> = []
    /// `true` when incomplete reminders exist outside the current date window
    /// (or are undated while `showsUndatedReminders` is off). Set by `reload()`;
    /// seeded by the preview/test init. Lets surfaces explain an empty state
    /// that is actually "nothing due right now".
    public private(set) var hasHidden = false
    /// All reminder-list titles (sorted, deduplicated) the settings UI presents.
    public private(set) var availableProjects: [String] = []
    public private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    public let loadsReminders: Bool

    /// The active sort ordering. Direct assignment (e.g. launch injection) does not
    /// fire hooks; use `setSortOption` for user-initiated changes.
    public var sortOption: SortOption = .priority

    /// Hook fired when the user changes sort (watch push, Phase 4). Wired by the
    /// app layer; Core never reads UserDefaults.
    public var onSortOptionChanged: ((SortOption) -> Void)?

    /// Hook invoked after every skip/clear mutation — passes the full skip ID array.
    /// Wired by each app layer to push skip-set changes via WatchConnectivity (Phase 4).
    public var onSkipSetChanged: (([String]) -> Void)?

    /// Hook invoked after any excluded-project mutation — passes the full excluded
    /// title array. Wired by each app layer to push exclusion changes via
    /// WatchConnectivity.
    public var onExcludedProjectsChanged: (([String]) -> Void)?

    /// Hook invoked when the user completes a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the completed reminder's identifier. Wired by
    /// the watch app layer to relay the completion to the iPhone via WatchConnectivity.
    public var onCompleteReminder: ((String) -> Void)?

    /// Hook invoked when the user deletes a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the deleted reminder's identifier. Wired by
    /// the watch app layer to relay the deletion to the iPhone via WatchConnectivity.
    public var onDeleteReminder: ((String) -> Void)?

    /// Hook invoked after any mutation that changes the visible reminder set
    /// (complete, skip, add, or clear-skipped reload). Wired by the iOS app layer
    /// to reload widget timelines.
    public var onRemindersChanged: (() -> Void)?

    /// Hook invoked when `showsUndatedReminders` changes. Wired by the iPhone app
    /// layer to push the combined sync context to the watch.
    public var onShowUndatedRemindersChanged: ((Bool) -> Void)?

    /// When `true`, `reload()` fetches with a nil/nil date predicate and keeps
    /// undated reminders plus dated reminders still inside the current window.
    /// Each surface sets this before its own `reload()` (phone from the Settings
    /// toggle, widget and watch from synced state).
    public var showsUndatedReminders = false {
        didSet {
            guard showsUndatedReminders != oldValue else { return }
            onShowUndatedRemindersChanged?(showsUndatedReminders)
        }
    }

    public var visibleReminders: [EKReminder] {
        reminders
            .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
            .filter { !excludedProjectTitles.contains($0.calendar?.title ?? "") }
            .sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }
    }

    /// Returns `true` when `allIncomplete` contains a reminder absent from
    /// `shown` (by `calendarItemIdentifier`) — i.e. the current in-window view
    /// is hiding at least one incomplete reminder.
    public static func hasHiddenFor(shown: [EKReminder], allIncomplete: [EKReminder]) -> Bool {
        let shownIDs = Set(shown.map(\.calendarItemIdentifier))
        return allIncomplete.contains { !shownIDs.contains($0.calendarItemIdentifier) }
    }

    // MARK: - Public methods

    /// Kicks off authorization + loading. Call from `.task` in the view layer.
    public func start() async {
        guard loadsReminders else { return }
        let current = eventStore.authorizationStatus(for: .reminder)
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
                try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
                await reload()
            } catch {
                Self.logger.error("Failed to complete reminder: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }

    public func completeCurrentReminder() async {
        guard let reminder = visibleReminders.first else { return }
        await completeReminder(identifier: reminder.calendarItemIdentifier)
    }

    /// Deletes a specific reminder by identifier.
    ///
    /// On iOS: removes the whole `EKReminder` object from EventKit and reloads.
    /// On watchOS (where EventKit is read-only): removes it locally and relays the
    /// deletion to the iPhone via `onDeleteReminder`.
    public func deleteReminder(identifier: String) async {
        #if os(watchOS)
            reminders.removeAll { $0.calendarItemIdentifier == identifier }
            onDeleteReminder?(identifier)
        #else
            guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return }
            do {
                try eventStore.remove(reminder, commit: true)
                try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
                await reload()
            } catch {
                Self.logger.error("Failed to delete reminder: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }

    public func deleteCurrentReminder() async {
        guard let reminder = visibleReminders.first else { return }
        await deleteReminder(identifier: reminder.calendarItemIdentifier)
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
            let reminder = eventStore.makeReminder(
                title: title,
                notes: notes,
                dueDate: dueDate,
                recurrenceRule: recurrenceRule)
            do {
                try eventStore.save(reminder, commit: true)
                try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to add reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        #endif
    }

    public func skipCurrentReminder() {
        guard let reminder = visibleReminders.first else { return }
        let updated = updatedSkipSet(afterSkipping: reminder.calendarItemIdentifier)
        Task {
            try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
            applySkipSet(updated)
        }
    }

    /// Assigns a new sort option, firing hooks only on an actual change so a
    /// redundant setting (or widget/intent process with nil hooks) is a no-op.
    public func setSortOption(_ option: SortOption) {
        guard option != sortOption else { return }
        sortOption = option
        onSortOptionChanged?(option)
        onRemindersChanged?()
    }

    /// Skips the first visible reminder synchronously.
    ///
    /// Unlike `skipCurrentReminder()`, this writes the skip list before returning.
    /// It exists for the widget's `SkipReminderIntent`, whose process WidgetKit may
    /// suspend right after `perform()` returns — the settle sleep used by the
    /// interactive path is unsafe there.
    @discardableResult
    public func skipCurrentReminderImmediately() -> Bool {
        guard let reminder = visibleReminders.first else { return false }
        let updated = updatedSkipSet(afterSkipping: reminder.calendarItemIdentifier)
        applySkipSet(updated)
        return true
    }

    public func reload(clearSkipped: Bool = false) async {
        guard loadsReminders else { return }
        #if !os(watchOS)
            eventStore.refreshSourcesIfNecessary()
        #endif
        let startDate: Date?
        let endDate: Date?
        if showsUndatedReminders {
            startDate = nil
            endDate = nil
        } else {
            startDate = ReminderDateFilter.overdueCutoff()
            endDate = ReminderDateFilter.endOfToday()
        }
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startDate,
            ending: endDate,
            calendars: nil)
        let fetched: [EKReminder] = await fetchReminders(matching: predicate)
        let shown = showsUndatedReminders
            ? fetched.filter { ReminderDateFilter.isInCurrentWindow($0.dueDateComponents?.date) }
            : fetched
        if showsUndatedReminders {
            // Broad fetch already in hand — derive from fetched vs shown.
            hasHidden = Self.hasHiddenFor(shown: shown, allIncomplete: fetched)
        } else {
            // Narrow fetch excludes future/old/undated work; one extra broad fetch
            // reveals whether the window is hiding reminders.
            let broadPredicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil)
            let allIncomplete: [EKReminder] = await fetchReminders(matching: broadPredicate)
            hasHidden = Self.hasHiddenFor(shown: shown, allIncomplete: allIncomplete)
        }
        reminders = shown
        availableProjects = Set(
            eventStore.calendars(for: .reminder)
                .map(\.title)
                .filter { !$0.isEmpty })
            .sorted()
        if clearSkipped {
            skippedIDs = []
            skipStore.save([])
            onSkipSetChanged?([])
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: shown.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
            excludedProjectTitles = Set(excludeStore.load())
            // Persist the pruned list so stale IDs (a deleted-while-skipped
            // reminder, for example) drop cleanly from UserDefaults too, keeping
            // the on-disk skip store consistent with in-memory `skippedIDs`.
            skipStore.save(resolved)
        }
        onRemindersChanged?()
    }

    /// Replaces the excluded-project title set, persisting immediately and firing
    /// both `onExcludedProjectsChanged` and `onRemindersChanged`.
    public func setExcludedProjectTitles(_ titles: Set<String>) {
        excludedProjectTitles = titles
        let array = Array(titles)
        excludeStore.save(array)
        onExcludedProjectsChanged?(array)
        onRemindersChanged?()
    }

    // MARK: Internal

    /// Requests full access to reminders, updating `authorizationStatus` and
    /// reloading on success. Extracted from `start()` for testability.
    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if granted {
                authorizationStatus = .fullAccess
                await reload()
            } else {
                authorizationStatus = eventStore.authorizationStatus(for: .reminder)
            }
        } catch {
            authorizationStatus = eventStore.authorizationStatus(for: .reminder)
        }
    }

    // MARK: Private

    /// EventKit may not reflect an in-flight save immediately; settle briefly
    /// before re-fetching so the just-written change shows up in `reload()`.
    private static let eventKitSettleDelay: UInt64 = 200_000_000

    private static let logger = Logger(subsystem: "app.alanvardy.SingleThread", category: "ReminderStore")

    private let eventStore: any EventKitStoring
    private let skipStore: SkippedReminderStore
    private let excludeStore: ExcludedProjectStore

    /// Computes the skip list that results from skipping `identifier`, pruning
    /// stale IDs against the currently-fetched reminders.
    private func updatedSkipSet(afterSkipping identifier: String) -> [String] {
        ReminderSkipLogic.skipping(
            identifier,
            fetched: reminders.map(\.calendarItemIdentifier),
            skipped: Array(skippedIDs))
    }

    /// Applies a new skip list to in-memory state, persistence, and hooks.
    private func applySkipSet(_ updated: [String]) {
        skippedIDs = Set(updated)
        skipStore.save(updated)
        onSkipSetChanged?(updated)
        onRemindersChanged?()
    }

    /// Bridges the EventKit completion-handler API to async/await.
    /// `fetchReminders(matching:)` performs its work off the main thread; this
    /// keeps the initial EventKit setup from blocking UI updates.
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        let gate = ResumptionGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
            eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
                let value = reminders ?? []
                resumeOnMainActor(gate) {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}
