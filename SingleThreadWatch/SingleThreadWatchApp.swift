import SingleThreadCore
import SwiftUI

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle

    init() {
        _store = State(initialValue: ReminderStore(
            loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing")))
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            WatchReminderView(store: store)
        }
    }

    // MARK: Private

    @State private var store: ReminderStore
}
