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
            Button("About SingleThread") {
                showAbout.wrappedValue = true
            }
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit SingleThread") {
                NSApplication.shared.terminate(nil)
            }
        }

        CommandMenu(SharedStrings.reminder) {
            Button(SharedStrings.completeReminder) {
                Task { @MainActor in
                    await store.completeCurrentReminder()
                }
            }
            .disabled(store.visibleReminders.first == nil)

            Button(SharedStrings.skipReminder) {
                Task { @MainActor in
                    store.skipCurrentReminder()
                }
            }
            .disabled(store.visibleReminders.first == nil)
        }

        CommandMenu("Appearance") {
            Picker("Appearance", selection: appearanceMode) {
                Text("System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
        }
    }
#endif
