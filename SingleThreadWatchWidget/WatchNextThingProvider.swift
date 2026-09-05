import EventKit
import SingleThreadCore
import WidgetKit

// MARK: - Timeline entry

struct WatchNextThingEntry: TimelineEntry {
    let date: Date
    let state: ReminderWidgetState
}

// MARK: - Provider

struct WatchNextThingProvider: TimelineProvider {
    func placeholder(in _: Context) -> WatchNextThingEntry {
        WatchNextThingEntry(date: Date(), state: .reminder(ReminderDisplay(title: "Next thing")))
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (WatchNextThingEntry) -> Void) {
        completion(
            WatchNextThingEntry(date: Date(), state: .reminder(ReminderDisplay(title: "Buy groceries"))))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<WatchNextThingEntry>) -> Void) {
        Task { @MainActor in
            let store = ReminderStore(loadsReminders: true)
            store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
            store.setSortOption(SortOptionStore().load())
            let state = await ReminderWidgetState.makeWidgetState(
                store: store,
                authorization: EKEventStore.authorizationStatus(for: .reminder))
            let refresh = Date().addingTimeInterval(15 * 60)
            completion(
                Timeline(
                    entries: [WatchNextThingEntry(date: Date(), state: state)],
                    policy: .after(refresh)))
        }
    }
}
