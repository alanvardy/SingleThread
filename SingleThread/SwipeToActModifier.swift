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
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardPlate(fill: CardPlate.plateFill(for: colorScheme))
            .opacity(Double(progress))
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme

    private var title: LocalizedStringResource {
        switch outcome {
        case .complete: SharedStrings.completeAction
        case .skip: SharedStrings.skipAction
        // Never rendered: the modifier omits the panel for `.none`.
        case .none: SharedStrings.completeAction
        }
    }

    private var systemImage: String {
        switch outcome {
        case .complete: "checkmark.circle.fill"
        case .skip: "circle.slash"
        case .none: "circle"
        }
    }

    private var tint: Color {
        switch outcome {
        case .complete: CardPlate.completeHintColor(for: colorScheme)
        case .skip: CardPlate.skipHintColor(for: colorScheme)
        case .none: .clear
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
        }
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0

    /// `|dx| / threshold`, capped at 1 — the panel's reveal intensity.
    private var progress: CGFloat {
        min(abs(dragOffset) / threshold, 1)
    }

    private var revealedOutcome: SwipeGestureOutcome {
        if dragOffset > 0 {
            .complete
        } else if dragOffset < 0 {
            .skip
        } else {
            .none
        }
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
