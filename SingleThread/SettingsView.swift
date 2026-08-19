import SwiftUI

// MARK: - SettingsView

/// Modal settings screen presented from the gear button. Owns no state —
/// every preference is bound back to `ContentView`'s `@AppStorage` values.
struct SettingsView: View {
    // MARK: Lifecycle

    #if os(iOS)
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            allowsLandscape: Binding<Bool>,
            showMicrophoneButton: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String]) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _allowsLandscape = allowsLandscape
            _showMicrophoneButton = showMicrophoneButton
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
        }
    #else
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            showMicrophoneButton: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String]) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _showMicrophoneButton = showMicrophoneButton
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
        }
    #endif

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                Picker("Text Size", selection: $textSize) {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        Label(size.title, systemImage: size.systemImage)
                            .tag(size)
                    }
                }
                #if os(iOS)
                    Toggle(isOn: $allowsLandscape) {
                        Label("Allow Landscape", systemImage: "rectangle.landscape.rotate")
                    }
                    .onChange(of: allowsLandscape) { _, newValue in
                        AppDelegate.applyLock(allowsLandscape: newValue)
                    }
                #endif
                Toggle(isOn: $showMicrophoneButton) {
                    Label("Show Microphone", systemImage: "microphone")
                }
                Section("Excluded Projects") {
                    ForEach(availableProjects, id: \.self) { project in
                        Toggle(isOn: excludedBinding(for: project)) {
                            Text(project)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .modifier(TextSizeModifier(textSize: textSize))
    }

    // MARK: Private

    @Binding private var appearanceMode: AppearanceMode
    @Binding private var textSize: TextSize
    #if os(iOS)
        @Binding private var allowsLandscape: Bool
    #endif
    @Binding private var showMicrophoneButton: Bool
    @Binding private var excludedProjects: Set<String>
    @Environment(\.dismiss)
    private var dismiss

    private let availableProjects: [String]

    private func excludedBinding(for project: String) -> Binding<Bool> {
        Binding(
            get: { excludedProjects.contains(project) },
            set: { isExcluded in
                if isExcluded {
                    excludedProjects.insert(project)
                } else {
                    excludedProjects.remove(project)
                }
            })
    }
}

// MARK: - Previews

#if os(iOS)
    #Preview("Default") {
        SettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            allowsLandscape: .constant(true),
            showMicrophoneButton: .constant(true),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"])
    }

    #Preview("Dark + Extra Large") {
        SettingsView(
            appearanceMode: .constant(.dark),
            textSize: .constant(.extraLarge),
            allowsLandscape: .constant(false),
            showMicrophoneButton: .constant(false),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"])
    }
#else
    #Preview("Default") {
        SettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            showMicrophoneButton: .constant(true),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"])
    }
#endif
