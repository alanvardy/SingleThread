import Foundation
import os
import StoreKit

/// Owns the "is entitled" flag by listening to StoreKit 2 `Transaction.updates`.
///
/// Published via `@Observable` so SwiftUI views react automatically. The phone
/// app owns one long-lived instance; the watch receives the flag over
/// WatchConnectivity instead of calling StoreKit APIs.
@MainActor
@Observable
public final class EntitlementStore {
    // MARK: Lifecycle

    /// Creates the store and starts the `Transaction.updates` observation loop,
    /// after an initial entitlement refresh so a fresh instance on an already
    /// purchased account starts entitled.
    public init() {
        observationTask = Task { [weak self] in
            await self?.refreshEntitlement()
            await self?.observeTransactionUpdates()
        }
    }

    /// Test/UI-test seam: sets `isEntitled` directly without starting the
    /// `Transaction.updates` observation loop. Used by the `--seed` launch-arg
    /// wiring in the app target (a separate module from this package, so the
    /// initializer must be public) and by unit tests. `isEntitled` defaults to
    /// false in production, so this seam only changes behavior under testing.
    public init(testingWithEntitled entitled: Bool) {
        isEntitled = entitled
        hasResolvedEntitlement = true
        observationTask = nil
    }

    /// UI-test seam: leaves both `isEntitled` and `hasResolvedEntitlement`
    /// false with no observation task, so the UI deterministically renders
    /// the pre-resolution state (no upgrade button, no action cluster).
    public init(testingWithEntitlementUnresolved _: ()) {
        observationTask = nil
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: Public

    /// The StoreKit product ID for the one-time unlock IAP.
    public static let unlockProductID = "app.alanvardy.SingleThread.unlimited"

    /// The free-tier lifetime-completion cap: the number of completions a
    /// non-entitled user may make before mutation is gated. Single source of
    /// truth — referenced by the mutation gate (`ReminderStore.canMutate`), the
    /// watch UI-test seam, and the boundary tests. Strict-`<` semantics: the
    /// gate closes at exactly this count.
    public static let freemiumCap = 100

    /// Whether the user has purchased the unlock IAP. Reactively updated by
    /// the `Transaction.updates` stream; also updated by `sync()`.
    public private(set) var isEntitled: Bool = false

    /// Whether the `isEntitled` value has been settled by at least one
    /// StoreKit refresh (or by a test seam). Views gate rendering on this
    /// flag so a purchased user never sees the "Upgrade to unlimited"
    /// prompt flash before the async entitlement check completes.
    public private(set) var hasResolvedEntitlement: Bool = false

    /// Calls `AppStore.sync()` to restore a prior purchase. StoreKit posts any
    /// resulting transactions to `Transaction.updates`, which this store
    /// observes, so `isEntitled` updates automatically after the sync completes.
    public func sync() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            Self.logger.info("AppStore.sync completed")
        } catch {
            Self.logger.error("AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "EntitlementStore")

    /// `nonisolated(unsafe)` so `deinit` (nonisolated) can cancel the observation
    /// task; the task captures `self` weakly and is only read/written on the
    /// main actor in normal operation.
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    private func observeTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            guard case let .verified(transaction) = verificationResult else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }

    /// Re-derives `isEntitled` from `Transaction.currentEntitlements`.
    private func refreshEntitlement() async {
        var entitled = false
        for await verificationResult in Transaction.currentEntitlements {
            guard case let .verified(transaction) = verificationResult,
                  transaction.productID == Self.unlockProductID
            else { continue }
            entitled = true
            break
        }
        isEntitled = entitled
        hasResolvedEntitlement = true
    }
}
