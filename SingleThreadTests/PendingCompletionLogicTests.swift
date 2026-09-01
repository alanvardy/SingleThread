import EventKit
@testable import SingleThreadCore
import Testing

@MainActor
struct PendingCompletionLogicTests {
    // MARK: Internal

    @Test
    func filteringDropsPendingIdentifiers() {
        let remA = reminder("A"), remB = reminder("B")
        let out = PendingCompletionLogic.filtering(fetched: [remA, remB], pending: [remA.calendarItemIdentifier])
        #expect(out.map(\.title) == ["B"])
    }

    @Test
    func filteringKeepsNonPending() {
        let remA = reminder("A"), remB = reminder("B")
        let out = PendingCompletionLogic.filtering(fetched: [remA, remB], pending: ["other"])
        #expect(out.count == 2)
    }

    @Test
    func prunedKeepsOnlyFetchedIDs() {
        let out = PendingCompletionLogic.pruned(pending: ["a", "b", "c"], fetchedIdentifiers: ["b", "c", "d"])
        #expect(out == ["b", "c"])
    }

    @Test
    func prunedEmptiesWhenNothingFetched() {
        #expect(PendingCompletionLogic.pruned(pending: ["a"], fetchedIdentifiers: []).isEmpty)
    }

    @Test
    func removingCompletedDropsCompletedOnly() {
        let done = reminder("Done", completed: true)
        let todo = reminder("Todo")
        let out = PendingCompletionLogic.removingCompleted([done, todo])
        #expect(out.map(\.title) == ["Todo"])
    }

    // MARK: Private

    private func reminder(_ title: String, completed: Bool = false) -> EKReminder {
        let store = InMemoryEventStore()
        let rem = store.makeReminder(title: title, notes: nil, dueDate: nil, recurrenceRule: nil)
        rem.isCompleted = completed
        return rem
    }
}
