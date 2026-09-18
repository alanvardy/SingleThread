import Foundation
import SingleThreadCore

// MARK: - PrivacySection

/// A single section of the privacy guide: a headline plus explanatory prose.
struct PrivacySection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

// MARK: - PrivacyGuideContent

/// Static disclosure copy — the single source of truth for what SingleThread
/// claims about its data handling.
///
/// IMPORTANT: this copy hardcodes facts about the app's data flow (Apple
/// Reminders via EventKit, local Watch sync over WCSession, and the
/// `vardy.cc/unsplash` background-image fetch). If any of those data flows
/// change, update this copy in the same change or it becomes misleading.
enum PrivacyGuideContent {
    // MARK: Internal

    /// The four disclosure sections, localized through the app catalog in the
    /// interface language (`in locale:` mirrors `LocalizedStringResource.resolved(in:)`).
    static func sections(in locale: Locale) -> [PrivacySection] {
        let remindersTitle = localized("Reminders", in: locale)
        let remindersBody = localized(
            "Reminders are read and written through Apple Reminders. "
                + "They stay on your device or in your own iCloud account, "
                + "and are never sent to the author or any third party.",
            in: locale)
        let preferencesTitle = localized("Display & Sync Preferences", in: locale)
        let preferencesBody = localized(
            "Your display and sync preferences — such as sort order, "
                + "text size, and which lists are hidden — are stored on your "
                + "device in shared app storage and synced to your own Apple "
                + "Watch over a direct local connection, never over the internet.",
            in: locale)
        let skippedTitle = localized("Skipped & Excluded Lists", in: locale)
        let skippedBody = localized(
            "Skipped reminders and excluded lists are stored on your "
                + "device and synced to your Apple Watch over the same direct "
                + "local connection. They never leave your devices.",
            in: locale)
        let backgroundTitle = localized("Background Image", in: locale)
        let backgroundBody = localized(
            "When the background is enabled, the background url and "
                + "artist information is downloaded from a proxy at vardy.cc. "
                + "This is the app's only network request, and it never "
                + "includes any reminder, preference, or list data. "
                + "This proxy is used to store an API key for Unsplash and "
                + "keep API usage reasonable.",
            in: locale)
        return [
            PrivacySection(id: "reminders", title: remindersTitle, body: remindersBody),
            PrivacySection(id: "preferences", title: preferencesTitle, body: preferencesBody),
            PrivacySection(id: "skipped", title: skippedTitle, body: skippedBody),
            PrivacySection(id: "background", title: backgroundTitle, body: backgroundBody)
        ]
    }

    static func closingLine(in locale: Locale) -> String {
        localized("SingleThread has no analytics, no tracking, and no advertising.", in: locale)
    }

    // MARK: Private

    /// Resolves a key from the app catalog against the interface language,
    /// following the codebase's pinned-lookup pattern
    /// (`LocalizedStringResource(...).resolved(in:)`). The key may be assembled
    /// from multiple literal pieces (the keys are the full English sentences);
    /// `LocalizationValue(stringLiteral:)` keeps the assembled string as the
    /// exact lookup key. `resolved(in:)` pins the lookup to the in-app interface
    /// language; `String(localized:…locale:)` is NOT used here — it ignores the
    /// pin for non-English locales and falls back to the development language.
    private static func localized(_ key: String, in locale: Locale) -> String {
        LocalizedStringResource(
            String.LocalizationValue(stringLiteral: key),
            table: "Localizable",
            bundle: .main).resolved(in: locale)
    }
}
