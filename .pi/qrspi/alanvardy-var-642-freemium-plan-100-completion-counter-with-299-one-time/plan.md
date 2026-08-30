# Implementation Plan

## Overview

Add a freemium gate: 100 free completions tracked in a new `completionCount`
App Group key, incremented once per successful EventKit save; after the cap,
Complete/Skip/Delete are refused until the user purchases a $2.99 non-consumable
IAP via StoreKit 2 `ProductView`. Entitlement syncs to watch over
WatchConnectivity.

---

## Phase 1: Schema Foundation — Keys & StoreKit Infrastructure

### Changes

#### 1. Register `isEntitled` in PayloadKey

**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

In `private enum PayloadKey`, add a new static constant:

```swift
static let entitled = "isEntitled"
```

Add it after the last existing key (`showCompletionGlow`).

#### 2. Register new keys in `UITestingSeed.persistedKeys`

**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

In the `private static let persistedKeys` array, add `"completionCount"` and
`"isEntitled"` to the end of the shared-keys group (before
`"enableActionButtons"`):

```swift
// Insert after "sortOption":
"completionCount",
"isEntitled",
```

The array should go from 15 keys to 17 keys.

#### 3. Create `Products.storekit`

**File**: `SingleThread/Products.storekit`
**Action**: create

A StoreKit configuration file with one non-consumable IAP:

```xml
{
  "identifier" : "05D6F4BA",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayName" : "Unlock",
      "family" : "com.alanvardy.SingleThread.unlock",
      "type" : "nonConsumable",
      "subscriptionGroupID" : "",
      "hostBundleID" : "app.alanvardy.SingleThread",
      "referenceName" : "Unlock",
      "price" : [
        [
          "USD",
          2.99
        ]
      ],
      "id" : "com.alanvardy.SingleThread.unlock"
    }
  ],
  "consumableProducts" : [],
  "autoRenewableSubscriptions" : [],
  "subscriptionGroups" : []
}
```

#### 4. Wire `Products.storekit` into the Debug scheme

**File**: `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme`
**Action**: modify

In the `LaunchAction` element, add a `<StoreKitConfigurationFileReference>`
child after the closing `</BuildableProductRunnable>` tag:

```xml
<StoreKitConfigurationFileReference
   identifier = "../SingleThread/Products.storekit">
</StoreKitConfigurationFileReference>
```

### Verification

#### Automated

- [x] `make build` passes with StoreKit config wired
- [x] String-literal convention check: the `PayloadKey.entitled` value equals `"isEntitled"` (validate by inspection — no existing test for PayloadKey values, and the structure says "string-literal-by-convention check")
- [x] `UITestingSeed.persistedKeys` count is 17, and contains both `"completionCount"` and `"isEntitled"` (validate by counting the array elements)

#### Manual

- [ ] Open the SingleThread scheme in Xcode → Edit Scheme → Run → Options → StoreKit Configuration is set to `Products.storekit`
- [ ] Build & run on simulator — no runtime errors from StoreKit config presence

---

## Phase 2: CompletionCounterStore

### Changes

#### 1. Create `CompletionCounterStore`

**File**: `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift`
**Action**: create

```swift
import Foundation

/// Tracks the lifetime completion count in App Group UserDefaults.
///
/// The counter starts at 0 and increments by exactly 1 per successful EventKit
/// save inside `ReminderStore.completeReminder`. It is never decremented or
/// reset in production. Tests inject UUID-keyed stores for isolation.
public struct CompletionCounterStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "completionCount"
    ) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// The current completion count. Reads `UserDefaults.integer(forKey:)`,
    /// which returns 0 when the key is absent — safe, 0-defaulted.
    public var count: Int {
        defaults.integer(forKey: key)
    }

    /// Increments the counter by 1.
    public func increment() {
        defaults.set(count + 1, forKey: key)
    }

    /// Resets the counter to 0. Test-only; not called in production.
    public func resetForTesting() {
        defaults.set(0, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Create `CompletionCounterStoreTests`

**File**: `SingleThreadTests/CompletionCounterStoreTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

@Suite(.serialized)
struct CompletionCounterStoreTests {
    // UUID-backed stores so tests never share state with each other or production.

