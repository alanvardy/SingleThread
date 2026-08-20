import EventKit
import SingleThreadCore
import SwiftUI
import WatchConnectivity

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let store: ReminderStore = if isUITesting {
            Self.uiTestingStore()
        } else {
            ReminderStore(loadsReminders: true)
        }
        self.store = store
        // Restore the last-received sort (persisted to .standard on receive) so the
        // watch shows the correct order even before the next context push arrives.
        store.sortOption = SortOptionStore().load()

        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore(),
                showDateStore: ShowDatePreference(defaults: .standard),
                sendsShowDate: false)
            service.onShowUndatedRemindersReceived = { [weak store] value in
                Task {
                    store?.showsUndatedReminders = value
                    await store?.reload()
                }
            }
            // Set before activate() — same write-once-before-activate invariant as
            // onCompleteReminderReceived.
            service.onSortOptionReceived = { [weak store] option in
                store?.setSortOption(option)
            }
            service.activate()
            store.onSkipSetChanged = { ids in
                service.push(ids, showUndatedReminders: store.showsUndatedReminders)
            }
            store.onExcludedProjectsChanged = { titles in service.pushExcludedProjectTitles(titles) }
            store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
        }
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            WatchReminderView(store: store)
        }
    }

    // MARK: Private

    private let store: ReminderStore

    /// Builds a deterministic store for `--ui-testing` launches so a real reminder
    /// card presents without requesting EventKit access.
    private static func uiTestingStore() -> ReminderStore {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }
}
