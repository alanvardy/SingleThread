import EventKit
import SwiftUI

/// Reschedule picker shared by the skip-nudge sheet and the action menu.
/// Callers wrap it in a `NavigationStack` and provide Cancel in their own
/// toolbar; it renders the optional nudge message, a date-only / date+time
/// picker tailored to the reminder, and the Reschedule confirm button.
struct RescheduleSheet: View {
    // MARK: Internal

    let reminder: EKReminder?
    let onReschedule: (DateComponents) async -> Bool
    let onCancel: () -> Void
    let nudgeMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let nudgeMessage {
                Text(nudgeMessage)
                    .font(.headline)
                    .accessibilityIdentifier("nudgeSheetTitle")
            }

            DatePicker(
                "Reschedule to",
                selection: $date,
                displayedComponents: Self.displayedComponents(
                    hasDueTime: Self.hasDueTime(reminder)))
                .accessibilityIdentifier("rescheduleDatePicker")

            HStack {
                Spacer()
                Button {
                    let components = Calendar.current.dateComponents(
                        Self.dateComponentsMask(hasDueTime: Self.hasDueTime(reminder)),
                        from: date)
                    Task {
                        if await onReschedule(components) {
                            onCancel()
                        }
                    }
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("rescheduleConfirmButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the reminder carries a due time, so the picker (and the written
    /// back components) omit time for reminders that never had one.
    static func hasDueTime(_ reminder: EKReminder?) -> Bool {
        guard let reminder, let components = reminder.dueDateComponents else { return false }
        return components.hour != nil
    }

    /// The `DatePicker` component set for a reminder with or without a due time.
    static func displayedComponents(hasDueTime: Bool) -> DatePicker.Components {
        hasDueTime ? [.date, .hourAndMinute] : [.date]
    }

    /// The calendar-component mask used when writing the picked date back.
    static func dateComponentsMask(hasDueTime: Bool) -> Set<Calendar.Component> {
        hasDueTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
    }

    // MARK: Private

    @State private var date = Date().addingTimeInterval(86400)
}
