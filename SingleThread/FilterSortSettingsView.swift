import SingleThreadCore
import SwiftUI

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, show-undated toggle, the
/// Excluded Lists sub-menu, and a preview of the currently visible set. Takes
/// only the bindings it needs rather than the full bag so it cannot
/// accidentally mutate unrelated preferences. The store is read-only and
/// exists solely to render the list preview.
struct FilterSortSettingsView: View {
    @Binding var sortOption: SortOption

    @Binding var aiSortRules: String

    @Binding var showUndatedReminders: Bool

    let isAIRankingAvailable: Bool

    let availableLists: [String]

    @Binding var excludedLists: Set<String>

    let store: ReminderStore

    /// The current visible set as display rows — sorted and filtered by the
    /// store exactly as the main reminder card sees it. Internal so tests can
    /// assert the order without rendering the pushed destination.
    var listDisplays: [ReminderDisplay] {
        store.visibleReminders.map { reminder in ReminderDisplay(reminder: reminder) }
    }

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
                    if isAIRankingAvailable {
                        TextEditor(text: $aiSortRules)
                            .frame(minHeight: 88)
                            .accessibilityLabel(Text("AI Sort Rules"))
                            .accessibilityIdentifier("aiSortRulesEditor")
                    } else {
                        // No point offering a rules editor the device cannot use;
                        // explain the fallback instead.
                        Label {
                            Text(LocalizedStringKey(
                                "This device doesn't support on-device AI, "
                                    + "so reminders stay in priority order."))
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityIdentifier("aiSortUnavailableMessage")
                    }
                } header: {
                    Text("AI Sort Rules")
                } footer: {
                    if isAIRankingAvailable {
                        SettingsCaption(
                            text: "Describe how reminders should be ordered. On-device AI applies these rules.")
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
