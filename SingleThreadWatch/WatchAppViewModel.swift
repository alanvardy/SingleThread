import EventKit
import SingleThreadCore
import SwiftUI
import WatchConnectivity
import WidgetKit

/// Owns the watch composition root: building the ``ReminderStore`` from launch
/// arguments (with the `--ui-testing` seam), wiring the ``SkippedReminderSyncService``
/// hooks, and producing the root ``WatchReminderViewModel``.
@MainActor
final class WatchAppViewModel {
    // MARK: Lifecycle

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let isUITesting = arguments.contains("--ui-testing")
        let store: ReminderStore = if isUITesting {
            Self.uiTestingStore(arguments: arguments)
        } else {
            ReminderStore(loadsReminders: true)
        }
        self.store = store
        // --ui-testing-gated: seed the local completion counter at the cap so
        // `store.canMutate` is false and the freemium upgrade prompt renders.
        // The watch store's counter reads `AppGroup.defaults` (`UserDefaults
        // (suiteName:) ?? .standard`), so the seeded count must land in that
        // suite (it falls back to `.standard` where no App Group is registered).
        if arguments.contains("--ui-testing-gated") {
            AppGroup.defaults.set(EntitlementStore.freemiumCap, forKey: "completionCount")
        }
        // Restore the last-received sort (persisted to .standard on receive) so the
        // watch shows the correct order even before the next context push arrives.
        store.sortOption = SortOptionStore().load()
        // Restore the last-received show-undated preference the same way. Direct
        // assignment fires the didSet hook, which is unwired on the watch — no echo.
        store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).load()

        showDateState = ShowDateState()
        showRecurrenceState = ShowRecurrenceState()
        showAlarmsState = ShowAlarmsState()
        showListState = ShowListState()
        showCompletionGlowState = ShowCompletionGlowState()
        entitlementState = EntitlementState()

        // --ui-testing-glow-disabled: pre-disable the state so the disabled-flow
        // watch UI test doesn't need a settings screen. --ui-testing-glow:
        // force-enable so the enabled-flow test never inherits a `false` persisted
        // by an earlier disabled-flow test in the same UI-test session (both tests
        // relaunch the same app install, so UserDefaults carries across).
        if arguments.contains("--ui-testing-glow-disabled") {
            showCompletionGlowState.apply(false)
        } else if arguments.contains("--ui-testing-glow") {
            showCompletionGlowState.apply(true)
        }
        isGlowUITesting = arguments.contains("--ui-testing-glow")
        if isGlowUITesting {
            // UI-test seam: keep the glow visible long enough for a deterministic
            // `waitForExistence` assertion (production duration is 0.5 s).
            reminderViewModel.completionGlow.duration = 2.0
        }

        setupSyncService(arguments: arguments)
    }

    // MARK: Internal

    let store: ReminderStore
    let showDateState: ShowDateState
    let showRecurrenceState: ShowRecurrenceState
    let showAlarmsState: ShowAlarmsState
    let showListState: ShowListState
    let showCompletionGlowState: ShowCompletionGlowState
    let entitlementState: EntitlementState

    /// True when the `--ui-testing-glow` launch argument is present (watch
    /// completion-glow UI tests). The seam extends the glow duration to 2 s so
    /// `waitForExistence` is deterministic.
    let isGlowUITesting: Bool

    /// The root reminder view model. Stored — not rebuilt on every access — so
    /// the UI-test seam can extend the completion-glow duration on the same
    /// instance the view renders, and so `completeCurrentReminder()` state
    /// (including the gate on `showCompletionGlowState`) survives view body
    /// re-evaluations.
    lazy var reminderViewModel = WatchReminderViewModel(
        store: store,
        showDateState: showDateState,
        showRecurrenceState: showRecurrenceState,
        showAlarmsState: showAlarmsState,
        showListState: showListState,
        showCompletionGlowState: showCompletionGlowState,
        entitlementState: entitlementState)

    /// Static so the watch unit tests can drive it with an injected store + isolated
    /// mailbox defaults (mirrors WatchSyncPipelineTests' fake-session pattern).
    static func drainPendingReminderAction(
        store: ReminderStore,
        actionStore: PendingReminderActionStore = PendingReminderActionStore()) async {
        guard let action = actionStore.load() else { return }
        switch action.kind {
        case .complete:
            await store.completeReminder(identifier: action.identifier)
        case .skip:
            store.skipCurrentReminder()
        }
        actionStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Drains the widget-process mailbox on launch. The store's relay hooks are
    /// already wired in `setupSyncService`, so completing fires
    /// `onCompleteReminder` → `requestCompleteReminder`, and skipping fires
    /// `onSkipSetChanged` → `pushAll()`.
    func drainPendingReminderAction() async {
        await Self.drainPendingReminderAction(store: store)
    }

    // MARK: Private

    /// Builds a deterministic store for `--ui-testing` launches so a real reminder
    /// card presents without requesting EventKit access.
    private static func uiTestingStore(arguments: [String]) -> ReminderStore {
        let scratchStore = EKEventStore()
        let reminder = EKReminder(eventStore: scratchStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        // `--ui-testing-priority <n>` overrides the sample reminder's priority so a
        // watch UI test can assert the rendered priority marker. Parsed before the
        // excluded-list loop below (which returns early) so the override is not
        // silently dropped when combined with an excluded-list flag. Absent the
        // flag, the reminder keeps the default `5` (medium).
        if let index = arguments.firstIndex(of: "--ui-testing-priority"),
           index + 1 < arguments.count,
           let priority = Int(arguments[index + 1]) {
            reminder.priority = priority
        }
        // `--ui-testing-excluded-list "<list>"` gives the sample reminder a calendar
        // of that title and pre-populates the store's exclusion set, so an XCTest
        // can assert a list's current card is suppressed (the store's live exclusion
        // set drives the rendered result).
        // `--ui-testing-live-excluded "<list>"` gives the sample reminder a
        // calendar of that title but leaves the exclusion set empty, so the card
        // renders first and disappears only when the UI-test seam delivers the
        // exclusion context (live-propagation proof).
        for flag in ["--ui-testing-excluded-list", "--ui-testing-live-excluded"] {
            guard let index = arguments.firstIndex(of: flag),
                  index + 1 < arguments.count else { continue }
            let list = arguments[index + 1]
            let calendar = EKCalendar(for: .reminder, eventStore: scratchStore)
            calendar.title = list
            reminder.calendar = calendar
            let inMemoryStore = InMemoryEventStore(reminders: [reminder])
            return ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                excludedListTitles: flag == "--ui-testing-excluded-list" ? [list] : [])
        }
        let inMemoryStore = InMemoryEventStore(reminders: [reminder])
        return ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }

    /// Wires the WatchConnectivity sync service onto the store. Mirroring the
    /// previous app-level composition: the service is created once, its handlers
    /// are assigned before activation, and the `--ui-testing-live-excluded` seam
    /// delivers a real application context several seconds after launch.
    private func setupSyncService(arguments: [String]) {
        guard WCSession.isSupported() else { return }
        let store = store
        let service = SkippedReminderSyncService(
            session: WCSession.default,
            skipStore: SkippedReminderStore(),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
            showDateStore: ShowDatePreference(defaults: .standard),
            showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
            showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
            showListStore: ShowListPreference(defaults: .standard),
            showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard),
            completionCounter: CompletionCounterStore(defaults: .standard),
            entitlementStore: EntitlementStore(),
            sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false, sendsShowList: false,
            sendsShowCompletionGlow: false, sendsEntitled: false)
        service.onShowUndatedRemindersReceived = { [weak store] value in
            Task {
                store?.showsUndatedReminders = value
                await store?.reload()
            }
        }
        // A watchlist skip lands and applies to this watch's live list without a
        // relaunch — reload() re-reads the just-persisted skip store and prunes IDs
        // whose reminders no longer exist.
        service.onSkippedIdentifiersReceived = { [weak store] _ in
            Task { await store?.reload() }
        }
        wireStateReceiveHooks(service)
        service.onSortOptionReceived = { [weak store] option in
            Task { @MainActor in store?.setSortOption(option) }
        }
        // A phone-side completion-count push lands and becomes the watch's local
        // counter so `store.canMutate` gates on the phone's real lifetime count.
        // The store's counter reads `AppGroup.defaults`, so the received count is
        // persisted there (falling back to `.standard` when no App Group exists).
        service.onCompletionCountReceived = { count in
            AppGroup.defaults.set(count, forKey: "completionCount")
        }
        // A phone-side exclusion toggle arrives and re-filters this watch's live list.
        // Same write-before-activate invariant as shared onShowUndatedRemindersReceived.
        service.onExcludedListTitlesReceived = { [weak store] titles in
            Task { @MainActor in store?.refreshExcludedListTitles(Set(titles)) }
        }
        service.activate()
        store.onSkipSetChanged = { _ in service.pushAll() }
        // Exclusions sync phone→watch only: nothing on watch edits exclusions, so no
        // push hook is wired here. The receive path above applies incoming exclusions.
        store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
        store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
        scheduleUITestLiveExcludedDelivery(service: service, arguments: arguments)
    }

    /// Wires the show-* preference receive hooks onto the sync service. Each
    /// state holder is captured weakly so a delivered context cannot retain the VM.
    /// Lives in its own helper so `setupSyncService` stays within SwiftLint's
    /// 50-line function-body limit.
    private func wireStateReceiveHooks(_ service: SkippedReminderSyncService) {
        let showDateState = showDateState
        let showRecurrenceState = showRecurrenceState
        let showAlarmsState = showAlarmsState
        let showListState = showListState
        let showCompletionGlowState = showCompletionGlowState
        service.onShowDateReceived = { [weak showDateState] value in
            Task { @MainActor in showDateState?.apply(value) }
        }
        service.onShowRecurrenceReceived = { [weak showRecurrenceState] value in
            Task { @MainActor in showRecurrenceState?.apply(value) }
        }
        service.onShowAlarmsReceived = { [weak showAlarmsState] value in
            Task { @MainActor in showAlarmsState?.apply(value) }
        }
        service.onShowListReceived = { [weak showListState] value in
            Task { @MainActor in showListState?.apply(value) }
        }
        service.onShowCompletionGlowReceived = { [weak showCompletionGlowState] value in
            Task { @MainActor in showCompletionGlowState?.apply(value) }
        }
        let entitlementState = entitlementState
        service.onEntitlementReceived = { [weak entitlementState] value in
            Task { @MainActor in entitlementState?.apply(value) }
        }
    }

    /// Delivers a real applicationContext several seconds after launch when the
    /// `--ui-testing-live-excluded` flag is present, proving settings apply
    /// live (no relaunch) end-to-end in watch UI tests.
    private func scheduleUITestLiveExcludedDelivery(
        service: SkippedReminderSyncService,
        arguments: [String]) {
        if let index = arguments.firstIndex(of: "--ui-testing-live-excluded"),
           index + 1 < arguments.count {
            let list = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                service.session(
                    WCSession.default,
                    didReceiveApplicationContext: ["excludedListTitles": [list]])
            }
        }
    }
}
