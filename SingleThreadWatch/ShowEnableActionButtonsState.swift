import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "enable action buttons" flag.
/// Reads its initial value from `AppGroup.defaults` (falling back to
/// `.standard` where the group is unavailable, e.g. a real watch), matching
/// where the sync pipeline persists received values so the state and the wire
/// never diverge. Updates arrive through the sync pipeline's explicit
/// `onEnableActionButtonsReceived` callback.
@Observable
final class ShowEnableActionButtonsState {
    // MARK: Lifecycle

    init() {
        isEnabled = AppGroup.defaults.bool(forKey: "enableActionButtons")
    }

    // MARK: Internal

    private(set) var isEnabled: Bool

    /// Persists a received value and publishes it to observing views.
    func apply(_ value: Bool) {
        AppGroup.defaults.set(value, forKey: "enableActionButtons")
        isEnabled = value
    }
}
