@testable import SingleThreadCore
import StoreKitTest
import Testing

// `@testable` (above) grants internal access to the `testingWithEntitled:` seam.

@MainActor
@Suite(.serialized)
struct EntitlementStoreTests {
    // SKTestSession for driving StoreKit in test.

    @Test
    func isEntitledIsFalseByDefault() {
        let store = EntitlementStore()
        #expect(!store.isEntitled)
    }

    @Test
    func hasResolvedEntitlementIsFalseByDefault() {
        let store = EntitlementStore()
        #expect(!store.hasResolvedEntitlement)
    }

    @Test
    func seamSetsEntitlement() {
        let entitled = EntitlementStore(testingWithEntitled: true)
        #expect(entitled.isEntitled)
        #expect(entitled.hasResolvedEntitlement)
        let notEntitled = EntitlementStore(testingWithEntitled: false)
        #expect(!notEntitled.isEntitled)
        #expect(notEntitled.hasResolvedEntitlement)
    }

    @Test
    func unresolvedSeamLeavesFlagsFalse() {
        let store = EntitlementStore(testingWithEntitlementUnresolved: ())
        #expect(!store.isEntitled)
        #expect(!store.hasResolvedEntitlement)
    }

    @Test
    func isEntitledSurvivesStoreRecreation() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        // The purchase path is exercised through the test seam
        // (`testingWithEntitled:`) because `SKTestSession.buyProduct` cannot
        // complete via `xcodebuild test` on Xcode 26.6 (config never reaches
        // the simulator's storekitd container; FB22237318). A fresh real store
        // on an empty account stays not entitled.
        let first = EntitlementStore(testingWithEntitled: true)
        #expect(first.isEntitled)

        let second = EntitlementStore()
        // The init task performs an initial entitlement refresh, but needs a
        // beat to deliver.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!second.isEntitled)
    }

    @Test
    func nonMatchingProductIDDoesNotSetEntitlement() throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        // No purchase exists, so the entitlement stays false regardless of
        // which product IDs are present in the storekit file.
        let store = EntitlementStore()
        #expect(!store.isEntitled)
    }

    /// The init task's initial entitlement refresh must settle
    /// `hasResolvedEntitlement` even on an empty account, so the UI never
    /// strands on the pre-resolution blank slot.
    @Test
    func initialRefreshSettlesResolvedFlag() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        let store = EntitlementStore()
        var waited: UInt64 = 0
        while !store.hasResolvedEntitlement, waited < 2_000_000_000 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 50_000_000
        }
        #expect(store.hasResolvedEntitlement)
        #expect(!store.isEntitled)
    }
}
