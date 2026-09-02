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

    /// Forwarded to `CardPlate.promptBoxFill`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let promptBoxFill = CardPlate.promptBoxFill

    /// Forwarded to `CardPlate.cornerRadius`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let plateCornerRadius: CGFloat = CardPlate.cornerRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if showSwipePrompt {
                prompt
            }
        }
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)
    }

    /// Forwarded to `CardPlate.plateFill(for:)`; kept so existing call sites
    /// and tests compile until the full migration lands. See `CardPlate.swift`.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        CardPlate.plateFill(for: colorScheme)
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
                        .accessibilityLabel(SharedStrings.priorityAccessibilityLabel(level.displayName))
                        .accessibilityIdentifier("priorityMarker")
                }
                Text(display.titleAttributed)
                    .font(.title)
            }
            HStack {
                if showDate, let due = display.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dueDateText")
                }
                if showRecurrence, display.hasRecurrence {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .accessibilityHidden(true)
                        Text(display.recurrenceSummary ?? SharedStrings.repeats)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("recurrenceLabel")
                }
            }

            if showList, let listName = display.listName, !listName.isEmpty {
                Text(listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("listNameText")
            }

            if showAlarms, display.hasAlarms {
                Image(systemName: "bell")
                    .accessibilityLabel(String(localized: "Has alarm", table: "Localizable", bundle: .main))
                    .accessibilityIdentifier("alarmLabel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notesAttr = display.notesAttributed {
                Text(notesAttr)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .accessibilityIdentifier("notesText")
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
            .accessibilityIdentifier("swipePromptDismissButton")
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Self.plateCornerRadius)
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
