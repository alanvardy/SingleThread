import SingleThreadCore
import SwiftUI

// MARK: - LocalizedNavigationTitle

extension View {
    /// A `.navigationTitle` that re-localizes when the in-app language changes.
    ///
    /// SwiftUI resolves a `LocalizedStringKey` navigation title once — against
    /// the system/per-app language — and does not re-resolve it when
    /// `.environment(\.locale)` changes (iOS 18+), so a locale switch leaves
    /// navigation bars stale until the screen is rebuilt. Resolving the resource
    /// against the environment locale ourselves makes the modifier's value
    /// change with the locale, so the navigation bar updates in place without
    /// re-keying the `NavigationStack` (which would reset navigation state).
    func localizedNavigationTitle(_ resource: LocalizedStringResource) -> some View {
        modifier(LocalizedNavigationTitleModifier(resource: resource))
    }
}

private struct LocalizedNavigationTitleModifier: ViewModifier {
    // MARK: Internal

    let resource: LocalizedStringResource

    func body(content: Content) -> some View {
        content.navigationTitle(resource.resolved(in: locale))
    }

    // MARK: Private

    @Environment(\.locale)
    private var locale
}
