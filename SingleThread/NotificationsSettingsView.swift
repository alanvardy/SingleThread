import SwiftUI

/// Notification preferences: enable toggle and interval picker. The
/// NavigationLink into this view is `#if os(iOS)` gated in `SettingsView`, so
/// it is only reachable on iOS even though the file compiles on all platforms.
struct NotificationsSettingsView: View {
    @Binding var notificationsEnabled: Bool

    @Binding var notificationIntervalHours: Int

    var body: some View {
        Form {
            Toggle(isOn: $notificationsEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Enable reminder notifications")
                        SettingsCaption(text: "Send a notification when you have due reminders.")
                    }
                } icon: {
                    Image(systemName: "bell.badge")
                }
            }
            .accessibilityIdentifier("notificationsEnabledToggle")
            Picker(selection: $notificationIntervalHours) {
                Text("24 hours").tag(24)
                Text("48 hours").tag(48)
                Text("72 hours").tag(72)
            } label: {
                VStack(alignment: .leading) {
                    Text("Remind after")
                    SettingsCaption(text: "How long to wait before sending another reminder.")
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("notificationIntervalPicker")
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        NotificationsSettingsView(
            notificationsEnabled: .constant(false),
            notificationIntervalHours: .constant(48))
    }
}
