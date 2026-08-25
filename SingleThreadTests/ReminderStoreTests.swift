import EventKit
@testable import SingleThreadCore
import Testing

@MainActor
@Suite(.serialized)
struct ReminderStoreTests {
    // MARK: - visibleReminders

    @Test
    func visibleRemindersFiltersOutSkippedIDs() {
        let rem = makeReminder(title: "A")
        let other = makeReminder(title: "B")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem, other],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let visible = store.visibleReminders
        #expect(visible.count == 1)
        #expect(visible.first?.title == "B")
    }

    @Test
    func visibleRemindersEmptyWhenAllSkipped() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.isEmpty)
    }

    @Test
    func visibleRemindersEmptyWhenNoReminders() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.isEmpty)
    }

    @Test
    func visibleRemindersSortsByPriority() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [low, high],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let titles = store.visibleReminders.map(\.title)
        #expect(titles == ["high", "low"])
    }

    @Test
    func visibleRemindersSortsDatedBeforeUndated() {
        let undated = makeReminder(title: "undated", priority: 5)
        let dated = makeReminder(
            title: "dated",
            priority: 5,
            dateComponents: DateComponents(year: 2024, month: 1, day: 1))
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [undated, dated],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let titles = store.visibleReminders.map(\.title)
        #expect(titles == ["dated", "undated"])
    }

    @Test
    func visibleRemindersFiltersOutExcludedListTitles() {
        let excluded = makeReminder(title: "A", calendarTitle: "Work")
        let kept = makeReminder(title: "B", calendarTitle: "Personal")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [excluded, kept],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(store.visibleReminders.map(\.title) == ["B"])
    }

    @Test
    func visibleRemindersKeepsNilCalendarReminders() {
        let noCalendar = makeReminder(title: "A") // calendar == nil
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [noCalendar],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(store.visibleReminders.count == 1)
    }

    @Test
    func visibleRemindersEmptyWhenAllListsExcluded() {
        let inList = makeReminder(title: "A", calendarTitle: "Work")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [inList],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(store.visibleReminders.isEmpty)
    }

    // MARK: - availableLists

    @Test
    func availableListsDefaultsToEmpty() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.availableLists.isEmpty)
    }

    // MARK: - setExcludedListTitles

    @Test
    func setExcludedListTitlesPersistsAndFiresHooks() {
        let key = "test-excluded-\(UUID().uuidString)"
        let excludeStore = ExcludedListStore(defaults: .standard, key: key)
        let store = ReminderStore(eventStore: InMemoryEventStore(), excludeStore: excludeStore, loadsReminders: false)
        var changedTitles: [String]?
        var remindersChanged = false
        store.onExcludedListsChanged = { changedTitles = $0 }
        store.onRemindersChanged = { remindersChanged = true }

        store.setExcludedListTitles(["Work", "Personal"])

        #expect(store.excludedListTitles == ["Work", "Personal"])
        #expect(Set(excludeStore.load()) == ["Work", "Personal"])
        #expect(Set(changedTitles ?? []) == ["Work", "Personal"])
        #expect(remindersChanged)
    }

    // MARK: - refreshExcludedListTitles

    @Test
    func refreshExcludedListTitlesUpdatesSetAndFiresRemindersChangedOnly() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var remindersChanged = false
        var excludedChanged = false
        store.onRemindersChanged = { remindersChanged = true }
        store.onExcludedListsChanged = { _ in excludedChanged = true }

        store.refreshExcludedListTitles(["Work"])

        #expect(store.excludedListTitles == ["Work"])
        #expect(remindersChanged)
        #expect(!excludedChanged)
    }

    // MARK: - setSortOption

    @Test
    func setSortOptionReordersVisibleReminders() {
        let highLater = makeReminder(
            title: "HighLater",
            priority: 1,
            dateComponents: DateComponents(year: 2024, month: 1, day: 10))
        let lowSooner = makeReminder(
            title: "LowSooner",
            priority: 9,
            dateComponents: DateComponents(year: 2024, month: 1, day: 2))
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [lowSooner, highLater],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.map(\.title) == ["HighLater", "LowSooner"]) // default .priority
        store.setSortOption(.dueDate)
        #expect(store.visibleReminders.map(\.title) == ["LowSooner", "HighLater"])
    }

    @Test
    func setSortOptionFiresBothHooks() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var received: SortOption?
        var remindersChanged = false
        store.onSortOptionChanged = { received = $0 }
        store.onRemindersChanged = { remindersChanged = true }
        store.setSortOption(.title)
        #expect(received == .title)
        #expect(remindersChanged)
    }

    @Test
    func setSortOptionIsIdempotent() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var fired = 0
        store.onSortOptionChanged = { _ in fired += 1 }
        store.setSortOption(.title)
        store.setSortOption(.title)
        store.setSortOption(.title)
        #expect(fired == 1)
    }

    // MARK: - addReminder

    @Test
    func addReminderDoesNotCrashWithoutAccess() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        // Without EventKit authorization the save fails and is logged internally;
        // the important assertion is that this completes without crashing.
        await store.addReminder(
            title: "Buy milk",
            notes: "Two percent",
            dueDate: DateComponents(year: 2025, month: 1, day: 2))
    }

    @Test
    func addReminderKeepsExistingRemindersUntouched() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "Existing")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await store.addReminder(title: "New", notes: nil, dueDate: nil)
        #expect(store.reminders.count == 1)
        #expect(store.reminders.first?.title == "Existing")
    }

    @Test
    func addReminderWithRecurrenceRuleDoesNotCrash() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        await store.addReminder(
            title: "Weekly review",
            notes: nil,
            dueDate: DateComponents(year: 2025, month: 1, day: 1),
            recurrenceRule: rule)
        // No crash = pass.
        #expect(Bool(true))
    }

    // MARK: - skipCurrentReminder

    @Test
    func skipCurrentReminderDoesNothingWhenNoVisibleReminders() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        store.skipCurrentReminder()
        #expect(store.skippedIDs.isEmpty)
    }

    @Test
    func skipCurrentReminderUpdatesSkippedIDs() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.onSkipSetChanged = { _ in continuation.resume() }
            store.skipCurrentReminder()
        }
        #expect(store.skippedIDs.contains(rem.calendarItemIdentifier))
    }

    @Test
    func skipCurrentReminderFiresRemindersChangedHook() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.onRemindersChanged = { continuation.resume() }
            store.skipCurrentReminder()
        }
        #expect(Bool(true))
    }

    // MARK: - completeCurrentReminder

    @Test
    func completeCurrentReminderDoesNothingWhenNoReminders() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await store.completeCurrentReminder()
        #expect(Bool(true)) // no crash
    }

    @Test
    func completeCurrentReminderDoesNothingWhenAllSkipped() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        await store.completeCurrentReminder()
        #expect(store.reminders.count == 1) // unchanged
    }

    @Test
    func completeCurrentReminderDoesNotCrashWithVisibleReminder() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        // Without EventKit access, save fails but does not crash.
        await store.completeCurrentReminder()
        #expect(Bool(true))
    }

    // MARK: - completeReminder

    @Test
    func completeReminderDoesNothingWhenIdentifierNotFound() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await store.completeReminder(identifier: "nonexistent")
        #expect(Bool(true)) // no crash
    }

    // MARK: - start / reload guards

    @Test
    func reloadResumesOnMainActorWhenFetchCompletesOffMain() async {
        let reminder = makeReminder(title: "A")
        let fake = InMemoryEventStore(reminders: [reminder], deliverCompletionOffMain: true)
        let store = ReminderStore(eventStore: fake, loadsReminders: true)
        await store.reload()
        #expect(store.reminders.map(\.title) == ["A"])
    }

    @Test
    func showsUndatedRemindersDefaultsToFalse() {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        #expect(store.showsUndatedReminders == false)
    }

    @Test
    func startDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        await store.start()
        #expect(store.authorizationStatus == .notDetermined)
    }

    @Test
    func reloadDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        await store.reload()
        #expect(store.reminders.isEmpty)
    }

    @Test
    func reloadClearSkippedDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        await store.reload(clearSkipped: true)
        #expect(store.reminders.isEmpty)
    }

    // MARK: - hasHidden

    @Test
    func hasHiddenDefaultsToFalse() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!store.hasHidden)
    }

    @Test
    func hasHiddenSeedsFromInit() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            hasHidden: true)
        #expect(store.hasHidden)
    }

    @Test
    func hasHiddenForFalseWhenSetsMatch() {
        let reminder = makeReminder(title: "A")
        #expect(!ReminderStore.hasHiddenFor(shown: [reminder], allIncomplete: [reminder]))
    }

    @Test
    func hasHiddenForTrueWhenIncompleteHasHidden() {
        let shown = makeReminder(title: "In")
        let hidden = makeReminder(title: "Hidden")
        #expect(ReminderStore.hasHiddenFor(shown: [shown], allIncomplete: [shown, hidden]))
    }
}

