import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

/// Owns the Settings screen's device-level and widget side effects so the view
/// stays a pure display of preference bindings. Each method is a thin
/// delegation with no stored state.
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: Lifecycle

    init(onShowGuideAgain: @escaping () -> Void = {}) {
        self.onShowGuideAgain = onShowGuideAgain
    }

    // MARK: Internal

    /// Pushes a one-shot "show the watch guide again" request. Ignored on
    /// platforms without a paired watch (the default is a no-op). Wired by the
    /// composition root so this VM never needs a sync-service reference.
    let onShowGuideAgain: () -> Void

    #if os(iOS)
        func allowsLandscapeChanged(_ value: Bool) {
            AppDelegate.applyLock(allowsLandscape: value)
        }
    #endif

    /// Requests the paired watch to show its guide again. Watch-only; locally
    /// this screen has no guide, so it just forwards the request.
    func showGuideAgain() {
        #if os(iOS)
            onShowGuideAgain()
        #endif
    }

    #if os(iOS) || os(macOS)
        /// Reloads widget timelines when any display preference (show date,
        /// show recurrence, show alarms) changes.
        func showPreferenceChanged() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    #endif
}
