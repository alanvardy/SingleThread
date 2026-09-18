import SingleThreadCore
import SwiftUI

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, show-undated toggle, and the
/// Excluded Lists sub-menu. Takes only the bindings it needs rather than the
/// full bag so it cannot accidentally mutate unrelated preferences.
struct FilterSortSettingsView: View {
    @Binding var sortOption: SortOption

    @Binding var aiSortRules: String

    @Binding var showUndatedReminders: Bool

    let isAIRankingAvailable: Bool

    let availableLists: [String]

    @Binding var excludedLists: Set<String>

    var body: some View {
        Form {
            Picker(selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
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
                    TextEditor(text: $aiSortRules)
                        .frame(minHeight: 88)
                        .accessibilityLabel(Text("AI Sort Rules"))
                        .accessibilityIdentifier("aiSortRulesEditor")
                } header: {
                    Text("AI Sort Rules")
                } footer: {
                    if isAIRankingAvailable {
                        SettingsCaption(
                            text: "Describe how reminders should be ordered. On-device AI applies these rules.")
                    } else {
                        SettingsCaption(
                            text: LocalizedStringKey(
                                "Describe how reminders should be ordered. "
                                    + "This device can't run on-device AI, so "
                                    + "reminders stay in priority order."))
                    }
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
            excludedLists: .constant([]))
    }
}
