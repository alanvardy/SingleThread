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

    // MARK: Recording

    private(set) var saved: [EKReminder] = []
    private(set) var lastSaveCommit = false
    private(set) var lastPredicate: NSPredicate?
    private(set) var fetchCallCount = 0
    private(set) var requestAccessCallCount = 0
    private(set) var refreshCallCount = 0

    // MARK: EventKitStoring

    func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus {
        authStatus
    }

    func requestFullAccessToReminders() async throws -> Bool {
        requestAccessCallCount += 1
        if let accessError {
            throw accessError
        }
        return accessGranted
    }

    func predicateForIncompleteReminders(
        withDueDateStarting _: Date?,
        ending _: Date?,
        calendars _: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
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

        func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule?) -> EKReminder {
            let reminder = EKReminder(eventStore: EKEventStore())
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
            #expect(fake.fetchCallCount == before + 1) // reload-after-save
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
        #expect(fake.fetchCallCount == 1)
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
        #expect(fake.fetchCallCount == 1)
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
        #expect(fake.fetchCallCount == 1)
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
        #expect(fake.fetchCallCount == 1)
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

// MARK: - Fixtures

private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    return reminder
}

@MainActor
private func testStore(eventStore: any EventKitStoring) -> ReminderStore {
    let skipStore = SkippedReminderStore(
        defaults: .standard,
        key: "test-\(UUID().uuidString)")
    return ReminderStore(eventStore: eventStore, skipStore: skipStore, loadsReminders: true)
}
