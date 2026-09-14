import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "enable action buttons" flag.
/// Reads its initial value from `AppGroup.defaults` (falling back to
/// `.standard` where the group is unavailable, e.g. a real watch), matching
/// where the sync pipeline persists received values so the state and the wire
/// never diverge. With no persisted value the flag defaults to on, so a fresh
/// install shows the action cluster until the phone syncs an explicit choice.
/// Updates arrive through the sync pipeline's explicit
/// `onEnableActionButtonsReceived` callback.
@Observable
final class ShowEnableActionButtonsState {
    // MARK: Lifecycle

    init() {
        isEnabled = BoolPreferenceStore(
            key: BoolPreferenceKey.enableActionButtons.rawValue,
            fallback: true).isEnabled
    }

    // MARK: Internal

    private(set) var isEnabled: Bool

    /// Persists a received value and publishes it to observing views.
    func apply(_ value: Bool) {
        AppGroup.defaults.set(value, forKey: BoolPreferenceKey.enableActionButtons.rawValue)
        isEnabled = value
    }
}
