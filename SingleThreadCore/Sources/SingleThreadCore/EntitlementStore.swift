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
        observationTask = nil
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: Public

    /// Whether the user has purchased the unlock IAP. Reactively updated by
    /// the `Transaction.updates` stream; also updated by `sync()`.
    public private(set) var isEntitled: Bool = false

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

    private static let unlockProductID = "com.alanvardy.SingleThread.unlock"

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
    }
}
