import SingleThreadCore
import SwiftUI
#if os(iOS)
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
        let loads = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let store = ReminderStore(loadsReminders: loads)
        self.store = store
        store.sortOption = SortOptionStore().load()

        #if os(iOS)
            if WCSession.isSupported() {
                let skipStore = SkippedReminderStore()
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: skipStore)
                // Assign the handler before activating: the service documents a
                // write-once-before-activate invariant, and a completion message
                // delivered right after activation must not observe a nil (or an
                // unsynchronized) handler. `[weak store]` breaks the retain cycle
                // otherwise formed with the hooks below.
                service.onCompleteReminderReceived = { [weak store] identifier in
                    Task { await store?.completeReminder(identifier: identifier) }
                }
                service.activate()
                store.onSkipSetChanged = { ids in
                    service.push(ids, showUndatedReminders: store.showsUndatedReminders)
                }
                store.onShowUndatedRemindersChanged = { newValue in
                    service.push(skipStore.load(), showUndatedReminders: newValue)
                }
                store.onExcludedProjectsChanged = { titles in service.pushExcludedProjectTitles(titles) }
                store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            }
        #endif
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = {
                WidgetCenter.shared.reloadAllTimelines()
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

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif

    private let store: ReminderStore
}
