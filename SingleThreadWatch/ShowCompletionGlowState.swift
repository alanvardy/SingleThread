import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "show completion glow" flag.
/// Replaces a former `@AppStorage` read-back; updates arrive through the
/// sync pipeline's explicit `onShowCompletionGlowReceived` callback.
@Observable
final class ShowCompletionGlowState {
    // MARK: Lifecycle

    init() {
        isEnabled = preference.isEnabled
    }

    // MARK: Internal

    private(set) var isEnabled: Bool

    /// Persists a received value and publishes it to observing views.
    func apply(_ value: Bool) {
        preference.set(value)
        isEnabled = value
    }

    // MARK: Private

    private let preference = ShowCompletionGlowPreference(defaults: .standard)
}
