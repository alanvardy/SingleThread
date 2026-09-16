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
    func nextOutcomeReportsNothingLeftToDoWhenAllSkipped() {
        let reminder = makeReminder(title: "A")
        let store = makeStore(with: [reminder], skippedIDs: [reminder.calendarItemIdentifier])
        #expect(ReminderIntentSupport.nextOutcome(for: store) == .nothingLeftToDo)
    }

    @Test
    func nextOutcomeDistinguishesHiddenFromEmpty() {
        #expect(ReminderIntentSupport.nextOutcome(for: makeStore(with: [])) == .nothingToDo)
        #expect(
            ReminderIntentSupport.nextOutcome(for: makeStore(with: [], hasHidden: true))
                == .nothingLeftToDo)
    }

    @Test
    func everyOutcomeHasANonEmptyDialog() {
        let outcomes: [ReminderIntentOutcome] = [
            .noAccess, .nothingToDo, .nothingLeftToDo,
            .next("A"), .completed("A"), .skipped("A")
        ]
        for outcome in outcomes {
            #expect(
                !ReminderIntentSupport.dialog(for: outcome).key.isEmpty,
                "\(outcome) has a dialog")
        }
    }

    @Test
    func nextOutcomeIsNothingToDoWhenEmpty() {
        #expect(ReminderIntentSupport.nextOutcome(for: makeStore(with: [])) == .nothingToDo)
    }

    // MARK: completeOutcome

    @Test
    func completeOutcomeNamesTheCompletedTask() async {
        let reminder = makeReminder(title: "Buy milk")
        let store = makeStore(with: [reminder])
        #expect(await ReminderIntentSupport.completeOutcome(for: store) == .completed("Buy milk"))
    }

    @Test
    func completeOutcomeIsNothingToDoWhenEmpty() async {
        #expect(await ReminderIntentSupport.completeOutcome(for: makeStore(with: [])) == .nothingToDo)
    }

    @Test
    func completeOutcomeIsNothingToDoWhenMutationGated() async {
        let reminder = makeReminder(title: "Buy milk")
        let store = makeGatedStore(with: [reminder])
        #expect(await ReminderIntentSupport.completeOutcome(for: store) == .nothingToDo)
    }

    @Test
    func completeOutcomePersistsThroughInMemoryEventStore() async {
        let reminder = makeReminder(title: "Buy milk")
        let eventStore = InMemoryEventStore(reminders: [reminder])
        let store = ReminderStore(
            eventStore: eventStore,
            loadsReminders: false,
            reminders: [reminder],
            authorizationStatus: .fullAccess,
            entitlementStore: EntitlementStore(testingWithEntitled: true),
            settle: noopSettle)
        _ = await ReminderIntentSupport.completeOutcome(for: store)
        #expect(eventStore.allReminders.first?.isCompleted == true, "completion is persisted")
    }

    // MARK: skipOutcome

    @Test
    func skipOutcomeNamesTheSkippedTask() {
        let reminder = makeReminder(title: "Buy milk")
        let store = makeStore(with: [reminder])
        #expect(ReminderIntentSupport.skipOutcome(for: store) == .skipped("Buy milk"))
    }

    @Test
    func skipOutcomeIsNothingToDoWhenEmpty() {
        #expect(ReminderIntentSupport.skipOutcome(for: makeStore(with: [])) == .nothingToDo)
    }

    @Test
    func skipOutcomeIsNothingToDoWhenMutationGated() {
        let reminder = makeReminder(title: "Buy milk")
        let store = makeGatedStore(with: [reminder])
        #expect(ReminderIntentSupport.skipOutcome(for: store) == .nothingToDo)
    }

    @Test
    func skipOutcomeWritesSkipSetBeforeReturning() {
        let reminder = makeReminder(title: "Buy milk")
        let store = makeStore(with: [reminder])
        _ = ReminderIntentSupport.skipOutcome(for: store)
        #expect(
            store.skippedIDs.contains(reminder.calendarItemIdentifier),
            "the skip set is durable before the intent returns")
    }

    // MARK: Private

    // MARK: Fixtures

    private func makeStore(
        with reminders: [EKReminder],
        skippedIDs: Set<String> = [],
        hasHidden: Bool = false) -> ReminderStore {
        ReminderStore(
            eventStore: InMemoryEventStore(reminders: reminders),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: .fullAccess,
            hasHidden: hasHidden,
            entitlementStore: EntitlementStore(testingWithEntitled: true),
            settle: noopSettle)
    }

    private func makeGatedStore(with reminders: [EKReminder]) -> ReminderStore {
        let defaults = UserDefaults.standard
        let key = UUID().uuidString
        defaults.set(EntitlementStore.freemiumCap, forKey: key) // count == 100 → canMutate false
        return ReminderStore(
            eventStore: InMemoryEventStore(reminders: reminders),
            loadsReminders: false,
            reminders: reminders,
            authorizationStatus: .fullAccess,
            completionCounter: CompletionCounterStore(defaults: defaults, key: key),
            entitlementStore: EntitlementStore(testingWithEntitled: false),
            settle: noopSettle)
    }
}
