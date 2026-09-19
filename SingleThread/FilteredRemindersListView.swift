import SingleThreadCore
import SwiftUI

// MARK: - FilteredRemindersListView

/// Read-only list of every reminder currently visible under the Filtering &
/// Sorting preferences, in the order the store sorted them. Pushed from the
/// Filtering & Sorting sub-menu so the effect of a sort/filter choice is
/// visible at a glance — the main surface shows one card at a time.
struct FilteredRemindersListView: View {
    // MARK: Internal

    let displays: [ReminderDisplay]

    var body: some View {
        Form {
            if displays.isEmpty {
                Text("No reminders match the current filters.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filteredRemindersEmptyState")
            } else {
                ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                    row(for: display)
                }
            }
        }
        .localizedNavigationTitle("Sorted & Filtered")
        .settingsSubscreenLayout()
    }

    // MARK: Private

    private func row(for display: ReminderDisplay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
            let caption = caption(for: display)
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filteredRemindersRow")
    }

    /// `ReminderDisplay`'s non-title fields as one caption line, skipping the
    /// fields this reminder does not have. Plain caption styling rather than
    /// `SettingsCaption`, because the string is composed at runtime and
    /// `SettingsCaption` takes a `LocalizedStringKey`.
    private func caption(for display: ReminderDisplay) -> String {
        var parts: [String] = []
        if let listName = display.listName, !listName.isEmpty {
            parts.append(listName)
        }
        if let dueDate = display.dueDate {
            parts.append(dueDate.formatted(date: .abbreviated, time: .omitted))
        }
        if !display.priorityMarker.isEmpty {
            parts.append(display.priorityMarker)
        }
        return parts.joined(separator: " · ")
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
