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
    // MARK: Internal

    @Test
    func stateReadsAndAppliesPreference() {
        // The holder hardcodes `.standard` + the glow key; seed that.
        UserDefaults.standard.set(false, forKey: BoolPreferenceKey.showCompletionGlow.rawValue)
        defer { UserDefaults.standard.removeObject(forKey: BoolPreferenceKey.showCompletionGlow.rawValue) }
        let state = ShowCompletionGlowState()
        #expect(!state.isEnabled, "initial value comes from the persisted preference")
        state.apply(false)
        #expect(
            !BoolPreferenceStore(
                defaults: .standard,
                key: BoolPreferenceKey.showCompletionGlow.rawValue,
                fallback: true).isEnabled,
            "apply persists into the preference store")
        #expect(!state.isEnabled, "apply republishes false through the state")
        state.apply(true)
        #expect(state.isEnabled, "apply republishes true through the state")
    }

    @Test(arguments: [
        ("--ui-testing-glow-disabled", false),
        ("--ui-testing-glow", true),
    ])
    func uiTestingGlowFlagsPreSetState(_ arg: (flag: String, expectedEnabled: Bool)) {
        // A persisted `false` from an earlier disabled-flow test in the same
        // UI-test session must not suppress the glow for the enabled-flow test.
        defer { UserDefaults.standard.removeObject(forKey: BoolPreferenceKey.showCompletionGlow.rawValue) }
        UserDefaults.standard.set(false, forKey: BoolPreferenceKey.showCompletionGlow.rawValue)
        let appViewModel = WatchAppViewModel(arguments: [arg.flag])
        #expect(
            appViewModel.showCompletionGlowState.isEnabled == arg.expectedEnabled,
            "\(arg.flag) forces the state \(arg.expectedEnabled ? "on" : "off")")
    }

    @Test
    func watchGateControlsGlowBasedOnState() async {
        defer { UserDefaults.standard.removeObject(forKey: BoolPreferenceKey.showCompletionGlow.rawValue) }

        // Disabled branch: the gate suppresses the glow so the disabled flow
        // needs no settings screen interference.
        let disabledState = ShowCompletionGlowState()
        disabledState.apply(false)
        let disabledViewModel = makeViewModel(glowState: disabledState)
        await disabledViewModel.completeCurrentReminder()
        #expect(
            !disabledViewModel.completionGlow.isActive,
            "gate suppresses the glow when the state is disabled")

        // Enabled branch: the gate lets the glow through.
        let enabledState = ShowCompletionGlowState()
        enabledState.apply(true)
        let enabledViewModel = makeViewModel(glowState: enabledState)
        await enabledViewModel.completeCurrentReminder()
        #expect(enabledViewModel.completionGlow.isActive, "gate triggers the glow when enabled")
    }

    // MARK: - Completion transition

    @Test
    func transitionFlagStartsFalse() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        #expect(!viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder == nil)
    }

    @Test
    func transitionFlagSetOnSuccessfulComplete() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        await viewModel.completeCurrentReminder()
        #expect(viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder != nil)
    }

    @Test
    func transitionFlagNotSetWhenGlowDisabled() async {
        let glowState = ShowCompletionGlowState()
        defer { UserDefaults.standard.removeObject(forKey: BoolPreferenceKey.showCompletionGlow.rawValue) }
        glowState.apply(false)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: glowState,
            entitlementState: EntitlementState())
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder == nil)
    }

    @Test
    func transitionFlagNotSetWhenNothingToComplete() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder == nil)
    }

    @Test
    func doubleTapIsNoOp() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        await viewModel.completeCurrentReminder()
        #expect(viewModel.isShowingCompletionTransition)
        // Second call while transition is active exits immediately.
        let wasActive = viewModel.completionGlow.isActive
        await viewModel.completeCurrentReminder()
        #expect(wasActive == viewModel.completionGlow.isActive, "Glow should not re-trigger on double-tap")
    }

    @Test
    func transitionFlagClearsAfterDelay() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        viewModel.completionGlow.duration = 0.05
        viewModel.completionTransitionBuffer = 0.01
        await viewModel.completeCurrentReminder()
        #expect(viewModel.isShowingCompletionTransition)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s > 0.05 + 0.01
        #expect(!viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder == nil)
    }

    @Test
    func transitionFlagClearsAfterDelayEvenWithNextReminder() async {
        // Two reminders: completing the first must NOT leave the ghost card
        // stuck on screen. After the glow + buffer delay the transition clears
        // and the surviving second reminder becomes the visible one, so the
        // user can keep completing without the app going unresponsive.
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder(), watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState())
        viewModel.completionGlow.duration = 0.05
        viewModel.completionTransitionBuffer = 0.01
        await viewModel.completeCurrentReminder()
        #expect(viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder != nil)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s > 0.05 + 0.01
        // The transition always ends after the glow; the next reminder is ready.
        #expect(!viewModel.isShowingCompletionTransition)
        #expect(viewModel.transitionReminder == nil)
        #expect(store.visibleReminders.count == 1)
    }

    // MARK: Private

    /// A fresh store + view model per call so a prior completion never leaks
    /// into the next branch of the gate test.
    private func makeViewModel(glowState: ShowCompletionGlowState) -> WatchReminderViewModel {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [watchReminder()],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        return WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: glowState,
            entitlementState: EntitlementState())
    }
}
