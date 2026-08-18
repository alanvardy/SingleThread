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
        crownRefreshContent
            .task {
                await store.start()
            }
    }

    // MARK: Private

    /// The refresh spinner stays visible for at least this long so brief
    /// EventKit fetches still read as a refresh.
    private static let refreshMinimumDisplayDuration: TimeInterval = 1

    @State private var crownDetector = CrownRefreshDetector()
    @State private var crownRotation = 0.0
    @State private var isRefreshing = false
    @State private var presentation = WatchReminderPresentation()

    private let store: ReminderStore

    private var allSkipped: Bool {
        store.visibleReminders.isEmpty && !store.reminders.isEmpty
    }

    // MARK: - Crown refresh gating

    /// When expanded, the `ScrollView` owns the Digital Crown for scrolling.
    /// Gating `.digitalCrownRotation` keeps the crown from being captured by
    /// both the ScrollView and the refresh gesture at the same time.
    @ViewBuilder private var crownRefreshContent: some View {
        if presentation.allowsCrownRefresh {
            statusContent
                .focusable(true)
                .digitalCrownRotation(
                    $crownRotation,
                    onChange: { event in
                        crownDetector.record(offset: event.offset)
                    },
                    onIdle: {
                        refreshIfNeeded()
                    })
        } else {
            statusContent
        }
    }

    private var statusContent: some View {
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
        .onChange(of: store.visibleReminders.first?.calendarItemIdentifier) { _, _ in
            presentation = WatchReminderPresentation()
        }
    }

    // MARK: - Reminder card

    private var reminderContent: some View {
        ZStack {
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
                    if presentation.isExpanded {
                        ScrollView {
                            reminderDetails(reminder)
                        }
                    } else {
                        reminderDetails(reminder)
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

            if isRefreshing {
                ProgressView()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top)
                    .padding(.top, 8)
            }
        }
    }

    /// Tappable reminder details — expandable to full length.
    private func reminderDetails(_ reminder: EKReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let level = ReminderPriority.level(for: reminder.priority) {
                    Text(ReminderPriority.marker(for: reminder.priority))
                        .font(.headline)
                        .foregroundStyle(priorityColor(level))
                }
                Text(reminder.title)
                    .font(.headline)
                    .lineLimit(presentation.isExpanded ? nil : 3)
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
                    .lineLimit(presentation.isExpanded ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            presentation.toggle()
        }
        .accessibilityLabel(presentation.isExpanded ? "Collapse reminder" : "Expand reminder")
        .accessibilityHint("Toggles full title and notes")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Refresh

    private func refreshIfNeeded() {
        guard crownDetector.settle(), !isRefreshing else { return }
        WKInterfaceDevice.current().play(.click)
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
