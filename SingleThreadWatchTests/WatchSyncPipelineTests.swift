import EventKit
import SingleThreadCore
import Testing
import WatchConnectivity

// MARK: - Fake session for testing

/// Private copy of the iOS suite's fake — it cannot be imported across test bundles.
private final class WatchFakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var pushShouldThrow = false

    func activate() {
        activated = true
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow {
            throw NSError(domain: "test", code: 1)
        }
        lastContext = applicationContext
    }

    func sendMessage(
        _: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler _: ((any Error) -> Void)?) {}
}

/// Watch-target compilation of the sync pipeline plus the Phase 1–3 behaviors,
/// asserted natively on watchOS where the iOS-side bundle cannot run.
@MainActor
struct WatchSyncPipelineTests {
    @Test
    func pushAllFromWatchOmitsShowDate() throws {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-skip-\(suffix)")
        skipStore.save(["A"])
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: skipStore,
            excludeStore: ExcludedListStore(defaults: .standard, key: "wtest-push-excl-\(suffix)"),
            sortStore: SortOptionStore(defaults: .standard, key: "wtest-push-sort-\(suffix)"),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-push-und-\(suffix)"),
            showDateStore: ShowDatePreference(defaults: .standard, key: "wtest-push-date-\(suffix)"),
            sendsShowDate: false)
        service.pushAll()
        let context = try #require(fake.lastContext)
        #expect(context["showDate"] == nil)
        #expect(context["skippedReminderIdentifiers"] != nil)
        #expect(context["excludedListTitles"] != nil)
        #expect(context["showUndatedReminders"] != nil)
        #expect(context["sortOption"] != nil)
    }

    @Test
    func receiveAppliesEveryPresentKey() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-all-skip-\(suffix)")
        let excludeStore = ExcludedListStore(defaults: .standard, key: "wtest-all-excl-\(suffix)")
        let showUndatedStore = ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-all-und-\(suffix)")
        let sortStore = SortOptionStore(defaults: .standard, key: "wtest-all-sort-\(suffix)")
        let showDateStore = ShowDatePreference(defaults: .standard, key: "wtest-all-date-\(suffix)")
        showDateStore.set(true)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: skipStore,
            excludeStore: excludeStore,
            sortStore: sortStore,
            showUndatedStore: showUndatedStore,
            showDateStore: showDateStore)

        var skips: [[String]] = []
        var titles: [[String]] = []
        var undated: [Bool] = []
        var sorts: [SortOption] = []
        var showDates: [Bool] = []
        service.onSkippedIdentifiersReceived = { skips.append($0) }
        service.onExcludedListTitlesReceived = { titles.append($0) }
        service.onShowUndatedRemindersReceived = { undated.append($0) }
        service.onSortOptionReceived = { sorts.append($0) }
        service.onShowDateReceived = { showDates.append($0) }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: [
                "skippedReminderIdentifiers": ["R1", "R2"],
                "excludedListTitles": ["Work"],
                "showUndatedReminders": true,
                "sortOption": "dueDate",
                "showDate": false
            ])

        #expect(Set(skipStore.load()) == ["R1", "R2"])
        #expect(excludeStore.load() == ["Work"])
        #expect(showUndatedStore.load())
        #expect(sortStore.load() == .dueDate)
        #expect(!showDateStore.isEnabled)
        #expect(skips == [["R1", "R2"]])
        #expect(titles == [["Work"]])
        #expect(undated == [true])
        #expect(sorts == [.dueDate])
        #expect(showDates == [false])
    }

    @Test
    func receiveAbsentKeysAreNoOps() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let excludeStore = ExcludedListStore(defaults: .standard, key: "wtest-absent-excl-\(suffix)")
        excludeStore.save(["KeepMe"])
        let showUndatedStore = ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-absent-und-\(suffix)")
        showUndatedStore.save(false)
        let sortStore = SortOptionStore(defaults: .standard, key: "wtest-absent-sort-\(suffix)")
        sortStore.save(.title)
        let showDateStore = ShowDatePreference(defaults: .standard, key: "wtest-absent-date-\(suffix)")
        showDateStore.set(true)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-absent-skip-\(suffix)"),
            excludeStore: excludeStore,
            sortStore: sortStore,
            showUndatedStore: showUndatedStore,
            showDateStore: showDateStore)

        var fired = false
        service.onExcludedListTitlesReceived = { _ in fired = true }
        service.onShowUndatedRemindersReceived = { _ in fired = true }
        service.onSortOptionReceived = { _ in fired = true }
        service.onShowDateReceived = { _ in fired = true }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

        #expect(excludeStore.load() == ["KeepMe"])
        #expect(!showUndatedStore.load())
        #expect(sortStore.load() == .title)
        #expect(showDateStore.isEnabled)
        #expect(!fired)
    }

    @Test
    func showUndatedSurvivesRelaunch() {
        // Receive → throw the service away → a fresh store instance reads the
        // value back, proving the value survives process relaunch.
        let key = "wtest-relaunch-\(UUID().uuidString)"
        let fake = WatchFakeSession()
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: key))
        service.session(WCSession.default, didReceiveApplicationContext: ["showUndatedReminders": true])
        let freshStore = ShowUndatedRemindersPreference(defaults: .standard, key: key)
        #expect(freshStore.load())
    }

    @Test
    func excludedTitlesRefreshFiltersVisibleReminders() {
        let fake = WatchFakeSession()
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [
                inListReminder(title: "A", list: "Work"),
                inListReminder(title: "B", list: "Personal")
            ],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-excl-comp-skip-\(UUID().uuidString)"),
            excludeStore: ExcludedListStore(
                defaults: .standard,
                key: "wtest-excl-comp-excl-\(UUID().uuidString)"))
        // Wire the service's receive hook into the shared store, mirroring the app-layer wiring.
        service.onExcludedListTitlesReceived = { titles in
            store.refreshExcludedListTitles(Set(titles))
        }

        #expect(Set(store.visibleReminders.map(\.title)) == ["A", "B"]) // both visible before

        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["excludedListTitles": ["Work"]])

        #expect(Set(store.visibleReminders.map(\.title)) == ["B"]) // "A" (Work) filtered
        #expect(Set(store.excludedListTitles) == ["Work"])
    }
}

/// Builds a reminder that lives in a calendar titled `list`, so exclusion
/// filtering (which matches `calendar.title`) can be exercised.
private func inListReminder(title: String, list: String) -> EKReminder {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = list
    reminder.calendar = calendar
    return reminder
}