// MARK: - makeReminder test seam

#if !os(watchOS)
    @MainActor
    struct MakeReminderTests {
        @Test
        func makeReminderSetsTitle() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.title == "Buy milk")
        }

        @Test
        func makeReminderSetsNotes() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: "Two percent",
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.notes == "Two percent")
        }

        @Test
        func makeReminderSetsDueDate() {
            let dueDate = DateComponents(year: 2025, month: 1, day: 2)
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: dueDate,
                recurrenceRule: nil)
            #expect(reminder.dueDateComponents?.year == dueDate.year)
            #expect(reminder.dueDateComponents?.month == dueDate.month)
            #expect(reminder.dueDateComponents?.day == dueDate.day)
        }

        @Test
        func makeReminderLeavesUnsetFieldsNil() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.notes == nil)
            #expect(reminder.dueDateComponents == nil)
            #expect(reminder.hasRecurrenceRules == false)
        }

        @Test
        func makeReminderSetsRecurrenceRule() {
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: rule)
            #expect(reminder.recurrenceRules?.count == 1)
            #expect(reminder.recurrenceRules?.first?.frequency == .weekly)
            #expect(reminder.recurrenceRules?.first?.interval == 1)
        }

        @Test
        func makeReminderUsesDefaultCalendar() {
            let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
            calendar.title = "Custom"
            let store = InMemoryEventStore(calendars: [], defaultCalendar: calendar)
            let reminder = store.makeReminder(
                title: "Test",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.calendar == calendar)
        }

        /// Tests real EventKit calendar behavior — intentionally uses EKEventStore.
        @Test
        func makeReminderSetsDefaultCalendar() {
            let eventStore = EKEventStore()
            let reminder = (eventStore as any EventKitStoring).makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.calendar == eventStore.defaultCalendarForNewReminders())
        }
    }
#endif

// MARK: - Fixtures

/// Construction only — never saved through EventKit.
private func makeReminder(title: String, priority: Int = 0, dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}

/// Construction only — never saved through EventKit.
private func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}
