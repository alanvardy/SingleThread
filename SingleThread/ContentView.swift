import EventKit
import SwiftUI

extension EKReminder: @retroactive @unchecked Sendable {}

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
                    if reminders.isEmpty {
                        ContentUnavailableView(
                            "No Reminders",
                            systemImage: "checklist",
                            description: Text("You don't have any reminders yet."))
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            if let reminder = reminders.first {
                                VStack(alignment: .leading) {
                                    Text(reminder.title)
                                        .font(.headline)
                                    if let due = reminder.dueDateComponents?.date {
                                        Text(due, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal)
                            }

                            Spacer(minLength: 0)

                            completeButton
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
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let loadsReminders: Bool
    private let store = EKEventStore()

    private var completeButton: some View {
        Button {
            Task { await completeReminder() }
        } label: {
            Label("Mark Complete", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 0)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom))
    }

    private func completeReminder() async {
        guard let reminder = reminders.first else { return }
        do {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
            reminders.removeFirst()
            await loadReminders()
        } catch {
            print("[\\(Date.now.timeIntervalSince1970)] complete error \\(error)")
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(loadsReminders: false)
    }
}
