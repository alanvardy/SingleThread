#if os(macOS)
    import AppKit
    import SingleThreadCore
    import SwiftUI

    /// macOS app-menu chrome: About/Quit in the app menu, Complete/Skip for the
    /// current reminder, and a System/Light/Dark appearance Picker. Store mutations
    /// route through `ReminderStore` so `guard canMutate` stays authoritative; the
    /// appearance Picker reuses `@AppStorage("appearanceMode")` and the existing
    /// `.onChange → handleAppearanceMode` write path.
    @CommandsBuilder
    func appCommands(
        store: ReminderStore,
        appearanceMode: Binding<AppearanceMode>,
        showAbout: Binding<Bool>) -> some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(
                LocalizedStringResource("About SingleThread", table: "Localizable", bundle: .main)
                    .resolvedInAppLanguage()) {
                showAbout.wrappedValue = true
            }
        }

        CommandGroup(replacing: .appTermination) {
            Button(
                LocalizedStringResource("Quit SingleThread", table: "Localizable", bundle: .main)
                    .resolvedInAppLanguage()) {
                NSApplication.shared.terminate(nil)
            }
        }

        CommandMenu(SharedStrings.reminder.resolvedInAppLanguage()) {
            Button(SharedStrings.completeReminder.resolvedInAppLanguage()) {
                Task { @MainActor in
                    await store.completeCurrentReminder()
                }
            }
            .disabled(store.visibleReminders.first == nil)

            Button(SharedStrings.skipReminder.resolvedInAppLanguage()) {
                Task { @MainActor in
                    store.skipCurrentReminder()
                }
            }
            .disabled(store.visibleReminders.first == nil)
        }

        CommandMenu(
            LocalizedStringResource("Appearance", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()) {
            Picker(
                LocalizedStringResource("Appearance", table: "Localizable", bundle: .main)
                    .resolvedInAppLanguage(),
                selection: appearanceMode) {
                    Text(
                        LocalizedStringResource("System", table: "Localizable", bundle: .main)
                            .resolvedInAppLanguage()).tag(AppearanceMode.system)
                    Text(
                        LocalizedStringResource("Light", table: "Localizable", bundle: .main)
                            .resolvedInAppLanguage()).tag(AppearanceMode.light)
                    Text(
                        LocalizedStringResource("Dark", table: "Localizable", bundle: .main)
                            .resolvedInAppLanguage()).tag(AppearanceMode.dark)
                }
        }
    }
#endif
