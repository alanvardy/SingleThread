import AppIntents
import EventKit
import SingleThreadCore
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct NextThingEntry: TimelineEntry {
    let date: Date
    let state: ListContent
    let showsDate: Bool
    let showsList: Bool
    let showsRecurrence: Bool
    let showsAlarms: Bool
}

// MARK: - Provider

struct NextThingProvider: TimelineProvider {
    // MARK: Internal

    func placeholder(in _: Context) -> NextThingEntry {
        NextThingEntry(
            date: Date(),
            state: .reminder(ReminderDisplay(title: "Next thing")),
            showsDate: true,
            showsList: true,
            showsRecurrence: true,
            showsAlarms: true)
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (NextThingEntry) -> Void) {
        completion(
            NextThingEntry(
                date: Date(),
                state: .reminder(ReminderDisplay(title: "Buy groceries")),
                showsDate: true,
                showsList: true,
                showsRecurrence: true,
                showsAlarms: true))
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
        let showsDate = ShowDatePreference().isEnabled
        let showsList = ShowListPreference().isEnabled
        let showsRecurrence = ShowRecurrencePreference().isEnabled
        let showsAlarms = ShowAlarmsPreference().isEnabled
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            let store = ReminderStore(loadsReminders: true)
            store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            return NextThingEntry(
                date: date,
                state: store.listContent,
                showsDate: showsDate,
                showsList: showsList,
                showsRecurrence: showsRecurrence,
                showsAlarms: showsAlarms)
        default:
            return NextThingEntry(
                date: date,
                state: .noAccess,
                showsDate: showsDate,
                showsList: showsList,
                showsRecurrence: showsRecurrence,
                showsAlarms: showsAlarms)
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
        .configurationDisplayName(
            LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main))
        .description(
            LocalizedStringResource(
                "Your next reminder, with Complete and Skip.",
                table: "Localizable",
                bundle: .main))
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
                title: SharedStrings.remindersAccess,
                systemImage: "lock.shield",
                message: String(
                    localized: "Open SingleThread to enable access.",
                    table: "Localizable",
                    bundle: .main))
        case let .empty(hasHidden):
            messageView(
                title: SharedStrings.noReminders,
                systemImage: "checklist",
                message: hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet)
        case .allDone:
            messageView(
                title: SharedStrings.allDone,
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
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(.green)
            .buttonStyle(.bordered)
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")

            Button(intent: SkipReminderIntent()) {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
            }
            .tint(.orange)
            .buttonStyle(.bordered)
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
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
                .accessibilityIdentifier("emptyStateTitle")
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
                        .accessibilityIdentifier("priorityMarker")
                }
                Text(display.titleAttributed)
                    .font(.headline)
                    .lineLimit(2)
            }
            if entry.showsDate, let dueDate = display.dueDate {
                Text(dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.showsList, let listName = display.listName, !listName.isEmpty {
                Text(listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.showsRecurrence, display.hasRecurrence {
                Label(display.recurrenceSummary ?? SharedStrings.repeats, systemImage: "repeat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("recurrenceLabel")
            }
            if entry.showsAlarms, display.hasAlarms {
                Label(SharedStrings.alert, systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("alertLabel")
            }
            if let notesAttr = display.notesAttributed {
                Text(notesAttr)
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
            title: "Use `map`",
            notes: "```\nlet x = 1\n```",
            dueDate: Date(),
            priorityMarker: "!!",
            listName: "Groceries")),
        showsDate: true,
        showsList: true,
        showsRecurrence: true,
        showsAlarms: true)
}

#Preview("No Access", as: .systemMedium) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .noAccess,
        showsDate: true,
        showsList: true,
        showsRecurrence: true,
        showsAlarms: true)
}

#Preview("All Done", as: .systemSmall) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .allDone,
        showsDate: true,
        showsList: true,
        showsRecurrence: true,
        showsAlarms: true)
}
