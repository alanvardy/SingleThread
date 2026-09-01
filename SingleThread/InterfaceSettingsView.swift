import SingleThreadCore // periphery:ignore
import SwiftUI

/// Interface preferences: appearance, text size, and platform-gated
/// orientation + action button toggles. Takes only the bindings it needs
/// rather than the full bag so it cannot accidentally mutate unrelated
/// preferences.
struct InterfaceSettingsView: View {
    @Binding var appearanceMode: AppearanceMode

    @Binding var textSize: TextSize

    #if os(iOS)
        @Binding var allowsLandscape: Bool
    #endif

    @Binding var showMicrophoneButton: Bool

    #if os(iOS)
        @Binding var enableActionButtons: Bool
    #endif

    #if os(iOS)
        @Binding var showSwipePrompt: Bool
    #endif

    #if os(iOS)
        @Binding var showUndoButton: Bool
    #endif

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .accessibilityIdentifier("appearancePicker")
            Picker("Text Size", selection: $textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            }
            .accessibilityIdentifier("textSizePicker")
            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label("Allow landscape", systemImage: "rectangle.landscape.rotate")
                }
                .accessibilityIdentifier("allowLandscapeToggle")
                .onChange(of: allowsLandscape) { _, newValue in
                    viewModel.allowsLandscapeChanged(newValue)
                }
            #endif
            Toggle(isOn: $showMicrophoneButton) {
                Label("Show microphone", systemImage: "microphone")
            }
            .accessibilityIdentifier("showMicrophoneToggle")
            #if os(iOS)
                Toggle(isOn: $enableActionButtons) {
                    Label("Show action buttons", systemImage: "hand.tap")
                }
                .accessibilityIdentifier("showActionButtonsToggle")
                Toggle(isOn: $showSwipePrompt) {
                    Label("Show swipe prompt", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("showSwipePromptToggle")
                Toggle(isOn: $showUndoButton) {
                    Label("Show undo button", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("showUndoButtonToggle")
            #endif
        }
        .navigationTitle("Interface")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        #if os(iOS)
            InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showSwipePrompt: .constant(true),
                showUndoButton: .constant(true),
                viewModel: SettingsViewModel())
        #else
            InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                viewModel: SettingsViewModel())
        #endif
    }
}
