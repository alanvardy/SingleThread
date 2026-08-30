import SingleThreadCore // periphery:ignore
import SwiftUI

/// Background preferences: toggle, fade percentage, and refreshing the wallpaper.
/// Takes only the bindings it needs plus the live `BackgroundImageStore`, whose
/// photo/attribution drives the refresh button's progress feedback.
struct BackgroundSettingsView: View {
    @Binding var backgroundEnabled: Bool

    @Binding var backgroundFadePercent: Int

    @Binding var backgroundPinned: Bool

    var backgroundImage: BackgroundImageStore

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
            if backgroundEnabled {
                Section {
                    Toggle(isOn: $backgroundPinned) {
                        Label("Pin wallpaper", systemImage: "pin")
                    }
                }
            }
            Section {
                Button {
                    Task { await backgroundImage.forceRefresh() }
                } label: {
                    HStack {
                        Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if backgroundImage.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(backgroundImage.isRefreshing)
                .accessibilityValue(backgroundImage.isRefreshing ? "Refreshing" : "")
            }
            Section {} footer: {
                if let photographer = backgroundImage.photographer {
                    if let url = backgroundImage.photographerURL {
                        Link(
                            "Photo by \(photographer) on Unsplash",
                            destination: url)
                    } else {
                        Text("Photo by \(photographer) on Unsplash")
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
            backgroundPinned: .constant(false),
            backgroundImage: BackgroundImageStore())
    }
}
