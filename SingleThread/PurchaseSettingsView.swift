import SingleThreadCore
import StoreKit
import SwiftUI

// MARK: - PurchaseSettingsView

/// The purchase screen: loads the unlock IAP product via `StoreKit.Product.products(for:)`
/// and shows a purchase button with localized price. Uses manual product loading instead
/// of `ProductView` so the view always has a stable intrinsic height — `ProductView` is
/// zero-height until product data arrives, so `List` may never re-measure the row.
/// Also shows loading, error, and purchased states clearly.
struct PurchaseSettingsView: View {
    // MARK: Internal

    let entitlementStore: EntitlementStore

    var body: some View {
        List {
            Section {
                if entitlementStore.isEntitled {
                    Label("You're all set! 🎉", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    purchaseContent
                }
            } header: {
                Text("Unlock SingleThread")
            } footer: {
                if entitlementStore.isEntitled {
                    Text("Thank you for your support! All features are unlocked.")
                } else if loadError != nil {
                    Text("Could not load product. Check your internet connection and try again.")
                        .foregroundStyle(.red)
                } else {
                    Text("A one-time purchase unlocks unlimited completions, skips, and deletes forever.")
                }
            }

            if !entitlementStore.isEntitled {
                Section {
                    Button {
                        Task { await entitlementStore.sync() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("restorePurchasesButton")
                } footer: {
                    Text("If you've already purchased Unlock on another device, restore it here.")
                }
            }
        }
        .navigationTitle("Unlock")
        .task {
            await loadProduct()
        }
        .onChange(of: entitlementStore.isEntitled) { _, entitled in
            if entitled {
                product = nil
                loadError = nil
                purchaseError = nil
                isPurchasing = false
            }
        }
    }

    // MARK: Private

    private static let unlockProductID = EntitlementStore.unlockProductID

    @State private var product: Product?
    @State private var loadError: String?
    @State private var purchaseError: String?
    @State private var isPurchasing = false

    @ViewBuilder private var purchaseContent: some View {
        if let error = loadError {
            VStack(spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Button("Try Again") {
                    loadError = nil
                    Task { await loadProduct() }
                }
                .buttonStyle(.bordered)
            }
            .frame(minHeight: 66)
        } else if let product {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.headline)
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await purchase(product) }
                    } label: {
                        if isPurchasing {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text(product.displayPrice)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchasing)
                }
                if let purchaseError {
                    Text(purchaseError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 66)
        } else {
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(minHeight: 66)
            .frame(maxWidth: .infinity)
        }
    }

    private func loadProduct() async {
        guard !entitlementStore.isEntitled else { return }
        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            product = products.first
            if product == nil {
                loadError = "Product not available."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success:
                await entitlementStore.sync()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        isPurchasing = false
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
            Label("Upgrade to unlimited", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(.blue, in: Capsule())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .accessibilityLabel("Upgrade to unlock unlimited completions")
        .accessibilityIdentifier("upgradeButton")
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
