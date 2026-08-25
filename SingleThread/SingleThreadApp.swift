import Foundation
import SingleThreadCore
import SwiftUI
#if os(iOS)
    import EventKit
    import UIKit
    import WatchConnectivity
#endif
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

@main
struct SingleThreadApp: App {
    // MARK: Lifecycle

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let (store, usesInMemory) = Self.makeStore(arguments: arguments)
        self.store = store
        usesInMemoryStore = usesInMemory
        store.sortOption = SortOptionStore().load()

        #if os(iOS)
            if WCSession.isSupported(), !usesInMemoryStore {
                let skipStore = SkippedReminderStore()
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: skipStore,
                    showDateStore: ShowDatePreference(),
                    sendsShowDate: true)
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
                    store?.refreshExcludedListTitles(Set(titles))
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
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, backgroundImage: backgroundImage)
            #if os(iOS)
                .onChange(of: showDate) { _, _ in
                    // @AppStorage has already written the App Group suite;
                    // pushAll() snapshots it via ShowDatePreference().
                    syncService?.pushAll()
                }
            #endif
        }
    }

    // MARK: Private

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate

        private var syncService: SkippedReminderSyncService?
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif

    @AppStorage("showDate", store: AppGroup.defaults)
    private var showDate = true

    private let store: ReminderStore
    private let usesInMemoryStore: Bool
    private let backgroundImage: BackgroundImageStore

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
            UITestingSeed.resetPersistedState()
            let inMemoryStore = InMemoryEventStore(
                reminders: seed.reminders,
                calendars: seed.calendars)
            let store = ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: true)
            if !seed.excludedListTitles.isEmpty {
                store.setExcludedListTitles(seed.excludedListTitles)
            }
            return (store, true)
        }
        #if os(iOS)
            // Mirrors the watch `--ui-testing` seam: a deterministic single-reminder
            // store so the reminder card presents without requesting EventKit access.
            // Also seeds the action-buttons toggle ON so the Complete/Skip cluster
            // renders for the interaction + accessibility-audit UI tests. The trade-off
            // (a persistent `.standard` value on the test simulator) is isolated to the
            // XCTest seam on a test-only destination.
            if arguments.contains("--ui-testing") {
                UserDefaults.standard.set(true, forKey: "enableActionButtons")
                let eventStore = EKEventStore()
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = "Buy groceries"
                reminder.priority = 5
                reminder.notes = "Don't forget the milk"
                return (ReminderStore(
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
}
