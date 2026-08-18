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
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.visibleReminders.isEmpty)
    }

    @Test
    func visibleRemindersEmptyWhenNoReminders() {
        let store = ReminderStore(
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
            loadsReminders: false,
            reminders: [undated, dated],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let titles = store.visibleReminders.map(\.title)
        #expect(titles == ["dated", "undated"])
    }

    // MARK: - addReminder

    @Test
    func addReminderDoesNotCrashWithoutAccess() async {
        let store = ReminderStore(loadsReminders: false)
        // Without EventKit authorization the save fails and is logged internally;
        // the important assertion is that this completes without crashing.
        await store.addReminder(
            title: "Buy milk",
            notes: "Two percent",
            dueDate: DateComponents(year: 2025, month: 1, day: 2))
    }

    @Test
    func addReminderReturnsFalseWithoutAccess() async {
        let store = ReminderStore(loadsReminders: false)
        let saved = await store.addReminder(title: "Test", notes: nil, dueDate: nil)
        #expect(!saved)
    }

    @Test
    func addReminderKeepsExistingRemindersUntouched() async {
        let store = ReminderStore(
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
        let store = ReminderStore(loadsReminders: false)
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
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await store.completeReminder(identifier: "nonexistent")
        #expect(Bool(true)) // no crash
    }

    // MARK: - start / reload guards

    @Test
    func startDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(loadsReminders: false)
        await store.start()
        #expect(store.authorizationStatus == .notDetermined)
    }

    @Test
    func reloadDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(loadsReminders: false)
        await store.reload()
        #expect(store.reminders.isEmpty)
    }

    @Test
    func reloadClearSkippedDoesNothingWhenLoadsRemindersFalse() async {
        let store = ReminderStore(loadsReminders: false)
        await store.reload(clearSkipped: true)
        #expect(store.reminders.isEmpty)
    }
}

// MARK: - makeReminder test seam

#if !os(watchOS)
    @MainActor
    struct MakeReminderTests {
        @Test
        func makeReminderSetsTitle() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.title == "Buy milk")
        }

        @Test
        func makeReminderSetsNotes() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: "Two percent",
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.notes == "Two percent")
        }

        @Test
        func makeReminderSetsDueDate() {
            let dueDate = DateComponents(year: 2025, month: 1, day: 2)
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: dueDate,
                eventStore: EKEventStore())
            #expect(reminder.dueDateComponents?.year == dueDate.year)
            #expect(reminder.dueDateComponents?.month == dueDate.month)
            #expect(reminder.dueDateComponents?.day == dueDate.day)
        }

        @Test
        func makeReminderLeavesUnsetFieldsNil() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.notes == nil)
            #expect(reminder.dueDateComponents == nil)
            #expect(reminder.hasRecurrenceRules == false)
        }

        @Test
        func makeReminderSetsRecurrenceRule() {
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore(),
                recurrenceRule: rule)
            #expect(reminder.recurrenceRules?.count == 1)
            #expect(reminder.recurrenceRules?.first?.frequency == .weekly)
            #expect(reminder.recurrenceRules?.first?.interval == 1)
        }

        @Test
        func makeReminderSetsDefaultCalendar() {
            let eventStore = EKEventStore()
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: eventStore)
            #expect(reminder.calendar == eventStore.defaultCalendarForNewReminders())
        }
    }
#endif

// MARK: - Fixtures

private func makeReminder(title: String, priority: Int = 0, dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}
