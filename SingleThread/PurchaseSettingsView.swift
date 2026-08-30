import SingleThreadCore
import StoreKit
import SwiftUI

/// The purchase screen: shows the StoreKit `ProductView` for the unlock IAP
/// and a "Restore Purchases" button that calls `AppStore.sync()`. Reached from
/// Settings, and (as a sheet) from the freemium upgrade prompt.
struct PurchaseSettingsView: View {
    let entitlementStore: EntitlementStore

    var body: some View {
        List {
            Section {
                if entitlementStore.isEntitled {
                    Label("You're all set! 🎉", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ProductView(id: "com.alanvardy.SingleThread.unlock")
                        .productViewStyle(.compact)
                }
            } header: {
                Text("Unlock SingleThread")
            } footer: {
                if entitlementStore.isEntitled {
                    Text("Thank you for your support! All features are unlocked.")
                } else {
                    Text("A one-time purchase of $2.99 unlocks unlimited completions, skips, and deletes forever.")
                }
            }

            Section {
                Button {
                    Task { await entitlementStore.sync() }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if entitlementStore.isEntitled {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .disabled(entitlementStore.isEntitled)
            } footer: {
                Text("If you've already purchased Unlock on another device, restore it here.")
            }
        }
        .navigationTitle("Unlock")
    }
}

/// The upgrade button shown in the main bottom bar when the free tier is gated.
/// Exposed as a button with an explicit label so the freemium-gate UI tests can
/// find it deterministically.
struct UpgradePromptButton: View {
    let isPresented: Binding<Bool>

    var body: some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            Label("Upgrade to Unlock", systemImage: "lock.fill")
                .font(.headline)
                .controlPlate(fill: .blue, glyph: .white)
        }
        .accessibilityLabel("Upgrade to unlock unlimited completions")
        .accessibilityAddTraits(.isButton)
    }
}

/// Navigation-wrapped `PurchaseSettingsView` presented as a sheet from the
/// freemium upgrade prompt, with a confirmation-action Done button.
struct PurchaseSheet: View {
    let isPresented: Binding<Bool>
    let entitlementStore: EntitlementStore

    var body: some View {
        NavigationStack {
            PurchaseSettingsView(entitlementStore: entitlementStore)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresented.wrappedValue = false
                        }
                    }
                }
        }
    }
}
