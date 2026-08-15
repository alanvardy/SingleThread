import EventKit
import SingleThreadCore
import SwiftUI

struct ContentView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (used by the app entry point, which wires
    /// WatchConnectivity hooks onto the store before handing it to the view).
    init(store: ReminderStore) {
        self.store = store
    }

    init(loadsReminders: Bool = true) {
        store = ReminderStore(loadsReminders: loadsReminders)
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
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if store.loadsReminders {
                authGatedContent
            } else {
                reminderList
            }
        }
        .onAppear {
            print("[\(Date.now.timeIntervalSince1970)]"
                + " onAppear \(store.authorizationStatus.rawValue)/\(store.reminders.count)")
        }
        .task {
            await store.start()
        }
    }

    // MARK: Private

    private let store: ReminderStore

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private var allSkipped: Bool {
        !store.reminders.isEmpty && store.visibleReminders.isEmpty
    }

    @ViewBuilder private var authGatedContent: some View {
        switch store.authorizationStatus {
        case .notDetermined:
            ProgressView("Requesting access…")
        case .fullAccess:
            reminderList
        default:
            ContentUnavailableView(
                "Reminders Access",
                systemImage: "lock.shield",
                description: Text("Enable access in Settings to see your reminders."))
        }
    }

    private var reminderList: some View {
        GeometryReader { geometry in
            let viewHeight = geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
            if allSkipped {
                ScrollView {
                    ContentUnavailableView(
                        "All Done",
                        systemImage: "checkmark.circle",
                        description: Text("Pull to refresh to see all your reminders again."))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await store.reload(clearSkipped: true)
                }
            } else if store.reminders.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "checklist",
                        description: Text("You don't have any reminders yet."))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await store.reload()
                }
            } else {
                List {
                    if let reminder = store.visibleReminders.first {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if let level = ReminderPriority.level(for: reminder.priority) {
                                    Text(ReminderPriority.marker(for: reminder.priority))
                                        .font(.title)
                                        .foregroundStyle(priorityColor(level))
                                }
                                Text(reminder.title)
                                    .font(.title)
                            }
                            if let due = reminder.dueDateComponents?.date {
                                Text(due, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                                Text(noteText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .frame(minHeight: viewHeight, alignment: .center)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await store.completeCurrentReminder() }
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                store.skipCurrentReminder()
                            } label: {
                                Label("Skip", systemImage: "circle.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await store.reload()
                }
            }
        }
    }
}

// MARK: - Preview Helpers

private let mockReminder: EKReminder = {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.title = "Buy groceries"
    reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    reminder.url = URL(string: "https://example.com/shopping-list")
    return reminder
}()

// MARK: - Previews

#Preview("Empty") {
    ContentView(loadsReminders: false)
}

#Preview("With Reminder") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("All Skipped") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [mockReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("No Access") {
    ContentView(
        loadsReminders: true,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}
