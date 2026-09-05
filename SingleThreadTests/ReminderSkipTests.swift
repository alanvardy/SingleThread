import EventKit
import SingleThreadCore
import Testing

struct ReminderSkipLogicTests {
    // MARK: - resolve

    private struct ResolveCase: Sendable {
        let fetched: [String]
        let skipped: [String]
        let expected: [String]
    }

    // MARK: - skipping

    private struct SkippingCase: Sendable {
        let identifier: String
        let fetched: [String]
        let skipped: [String]
        let expected: [String]
    }

    @Test(arguments: [
        ResolveCase(fetched: ["A", "B"], skipped: ["A", "C", "D"], expected: ["A"]),
        ResolveCase(fetched: ["A", "B", "C"], skipped: ["A", "B", "C"], expected: ["A", "B", "C"]),
        ResolveCase(fetched: [], skipped: ["A", "B"], expected: []),
        ResolveCase(fetched: ["A", "B"], skipped: [], expected: []),
        ResolveCase(fetched: ["A", "B"], skipped: ["C", "D"], expected: [])
    ])
    private func resolveIntersectsFetchedAndSkipped(_ spec: ResolveCase) {
        let result = ReminderSkipLogic.resolve(fetched: spec.fetched, skipped: spec.skipped)
        #expect(
            Set(result) == Set(spec.expected),
            "fetched \(spec.fetched), skipped \(spec.skipped) → \(spec.expected)")
    }

    @Test(arguments: [
        SkippingCase(identifier: "B", fetched: ["A", "B", "C"], skipped: ["A"], expected: ["A", "B"]),
        SkippingCase(identifier: "B", fetched: ["A", "B"], skipped: ["A", "C", "D"], expected: ["A", "B"]),
        SkippingCase(identifier: "A", fetched: ["A", "B"], skipped: ["A"], expected: ["A"]),
        SkippingCase(identifier: "A", fetched: [], skipped: ["B"], expected: []),
        SkippingCase(identifier: "C", fetched: ["A", "B", "C", "D"], skipped: ["A", "B"], expected: ["A", "B", "C"])
    ])
    private func skippingAddsIdentifierAndPrunesStale(_ spec: SkippingCase) {
        let result = ReminderSkipLogic.skipping(
            spec.identifier,
            fetched: spec.fetched,
            skipped: spec.skipped)
        #expect(
            Set(result) == Set(spec.expected),
            "skip \(spec.identifier) over fetched \(spec.fetched), skipped \(spec.skipped) → \(spec.expected)")
    }
}

// MARK: - ReminderPriority

struct ReminderPriorityTests {
    // MARK: Internal

    @Test(arguments: [
        (0, nil),
        (1, ReminderPriority.Level.high), (2, .high), (3, .high), (4, .high),
        (5, .medium),
        (6, .low), (7, .low), (8, .low), (9, .low)
    ] as [(Int, ReminderPriority.Level?)])
    func levelMapsEveryPriority(_ spec: (priority: Int, expected: ReminderPriority.Level?)) {
        #expect(
            ReminderPriority.level(for: spec.priority) == spec.expected,
            "priority \(spec.priority) → \(spec.expected.map(String.init(describing:)) ?? "nil")")
    }

    @Test
    func displayNameLocalizes() {
        #expect(ReminderPriority.Level.high.displayName == String.en("High", bundle: .core), "high → High")
        #expect(ReminderPriority.Level.medium.displayName == String.en("Medium", bundle: .core), "medium → Medium")
        #expect(ReminderPriority.Level.low.displayName == String.en("Low", bundle: .core), "low → Low")
    }

    // MARK: Private

    private struct MarkerRankCase: Sendable {
        let priority: Int
        let marker: String
        let rank: Int?
    }

    @Test(arguments: [
        MarkerRankCase(priority: 0, marker: "", rank: nil),
        MarkerRankCase(priority: 1, marker: "!!!", rank: 0),
        MarkerRankCase(priority: 4, marker: "!!!", rank: 0),
        MarkerRankCase(priority: 5, marker: "!!", rank: 1),
        MarkerRankCase(priority: 6, marker: "!", rank: 2),
        MarkerRankCase(priority: 9, marker: "!", rank: 2)
    ])
    private func markerAndRankMap(_ spec: MarkerRankCase) {
        #expect(
            ReminderPriority.marker(for: spec.priority) == spec.marker,
            "marker for priority \(spec.priority) → \(spec.marker)")
        #expect(
            ReminderPriority.rank(for: spec.priority) == spec.rank,
            "rank for priority \(spec.priority) → \(spec.rank.map(String.init(describing:)) ?? "nil")")
    }
}

