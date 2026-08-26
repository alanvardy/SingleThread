import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

// MARK: - Recording fake

@MainActor
private final class FakeEventStore: EventKitStoring {
    // MARK: Lifecycle

    init(
        authStatus: EKAuthorizationStatus = .notDetermined,
        accessGranted: Bool = true,
        accessError: (any Error)? = nil,
        fetchResult: [EKReminder] = [],
        defaultCalendar: EKCalendar? = nil) {
        self.authStatus = authStatus
        self.accessGranted = accessGranted
        self.accessError = accessError
        self.fetchResult = fetchResult
        self.defaultCalendar = defaultCalendar
    }

    // MARK: Internal

    // MARK: Configuration

    var authStatus: EKAuthorizationStatus
    var accessGranted: Bool
    var accessError: (any Error)?
    var fetchResult: [EKReminder]
    var defaultCalendar: EKCalendar?
    var saveShouldThrow = false
    var removeShouldThrow = false
    var returnedCalendars: [EKCalendar] = []

    // MARK: Recording

    private(set) var saved: [EKReminder] = []
    private(set) var removed: [EKReminder] = []
    private(set) var lastSaveCommit = false
    private(set) var lastRemoveCommit = false
    private(set) var lastPredicate: NSPredicate?
    private(set) var lastStartDate: Date?
    private(set) var lastEndDate: Date?
    private(set) var firstStartDate: Date?
    private(set) var firstEndDate: Date?
    private(set) var fetchCallCount = 0
    private(set) var requestAccessCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var calendarFetchCallCount = 0

    // MARK: EventKitStoring

    func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus {
        authStatus
    }

    func calendars(for _: EKEntityType) -> [EKCalendar] {
        calendarFetchCallCount += 1
        return returnedCalendars
    }

    func requestFullAccessToReminders() async throws -> Bool {
        requestAccessCallCount += 1
        if let accessError {
            throw accessError
        }
        return accessGranted
    }

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars _: [EKCalendar]?) -> NSPredicate {
        if lastStartDate == nil && lastEndDate == nil && fetchCallCount == 0 {
            firstStartDate = startDate
            firstEndDate = endDate
        }
        lastStartDate = startDate
        lastEndDate = endDate
        return NSPredicate(value: true)
    }

    @discardableResult
    func fetchReminders(
        matching predicate: NSPredicate,
        completion: @escaping ([EKReminder]?) -> Void) -> Any {
        fetchCallCount += 1
        lastPredicate = predicate
        completion(fetchResult)
        return ()
    }

    #if !os(watchOS)
        func refreshSourcesIfNecessary() {
            refreshCallCount += 1
        }

        func save(_ reminder: EKReminder, commit: Bool) throws {
            lastSaveCommit = commit
            if saveShouldThrow {
                throw NSError(domain: "FakeEventStore", code: 1)
            }
            saved.append(reminder)
        }

        func remove(_ reminder: EKReminder, commit: Bool) throws {
            lastRemoveCommit = commit
            if removeShouldThrow {
                throw NSError(domain: "FakeEventStore", code: 1)
            }
            removed.append(reminder)
            // Mirror the real store: a removed reminder no longer appears in fetches.
            fetchResult.removeAll { $0 === reminder }
        }

        func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule?) -> EKReminder {
            let reminder = EKReminder(eventStore: storeForReminderCreation)
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = defaultCalendar
            return reminder
        }
    #endif

    // MARK: Private

    /// A single `EKEventStore` kept alive to back all `EKReminder`
    /// instances created by `makeReminder`. The backing store must
    /// outlive the reminders to avoid a SIGTRAP crash on iOS.
    private let storeForReminderCreation = EKEventStore()
}

// MARK: - Write-path tests

