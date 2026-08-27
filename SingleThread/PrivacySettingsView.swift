import SwiftUI

// MARK: - PrivacySettingsView

/// Read-only, long-form disclosure of what SingleThread reads, stores, and
/// syncs. Stateless: no bindings, no view model, no init parameters — it
/// renders `PrivacyGuideContent` directly.
struct PrivacySettingsView: View {
    var body: some View {
        Form {
            ForEach(PrivacyGuideContent.sections) { section in
                Section(section.title) {
                    Text(section.body)
                }
            }
            Section {} footer: {
                Text(PrivacyGuideContent.closingLine)
            }
        }
        .navigationTitle("Privacy Policy")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        PrivacySettingsView()
    }
}
