import EventKit
import SingleThreadCore
import Speech
import SwiftUI

struct ContentView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (used by the app entry point, which wires
    /// WatchConnectivity hooks onto the store before handing it to the view).
    init(store: ReminderStore, speechTranscriber: (any SpeechTranscribing)? = nil) {
        self.store = store
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
    }

    init(loadsReminders: Bool = true, speechTranscriber: (any SpeechTranscribing)? = nil) {
        store = ReminderStore(loadsReminders: loadsReminders)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        speechTranscriber: (any SpeechTranscribing)? = nil) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
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
        .task {
            await store.start()
        }
    }

    // MARK: Private

    @State private var isDictating = false
    @State private var dictationText = ""
    @State private var dictationError: String?

    private let store: ReminderStore
    private let speechTranscriber: any SpeechTranscribing

    private var allSkipped: Bool {
        !store.reminders.isEmpty && store.visibleReminders.isEmpty
    }

    private var canDictate: Bool {
        speechTranscriber.authorizationStatus == .authorized
            || speechTranscriber.authorizationStatus == .notDetermined
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
                ZStack(alignment: .bottom) {
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
                    micOverlay
                }
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        if let reminder = store.visibleReminders.first {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.title)
                                    .font(.title)
                                if let due = reminder.dueDateComponents?.date {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        if let level = ReminderPriority.level(for: reminder.priority) {
                                            Text(ReminderPriority.marker(for: reminder.priority))
                                                .font(.caption)
                                                .foregroundStyle(priorityColor(level))
                                        }
                                        Text(due, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
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
                    micOverlay
                }
            }
        }
    }

    // MARK: - Mic Dictation

    private var micOverlay: some View {
        VStack(spacing: 8) {
            if let error = dictationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if isDictating {
                if !dictationText.isEmpty {
                    Text(dictationText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                recordingIndicator
            } else if canDictate {
                micButton
            }
        }
        .padding(.bottom, 16)
    }

    private var micButton: some View {
        Button {
            Task { await startDictation() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.blue, in: Circle())
                .shadow(radius: 4)
        }
        .accessibilityLabel("Dictate reminder")
        .accessibilityAddTraits(.isButton)
    }

    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.red, in: Circle())
            .shadow(radius: 4)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
    }

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }

    private func startDictation() async {
        if speechTranscriber.authorizationStatus == .notDetermined {
            let status = await speechTranscriber.requestAuthorization()
            guard status == .authorized else {
                dictationError = "Speech recognition access is required."
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            dictationError = "Speech recognition access was denied."
            return
        }
        isDictating = true
        dictationText = ""
        dictationError = nil
        do {
            let result = try await speechTranscriber.transcribe { text in
                dictationText = text
            }
            let parsed = ReminderDictationParser.parse(result)
            if !parsed.title.isEmpty {
                await store.addReminder(
                    title: parsed.title,
                    notes: nil,
                    dueDate: parsed.dueDateComponents)
            }
        } catch {
            dictationError = error.localizedDescription
        }
        isDictating = false
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