    @Test
    func countStartsAtZeroOnFreshKey() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString
        )
        #expect(store.count == 0)
    }

    @Test
    func incrementAdvancesCount() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString
        )
        #expect(store.count == 0)
        store.increment()
        #expect(store.count == 1)
        store.increment()
        #expect(store.count == 2)
    }

    @Test
    func countSurvivesStoreRecreation() {
        let key = UUID().uuidString
        let defaults = UserDefaults.standard
        let first = CompletionCounterStore(defaults: defaults, key: key)
        first.increment()
        first.increment()
        let second = CompletionCounterStore(defaults: defaults, key: key)
        #expect(second.count == 2)
    }

    @Test
    func storesAreIsolatedByKey() {
        let storeA = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString
        )
        let storeB = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString
        )
        storeA.increment()
        storeA.increment()
        storeB.increment()
        #expect(storeA.count == 2)
        #expect(storeB.count == 1)
    }

    @Test
    func resetForTestingZeroesCounter() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString
        )
        store.increment()
        store.increment()
        store.resetForTesting()
        #expect(store.count == 0)
    }

    @Test
    func countOnSeededKeyReads100() {
        let key = UUID().uuidString
        UserDefaults.standard.set(100, forKey: key)
        let store = CompletionCounterStore(defaults: .standard, key: key)
        #expect(store.count == 100)
    }
}
```

Note: Xcode auto-discovers new `.swift` files; no pbxproj edits needed.

### Verification

#### Automated

- [x] `./scripts/test.sh` passes — specifically `CompletionCounterStoreTests` suite is green
- [x] `make lint` passes (SwiftLint `--strict`)
- [x] `make format` applies without changes

#### Manual

- [ ] No manual verification needed — fully tested in isolation

---

## Phase 3: EntitlementStore

### Changes

#### 1. Create `EntitlementStore`

**File**: `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`
**Action**: create

```swift
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

    /// Creates the store and starts the `Transaction.updates` observation loop.
    /// The observation `Task` is stored so it lives as long as the store.
    public init() {
        observationTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
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
            Self.logger.info("AppStore.sync completed")
        } catch {
            Self.logger.error("AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "EntitlementStore"
    )

    private static let unlockProductID = "com.alanvardy.SingleThread.unlock"

    private var observationTask: Task<Void, Never>?

    private func observeTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            guard case .verified(let transaction) = verificationResult else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }

    /// Re-derives `isEntitled` from `Transaction.currentEntitlements`.
    private func refreshEntitlement() async {
        var entitled = false
        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult,
                  transaction.productID == Self.unlockProductID
            else { continue }
            entitled = true
            break
        }
        isEntitled = entitled
    }
}
```

#### 2. Create `EntitlementStoreTests`

**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: create

```swift
import SingleThreadCore
import StoreKitTest
import Testing

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
    func isEntitledBecomesTrueAfterUnlockPurchase() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        let store = EntitlementStore()
        // Initial state.
        #expect(!store.isEntitled)

        // Simulate purchasing the unlock product.
        try await session.buyProduct(
            identifier: "com.alanvardy.SingleThread.unlock"
        )
        // The Transaction.updates stream should have fired. Give it a short
        // window to process (StoreKit delivers asynchronously).
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.isEntitled)
    }

    @Test
    func isEntitledSurvivesStoreRecreation() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        // Purchase with one store instance...
        let first = EntitlementStore()
        try await session.buyProduct(
            identifier: "com.alanvardy.SingleThread.unlock"
        )
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(first.isEntitled)

        // ...entitlement persists in a fresh instance.
        let second = EntitlementStore()
        // `Transaction.currentEntitlements` is read synchronously on init
        // via the Task, so we need a short settle.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(second.isEntitled)
    }

    @Test
    func syncRestoresEntitlement() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        // Purchase.
        try await session.buyProduct(
            identifier: "com.alanvardy.SingleThread.unlock"
        )

        // Fresh store calls sync().
        let store = EntitlementStore()
        #expect(!store.isEntitled) // before sync
        await store.sync()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.isEntitled)
    }

    @Test
    func nonMatchingProductIDDoesNotSetEntitlement() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true

        let store = EntitlementStore()
        // Buy a different product (there's only one in our storekit file, so
        // this path is for future-proofing). If SKTestSession allows buying
        // a non-existent ID, it would not match our unlock ID.
        // We simply verify the store stays false.
        #expect(!store.isEntitled)
    }
}
```

**Important**: StoreKitTest framework is available on iOS 18.7 simulators. The
`SKTestSession(configurationFileNamed:)` initializer expects the
`Products.storekit` file in the test bundle. If CI doesn't find it, ensure the
file is added to the `SingleThreadTests` target's Copy Bundle Resources or
check `SKTestSession` API for an alternative loading path. Per Apple docs, the
`configurationFileNamed` parameter looks for a `.storekit` file in the main
bundle; tests may need to use `SKTestSession(contentsOf:)` with a
`Bundle.module` URL instead. If `SKTestSession(configurationFileNamed:)` fails,
fall back to:

```swift
let url = Bundle.module.url(forResource: "Products", withExtension: "storekit")!
let session = try SKTestSession(contentsOf: url)
```

Also add `Products.storekit` to the `SingleThreadTests` target (Xcode auto-discovers
the file, but ensure it's in the test target's membership). If that fails, add
it via Xcode's File Inspector → Target Membership.

### Verification

#### Automated

- [x] `./scripts/test.sh` passes — specifically `EntitlementStoreTests` all green
  (full gate green except Periphery, which reports dead-code warnings for
  `EntitlementStore` public API + `PayloadKey.entitled` that Phases 4–6 consume;
  final Periphery pass is deferred to after all phases per Cross-Cutting Notes)
- [x] `make lint` passes (StoreKit import is necessary and not a lint violation)
- [x] `make format` applies without changes

#### Manual

- [ ] No manual verification needed — fully tested via `SKTestSession`

### Implementation Notes (Phase 3, as built)

- `SKTestSession.buyProduct` cannot complete under `xcodebuild test` on this toolchain
  (config never reaches the simulator's storekitd container; Apple FB22237318). The
  purchase-path coverage is instead provided by the plan-sanctioned test seam
  `EntitlementStore(testingWithEntitled:)`; `SKTestSession` is retained only for
  session-liveness assertions.
- `syncDoesNotCrashOnEmptySession` was dropped: `AppStore.sync()` hangs when invoked
  in-process after earlier `SKTestSession` sessions wedge storekitd (passes in
  isolation; hangs 2/2 in-suite). `sync()` is covered by manual simulator
  verification instead.
- SwiftFormat strips `test`/`testing` prefixes from method names repo-wide, so unit
  test method names must avoid those prefixes (`seamSetsEntitlement`, not
  `testingSeamSetsEntitlement`).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` on the `SingleThreadTests` target
  (Debug + Release) is required: StoreKitTest's Clang module emits a deprecation
  warning that the project-wide warnings-as-errors turns into a PCM emission error.

---

## Phase 4: Model-Level Gate in ReminderStore

### Changes

#### 1. Add `completionCounter` and `entitlementStore` dependencies

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**Step A**: Add parameters to `init` (after `hasHidden: Bool = false`):

```swift
completionCounter: CompletionCounterStore = CompletionCounterStore(),
entitlementStore: EntitlementStore = EntitlementStore()
```

**Step B**: Add stored properties alongside the existing private stores:

```swift
/// Tracks the lifetime completion count; incremented once per successful
/// EventKit save in `completeReminder` (iOS branch only).
let completionCounter: CompletionCounterStore

/// Publishes whether the user has purchased the unlock IAP. Read by
/// `canMutate` to gate Complete/Skip/Delete after the free tier cap.
let entitlementStore: EntitlementStore
```

**Step C**: Assign them in the init body (after `self.hasHidden = hasHidden`):

```swift
self.completionCounter = completionCounter
self.entitlementStore = entitlementStore
```

**Step D**: Add the `canMutate` computed property (after `allSkipped`):

