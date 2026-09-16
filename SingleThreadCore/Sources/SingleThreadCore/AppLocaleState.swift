import Foundation
import Observation

/// Process-wide holder of the chosen language. One instance per process,
/// injected at the app and watch roots into `\.locale`; tests construct their
/// own with an isolated `UserDefaults` suite.
@MainActor
@Observable
public final class AppLocaleState {
    // MARK: Lifecycle

    public init(language: AppLanguage? = nil, defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.language = language ?? AppLanguagePreference(defaults: defaults).load()
    }

    // MARK: Public

    /// Shared instance used by the app and watch roots and by
    /// `SettingsBindings.appLanguage`.
    public static let current = AppLocaleState()

    /// Locale for non-View, non-MainActor consumers (formatters, notification
    /// bodies, widget timeline build) — a plain store read, no actor hop.
    public nonisolated static var storedEffectiveLocale: Locale {
        AppLanguagePreference().load().locale
    }

    public private(set) var language: AppLanguage

    /// Locale handed to SwiftUI's `\.locale` and to `resolved(in:)`.
    public var effectiveLocale: Locale {
        language.locale
    }

    /// Persists and publishes the choice. Writes through the preference store so
    /// any `UserDefaults.didChangeNotification` observer (sync push) sees it.
    public func set(_ language: AppLanguage) {
        AppLanguagePreference(defaults: defaults).setRawValue(language.rawValue)
        self.language = language
    }

    // MARK: Private

    private let defaults: UserDefaults
}
