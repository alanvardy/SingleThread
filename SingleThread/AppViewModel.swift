import Foundation
import SingleThreadCore
import SwiftUI
#if os(iOS)
    import EventKit
    import WatchConnectivity
#endif
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

/// Owns the app's composition root: building the ``ReminderStore`` from launch
/// arguments, wiring the WatchConnectivity sync service and widget-timeline
/// reload hooks onto it, and producing the root ``ContentViewModel``.
@MainActor
@Observable
final class AppViewModel {
    // MARK: Lifecycle

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let (store, usesInMemory) = Self.makeStore(arguments: arguments)
        self.store = store
        usesInMemoryStore = usesInMemory
        store.sortOption = SortOptionStore().load()

        #if os(iOS)
            if WCSession.isSupported(), !usesInMemoryStore {
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: SkippedReminderStore(),
                    showDateStore: ShowDatePreference(),
                    showRecurrenceStore: ShowRecurrencePreference(),
                    showAlarmsStore: ShowAlarmsPreference(),
                    showCompletionGlowStore: ShowCompletionGlowPreference(),
                    entitlementStore: store.entitlementStore,
                    sendsShowDate: true,
                    sendsEntitled: true)
                // Assign the handler before activating: the service documents a
                // write-once-before-activate invariant, and a completion message
                // delivered right after activation must not observe a nil (or an
                // unsynchronized) handler. `[weak store]` breaks the retain cycle
                // otherwise formed with the hooks below.
                service.onCompleteReminderReceived = { [weak store] identifier in
                    Task { await store?.completeReminder(identifier: identifier) }
                }
                // Receive-side: a watch Delete arrives and is executed on the phone.
                service.onDeleteReminderReceived = { [weak store] identifier in
                    Task { await store?.deleteReminder(identifier: identifier) }
                }
                // Receive-side: a watch exclusion toggle arrives and re-filters the local list.
                service.onExcludedListTitlesReceived = { [weak store] titles in
                    Task { @MainActor in store?.refreshExcludedListTitles(Set(titles)) }
                }
                service.activate()
                syncService = service
                store.onSkipSetChanged = { _ in service.pushAll() }
                store.onShowUndatedRemindersChanged = { _ in service.pushAll() }
                store.onExcludedListsChanged = { _ in service.pushAll() }
                store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
                // Send-side (defensive/consistent): a phone-side delete relays to the
                // watch. The iPhone's `deleteReminder` never fires `onDeleteReminder`
                // (only the watchOS branch does), so this is inert on iOS but kept for
                // symmetry with the completion path.
                store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
                // The old sort push persisted the option itself; that responsibility
                // moves here so the pushed snapshot always matches what was just saved.
                store.onSortOptionChanged = { option in
                    SortOptionStore().save(option)
                    service.pushAll()
                }
            }
        #endif
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = {
                WidgetCenter.shared.reloadAllTimelines()
            }
        #endif

        backgroundImage = BackgroundImageStore()

        // Observe showDate/showRecurrence/showAlarms changes in AppGroup.defaults
        // so syncService.pushAll() fires without duplicating @AppStorage keys.
        #if os(iOS)
            setupSyncObservation()
            setupEntitlementObservation()
        #endif
    }

    // MARK: Internal

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let usesInMemoryStore: Bool
    #if os(iOS)
        private(set) var syncService: SkippedReminderSyncService?
    #endif

    /// The root view model. Rebuilt on demand so the view always reflects the
    /// latest store/background state.
    var contentViewModel: ContentViewModel {
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: backgroundImage,
            speechTranscriber: ReminderDictation())
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-glow") {
            // UI-test seam: keep the glow visible long enough for a
            // deterministic `exists` assertion (production duration is 0.25 s).
            viewModel.completionGlow.duration = 2.0
        }
        return viewModel
    }

    // MARK: Private

    /// Builds the app's ``ReminderStore`` from launch arguments.
    ///
    /// When a `--seed '<json>'` argument is present (UI tests), backs the store
    /// with an in-memory ``InMemoryEventStore`` seeded with reminders/calendars
    /// so complete/delete/add flows run deterministically without EventKit, and
    /// resets persisted UserDefaults so no state leaks between test launches.
    /// Otherwise falls back to the production EventKit-backed store (suppressing
    /// load for `--ui-testing`/`--no-reminders`).
    private static func makeStore(arguments: [String]) -> (store: ReminderStore, usesInMemory: Bool) {
        if let seed = UITestingSeed.fromLaunchArguments(arguments) {
            return (seededStore(seed), true)
        }
        #if os(iOS)
            // Mirrors the watch `--ui-testing` seam: a deterministic single-reminder
            // store so the reminder card presents without requesting EventKit access.
            // Also seeds the action-buttons toggle ON so the Complete/Skip cluster
            // renders for the interaction + accessibility-audit UI tests. The trade-off
            // (a persistent `.standard` value on the test simulator) is isolated to the
            // XCTest seam on a test-only destination.
            if arguments.contains("--ui-testing") {
                if arguments.contains("--reset-glow-preference") {
                    UserDefaults.standard.removeObject(forKey: "showCompletionGlow")
                }
                if arguments.contains("--reset-swipe-preference") {
                    UserDefaults.standard.removeObject(forKey: "showSwipePrompt")
                }
                UserDefaults.standard.set(true, forKey: "enableActionButtons")
                // Build the reminder through `InMemoryEventStore.makeReminder` so it is
                // backed by the store's persistent `EKEventStore`. A local `EKEventStore()`
                // would be deallocated when this scope exits, crashing any later reads of
                // the reminder with SIGTRAP.
                let inMemoryStore = InMemoryEventStore(
                    reminders: [],
                    calendars: [])
                let reminder = inMemoryStore.makeReminder(
                    title: "Buy groceries",
                    notes: "Don't forget the milk",
                    dueDate: nil,
                    recurrenceRule: nil)
                reminder.priority = 5
                return (ReminderStore(
                    eventStore: inMemoryStore,
                    loadsReminders: false,
                    reminders: [reminder],
                    skippedIDs: [],
                    authorizationStatus: .fullAccess), false)
            }
        #endif
        let loads = !arguments.contains("--ui-testing")
            && !arguments.contains("--no-reminders")
        return (ReminderStore(loadsReminders: loads), false)
    }

    /// Builds the store for a `--seed '<json>'` launch: an in-memory EventKit
    /// store seeded with the payload's reminders, the freemium counter written
    /// to the App Group key (or `.standard` fallback), and an entitlement store
    /// that reflects the seeded `isEntitled` flag.
    private static func seededStore(_ seed: UITestingSeed) -> ReminderStore {
        UITestingSeed.resetPersistedState()
        let inMemoryStore = InMemoryEventStore(
            reminders: seed.reminders,
            calendars: seed.calendars,
            defaultCalendar: seed.calendars.first)
        // Seed the freemium counter straight into the App Group (or, on
        // watchOS fallback, `.standard`) so `canMutate` reflects the seeded
        // cap. The counter store is read-only except `increment()`, so the
        // value is written before the store observes it.
        AppGroup.defaults.set(seed.completionCount, forKey: "completionCount")
        // Mirror the `--ui-testing` seam: enable the action-buttons toggle so
        // the Complete/Skip/Mic cluster (not just the mic) renders over a
        // visible reminder in seeded UI tests.
        UserDefaults.standard.set(true, forKey: "enableActionButtons")
        let entitlementStore = seed.isEntitled
            ? EntitlementStore(testingWithEntitled: true)
            : EntitlementStore()
        let store = ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: true,
            completionCounter: CompletionCounterStore(
                defaults: AppGroup.defaults,
                key: "completionCount"),
            entitlementStore: entitlementStore)
        if !seed.excludedListTitles.isEmpty {
            store.setExcludedListTitles(seed.excludedListTitles)
        }
        return store
    }

    #if os(iOS)
        /// Re-registers observation on the shared entitlement store so every
        /// `isEntitled` change pushes a fresh snapshot to the watch. This SDK's
        /// `withObservationTracking` returns `Void`, so re-registration happens
        /// by calling this helper again from the onChange callback.
        private func setupEntitlementObservation() {
            withObservationTracking {
                _ = store.entitlementStore.isEntitled
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.syncService?.pushAll()
                    self?.setupEntitlementObservation()
                }
            }
        }

        /// Observes `AppGroup.defaults` for showDate/showRecurrence/showAlarms
        /// changes and pushes a fresh snapshot to a paired watch. The token is
        /// stored so observation lives as long as the VM; NotificationCenter
        /// removes the observer when the token is deallocated. The `@Sendable`
        /// observer block hands off to MainActor so it can touch VM state.
        private func setupSyncObservation() {
            let center = NotificationCenter.default
            syncDefaultsObserver = center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: AppGroup.defaults,
                queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.handlePreferencesChanged()
                    }
                }
        }

        /// Compares the current App Group suite values against the last observed
        /// state and pushes a fresh snapshot to a paired watch when any changed.
        private func handlePreferencesChanged() {
            let currentShowDate = ShowDatePreference().isEnabled
            let currentShowRecurrence = ShowRecurrencePreference().isEnabled
            let currentShowAlarms = ShowAlarmsPreference().isEnabled
            let currentShowList = ShowListPreference().isEnabled
            let currentShowCompletionGlow = ShowCompletionGlowPreference().isEnabled
            if currentShowDate != lastShowDate
                || currentShowRecurrence != lastShowRecurrence
                || currentShowAlarms != lastShowAlarms
                || currentShowList != lastShowList
                || currentShowCompletionGlow != lastShowCompletionGlow {
                lastShowDate = currentShowDate
                lastShowRecurrence = currentShowRecurrence
                lastShowAlarms = currentShowAlarms
                lastShowList = currentShowList
                lastShowCompletionGlow = currentShowCompletionGlow
                syncService?.pushAll()
            }
        }

        /// Last-seen values from the App Group suite, used to detect changes.
        private var lastShowDate = ShowDatePreference().isEnabled
        private var lastShowRecurrence = ShowRecurrencePreference().isEnabled
        private var lastShowAlarms = ShowAlarmsPreference().isEnabled
        private var lastShowList = ShowListPreference().isEnabled
        private var lastShowCompletionGlow = ShowCompletionGlowPreference().isEnabled

        private var syncDefaultsObserver: NSObjectProtocol?
    #endif
}
