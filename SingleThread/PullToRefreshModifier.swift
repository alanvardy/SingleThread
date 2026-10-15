import CoreGraphics
import SingleThreadCore
import SwiftUI

/// Pure pull-down-to-refresh rule. Extracted from the modifier so the arming
/// distance is unit-testable without a gesture runtime.
enum PullToRefresh {
    /// Downward travel (pt) past which releasing fires the refresh. Matches the
    /// up-swipe release distance so every vertical pull feels consistent.
    static let releaseDistance: CGFloat = 96

    /// Shortest time the panel stays up once a refresh starts. A local fetch
    /// can finish in well under a frame, which would read as a flicker rather
    /// than as feedback.
    static let minimumVisible: TimeInterval = 0.6

    /// True when `pull` has travelled far enough to refresh on release.
    static func isArmed(pull: CGFloat, threshold: CGFloat = releaseDistance) -> Bool {
        pull >= threshold
    }

    /// `pull / threshold`, clamped to 0…1 — the reveal panel's intensity.
    static func progress(pull: CGFloat, threshold: CGFloat = releaseDistance) -> CGFloat {
        min(max(pull, 0) / max(threshold, 1), 1)
    }
}

/// Pull-down-to-refresh for a scrollable surface. Reveals a branded panel at the
/// top edge as the pull grows, runs `onRefresh` on release past `threshold`, and
/// holds the panel plus a spinner until the refresh finishes.
///
/// Hand-rolled rather than `.refreshable`: the reminder list is a single
/// full-height row, so the stock control never arms on it — pulls on the card
/// and pulls on the empty space above it both did nothing, and there was no
/// spinner. This hangs the pull off the whole scroll surface instead, so both
/// places refresh and the panel is the visible feedback.
struct PullToRefreshModifier: ViewModifier {
    // MARK: Lifecycle

    init(
        threshold: CGFloat = PullToRefresh.releaseDistance,
        onRefresh: @escaping () async -> Void) {
        self.threshold = threshold
        self.onRefresh = onRefresh
    }

    // MARK: Internal

    let threshold: CGFloat
    let onRefresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard !isRefreshing else { return }
                        pull = max(value.translation.height, 0)
                    }
                    .onEnded { _ in
                        guard !isRefreshing,
                              PullToRefresh.isArmed(pull: pull, threshold: threshold)
                        else {
                            withAnimation(.snappy) { pull = 0 }
                            return
                        }
                        runRefresh()
                    })
            .overlay(alignment: .top) { panel }
            .accessibilityAction(named: Text("Refresh")) {
                runRefresh()
            }
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var pull: CGFloat = 0
    @State private var isRefreshing = false

    /// Branded plate pinned to the top edge: the glyph becomes a spinner while
    /// the refresh runs. Hidden until the pull starts.
    @ViewBuilder private var panel: some View {
        if pull > 0 {
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView()
                    Text("Refreshing")
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Refresh")
                }
            }
            .font(.headline)
            .foregroundStyle(CardPlate.refreshHintColor(for: colorScheme))
            .cardPlate(fill: CardPlate.plateFill(for: colorScheme))
            .opacity(isRefreshing
                ? 1
                : Double(PullToRefresh.progress(pull: pull, threshold: threshold)))
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
    }

    /// Fires the refresh once, holding the panel visible for its duration.
    private func runRefresh() {
        guard !isRefreshing else { return }
        withAnimation(.snappy) {
            pull = threshold
            isRefreshing = true
        }
        Task {
            let startedAt = Date()
            await onRefresh()
            let remaining = MinimumDisplayDuration.remainingSleep(
                elapsed: Date().timeIntervalSince(startedAt),
                minimum: PullToRefresh.minimumVisible)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            withAnimation(.snappy) {
                isRefreshing = false
                pull = 0
            }
        }
    }
}

extension View {
    /// Adds pull-down-to-refresh with a branded reveal panel and spinner.
    func pullToRefresh(
        threshold: CGFloat = PullToRefresh.releaseDistance,
        onRefresh: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(threshold: threshold, onRefresh: onRefresh))
    }
}
