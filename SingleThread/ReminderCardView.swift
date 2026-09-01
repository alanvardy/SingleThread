import SingleThreadCore
import SwiftUI

/// The reminder card content: priority marker + title, the optional due-date
/// and list-name rows, notes, and the dismissible swipe-instruction prompt.
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
        showAlarms: Bool = true,
        showSwipePrompt: Binding<Bool> = .constant(false)) {
        self.display = display
        self.showDate = showDate
        self.showList = showList
        self.showRecurrence = showRecurrence
        self.showAlarms = showAlarms
        _showSwipePrompt = showSwipePrompt
    }

    // MARK: Internal

    /// Dark grey plate behind the swipe instructions and Dismiss button so the
    /// coloured hints read as one dismissible prompt on the card — in both the
    /// off-white (light) and black (dark) card-plate modes. Extracted because
    /// the rendered paint can't be asserted headlessly — tests assert this
    /// decision instead.
    static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)

    /// Shared corner radius for content plates: the card text plate and the
    /// empty-state material plate. Extracted because the rendered shape can't be
    /// asserted headlessly — tests assert this decision instead.
    static let emptyStateCornerRadius: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if showSwipePrompt {
                prompt
            }
        }
        // The card text always sits on its own small, content-sized high-contrast
        // plate (off-white in light, black in dark) so it stays readable over the
        // photo or the wallpaper on every device. The padding pair grows the view
        // to fit the plate, then restores the original outer geometry so list
        // metrics are unchanged.
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Self.emptyStateCornerRadius)
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

    /// Bound to the app's persisted `showSwipePrompt` preference; the Dismiss
    /// button writes `false` through this binding.
    @Binding private var showSwipePrompt: Bool

    private let display: ReminderDisplay
    private let showDate: Bool
    private let showList: Bool

    /// True when the recurrence indicator row is shown.
    private let showRecurrence: Bool

    /// True when the alarm indicator row is shown.
    private let showAlarms: Bool

    /// The card's reminder content, combined into a single accessible element so
    /// VoiceOver reads the whole card as one unit. The swipe-instruction prompt
    /// lives outside this subtree so its Dismiss button stays individually
    /// reachable.
    private var content: some View {
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
    }

    /// Instructs the user that swiping left skips and swiping right completes.
    /// Visual-only: the text is hidden from accessibility (VoiceOver users know
    /// the swipe-gesture vocabulary), but the Dismiss button stays reachable.
    private var prompt: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                    Text("Swipe left to skip")
                }
                .foregroundStyle(.orange)

                Text("|")
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    Text("Swipe right to complete")
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.green)
            }
            .font(.caption)
            .accessibilityHidden(true)

            Button {
                showSwipePrompt = false
            } label: {
                Text("Dismiss")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            // Caption-sized text alone falls below the 44pt accessibility
            // hit-region minimum; stretch the button's frame vertically so
            // the hit area passes the audit. Padding on the label content
            // does not expand the accessibility frame, so it goes on the
            // button itself.
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityLabel("Dismiss swipe prompt")
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Self.promptBoxFill)
        }
    }

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}
