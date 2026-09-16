import AppIntents
import SingleThreadCore

/// Registers the reminder intents for Siri, the Shortcuts app, Spotlight and
/// the Home Screen app-icon long-press menu.
struct SingleThreadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What is next in \(.applicationName)"
            ],
            shortTitle: "What's Next",
            systemImageName: "list.bullet")
        AppShortcut(
            intent: CompleteCurrentTaskIntent(),
            phrases: [
                "Complete the current task in \(.applicationName)",
                "Mark my current task done in \(.applicationName)"
            ],
            shortTitle: "Complete Current Task",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: SkipCurrentTaskIntent(),
            phrases: [
                "Skip the current task in \(.applicationName)",
                "Skip my current task in \(.applicationName)"
            ],
            shortTitle: "Skip Current Task",
            systemImageName: "arrow.uturn.forward")
    }
}
