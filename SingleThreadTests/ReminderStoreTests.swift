import EventKit
@testable import SingleThreadCore
import Testing

// The Undo completion suite keeps this file above the `file_length` warning
// threshold (650); the shared file-scoped `makeReminder` fixtures require the
// suites to live together.
// swiftlint:disable file_length

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
    func addReminderWithInMemoryStoreDoesNotCrash() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        // The in-memory store's save never throws; the important assertion is
        // that this completes without crashing.
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
        let completed = await store.completeCurrentReminder()
        #expect(!completed)
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
        let completed = await store.completeCurrentReminder()
        #expect(!completed)
        #expect(store.reminders.count == 1) // unchanged
    }

    @Test
    func completeCurrentReminderWithVisibleReminderReturnsTrue() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let completed = await store.completeCurrentReminder()
        #expect(completed)
        #expect(rem.isCompleted)
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
        let completed = await store.completeReminder(identifier: "nonexistent")
        #expect(!completed)
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

    // MARK: - allSkipped

    @Test
    func allSkippedTrueWhenRemindersExistButAllSkipped() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.allSkipped)
    }

    @Test
    func allSkippedFalseWhenRemindersEmpty() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!store.allSkipped)
    }

    @Test
    func allSkippedFalseWhenVisibleRemindersExist() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!store.allSkipped)
    }

    @Test
    func allSkippedTrueWhenAllExcluded() {
        let rem = makeReminder(title: "A", calendarTitle: "Work")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(store.allSkipped)
    }
}

// MARK: - Undo completion

#if !os(watchOS)
    @MainActor
    @Suite(.serialized)
    struct UndoCompletionTests {
        @Test
        func completeRetainsInUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(store.undoStore.hasUndoableReminder)
            #expect(store.undoStore.lastCompletedReminder === rem)
        }

        @Test
        func undoLastCompletionRevertsReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(rem.isCompleted)
            let undone = await store.undoLastCompletion()
            #expect(undone)
            #expect(!rem.isCompleted)
        }

        @Test
        func undoLastCompletionClearsUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            _ = await store.undoLastCompletion()
            #expect(!store.undoStore.hasUndoableReminder)
        }

        @Test
        func secondCompleteOverwritesUndoStore() async {
            let remA = makeReminder(title: "A")
            let remB = makeReminder(title: "B")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [remA, remB],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: remA.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remA)
            _ = await store.completeReminder(identifier: remB.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remB)
            // Undo B — A is gone permanently
            _ = await store.undoLastCompletion()
            #expect(!remB.isCompleted)
            #expect(remA.isCompleted) // A stays completed
        }

        @Test
        func undoReturnsFalseWhenNoRetainedReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoReturnsFalseWhenGated() async {
            let key = UUID().uuidString
            UserDefaults.standard.set(100, forKey: key)
            let counter = CompletionCounterStore(defaults: .standard, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter,
                entitlementStore: EntitlementStore(testingWithEntitled: false))
            // Manually stash a reminder (simulating a prior completion before
            // the gate closed; the complete itself would have been gated).
            store.undoStore.retain(rem)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoDecrementsCompletionCounter() async {
            let key = UUID().uuidString
            let defaults = UserDefaults.standard
            let counter = CompletionCounterStore(defaults: defaults, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(counter.count == 1)
            _ = await store.undoLastCompletion()
            #expect(counter.count == 0) // swiftlint:disable:this empty_count
        }
    }
#endif

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

@MainActor private let sharedTestEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String, priority: Int = 0, dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}
