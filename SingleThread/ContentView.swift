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
                    GeometryReader { geometry in
                        ScrollView {
                            if reminders.isEmpty {
                                ContentUnavailableView(
                                    "No Reminders",
                                    systemImage: "checklist",
                                    description: Text("You don't have any reminders yet."))
                                    .frame(minHeight: geometry.size.height)
                            } else {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)

                                    if let reminder = reminders.first {
                                        reminderCard(reminder)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: geometry.size.height)
                            }
                        }
                        .refreshable {
                            await loadReminders()
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

    static func shouldCompleteSwipe(translationWidth: CGFloat) -> Bool {
        translationWidth >= swipeCompletionThreshold
    }

    // MARK: Private

    private static let swipeCompletionThreshold: CGFloat = 120
    private static let swipeFlyOffDistance: CGFloat = 600

    @State private var dragOffset: CGSize = .zero
    @State private var isCompleting = false
    @State private var reminders: [EKReminder] = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let loadsReminders: Bool
    private let store = EKEventStore()

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isCompleting else { return }
                let horizontal = value.translation.width
                dragOffset = CGSize(width: max(horizontal, 0), height: 0)
            }
            .onEnded { value in
                handleSwipeEnd(translation: value.translation)
            }
    }

    private func reminderCard(_ reminder: EKReminder) -> some View {
        ZStack {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Complete")
                }
                .font(.headline)
                .foregroundStyle(.green)
                .padding(.leading, 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading) {
                Text(reminder.title)
                    .font(.headline)
                if let due = reminder.dueDateComponents?.date {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground)))
            .offset(x: dragOffset.width)
        }
        .padding(.horizontal)
        .gesture(dragGesture)
    }

    private func handleSwipeEnd(translation: CGSize) {
        guard !isCompleting else { return }
        if Self.shouldCompleteSwipe(translationWidth: translation.width) {
            isCompleting = true
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: Self.swipeFlyOffDistance, height: 0)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await completeReminder()
                dragOffset = .zero
                isCompleting = false
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
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
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: ReminderDateFilter.endOfToday(),
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
