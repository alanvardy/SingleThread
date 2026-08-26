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