// MARK: - ReminderNotesFormatter

struct ReminderNotesFormatterTests {
    @Test(arguments: [nil, "", "   ", "\n\n", "t", "t "])
    func formatReturnsNilForBlankOrPrefixOnly(_ input: String?) {
        #expect(ReminderNotesFormatter.format(input) == nil, "nil for input \(input.map { "\"\($0)\"" } ?? "nil")")
    }

    @Test(arguments: [
        ("Buy milk", "Buy milk"),
        ("  hello", "hello"),
        ("hello  ", "hello"),
        ("tBuy milk", "Buy milk"),
        ("t Buy milk", "Buy milk"),
        ("Get two items", "Get two items"),
        ("take out trash", "take out trash"),
        ("two percent", "two percent"),
        ("Line one\nLine two", "Line one\nLine two"),
        ("tLine one\nLine two", "Line one\nLine two")
    ])
    func formatTransforms(_ pair: (input: String, expected: String)) {
        #expect(
            ReminderNotesFormatter.format(pair.input) == pair.expected,
            "\(pair.input) → \(pair.expected)")
    }
}

// MARK: - ReminderSort

struct ReminderSortTests {
    // MARK: Internal

    @Test
    func sortsByPriorityThenDateThenTitle() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        #expect(titles(of: [low, high]) == ["high", "low"], "high priority before low")
        let low2 = makeReminder(title: "L", priority: 9)
        let med = makeReminder(title: "M", priority: 5)
        let high2 = makeReminder(title: "H", priority: 1)
        #expect(titles(of: [low2, med, high2]) == ["H", "M", "L"], "high before medium before low")
        let none = makeReminder(title: "none")
        let high3 = makeReminder(title: "high", priority: 1)
        #expect(titles(of: [none, high3]) == ["high", "none"], "prioritized before no priority")
    }

    @Test
    func sortsWithinSamePriorityByDateThenTitle() {
        let later = makeReminder(title: "later", priority: 1, dateComponents: date(10))
        let sooner = makeReminder(title: "sooner", priority: 1, dateComponents: date(2))
        #expect(titles(of: [later, sooner]) == ["sooner", "later"], "earlier date sorts first")
        let undated = makeReminder(title: "undated", priority: 5)
        let dated = makeReminder(title: "dated", priority: 5, dateComponents: date(3))
        #expect(titles(of: [undated, dated]) == ["dated", "undated"], "dated before undated")
        let beta = makeReminder(title: "Beta", priority: 5)
        let alpha = makeReminder(title: "Alpha", priority: 5)
        #expect(titles(of: [beta, alpha]) == ["Alpha", "Beta"], "alphabetical tie-break")
    }

    @Test
    func priorityOptionMatchesLegacyComparator() {
        let lowPriority = makeReminder(title: "a", priority: 9, dateComponents: date(2), calendarTitle: "Work")
        let highPriority = makeReminder(title: "b", priority: 1, calendarTitle: "Home")
        let viaPriority = [lowPriority, highPriority].sorted {
            ReminderSort.areInIncreasingOrder($0, $1, using: .priority)
        }.map(\.title)
        let viaLegacy = [lowPriority, highPriority].sorted { ReminderSort.areInIncreasingOrder($0, $1) }.map(\.title)
        #expect(viaPriority == viaLegacy)
    }

    @Test
    func dueDateOptionSortsSoonestFirst() {
        let lowSoon = makeReminder(title: "sooner", priority: 9, dateComponents: date(2))
        let highLater = makeReminder(title: "later", priority: 1, dateComponents: date(10))
        #expect(
            titles(of: [lowSoon, highLater], using: .dueDate) == ["sooner", "later"],
            "due-date sort ignores priority")
        let undated = makeReminder(title: "undated")
        let dated = makeReminder(title: "dated", dateComponents: date(3))
        #expect(titles(of: [undated, dated], using: .dueDate) == ["dated", "undated"], "dated before undated")
    }

    @Test
    func titleOptionSortsCaseInsensitively() {
        let zebra = makeReminder(title: "Zebra", priority: 1) // priority ignored
        let apple = makeReminder(title: "apple", priority: 9)
        #expect(titles(of: [zebra, apple], using: .title) == ["apple", "Zebra"], "case-insensitive alphabetical")
        let later = makeReminder(title: "Same", dateComponents: date(10))
        let sooner = makeReminder(title: "Same", dateComponents: date(2))
        let sorted = [later, sooner].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .title) }
        #expect(sorted[0].dueDateComponents?.day == 2, "same title breaks tie by sooner due date")
        #expect(sorted[1].dueDateComponents?.day == 10, "same title breaks tie by later due date")
    }

    @Test
    func groupsByListWithinPriorityBucket() {
        let work = makeReminder(title: "Work task", priority: 1, calendarTitle: "Work")
        let home = makeReminder(title: "Home task", priority: 1, calendarTitle: "Home")
        #expect(titles(of: [work, home]) == ["Home task", "Work task"], "same priority groups by list")
    }

    @Test
    func groupsByListWithinDueDateBucket() {
        let work = makeReminder(title: "Work task", dateComponents: date(2), calendarTitle: "Work")
        let home = makeReminder(title: "Home task", dateComponents: date(2), calendarTitle: "Home")
        #expect(titles(of: [work, home], using: .dueDate) == ["Home task", "Work task"], "same due date groups by list")
    }

    @Test
    func groupsByListWithinTitleBucket() {
        let homeLater = makeReminder(title: "Same", dateComponents: date(10), calendarTitle: "Home")
        let workSooner = makeReminder(title: "Same", dateComponents: date(2), calendarTitle: "Work")
        let sorted = [homeLater, workSooner].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .title) }
        #expect(sorted.map(\.calendar?.title) == ["Home", "Work"], "same title groups by list; list beats due date")
    }

    @Test
    func listCollationIsCaseAndLocaleInsensitive() {
        let upper = makeReminder(title: "z-title", priority: 1, calendarTitle: "Work")
        let lower = makeReminder(title: "a-title", priority: 1, calendarTitle: "work")
        // Case-sensitive would order "Work" before "work"; case-insensitive ties
        // them so title decides. Locale-insensitivity is inherited from
        // localizedCaseInsensitiveCompare (not deterministically assertable here).
        let sorted = [upper, lower].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .priority) }
        #expect(sorted.map(\.title) == ["a-title", "z-title"], "Work/work collapse to one list; title breaks the tie")
    }

    @Test
    func nilListSortsLast() {
        let titled = makeReminder(title: "titled", priority: 1, calendarTitle: "Work")
        let untitled = makeReminder(title: "untitled", priority: 1)
        #expect(titles(of: [untitled, titled]) == ["titled", "untitled"], "titled list before nil list")
        #expect(titles(of: [titled, untitled]) == ["titled", "untitled"], "nil list sorts last regardless of input order")
    }

    @Test
    func sameListFallsThroughToDateThenTitle() {
        let later = makeReminder(title: "later", priority: 1, dateComponents: date(10), calendarTitle: "Work")
        let sooner = makeReminder(title: "sooner", priority: 1, dateComponents: date(2), calendarTitle: "Work")
        #expect(titles(of: [later, sooner]) == ["sooner", "later"], "same list falls through to date")
        let beta = makeReminder(title: "Beta", priority: 1, calendarTitle: "Work")
        let alpha = makeReminder(title: "Alpha", priority: 1, calendarTitle: "Work")
        #expect(titles(of: [beta, alpha]) == ["Alpha", "Beta"], "same list + no date falls through to title")
    }

    // MARK: Private

    /// Construction only — never saved through EventKit.
    private func makeReminder(
        title: String,
        priority: Int = 0,
        dateComponents: DateComponents? = nil,
        calendarTitle: String? = nil) -> EKReminder {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.priority = priority
        reminder.dueDateComponents = dateComponents
        if let calendarTitle {
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = calendarTitle
            reminder.calendar = calendar
        }
        return reminder
    }

    private func titles(of reminders: [EKReminder]) -> [String] {
        reminders.sorted { ReminderSort.areInIncreasingOrder($0, $1) }.map(\.title)
    }

    private func titles(of reminders: [EKReminder], using option: SortOption) -> [String] {
        reminders.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: option) }.map(\.title)
    }

    private func date(_ day: Int) -> DateComponents {
        DateComponents(year: 2024, month: 1, day: day)
    }
}
