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
            glyph("lock.shield")
        case let .empty(hasHidden):
            glyph(hasHidden ? "clock.badge.questionmark" : "checklist")
        case .allDone:
            glyph("checkmark.circle")
        case let .reminder(display):
            Text(display.titleAttributed)
                .font(.headline)
                .lineLimit(1)
        }
    }

    // MARK: Private

    private func glyph(_ systemImage: String) -> some View {
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
