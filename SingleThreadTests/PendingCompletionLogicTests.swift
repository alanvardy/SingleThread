import EventKit
@testable import SingleThreadCore
import Testing

@MainActor private let sharedPendingTestEventStore = EKEventStore()

// MARK: - Tests

@MainActor
struct PendingCompletionLogicTests {
    // MARK: Internal

    @Test
    func filteringPruningAndRemoval() {
        let remA = reminder("A"), remB = reminder("B")
        let filtered = PendingCompletionLogic.filtering(
            fetched: [remA, remB],
            pending: [remA.calendarItemIdentifier])
        #expect(filtered.map(\.title) == ["B"], "fetched reminder whose id is pending is dropped")
        let kept = PendingCompletionLogic.filtering(fetched: [remA, remB], pending: ["other"])
        #expect(kept.count == 2, "non-pending fetched reminders are all kept")

        let pruned = PendingCompletionLogic.pruned(
            pending: ["a", "b", "c"],
            fetchedIdentifiers: ["b", "c", "d"])
        #expect(pruned == ["b", "c"], "pruning keeps only ids still fetched")
        #expect(
            PendingCompletionLogic.pruned(pending: ["a"], fetchedIdentifiers: []).isEmpty,
            "pruning with an empty fetch empties the pending set")

        let done = reminder("Done", completed: true)
        let todo = reminder("Todo")
        let remaining = PendingCompletionLogic.removingCompleted([done, todo])
        #expect(remaining.map(\.title) == ["Todo"], "completed reminders are dropped, todo kept")
    }

    // MARK: Private

    private func reminder(_ title: String, completed: Bool = false) -> EKReminder {
        let rem = EKReminder(eventStore: sharedPendingTestEventStore)
        rem.title = title
        rem.isCompleted = completed
        return rem
    }
}
