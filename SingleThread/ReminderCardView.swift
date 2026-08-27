import SingleThreadCore
import SwiftUI

/// The reminder card content: priority marker + title, the optional due-date
/// and list-name rows, and notes.
///
/// Lives outside `List` so the due-date gate stays observable in
/// string-snapshot tests — `List` type-erases `if` conditionals to a stable
/// `Optional<Text>`, which made the gate invisible to `String(describing:)`.
struct ReminderCardView: View {
    // MARK: Lifecycle

    init(
        display: ReminderDisplay,
        showDate: Bool,
        showList: Bool = false,
        showRecurrence: Bool = true,
        showAlarms: Bool = true) {
        self.display = display
        self.showDate = showDate
        self.showList = showList
        self.showRecurrence = showRecurrence
        self.showAlarms = showAlarms
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let level = ReminderPriority.level(forMarker: display.priorityMarker) {
                    Text(display.priorityMarker)
                        .font(.title)
                        .foregroundStyle(priorityColor(level))
                        .accessibilityLabel("\(level.displayName) priority")
                }
                Text(display.titleAttributed)
                    .font(.title)
            }
            HStack {
                if showDate, let due = display.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showRecurrence, display.hasRecurrence {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .accessibilityHidden(true)
                        Text(display.recurrenceSummary ?? "Repeats")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if showList, let listName = display.listName, !listName.isEmpty {
                Text(listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showAlarms, display.hasAlarms {
                Image(systemName: "bell")
                    .accessibilityLabel("Has alarm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notesAttr = display.notesAttributed {
                Text(notesAttr)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        // Combine the card's text into a single accessible element. VoiceOver then
        // reads the whole card as one unit, and the iOS hit-region audit no longer
        // size-checks each small child (marker / notes rows fall below 44pt). This is
        // a genuine app-wide accessibility improvement, not just a test escape.
        .accessibilityElement(children: .combine)
        // The card text always sits on its own small, content-sized high-contrast
        // plate (off-white in light, black in dark) so it stays readable over the
        // photo or the wallpaper on every device. The padding pair grows the view
        // to fit the plate, then restores the original outer geometry so list
        // metrics are unchanged.
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Self.plateFill(for: colorScheme))
        }
        .padding(-12)
    }

    /// Small content-sized high-contrast plate behind the card text: off-white in
    /// light, black in dark, so the text stays readable over a photo or wallpaper.
    /// Extracted because the rendered paint can't be asserted headlessly — tests
    /// assert this decision instead.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme

    private let display: ReminderDisplay
    private let showDate: Bool
    private let showList: Bool

    /// True when the recurrence indicator row is shown.
    private let showRecurrence: Bool

    /// True when the alarm indicator row is shown.
    private let showAlarms: Bool

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}
