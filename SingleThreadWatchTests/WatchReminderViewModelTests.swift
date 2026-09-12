import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Builds a reload-capable `ReminderStore` plus its `WatchReminderViewModel`,
/// seeded with one visible and one skipped reminder. The skipped id is persisted
/// through the injected `skipStore` so `reload(clearSkipped:)` prunes (never
/// clears) it while the visible reminder stays on screen.
@MainActor
private func makeWatchReminderViewModel(skipKey: String) -> (viewModel: WatchReminderViewModel, store: ReminderStore, skippedID: String) {
    let visible = watchReminder("Visible")
    let skipped = watchReminder("Skipped")
    let skipStore = SkippedReminderStore(defaults: .standard, key: skipKey)
    skipStore.save([skipped.calendarItemIdentifier])

    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [visible, skipped]),
        skipStore: skipStore,
        loadsReminders: true,
        reminders: [visible, skipped],
        skippedIDs: [skipped.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState(),
        entitlementState: EntitlementState(),
        showEnableActionButtonsState: ShowEnableActionButtonsState())
    return (viewModel, store, skipped.calendarItemIdentifier)
}

/// Covers `WatchReminderViewModel.refreshFromCardTap()` and the rechecker
/// lifecycle attached to `task()`: a card tap runs a full refresh cycle
/// (`isRefreshing` false → true → false) and passes `store.allSkipped` through
/// as `clearSkipped`, pruning (never clearing) skip state while a reminder is
/// still visible.
@MainActor
@Suite(.serialized)
struct WatchReminderViewModelTests {
    @Test
    func refreshFromCardTapTriggersRefreshCycle() async {
        let skipKey = "watch-cardtap-skip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: skipKey) }

        let fixture = makeWatchReminderViewModel(skipKey: skipKey)
        let viewModel = fixture.viewModel
        let store = fixture.store

        #expect(!viewModel.isRefreshing)
        #expect(!store.allSkipped) // "Visible" is not skipped, so a reminder shows

        // `refresh` sets `isRefreshing = true` synchronously ahead of its first
        // suspension, so a single yield lets the spawned task reach it.
        let cycle = Task { await viewModel.refreshFromCardTap() }
        await Task.yield()
        #expect(viewModel.isRefreshing)

        await cycle.value // includes the ~1 s `refreshMinimumDisplayDuration` pad

        #expect(!viewModel.isRefreshing)
        // Prune (`clearSkipped == false`) keeps the still-fetched skip; a wrong
        // `clearSkipped: true` would have cleared it to `[]`.
        #expect(store.skippedIDs.contains(fixture.skippedID))
    }

    /// Covers the `store.allSkipped == true` branch of `refreshFromCardTap()`:
    /// when every loaded reminder is already skipped, a card tap clears the skip
    /// set so the all-done state can be exited.
    @Test
    func refreshFromCardTapClearsSkippedWhenAllRemindersSkipped() async {
        let skipKey = "watch-cardtap-clear-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: skipKey) }

        let skipped = watchReminder("All Skipped")
        let skipStore = SkippedReminderStore(defaults: .standard, key: skipKey)
        skipStore.save([skipped.calendarItemIdentifier])

        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [skipped]),
            skipStore: skipStore,
            loadsReminders: true,
            reminders: [skipped],
            skippedIDs: [skipped.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState())

        #expect(store.allSkipped)
        #expect(store.skippedIDs.contains(skipped.calendarItemIdentifier))

        await viewModel.refreshFromCardTap()

        #expect(store.skippedIDs.isEmpty)
    }

    /// Two concurrent card taps collapse into one refresh cycle: the second tap
    /// is absorbed by `refresh`'s `guard !isRefreshing`, and the
    /// `defer { isRefreshing = false }` guarantee means the flag always settles
    /// back to false (no stuck spinner).
    @Test
    func refreshFromCardTapAbsorbsDoubleTap() async {
        let skipKey = "watch-cardtap-double-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: skipKey) }

        let fixture = makeWatchReminderViewModel(skipKey: skipKey)
        let viewModel = fixture.viewModel

        // `refresh` sets `isRefreshing = true` synchronously ahead of its first
        // suspension, so a single yield lets the first tap reach the guard.
        let first = Task { await viewModel.refreshFromCardTap() }
        await Task.yield()
        #expect(viewModel.isRefreshing)

        // The second tap must be absorbed (no double refresh, no stuck flag).
        let second = Task { await viewModel.refreshFromCardTap() }
        await Task.yield()
        await second.value

        await first.value // includes the ~1 s `refreshMinimumDisplayDuration` pad

        #expect(!viewModel.isRefreshing)
        #expect(fixture.store.skippedIDs.contains(fixture.skippedID))
    }

    // MARK: - Rechecker lifecycle

    @Test
    func taskStartsRecheckerAfterStoreStart() async {
        let recording = RecordingRechecker()
        let viewModel = WatchReminderViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState()) { _ in recording }
        let task = Task { await viewModel.task() }
        while recording.startCount == 0 {
            await Task.yield()
        }
        #expect(recording.startCount == 1)
        task.cancel()
        await task.value
    }

    @Test
    func taskCancellationStopsRecheckerOnce() async {
        let recording = RecordingRechecker()
        let viewModel = WatchReminderViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState()) { _ in recording }
        let task = Task { await viewModel.task() }
        while recording.startCount == 0 {
            await Task.yield()
        }
        task.cancel()
        await task.value
        #expect(recording.stopCount == 1) // stopped exactly once by the defer
    }

    @Test
    func nilRecheckerFactoryDoesNotCrash() async {
        let viewModel = WatchReminderViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState()) { _ in nil }
        let task = Task { await viewModel.task() }
        await Task.yield()
        task.cancel()
        await task.value // optional chaining must not crash with a nil rechecker
        #expect(true)
    }
}