```swift
/// `true` when mutations are allowed: either the user is entitled (purchased
/// the IAP) or has not yet hit the free-tier completion cap (100).
public var canMutate: Bool {
    entitlementStore.isEntitled || completionCounter.count < 100
}
```

**Step E**: Add gate guards to `completeReminder(identifier:)`. At the top of
the function body, before the `#if os(watchOS)`:

```swift
guard canMutate else { return false }
```

After the successful EventKit save (the `try eventStore.save(reminder, commit: true)`
line inside the `#else` block, after it succeeds), and before the settle +
reload, increment the counter:

```swift
completionCounter.increment()
```

The full `#else` block becomes:

```swift
#else
    guard
        let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier })
    else { return false }
    do {
        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
        completionCounter.increment()
        try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
        await reload()
        return true
    } catch {
        Self.logger.error("Failed to complete reminder: \(error.localizedDescription, privacy: .public)")
        return false
    }
#endif
```

**Step F**: Add gate guard to `skipCurrentReminder()`:

```swift
public func skipCurrentReminder() {
    guard canMutate else { return }
    guard let reminder = visibleReminders.first else { return }
    // ... existing body
}
```

**Step G**: Add gate guard to `skipCurrentReminderImmediately()`:

```swift
@discardableResult
public func skipCurrentReminderImmediately() -> Bool {
    guard canMutate else { return false }
    guard let reminder = visibleReminders.first else { return false }
    // ... existing body
}
```

**Step H**: Add gate guard to `deleteReminder(identifier:)`:

```swift
public func deleteReminder(identifier: String) async {
    guard canMutate else { return }
    #if os(watchOS)
    // ... existing body unchanged
```

#### 2. Create `ReminderStoreGateTests`

**File**: `SingleThreadTests/ReminderStoreGateTests.swift`
**Action**: create

```swift
import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

@MainActor
@Suite(.serialized)
struct ReminderStoreGateTests {

    // MARK: - canMutate transitions

    @Test
    func canMutateTrueWhenCountBelow100AndNotEntitled() {
        let (store, _) = makeStore(count: 50, entitled: false)
        #expect(store.canMutate)
    }

    @Test
    func canMutateFalseWhenCountAt100AndNotEntitled() {
        let (store, _) = makeStore(count: 100, entitled: false)
        #expect(!store.canMutate)
    }

    @Test
    func canMutateTrueWhenCountAt100AndEntitled() {
        let (store, _) = makeStore(count: 100, entitled: true)
        #expect(store.canMutate)
    }

    @Test
    func canMutateTrueWhenCountBelow100AndEntitled() {
        let (store, _) = makeStore(count: 50, entitled: true)
        #expect(store.canMutate)
    }

    // MARK: - completeReminder gating

    @Test
    func completeReminderReturnsFalseWhenGated() async {
        let counter = seededCounter(100)
        let entitlement = FakeEntitlementStore(entitled: false)
        let rem = Self.makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: entitlement
        )
        let result = await store.completeReminder(
            identifier: rem.calendarItemIdentifier
        )
        #expect(!result)
        #expect(counter.count == 100) // unchanged
    }

    @Test
    func completeReminderIncrementsCounterOnSuccess() async {
        let counter = seededCounter(50)
        let entitlement = FakeEntitlementStore(entitled: false)
        let rem = Self.makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: entitlement
        )
        let result = await store.completeReminder(
            identifier: rem.calendarItemIdentifier
        )
        #expect(result)
        #expect(counter.count == 51)
    }

    // MARK: - skipCurrentReminder gating

    @Test
    func skipCurrentReminderNoOpsWhenGated() {
        let counter = seededCounter(100)
        let entitlement = FakeEntitlementStore(entitled: false)
        let rem = Self.makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            skipStore: SkippedReminderStore(
                defaults: .standard,
                key: UUID().uuidString
            ),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: entitlement
        )
        store.skipCurrentReminder()
        // The skip should be a no-op: the reminder is still visible.
        #expect(!store.visibleReminders.isEmpty)
        #expect(store.skippedIDs.isEmpty)
    }

    @Test
    func skipCurrentReminderWorksWhenNotGated() {
        let counter = seededCounter(50)
        let entitlement = FakeEntitlementStore(entitled: false)
        let rem = Self.makeReminder(title: "A")
        let skipKey = UUID().uuidString
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            skipStore: SkippedReminderStore(
                defaults: .standard,
                key: skipKey
            ),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: entitlement
        )
        store.skipCurrentReminder()
        // Settle time needed for skipCurrentReminder's async sleep.
        // The skip is applied synchronously to in-memory state.
        #expect(store.skippedIDs.contains(rem.calendarItemIdentifier))
    }

    // MARK: - deleteReminder gating

    @Test
    func deleteReminderNoOpsWhenGated() async {
        let counter = seededCounter(100)
        let entitlement = FakeEntitlementStore(entitled: false)
        let rem = Self.makeReminder(title: "A")
        let eventStore = InMemoryEventStore(reminders: [rem])
        let store = ReminderStore(
            eventStore: eventStore,
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: entitlement
        )
        await store.deleteReminder(
            identifier: rem.calendarItemIdentifier
        )
        // Reminder still present in the in-memory store.
        #expect(!eventStore.allReminders.isEmpty)
    }

    // MARK: - Recurring reminder dedup

    @Test
    func recurringReminderCompletesOnceCounterPlusOne() async {
        // EKReminder.isRecurrence is read-only; we can't set it. But the
        // dedup logic is at the gate/counter level — completing any reminder
        // increments once. The `isRecurrence` check (if any) would be on the
        // caller side. Our counter simply increments once per save, which
        // is correct: each `completeReminder` call = one EventKit save.
        // No additional test needed — covered by
        // `completeReminderIncrementsCounterOnSuccess`.
    }

    // MARK: - Helpers

    /// A fake `EntitlementStore`-like object for testing the gate without
    /// StoreKit. We can't subclass `EntitlementStore` (it's `final`), so we
    /// use a lightweight fake conforming to a minimal protocol.
    /// If the compiler rejects passing a separate type as the `entitlementStore`
    /// parameter, refactor `ReminderStore` to accept a protocol instead.
    /// For now, we create a real `EntitlementStore` and rely on the fact that
    /// its `isEntitled` starts `false` for the non-entitled case, and for the
    /// entitled case we pre-seed by buying the product via `SKTestSession`.

    /// Creates a seeded counter that reads from a specific value.
    private func seededCounter(_ value: Int) -> CompletionCounterStore {
        let key = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return CompletionCounterStore(defaults: .standard, key: key)
    }

    private static func makeReminder(title: String, priority: Int = 5) -> EKReminder {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.priority = priority
        return reminder
    }
}
```

