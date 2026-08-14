import SingleThreadCore
import Testing

struct ReminderSkipLogicTests {
    // MARK: - resolve

    @Test
    func resolvePrunesStaleIDs() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: ["A", "C", "D"])
        #expect(Set(result) == ["A"])
    }

    @Test
    func resolveKeepsAllValidIDs() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B", "C"],
            skipped: ["A", "B", "C"])
        #expect(Set(result) == ["A", "B", "C"])
    }

    @Test
    func resolveReturnsEmptyWhenFetchedIsEmpty() {
        let result = ReminderSkipLogic.resolve(
            fetched: [],
            skipped: ["A", "B"])
        #expect(result.isEmpty)
    }

    @Test
    func resolveReturnsEmptyWhenSkippedIsEmpty() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: [])
        #expect(result.isEmpty)
    }

    @Test
    func resolveReturnsEmptyWhenNoOverlap() {
        let result = ReminderSkipLogic.resolve(
            fetched: ["A", "B"],
            skipped: ["C", "D"])
        #expect(result.isEmpty)
    }

    // MARK: - skipping

    @Test
    func skippingAddsIdentifier() {
        let result = ReminderSkipLogic.skipping(
            "B",
            fetched: ["A", "B", "C"],
            skipped: ["A"])
        #expect(Set(result) == ["A", "B"])
    }

    @Test
    func skippingPrunesStaleEntries() {
        let result = ReminderSkipLogic.skipping(
            "B",
            fetched: ["A", "B"],
            skipped: ["A", "C", "D"])
        #expect(Set(result) == ["A", "B"])
    }

    @Test
    func skippingHandlesDuplicateIdentifier() {
        let result = ReminderSkipLogic.skipping(
            "A",
            fetched: ["A", "B"],
            skipped: ["A"])
        #expect(Set(result) == ["A"])
    }

    @Test
    func skippingWithEmptyFetchedReturnsEmpty() {
        let result = ReminderSkipLogic.skipping(
            "A",
            fetched: [],
            skipped: ["B"])
        #expect(result.isEmpty)
    }

    @Test
    func skippingPreservesExistingSkippedInFetched() {
        let result = ReminderSkipLogic.skipping(
            "C",
            fetched: ["A", "B", "C", "D"],
            skipped: ["A", "B"])
        #expect(Set(result) == ["A", "B", "C"])
    }
}

// MARK: - ReminderNotesFormatter

struct ReminderNotesFormatterTests {
    @Test
    func formatReturnsNilForNilInput() {
        #expect(ReminderNotesFormatter.format(nil) == nil)
    }

    @Test
    func formatReturnsNilForWhitespaceOnly() {
        #expect(ReminderNotesFormatter.format("   ") == nil)
    }

    @Test
    func formatReturnsNilForEmptyString() {
        #expect(ReminderNotesFormatter.format("") == nil)
    }

    @Test
    func formatReturnsNilForNewlinesOnly() {
        #expect(ReminderNotesFormatter.format("\n\n") == nil)
    }

    @Test
    func formatPreservesPlainNotes() {
        let result = ReminderNotesFormatter.format("Buy milk")
        #expect(result == "Buy milk")
    }

    @Test
    func formatTrimsLeadingWhitespace() {
        let result = ReminderNotesFormatter.format("  hello")
        #expect(result == "hello")
    }

    @Test
    func formatTrimsTrailingWhitespace() {
        let result = ReminderNotesFormatter.format("hello  ")
        #expect(result == "hello")
    }

    @Test
    func formatStripsLeadingTPrefix() {
        let result = ReminderNotesFormatter.format("tBuy milk")
        #expect(result == "Buy milk")
    }

    @Test
    func formatStripsLeadingTPrefixWithSpace() {
        let result = ReminderNotesFormatter.format("t Buy milk")
        #expect(result == "Buy milk")
    }

    @Test
    func formatKeepsTInsideText() {
        let result = ReminderNotesFormatter.format("Get two items")
        #expect(result == "Get two items")
    }

    @Test
    func formatPreservesMultilineNotes() {
        let result = ReminderNotesFormatter.format("Line one\nLine two")
        #expect(result == "Line one\nLine two")
    }

    @Test
    func formatStripsLeadingTPrefixFromMultiline() {
        let result = ReminderNotesFormatter.format("tLine one\nLine two")
        #expect(result == "Line one\nLine two")
    }

    @Test
    func formatReturnsNilWhenOnlyLeadingPrefixChar() {
        #expect(ReminderNotesFormatter.format("t") == nil)
    }

    @Test
    func formatReturnsNilWhenOnlyLeadingPrefixCharWithSpace() {
        #expect(ReminderNotesFormatter.format("t ") == nil)
    }
}
