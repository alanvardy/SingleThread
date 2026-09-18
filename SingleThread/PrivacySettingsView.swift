import SwiftUI

// MARK: - PrivacySettingsView

/// Read-only, long-form disclosure of what SingleThread reads, stores, and
/// syncs. Stateless: no bindings, no view model, no init parameters. The copy
/// resolves against `\.locale` — the interface language injected at the app
/// root — so switching language re-renders the open screen in place (same
/// mechanism as `localizedNavigationTitle`).
struct PrivacySettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            ForEach(PrivacyGuideContent.sections(in: locale)) { section in
                Section(section.title) {
                    Text(section.body)
                }
            }
            Section {} footer: {
                Text(PrivacyGuideContent.closingLine(in: locale))
            }
        }
        .localizedNavigationTitle("Privacy Policy")
        .settingsSubscreenLayout()
    }

    // MARK: Private

    @Environment(\.locale)
    private var locale
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        PrivacySettingsView()
    }
}