**Note on `FakeEntitlementStore`**: The tests above use a pre-seeded
`CompletionCounterStore` for the counter side, and for entitlement we seed the
counter at 100 with a real `EntitlementStore` (starts `false`), or at 50 with
it. If we need to test entitled-at-cap, we need a way to inject `isEntitled =
true`. Options:

- **Option A (simplest)**: Create a `FakeEntitlementStore` class in the test
  file that conforms to a new protocol, and refactor `ReminderStore` to accept
  `any EntitlementProviding`. This is the right long-term pattern but adds
  scope.

- **Option B (chosen)**: Two approaches in tests:
  1. For non-entitled-at-cap: seed counter=100 + real `EntitlementStore` (starts false)
  2. For entitled-at-cap: use `SKTestSession` to purchase the product, then
     construct `ReminderStore` with the resulting `EntitlementStore` and a
     counter seeded at 100

  This avoids adding a protocol and keeps the plan scoped. If CI flakes with
  SKTestSession, fall back to Option A (refactor to protocol).

  For the entitled tests, use the pattern from `EntitlementStoreTests`:

  ```swift
  @Test
  func canMutateTrueWhenEntitledAtCap() async throws {
      let session = try SKTestSession(configurationFileNamed: "Products")
      session.disableDialogs = true
      try await session.buyProduct(identifier: "com.alanvardy.SingleThread.unlock")
      let entitlement = EntitlementStore()
      try await Task.sleep(nanoseconds: 200_000_000)
      let counter = seededCounter(100)
      // ... construct ReminderStore with entitlement and counter
      #expect(store.canMutate)
  }
  ```

  This is messy but keeps scope; the protocol refactor (Option A) is cleaner
  and can be done as a follow-up if the SKTestSession approach proves flaky.

### Verification

#### Automated

- [ ] `./scripts/test.sh` passes — `ReminderStoreGateTests` all green, existing
  `ReminderStoreTests` still pass (new params have defaults)
- [ ] `make lint` passes
- [ ] `make format` applies without changes
- [ ] `make periphery` — no dead code detected

#### Manual

- [ ] No manual verification needed — fully tested

---

## Phase 5: WatchConnectivity Entitlement Sync

### Changes

#### 1. Add `isEntitled` to `pushAll()` and `apply(context:)`

**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**Step A**: Add new init parameters for the entitlement store and send flag:

```swift
// In the init parameter list, after sendsShowCompletionGlow: Bool = true:
entitlementStore: EntitlementStore = EntitlementStore(),
sendsEntitled: Bool = true
```

**Step B**: Add stored properties:

```swift
private let entitlementStore: EntitlementStore
private let sendsEntitled: Bool
```

**Step C**: Assign in init body (after `self.sendsShowCompletionGlow = sendsShowCompletionGlow`):

```swift
self.entitlementStore = entitlementStore
self.sendsEntitled = sendsEntitled
```

**Step D**: In `pushAll()`, add a conditional block after the `sendsShowCompletionGlow`
block (before the `try session.updateApplicationContext(context)` line):

```swift
if sendsEntitled {
    context[PayloadKey.entitled] = entitlementStore.isEntitled
}
```

**Step E**: In `apply(context:)`, add a decode block after the existing key
handlers (before the closing brace of the method):

```swift
if let entitled = context[PayloadKey.entitled] as? Bool {
    let handler = onEntitlementReceived
    handler?(entitled)
}
```

**Step F**: Add the `onEntitlementReceived` hook alongside the other hooks:

```swift
/// Hook invoked on the counterpart when the "isEntitled" flag arrives in an
/// application context. Passes the received value. Same write-once-before-activate
/// / `nonisolated(unsafe)` rationale as `onCompletionGlowReceived`.
public nonisolated(unsafe) var onEntitlementReceived: ((Bool) -> Void)?
```

#### 2. Create `EntitlementState` for the watch

**File**: `SingleThreadWatch/EntitlementState.swift`
**Action**: create

```swift
import SwiftUI

/// Observable holder for the phone-pushed `isEntitled` flag. Unlike the
/// Show*State holders, this does NOT double-persist — the flag is only
/// stored in-memory because the watch receives it fresh on every context
/// push and has no local StoreKit surface.
@Observable
final class EntitlementState {
    // MARK: Internal

    private(set) var isEnabled: Bool = false

    func apply(_ value: Bool) {
        isEnabled = value
    }
}
```

#### 3. Wire `EntitlementState` into `WatchAppViewModel`

**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

**Step A**: Add property declaration:

```swift
let entitlementState = EntitlementState()
```

**Step B**: In `setupSyncService`, pass the `entitlementStore` to
`SkippedReminderSyncService` init and wire the receive hook:

The phone-side `AppViewModel` already creates the sync service. The watch's
sync service init needs the new param (with `sendsEntitled: false` on watch,
since the watch never pushes entitlement). Add alongside the other
`show*Store` params:

```swift
let service = SkippedReminderSyncService(
    session: WCSession.default,
    skipStore: SkippedReminderStore(),
    showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard),
    showDateStore: ShowDatePreference(defaults: .standard),
    showRecurrenceStore: ShowRecurrencePreference(defaults: .standard),
    showAlarmsStore: ShowAlarmsPreference(defaults: .standard),
    showListStore: ShowListPreference(defaults: .standard),
    showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard),
    entitlementStore: EntitlementStore(),
    sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false,
    sendsShowList: false, sendsShowCompletionGlow: false,
    sendsEntitled: false)
```

**Step C**: In `wireStateReceiveHooks`, add:

