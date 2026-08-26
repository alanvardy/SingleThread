import SingleThreadCore
import SwiftUI

/// Background preferences: toggle, fade percentage, and Unsplash photo credit.
/// Bound through the shared `@Observable` bag; photo credit is passed read-only
/// from ContentView's loaded background image.
struct BackgroundSettingsView: View {
    @Bindable var bindings: SettingsBindings

    let backgroundPhotographer: String?

    let backgroundPhotographerURL: URL?

    var body: some View {
        Form {
            Toggle(isOn: $bindings.backgroundEnabled) {
                Label("Background", systemImage: "photo")
            }
            Picker("Background Fade", selection: $bindings.backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            Section {} footer: {
                if let backgroundPhotographer {
                    if let backgroundPhotographerURL {
                        Link(
                            "Photo by \(backgroundPhotographer) on Unsplash",
                            destination: backgroundPhotographerURL)
                    } else {
                        Text("Photo by \(backgroundPhotographer) on Unsplash")
                    }
                }
            }
        }
        .navigationTitle("Background")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        BackgroundSettingsView(
            bindings: SettingsBindings(),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"))
    }
}
