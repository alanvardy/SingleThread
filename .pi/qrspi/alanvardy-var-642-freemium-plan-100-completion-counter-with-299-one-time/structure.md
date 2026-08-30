# Structure Outline

## Approach

Build the freemium gate bottom-up in **six horizontal layers**, each fully
tested before the next begins. Counter + entitlement state sit in new store
structs; model-level gate in `ReminderStore` enforces one check for all nine
completion surfaces; StoreKit 2 `ProductView` unlocks permanently; watch
receives entitlement via WatchConnectivity.

---

## Stage 1: Schema Foundation — Keys & StoreKit Infrastructure

Register the two new persistence keys everywhere they must appear, and wire
StoreKit 2 into the Debug scheme so later layers can compile against it.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift` (PayloadKey)
- `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` (persistedKeys)
- `SingleThread/Products.storekit` — **new**
- `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme`

**Key changes**:
```swift
// PayloadKey enum — new entry:
static let entitled = "isEntitled"

// UITestingSeed.persistedKeys — two additions:
"completionCount",
"isEntitled"
```

- `Products.storekit`: one non-consumable IAP, product ID `"com.alanvardy.SingleThread.unlock"`, USD $2.99.
- Debug scheme `LaunchAction` gains `<StoreKitConfigurationFileReference>` pointing to `Products.storekit`.

**Tests**:
- `PayloadKey.entitled == "isEntitled"` (string-literal-by-convention check)
- `persistedKeys` contains both new keys; count = previous + 2
- `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` succeeds with StoreKit config wired

**Verify**: `make build` passes; new keys are the *only* schema change — no stores, no gate.

---

## Stage 2: CompletionCounterStore

A new `UserDefaults`-backed store-struct following the `Preference` convention.
Reads/writes `completionCount` from App Group, injectable defaults for tests.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift` — **new**
- `SingleThreadTests/CompletionCounterStoreTests.swift` — **new**

**Key signatures**:
```swift
public struct CompletionCounterStore {
    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "completionCount"
    )

    /// Reads `defaults.integer(forKey:)` — safe 0-defaulted.
    public var count: Int { get }

    /// Writes `count + 1`.
    public func increment()

    /// Writes 0 to clean up between tests. Not visible in release.
    public func resetForTesting()
}
```

**Tests** (`CompletionCounterStoreTests`, `@Suite(.serialized)`, UUID-key isolation):
- `count` starts at 0 on a fresh key
- `increment()` advances count 0→1→2→…
- `count` survives store re-creation (reads persisted value)
- Two stores with different UUID keys are isolated (`storesAreIsolatedByKey`)
- `resetForTesting()` zeroes the counter
- `count` on a 100-seeded key reads 100

**Verify**: `./scripts/test.sh` passes (all existing + new `CompletionCounterStoreTests`).

---

## Stage 3: EntitlementStore

A `@MainActor @Observable` class listening to StoreKit 2 `Transaction.updates`.
Publishes `isEntitled` for SwiftUI reactivity; exposes `sync()` for restore.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift` — **new**
- `SingleThreadTests/EntitlementStoreTests.swift` — **new**

**Key signatures**:
```swift
@MainActor @Observable
public final class EntitlementStore {
    public private(set) var isEntitled: Bool

    public init()

    /// Calls `AppStore.sync()` — restores previous purchase.
    public func sync() async

    // Internal: listens to Transaction.updates; updates isEntitled
    // when currentEntitlements contains the unlock product.
}
```

**Tests** (`EntitlementStoreTests`, `@MainActor @Suite(.serialized)`, `SKTestSession`):
- `isEntitled` is `false` by default (no purchase)
- Simulated purchase of unlock product → `isEntitled == true`
- `isEntitled` survives store re-creation (`Transaction.currentEntitlements`)
- `sync()` restores entitlement after simulated purchase on a fresh session
- Non-matching product ID does not set `isEntitled`

**Verify**: `./scripts/test.sh` passes; `SKTestSession`-based tests run in CI
(StoreKitTest framework available on iOS 18.7 simulators).

---

## Stage 4: Model-Level Gate in ReminderStore

The core enforcement layer. `ReminderStore` gains two injectable dependencies
(`CompletionCounterStore`, `EntitlementStore`), a `canMutate` computed property,
and guard clauses on every mutating method. Counter increments exactly once per
successful EventKit save — only in the iOS branch.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
- `SingleThreadTests/ReminderStoreGateTests.swift` — **new**

**Key changes**:
```swift
// ReminderStore.init gains two parameters (with defaults for production):
completionCounter: CompletionCounterStore = CompletionCounterStore(),
entitlementStore: EntitlementStore = EntitlementStore()

// ReminderStore gains:
let completionCounter: CompletionCounterStore
let entitlementStore: EntitlementStore

public var canMutate: Bool {
    entitlementStore.isEntitled || completionCounter.count < 100
}

// completeReminder — iOS branch, after eventStore.save succeeds:
completionCounter.increment()  // single point for phone/widget/watch-relay
// (watchOS #if branch never increments — no EventKit save)

// completeReminder — guard at top:
guard canMutate else { return false }

// skipCurrentReminder:
guard canMutate else { return }

// skipCurrentReminderImmediately:
guard canMutate else { return false }