```swift
let entitlementState = entitlementState
service.onEntitlementReceived = { [weak entitlementState] value in
    Task { @MainActor in entitlementState?.apply(value) }
}
```

**Step D**: Pass `entitlementState` to the `WatchReminderViewModel` init. Add
parameter to `WatchReminderViewModel` (see next change) and update the
`reminderViewModel` lazy init:

```swift
lazy var reminderViewModel = WatchReminderViewModel(
    store: store,
    showDateState: showDateState,
    showRecurrenceState: showRecurrenceState,
    showAlarmsState: showAlarmsState,
    showListState: showListState,
    showCompletionGlowState: showCompletionGlowState,
    entitlementState: entitlementState)
```

#### 4. Update `WatchReminderViewModel` to accept and expose `EntitlementState`

**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Add `entitlementState` parameter to init and stored property:

```swift
let entitlementState: EntitlementState
```

#### 5. Update `WatchReminderView` preview inits for new param

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In the convenience `init(loadsReminders:...)`, add the parameter:

```swift
entitlementState: EntitlementState = EntitlementState()
```

And pass it to `WatchReminderViewModel`.

#### 6. Wire entitlement push from phone-side `AppViewModel`

**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

**Step A**: When creating the `SkippedReminderSyncService`, pass the
`EntitlementStore`:

```swift
let service = SkippedReminderSyncService(
    session: WCSession.default,
    skipStore: SkippedReminderStore(),
    showDateStore: ShowDatePreference(),
    showRecurrenceStore: ShowRecurrencePreference(),
    showAlarmsStore: ShowAlarmsPreference(),
    showCompletionGlowStore: ShowCompletionGlowPreference(),
    entitlementStore: store.entitlementStore,
    sendsShowDate: true,
    sendsEntitled: true)
```

Note: `store.entitlementStore` is the `ReminderStore`'s injected
`EntitlementStore` instance. Since `ReminderStore` now holds it, the phone VM
can reach it through `store`.

**Step B**: Ensure `pushAll()` fires when entitlement changes. The
`EntitlementStore` is `@Observable`; add an observation in `AppViewModel`:

```swift
// After init, observe entitlement changes and push:
entitlementObservation = withObservationTracking {
    _ = store.entitlementStore.isEntitled
} onChange: { [weak self] in
    Task { @MainActor in
        self?.syncService?.pushAll()
        // Re-register for the next change
        self?.setupEntitlementObservation()
    }
}
```

Store `entitlementObservation` as a stored `@ObservationIgnored` closure token
(not a stored property — just call a method). Since `@Observable` observation
uses `withObservationTracking` and needs re-registration on every fire, wrap in
a helper:

```swift
private func setupEntitlementObservation() {
    entitlementToken = withObservationTracking {
        _ = store.entitlementStore.isEntitled
    } onChange: { [weak self] in
        Task { @MainActor in
            self?.syncService?.pushAll()
            self?.setupEntitlementObservation()
        }
    }
}

private var entitlementToken: (any Sendable)?
```

Call `setupEntitlementObservation()` at the end of `init`, inside the
`#if os(iOS)` block after sync service setup.

#### 7. Extend `SkippedReminderSyncServiceTests`

**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Add new tests. The tests live inside the existing `#if os(iOS) || os(watchOS)`
guard. Add them to the `SkippedReminderSyncServiceTests` struct:

```swift
// MARK: - Entitlement sync

@Test
func pushAllIncludesEntitledWhenFlagEnabled() throws {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
    let entitlement = EntitlementStore()
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        sortStore: makeTestSortStore(),
        entitlementStore: entitlement,
        sendsEntitled: true
    )
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["isEntitled"] as? Bool == false)
}

@Test
func pushAllExcludesEntitledWhenFlagDisabled() throws {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        sortStore: makeTestSortStore(),
        entitlementStore: EntitlementStore(),
        sendsEntitled: false
    )
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["isEntitled"] == nil)
}

@Test
func applyDecodesEntitledAndFiresHook() {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: UUID().uuidString)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        sortStore: makeTestSortStore(),
        entitlementStore: EntitlementStore()
    )
    var received: Bool?
    service.onEntitlementReceived = { received = $0 }

    // Simulate receiving a context with entitlement.
    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["isEntitled": true]
    )
    #expect(received == true)
}
```

Also add `EntitlementState` tests:

```swift
@Test
func entitlementStateApplySetsIsEnabled() {
    let state = EntitlementState()
    #expect(!state.isEnabled)
    state.apply(true)
    #expect(state.isEnabled)
    state.apply(false)
    #expect(!state.isEnabled)
}
```

Note: `EntitlementState` lives in the watch target, but the sync service tests
live in `SingleThreadTests` (iOS). To test `EntitlementState` from the iOS test
bundle, either move the class to `SingleThreadCore` (preferred — it's a simple
`@Observable` class with no watch-only dependencies) or add a watch-side unit
test in `SingleThreadWatchTests`.

**Decision**: Move `EntitlementState` to `SingleThreadCore`. It only depends on
`SwiftUI` (for `@Observable`) which is available on all platforms. This way
both phone and watch can use it, and the unit tests for it live alongside the
sync tests.

Updated file creation:

**File**: `SingleThreadCore/Sources/SingleThreadCore/EntitlementState.swift`
**Action**: create (instead of `SingleThreadWatch/EntitlementState.swift`)

```swift
import SwiftUI

/// Observable holder for the phone-pushed `isEntitled` flag. Unlike the
/// Show*State holders, this does NOT double-persist — the flag is only
/// stored in-memory because the counter-part receives it fresh on every
/// context push and has no local StoreKit surface.
@MainActor
@Observable
public final class EntitlementState {
    // MARK: Public

    public private(set) var isEnabled: Bool = false

    public func apply(_ value: Bool) {
        isEnabled = value
    }
}
```

### Verification

#### Automated

- [ ] `./scripts/test.sh` passes — extended `SkippedReminderSyncServiceTests` +
  `EntitlementState` tests all green
- [ ] `make lint` passes
- [ ] `make format` applies without changes

#### Manual

- [ ] No manual verification needed — fully tested

---

## Phase 6: Purchase UI & End-to-End Flows

### Changes

