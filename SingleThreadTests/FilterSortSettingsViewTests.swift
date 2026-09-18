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
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Sort By", "Show undated reminders", "Excluded Lists"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Choose the order reminders appear in.",
            "Include reminders that have no due date.",
            "Hide specific lists from the reminder view."
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

    @Test
    func filterSortSettingsViewShowsAISectionWhenAIUnavailable() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.ai),
            aiSortRules: .constant("clients first"),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("AI Sort Rules"))
    }

    @Test
    func filterSortSettingsViewHidesEditorAndExplainsWhenAIUnavailable() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.ai),
            aiSortRules: .constant("clients first"),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant([]))
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
    }

    @Test
    func filterSortSettingsViewShowsAIRulesEditorWhenAIAvailable() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.ai),
            aiSortRules: .constant("clients first"),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: true,
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        #expect(
            bodyDescription.contains("clients first"),
            "the rules editor (and its binding) is rendered when the device can run on-device AI")
        #expect(
            bodyDescription.contains("On-device AI applies these rules."),
            "available device gets the rules guidance footer")
        #expect(
            !bodyDescription.contains("This device doesn't support on-device AI"),
            "available device is not told on-device AI is unsupported")
    }

    @Test
    func filterSortSettingsViewFooterExplainsUnavailableAI() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.ai),
            aiSortRules: .constant("clients first"),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        #expect(
            bodyDescription.contains("so reminders stay in priority order"),
            "unavailable footer explains the priority-order fallback")
    }

    @Test
    func filterSortSettingsViewHasNoAIEditorWhenAnotherOptionSelected() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        #expect(!bodyDescription.contains("AI Sort Rules"))
    }
}
