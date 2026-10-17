import CoreGraphics
import SingleThreadCore
import SwiftUI

/// Tinted hint panel revealed behind the card while a swipe or pull-down is in
/// progress. Fill matches the prompt plate; icon+label take the adaptive
/// per-action hint colour, and opacity scales with `progress` so it intensifies
/// toward the threshold. The plate hugs the label rather than filling the row,
/// so the reveal is a small badge at the edge the card uncovers — not a
/// full-height slab — and is anchored to that edge by `alignment(for:)`.
struct SwipeRevealPanel: View {
    // MARK: Internal

    let outcome: SwipeGestureOutcome
    let progress: CGFloat

    /// True while the pull-down refresh is running: the refresh panel keeps its
    /// place under the card and swaps its glyph for a spinner.
    var isRefreshing = false

    var body: some View {
        Group {
            if isRefreshing {
                Label {
                    Text("Refreshing")
                } icon: {
                    ProgressView()
                }
            } else {
                Label(presentation.title, systemImage: presentation.systemImage)
            }
        }
        .font(.headline)
        .foregroundStyle(presentation.tint)
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme))
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: Self.alignment(for: outcome))
        .opacity(Double(progress))
    }

    /// Edge the label plate hugs. Complete is uncovered from the leading edge
    /// as the card travels right, Skip from the trailing edge as it travels
    /// left, More from the bottom edge as the card is lifted up, Refresh from
    /// the top edge as the card is pulled down. `.none` is never rendered, so
    /// its arm is an arbitrary placeholder. Extracted from the body so the
    /// placement decision is unit-testable — SwiftUI layout itself cannot be
    /// asserted headlessly.
    static func alignment(for outcome: SwipeGestureOutcome) -> Alignment {
        switch outcome {
        case .complete: .leading
        case .skip: .trailing
        case .more: .bottom
        case .refresh: .top
        case .none: .leading
        }
    }

    /// SF Symbol for the revealed direction. Extracted alongside `alignment(for:)`
    /// because a runtime `systemImage` string is not recoverable from SwiftUI's
    /// reflected view description.
    static func systemImage(for outcome: SwipeGestureOutcome) -> String {
        switch outcome {
        case .complete: "checkmark.circle.fill"
        case .skip: "arrow.left.circle.fill"
        case .more: "ellipsis.circle.fill"
        case .refresh: "arrow.clockwise.circle.fill"
        case .none: "circle"
        }
    }

    // MARK: Private

    /// Render data for one revealed direction.
    private struct Presentation {
        let title: LocalizedStringResource
        let systemImage: String
        let tint: Color
    }

    @Environment(\.colorScheme)
    private var colorScheme

    /// Label, icon and colour for the revealed direction, in one place so they
    /// cannot drift apart. The `.none` arm exists for exhaustiveness but is
    /// never rendered: the modifier omits the panel for `.none`.
    private var presentation: Presentation {
        switch outcome {
        case .complete:
            Presentation(
                title: SharedStrings.completeAction,
                systemImage: Self.systemImage(for: outcome),
                tint: CardPlate.completeHintColor(for: colorScheme))
        case .skip:
            Presentation(
                title: SharedStrings.skipAction,
                systemImage: Self.systemImage(for: outcome),
                tint: CardPlate.skipHintColor(for: colorScheme))
        case .more:
            Presentation(
                title: SharedStrings.moreAction,
                systemImage: Self.systemImage(for: outcome),
                tint: CardPlate.moreHintColor(for: colorScheme))
        case .refresh:
            Presentation(
                title: LocalizedStringResource("Refresh", table: "Localizable", bundle: .main),
                systemImage: Self.systemImage(for: outcome),
                tint: CardPlate.refreshHintColor(for: colorScheme))
        case .none:
            Presentation(
                title: SharedStrings.completeAction,
                systemImage: "circle",
                tint: .clear)
        }
    }
}

/// Reveal container for the swiped card: the tinted `SwipeRevealPanel` sits
/// behind, the offset card plate in front. Because it wraps only the plate —
/// never the surrounding swipe-guide chrome — the panel is pinned to the card's
/// own edges, so every action emerges from under the card. Hugs the card
/// vertically too: without the fixed size the flexible panel absorbs the
/// full-height proposal from the row's centering frame, which stranded the
/// `.bottom` "More" plate at the bottom of the screen. Extracted from
/// `SwipeToActModifier` so both constraints are assertable by reflection;
/// SwiftUI layout cannot be asserted headlessly.
struct SwipeRevealContainer<Content: View>: View {
    let revealedOutcome: SwipeGestureOutcome
    let progress: CGFloat