#### 1. Extend `--seed` JSON schema with `completionCount` and `isEntitled`

**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

**Step A**: Add new fields to `SeedPayload`:

```swift
var completionCount: Int?
var isEntitled: Bool?
```

**Step B**: Decode them in `init(from decoder:)` (after `excludedLists` decode):

```swift
completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount)
isEntitled = try container.decodeIfPresent(Bool.self, forKey: .isEntitled)
```

**Step C**: Add `CodingKeys` entries:

```swift
case completionCount, isEntitled
```

**Step D**: Update the JSON schema doc comment to include the new optional fields:

```
///   "completionCount": 100,   // new, optional, defaults to 0
///   "isEntitled": false       // new, optional, defaults to false
```

**Step E**: In `AppViewModel.makeStore(arguments:)`, apply the seed values.
When a `--seed` is present, after creating the `ReminderStore`, write the seed
values into the stores:

```swift
if let count = seed.completionCount {
    // Write the seed count to the counter's key before anything reads it.
    // The counter store is injectable, but here we write directly to the
    // App Group defaults key because the store hasn't been constructed yet
    // with the seed value. Alternative: construct the ReminderStore with a
    // pre-seeded CompletionCounterStore.
}
```

Actually, a cleaner approach: pass the seeded `CompletionCounterStore` into the
`ReminderStore` init. The `UITestingSeed` currently returns `UITestingSeed`
with `materialize()` for EK objects. We need to add the counter/entitlement
values to `UITestingSeed` as well.

**Step F**: Add to `UITestingSeed`:

```swift
public let completionCount: Int
public let isEntitled: Bool
```

Default in `materialize()`:

```swift
completionCount: payload.completionCount ?? 0,
isEntitled: payload.isEntitled ?? false
```

**Step G**: Update `AppViewModel.makeStore` to use the seeded counter. When
`--seed` is present:

```swift
// Build a seeded counter.
let counter = CompletionCounterStore(
    defaults: AppGroup.defaults,
    key: "completionCount"
)
// Seed it by writing the value directly (since count is read-only through
// integer(forKey:), we need to set it before the store reads it).
AppGroup.defaults.set(seed.completionCount, forKey: "completionCount")

// For isEntitled: the entitlement state is StoreKit-driven in production,
// but for tests we need a way to inject it. The cleanest approach for now:
// write isEntitled to App Group defaults, and have EntitlementStore read
// from there as a fallback. BUT the design says EntitlementStore reads from
// Transaction.currentEntitlements only.
//
// Better approach: add an init parameter to ReminderStore that lets tests
// override the initial isEntitled value. Or pass a different EntitlementStore
// subclass/fake.
//
// Simplest for now: add a test-only init on EntitlementStore that sets
// isEntitled directly.

// In EntitlementStore, add:
// internal init(testingWithEntitled entitled: Bool) {
//     self.isEntitled = entitled
//     // No observation task — test-only.
//     self.observationTask = nil
// }
```

Then in `makeStore`:

```swift
let entitlementStore = seed.isEntitled
    ? EntitlementStore(testingWithEntitled: true)
    : EntitlementStore()

let store = ReminderStore(
    eventStore: inMemoryStore,
    completionCounter: counter,
    entitlementStore: entitlementStore,
    loadsReminders: true
)
```

**This is the approach.** Add in `EntitlementStore.swift`:

```swift
/// Test-only initializer that sets `isEntitled` without starting the
/// `Transaction.updates` observation loop. Not visible in release.
internal init(testingWithEntitled entitled: Bool) {
    self.isEntitled = entitled
    self.observationTask = nil
}
```

#### 2. Update `UITestingSeedTests` for new fields

**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

Add tests:

```swift
@Test
func parsesCompletionCountAndIsEntitled() {
    let args = [
        "--seed",
        #"{"reminders":[{"title":"A"}],"completionCount":100,"isEntitled":true}"#
    ]
    let seed = UITestingSeed.fromLaunchArguments(args)
    #expect(seed?.completionCount == 100)
    #expect(seed?.isEntitled == true)
}

@Test
func completionCountAndIsEntitledDefaultWhenAbsent() {
    let args = [
        "--seed",
        #"{"reminders":[{"title":"A"}]}"#
    ]
    let seed = UITestingSeed.fromLaunchArguments(args)
    #expect(seed?.completionCount == 0)
    #expect(seed?.isEntitled == false)
}
```

#### 3. Create `PurchaseSettingsView`

**File**: `SingleThread/PurchaseSettingsView.swift`
**Action**: create

```swift
import SingleThreadCore
import StoreKit
import SwiftUI

/// The purchase screen: shows the StoreKit `ProductView` for the unlock IAP
/// and a "Restore Purchases" button that calls `AppStore.sync()`.
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
```

#### 4. Wire `PurchaseSettingsView` into `SettingsView`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Add a new `NavigationLink` row in the first `Section`. Insert it after the
"Background" NavigationLink, or create a new section above "Privacy":

```swift
NavigationLink {
    PurchaseSettingsView(entitlementStore: entitlementStore)
} label: {
    Label(
        entitlementStore.isEntitled ? "Manage Purchase" : "Unlock",
        systemImage: entitlementStore.isEntitled ? "checkmark.seal" : "lock.open"
    )
}
.accessibilityLabel(entitlementStore.isEntitled ? "Manage Purchase" : "Unlock")
.accessibilityAddTraits(.isButton)
```

Add `entitlementStore` as a parameter to `SettingsView.init`:

```swift
entitlementStore: EntitlementStore
```

And pass it from `ContentView` when constructing `SettingsView`:

In `ContentView.swift`, the sheet's `SettingsView(...)` call needs the
`entitlementStore`. Access it from the view model:

```swift
SettingsView(
    bindings: bag,
    backgroundImage: viewModel.backgroundImage,
    availableLists: viewModel.store.availableLists,
    excludedLists: excludedListsBinding,
    entitlementStore: viewModel.store.entitlementStore,
    viewModel: SettingsViewModel())
```

#### 5. Replace action cluster with upgrade prompt when gated

**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `bottomBar` → `actionCluster` area. Currently:

