import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "show list" flag. Replaces the
/// former `@AppStorage("showList")` read-back, whose observation of out-of-band
/// UserDefaults writes is OS-version-dependent; updates now arrive through the
/// sync pipeline's explicit `onShowListReceived` callback.
@Observable
final class ShowListState {
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

    private let preference = ShowListPreference(defaults: .standard)
}
