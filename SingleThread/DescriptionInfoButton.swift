import SwiftUI

/// Tappable ⓘ affordance that reveals a short description of a settings row.
///
/// `View.help(_:)` is a pointer-driven tooltip: on iPhone it renders nothing
/// visible, so rows use this explicit button instead. Tapping presents the
/// description in a compact-adapted popover (a small floating bubble rather
/// than a full-screen sheet).
struct DescriptionInfoButton: View {
    // MARK: Lifecycle

    init(settingName: String, description: Text) {
        self.settingName = settingName
        self.description = description
    }

    // MARK: Internal

    var body: some View {
        Button {
            isShowingDescription = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(settingName)")
        .popover(isPresented: $isShowingDescription) {
            descriptionContent
        }
    }

    // MARK: Private

    @State private var isShowingDescription = false

    private let settingName: String
    private let description: Text

    private var descriptionContent: some View {
        #if os(iOS) || os(macCatalyst)
            return description
                .font(.subheadline)
                .padding()
                .presentationCompactAdaptation(.popover)
        #else
            return description
                .font(.subheadline)
                .padding()
        #endif
    }
}
