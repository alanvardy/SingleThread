import SingleThreadCore
import SwiftUI

// MARK: - ReminderDisplayRow

/// One reminder rendered as a title plus a caption line of the non-title fields
/// it has, skipping the fields this reminder does not have. Shared by the
/// standalone sorted-list screen and the AI Sort Rules sub-menu, which renders
/// it smaller so the editor and the list fit one screen. `captionText(for:)` is
/// a static so the composition is unit-testable without rendering.
struct ReminderDisplayRow: View {
    let display: ReminderDisplay
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(display.title)
                .font(font)
            let caption = Self.captionText(for: display)
            if !caption.isEmpty {
                Text(caption)
                    .font(font)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filteredRemindersRow")
    }

    /// `ReminderDisplay`'s non-title fields as one caption line. Plain caption
    /// styling rather than `SettingsCaption`, because the string is composed at
    /// runtime and `SettingsCaption` takes a `LocalizedStringKey`.
    static func captionText(for display: ReminderDisplay) -> String {
        var parts: [String] = []
        if let listName = display.listName, !listName.isEmpty {
            parts.append(listName)
        }
        if let dueDate = display.dueDate {
            parts.append(dueDate.formatted(date: .abbreviated, time: .omitted))
        }
        if !display.priorityMarker.isEmpty {
            parts.append(display.priorityMarker)
        }
        return parts.joined(separator: " · ")
    }
}
