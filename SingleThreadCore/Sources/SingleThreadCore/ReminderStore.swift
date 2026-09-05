import EventKit
import Foundation
import os

// The skip-count lifecycle (Phase 1/2) plus the reschedule write (Phase 3)
// push this store over the `file_length` threshold; the logic is cohesive so
// the store stays in one file. Same convention as `ContentView.swift`.
// swiftlint:disable file_length

/// Post-save settle hook. Production waits 200 ms for EventKit to reflect an
/// in-flight write before `reload()`; tests inject a no-op for determinism.
public typealias ReminderStoreSettle = @Sendable () async -> Void

@MainActor
@Observable
public final class ReminderStore {
    // MARK: Lifecycle

    // MARK: - Init

    /// Single init. Production callers accept all defaults; tests inject
    /// an in-memory event store and pre-seeded state.
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        skipCountStore: SkipCountStore = SkipCountStore(),
        pendingCompletionStore: PendingCompletionStore = PendingCompletionStore(),
        excludeStore: ExcludedListStore = ExcludedListStore(),
        loadsReminders: Bool = true,
        reminders: [EKReminder] = [],
        skippedIDs: Set<String> = [],
        pendingCompletions: Set<String> = [],
        authorizationStatus: EKAuthorizationStatus = .notDetermined,
        excludedListTitles: Set<String> = [],
        hasHidden: Bool = false,
        completionCounter: CompletionCounterStore = CompletionCounterStore(),
        entitlementStore: EntitlementStore = EntitlementStore(),
        settle: @escaping ReminderStoreSettle = {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.skipCountStore = skipCountStore
        self.pendingCompletionStore = pendingCompletionStore
        self.excludeStore = excludeStore
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.pendingCompletions = pendingCompletions
        self.authorizationStatus = authorizationStatus
        self.excludedListTitles = excludedListTitles
        self.hasHidden = hasHidden
        self.completionCounter = completionCounter
        self.entitlementStore = entitlementStore
        self.settle = settle
    }

    // MARK: Public

    // MARK: - Public properties

    public private(set) var reminders: [EKReminder] = []
    public private(set) var skippedIDs: Set<String> = []
    public private(set) var excludedListTitles: Set<String> = []
    /// `true` when incomplete reminders exist outside the current date window
    /// (or are undated while `showsUndatedReminders` is off). Set by `reload()`;
    /// seeded via the init. Lets surfaces explain an empty state
    /// that is actually "nothing due right now".
    public private(set) var hasHidden = false
    /// All reminder-list titles (sorted, deduplicated) the settings UI presents.
    public private(set) var availableLists: [String] = []
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

    /// Hook invoked after any excluded-list mutation — passes the full excluded
    /// title array. Wired by each app layer to push exclusion changes via
    /// WatchConnectivity.
    public var onExcludedListsChanged: (([String]) -> Void)?

    /// Hook fired when a reminder's skip count first crosses the nudge threshold
    /// (6). Passes the reminder's identifier. Wired by the iOS/watch view models
    /// to surface the nudge banner.
    public var onSkipNudgeRequested: ((String) -> Void)?

    /// Hook invoked when the user completes a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the completed reminder's identifier. Wired by
    /// the watch app layer to relay the completion to the iPhone via WatchConnectivity.
    public var onCompleteReminder: ((String) -> Void)?

    /// Hook invoked when the user deletes a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the deleted reminder's identifier. Wired by
    /// the watch app layer to relay the deletion to the iPhone via WatchConnectivity.
    public var onDeleteReminder: ((String) -> Void)?

    /// Hook invoked when the user reschedules a reminder on watchOS, where EventKit
    /// writes are unavailable. Passes the reminder's identifier and the new due-date
    /// components. Wired by the watch app layer to relay the reschedule to the
    /// iPhone via WatchConnectivity.
    public var onRescheduleReminder: ((String, DateComponents) -> Void)?

    /// Hook invoked after any mutation that changes the visible reminder set
    /// (complete, skip, add, or clear-skipped reload). Wired by the iOS app layer
    /// to reload widget timelines.
    public var onRemindersChanged: (() -> Void)?

    /// Hook invoked when `showsUndatedReminders` changes. Wired by the iPhone app
    /// layer to push the combined sync context to the watch.
    public var onShowUndatedRemindersChanged: ((Bool) -> Void)?

    /// Tracks the lifetime completion count; incremented once per successful
    /// EventKit save in `completeReminder` (iOS branch only).
    public let completionCounter: CompletionCounterStore

    /// Publishes whether the user has purchased the unlock IAP. Read by
    /// `canMutate` to gate Complete/Skip/Delete after the free tier cap.
    public let entitlementStore: EntitlementStore

