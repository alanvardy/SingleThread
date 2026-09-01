import Foundation

extension String {
    /// Localizes a key from the given bundle with the test suite's pinned locale,
    /// so unit tests assert deterministic English output regardless of host locale.
    static func en(
        _ key: String.LocalizationValue,
        bundle: Bundle,
        table: String = "Localizable") -> String {
        String(localized: key, table: table, bundle: bundle, locale: Locale(identifier: "en"))
    }
}

extension Bundle {
    /// The SingleThreadCore resource bundle as embedded in the app that hosts the
    /// test runner. Xcode names Swift-package resource bundles
    /// `<PackageName>_<TargetName>.bundle` and embeds them in the app bundle;
    /// the tests cannot use the package-only `Bundle.module`.
    static var core: Bundle {
        if let url = main.url(
            forResource: "SingleThreadCore_SingleThreadCore",
            withExtension: "bundle"),
            let core = Self(url: url) {
            return core
        }
        return .main
    }
}
