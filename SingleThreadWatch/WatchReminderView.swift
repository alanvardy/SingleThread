import EventKit
import SingleThreadCore
import SwiftUI

struct WatchReminderView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (production or preview).
    init(store: ReminderStore) {
        self.store = store
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus)
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

    /// The refresh spinner stays visible for at least this long so brief
    /// EventKit fetches still read as a refresh.
    private static let refreshMinimumDisplayDuration: TimeInterval = 1

    @State private var isRefreshing = false
    @State private var isShowingRefreshConfirmation = false

    @AppStorage("showDate")
    private var showDate = true

    private let store: ReminderStore

    private var allSkipped: Bool {
        store.visibleReminders.isEmpty && !store.reminders.isEmpty
    }

    // MARK: - Content

    private var reminderContent: some View {
        ZStack {
            if allSkipped {
                allDoneState
            } else if let reminder = store.visibleReminders.first {
                reminderCard(reminder)
            } else {
                noRemindersState
            }

            if isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
    }

    private var actionButtons: some View {
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

    private var allDoneState: some View {
        VStack(spacing: 6) {
            Text("All Done")
                .font(.headline)
            refreshButton
        }
    }

    private var noRemindersState: some View {
        VStack(spacing: 6) {
            Text("No Reminders")
                .foregroundStyle(.secondary)
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button("Refresh") {
            refresh()
        }
        .disabled(isRefreshing)
    }

    /// The reminder is always scrollable so long titles and notes are never cut off.
    private func reminderCard(_ reminder: EKReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                reminderDetails(reminder)
            }
            .onLongPressGesture {
                isShowingRefreshConfirmation = true
            }
            .confirmationDialog("Reminder", isPresented: $isShowingRefreshConfirmation) {
                Button("Refresh") {
                    refresh()
                }

                Button("Delete", role: .destructive) {
                    Task { await store.deleteCurrentReminder() }
                }
            }

            actionButtons
        }
        .padding()
    }

    private func reminderDetails(_ reminder: EKReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let level = ReminderPriority.level(for: reminder.priority) {
                    Text(ReminderPriority.marker(for: reminder.priority))
                        .font(.headline)
                        .foregroundStyle(priorityColor(level))
                        .accessibilityLabel("\(level.displayName) priority")
                }
                Text(reminder.title)
                    .font(.headline)
            }
            if showDate, let due = reminder.dueDateComponents?.date {
                Text(due, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                Text(noteText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Refresh

    private func refresh() {
        guard !isRefreshing else { return }
        let clearSkipped = allSkipped
        isRefreshing = true
        let startedAt = Date()
        Task {
            await store.reload(clearSkipped: clearSkipped)
            let remaining = MinimumDisplayDuration.remainingSleep(
                elapsed: Date().timeIntervalSince(startedAt),
                minimum: Self.refreshMinimumDisplayDuration)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            isRefreshing = false
        }
    }

    // MARK: - Helpers

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}

// MARK: - Previews

private let mockWatchReminder: EKReminder = {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 18, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    return reminder
}()

#Preview("Requesting Access") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .notDetermined)
}

#Preview("Reminder") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [mockWatchReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("All Skipped") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [mockWatchReminder],
        skippedIDs: [mockWatchReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("No Reminders") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("No Access") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}
