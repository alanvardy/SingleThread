import EventKit
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - AI Sort Rules View Tests

@MainActor
struct AISortRulesViewTests {
    @Test
    func aiSortRulesViewShowsEditorRefreshAndGuidanceWhenAIAvailable() {
        let view = AISortRulesView(
            aiSortRules: .constant("clients first"),
            isAIRankingAvailable: true,
            store: makeEmptyReminderStore())
        let bodyDescription = String(describing: view.body)

        #expect(
            bodyDescription.contains("clients first"),
            "the rules editor (and its binding) is rendered when the device can run on-device AI")
        #expect(
            bodyDescription.contains("On-device AI applies these rules."),
            "available device gets the rules guidance footer")
        #expect(
            bodyDescription.contains("Refresh"),
            "a refresh button sits under the rules editor")
        #expect(
            !bodyDescription.contains("This device doesn't support on-device AI"),
            "available device is not told on-device AI is unsupported")
    }

    @Test
    func aiSortRulesViewExplainsAndHidesEditorWhenAIUnavailable() {
        let view = AISortRulesView(
            aiSortRules: .constant("clients first"),
            isAIRankingAvailable: false,
            store: makeEmptyReminderStore())
        let bodyDescription = String(describing: view.body)

        #expect(
            !bodyDescription.contains("clients first"),
            "the rules-editor binding is not rendered when the device cannot run on-device AI")
        #expect(
            bodyDescription.contains("This device doesn't support on-device AI"),
            "unavailable device is told on-device AI is unsupported")
        #expect(
            !bodyDescription.contains("On-device AI applies these rules."),
            "unavailable device does not get the editor guidance footer")
        #expect(
            !bodyDescription.contains("aiSortRefreshButton"),
            "no refresh button when there is no editor to refresh")
    }

    /// The preview rows are the store's sorted and filtered visible set: skipped
    /// IDs and excluded-list reminders are absent, and priority order holds.
    @Test
    func aiSortRulesViewListDisplaysMatchVisibleReminders() {
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
        let view = AISortRulesView(
            aiSortRules: .constant(""),
            isAIRankingAvailable: true,
            store: store)

        #expect(view.listDisplays.map(\.title) == ["high", "low"])

        // The rows reach the body, not just the computed property.
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("high"))
        #expect(!bodyDescription.contains("skipped"))
    }

    /// Sad path: an empty visible set maps to an empty row list and an
    /// explanatory empty state rather than a stale or crashy surface.
    @Test
    func aiSortRulesViewListDisplaysEmptyWhenNothingVisible() {
        let only = makeReminder(title: "gone", priority: 1)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [only],
            skippedIDs: [only.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let view = AISortRulesView(
            aiSortRules: .constant(""),
            isAIRankingAvailable: true,
            store: store)

        #expect(view.listDisplays.isEmpty)
        #expect(
            String(describing: view.body)
                .contains("No reminders match the current filters."))
    }
}
