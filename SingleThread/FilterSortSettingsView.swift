import SingleThreadCore
import SwiftUI

// MARK: - ExcludedListsView

/// Submenu listing the lists the user has chosen to exclude. Pushed from the
/// filtering & sorting sub-menu so the main settings screen stays focused on
/// its core preference groups.
struct ExcludedListsView: View {
    // MARK: Lifecycle

    init(excludedLists: Binding<Set<String>>, availableLists: [String]) {
        _excludedLists = excludedLists
        self.availableLists = availableLists
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section {
                ForEach(availableLists, id: \.self) { list in
                    Toggle(isOn: excludedBinding(for: list)) {
                        Text(list)
                    }
                }
            } footer: {
                Text("Excluded lists are hidden from the reminder list.")
            }
        }
        .navigationTitle("Excluded Lists")
    }

    // MARK: Private

    @Binding private var excludedLists: Set<String>

    private let availableLists: [String]

    private func excludedBinding(for list: String) -> Binding<Bool> {
        Binding(
            get: { excludedLists.contains(list) },
            set: { isExcluded in
                if isExcluded {
                    excludedLists.insert(list)
                } else {
                    excludedLists.remove(list)
                }
            })
    }
}

// MARK: - FilterSortSettingsView

/// Filtering and sorting preferences: sort order, show-undated toggle, and the
/// Excluded Lists sub-menu. Bound through the shared `@Observable` bag; the
/// excluded lists set is store-backed and passed separately as a binding.
struct FilterSortSettingsView: View {
    @Bindable var bindings: SettingsBindings

    let availableLists: [String]

    @Binding var excludedLists: Set<String>

    var body: some View {
        Form {
            Picker("Sort By", selection: $bindings.sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            Toggle(isOn: $bindings.showUndatedReminders) {
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
            bindings: SettingsBindings(),
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]))
    }
}
