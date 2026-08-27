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
    func uiTestingGlowDisabledFlagPreDisablesState() {
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        let appViewModel = WatchAppViewModel(arguments: ["--ui-testing-glow-disabled"])
        #expect(
            !appViewModel.showCompletionGlowState.isEnabled,
            "The seam pre-disables the state so the disabled-flow test needs no settings screen")
    }

    @Test
    func uiTestingGlowFlagPreEnablesState() {
        // A persisted `false` from an earlier disabled-flow test in the same
        // UI-test session must not suppress the glow for the enabled-flow test.
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        UserDefaults.standard.set(false, forKey: "showCompletionGlow")
        let appViewModel = WatchAppViewModel(arguments: ["--ui-testing-glow"])
        #expect(
            appViewModel.showCompletionGlowState.isEnabled,
            "The seam forces the state on so the enabled-flow test is deterministic")
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
        // apply(false) persists to .standard; clean up so the enabled case
        // still reads the default (true) in this serialized suite.
        defer { UserDefaults.standard.removeObject(forKey: "showCompletionGlow") }
        glowState.apply(false)
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