    var isRefreshing = false

    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            if revealedOutcome != .none {
                SwipeRevealPanel(
                    outcome: revealedOutcome,
                    progress: progress,
                    isRefreshing: isRefreshing)
            }
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Drag-to-act behaviour for the reminder card plate: locks the drag to a single
/// axis (right → complete, left → skip, up → more), reveals `SwipeRevealPanel`
/// behind the plate, fires `onOutcome` on release past `threshold`, and always
/// animates the plate back to zero.
///
/// The plate offset is a binding rather than private state so the owner can
/// shift the swipe-guide chrome alongside it — the guides keep moving with the
/// card without being part of the reveal container, which is what keeps the
/// panel anchored to the card plate.
struct SwipeToActModifier: ViewModifier {
    // MARK: Lifecycle

    init(
        offset: Binding<CGSize>,
        threshold: CGFloat = SwipeGesture.releaseDistance,
        pull: CGFloat = 0,
        isRefreshing: Bool = false,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) {
        _offset = offset
        self.threshold = threshold
        self.pull = pull
        self.isRefreshing = isRefreshing
        self.onOutcome = onOutcome
    }

    // MARK: Internal

    let threshold: CGFloat

    /// Downward pull from the list's pull-to-refresh surface, in points. Drives
    /// the `.refresh` reveal out of the card's top edge, matching the drag-driven
    /// reveals for the other three directions.
    let pull: CGFloat

    /// True while the refresh is running: holds the `.refresh` plate out and
    /// swaps its glyph for a spinner.
    let isRefreshing: Bool

    let onOutcome: (SwipeGestureOutcome) -> Void

    func body(content: Content) -> some View {
        SwipeRevealContainer(
            revealedOutcome: revealedOutcome,
            progress: progress,
            isRefreshing: isRefreshing) {
                content
                    .contentShape(Rectangle())
                    .offset(x: offset.width, y: verticalTravel)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let axis = lockedAxis ?? SwipeGesture.axis(for: value.translation)
                                lockedAxis = axis
                                offset = SwipeGesture.railed(value.translation, on: axis)
                            }
                            .onEnded { value in
                                let railed = lockedAxis.map {
                                    SwipeGesture.railed(value.translation, on: $0)
                                } ?? value.translation
                                lockedAxis = nil
                                let outcome = SwipeGesture.outcome(for: railed, threshold: threshold)
                                withAnimation(.snappy) { offset = .zero }
                                if outcome != .none {
                                    onOutcome(outcome)
                                }
                            })
                    .accessibilityAction(named: Text(SharedStrings.completeAction)) {
                        onOutcome(.complete)
                    }
                    .accessibilityAction(named: Text(SharedStrings.skipAction)) {
                        onOutcome(.skip)
                    }
                    .accessibilityAction(named: Text(SharedStrings.moreAction)) {
                        onOutcome(.more)
                    }
                    .accessibilityIdentifier("reminderCard")
            }
    }

    // MARK: Private

    @Binding private var offset: CGSize

    /// Rail the in-flight drag locked to. `nil` until the first `onChanged`
    /// fires, then held for the rest of the gesture so the card cannot leave
    /// its axis. Cleared on release.
    @State private var lockedAxis: SwipeAxis?

    /// Downward drags are left to the pull-to-refresh surface, so the plate only
    /// ever travels up from its own gesture; the pull adds its own downward
    /// travel on top.
    private var verticalTravel: CGFloat {
        min(offset.height, 0) + max(pull, 0)
    }

    /// `max(|dx|, |dy|) / threshold`, capped at 1 — the panel's reveal intensity.
    /// The denominator is floored at 1 so a zero threshold cannot divide by zero.
    private var progress: CGFloat {
        if isRefreshing {
            return 1
        }
        if pull > 0 {
            return PullToRefresh.progress(pull: pull)
        }
        return min(max(abs(offset.width), abs(offset.height)) / max(threshold, 1), 1)
    }

    /// `.refresh` wins while the pull-to-refresh surface is active; otherwise
    /// the direction follows the plate's own drag.
    private var revealedOutcome: SwipeGestureOutcome {
        if isRefreshing || pull > 0 {
            return .refresh
        }
        return SwipeGesture.revealedOutcome(forOffset: offset)
    }
}

extension View {
    /// Adds drag-to-complete (right) / drag-to-skip (left) / drag-to-more (up)
    /// plus a pull-down `.refresh` reveal, with the panel behind the view and a
    /// fixed release threshold. `offset` reports the plate's live travel so the
    /// caller can move adjacent chrome in step with it.
    func swipeToAct(
        offset: Binding<CGSize>,
        threshold: CGFloat = SwipeGesture.releaseDistance,
        pull: CGFloat = 0,
        isRefreshing: Bool = false,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) -> some View {
        modifier(SwipeToActModifier(
            offset: offset,
            threshold: threshold,
            pull: pull,
            isRefreshing: isRefreshing,
            onOutcome: onOutcome))
    }
}
