import EventKit
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

// MARK: - ReminderPriority

struct ReminderPriorityTests {
    @Test
    func levelMapsHighPriority() {
        #expect(ReminderPriority.level(for: 1) == .high)
    }

    @Test
    func levelMapsMediumPriority() {
        #expect(ReminderPriority.level(for: 5) == .medium)
    }

    @Test
    func levelMapsLowPriority() {
        #expect(ReminderPriority.level(for: 9) == .low)
    }

    @Test
    func levelIsNilForNoPriority() {
        #expect(ReminderPriority.level(for: 0) == nil)
    }

    @Test
    func levelIsNilForUnknownPriority() {
        #expect(ReminderPriority.level(for: 3) == nil)
    }

    @Test
    func markerIsTwoForMedium() {
        #expect(ReminderPriority.marker(for: 5) == "!!")
    }

    @Test
    func markerIsThreeForHigh() {
        #expect(ReminderPriority.marker(for: 1) == "!!!")
    }

    @Test
    func markerIsOneForLow() {
        #expect(ReminderPriority.marker(for: 9) == "!")
    }

    @Test
    func markerIsEmptyWhenNoPriority() {
        #expect(ReminderPriority.marker(for: 0) == "")
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

// MARK: - ReminderSort

struct ReminderSortTests {
    private func makeReminder(
        title: String,
        priority: Int = 0,
        dateComponents: DateComponents? = nil) -> EKReminder {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.priority = priority
        reminder.dueDateComponents = dateComponents
        return reminder
    }

    private func titles(of reminders: [EKReminder]) -> [String] {
        reminders.sorted { ReminderSort.areInIncreasingOrder($0, $1) }.map(\.title)
    }

    private func date(_ day: Int) -> DateComponents {
        DateComponents(year: 2024, month: 1, day: day)
    }

    @Test
    func sortsHighPriorityBeforeLow() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        #expect(titles(of: [low, high]) == ["high", "low"])
    }

    @Test
    func sortsHighBeforeMediumBeforeLow() {
        let low = makeReminder(title: "L", priority: 9)
        let med = makeReminder(title: "M", priority: 5)
        let high = makeReminder(title: "H", priority: 1)
        #expect(titles(of: [low, med, high]) == ["H", "M", "L"])
    }

    @Test
    func sortsPrioritizedBeforeNoPriority() {
        let none = makeReminder(title: "none")
        let high = makeReminder(title: "high", priority: 1)
        #expect(titles(of: [none, high]) == ["high", "none"])
    }

    @Test
    func sortsWithinSamePriorityByDate() {
        let later = makeReminder(title: "later", priority: 1, dateComponents: date(10))
        let sooner = makeReminder(title: "sooner", priority: 1, dateComponents: date(2))
        #expect(titles(of: [later, sooner]) == ["sooner", "later"])
    }

    @Test
    func sortsDatedBeforeUndated() {
        let undated = makeReminder(title: "undated", priority: 5)
        let dated = makeReminder(title: "dated", priority: 5, dateComponents: date(3))
        #expect(titles(of: [undated, dated]) == ["dated", "undated"])
    }

    @Test
    func breaksTiesAlphabetically() {
        let beta = makeReminder(title: "Beta", priority: 5)
        let alpha = makeReminder(title: "Alpha", priority: 5)
        #expect(titles(of: [beta, alpha]) == ["Alpha", "Beta"])
    }
}
