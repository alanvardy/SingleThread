import SingleThreadCore
import SwiftUI

/// Interface preferences: appearance, text size, and platform-gated
/// orientation + action button toggles. Bound through the shared
/// @Observable SettingsBindings bag.
struct InterfaceSettingsView: View {
    @Bindable var bindings: SettingsBindings

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker("Appearance", selection: $bindings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            Picker("Text Size", selection: $bindings.textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            }
            #if os(iOS)
                Toggle(isOn: $bindings.allowsLandscape) {
                    Label("Allow landscape", systemImage: "rectangle.landscape.rotate")
                }
                .onChange(of: bindings.allowsLandscape) { _, newValue in
                    viewModel.allowsLandscapeChanged(newValue)
                }
            #endif
            Toggle(isOn: $bindings.showMicrophoneButton) {
                Label("Show microphone", systemImage: "microphone")
            }
            #if os(iOS)
                Toggle(isOn: $bindings.enableActionButtons) {
                    Label("Show action buttons", systemImage: "hand.tap")
                }
            #endif
        }
        .navigationTitle("Interface")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        InterfaceSettingsView(
            bindings: SettingsBindings(),
            viewModel: SettingsViewModel())
    }
}
