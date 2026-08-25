import EventKit
import SingleThreadCore
import SwiftUI
import WatchConnectivity

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--ui-testing")
        let store: ReminderStore = if isUITesting {
            Self.uiTestingStore(arguments: arguments)
        } else {
            ReminderStore(loadsReminders: true)
        }
        self.store = store
        // Restore the last-received sort (persisted to .standard on receive) so the
        // watch shows the correct order even before the next context push arrives.
        store.sortOption = SortOptionStore().load()
        // Restore the last-received show-undated preference the same way. Direct
        // assignment fires the didSet hook, which is unwired on the watch — no echo.
        store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).load()

        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore(),
                showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
                showDateStore: ShowDatePreference(defaults: .standard),
                showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
                showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
                sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false)
            service.onShowUndatedRemindersReceived = { [weak store] value in
                Task {
                    store?.showsUndatedReminders = value
                    await store?.reload()
                }
            }
            // A phone-side skip lands and applies to this watch's live list without a
            // relaunch — reload() re-reads the just-persisted skip store and prunes IDs
            // whose reminders no longer exist.
            service.onSkippedIdentifiersReceived = { [weak store] _ in
                Task { await store?.reload() }
            }
            service.onShowDateReceived = { [weak showDateState] value in showDateState?.apply(value) }
            service.onShowRecurrenceReceived = { [weak showRecurrenceState] value in showRecurrenceState?.apply(value) }
            service.onShowAlarmsReceived = { [weak showAlarmsState] value in showAlarmsState?.apply(value) }
            service.onSortOptionReceived = { [weak store] option in store?.setSortOption(option) }
            // A phone-side exclusion toggle arrives and re-filters this watch's live list.
            // Same write-once-before-activate invariant as onShowUndatedRemindersReceived.
            service.onExcludedListTitlesReceived = { [weak store] titles in
                store?.refreshExcludedListTitles(Set(titles))
            }
            service.activate()
            store.onSkipSetChanged = { _ in service.pushAll() }
            // Exclusions sync phone→watch only: nothing on watch edits exclusions, so no
            // push hook is wired here. The receive path above applies incoming exclusions.
            store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }

            // UI-test seam: delivers a real applicationContext through the WCSession
            // delegate entry point several seconds after launch, proving settings
            // apply live (no relaunch) end-to-end in SingleThreadWatchUITests.
            // Long enough that the seeded card has rendered first.
            if let index = arguments.firstIndex(of: "--ui-testing-live-excluded"),
               index + 1 < arguments.count {
                let list = arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    service.session(
                        WCSession.default,
                        didReceiveApplicationContext: ["excludedListTitles": [list]])
                }
            }
        }
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            WatchReminderView(
                store: store,
                showDateState: showDateState,
                showRecurrenceState: showRecurrenceState,
                showAlarmsState: showAlarmsState)
        }
    }

    // MARK: Private

    private let showDateState = ShowDateState()

    private let showRecurrenceState = ShowRecurrenceState()

    private let showAlarmsState = ShowAlarmsState()

    private let store: ReminderStore

    /// Builds a deterministic store for `--ui-testing` launches so a real reminder
    /// card presents without requesting EventKit access.
    private static func uiTestingStore(arguments: [String]) -> ReminderStore {
        let scratchStore = EKEventStore()
        let reminder = EKReminder(eventStore: scratchStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        // `--ui-testing-excluded-list "<list>"` gives the sample reminder a calendar
        // of that title and pre-populates the store's exclusion set, so an XCTest
        // can assert a list's current card is suppressed (the store's live exclusion
        // set drives the rendered result).
        // `--ui-testing-live-excluded "<list>"` gives the sample reminder a
        // calendar of that title but leaves the exclusion set empty, so the card
        // renders first and disappears only when the UI-test seam delivers the
        // exclusion context (live-propagation proof).
        for flag in ["--ui-testing-excluded-list", "--ui-testing-live-excluded"] {
            guard let index = arguments.firstIndex(of: flag),
                  index + 1 < arguments.count else { continue }
            let list = arguments[index + 1]
            let calendar = EKCalendar(for: .reminder, eventStore: scratchStore)
            calendar.title = list
            reminder.calendar = calendar
            let inMemoryStore = InMemoryEventStore(reminders: [reminder])
            return ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                excludedListTitles: flag == "--ui-testing-excluded-list" ? [list] : [])
        }
        let inMemoryStore = InMemoryEventStore(reminders: [reminder])
        return ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }
}