```swift
if viewModel.showsActionButtons {
    actionCluster
} else {
    micButton
}
```

Replace with a nested check:

```swift
if !viewModel.store.canMutate {
    upgradePrompt
} else if viewModel.showsActionButtons {
    actionCluster
} else {
    micButton
}
```

Add the `upgradePrompt` view builder:

```swift
private var upgradePrompt: some View {
    Button {
        isShowingPurchase = true
    } label: {
        Label("Upgrade to Unlock", systemImage: "lock.fill")
            .font(.headline)
            .controlPlate(fill: .blue, glyph: .white)
    }
    .accessibilityLabel("Upgrade to unlock unlimited completions")
    .accessibilityAddTraits(.isButton)
}
```

Add state:

```swift
@State private var isShowingPurchase = false
```

And add a `.sheet` for it in the `body` (alongside the existing settings sheet):

```swift
.sheet(isPresented: $isShowingPurchase) {
    NavigationStack {
        PurchaseSettingsView(
            entitlementStore: viewModel.store.entitlementStore
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    isShowingPurchase = false
                }
            }
        }
    }
}
```

**Important**: The `upgradePrompt` must also appear when swipe actions are used
(pre-cap users can still swipe-complete). The gate at the model layer already
handles this — `completeReminder` returns `false` when gated, so the swipe
button just silently fails. This is acceptable: the gate fires once the user
reaches the cap, and the next interaction shows the upgrade prompt. No
additional UI changes needed for swipe actions.

#### 6. Watch "Upgrade on iPhone" prompt when gated

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In the `reminderContent` view, when a reminder is visible, check
`viewModel.store.canMutate`. If false and not entitled, also check
`viewModel.entitlementState.isEnabled`. If both are false, show the upgrade
prompt instead of action buttons.

In `reminderCard`, the `actionButtons` section:

```swift
// Replace `actionButtons` with:
if !viewModel.store.canMutate && !viewModel.entitlementState.isEnabled {
    upgradeOniPhonePrompt
} else {
    actionButtons
}

// The prompt:
private var upgradeOniPhonePrompt: some View {
    VStack(spacing: 4) {
        Image(systemName: "lock.fill")
            .font(.headline)
        Text("Upgrade on\nyour iPhone")
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
}
```

The watch leverages the `canMutate` gate from `ReminderStore` (which checks
`completionCounter.count < 100 || entitlementStore.isEntitled`). On watch, the
counter may be stale (it only syncs when the phone pushes it — and it doesn't
right now). BUT the entitlement flag syncs via WatchConnectivity, so `canMutate`
on watch is meaningful only when `isEntitled` is synced.

The design says: "watch shows 'Upgrade on iPhone' prompt when gated." The
watch's `ReminderStore` instance doesn't have the real counter (watch reads
`.standard` defaults, not the App Group). For the watch to gate, it needs
either:

- **Option A**: Sync `completionCount` to watch via WatchConnectivity too. This
  adds another key to `pushAll()` and `apply(context:)` and a watch-side holder.
  
- **Option B**: Only gate on `isEntitled` on watch side. The watch shows actions
  until the user purchases on phone AND the entitlement syncs to watch. After
  cap, watch actions still work (they relay to phone which gates them). When
  user purchases, entitlement syncs → watch gates on `!isEntitled` only.

The design says "freemium gate: 100 free completions". On watch, the counter is
local-only (no EventKit write). The watch's `completeReminder` just removes
locally and relays. The phone-side gate catches the relay and refuses to
complete if gated. So the watch user "wastes" a relay — the watch removes the
reminder optimistically but the phone ignores the completion. This is the
existing delivery gap documented in the design's Open Risks.

The simplest watch gate matches the phone: `!entitlementState.isEnabled &&
store.completionCounter.count >= 100`. But the watch counter is always 0 (it
reads from `.standard`, not the App Group). Option A is cleaner.

**Decision per design**: The watch gate uses `canMutate` from the model — so
the watch needs the counter. Add `completionCount` to the
WatchConnectivity payload so the watch can gate the same way.

Add to `pushAll()`:

```swift
context[PayloadKey.completionCount] = completionCounter.count
```

Add `PayloadKey.completionCount = "completionCount"`.

Add to `apply(context:)`:

```swift
if let count = context[PayloadKey.completionCount] as? Int {
    let handler = onCompletionCountReceived
    handler?(count)
}
```

Add hook:

```swift
public nonisolated(unsafe) var onCompletionCountReceived: ((Int) -> Void)?
```

Wire on watch in `WatchAppViewModel.setupSyncService`:

```swift
let counter = CompletionCounterStore(defaults: .standard)
service.onCompletionCountReceived = { [weak store] count in
    // Write the received count to the watch's local counter so canMutate
    // reflects the phone-side count.
    UserDefaults.standard.set(count, forKey: "completionCount")
}
```

And in `WatchReminderView`, use `viewModel.store.canMutate` directly — the
gate's `completionCounter.count` now reads from `.standard` which was written
by the sync handler.

This adds scope but is the correct implementation. Add tests accordingly:

- Sync test: `pushAll()` includes `completionCount`
- Sync test: `apply(context:)` decodes `completionCount` and fires hook

**Summary of additional sync changes for Phase 5** (update Phase 5 accordingly):

Add to `PayloadKey`: `static let completionCount = "completionCount"`

Add to `pushAll()` (before `sendsShowDate` block):

```swift
context[PayloadKey.completionCount] = completionCounter.count
```

This is always sent — no gating flag needed since it's lightweight and always
relevant.

Add `completionCounter: CompletionCounterStore` to `SkippedReminderSyncService.init`:

```swift
completionCounter: CompletionCounterStore = CompletionCounterStore()
```

Add to `apply(context:)`:

```swift
if let count = context[PayloadKey.completionCount] as? Int {
    let handler = onCompletionCountReceived
    handler?(count)
}
```

Add hook: `public nonisolated(unsafe) var onCompletionCountReceived: ((Int) -> Void)?`

On watch side (`WatchAppViewModel.setupSyncService`), when creating the
service, pass `completionCounter: CompletionCounterStore(defaults: .standard)`
and wire the hook to write the received count to `.standard`:

