import SingleThreadCore
import SwiftUI
import WatchConnectivity

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle

    init() {
        let store = ReminderStore(
            loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        self.store = store
        // Restore the last-received sort (persisted to .standard on receive) so the
        // watch shows the correct order even before the next context push arrives.
        store.sortOption = SortOptionStore().load()

        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore())
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
}
