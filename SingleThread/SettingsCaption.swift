import SwiftUI

// MARK: - SettingsCaption

/// Shared caption styling used under every settings row title.
/// Call sites pass a `LocalizedStringKey` literal so Style A
/// auto-localization is preserved.
struct SettingsCaption: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - SettingsLinkLabel

/// NavigationLink label with a title, system image, and caption subtitle.
/// Used for the eight root settings rows.
struct SettingsLinkLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let caption: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                SettingsCaption(text: caption)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
