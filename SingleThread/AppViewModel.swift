import Foundation
import SingleThreadCore
import SwiftUI
#if os(iOS)
    import EventKit
    import UserNotifications
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

    #if os(iOS)
        /// Notification-preference UserDefaults keys, shared between
        /// AppViewModel reads and the @AppStorage declarations in ContentView.
        enum NotificationKeys {
            static let enabled = "notificationsEnabled"
            static let intervalHours = "notificationIntervalHours"
        }

        /// The single pending notification-request identifier — stable across
        /// schedules so each cycle replaces the previous one.
        static let idleReminderIdentifier = "app.alanvardy.SingleThread.idle-reminder"

        /// Current pending notification requests, rendered as a stable status
        /// string ONLY under the UI-test flag (see below). Updated on the
        /// schedule (before guards and after add) and cancel paths.
        private(set) var pendingSummary: String?

        /// What was most recently SCHEDULED (survives cancel / foreground).
        /// Present only if a request was actually added this cycle.
        private(set) var lastScheduleSummary: String?

        /// Schedules a single local notification if the feature is enabled and
        /// reminders are pending. Always removes existing requests first
        /// (including stale requests from a previous schedule cycle), so only
        /// one notification is ever scheduled.
        func scheduleNotificationIfNeeded() async {
            await refreshPendingSummary()

            // Always clear stale requests before checking whether to schedule
            // new ones — a previous schedule left a pending request that will
            // fire unless we cancel it now.
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()

            guard UserDefaults.standard.bool(forKey: NotificationKeys.enabled) else { return }
            let count = store.visibleReminders.count
            guard count > 0 || store.hasHidden else { return }

            let intervalHours = UserDefaults.standard.integer(forKey: NotificationKeys.intervalHours)
            let effectiveHours = intervalHours > 0 ? intervalHours : 48

            let content = UNMutableNotificationContent()
            content.title = String(localized: "SingleThread", table: "Localizable", bundle: .main)
            content.body = String(
                localized: "You have \(count) reminders waiting — open SingleThread!",
                table: "Localizable",
                bundle: .main)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Double(effectiveHours * 3600),
                repeats: false)

            let request = UNNotificationRequest(
                identifier: Self.idleReminderIdentifier,
                content: content,
                trigger: trigger)

            do {
                try await center.add(request)
                await refreshPendingSummary()
                lastScheduleSummary = Self.summary(requests: [request])
            } catch {
                // Silently skip — the user won't get reminded this cycle.
                // The next background transition will retry.
                lastScheduleSummary = nil
            }
        }

        /// Cancels all pending local notifications and refreshes the seam.
        func cancelNotifications() async {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            await refreshPendingSummary()
        }

        /// Requests notification authorization (.alert + .badge).
        /// No-op if already determined (granted or denied).
        ///
        /// When authorization is denied by the user (or the request throws),
        /// flips `notificationsEnabled` back to `false` so the UI toggle
        /// reflects reality — notifications can never fire under `.denied`.
        func requestNotificationPermissionIfNeeded() async {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted: Bool
                do {
                    granted = try await center.requestAuthorization(options: [.alert, .badge])
                } catch {
                    UserDefaults.standard.set(false, forKey: NotificationKeys.enabled)
                    return
                }
                if !granted {
                    UserDefaults.standard.set(false, forKey: NotificationKeys.enabled)
                }
            default:
                break
            }
        }
    #endif

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let usesInMemoryStore: Bool
    #if os(iOS)
        private(set) var syncService: SkippedReminderSyncService?
    #endif

    /// Registers fallback `UserDefaults` values for keys whose offline default is
    /// not `false`. `@AppStorage` initializers are invisible to raw
    /// `bool(forKey:)` reads, so registration removes the silent divergence.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["showMicrophoneButton": true])
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
                    UserDefaults.standard.removeObject(forKey: ShowCompletionGlowPreference.defaultsKey)
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
    private static func seededStore(_ seed: UITestingSeed) -> ReminderStore {
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
        AppGroup.defaults.set(seed.completionCount, forKey: CompletionCounterStore.defaultsKey)
        // Preload the skip counts so a seeded test reaches the 6th-skip nudge
        // with one tap (seed `skipCounts` at 5). The store's `SkipCountStore`
        // reads `AppGroup.defaults`, falling back to `.standard` on watchOS.
        AppGroup.defaults.set(seed.skipCountsByIdentifier, forKey: SkipCountStore.defaultsKey)
        // Mirror the `--ui-testing` seam: enable the action-buttons toggle so
        // the Complete/Skip/Mic cluster (not just the mic) renders over a
        // visible reminder in seeded UI tests.
        UserDefaults.standard.set(true, forKey: "enableActionButtons")
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
        let store = ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: !emptyWithHidden,
            hasHidden: seed.hasHidden,
            completionCounter: CompletionCounterStore(
                defaults: AppGroup.defaults,
                key: CompletionCounterStore.defaultsKey),
            entitlementStore: entitlementStore)
        if !seed.excludedListTitles.isEmpty {
            store.setExcludedListTitles(seed.excludedListTitles)
        }
        return store
    }

    #if os(iOS)
        /// Refreshes `pendingSummary` from the notification center, but only
        /// when the UI-test seam flag is present so production never incurs the
        /// query or exposes the status.
        private func refreshPendingSummary() async {
            guard ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications") else { return }
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            pendingSummary = Self.summary(requests: requests)
        }

        /// Renders a pending-notification snapshot as a stable key=value
        /// status string for the UI-test seam.
        private static func summary(requests: [UNNotificationRequest]) -> String {
            guard let first = requests.first else { return "count=0" }
            let interval = (first.trigger as? UNTimeIntervalNotificationTrigger)
                .map { Int($0.timeInterval.rounded()) } ?? -1
            return "count=\(requests.count)\nid=\(first.identifier)\nbody=\(first.content.body)\ninterval=\(interval)"
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
