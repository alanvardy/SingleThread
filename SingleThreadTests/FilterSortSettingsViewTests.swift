import EventKit
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Filter & Sort Settings View Tests

@MainActor
struct FilterSortSettingsViewTests {
    @Test
    func filterSortSettingsViewContainsExpectedRows() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant([]),
            store: makeEmptyReminderStore())
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Sort By", "Show undated reminders", "Excluded Lists", "View sorted and filtered list"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Choose the order reminders appear in.",
            "Include reminders that have no due date.",
            "Hide specific lists from the reminder view.",
            "Preview how your reminders are ordered right now."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    /// AI sort is disabled, so the Sort By picker offers only the menu options:
    /// the `.ai` case stays in the enum for a later re-enable but is never
    /// presented, nor handed to the picker as a selection.
    @Test
    func filterSortSettingsViewChoicesExcludeDisabledAI() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: true,
            availableLists: ["Work"],
            excludedLists: .constant([]),
            store: makeEmptyReminderStore())

        #expect(view.sortOptionChoices == [.priority, .dueDate, .title])
        #expect(!view.sortOptionChoices.contains(.ai))
    }

    /// The AI rules editor and the sorted/filtered preview live behind one
    /// pushed sub-menu row, so both are reachable while AI sort is selected.
    /// It replaces the standalone preview row, which has no editor to sit beside.
    @Test
    func filterSortSettingsViewShowsAIRulesSubmenuWhenAISelected() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.ai),
            aiSortRules: .constant("clients first"),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: true,
            availableLists: ["Work"],
            excludedLists: .constant([]),
            store: makeEmptyReminderStore())
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("AI Sort Rules"))
        #expect(
            bodyDescription.contains("Write rules and see how they reorder your reminders."),
            "the AI row advertises the rules editor and preview it pushes")
        #expect(
            !bodyDescription.contains("View sorted and filtered list"),
            "the AI sub-menu carries the preview instead of the standalone row")
    }

    /// Every non-AI sort option keeps the standalone preview row.
    @Test
    func filterSortSettingsViewShowsStandaloneListForNonAISorts() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: true,
            availableLists: ["Work"],
            excludedLists: .constant([]),
            store: makeEmptyReminderStore())
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("View sorted and filtered list"))
        #expect(bodyDescription.contains("Preview how your reminders are ordered right now."))
        #expect(!bodyDescription.contains("AI Sort Rules"))
    }

    /// The list rows are the store's sorted and filtered visible set: skipped
    /// IDs and excluded-list reminders are absent, and priority order holds.
    @Test
    func filterSortSettingsViewListDisplaysMatchVisibleReminders() {
        let high = makeReminder(title: "high", priority: 1)
        let low = makeReminder(title: "low", priority: 9)
        let skipped = makeReminder(title: "skipped", priority: 1)
        let excluded = makeReminder(title: "excluded", calendarTitle: "Work")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [low, high, skipped, excluded],
            skippedIDs: [skipped.calendarItemIdentifier],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant(["Work"]),
            store: store)

        #expect(view.listDisplays.map(\.title) == ["high", "low"])

        // The pushed destination is what the row hands to the list surface:
        // its display rows must reach the body, not just the computed property.
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("high"))
        #expect(!bodyDescription.contains("skipped"))
    }

    /// Sad path: an empty visible set maps to an empty row list rather than a
    /// stale or crashy surface.
    @Test
    func filterSortSettingsViewListDisplaysEmptyWhenNothingVisible() {
        let only = makeReminder(title: "gone", priority: 1)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [only],
            skippedIDs: [only.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: [],
            excludedLists: .constant([]),
            store: store)

        #expect(view.listDisplays.isEmpty)
    }
}
