@testable import SingleThread
import Testing

struct ReminderSkipLogicTests {
    // MARK: - resolve

    @Test func resolvePrunesStaleIDs() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: ["A", "C", "D"])
        #expect(Set(result) == ["A"])
    }

    @Test func resolveKeepsAllValidIDs() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B", "C"],
            skipped: ["A", "B", "C"])
        #expect(Set(result) == ["A", "B", "C"])
    }

    @Test func resolveReturnsEmptyWhenFetchedIsEmpty() {
        let result = ReminderSkipLogic.resolve(
            fetched: [],
            skipped: ["A", "B"])
        #expect(result.isEmpty)
    }

    @Test func resolveReturnsEmptyWhenSkippedIsEmpty() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: [])
        #expect(result.isEmpty)
    }

    @Test func resolveReturnsEmptyWhenNoOverlap() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: ["C", "D"])
        #expect(result.isEmpty)
    }

    // MARK: - skipping

    @Test func skippingAddsIdentifier() {
        let result = ReminderSkipLogic.skipping(
            "B",
            fetched: ["A", "B", "C"],
            skipped: ["A"])
        #expect(Set(result) == ["A", "B"])
    }

    @Test func skippingPrunesStaleEntries() {
        let result = ReminderSkipLogic.skipping(
            "B",
            fetched: ["A", "B"],
            skipped: ["A", "C", "D"])
        #expect(Set(result) == ["A", "B"])
    }

    @Test func skippingHandlesDuplicateIdentifier() {
        let result = ReminderSkipLogic.skipping(
            "A",
            fetched: ["A", "B"],
            skipped: ["A"])
        #expect(Set(result) == ["A"])
    }

    @Test func skippingWithEmptyFetchedReturnsEmpty() {
        let result = ReminderSkipLogic.skipping(
            "A",
            fetched: [],
            skipped: ["B"])
        #expect(result.isEmpty)
    }

    @Test func skippingPreservesExistingSkippedInFetched() {
        let result = ReminderSkipLogic.skipping(
            "C",
            fetched: ["A", "B", "C", "D"],
            skipped: ["A", "B"])
        #expect(Set(result) == ["A", "B", "C"])
    }
}
