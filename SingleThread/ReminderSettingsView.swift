import SingleThreadCore
import SwiftUI

/// Display preferences for reminder content: show date, show list,
/// recurrence indicator, and reminder alerts. Each changes widget timelines,
/// so the sub-view fires the reload hooks through `viewModel`. Takes only
/// the bindings it needs rather than the full bag.
struct ReminderSettingsView: View {
    @Binding var showDate: Bool

    @Binding var showList: Bool

    @Binding var showRecurrence: Bool

    @Binding var showAlarms: Bool

    @Binding var showCompletionGlow: Bool

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle(isOn: $showDate) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show date")
                        SettingsCaption(text: "Show the due date next to each reminder.")
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            .accessibilityIdentifier("showDateToggle")
            #if os(iOS) || os(macOS)
                .onChange(of: showDate) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
            Toggle(isOn: $showList) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show list")
                        SettingsCaption(text: "Show which list each reminder belongs to.")
                    }
                } icon: {
                    Image(systemName: "list.bullet")
                }
            }
            .accessibilityIdentifier("showListToggle")
            Toggle(isOn: $showRecurrence) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Recurrence indicator")
                        SettingsCaption(text: "Show if a reminder repeats.")
                    }
                } icon: {
                    Image(systemName: "repeat")
                }
            }
            .accessibilityIdentifier("showRecurrenceToggle")
            #if os(iOS) || os(macOS)
                .onChange(of: showRecurrence) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
            Toggle(isOn: $showAlarms) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Reminder alerts")
                        SettingsCaption(text: "Show if a reminder has a time alert.")
                    }
                } icon: {
                    Image(systemName: "bell")
                }
            }
            .accessibilityIdentifier("showAlarmsToggle")
            #if os(iOS) || os(macOS)
                .onChange(of: showAlarms) { _, _ in
                    viewModel.showPreferenceChanged()
                }
            #endif
            Toggle(isOn: $showCompletionGlow) {
                Label {
                    VStack(alignment: .leading) {
                        Text(SharedStrings.completionGlow)
                        SettingsCaption(text: "Show a sparkle animation when a reminder is completed.")
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .accessibilityIdentifier("showCompletionGlowToggle")
        }
        .navigationTitle("Reminder")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        ReminderSettingsView(
            showDate: .constant(true),
            showList: .constant(false),
            showRecurrence: .constant(true),
            showAlarms: .constant(true),
            showCompletionGlow: .constant(true),
            viewModel: SettingsViewModel())
    }
}
