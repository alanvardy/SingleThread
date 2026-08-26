import SingleThreadCore // periphery:ignore
import SwiftUI

/// Background preferences: toggle, fade percentage, and Unsplash photo credit.
/// Takes only the bindings it needs rather than the full bag; photo credit is
/// passed read-only from ContentView's loaded background image.
struct BackgroundSettingsView: View {
    @Binding var backgroundEnabled: Bool

    @Binding var backgroundFadePercent: Int

    let backgroundPhotographer: String?

    let backgroundPhotographerURL: URL?

    var body: some View {
        Form {
            Toggle(isOn: $backgroundEnabled) {
                Label("Background", systemImage: "photo")
            }
            Picker("Background Fade", selection: $backgroundFadePercent) {
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
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"))
    }
}