// deleteReminder — guard at top:
guard canMutate else { return }
```

**Tests** (`ReminderStoreGateTests`, `@MainActor @Suite(.serialized)`):
- `canMutate` transitions:
  - `true` when count < 100 (regardless of entitlement)
  - `false` when count ≥ 100 AND `!isEntitled`
  - `true` when count ≥ 100 AND `isEntitled`
  - `true` when count < 100 AND `!isEntitled`
- `completeReminder` increments counter after successful save (iOS branch)
- `completeReminder` does NOT increment in watchOS branch (optimistic removal path)
- `completeReminder` returns `false` when gated (counter untouched)
- `skipCurrentReminder` no-ops when gated (skip set unchanged)
- `deleteReminder` no-ops when gated (reminder still present)
- Counter increments for widget-intent completes (runs iOS branch)
- Counter increments for watch-relay completes (re-enters iOS branch on phone)
- Recurring reminder (`isRecurrence`) completes once (counter +1, not per instance)

**Verify**: `./scripts/test.sh` passes; `ReminderStoreGateTests` all green.
Existing `ReminderStoreTests` still pass (new params have defaults).

---

## Stage 5: WatchConnectivity Entitlement Sync

`isEntitled` travels phone→watch in the `pushAll()` payload. Watch receives it
into a new `EntitlementState` holder, gating its own action button. Follows the
existing `ShowDateState` pattern but without double-persistence.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThreadCore/Sources/SingleThreadCore/EntitlementState.swift` — **new**
- `SingleThread/AppViewModel.swift`
- `SingleThreadWatch/WatchAppViewModel.swift`

**Key changes**:
```swift
// EntitlementState (new file, SingleThreadCore):
@MainActor @Observable
public final class EntitlementState {
    public private(set) var isEnabled: Bool = false
    public func apply(_ value: Bool) { isEnabled = value }
}

// SkippedReminderSyncService.init — new param + flag:
entitlementStore: EntitlementStore = EntitlementStore(),
sendsEntitled: Bool = true

// pushAll() — new conditional block:
if sendsEntitled {
    context[PayloadKey.entitled] = entitlementStore.isEntitled
}

// apply(context:) — new decode + hook:
if let entitled = context[PayloadKey.entitled] as? Bool {
    let handler = onEntitlementReceived
    handler?(entitled)
}

// onEntitlementReceived hook (nonisolated(unsafe), same pattern as existing hooks)
```

Phone side: `EntitlementStore` change → `pushAll()` → watch receives.
Watch side: `EntitlementState.apply(_:)` sets `isEnabled`; `WatchAppViewModel`
wires `onEntitlementReceived` hook.

**Tests** (extend `SkippedReminderSyncServiceTests`):
- `pushAll()` includes `isEntitled` in payload when `sendsEntitled: true`
- `pushAll()` excludes `isEntitled` when `sendsEntitled: false`
- `apply(context:)` decodes `isEntitled: true/false` and fires hook
- `EntitlementState.apply(true)` → `isEnabled == true`
- Round-trip: phone entitlement `true` → pushAll → apply → `EntitlementState.isEnabled == true`

**Verify**: `./scripts/test.sh` passes; existing sync tests still pass.

---

## Stage 6: Purchase UI & End-to-End Flows

iPhone presents `ProductView` when the gate fires; Settings gains Purchase &
Restore rows. Watch shows "Upgrade on iPhone" when gated. UI tests cover the
full unlock flow.

**Files**:
- `SingleThread/ContentView.swift`
- `SingleThread/PurchaseSettingsView.swift` — **new**
- `SingleThread/SettingsView.swift`
- `SingleThreadWatch/WatchReminderView.swift`
- `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` (extend schema)
- `SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:
```swift
// ContentView: when !store.canMutate, replace action cluster with:
UpgradePromptView(entitlementStore: store.entitlementStore)
    .sheet(isPresented:) { PurchaseSettingsView(entitlementStore:) }

// PurchaseSettingsView:
// - ProductView for "com.alanvardy.SingleThread.unlock"
// - "Restore Purchases" button → entitlementStore.sync()
// - manages product loading + purchase state

// SettingsView: new Section row
// NavigationLink to PurchaseSettingsView (or "Manage Purchase" if entitled)

// WatchReminderView: when !canMutate, show "Upgrade on iPhone" prompt

// --seed JSON schema extended:
{
  "reminders": [...],
  "calendars": [...],
  "excludedLists": [...],
  "completionCount": 100,   // new, optional, defaults to 0
  "isEntitled": false       // new, optional, defaults to false
}
```

**Tests**:
- `UITestingSeedTests`: new fields parse from JSON; absent keys default to 0/false
- UI test: upgrade sheet appears when `--seed '{..."completionCount":100,"isEntitled":false}'`
- UI test: action cluster renders when `--seed '{..."completionCount":100,"isEntitled":true}'`
- UI test: Settings → Purchase/Manage row navigates to `PurchaseSettingsView`
- UI test: "Restore Purchases" button is tappable (calls `sync()` on `SKTestSession`)
- Accessibility audit still passes (`testAccessibilityAudit()`)
- Watch UI test: "Upgrade on iPhone" renders when `--ui-testing` + count ≥ 100 + not entitled

**Verify**: `./scripts/test.sh` passes (unit + UI + lint + periphery + accessibility).

---

## Testing Checkpoints

After each stage, `./scripts/test.sh` must pass before advancing:

| Stage | What must be green |
|-------|-------------------|
| 1 | `make build` + key registration assertions |
| 2 | `CompletionCounterStoreTests` (isolation, increment, persistence) |
| 3 | `EntitlementStoreTests` (SKTestSession purchase/restore) |
| 4 | `ReminderStoreGateTests` (gate transitions, counter dedup) + existing `ReminderStoreTests` |
| 5 | Extended `SkippedReminderSyncServiceTests` (entitlement in payload round-trip) |
| 6 | `UITestingSeedTests` (schema) + `SingleThreadUITestsFlows` (unlock flow) + accessibility audit |