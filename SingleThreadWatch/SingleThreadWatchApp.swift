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
            Self.uiTestingStore(arguments: ProcessInfo.processInfo.arguments)
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
            // A phone-side exclusion toggle arrives and re-filters this watch's live list.
            // Same write-once-before-activate invariant as onShowUndatedRemindersReceived.
            service.onExcludedProjectTitlesReceived = { [weak store] titles in
                store?.refreshExcludedProjectTitles(Set(titles))
            }
            service.activate()
            store.onSkipSetChanged = { _ in service.pushAll() }
            store.onExcludedProjectsChanged = { _ in service.pushAll() }
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
    private static func uiTestingStore(arguments: [String]) -> ReminderStore {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        // `--ui-testing-excluded "<project>"` gives the sample reminder a calendar of
        // that title and pre-populates the store's exclusion set, so an XCTest can
        // assert a project's current card is suppressed (the store's live exclusion
        // set drives the rendered result).
        if let index = arguments.firstIndex(of: "--ui-testing-excluded"),
           index + 1 < arguments.count {
            let project = arguments[index + 1]
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = project
            reminder.calendar = calendar
            return ReminderStore(
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                excludedProjectTitles: [project])
        }
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }
}
