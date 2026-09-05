import AppIntents
import SingleThreadCore
import SwiftUI
import WidgetKit

// MARK: - Widget

struct WatchNextThingWidget: Widget {
    let kind = "NextThingWatch"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchNextThingProvider()) { entry in
            WatchNextThingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(
            LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main))
        .description(
            LocalizedStringResource(
                "Your next reminder, with Complete and Skip.",
                table: "Localizable",
                bundle: .main))
        .supportedFamilies([.accessoryRectangular, .accessoryCorner, .accessoryCircular])
    }
}

// MARK: - View

struct WatchNextThingWidgetView: View {
    // MARK: Internal

    let entry: WatchNextThingEntry

    var body: some View {
        switch entry.state {
        case .noAccess:
            accessoryGlyph("lock.shield")
        case let .empty(hasHidden):
            accessoryGlyph(hasHidden ? "clock.badge.questionmark" : "checklist")
        case .allDone:
            accessoryGlyph("checkmark.circle")
        case let .reminder(display):
            accessoryReminder(display)
        }
    }

    // MARK: Private

    @Environment(\.widgetFamily) private var family: WidgetFamily

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteReminderIntent()) {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)

            Button(intent: SkipReminderIntent()) {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
        }
    }

    /// Rectangular complication carries a compact title, due date, and the
    /// interactive Complete/Skip buttons (Smart Stack only — WidgetKit strips
    /// them from complications). Corner/circular fall back to a single glyph so
    /// the complication is never blank.
    @ViewBuilder
    private func accessoryReminder(_ display: ReminderDisplay) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if !display.priorityMarker.isEmpty {
                        Text(display.priorityMarker)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(display.titleAttributed)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let dueDate = display.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                actionButtons
            }
        default:
            accessoryGlyph(display.priorityMarker.isEmpty ? "checklist" : "exclamationmark")
        }
    }

    private func accessoryGlyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
    }
}

// MARK: - Previews

#Preview("Reminder", as: .accessoryRectangular) {
    WatchNextThingWidget()
} timeline: {
    WatchNextThingEntry(
        date: Date(),
        state: .reminder(ReminderDisplay(title: "Use `map`", dueDate: Date())))
}

#Preview("No Access", as: .accessoryCircular) {
    WatchNextThingWidget()
} timeline: {
    WatchNextThingEntry(date: Date(), state: .noAccess)
}

#Preview("All Done", as: .accessoryCorner) {
    WatchNextThingWidget()
} timeline: {
    WatchNextThingEntry(date: Date(), state: .allDone)
}
