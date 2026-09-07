import EventKit
import Foundation

/// Registers a `.EKEventStoreChanged` handler and returns an unregister
/// closure. Protocol seam so the rechecker's loop stays free of
/// NotificationCenter/EventKit coupling.
@MainActor
public protocol EventStoreChangedObserving {
    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void)
}

/// Production implementation: observes globally (`object: nil`) and lets the
/// rechecker's on-screen gate + full `reload()` do the filtering (design
/// decision 3 — no cheap second-fetch path).
@MainActor
public final class EventStoreChangedObserver: EventStoreChangedObserving {
    // MARK: Lifecycle

    public init(center: NotificationCenter = .default) {
        self.center = center
    }

    // MARK: Public

    public func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void) {
        let token = center.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
        return { [center] in
            center.removeObserver(token)
        }
    }

    // MARK: Private

    private let center: NotificationCenter
}
