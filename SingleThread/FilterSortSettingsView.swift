import SingleThreadCore
import SwiftUI

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, the AI Sort Rules sub-menu
/// (rules editor plus the sorted & filtered preview), the show-undated toggle,
/// and the Excluded Lists sub-menu. The non-AI options push the standalone
/// sorted & filtered preview instead. Takes only the bindings it needs rather
/// than the full bag so it cannot accidentally mutate unrelated preferences.
/// The store is read-only and exists solely to feed those previews.
///
/// AI sort is currently disabled — the picker offers `SortOption.menuOptions`,
/// which withholds `.ai` — so the AI Sort Rules section below is unreachable
/// from the picker. It is kept in place for a later re-enable.
struct FilterSortSettingsView: View {
    @Binding var sortOption: SortOption

    @Binding var aiSortRules: String

    @Binding var showUndatedReminders: Bool

    let isAIRankingAvailable: Bool

    let availableLists: [String]

    @Binding var excludedLists: Set<String>

    let store: ReminderStore

    /// The options the Sort By picker offers. Kept as a named property so a test
    /// can pin the menu to `SortOption.menuOptions` (which withholds the disabled
    /// `.ai`) rather than the full `allCases`.
    var sortOptionChoices: [SortOption] {
        SortOption.menuOptions
    }

    /// The current visible set as display rows — sorted and filtered by the
    /// store exactly as the main reminder card sees it. Feeds the standalone
    /// preview pushed for every non-AI sort option.
    var listDisplays: [ReminderDisplay] {
        store.visibleReminders.map { reminder in ReminderDisplay(reminder: reminder) }
    }

    var body: some View {
        Form {
            Picker(selection: $sortOption) {
                ForEach(sortOptionChoices, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Sort By")
                    SettingsCaption(text: "Choose the order reminders appear in.")
                }
            }
            if sortOption == .ai {
                Section {
                    NavigationLink {
                        AISortRulesView(
                            aiSortRules: $aiSortRules,
                            isAIRankingAvailable: isAIRankingAvailable,
                            store: store)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("AI Sort Rules")
                                SettingsCaption(
                                    text: "Write rules and see how they reorder your reminders.")
                            }
                        } icon: {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .accessibilityIdentifier("aiSortRulesRow")
                }
            }
            Toggle(isOn: $showUndatedReminders) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show undated reminders")
                        SettingsCaption(text: "Include reminders that have no due date.")
                    }
                } icon: {
                    Image(systemName: "calendar.badge.minus")
                }
            }
            Section {
                NavigationLink {
                    ExcludedListsView(
                        excludedLists: $excludedLists,
                        availableLists: availableLists)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Excluded Lists")
                            SettingsCaption(text: "Hide specific lists from the reminder view.")
                        }
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                }
            }
            // The standalone preview has no rules editor to sit beside, so it
            // only appears for the non-AI options — `.ai` shows the same rows
            // inside the AI Sort Rules sub-menu instead.
            if sortOption != .ai {
                Section {
                    NavigationLink {
                        FilteredRemindersListView(displays: listDisplays)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("View sorted and filtered list")
                                SettingsCaption(text: "Preview how your reminders are ordered right now.")
                            }
                        } icon: {
                            Image(systemName: "list.number")
                        }
                    }
                    .accessibilityIdentifier("filterSortShowListRow")
                }
            }
        }
        .localizedNavigationTitle("Filtering & Sorting")
        .settingsSubscreenLayout()
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]),
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false))
    }
}
