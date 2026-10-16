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

    /// Downward travel to report for a live drag. A drag that has locked to the
    /// horizontal rail reports none at all, so a left/right card swipe cannot
    /// nudge the card up or down on its way past.
    static func pull(for translation: CGSize, on axis: SwipeAxis) -> CGFloat {
        axis == .vertical ? max(translation.height, 0) : 0
    }
}

/// Pull-down-to-refresh for a scrollable surface. Tracks a downward drag, runs
/// `onRefresh` on release past `threshold`, and holds the feedback up for its
/// duration.
///
/// The stock `.refreshable` never arms on these screens — the reminder list is a
/// single full-height row, so there is nothing for the control to pull — so this
/// hangs the pull off the whole scroll surface instead.
///
/// Two presentations:
/// - **Bindings supplied** (the reminder screen): the pull is handed to the
///   caller, which drives its own reveal — the card plate sliding down so the
///   `Refresh` plate emerges from under its top edge, exactly like the other
///   swipe actions.
/// - **No bindings** (the empty / all-done screens, which have no card to emerge
///   from under): this modifier paints its own panel at the top edge.
struct PullToRefreshModifier: ViewModifier {
    // MARK: Lifecycle

    init(
        threshold: CGFloat = PullToRefresh.releaseDistance,
        pull: Binding<CGFloat>? = nil,
        isRefreshing: Binding<Bool>? = nil,
        onRefresh: @escaping () async -> Void) {
        self.threshold = threshold
        externalPull = pull
        externalRefreshing = isRefreshing
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
                        let axis = lockedAxis ?? SwipeGesture.axis(for: value.translation)
                        lockedAxis = axis
                        pull.wrappedValue = PullToRefresh.pull(for: value.translation, on: axis)
                    }
                    .onEnded { _ in
                        lockedAxis = nil
                        guard !isRefreshing,
                              PullToRefresh.isArmed(pull: pull.wrappedValue, threshold: threshold)
                        else {
                            withAnimation(.snappy) { pull.wrappedValue = 0 }
                            return
                        }
                        runRefresh()
                    })
            .overlay(alignment: .top) { ownPanel }
            .accessibilityAction(named: Text("Refresh")) {
                runRefresh()
            }
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var localPull: CGFloat = 0
    @State private var localRefreshing = false

    /// Rail the in-flight drag locked to, mirroring `SwipeToActModifier`: held
    /// for the whole gesture so a horizontal swipe cannot start reporting a pull
    /// halfway through.
    @State private var lockedAxis: SwipeAxis?

    private let externalPull: Binding<CGFloat>?
    private let externalRefreshing: Binding<Bool>?

    /// The caller's state when it owns the reveal (the reminder card), else this
    /// modifier's own — the card-less screens have nothing else to show the pull.
    private var pull: Binding<CGFloat> {
        externalPull ?? $localPull
    }

    private var refreshing: Binding<Bool> {
        externalRefreshing ?? $localRefreshing
    }

    /// Reads `localRefreshing` directly — as `ownPanel` reads `localPull` — so
    /// Periphery under Xcode 27 sees both states used. It misses lone
    /// `$`projection references, which is the same reason `ContentView`'s
    /// `upgradePrompt` reads `isShowingPurchase` directly.
    private var isRefreshing: Bool {
        externalRefreshing?.wrappedValue ?? localRefreshing
    }

    /// Only the card-less screens need this modifier to draw its own panel.
    @ViewBuilder private var ownPanel: some View {
        if externalPull == nil, localPull > 0 {
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
                : Double(PullToRefresh.progress(pull: localPull, threshold: threshold)))
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
    }

    /// Fires the refresh once, holding the feedback visible for its duration.
    private func runRefresh() {
        guard !isRefreshing else { return }
        withAnimation(.snappy) {
            pull.wrappedValue = threshold
            refreshing.wrappedValue = true
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
                refreshing.wrappedValue = false
                pull.wrappedValue = 0
            }
        }
    }
}

extension View {
    /// Adds pull-down-to-refresh. With bindings supplied the caller renders the
    /// feedback (see `PullToRefreshModifier`); without them this paints a panel
    /// at the top edge.
    func pullToRefresh(
        threshold: CGFloat = PullToRefresh.releaseDistance,
        pull: Binding<CGFloat>? = nil,
        isRefreshing: Binding<Bool>? = nil,
        onRefresh: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(
            threshold: threshold,
            pull: pull,
            isRefreshing: isRefreshing,
            onRefresh: onRefresh))
    }
}
