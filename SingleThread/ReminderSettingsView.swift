import SingleThreadCore
import SwiftUI

/// Display preferences for reminder content: show date, show list,
/// recurrence indicator, and reminder alerts. Each changes widget timelines,
/// so the sub-view fires the reload hooks through `viewModel`.
struct ReminderSettingsView: View {
    @Bindable var bindings: SettingsBindings

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle(isOn: $bindings.showDate) {
                Label("Show date", systemImage: "calendar")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: bindings.showDate) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $bindings.showList) {
                Label("Show list", systemImage: "list.bullet")
            }
            Toggle(isOn: $bindings.showRecurrence) {
                Label("Recurrence indicator", systemImage: "repeat")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: bindings.showRecurrence) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $bindings.showAlarms) {
                Label("Reminder alerts", systemImage: "bell")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: bindings.showAlarms) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
        }
        .navigationTitle("Reminder")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        ReminderSettingsView(
            bindings: SettingsBindings(),
            viewModel: SettingsViewModel())
    }
}
