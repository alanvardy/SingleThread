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

    // MARK: Configuration

    var authStatus: EKAuthorizationStatus
    var accessGranted: Bool
    var accessError: (any Error)?
    var fetchResult: [EKReminder]
    var defaultCalendar: EKCalendar?
    var saveShouldThrow = false

    // MARK: Recording

    private(set) var saved: [EKReminder] = []
    private(set) var lastSaveCommit: Bool?
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

        func defaultCalendarForNewReminders() -> EKCalendar? {
            defaultCalendar
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
