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
        showSwipePrompt: Binding<Bool> = .constant(false),
        showNudge: Bool = false,
        onNudgeTap: @escaping () -> Void = {},
        maxWidth: CGFloat = 340,
        pullOffset: CGFloat = 0,
        isRefreshing: Bool = false,
        onSwipe: @escaping (SwipeGestureOutcome) -> Void = { _ in }) {
        self.display = display
        self.showDate = showDate
        self.showList = showList
        self.showRecurrence = showRecurrence
        self.showAlarms = showAlarms
        _showSwipePrompt = showSwipePrompt
        self.showNudge = showNudge
        self.onNudgeTap = onNudgeTap
        self.maxWidth = maxWidth
        self.pullOffset = pullOffset
        self.isRefreshing = isRefreshing
        self.onSwipe = onSwipe
    }

    // MARK: Internal

    /// Vertical gap (in points) between the swipe-prompt chrome and the card —
    /// applied both above and below the card plate so the two black hint panels
    /// are separated by the card itself and never touch. Extracted so the gap
    /// can be asserted headlessly.
    static let promptPanelSpacing: CGFloat = 12

    /// Fill behind both swipe-hint panels: solid black so the tinted hints stay
    /// legible over any wallpaper in light and dark schemes.
    static let promptPanelFill = Color.black

    var body: some View {
        VStack(spacing: Self.promptPanelSpacing) {
            if showSwipePrompt {
                upGuidePanel
                    .offset(cardOffset)
            }
            cardPlate
            if showSwipePrompt {
                sideGuidePanel
                    .offset(cardOffset)
            }
        }
        .frame(maxWidth: maxWidth)
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme

    /// Routes inline link taps through the scene-installed opener.
    @Environment(\.openURL)
    private var openURL

    /// Bound to the app's persisted `showSwipePrompt` preference; the Dismiss
    /// button writes `false` through this binding.
    @Binding private var showSwipePrompt: Bool

    /// The plate's live travel, mirrored onto the prompt chrome so the guides
    /// travel with the card without being pulled into the reveal container —
    /// which would anchor the revealed plate to the chrome instead of the card.
    @State private var swipeOffset: CGSize = .zero

    private let display: ReminderDisplay
    private let showDate: Bool
    private let showList: Bool

    /// When true, an actionable nudge banner is shown under the card content.
    private let showNudge: Bool

    /// Tapped when the nudge banner is activated.
    private let onNudgeTap: () -> Void

    /// True when the recurrence indicator row is shown.
    private let showRecurrence: Bool

    /// True when the alarm indicator row is shown.
    private let showAlarms: Bool

    /// Caps the card's width so long titles wrap and the nudge banner/styled
    /// buttons stop expanding under the row's `.center` proposal on iPad.
    private let maxWidth: CGFloat

    /// Downward pull from the list's pull-to-refresh surface, in points.
    private let pullOffset: CGFloat

    /// True while the pull-down refresh is running.
    private let isRefreshing: Bool

    /// Fired when the plate's own swipe passes its release threshold.
    private let onSwipe: (SwipeGestureOutcome) -> Void

    /// Downward drags belong to the pull-to-refresh surface, so the plate only
    /// travels up from its own gesture; the pull adds downward travel on top.
    private var cardOffset: CGSize {
        CGSize(width: swipeOffset.width, height: min(swipeOffset.height, 0) + max(pullOffset, 0))
    }

    /// Every link in the card's title and notes, in reading order.
    private var linkURLs: [URL] {
        var urls = LinkFormatter.links(in: display.title)
        if let notes = display.notes {
            urls.append(contentsOf: LinkFormatter.links(in: notes))
        }
        return urls
    }

    /// The reminder content on its plate — and the swipe surface. Only this part
    /// is wrapped by the reveal container, so complete / skip / more / refresh
    /// all emerge from under the card itself.
    private var cardPlate: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if showNudge {
                nudgeBanner
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)
        .swipeToAct(
            offset: $swipeOffset,
            pull: pullOffset,
            isRefreshing: isRefreshing,
            onOutcome: onSwipe)
    }

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
                Text(display.titleAttributedWithLinks)
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
                    .accessibilityLabel(LocalizedStringResource("Has alarm", table: "Localizable", bundle: .main))
                    .accessibilityIdentifier("alarmLabel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notesAttr = display.notesAttributedWithLinks {
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
        .accessibilityActions {
            ForEach(Array(linkURLs.enumerated()), id: \.offset) { _, url in
                Button {
                    openURL(url)
                } label: {
                    Text(SharedStrings.openLink(to: url.host() ?? url.absoluteString))
                }
            }
        }
    }

    /// Tappable nudge banner. Unlike the swipe hint, NOT `.accessibilityHidden` —
    /// the nudge is actionable and must be screen-reader reachable.
    ///
    /// Sizes to its label (like the watch nudge) instead of `.frame(maxWidth:
    /// .infinity)`: an unbounded banner would stretch this compact content-hugging
    /// card plate edge-to-edge across the whole screen.
    private var nudgeBanner: some View {
        Button(action: onNudgeTap) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble")
                Text(SharedStrings.skipNudgeTitle)
                    .font(.caption.bold())
            }
            .foregroundStyle(.orange)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel(String(format: LocalizedStringResource(
            "Skipped %lld times — tap to manage",
            table: "Localizable",
            bundle: .main).resolvedInAppLanguage(), 6))
        .accessibilityIdentifier("skipNudgeBanner")
    }

    /// The up-guide badge on its black panel: `↑ Swipe up for more` centred,
    /// visual-only, above the card.
    private var upGuidePanel: some View {
        upGuide
            .cardPlate(fill: Self.promptPanelFill)
    }

    /// The bottom black panel carrying the horizontal guide row and the Dismiss
    /// button, below the card. Both side hints share one plate so the two
    /// labels read as a single dismissible group.
    private var sideGuidePanel: some View {
        VStack(spacing: Self.promptPanelSpacing) {
            horizontalGuide
            dismissButton
        }
        .cardPlate(fill: Self.promptPanelFill)
    }

    /// `↑ Swipe up for more`, centred above the card. Visual-only: the copy is
    /// hidden from accessibility (VoiceOver users get the card's swipe actions).
    private var upGuide: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.up")
            Text("Swipe up for more")
        }
        .font(.caption)
        .foregroundStyle(CardPlate.moreHintColor(for: colorScheme))
        .accessibilityHidden(true)
    }

    /// `← Swipe left to skip` and `Swipe right to complete →`, one row below the
    /// card, arrow on the outer edge of each side and tinted like its revealed
    /// panel. Visual-only.
    private var horizontalGuide: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Text("Swipe left to skip")
            }
            .foregroundStyle(CardPlate.skipHintColor(for: colorScheme))

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text("Swipe right to complete")
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(CardPlate.completeHintColor(for: colorScheme))
        }
        .font(.caption)
        .accessibilityHidden(true)
    }

    /// Hides the swipe guide: writes `false` through the persisted
    /// `showSwipePrompt` binding. Caption-sized, bordered-prominent, white pill
    /// so it always contrasts against the black hint panel behind it — a black
    /// pill would vanish into that panel in light mode.
    private var dismissButton: some View {
        Button {
            showSwipePrompt = false
        } label: {
            Text("Dismiss hints")
                .font(.caption.bold())
                .foregroundStyle(Color.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.white)
        // Caption-sized text alone falls below the 44pt accessibility
        // hit-region minimum; stretch the button's frame vertically so
        // the hit area passes the audit. Padding on the label content
        // does not expand the accessibility frame, so it goes on the
        // button itself.
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel("Dismiss swipe hints")
        .accessibilityIdentifier("swipePromptDismissButton")
    }

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}
