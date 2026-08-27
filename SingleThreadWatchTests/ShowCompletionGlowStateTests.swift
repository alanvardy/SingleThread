import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

// MARK: - Fixture

/// A single `EKEventStore` kept alive to back the test reminder. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor private let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func watchReminder() -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = "Buy groceries"
    return reminder
}

/// Covers the state-holder semantics and the watch-side completion-glow gate.
/// Serialized because every test writes the same real UserDefaults key
/// ("showCompletionGlow") via the holder's hardcoded `.standard` store; running
/// them in parallel lets one test's `set(false)`/cleanup race another's read of
/// the default (`true`).
@MainActor
@Suite(.serialized)
struct ShowCompletionGlowStateTests {
    @Test
    func initialValueFromPreference() {
        // The holder hardcodes `.standard` + key "showCompletionGlow"; seed that.
        UserDefaults.standard.set(false, forKey: "showCompletionGlow")
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        let state = ShowCompletionGlowState()
        #expect(!state.isEnabled)
    }

    @Test
    func applyPersists() {
        let state = ShowCompletionGlowState()
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        state.apply(false)
        #expect(!ShowCompletionGlowPreference(defaults: .standard).isEnabled)
    }

    @Test
    func applyRepublishes() {
        let state = ShowCompletionGlowState()
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        #expect(state.isEnabled) // default
        state.apply(false)
        #expect(!state.isEnabled) // republished
        state.apply(true)
        #expect(state.isEnabled)
    }

    @Test
    func watchGateSuppressesGlowWhenDisabled() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let glowState = ShowCompletionGlowState()
        glowState.apply(false)
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: glowState)
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }

    @Test
    func watchGateTriggersGlowWhenEnabled() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let glowState = ShowCompletionGlowState()
        // Defaults to enabled — no apply(false) call.
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: glowState)
        await viewModel.completeCurrentReminder()
        #expect(viewModel.completionGlow.isActive)
    }
}
