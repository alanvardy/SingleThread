import AppIntents
import EventKit
import SingleThreadCore
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct NextThingEntry: TimelineEntry {
    enum State {
        case noAccess
        case empty
        case allDone
        case reminder(ReminderDisplay)
    }

    let date: Date
    let state: State
}

// MARK: - Provider

struct NextThingProvider: TimelineProvider {
    // MARK: Internal

    func placeholder(in _: Context) -> NextThingEntry {
        NextThingEntry(
            date: Date(),
            state: .reminder(ReminderDisplay(title: "Next thing")))
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (NextThingEntry) -> Void) {
        completion(
            NextThingEntry(
                date: Date(),
                state: .reminder(ReminderDisplay(title: "Buy groceries"))))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<NextThingEntry>) -> Void) {
        Task {
            let entry = await Self.makeEntry()
            let refresh = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    // MARK: Private

    @MainActor
    private static func makeEntry() async -> NextThingEntry {
        let date = Date()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            let store = ReminderStore(loadsReminders: true)
            store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
            await store.reload()
            if store.reminders.isEmpty {
                return NextThingEntry(date: date, state: .empty)
            }
            guard let current = store.visibleReminders.first else {
                return NextThingEntry(date: date, state: .allDone)
            }
            return NextThingEntry(
                date: date,
                state: .reminder(ReminderDisplay(reminder: current)))
        default:
            return NextThingEntry(date: date, state: .noAccess)
        }
    }
}

// MARK: - Widget

struct NextThingWidget: Widget {
    let kind = "NextThing"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextThingProvider()) { entry in
            NextThingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Thing")
        .description("Your next reminder, with Complete and Skip.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - View

struct NextThingWidgetView: View {
    // MARK: Internal

    let entry: NextThingEntry

    var body: some View {
        switch entry.state {
        case .noAccess:
            messageView(
                title: "Reminders Access",
                systemImage: "lock.shield",
                message: "Open SingleThread to enable access.")
        case .empty:
            messageView(
                title: "No Reminders",
                systemImage: "checklist",
                message: nil)
        case .allDone:
            messageView(
                title: "All Done",
                systemImage: "checkmark.circle",
                message: nil)
        case let .reminder(display):
            reminderView(display)
        }
    }

    // MARK: Private

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(intent: CompleteReminderIntent()) {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(.green)
            .buttonStyle(.bordered)
            .accessibilityLabel("Complete reminder")

            Button(intent: SkipReminderIntent()) {
                Label("Skip", systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
            }
            .tint(.orange)
            .buttonStyle(.bordered)
            .accessibilityLabel("Skip reminder")
        }
    }

    private func messageView(title: String, systemImage: String, message: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reminderView(_ display: ReminderDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if !display.priorityMarker.isEmpty {
                    Text(display.priorityMarker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(display.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let dueDate = display.dueDate {
                Text(dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notes = display.notes {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            actionButtons
        }
    }
}

// MARK: - Previews

#Preview("Reminder", as: .systemMedium) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .reminder(ReminderDisplay(
            title: "Buy groceries",
            notes: "Don't forget the milk",
            dueDate: Date(),
            priorityMarker: "!!")))
}

#Preview("No Access", as: .systemMedium) {
    NextThingWidget()
} timeline: {
    NextThingEntry(date: Date(), state: .noAccess)
}

#Preview("All Done", as: .systemSmall) {
    NextThingWidget()
} timeline: {
    NextThingEntry(date: Date(), state: .allDone)
}
