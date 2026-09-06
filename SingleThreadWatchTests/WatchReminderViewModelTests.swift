import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

// MARK: - Fixture

/// A single `EKEventStore` kept alive to back the test reminders. `EKReminder`
/// holds a weak reference to its backing store, so a deallocated store crashes
/// (SIGTRAP) when any property is read. Mirrors `ReminderStoreWatchTests` and
/// `ShowCompletionGlowStateTests` — `InMemoryEventStore.makeReminder` is iOS-only,
/// so watch unit tests build reminders against a live store.
@MainActor private let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

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

/// Covers `WatchReminderViewModel.refreshFromCardTap()`: a card tap runs a full
/// refresh cycle (`isRefreshing` false → true → false) and passes
/// `store.allSkipped` through as `clearSkipped`, pruning (never clearing) skip
/// state while a reminder is still visible.
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
}
