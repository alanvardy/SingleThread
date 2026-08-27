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

    @Binding var showGuide: Bool

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle(isOn: $showDate) {
                Label("Show date", systemImage: "calendar")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: showDate) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $showList) {
                Label("Show list", systemImage: "list.bullet")
            }
            Toggle(isOn: $showRecurrence) {
                Label("Recurrence indicator", systemImage: "repeat")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: showRecurrence) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $showAlarms) {
                Label("Reminder alerts", systemImage: "bell")
            }
            #if os(iOS) || os(macOS)
            .onChange(of: showAlarms) { _, _ in
                viewModel.showPreferenceChanged()
            }
            #endif
            Toggle(isOn: $showCompletionGlow) {
                Label("Completion glow", systemImage: "sparkles")
            }
            Toggle(isOn: $showGuide) {
                Label("Show guide again", systemImage: "questionmark.circle")
            }
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
            showGuide: .constant(true),
            viewModel: SettingsViewModel())
    }
}
