import EventKit
import SwiftUI

extension EKReminder: @retroactive @unchecked Sendable {}

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Group {
                switch authorizationStatus {
                case .notDetermined:
                    ProgressView("Requesting access…")
                case .fullAccess:
                    if reminders.isEmpty {
                        ContentUnavailableView(
                            "No Reminders",
                            systemImage: "checklist",
                            description: Text("You don't have any reminders yet."))
                    } else {
                        List(reminders, id: \.calendarItemIdentifier) { reminder in
                            VStack(alignment: .leading) {
                                Text(reminder.title)
                                    .font(.headline)
                                if let due = reminder.dueDateComponents?.date {
                                    Text(due, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let store = EKEventStore()

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

    private func loadReminders() async {
        print("[\(Date.now.timeIntervalSince1970)] loadReminders()")
        let endOfToday = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: Date()))!
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endOfToday,
            calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            print("[\(Date.now.timeIntervalSince1970)] fetch dispatch")
            DispatchQueue.main.async {
                store.fetchReminders(matching: predicate) { results in
                    let count = results?.count ?? 0
                    print("[\(Date.now.timeIntervalSince1970)] callback \(count)")
                    continuation.resume(returning: results ?? [])
                }
            }
        }
        reminders = Array(fetched.prefix(1))
        print("[\(Date.now.timeIntervalSince1970)] done \(reminders.count)/\(fetched.count)")
    }
}
