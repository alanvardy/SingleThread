import EventKit
import Foundation
import SingleThreadCore
import Testing

private let noopSettle: ReminderStoreSettle = {}

@MainActor
@Suite(.serialized)
struct ReminderIntentSupportTests {
    // MARK: Internal

    // MARK: makeStore

    @Test
    func makeStoreReturnsNilWhenAccessDenied() async {
        let store = await ReminderIntentSupport.makeStore(
            eventStore: InMemoryEventStore(reminders: [makeReminder(title: "A")]),
            authorizationStatus: .denied)
        #expect(store == nil, "denied access builds no store")
    }

    @Test
    func makeStoreReturnsReloadedStoreWhenAuthorized() async {
        let store = await ReminderIntentSupport.makeStore(
            eventStore: InMemoryEventStore(reminders: [makeReminder(title: "Buy milk")]),
            authorizationStatus: .fullAccess)
        #expect(store?.visibleReminders.first?.title == "Buy milk", "authorized store reloads reminders")
    }

    @Test
    func makeStoreDoesNotPromptWhenNotAuthorized() async {
        let eventStore = InMemoryEventStore(reminders: [makeReminder(title: "A")])
        _ = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: .notDetermined)
        #expect(eventStore.requestFullAccessCallCount == 0, "an intent never prompts for access")
    }

    // MARK: nextOutcome

    @Test
    func nextOutcomeNamesTheFirstVisibleReminder() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        let store = makeStore(with: [low, high])
        #expect(ReminderIntentSupport.nextOutcome(for: store) == .next("high"))
    }

    @Test
    func nextOutcomeIsNothingToDoWhenAllSkipped() {
        let reminder = makeReminder(title: "A")
        let store = makeStore(with: [reminder], skippedIDs: [reminder.calendarItemIdentifier])
        #expect(ReminderIntentSupport.nextOutcome(for: store) == .nothingToDo)
    }

    @Test
    func nextOutcomeIsNothingToDoWhenEmpty() {
        #expect(ReminderIntentSupport.nextOutcome(for: makeStore(with: [])) == .nothingToDo)
    }

    // MARK: Private

    // MARK: Fixtures

    private func makeStore(
        with reminders: [EKReminder],
        skippedIDs: Set<String> = []) -> ReminderStore {
        ReminderStore(
            eventStore: InMemoryEventStore(reminders: reminders),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: .fullAccess,
            entitlementStore: EntitlementStore(testingWithEntitled: true),
            settle: noopSettle)
    }
}
