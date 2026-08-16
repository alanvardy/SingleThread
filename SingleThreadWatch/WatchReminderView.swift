import EventKit
import SingleThreadCore
import SwiftUI
import WatchKit

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
        .focusable(true)
        .digitalCrownRotation(
            $crownRotation,
            onChange: { event in
                crownDetector.record(offset: event.offset)
            },
            onIdle: {
                refreshIfNeeded()
            })
        .task {
            await store.start()
        }
    }

    // MARK: Private

    @State private var crownDetector = CrownRefreshDetector()
    @State private var crownRotation = 0.0

    private let store: ReminderStore

    private var allSkipped: Bool {
        store.visibleReminders.isEmpty && !store.reminders.isEmpty
    }

    @ViewBuilder private var reminderContent: some View {
        if allSkipped {
            VStack {
                Text("All Done")
                    .font(.headline)
                Text("Turn the crown to see all")
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
            VStack {
                Text("No Reminders")
                    .foregroundStyle(.secondary)
                Text("Turn the crown to refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshIfNeeded() {
        guard crownDetector.settle() else { return }
        WKInterfaceDevice.current().play(.click)
        let clearSkipped = allSkipped
        Task {
            await store.reload(clearSkipped: clearSkipped)
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
