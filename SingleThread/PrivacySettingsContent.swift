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
    static let sections: [PrivacySection] = [
        PrivacySection(
            id: "reminders",
            title: "Reminders",
            body: "Reminders are read and written through Apple Reminders. "
                + "They stay on your device or in your own iCloud account, "
                + "and are never sent to SingleThread or any third party."),
        PrivacySection(
            id: "preferences",
            title: "Display & Sync Preferences",
            body: "Your display and sync preferences — such as sort order, "
                + "text size, and which lists are hidden — are stored on your "
                + "device in shared app storage and synced to your own Apple "
                + "Watch over a direct local connection, never over the "
                + "internet."),
        PrivacySection(
            id: "skipped",
            title: "Skipped & Excluded Lists",
            body: "Skipped reminders and excluded lists are stored on your "
                + "device and synced to your Apple Watch over the same direct "
                + "local connection. They never leave your devices."),
        PrivacySection(
            id: "background",
            title: "Background Image",
            body: "When the background is enabled, the image is downloaded "
                + "from vardy.cc/unsplash and cached on your device. This is "
                + "the app's only network request, and it never includes any "
                + "reminder, preference, or list data."),
    ]

    static let closingLine =
        "SingleThread has no analytics, no tracking, and no advertising."
}
