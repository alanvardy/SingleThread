import SwiftUI

/// Abstract over `OpenURLAction` so tests can intercept opened URLs.
/// `AnyObject`-constrained so a view model stores `any URLOpening`
/// without a protocol-boxing `@MainActor` conflict.
@MainActor
protocol URLOpening: AnyObject {
    func open(_ url: URL)
}

/// Production wrapper: delegates to the live `@Environment(\.openURL)` value.
@MainActor
final class SystemURLOpener: URLOpening {
    // MARK: Lifecycle

    init(action: OpenURLAction) {
        self.action = action
    }

    // MARK: Internal

    /// Shared no-op opener for call sites that never exercise the deep link
    /// (previews, unit tests). Every production call site must inject the
    /// scene's live `OpenURLAction`; a forgotten injection silently drops
    /// opens, so keep the no-op the explicit exception, not the default.
    static var noop: SystemURLOpener {
        SystemURLOpener(action: OpenURLAction { _ in .handled })
    }

    func open(_ url: URL) {
        action(url)
    }

    // MARK: Private

    private let action: OpenURLAction
}

/// Records every URL passed to `open(_:)` — test spy for unit + UI tests.
/// Lives in the app target (not `SingleThreadTests/`) because the
/// `--url-opener-spy` UI-test seam runs in the app process.
@MainActor
final class URLOpeningSpy: URLOpening {
    private(set) var openedURLs: [URL] = []

    var lastOpenedURL: URL? {
        openedURLs.last
    }

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}
