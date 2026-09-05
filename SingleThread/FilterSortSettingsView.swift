import SingleThreadCore
import SwiftUI

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, show-undated toggle, and the
/// Excluded Lists sub-menu. Takes only the bindings it needs rather than the
/// full bag so it cannot accidentally mutate unrelated preferences.
struct FilterSortSettingsView: View {
    @Binding var sortOption: SortOption

    @Binding var showUndatedReminders: Bool

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
        .navigationTitle("Filtering & Sorting")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        FilterSortSettingsView(
            sortOption: .constant(.priority),
            showUndatedReminders: .constant(false),
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]))
    }
}
