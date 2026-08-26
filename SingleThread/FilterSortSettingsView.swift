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
            Picker("Sort By", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            Toggle(isOn: $showUndatedReminders) {
                Label("Show undated reminders", systemImage: "calendar.badge.minus")
            }
            Section {
                NavigationLink {
                    ExcludedListsView(
                        excludedLists: $excludedLists,
                        availableLists: availableLists)
                } label: {
                    Label("Excluded Lists", systemImage: "eye.slash")
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