#if !os(watchOS)
    @MainActor
    @Suite(.serialized)
    struct ReminderStoreWriteTests {
        @Test
        func completeReminderMarksSavedAndReloads() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.completeReminder(identifier: reminder.calendarItemIdentifier)

            #expect(reminder.isCompleted)
            #expect(fake.saved.count == 1)
            #expect(fake.saved.first === reminder)
            #expect(fake.lastSaveCommit == true)
            #expect(fake.lastPredicate != nil)
            #expect(fake.fetchCallCount == before + 2) // reload-after-save (narrow + broad)
        }

        @Test
        func completeReminderSaveErrorStaysSilentAndSkipsReload() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            fake.saveShouldThrow = true
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.completeReminder(identifier: reminder.calendarItemIdentifier)

            #expect(fake.saved.isEmpty)
            #expect(fake.fetchCallCount == before) // no reload on save error
        }

        @Test
        func addReminderSavesAndReturnsTrue() async {
            let fake = FakeEventStore()
            let store = testStore(eventStore: fake)
            let dueDate = DateComponents(year: 2026, month: 1, day: 2)
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)

            let savedResult = await store.addReminder(
                title: "New",
                notes: "Note",
                dueDate: dueDate,
                recurrenceRule: rule)

            #expect(savedResult)
            #expect(fake.saved.count == 1)
            #expect(fake.saved.first?.title == "New")
            #expect(fake.saved.first?.notes == "Note")
            #expect(fake.saved.first?.dueDateComponents?.day == 2)
            #expect(fake.saved.first?.recurrenceRules?.count == 1)
            #expect(fake.lastSaveCommit == true)
            #expect(fake.lastPredicate != nil) // reload-after-save re-fetched
        }

        @Test
        func addReminderSaveErrorReturnsFalse() async {
            let fake = FakeEventStore()
            fake.saveShouldThrow = true
            let store = testStore(eventStore: fake)

            let savedResult = await store.addReminder(title: "New", notes: nil, dueDate: nil)

            #expect(!savedResult)
            #expect(fake.saved.isEmpty)
        }

        @Test
        func deleteReminderRemovesAndReloads() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

            #expect(fake.removed.count == 1)
            #expect(fake.removed.first === reminder)
            #expect(fake.lastRemoveCommit == true)
            #expect(fake.lastPredicate != nil)
            #expect(fake.fetchCallCount == before + 2) // reload-after-remove (narrow + broad)
            #expect(store.visibleReminders.isEmpty)
        }

        @Test
        func deleteReminderRemoveErrorStaysSilentAndSkipsReload() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            fake.removeShouldThrow = true
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

            #expect(fake.removed.isEmpty)
            #expect(fake.fetchCallCount == before) // no reload on remove error
        }

        @Test
        func deleteReminderWhileSkippedPrunesSkipIDOnReload() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            let skipStore = SkippedReminderStore(
                defaults: .standard,
                key: "test-delete-skip-\(UUID().uuidString)")
            let store = ReminderStore(eventStore: fake, skipStore: skipStore, loadsReminders: true)
            await store.reload()
            // Skip it so the ID is in the persisted skip set; then the reminder is gone.
            store.skipCurrentReminderImmediately()
            #expect(Set(skipStore.load()).contains(reminder.calendarItemIdentifier))

            fake.fetchResult = []
            await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

            #expect(fake.removed.first === reminder)
            #expect(!Set(skipStore.load()).contains(reminder.calendarItemIdentifier))
        }
    }
#endif

// MARK: - Lifecycle tests

@MainActor
@Suite(.serialized)
struct ReminderStoreLifecycleTests {
    @Test
    func reloadPopulatesRemindersFromFetch() async {
        let first = makeReminder(title: "A")
        let second = makeReminder(title: "B")
        let fake = FakeEventStore(fetchResult: [first, second])
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A", "B"])
        #expect(fake.fetchCallCount == 2) // narrow + extra broad detect fetch
        #expect(fake.lastPredicate != nil)
        #if !os(watchOS)
            #expect(fake.refreshCallCount == 1)
        #endif
    }

    @Test
    func startWithFullAccessFetchesWithoutRequesting() async {
        let fake = FakeEventStore(
            authStatus: .fullAccess,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.start()

        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 2) // narrow + extra broad fetch in reload
        #expect(fake.requestAccessCallCount == 0)
    }

