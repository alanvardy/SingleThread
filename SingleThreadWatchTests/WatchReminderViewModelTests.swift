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

/// Covers `WatchReminderViewModel.cardTapped()`: a card tap runs a full refresh
/// cycle (`isRefreshing` false → true → false) and passes `store.allSkipped`
/// through as `clearSkipped`, pruning (never clearing) skip state while a
/// reminder is still visible.
@MainActor
@Suite(.serialized)
struct WatchReminderViewModelTests {
    @Test
    func cardTappedTriggersRefreshCycle() async {
        let skipKey = "watch-cardtap-skip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: skipKey) }

        let visible = watchReminder("Visible")
        let skipped = watchReminder("Skipped")
        // The reload path prunes from the *persisted* skip store, not the
        // in-memory `skippedIDs`, so the isolated store must be pre-seeded.
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

        #expect(!viewModel.isRefreshing)
        #expect(!store.allSkipped) // "Visible" is not skipped, so a reminder shows

        // `refresh` sets `isRefreshing = true` synchronously ahead of its first
        // suspension, so a single yield lets the spawned task reach it.
        let cycle = Task { await viewModel.cardTapped() }
        await Task.yield()
        #expect(viewModel.isRefreshing)

        await cycle.value // includes the ~1 s `refreshMinimumDisplayDuration` pad

        #expect(!viewModel.isRefreshing)
        // Prune (`clearSkipped == false`) keeps the still-fetched skip; a wrong
        // `clearSkipped: true` would have cleared it to `[]`.
        #expect(store.skippedIDs.contains(skipped.calendarItemIdentifier))
    }
}
