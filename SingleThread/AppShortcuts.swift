import AppIntents
import SingleThreadCore

/// Registers the reminder intents for Siri, the Shortcuts app, Spotlight and
/// the Home Screen app-icon long-press menu.
struct SingleThreadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: ["What's next in \(.applicationName)"],
            shortTitle: "What's Next",
            systemImageName: "list.bullet")
        AppShortcut(
            intent: CompleteCurrentTaskIntent(),
            phrases: ["Complete the current task in \(.applicationName)"],
            shortTitle: "Complete Current Task",
            systemImageName: "checkmark.circle")
    }
}
