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
    // MARK: Internal

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
        #expect(context["showRecurrence"] != nil)
        #expect(context["showAlarms"] != nil)
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
        let countStore = SkipCountStore(defaults: .standard, key: "wtest-all-cnt-\(suffix)")
        let excludeStore = ExcludedListStore(defaults: .standard, key: "wtest-all-excl-\(suffix)")
        let showUndatedStore = ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-all-und-\(suffix)")
        let sortStore = SortOptionStore(defaults: .standard, key: "wtest-all-sort-\(suffix)")
        let showDateStore = ShowDatePreference(defaults: .standard, key: "wtest-all-date-\(suffix)")
        showDateStore.set(true)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: skipStore,
            countStore: countStore,
            excludeStore: excludeStore,
            sortStore: sortStore,
            showUndatedStore: showUndatedStore,
            showDateStore: showDateStore)

        var skips: [[String]] = []
        var counts: [[String: Int]] = []
        var titles: [[String]] = []
        var undated: [Bool] = []
        var sorts: [SortOption] = []
        var showDates: [Bool] = []
        service.onSkippedIdentifiersReceived = { skips.append($0) }
        service.onSkipCountsReceived = { counts.append($0) }
        service.onExcludedListTitlesReceived = { titles.append($0) }
        service.onShowUndatedRemindersReceived = { undated.append($0) }
        service.onSortOptionReceived = { sorts.append($0) }
        service.onShowDateReceived = { showDates.append($0) }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: [
                "skippedReminderIdentifiers": ["R1", "R2"],
                "skipCounts": ["R1": 6],
                "excludedListTitles": ["Work"],
                "showUndatedReminders": true,
                "sortOption": "dueDate",
                "showDate": false
            ])

        #expect(Set(skipStore.load()) == ["R1", "R2"])
        #expect(countStore.load() == ["R1": 6])
        #expect(excludeStore.load() == ["Work"])
        #expect(showUndatedStore.load())
        #expect(sortStore.load() == .dueDate)
        #expect(!showDateStore.isEnabled)
        #expect(skips == [["R1", "R2"]])
        #expect(counts == [["R1": 6]])
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

    @Test(arguments: [
        ("showUndatedReminders", true),
        ("showRecurrence", false),
        ("showAlarms", false),
        ("showList", true),
        ("showCompletionGlow", false),
    ])
    func receivedPreferenceSurvivesRelaunch(_ payload: (key: String, value: Bool)) {
        // Receive → throw the service away → a fresh store instance reads the
        // value back, proving the value survives process relaunch.
        let key = "wtest-relaunch-\(UUID().uuidString)"
        let fake = WatchFakeSession()
        let service = Self.makeService(forContextKey: payload.key, session: fake, storageKey: key)
        service.session(WCSession.default, didReceiveApplicationContext: [payload.key: payload.value])
        let fresh = Self.makePreference(forContextKey: payload.key, defaults: .standard, storageKey: key)
        #expect(
            fresh.currentValue == payload.value,
            "\(payload.key)=\(payload.value) should survive relaunch")
    }

    @Test
    func excludedTitlesRefreshFiltersVisibleReminders() {
        let fake = WatchFakeSession()
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
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

    @Test
    func receiveAppliesShowRecurrenceAndShowAlarms() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let showRecurrenceStore = ShowRecurrencePreference(defaults: .standard, key: "wtest-rec-\(suffix)")
        let showAlarmsStore = ShowAlarmsPreference(defaults: .standard, key: "wtest-alarm-\(suffix)")
        showRecurrenceStore.set(false)
        showAlarmsStore.set(false)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-ids-\(suffix)"),
            showRecurrenceStore: showRecurrenceStore,
            showAlarmsStore: showAlarmsStore)

        var recurrenceValues: [Bool] = []
        var alarmValues: [Bool] = []
        service.onShowRecurrenceReceived = { recurrenceValues.append($0) }
        service.onShowAlarmsReceived = { alarmValues.append($0) }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: [
                "showRecurrence": true,
                "showAlarms": true
            ])

        #expect(showRecurrenceStore.isEnabled)
        #expect(showAlarmsStore.isEnabled)
        #expect(recurrenceValues == [true])
        #expect(alarmValues == [true])
    }

    @Test
    func receiveAbsentRecurrenceAndAlarmsKeysAreNoOps() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let showRecurrenceStore = ShowRecurrencePreference(defaults: .standard, key: "wtest-absent-rec-\(suffix)")
        let showAlarmsStore = ShowAlarmsPreference(defaults: .standard, key: "wtest-absent-alarm-\(suffix)")
        showRecurrenceStore.set(false)
        showAlarmsStore.set(false)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-absent-ids-\(suffix)"),
            showRecurrenceStore: showRecurrenceStore,
            showAlarmsStore: showAlarmsStore)

        var fired = false
        service.onShowRecurrenceReceived = { _ in fired = true }
        service.onShowAlarmsReceived = { _ in fired = true }

        // Push only skip IDs — recurrence and alarms keys absent
        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

        #expect(!showRecurrenceStore.isEnabled) // unchanged
        #expect(!showAlarmsStore.isEnabled) // unchanged
        #expect(!fired)
    }

    @Test
    func receiveAppliesShowList() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let showListStore = ShowListPreference(defaults: .standard, key: "wtest-sl-\(suffix)")
        showListStore.set(false)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-sl-ids-\(suffix)"),
            showListStore: showListStore)

        var showListValues: [Bool] = []
        service.onShowListReceived = { showListValues.append($0) }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["showList": true])

        #expect(showListStore.isEnabled)
        #expect(showListValues == [true])
    }

    @Test
    func receiveAbsentShowListKeyIsNoOp() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let showListStore = ShowListPreference(defaults: .standard, key: "wtest-absent-sl-\(suffix)")
        showListStore.set(false)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-absent-sl-ids-\(suffix)"),
            showListStore: showListStore)

        var fired = false
        service.onShowListReceived = { _ in fired = true }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

        #expect(!showListStore.isEnabled)
        #expect(!fired)
    }

    @Test
    func pushAllFromWatchOmitsShowListWhenFlagged() throws {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-sl-skip-\(suffix)")
        skipStore.save(["A"])
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: skipStore,
            excludeStore: ExcludedListStore(defaults: .standard, key: "wtest-push-sl-excl-\(suffix)"),
            sortStore: SortOptionStore(defaults: .standard, key: "wtest-push-sl-sort-\(suffix)"),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-push-sl-und-\(suffix)"),
            showDateStore: ShowDatePreference(defaults: .standard, key: "wtest-push-sl-date-\(suffix)"),
            showListStore: ShowListPreference(defaults: .standard, key: "wtest-push-sl-\(suffix)"),
            sendsShowDate: false, sendsShowList: false)
        service.pushAll()
        let context = try #require(fake.lastContext)
        #expect(context["showDate"] == nil)
        #expect(context["showList"] == nil)
        #expect(context["showRecurrence"] != nil)
        #expect(context["showAlarms"] != nil)
    }

    @Test
    func receiveAppliesShowCompletionGlow() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let glowStore = ShowCompletionGlowPreference(defaults: .standard, key: "wtest-glow-\(suffix)")
        glowStore.set(true)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-glow-ids-\(suffix)"),
            showCompletionGlowStore: glowStore)

        var values: [Bool] = []
        service.onShowCompletionGlowReceived = { values.append($0) }

        service.session(WCSession.default, didReceiveApplicationContext: ["showCompletionGlow": false])

        #expect(!glowStore.isEnabled)
        #expect(values == [false])
    }

    @Test
    func pushAllFromWatchIncludesSkipCountsAndOmitsPhoneOnlyKeys() throws {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-cnt-skip-\(suffix)")
        skipStore.save(["A"])
        let countStore = SkipCountStore(defaults: .standard, key: "wtest-push-cnt-\(suffix)")
        countStore.save(["a": 2])
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: skipStore,
            countStore: countStore,
            excludeStore: ExcludedListStore(defaults: .standard, key: "wtest-push-cnt-excl-\(suffix)"),
            sortStore: SortOptionStore(defaults: .standard, key: "wtest-push-cnt-sort-\(suffix)"),
            showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-push-cnt-und-\(suffix)"),
            sendsShowDate: false, sendsEntitled: false)
        service.pushAll()
        let context = try #require(fake.lastContext)
        // The count snapshot rides the shared context like the skip IDs.
        let counts = try #require(context["skipCounts"] as? [String: Int])
        #expect(counts == ["a": 2])
        // Phone-only keys stay omitted from the watch's push.
        #expect(context["showDate"] == nil)
        #expect(context["isEntitled"] == nil)
    }

    @Test
    func receiveSkipCountsSavesAndFiresHookOnWatch() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let countStore = SkipCountStore(defaults: .standard, key: "wtest-recv-cnt-\(suffix)")
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-recv-cnt-skip-\(suffix)"),
            countStore: countStore)
        var received: [[String: Int]] = []
        service.onSkipCountsReceived = { received.append($0) }

        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["skipCounts": ["a": 6]])

        #expect(countStore.load() == ["a": 6]) // persisted first
        #expect(received == [["a": 6]]) // then notified
    }

    // MARK: Private

    // MARK: Private — relaunch-test seam

    /// Reads the persisted Bool the way any `Show*Preference` would after the
    /// service applied an incoming context value. The five concrete preference
    /// types diverge only in default and key, so the relaunch shape unifies
    /// behind this wrapper.
    private struct PreferenceValue {
        let currentValue: Bool
    }

    /// Builds the concrete store the service treats as "fresh" after a relaunch:
    /// the raw Bool the previous service instance persisted under `storageKey`.
    private static func makePreference(
        forContextKey _: String,
        defaults: UserDefaults,
        storageKey: String) -> PreferenceValue {
        PreferenceValue(currentValue: defaults.object(forKey: storageKey) as? Bool ?? false)
    }

    /// Wires a service with the concrete `Show*Preference` store for the given
    /// context key, each under the same `storageKey` so a later read-back sees
    /// the persisted value.
    private static func makeService(
        forContextKey contextKey: String,
        session: WatchFakeSession,
        storageKey: String) -> SkippedReminderSyncService {
        let skipStore = SkippedReminderStore(defaults: .standard, key: storageKey + "-ids")
        switch contextKey {
        case "showUndatedReminders":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: storageKey))
        case "showRecurrence":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showRecurrenceStore: ShowRecurrencePreference(defaults: .standard, key: storageKey))
        case "showAlarms":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showAlarmsStore: ShowAlarmsPreference(defaults: .standard, key: storageKey))
        case "showList":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showListStore: ShowListPreference(defaults: .standard, key: storageKey))
        case "showCompletionGlow":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard, key: storageKey))
        default:
            Issue.record("unexpected legacy context key \(contextKey)")
            return SkippedReminderSyncService(session: session, skipStore: skipStore)
        }
    }
}

/// Builds a reminder that lives in a calendar titled `list`, so exclusion
/// filtering (which matches `calendar.title`) can be exercised.
/// Construction only — never saved through EventKit.
private func inListReminder(title: String, list: String) -> EKReminder {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = list
    reminder.calendar = calendar
    return reminder
}
