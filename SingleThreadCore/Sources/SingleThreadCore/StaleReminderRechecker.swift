import Foundation

/// Conformance seam so app/watch view models can be tested with a recording
/// fake instead of the real loop (house pattern: the store itself is injected;
/// here the rechecker is injected).
@MainActor
public protocol StaleReminderRechecking {
    func start()
    func stop()
}

/// Hybrid re-check coordinator for out-of-band reminder completion/deletion.
/// Combines a change-observer tick source (injected in Stage 2) with a slow
/// poll; both funnel into the on-screen gate → debounce/coalesce → `reload()`
/// so a currently-displayed reminder advances without a user gesture.
///
/// Pure coordination: owns no EventKit/NotificationCenter reference of its own;
/// `reload`, `sleep`, `isShowingReminder`, and (Stage 2) the change source are
/// all injected. The `sleep` seam mirrors `ReminderStoreSettle`.
@MainActor
public final class StaleReminderRechecker: StaleReminderRechecking {
    // MARK: Lifecycle

    public init(
        isShowingReminder: @escaping IsShowingReminder,
        reload: @escaping Reload,
        sleep: @escaping Sleep,
        pollInterval: Duration = StaleReminderRechecker.defaultPollInterval) {
        self.isShowingReminder = isShowingReminder
        self.reload = reload
        self.sleep = sleep
        self.pollInterval = pollInterval
    }

    // MARK: Public

    public typealias Reload = @MainActor () async -> Void
    public typealias IsShowingReminder = @MainActor () -> Bool
    public typealias Sleep = @Sendable (Duration) async -> Void

    // MARK: Types

    /// Poll-fallback interval. Named/tunable (design decision 5).
    public static let defaultPollInterval: Duration = .seconds(60)

    // MARK: Control

    /// Begins the poll loop and arms an immediate first tick. Idempotent: a
    /// second `start()` while running is a no-op.
    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Cancels the poll loop. Idempotent — safe to call more than once.
    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: Private

    private let isShowingReminder: IsShowingReminder
    private let reload: Reload
    private let sleep: Sleep
    private let pollInterval: Duration

    private var loopTask: Task<Void, Never>?
    /// True while a coalesced `reload()` is in flight.
    private var isReloading = false
    /// Set when a tick arrives during an in-flight reload; collapses N
    /// overlapping ticks into exactly one trailing reload.
    private var reloadPending = false

    private func runLoop() async {
        while !Task.isCancelled {
            receiveTick()
            if Task.isCancelled {
                return
            }
            await sleep(pollInterval)
        }
    }

    /// Single tick funnel: on-screen gate → debounce/coalesce → `reload()`.
    private func receiveTick() {
        guard isShowingReminder() else { return }
        if isReloading {
            reloadPending = true
            return
        }
        isReloading = true
        Task { [weak self] in
            await self?.drain()
        }
    }

    /// Runs one `reload()`, plus one trailing reload if a tick arrived while
    /// the previous reload was in flight (coalescing; mirrors
    /// `ContentViewModel.refreshManual`'s re-entrancy guard). No `await` sits
    /// between the final `reload()` return and `isReloading = false`, so a tick
    /// can't race the guard on the MainActor.
    private func drain() async {
        repeat {
            reloadPending = false
            await reload()
        } while reloadPending
        isReloading = false
    }
}

public extension StaleReminderRechecker {
    /// Production wiring used by the view models: gate on
    /// `store.listContent` being `.reminder` (the case carries an associated
    /// value, so matching uses a pattern), reload via `store.reload()`, real
    /// `Task.sleep` poll, and a global `.EKEventStoreChanged` observer
    /// (availability of the observer type lands in Stage 2 — the parameter
    /// below is added by that stage and defaults to nil until then).
    @MainActor
    static func live(store: ReminderStore) -> StaleReminderRechecker {
        StaleReminderRechecker(
            isShowingReminder: {
                if case .reminder = store.listContent {
                    return true
                }
                return false
            },
            reload: { await store.reload() },
            sleep: { try? await Task.sleep(for: $0) })
    }
}
