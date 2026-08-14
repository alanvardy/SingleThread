import EventKit
import SwiftUI

extension EKReminder: @retroactive @unchecked Sendable {}

/// Computes the due-date boundary for the "today or overdue" filter.
nonisolated enum ReminderDateFilter {
    /// The last instant of today (23:59:59), so reminders due tomorrow are excluded.
    static func endOfToday(
        calendar: Calendar = .current,
        now: Date = Date()) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return startOfToday
        }
        return tomorrow.addingTimeInterval(-1)
    }
}

struct ContentView: View {
    // MARK: Lifecycle

    init(loadsReminders: Bool = true) {
        self.loadsReminders = loadsReminders
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus) {
        self.loadsReminders = loadsReminders
        _reminders = State(initialValue: reminders)
        _skippedIDs = State(initialValue: skippedIDs)
        _authorizationStatus = State(initialValue: authorizationStatus)
    }

    // MARK: Internal

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if loadsReminders {
                authGatedContent
            } else {
                reminderList
            }
        }
        .onAppear {
            print("[\(Date.now.timeIntervalSince1970)] onAppear \(authorizationStatus.rawValue)/\(reminders.count)")
        }
        .task {
            guard loadsReminders else { return }
            print("[\(Date.now.timeIntervalSince1970)] task start")
            let currentStatus = EKEventStore.authorizationStatus(for: .reminder)
            print("[\(Date.now.timeIntervalSince1970)] auth \(currentStatus.rawValue)")
            authorizationStatus = currentStatus
            if currentStatus == .fullAccess {
                await loadReminders()
            } else {
                await requestAccess()
            }
            print("[\(Date.now.timeIntervalSince1970)] task done")
        }
    }

    // MARK: Private

    @State private var reminders: [EKReminder] = []
    @State private var skippedIDs: Set<String> = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let loadsReminders: Bool
    private let store = EKEventStore()
    private let skipStore = SkippedReminderStore()

    private var visibleReminders: [EKReminder] {
        reminders.filter { !skippedIDs.contains($0.calendarItemIdentifier) }
    }

    /// Every fetched reminder has been skipped (but there are reminders to show again).
    private var allSkipped: Bool {
        !reminders.isEmpty && visibleReminders.isEmpty
    }

    @ViewBuilder private var authGatedContent: some View {
        switch authorizationStatus {
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
                    await loadReminders(clearSkipped: true)
                }
            } else if reminders.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "checklist",
                        description: Text("You don't have any reminders yet."))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await loadReminders()
                }
            } else {
                List {
                    if let reminder = visibleReminders.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                                .font(.title)
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
                            if let url = reminder.url {
                                Link(url.absoluteString, destination: url)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .frame(minHeight: viewHeight, alignment: .center)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await completeReminder() }
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                skipReminder()
                            } label: {
                                Label("Skip", systemImage: "circle.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadReminders()
                }
            }
        }
    }

    private func skipReminder() {
        guard let reminder = visibleReminders.first else { return }
        let fetchedIDs = reminders.map(\.calendarItemIdentifier)
        let updated = ReminderSkipLogic.skipping(
            reminder.calendarItemIdentifier,
            fetched: fetchedIDs,
            skipped: Array(skippedIDs))
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            skippedIDs = Set(updated)
            skipStore.save(updated)
        }
    }

    private func completeReminder() async {
        guard let reminder = visibleReminders.first else { return }
        do {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await loadReminders()
        } catch {
            print("[\(Date.now.timeIntervalSince1970)] complete error \(error)")
        }
    }

    private func requestAccess() async {
        print("[\(Date.now.timeIntervalSince1970)] requestAccess()")
        do {
            let granted = try await store.requestFullAccessToReminders()
            print("[\(Date.now.timeIntervalSince1970)] granted \(granted)")
            if granted {
                authorizationStatus = .fullAccess
                await loadReminders()
            } else {
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            print("[\(Date.now.timeIntervalSince1970)] error \(error)")
        }
    }

    private func loadReminders(clearSkipped: Bool = false) async {
        print("[\(Date.now.timeIntervalSince1970)] loadReminders()")
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: ReminderDateFilter.endOfToday(),
            calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                store.fetchReminders(matching: predicate) { results in
                    continuation.resume(returning: results ?? [])
                }
            }
        }
        reminders = fetched
        if clearSkipped {
            skippedIDs = []
            skipStore.save([])
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: fetched.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
        }
        print("[\(Date.now.timeIntervalSince1970)] done \(visibleReminders.count)/\(fetched.count)")
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
