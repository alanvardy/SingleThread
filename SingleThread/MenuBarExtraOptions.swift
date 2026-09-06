#if os(macOS)
    import AppKit
    import EventKit
    import SingleThreadCore
    import SwiftUI

    /// `.menu`-style MenuBarExtra content: the next due reminder's title + due
    /// date with Complete/Skip actions and an "Open SingleThread" launcher.
    /// Renders nothing when no reminder is due (the scene is hidden upstream, but
    /// this empty-content branch also serves as the documented fallback).
    struct MenuBarExtraOptions: View {
        let store: ReminderStore

        var body: some View {
            if let reminder = store.visibleReminders.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reminder.title ?? "")
                        .font(.headline)
                    if let due = reminder.dueDateComponents?.date {
                        Text(due, format: .dateTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("Complete Reminder") {
                        Task { @MainActor in await store.completeCurrentReminder() }
                    }
                    Button("Skip Reminder") {
                        Task { @MainActor in store.skipCurrentReminder() }
                    }
                    Divider()
                    Button("Open SingleThread") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
                    }
                }
                .padding()
            }
        }
    }
#endif