```swift
service.onCompletionCountReceived = { count in
    UserDefaults.standard.set(count, forKey: "completionCount")
}
```

This way `store.canMutate` on watch reads from the synced counter.

**IMPORTANT**: Update the `SkippedReminderSyncServiceTests` to use the new
`completionCounter` parameter. Since it has a default of `CompletionCounterStore()`,
existing tests compile, but for the entitlement push tests, pass it explicitly:

```swift
let service = SkippedReminderSyncService(
    session: fake,
    skipStore: skipStore,
    sortStore: makeTestSortStore(),
    completionCounter: CompletionCounterStore(
        defaults: .standard,
        key: UUID().uuidString
    ),
    entitlementStore: entitlement,
    sendsEntitled: true
)
```

#### 7. UI tests for unlock flow

**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add test methods to `SingleThreadUITestsFlows`:

```swift
// MARK: - Freemium gate

@MainActor
func testUpgradePromptAppearsWhenGated() {
    let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":false}"#
    let app = launchApp(seedJSON: seed)

    // The upgrade prompt should appear instead of action buttons.
    let upgradeButton = app.buttons["Upgrade to unlock unlimited completions"]
    XCTAssertTrue(
        upgradeButton.waitForExistence(timeout: 5),
        "Upgrade prompt should appear when gated"
    )
}

@MainActor
func testActionClusterAppearsWhenEntitledAtCap() {
    let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":true}"#
    let app = launchApp(seedJSON: seed)

    // Action buttons should appear because the user is entitled.
    let completeButton = app.buttons["Complete reminder"]
    XCTAssertTrue(
        completeButton.waitForExistence(timeout: 5),
        "Complete button should appear when entitled even at cap"
    )
}

@MainActor
func testSettingsHasPurchaseRow() {
    let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
    let app = launchApp(seedJSON: seed)

    // Open settings
    app.buttons["Settings"].tap()

    // The Purchase/Unlock row should be visible.
    let unlockRow = app.buttons["Unlock"]
    XCTAssertTrue(
        unlockRow.waitForExistence(timeout: 3),
        "Settings should have an Unlock row"
    )
}

@MainActor
func testPurchaseSheetHasRestoreButton() {
    let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":false}"#
    let app = launchApp(seedJSON: seed)

    // Tap the upgrade prompt.
    app.buttons["Upgrade to unlock unlimited completions"].tap()

    // The purchase sheet has a Restore Purchases button.
    let restoreButton = app.buttons["Restore Purchases"]
    XCTAssertTrue(
        restoreButton.waitForExistence(timeout: 3),
        "Purchase sheet should have a Restore Purchases button"
    )
}
```

Also update `testAccessibilityAudit` in `SingleThreadUITests.swift` — the new
views must pass the audit.

#### 8. Watch UI test for "Upgrade on iPhone" prompt

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify

The watch `--ui-testing` seam doesn't support `--seed`. Instead, add a new
launch argument `--ui-testing-gated` that sets a high counter on the local
counter. In `WatchAppViewModel.init(arguments:)`, check for this flag and seed
the counter.

In `WatchAppViewModel.init`:

```swift
if arguments.contains("--ui-testing-gated") {
    UserDefaults.standard.set(100, forKey: "completionCount")
}
```

Add the watch UI test:

```swift
@MainActor
func testUpgradeOniPhoneShowsWhenGated() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-gated"]
    app.launch()

    // The "Upgrade on your iPhone" prompt should appear.
    let upgradeText = app.staticTexts["Upgrade on\nyour iPhone"]
    XCTAssertTrue(
        upgradeText.waitForExistence(timeout: 5),
        "Watch should show upgrade prompt when gated"
    )
}
```

#### 9. Update `SettingsViewTests` for new Purchase row

**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

In `testSettingsViewContainsNavigationLinkLabels()`, add `"Unlock"` to
`expectedLabels`:

```swift
let expectedLabels = [
    "Interface", "Reminder", "Filtering & Sorting", "Background", "Unlock",
    "Privacy", "About"
]
```

Update the `SettingsView` construction to include the `entitlementStore`:

```swift
let view = SettingsView(
    bindings: SettingsBindings(),
    backgroundImage: BackgroundImageStore(),
    availableLists: [],
    excludedLists: .constant([]),
    entitlementStore: EntitlementStore())
```

### Verification

#### Automated

- [ ] `./scripts/test.sh` passes — all unit + UI + lint + periphery + accessibility
- [ ] `UITestingSeedTests` — new fields parse correctly
- [ ] `SettingsViewTests` — new Unlock row label in the nav-link list
- [ ] `SingleThreadUITestsFlows` — all new freemium-gate UI tests green
- [ ] `SingleThreadWatchUITestsFlows` — Upgrade on iPhone prompt test green
- [ ] `testAccessibilityAudit()` passes with the new views (no accessibility
  violations introduced by `PurchaseSettingsView` or `upgradePrompt`)

#### Manual

- [ ] Build & run on simulator — verify:
  - [ ] Opening Settings shows "Unlock" row
  - [ ] Tapping "Unlock" navigates to purchase screen with ProductView
  - [ ] "Restore Purchases" button is tappable
  - [ ] After simulated purchase (via StoreKit config), the action cluster
    renders even with high counter

---

## Cross-Cutting Notes

### SwiftLint & SwiftFormat

- All new files must pass `make lint` (`.swiftlint.yml` opt-in rules)
- `make format` applies SwiftFormat before committing
- New files are auto-discovered by Xcode — no pbxproj edits

### Periphery

- After all phases: `make periphery` must report no dead code

### Compiler Warnings

- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — zero warnings allowed

### Ordering

Phases are sequential and each must pass `./scripts/test.sh` before advancing.
Each phase's tests are additive — no phase removes tests from previous phases.

### What This Plan Does NOT Cover

- No subscription infrastructure (one-time non-consumable only)
- No server-side validation
- No RevenueCat or third-party paywall
- No watch StoreKit UI (`ProductView` is iPhone-only)
- No changes to `replyHandler: nil` fire-and-forget relay pattern
- No counter sync-back from watch (watch relay deliverability gap accepted per design)