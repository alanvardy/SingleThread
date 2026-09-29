import CoreGraphics
import SingleThreadCore
import SwiftUI

/// Tinted hint panel revealed behind the card while a swipe is in progress.
/// Fill matches the prompt plate; icon+label take the adaptive Complete/Skip
/// hint colours, and opacity scales with `progress` so it intensifies toward
/// the threshold.
struct SwipeRevealPanel: View {
    // MARK: Internal

    let outcome: SwipeGestureOutcome
    let progress: CGFloat

    var body: some View {
        Label(presentation.title, systemImage: presentation.systemImage)
            .font(.headline)
            .foregroundStyle(presentation.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardPlate(fill: CardPlate.plateFill(for: colorScheme))
            .opacity(Double(progress))
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
                systemImage: "checkmark.circle.fill",
                tint: CardPlate.completeHintColor(for: colorScheme))
        case .skip:
            Presentation(
                title: SharedStrings.skipAction,
                systemImage: "circle.slash",
                tint: CardPlate.skipHintColor(for: colorScheme))
        case .none:
            Presentation(
                title: SharedStrings.completeAction,
                systemImage: "circle",
                tint: .clear)
        }
    }
}

/// Drag-to-act behaviour for the reminder card: tracks horizontal travel,
/// reveals `SwipeRevealPanel` behind the card, fires `onOutcome` on release past
/// `threshold`, and always animates the card back to zero.
struct SwipeToActModifier: ViewModifier {
    // MARK: Lifecycle

    init(
        threshold: CGFloat = SwipeGesture.releaseDistance,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) {
        self.threshold = threshold
        self.onOutcome = onOutcome
    }

    // MARK: Internal

    let threshold: CGFloat
    let onOutcome: (SwipeGestureOutcome) -> Void

    func body(content: Content) -> some View {
        ZStack {
            if revealedOutcome != .none {
                SwipeRevealPanel(outcome: revealedOutcome, progress: progress)
            }
            content
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let outcome = SwipeGesture.outcome(
                                for: value.translation,
                                threshold: threshold)
                            withAnimation(.snappy) { dragOffset = 0 }
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
                .accessibilityIdentifier("reminderCard")
        }
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0

    /// `|dx| / threshold`, capped at 1 — the panel's reveal intensity. The
    /// denominator is floored at 1 so a zero threshold cannot divide by zero.
    private var progress: CGFloat {
        min(abs(dragOffset) / max(threshold, 1), 1)
    }

    private var revealedOutcome: SwipeGestureOutcome {
        SwipeGesture.revealedOutcome(forOffset: dragOffset)
    }
}

extension View {
    /// Adds drag-to-complete (right) / drag-to-skip (left) with a reveal panel
    /// behind the view and a fixed release threshold.
    func swipeToAct(
        threshold: CGFloat = SwipeGesture.releaseDistance,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) -> some View {
        modifier(SwipeToActModifier(threshold: threshold, onOutcome: onOutcome))
    }
}
