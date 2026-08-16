import EventKit
import SingleThreadCore
import SwiftUI

struct WatchReminderView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (production or preview).
    init(store: ReminderStore) {
        self.store = store
    }

    // MARK: Internal

    var body: some View {
        Group {
            switch store.authorizationStatus {
            case .notDetermined:
                ProgressView("Requesting access…")
            case .fullAccess:
                reminderContent
            default:
                Text("Enable Reminders access in Settings")
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            await store.start()
        }
    }

    // MARK: Private

    private let store: ReminderStore

    @ViewBuilder private var reminderContent: some View {
        if store.visibleReminders.isEmpty && !store.reminders.isEmpty {
            VStack {
                Text("All Done")
                    .font(.headline)
                Text("Pull down to see all")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let reminder = store.visibleReminders.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let level = ReminderPriority.level(for: reminder.priority) {
                        Text(ReminderPriority.marker(for: reminder.priority))
                            .font(.headline)
                            .foregroundStyle(priorityColor(level))
                    }
                    Text(reminder.title)
                        .font(.headline)
                        .lineLimit(3)
                }
                if let due = reminder.dueDateComponents?.date {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                    Text(noteText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Button {
                        Task { await store.completeCurrentReminder() }
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.green)

                    Button {
                        store.skipCurrentReminder()
                    } label: {
                        Label("Skip", systemImage: "circle.slash")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.orange)
                }
            }
            .padding()
        } else {
            Text("No Reminders")
                .foregroundStyle(.secondary)
        }
    }

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}