/// Records `start()`/`stop()` calls so the rechecker lifecycle attached to
/// `task()` can be asserted headlessly.
@MainActor
final class RecordingRechecker: StaleReminderRechecking {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

/// Builds a `WatchReminderViewModel` for the reschedule-confirm flow, backed by
/// `AppGroup.defaults` (the shared-value rule); one visible reminder keeps the
/// confirm path reachable.
@MainActor
private func makeRescheduleFixture() -> (viewModel: WatchReminderViewModel, store: ReminderStore, key: String) {
    let visible = watchReminder("Visible")
    let key = "watch-resched-vm-\(UUID().uuidString)"
    let skipStore = SkippedReminderStore(defaults: AppGroup.defaults, key: key)
    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [visible]),
        skipStore: skipStore,
        loadsReminders: true,
        reminders: [visible],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState(),
        entitlementState: EntitlementState(),
        showEnableActionButtonsState: ShowEnableActionButtonsState())
    return (viewModel, store, key)
}

@MainActor
@Suite(.serialized)
struct RescheduleConfirmTests {
    @Test
    func confirmRescheduleRefreshesVisibleRemindersOnSuccess() async {
        let fixture = makeRescheduleFixture()
        defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
        let viewModel = fixture.viewModel
        let store = fixture.store
        store.onRescheduleReminder = { _, _ in true }
        var reloads = 0
        store.onRemindersChanged = { reloads += 1 }
        viewModel.isShowingRescheduleSheet = true
        viewModel.rescheduleDate = Date(timeIntervalSince1970: 1_800_000_000) // arbitrary

        await viewModel.confirmReschedule()

        #expect(reloads >= 1) // refresh ran
        #expect(!viewModel.rescheduleFailure)
        #expect(!viewModel.isShowingRescheduleSheet) // success closes the sheet
    }

    @Test
    func confirmRescheduleSetsFailureWhenRelayRejected() async {
        let fixture = makeRescheduleFixture()
        defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
        let viewModel = fixture.viewModel
        fixture.store.onRescheduleReminder = { _, _ in false }
        viewModel.isShowingRescheduleSheet = true

        await viewModel.confirmReschedule()

        #expect(viewModel.rescheduleFailure)
        #expect(viewModel.isShowingRescheduleSheet) // sheet stays open on failure
    }

    @Test
    func confirmRescheduleNoopWithoutVisibleReminder() async {
        let skipped = watchReminder("Only")
        let key = "watch-resched-vm-none-\(UUID().uuidString)"
        defer { AppGroup.defaults.removeObject(forKey: key) }
        let skipStore = SkippedReminderStore(defaults: AppGroup.defaults, key: key)
        skipStore.save([skipped.calendarItemIdentifier])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [skipped]),
            skipStore: skipStore,
            loadsReminders: true,
            reminders: [skipped],
            skippedIDs: [skipped.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState())
        var fired = false
        store.onRescheduleReminder = { _, _ in fired = true; return true }
        viewModel.isShowingRescheduleSheet = true

        await viewModel.confirmReschedule()

        #expect(!fired)
        #expect(!viewModel.rescheduleFailure)
        #expect(!viewModel.isShowingRescheduleSheet) // pre-existing no-op closes the sheet
    }

    @Test
    func confirmRescheduleSendsDateOnlyComponents() async throws {
        let fixture = makeRescheduleFixture()
        defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
        let viewModel = fixture.viewModel
        var sent: DateComponents?
        fixture.store.onRescheduleReminder = { _, components in
            sent = components
            return true
        }
        // A date with a non-midnight time; the picker is date-only.
        viewModel.rescheduleDate = Date(timeIntervalSince1970: 1_800_000_000)

        await viewModel.confirmReschedule()

        let components = try #require(sent)
        #expect(components.year != nil)
        #expect(components.month != nil)
        #expect(components.day != nil)
        #expect(components.hour == nil) // date-only wire semantics preserved
        #expect(components.minute == nil)
    }
}
