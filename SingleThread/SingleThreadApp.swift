import SingleThreadCore
import SwiftUI
#if os(iOS)
    import UIKit
    import WatchConnectivity
#endif

@main
struct SingleThreadApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    // MARK: Lifecycle

    init() {
        let loads = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let store = ReminderStore(loadsReminders: loads)
        self.store = store

        #if os(iOS)
            if WCSession.isSupported() {
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: SkippedReminderStore())
                service.activate()
                service.onCompleteReminderReceived = { identifier in
                    Task { await store.completeReminder(identifier: identifier) }
                }
                store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }
                store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            }
        #endif
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }

    // MARK: Private

    private let store: ReminderStore
}
