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
                Label("Enable reminder notifications", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("notificationsEnabledToggle")
            Picker("Remind after", selection: $notificationIntervalHours) {
                Text("24 hours").tag(24)
                Text("48 hours").tag(48)
                Text("72 hours").tag(72)
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
