import SingleThreadCore // periphery:ignore
import SwiftUI

/// Background preferences: toggle, fade percentage, pin, and refreshing the
/// wallpaper. Takes only the bindings it needs plus the live
/// `BackgroundImageStore`, whose photo/attribution drives the refresh button's
/// progress feedback. The pin toggle stays visible even when Background is off
/// so the pin state is never hidden.
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
            .accessibilityIdentifier("backgroundToggle")
            Picker("Background Fade", selection: $backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            .accessibilityIdentifier("backgroundFadePicker")
            Section {
                Toggle(isOn: $backgroundPinned) {
                    Label("Pin wallpaper", systemImage: "pin")
                }
                .accessibilityIdentifier("pinWallpaperToggle")
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
                .accessibilityValue(
                    backgroundImage.isRefreshing
                        ? String(localized: "Refreshing", table: "Localizable", bundle: .main)
                        : "")
                .accessibilityIdentifier("refreshWallpaperButton")
            }
            Section {} footer: {
                if let photographer = backgroundImage.photographer {
                    let credit = String(
                        localized: "Photo by \(photographer) on Unsplash",
                        table: "Localizable", bundle: .main)
                    if let url = backgroundImage.photographerURL {
                        Link(credit, destination: url)
                    } else {
                        Text(credit)
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
