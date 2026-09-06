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
        Self.registerDefaults()

        backgroundImage = BackgroundImageStore()

        #if os(iOS)
            setupSyncService(with: store)
        #endif
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = { [weak self] in
                WidgetCenter.shared.reloadAllTimelines()
                #if os(macOS)
                Task { @MainActor in
                    await self?.scheduleNotificationsForMacOS()
                }
                #endif
            }
        #endif

        // Observe showDate/showRecurrence/showAlarms changes in AppGroup.defaults
        // so syncService.pushAll() fires without duplicating @AppStorage keys.
        #if os(iOS)
            setupSyncObservation()
            setupEntitlementObservation()
        #endif
    }

    // MARK: Internal

    #if os(iOS)
        /// Notification-preference UserDefaults keys, shared between
        /// AppViewModel reads and the @AppStorage declarations in ContentView.
        enum NotificationKeys {
            static let enabled = "notificationsEnabled"
            static let intervalHours = "notificationIntervalHours"
        }

        /// Current pending notification requests, rendered as a stable status
        /// string ONLY under the UI-test flag. Delegates to the scheduler.
        var pendingSummary: String? {
            notificationScheduler.pendingSummary
        }

        /// What was most recently SCHEDULED (survives cancel / foreground).
        /// Present only if a request was actually added this cycle.
        var lastScheduleSummary: String? {
            notificationScheduler.lastScheduleSummary
        }

        /// Schedules a single local notification if the feature is enabled and
        /// reminders are pending. Always removes existing requests first
        /// (including stale requests from a previous schedule cycle), so only
        /// one notification is ever scheduled.
        func scheduleNotificationIfNeeded() async {
            await notificationScheduler.scheduleIfNeeded(
                reminderCount: store.visibleReminders.count,
                hasHidden: store.hasHidden)
        }

        /// Cancels all pending local notifications and refreshes the seam.
        func cancelNotifications() async {
            await notificationScheduler.cancelAll()
        }

        /// Requests notification authorization (.alert + .badge).
        /// No-op if already determined (granted or denied).
        ///
        /// When authorization is denied by the user (or the request throws),
        /// flips `notificationsEnabled` back to `false` so the UI toggle
        /// reflects reality — notifications can never fire under `.denied`.
        func requestNotificationPermissionIfNeeded() async {
            await notificationScheduler.requestPermissionIfNeeded()
        }
    #endif

    #if os(macOS)
        /// Schedules (or cancels) the macOS idle-reminder notification on every
        /// reminders change — which also fires at launch, since `start()` →
        /// `reload()` ends with `onRemindersChanged`. macOS has no in-app
        /// notifications toggle, so the enabled key defaults to on (registered
        /// in `registerDefaults`); permission is requested lazily, at most once
        /// (self-guards on `.notDetermined`), and only when something is due.
        /// Cancellation when nothing is due lives in `NotificationScheduler`.
        private func scheduleNotificationsForMacOS() async {
            if store.visibleReminders.count > 0 || store.hasHidden {
                await notificationScheduler.requestPermissionIfNeeded()
            }
            await notificationScheduler.scheduleIfNeeded(
                reminderCount: store.visibleReminders.count,
                hasHidden: store.hasHidden)
        }
    #endif

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let usesInMemoryStore: Bool
    /// Schedules / cancels the idle-notification reminder against the real
    /// `UNUserNotificationCenter` through the `UserNotificationCentering` seam.
    /// Shared by the iOS toggle-driven wrappers and the macOS scheduling trigger.
    let notificationScheduler = NotificationScheduler()
    #if os(iOS)
        private(set) var syncService: SkippedReminderSyncService?
    #endif

    /// Registers fallback `UserDefaults` values for keys whose offline default is
    /// not `false`. `@AppStorage` initializers are invisible to raw
    /// `bool(forKey:)` reads, so registration removes the silent divergence.
    /// Also runs one-time storage migrations: `enableActionButtons` moved from
    /// `.standard` to `AppGroup.defaults` (shared with the watch), and existing
    /// users' value is copied over once; fresh installs stay default-off.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["showMicrophoneButton": true])
        #if os(macOS)
            // macOS has no in-app notifications toggle, so the scheduler's
            // enabled key defaults to on; a denied macOS permission prompt
            // still flips it off and stops future scheduling (iOS keeps its
            // toggle-driven default).
            UserDefaults.standard.register(defaults: ["notificationsEnabled": true])
        #endif
        if UserDefaults.standard.object(forKey: "enableActionButtons") != nil,
           AppGroup.defaults.object(forKey: "enableActionButtons") == nil {
            AppGroup.defaults.set(
                UserDefaults.standard.bool(forKey: "enableActionButtons"),
                forKey: "enableActionButtons")
        }
    }

    /// Builds an App Group–backed store for one of the synced show-* preferences:
    /// each is a `BoolPreferenceStore` under its named key with the fallback the
    /// old concrete `Show*Preference` types encoded (date/recurrence/alarms/glow
    /// default true; list/undated default false). Kept in one place so the
    /// sync-service wiring stays compact.
    static func showPreferenceStore(
        _ key: BoolPreferenceKey, fallback: Bool) -> BoolPreferenceStore {
        BoolPreferenceStore(key: key.rawValue, fallback: fallback)
    }

    /// The root view model. Rebuilt on demand so the view always reflects the
    /// latest store/background state.
    ///
    /// The scene's live `OpenURLAction` is threaded in so the "View in
    /// Reminders" deep link opens the real Reminders app in production. Under
    /// the `--url-opener-spy` UI-test seam the spy takes precedence and records
    /// the URL without opening anything, and the shared spy is stored back so
    /// `ContentView` can render it for an XCUITest assertion.
    func makeContentViewModel(openURLAction: OpenURLAction? = nil) -> ContentViewModel {
        // The `urlOpener` is chosen by launch-mode: the `--url-opener-spy` UI-test
        // seam reuses a single shared spy (so the view can read the last URL
        // back), otherwise the scene's live `OpenURLAction` is wrapped, with a
        // no-op fallback for previews and unit-test call sites that pass neither.
        let urlOpener: any URLOpening
        if isURLSpyUITesting {
            if let spy = urlOpenerSpy {
                urlOpener = spy
            } else {
                let freshSpy = URLOpeningSpy()
                urlOpenerSpy = freshSpy
                urlOpener = freshSpy
            }
        } else if let openURLAction {
            urlOpener = SystemURLOpener(action: openURLAction)
        } else {
            urlOpener = SystemURLOpener.noop
        }
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: backgroundImage,
            speechTranscriber: ReminderDictation(),
            urlOpener: urlOpener)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-glow") {
            // UI-test seam: keep the glow visible long enough for a
            // deterministic `exists` assertion (production duration is 0.50 s).
            viewModel.completionGlow.duration = 2.0
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduced-glow") {
            // UI-test seam: shorten the glow (production duration is 0.50 s)
            // so UI tests spend less wall-clock time on the overlay.
            viewModel.completionGlow.duration = 0.1
        }
        return viewModel
    }

    // MARK: Private

    /// The `--url-opener-spy` UI-test seam's shared spy. Reused across
    /// `makeContentViewModel` calls so the view and view model share one
    /// recording (and so `ContentView` can read the last opened URL back).
    /// Always nil in production (the spy launch arg is absent).
    private var urlOpenerSpy: URLOpeningSpy?

    /// True only under the `--url-opener-spy` UI-test seam; production opens
    /// real deep links through the scene's `OpenURLAction` instead.
    private var isURLSpyUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--url-opener-spy")
    }

    /// Builds the app's ``ReminderStore`` from launch arguments.
    ///
    /// When a `--seed '<json>'` argument is present (UI tests), backs the store
    /// with an in-memory ``InMemoryEventStore`` seeded with reminders/calendars
    /// so complete/delete/add flows run deterministically without EventKit, and
    /// resets persisted UserDefaults so no state leaks between test launches.
    /// Otherwise falls back to the production EventKit-backed store (suppressing
    /// load for `--ui-testing`/`--no-reminders`).
    private static func makeStore(arguments: [String]) -> (store: ReminderStore, usesInMemory: Bool) {
        let useNoopSettle = arguments.contains("--ui-testing-noop-settle")
        if let seed = UITestingSeed.fromLaunchArguments(arguments) {
            return (seededStore(seed, useNoopSettle: useNoopSettle), true)
        }
        #if os(iOS)
            // Mirrors the watch `--ui-testing` seam: a deterministic single-reminder
            // store so the reminder card presents without requesting EventKit access.
            // Also seeds the action-buttons toggle ON so the Complete/Skip cluster
            // renders for the interaction + accessibility-audit UI tests. The trade-off
            // (a persistent App Group suite value on the test simulator) is isolated to
            // the XCTest seam on a test-only destination.
            if arguments.contains("--ui-testing") {
                if arguments.contains("--reset-glow-preference") {
                    UserDefaults.standard.removeObject(forKey: "showCompletionGlow")
                }
                if arguments.contains("--reset-swipe-preference") {
                    UserDefaults.standard.removeObject(forKey: "showSwipePrompt")
                }
                AppGroup.defaults.set(true, forKey: "enableActionButtons")
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
                // `--ui-testing-noop-settle` skips EventKit's 200ms post-save
                // settle so write-flow UI tests run deterministically and fast.
                // Without the flag the init default (production 200ms timing)
                // is left in place, so the relaunch-persistence trio that
                // launches via `--ui-testing` still exercises the real settle.
                if useNoopSettle {
                    return (ReminderStore(
                        eventStore: inMemoryStore,
                        loadsReminders: false,
                        reminders: [reminder],
                        skippedIDs: [],
                        authorizationStatus: .fullAccess,
                        entitlementStore: EntitlementStore(testingWithEntitled: false)) {}, false)
                }
                return (ReminderStore(
                    eventStore: inMemoryStore,
                    loadsReminders: false,
                    reminders: [reminder],
                    skippedIDs: [],
                    authorizationStatus: .fullAccess,
                    entitlementStore: EntitlementStore(testingWithEntitled: false)), false)
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
    ///
    /// The counter write is deliberately unclamped: production only writes
    /// `count + 1`, `max(0, count - 1)`, or `0` (see ``CompletionCounterStore``),
    /// but the seed accepts any `Int` so UI tests can stage the free-tier gate
    /// (99 = near-cap, 100 = gated) that production never produces. Gating
    /// scenarios seeded here drive `canMutate` exactly as the real counter does.
    private static func seededStore(_ seed: UITestingSeed, useNoopSettle: Bool) -> ReminderStore {
        UITestingSeed.resetPersistedState()
        let inMemoryStore = InMemoryEventStore(
            reminders: seed.reminders,
            calendars: seed.calendars,
            defaultCalendar: seed.calendars.first)
        // Seed the freemium counter straight into the App Group (or, on
        // watchOS fallback, `.standard`) so `canMutate` reflects the seeded
        // cap. The counter store is read-only except `increment()`, so the
        // value is written before the store observes it. Unlike production
        // writes (count+1 / max(0, count-1) / 0 — see CompletionCounterStore),
        // the seed value is intentionally unclamped: gating scenarios seed 99
        // (near-cap) and 100 (gated), both values production never produces.
        AppGroup.defaults.set(seed.completionCount, forKey: "completionCount")
        // Preload the skip counts so a seeded test reaches the 6th-skip nudge
        // with one tap (seed `skipCounts` at 5). The store's `SkipCountStore`
        // reads `AppGroup.defaults`, falling back to `.standard` on watchOS.
        AppGroup.defaults.set(seed.skipCountsByIdentifier, forKey: "skipCounts")
        // Mirror the `--ui-testing` seam: enable the action-buttons toggle so
        // the Complete/Skip/Mic cluster (not just the mic) renders over a
        // visible reminder in seeded UI tests.
        AppGroup.defaults.set(true, forKey: "enableActionButtons")
        let entitlementStore = if seed.entitlementUnresolved {
            EntitlementStore(testingWithEntitlementUnresolved: ())
        } else if seed.isEntitled {
            EntitlementStore(testingWithEntitled: true)
        } else {
            EntitlementStore(testingWithEntitled: false)
        }
        // An empty + hidden seed must keep the store exactly as initialized:
        // with `loadsReminders: true`, `start()` → `reload()` recomputes
        // `hasHidden` from the broad fetch, and `InMemoryEventStore` returns the
        // same list for narrow and broad fetches — resetting `hasHidden` to false.
        let emptyWithHidden = seed.reminders.isEmpty && seed.hasHidden
        // `--ui-testing-noop-settle` skips EventKit's 200ms post-save settle
        // for deterministic seeded write flows; absent the flag the init
        // default (production 200ms timing) applies.
        let store = if useNoopSettle {
            ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: !emptyWithHidden,
                hasHidden: seed.hasHidden,
                completionCounter: CompletionCounterStore(
                    defaults: AppGroup.defaults,
                    key: "completionCount"),
                entitlementStore: entitlementStore) {}
        } else {
            ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: !emptyWithHidden,
                hasHidden: seed.hasHidden,
                completionCounter: CompletionCounterStore(
                    defaults: AppGroup.defaults,
                    key: "completionCount"),
                entitlementStore: entitlementStore)
        }
        if !seed.excludedListTitles.isEmpty {
            store.setExcludedListTitles(seed.excludedListTitles)
        }
        return store
    }

    #if os(iOS)
        /// Wires the WatchConnectivity sync service onto the store: creates the
        /// service, assigns its receive-side handlers before activation, and hooks
        /// the store's mutation events back onto the service. Skipped for in-memory
        /// (UI-test) stores — there is no paired device in the test harness.
        private func setupSyncService(with store: ReminderStore) {
            guard WCSession.isSupported(), !usesInMemoryStore else { return }
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore(),
                showDateStore: Self.showPreferenceStore(.showDate, fallback: true),
                showRecurrenceStore: Self.showPreferenceStore(.showRecurrence, fallback: true),
                showAlarmsStore: Self.showPreferenceStore(.showAlarms, fallback: true),
                showCompletionGlowStore: Self.showPreferenceStore(.showCompletionGlow, fallback: true),
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
            // Receive-side: a watch Reschedule arrives and is executed on the phone.
            service.onRescheduleReminderReceived = { [weak store] identifier, components in
                Task { await store?.rescheduleReminder(identifier: identifier, to: components) }
            }
            // Receive-side: a watch exclusion toggle arrives and re-filters the local list.
            service.onExcludedListTitlesReceived = { [weak store] titles in
                Task { @MainActor in store?.refreshExcludedListTitles(Set(titles)) }
            }
            // A watch skip-count map lands and applies via reload (authoritative save).
            service.onSkipCountsReceived = { [weak store] _ in Task { @MainActor in await store?.reload() } }
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
            let currentShowDate = BoolPreferenceStore(
                key: BoolPreferenceKey.showDate.rawValue, fallback: true).isEnabled
            let currentShowRecurrence = BoolPreferenceStore(
                key: BoolPreferenceKey.showRecurrence.rawValue,
                fallback: true).isEnabled
            let currentShowAlarms = BoolPreferenceStore(
                key: BoolPreferenceKey.showAlarms.rawValue,
                fallback: true).isEnabled
            let currentShowList = BoolPreferenceStore(
                key: BoolPreferenceKey.showList.rawValue,
                fallback: false).isEnabled
            let currentShowCompletionGlow = BoolPreferenceStore(
                key: BoolPreferenceKey.showCompletionGlow.rawValue,
                fallback: true).isEnabled
            let currentEnableActionButtons = AppGroup.defaults.bool(forKey: "enableActionButtons")
            if currentShowDate != lastShowDate
                || currentShowRecurrence != lastShowRecurrence
                || currentShowAlarms != lastShowAlarms
                || currentShowList != lastShowList
                || currentShowCompletionGlow != lastShowCompletionGlow
                || currentEnableActionButtons != lastEnableActionButtons {
                lastShowDate = currentShowDate
                lastShowRecurrence = currentShowRecurrence
                lastShowAlarms = currentShowAlarms
                lastShowList = currentShowList
                lastShowCompletionGlow = currentShowCompletionGlow
                lastEnableActionButtons = currentEnableActionButtons
                syncService?.pushAll()
            }
        }

        /// Last-seen values from the App Group suite, used to detect changes.
        private var lastShowDate = BoolPreferenceStore(
            key: BoolPreferenceKey.showDate.rawValue,
            fallback: true).isEnabled
        private var lastShowRecurrence = BoolPreferenceStore(
            key: BoolPreferenceKey.showRecurrence.rawValue,
            fallback: true).isEnabled
        private var lastShowAlarms = BoolPreferenceStore(
            key: BoolPreferenceKey.showAlarms.rawValue,
            fallback: true).isEnabled
        private var lastShowList = BoolPreferenceStore(
            key: BoolPreferenceKey.showList.rawValue,
            fallback: false).isEnabled
        private var lastShowCompletionGlow = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionGlow.rawValue,
            fallback: true).isEnabled
        private var lastEnableActionButtons = AppGroup.defaults.bool(forKey: "enableActionButtons")

        private var syncDefaultsObserver: NSObjectProtocol?
    #endif
}