    #if !os(watchOS)
        /// Transient undo store — holds the most-recently completed reminder
        /// so the user can revert it. iOS-only; not persisted.
        public let undoStore = UndoStore()
    #endif

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
            .filter { !excludedListTitles.contains($0.calendar?.title ?? "") }
            .sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }
    }

    /// `true` when reminders exist but are all skipped or excluded — i.e. nothing
    /// to display in the current view despite a non-empty source list.
    public var allSkipped: Bool {
        !reminders.isEmpty && visibleReminders.isEmpty
    }

    /// Single post-auth resolution of what a list surface should show, in
    /// canonical order `allDone → reminder → empty`. Never returns `.noAccess`
    /// (auth is a target-local concern).
    public var listContent: ListContent {
        if allSkipped {
            return .allDone
        }
        if let first = visibleReminders.first {
            return .reminder(ReminderDisplay(reminder: first))
        }
        return .empty(hasHidden: hasHidden)
    }

    /// `true` when mutations are allowed: either the user is entitled (purchased
    /// the IAP) or has not yet hit the free-tier completion cap
    /// (`EntitlementStore.freemiumCap`).
    public var canMutate: Bool {
        entitlementStore.isEntitled || completionCounter.count < EntitlementStore.freemiumCap
    }

    /// Whether the entitlement value has been settled by at least one StoreKit
    /// refresh (or a test seam). Mirrors `entitlementStore.hasResolvedEntitlement`
    /// so views can gate on one seam without reaching into the entitlement store.
    public var hasResolvedEntitlement: Bool {
        entitlementStore.hasResolvedEntitlement
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
    ///
    /// Returns `true` when a reminder was actually completed (or, on watchOS,
    /// removed and relayed); `false` when the identifier didn't match or the
    /// EventKit save failed. Callers use this to gate success-only feedback
    /// such as the completion glow.
    @discardableResult
    public func completeReminder(identifier: String) async -> Bool {
        guard canMutate else { return false }
        #if os(watchOS)
            let removed = reminders.contains { $0.calendarItemIdentifier == identifier }
            reminders.removeAll { $0.calendarItemIdentifier == identifier }
            if removed {
                // Track before the fire-and-forget relay so a reload before the
                // phone processes it cannot resurrect (or double-complete) this
                // reminder. Hydrate from disk first so a completion never
                // overwrites pending IDs persisted by an earlier session; the
                // store's 5-minute expiry also drops any relay that was silently
                // lost. Pruned by `reload()` once the phone catches up.
                pendingCompletions = pendingCompletionStore.load()
                pendingCompletions.insert(identifier)
                pendingCompletionStore.record(identifier)
                onCompleteReminder?(identifier)
                resetSkipCount(for: identifier)
            }
            return removed
        #else
            guard
                let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier })
            else { return false }
            do {
                reminder.isCompleted = true
                try eventStore.save(reminder, commit: true)
                completionCounter.increment()
                undoStore.retain(reminder)
                resetSkipCount(for: identifier)
                await settle()
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to complete reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        #endif
    }

    @discardableResult
    public func completeCurrentReminder() async -> Bool {
        guard let reminder = visibleReminders.first else { return false }
        return await completeReminder(identifier: reminder.calendarItemIdentifier)
    }

    #if !os(watchOS)
        /// Reverts the most-recent completion: sets `isCompleted = false` on
        /// the retained reminder, saves to EventKit, decrements the counter,
        /// clears the undo store, and reloads. Returns `false` when there is
        /// nothing to undo or mutation is gated.
        @discardableResult
        public func undoLastCompletion() async -> Bool {
            guard canMutate, let reminder = undoStore.lastCompletedReminder else {
                return false
            }
            do {
                reminder.isCompleted = false
                try eventStore.save(reminder, commit: true)
                completionCounter.decrement()
                undoStore.clear()
                await settle()
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to undo completion: \(error.localizedDescription, privacy: .public)")
                undoStore.clear()
                return false
            }
        }
    #endif

    /// Deletes a specific reminder by identifier.
    ///
    /// On iOS: removes the whole `EKReminder` object from EventKit and reloads.
    /// On watchOS (where EventKit is read-only): removes it locally and relays the
    /// deletion to the iPhone via `onDeleteReminder`.
    public func deleteReminder(identifier: String) async {
        guard canMutate else { return }
        #if os(watchOS)
            reminders.removeAll { $0.calendarItemIdentifier == identifier }
            resetSkipCount(for: identifier)
            onDeleteReminder?(identifier)
        #else
            guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return }
            do {
                try eventStore.remove(reminder, commit: true)
                resetSkipCount(for: identifier)
                await settle()
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
                await settle()
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to add reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        #endif
    }

    /// Reschedules `identifier` to a new due date (iOS only — EventKit is
    /// read-only on watchOS). Sets `dueDateComponents`, saves, and reloads; also
    /// resets the reminder's skip count so its nudge history starts over.
    /// On watchOS, relays the request to the iPhone via `onRescheduleReminder`
    /// and returns `true` once the relay is dispatched.
    @discardableResult
    public func rescheduleReminder(identifier: String, to due: DateComponents) async -> Bool {
        guard canMutate else { return false }
        #if os(watchOS)
            let handler = onRescheduleReminder
            handler?(identifier, due)
            return true
        #else
            guard let reminder = reminders.first(where: {
                $0.calendarItemIdentifier == identifier
            }) else { return false }
            do {
                reminder.dueDateComponents = due
                try eventStore.save(reminder, commit: true)
                resetSkipCount(for: identifier)
                await settle()
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to reschedule reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        #endif
    }

    public func skipCurrentReminder() {
        guard canMutate else { return }
        guard let reminder = visibleReminders.first else { return }
        let identifier = reminder.calendarItemIdentifier
        #if os(iOS) || os(watchOS)
            if incrementSkipCount(for: identifier) {
                // 6th skip: interrupt the cycle and prompt instead of advancing.
                onSkipNudgeRequested?(identifier)
                return
            }
        #else
            _ = incrementSkipCount(for: identifier)
        #endif
        let updated = updatedSkipSet(afterSkipping: identifier)
        let capturedGeneration = skipGeneration
        Task {
            await settle()
            // Refetch only when the skip actually applied — a clear that raced
            // ahead discards it (generation gate) so no stale refetch runs.
            if applySkipSet(updated, generation: capturedGeneration) {
                await reload()
            }
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
        guard canMutate else { return false }
        guard let reminder = visibleReminders.first else { return false }
        let identifier = reminder.calendarItemIdentifier
        if incrementSkipCount(for: identifier) {
            // Widget has no nudge UI; the count still persists so the paired
            // phone/watch surfaces the prompt. The skip still applies.
            onSkipNudgeRequested?(identifier)
        }
        let updated = updatedSkipSet(afterSkipping: identifier)
        applySkipSet(updated)
        return true
    }

    /// Refetches reminders from EventKit and reconciles all derived state:
    /// the visible `reminders` array, hidden/skip/excluded sets, and the
    /// watch-relayed pending-completion set. When `clearSkipped` is set, the
    /// skipped set is cleared instead of re-resolved.
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
        var shown = showsUndatedReminders
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
        // Pending completions (watch-relayed) hide their reminder until the
        // phone processes them; the defensive drop guarantees the invariant
        // that `reminders` never contains a completed reminder. No-op on iOS,
        // where the device-local set is always empty.
        shown = applyingPendingCompletionFilter(to: shown)
        reminders = shown
        availableLists = Set(
            eventStore.calendars(for: .reminder)
                .map(\.title)
                .filter { !$0.isEmpty })
            .sorted()
        // Reconcile the skip/excluded state from the visible reminders
        // (clearing everything instead when requested).
        reconcileSkipState(clearSkipped: clearSkipped, visibleShown: shown)
        // Prune pending IDs no longer present in the fetch — the phone has
        // processed the relay and the reminder is now genuinely completed.
        prunePendingCompletions(fetched: fetched)
        onRemindersChanged?()
    }

    /// Replaces the excluded-list title set, persisting immediately and firing
    /// both `onExcludedListsChanged` and `onRemindersChanged`.
    public func setExcludedListTitles(_ titles: Set<String>) {
        excludedListTitles = titles
        let array = Array(titles)
        excludeStore.save(array)
        onExcludedListsChanged?(array)
        onRemindersChanged?()
    }

    /// Refreshes the live excluded-list set from titles received over
    /// WatchConnectivity. Does NOT fire `onExcludedListsChanged`, so
    /// the receive path never echoes a push back to the sender (that hook is only
    /// for local `setExcludedListTitles` changes).
    public func refreshExcludedListTitles(_ titles: Set<String>) {
        excludedListTitles = titles
        onRemindersChanged?()
    }

    // MARK: Skip counts

    /// The persisted skip count for a reminder, `0` when unknown.
    public func skipCount(for identifier: String) -> Int {
        skipCountStore.load()[identifier] ?? 0
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

    private static let logger = Logger(subsystem: "app.alanvardy.SingleThread", category: "ReminderStore")

    /// Post-save settle hook. Injected for tests; production keeps the 200 ms
    /// default so EventKit writes land before `reload()`.
    private let settle: ReminderStoreSettle

    private let eventStore: any EventKitStoring
    private let skipStore: SkippedReminderStore
    private let skipCountStore: SkipCountStore
    private let pendingCompletionStore: PendingCompletionStore
    private let excludeStore: ExcludedListStore

    /// Watch-completed identifiers awaiting the phone's relay. Loaded/pruned
    /// inside `reload()`; mutated by the watchOS `completeReminder` branch.
    private var pendingCompletions: Set<String> = []

    /// Increments whenever the skipped set is cleared, invalidating any
    /// in-flight skip task captured before the clear.
    private var skipGeneration: Int = 0

    /// Computes the skip list that results from skipping `identifier`, pruning
    /// stale IDs against the currently-fetched reminders.
    private func updatedSkipSet(afterSkipping identifier: String) -> [String] {
        ReminderSkipLogic.skipping(
            identifier,
            fetched: reminders.map(\.calendarItemIdentifier),
            skipped: Array(skippedIDs))
    }

    /// Increments the count and persists it, returning `true` when the increment
    /// first crossed the nudge threshold.
    private func incrementSkipCount(for identifier: String) -> Bool {
        var counts = skipCountStore.load()
        let old = counts[identifier] ?? 0
        let new = old + 1
        counts[identifier] = new
        skipCountStore.save(counts)
        return SkipCountLogic.crossedThreshold(from: old, to: new)
    }

    /// Removes a reminder's count (delete/reschedule/complete). No-op when absent.
    private func resetSkipCount(for identifier: String) {
        let counts = skipCountStore.load()
        let filtered = counts.filter { $0.key != identifier }
        guard filtered.count != counts.count else { return } // absent → no-op
        skipCountStore.save(filtered)
    }

    /// Prunes counts for identifiers no longer in the in-window fetched set, so a
    /// reminder that leaves the window re-zeros (mirrors the skip-set prune).
    private func reconcileSkipCounts(visibleShown: [EKReminder]) {
        let windowIDs = Set(visibleShown.map(\.calendarItemIdentifier))
        let counts = skipCountStore.load()
        let pruned = counts.filter { windowIDs.contains($0.key) }
        if pruned.count != counts.count {
            skipCountStore.save(pruned)
        }
    }

    /// Clears the skipped set, bumping the generation so any in-flight skip task
    /// captured before the clear is discarded when it wakes up.
    private func clearSkippedState() {
        skipGeneration &+= 1
        skippedIDs = []
        skipStore.save([])
        onSkipSetChanged?([])
    }

    /// Applies a new skip list to in-memory state, persistence, and hooks.
    /// When `generation` is provided and no longer matches, the apply is
    /// discarded — a clear-skipped raced ahead of the in-flight skip task.
    /// Returns `false` when the apply was discarded (generation mismatch) and
    /// `true` when it was applied.
    @discardableResult
    private func applySkipSet(_ updated: [String], generation: Int? = nil) -> Bool {
        if let generation, generation != skipGeneration {
            return false
        }
        skippedIDs = Set(updated)
        skipStore.save(updated)
        onSkipSetChanged?(updated)
        onRemindersChanged?()
        return true
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

    /// Loads the device-local pending-completion set and applies it to `shown`:
    /// hides reminders whose completion the watch relayed but the phone has not
    /// yet processed, then drops any completed reminder that slipped the
    /// incomplete predicate (the "never show a completed card" invariant).
    private func applyingPendingCompletionFilter(to shown: [EKReminder]) -> [EKReminder] {
        pendingCompletions = pendingCompletionStore.load()
        let filtered = PendingCompletionLogic.filtering(fetched: shown, pending: pendingCompletions)
        return PendingCompletionLogic.removingCompleted(filtered)
    }

    /// Removes pending IDs the phone has since completed (no longer present in
    /// the fetched incomplete set) and persists the remainder. An empty fetch
    /// is skipped — a transient empty EventKit result must not wipe the whole
    /// set and resurrect every still-incomplete relayed reminder
    /// (double-completion + a second counter increment).
    private func prunePendingCompletions(fetched: [EKReminder]) {
        guard !fetched.isEmpty else { return }
        let pruned = PendingCompletionLogic.pruned(
            pending: pendingCompletions,
            fetchedIdentifiers: Set(fetched.map(\.calendarItemIdentifier)))
        if pruned != pendingCompletions {
            pendingCompletions = pruned
            pendingCompletionStore.save(pruned)
        }
    }

    /// Reconciles the in-memory skip and excluded-list sets against the
    /// still-visible reminders and persists the pruned skip list so stale IDs
    /// (a deleted-while-skipped reminder, for example) drop cleanly from
    /// UserDefaults too, keeping the on-disk skip store consistent with
    /// in-memory `skippedIDs`.
    private func reconcileSkipState(clearSkipped: Bool, visibleShown: [EKReminder]) {
        if clearSkipped {
            clearSkippedState()
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: visibleShown.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
            excludedListTitles = Set(excludeStore.load())
            skipStore.save(resolved)
        }
        // Counts are history, not part of the skip set — `clearSkipped: true`
        // clears the skip set but keeps counts (the prune still runs, so only
        // out-of-window identifiers drop).
        reconcileSkipCounts(visibleShown: visibleShown)
    }
}
