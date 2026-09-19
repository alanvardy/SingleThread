import SingleThreadCore
import SwiftUI

// MARK: - FilteredRemindersListView

/// Read-only list of every reminder currently visible under the Filtering &
/// Sorting preferences, in the order the store sorted them. Pushed from the
/// Filtering & Sorting sub-menu for every non-AI sort option so the effect of a
/// sort/filter choice is visible at a glance — the main surface shows one card
/// at a time. The AI option shows these same rows inside its rules sub-menu
/// instead (see ``AISortRulesView``).
struct FilteredRemindersListView: View {
    let displays: [ReminderDisplay]

    var body: some View {
        Form {
            if displays.isEmpty {
                Text("No reminders match the current filters.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filteredRemindersEmptyState")
            } else {
                ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                    ReminderDisplayRow(display: display, font: .body)
                }
            }
        }
        .localizedNavigationTitle("Sorted & Filtered")
        .settingsSubscreenLayout()
    }
}

// MARK: - Previews

#Preview("Rows") {
    NavigationStack {
        FilteredRemindersListView(displays: [
            ReminderDisplay(title: "Call the dentist", listName: "Personal"),
            ReminderDisplay(title: "Ship the release", priorityMarker: "!!"),
            ReminderDisplay(
                title: "Book flights",
                dueDate: Date(timeIntervalSince1970: 0),
                priorityMarker: "!!",
                listName: "Personal")
        ])
    }
}
