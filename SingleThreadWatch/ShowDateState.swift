import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "show due date" flag. Replaces the
/// former `@AppStorage("showDate")` read-back, whose observation of out-of-band
/// UserDefaults writes is OS-version-dependent; updates now arrive through the
/// sync pipeline's explicit `onShowDateReceived` callback.
@Observable
final class ShowDateState {
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

    private let preference = ShowDatePreference(defaults: .standard)
}
