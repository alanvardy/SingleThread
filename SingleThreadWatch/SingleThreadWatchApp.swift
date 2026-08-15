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

        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore())
            service.activate()
            store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }
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

