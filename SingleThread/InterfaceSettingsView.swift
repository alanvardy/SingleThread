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

    @Binding var enableActionButtons: Bool

    #if os(iOS)
        @Binding var showSwipePrompt: Bool
    #endif

    #if os(iOS)
        @Binding var showUndoButton: Bool
    #endif

    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Appearance")
                    SettingsCaption(text: "Choose between system, light, and dark mode.")
                }
            }
            .accessibilityIdentifier("appearancePicker")
            Picker(selection: $textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Text Size")
                    SettingsCaption(text: "Adjust the size of text throughout the app.")
                }
            }
            .accessibilityIdentifier("textSizePicker")
            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Allow landscape")
                            SettingsCaption(text: "Let the app rotate on iPhone.")
                        }
                    } icon: {
                        Image(systemName: "rectangle.landscape.rotate")
                    }
                }
                .accessibilityIdentifier("allowLandscapeToggle")
                .onChange(of: allowsLandscape) { _, newValue in
                    viewModel.allowsLandscapeChanged(newValue)
                }
            #endif
            Toggle(isOn: $showMicrophoneButton) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show microphone")
                        SettingsCaption(text: "Add a microphone button for voice input.")
                    }
                } icon: {
                    Image(systemName: "microphone")
                }
            }
            .accessibilityIdentifier("showMicrophoneToggle")
            #if os(iOS)
                Toggle(isOn: $enableActionButtons) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Show action buttons")
                            SettingsCaption(text: "Show complete, skip, and delete buttons.")
                        }
                    } icon: {
                        Image(systemName: "hand.tap")
                    }
                }
                .accessibilityIdentifier("showActionButtonsToggle")
                Toggle(isOn: $showSwipePrompt) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Show swipe prompt")
                            SettingsCaption(text: "Show a hint when there are swipeable reminders.")
                        }
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                }
                .accessibilityIdentifier("showSwipePromptToggle")
                .accessibilityLabel("Show swipe prompt")
                Toggle(isOn: $showUndoButton) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Show undo button")
                            SettingsCaption(text: "Show an undo button after completing a reminder.")
                        }
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
                .accessibilityIdentifier("showUndoButtonToggle")
            #endif
        }
        .navigationTitle("Interface")
        .settingsSubscreenLayout()
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
                enableActionButtons: .constant(false),
                viewModel: SettingsViewModel())
        #endif
    }
}
