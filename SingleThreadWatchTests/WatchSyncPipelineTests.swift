import EventKit
import SingleThreadCore
import Testing
import WatchConnectivity

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
            showUndatedStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-und-\(suffix)",
                fallback: false),
            showDateStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-date-\(suffix)",
                fallback: true),
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
    func receiveAbsentKeysAreNoOps() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let excludeStore = ExcludedListStore(defaults: .standard, key: "wtest-absent-excl-\(suffix)")
        excludeStore.save(["KeepMe"])
        let showUndatedStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-absent-und-\(suffix)",
            fallback: false)
        showUndatedStore.set(false)
        let sortStore = SortOptionStore(defaults: .standard, key: "wtest-absent-sort-\(suffix)")
        sortStore.save(.title)
        let showDateStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-absent-date-\(suffix)",
            fallback: true)
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
        #expect(!showUndatedStore.isEnabled)
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
    func receiveAppliesShowRecurrenceAndShowAlarms() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let showRecurrenceStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-rec-\(suffix)",
            fallback: true)
        let showAlarmsStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-alarm-\(suffix)",
            fallback: true)
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
        let showRecurrenceStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-absent-rec-\(suffix)",
            fallback: true)
        let showAlarmsStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-absent-alarm-\(suffix)",
            fallback: true)
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
        let showListStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-sl-\(suffix)",
            fallback: false)
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
        let showListStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-absent-sl-\(suffix)",
            fallback: false)
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
            showUndatedStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-sl-und-\(suffix)",
                fallback: false),
            showDateStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-sl-date-\(suffix)",
                fallback: true),
            showListStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-sl-\(suffix)",
                fallback: false),
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
        let glowStore = BoolPreferenceStore(
            defaults: .standard,
            key: "wtest-glow-\(suffix)",
            fallback: true)
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
            showUndatedStore: BoolPreferenceStore(
                defaults: .standard,
                key: "wtest-push-cnt-und-\(suffix)",
                fallback: false),
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

    /// Wires a service with the concrete `BoolPreferenceStore` for the given
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
                showUndatedStore: BoolPreferenceStore(
                    defaults: .standard, key: storageKey, fallback: false))
        case "showRecurrence":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showRecurrenceStore: BoolPreferenceStore(
                    defaults: .standard, key: storageKey, fallback: true))
        case "showAlarms":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showAlarmsStore: BoolPreferenceStore(
                    defaults: .standard, key: storageKey, fallback: true))
        case "showList":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showListStore: BoolPreferenceStore(
                    defaults: .standard, key: storageKey, fallback: false))
        case "showCompletionGlow":
            return SkippedReminderSyncService(
                session: session,
                skipStore: skipStore,
                showCompletionGlowStore: BoolPreferenceStore(
                    defaults: .standard, key: storageKey, fallback: true))
        default:
            Issue.record("unexpected legacy context key \(contextKey)")
            return SkippedReminderSyncService(session: session, skipStore: skipStore)
        }
    }
}

/// Watch-target compile + behavior tests for the `enableActionButtons` sync
/// preference. Serialized because every test writes the same real App Group
/// key the service persists on receive; running them in parallel would let one
/// test's write race another's assertion.
@MainActor
@Suite(.serialized)
struct WatchEnableActionButtonsSyncTests {
    @Test
    func receiveEnableActionButtonsPersistsAndFiresHook() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-aab-recv-ids-\(suffix)"))
        var received: [Bool] = []
        service.onEnableActionButtonsReceived = { received.append($0) }
        defer { AppGroup.defaults.removeObject(forKey: "enableActionButtons") }
        service.session(WCSession.default, didReceiveApplicationContext: ["enableActionButtons": true])
        #expect(AppGroup.defaults.bool(forKey: "enableActionButtons")) // persisted first
        #expect(received == [true]) // then notified
    }

    @Test
    func receiveAbsentEnableActionButtonsKeyIsNoOp() {
        let fake = WatchFakeSession()
        let suffix = UUID().uuidString
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-aab-noop-ids-\(suffix)"))
        var fired = false
        service.onEnableActionButtonsReceived = { _ in fired = true }
        defer { AppGroup.defaults.removeObject(forKey: "enableActionButtons") }
        AppGroup.defaults.set(true, forKey: "enableActionButtons")

        // Push only skip IDs — the enableActionButtons key is absent.
        service.session(
            WCSession.default,
            didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])

        #expect(AppGroup.defaults.bool(forKey: "enableActionButtons")) // unchanged
        #expect(!fired)
    }
}
