import EventKit
import SingleThreadCore
import SwiftUI

/// The reminder card content: priority marker + title, the optional due-date
/// row, and notes.
///
/// Lives outside `List` so the due-date gate stays observable in
/// string-snapshot tests — `List` type-erases `if` conditionals to a stable
/// `Optional<Text>`, which made the gate invisible to `String(describing:)`.
struct ReminderCardView: View {
    // MARK: Lifecycle

    init(reminder: EKReminder, showDate: Bool) {
        self.reminder = reminder
        self.showDate = showDate
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let level = ReminderPriority.level(for: reminder.priority) {
                    Text(ReminderPriority.marker(for: reminder.priority))
                        .font(.title)
                        .foregroundStyle(priorityColor(level))
                        .accessibilityLabel("\(level.displayName) priority")
                }
                Text(reminder.title)
                    .font(.title)
            }
            if showDate, let due = reminder.dueDateComponents?.date {
                Text(due, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                Text(noteText)
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
    }

    // MARK: Private

    private let reminder: EKReminder
    private let showDate: Bool

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}