    @Test
    func startWithoutAccessRequestsThenReloads() async {
        let fake = FakeEventStore(
            authStatus: .notDetermined,
            accessGranted: true,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.start()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 2) // narrow + broad fetch in reload
    }

    @Test
    func requestAccessGrantSetsFullAccessAndReloads() async {
        let fake = FakeEventStore(
            authStatus: .notDetermined,
            accessGranted: true,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 2) // narrow + broad fetch in reload
        #expect(fake.firstStartDate != nil) // narrow window predicate comes first
    }

    @Test
    func requestAccessDenyRereadsStatusWithoutFetching() async {
        let fake = FakeEventStore(authStatus: .denied, accessGranted: false)
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .denied)
        #expect(fake.fetchCallCount == 0)
    }

    @Test
    func requestAccessErrorRereadsStatusWithoutFetching() async {
        let fake = FakeEventStore(
            authStatus: .restricted,
            accessError: NSError(domain: "test", code: 1))
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .restricted)
        #expect(fake.fetchCallCount == 0)
    }

    @Test
    func reloadDefaultUsesWindowPredicate() async {
        let fake = FakeEventStore(fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(fake.firstStartDate != nil)
        #expect(fake.firstEndDate != nil)
    }

    @Test
    func reloadWithShowsUndatedUsesNilPredicateAndFiltersWindow() async {
        let undated = makeReminder(title: "Undated")
        let inWindow = makeReminder(title: "Now")
        inWindow.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date())
        let outOfWindow = makeReminder(title: "Future")
        outOfWindow.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date().addingTimeInterval(40 * 86400))
        let fake = FakeEventStore(fetchResult: [undated, inWindow, outOfWindow])
        let store = testStore(eventStore: fake)
        store.showsUndatedReminders = true

        await store.reload()

        #expect(fake.lastStartDate == nil)
        #expect(fake.lastEndDate == nil)
        #expect(store.reminders.map(\.title) == ["Undated", "Now"])
    }

    @Test
    func loadsRemindersFalseMakesReadPathsNoOps() async {
        let fake = FakeEventStore(
            authStatus: .fullAccess,
            fetchResult: [makeReminder(title: "A")])
        let skipStore = SkippedReminderStore(
            defaults: .standard,
            key: "test-\(UUID().uuidString)")
        let store = ReminderStore(
            eventStore: fake,
            skipStore: skipStore,
            loadsReminders: false)

        await store.start()
        await store.reload()

        #expect(fake.fetchCallCount == 0)
        #expect(fake.requestAccessCallCount == 0)
        #expect(store.reminders.isEmpty)
    }
}

// MARK: - Available projects tests

@MainActor
@Suite(.serialized)
struct ReminderStoreAvailableListsTests {
    @Test
    func availableListsSortedAndDeduplicatedAfterReload() async {
        let fake = FakeEventStore()
        fake.returnedCalendars = [
            makeCalendar(title: "Work"),
            makeCalendar(title: "Personal"),
            makeCalendar(title: "work"),
            makeCalendar(title: "Work"),
            makeCalendar(title: "")
        ]
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.availableLists == ["Personal", "Work", "work"])
        #expect(fake.calendarFetchCallCount == 1)
    }

    @Test
    func availableListsEmptyWhenNoCalendars() async {
        let fake = FakeEventStore()
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.availableLists.isEmpty)
        #expect(fake.calendarFetchCallCount == 1)
    }
}

// MARK: - Fixtures

@MainActor private let sharedTestEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
private func makeCalendar(title: String) -> EKCalendar {
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = title
    return calendar
}

@MainActor
private func testStore(eventStore: any EventKitStoring) -> ReminderStore {
    let skipStore = SkippedReminderStore(
        defaults: .standard,
        key: "test-\(UUID().uuidString)")
    return ReminderStore(eventStore: eventStore, skipStore: skipStore, loadsReminders: true)
}
