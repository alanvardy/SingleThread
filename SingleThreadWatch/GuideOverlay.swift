import SwiftUI

/// Full-screen guide overlay shown on first launch (and whenever the phone
/// toggles "show guide again" on). Describes the Complete and Skip buttons
/// with arrows, plus a "Got it" dismiss button.
struct GuideOverlay: View {
    /// Whether the overlay is rendered and interactive. Animation is gated
    /// on this flag from the parent view.
    let isActive: Bool

    /// Persists `false` and triggers fade-out when the user taps "Got it".
    let onDismiss: () -> Void

    /// When `true`, the overlay appears/disappears instantly instead of fading.
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.left")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text("Tap Complete to finish")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tap the Complete button to finish the current reminder")

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.right")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text("Tap Skip to skip")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tap the Skip button to skip the current reminder")

                Spacer()

                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Dismisses the guide and shows your reminders")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: isActive)
    }
}
