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
        return calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: startOfToday)!
    }
}

struct ContentView: View {
    // MARK: Lifecycle

    init(loadsReminders: Bool = true) {
        self.loadsReminders = loadsReminders
    }

    // MARK: Internal

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Group {
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

    private var reminderList: some View {
        GeometryReader { geometry in
            let rowHeight = geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
            List {
                if allSkipped {
                    ContentUnavailableView(
                        "All Done",
                        systemImage: "checkmark.circle",
                        description: Text("Pull to refresh to see all your reminders again."))
                        .listRowSeparator(.hidden)
                } else if reminders.isEmpty {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "checklist",
                        description: Text("You don't have any reminders yet."))
                        .listRowSeparator(.hidden)
                } else if let reminder = visibleReminders.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.title)
                            .font(.headline)
                        if let due = reminder.dueDateComponents?.date {
                            Text(due, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: rowHeight, alignment: .center)
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
                let shouldClear = allSkipped
                await loadReminders(clearSkipped: shouldClear)
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
        skippedIDs = Set(updated)
        skipStore.save(updated)
    }

    private func completeReminder() async {
        guard let reminder = visibleReminders.first else { return }
        do {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(loadsReminders: false)
    }
}
