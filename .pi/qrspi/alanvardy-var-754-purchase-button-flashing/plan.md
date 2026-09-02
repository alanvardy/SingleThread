# Implementation Plan

## Overview

Suppress the iOS bottom-bar freemium cluster while StoreKit entitlement is unresolved — a purchased user no longer sees the "Upgrade to unlimited" button flash before the async refresh lands. A new in-memory `hasResolvedEntitlement` flag gates rendering in `ContentView.bottomBar`; `isEntitled`, `canMutate`, silent mutation guards, the completion counter, and the watch sync payload are untouched.

---

## Phase 1: State contract — `EntitlementStore.hasResolvedEntitlement`

### Changes

#### 1. New observable flag on `EntitlementStore`
**File**: `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`
**Action**: modify

Add the resolved flag next to `isEntitled` (after line 46):

```swift
/// Whether the `isEntitled` value has been settled by at least one
/// StoreKit refresh (or by a test seam). Views gate rendering on this
/// flag so a purchased user never sees the "Upgrade to unlimited"
/// prompt flash before the async entitlement check completes.
public private(set) var hasResolvedEntitlement: Bool = false
```

Set it in `refreshEntitlement()` immediately after the `isEntitled` assignment (end of method, after line 90):

```swift
isEntitled = entitled
hasResolvedEntitlement = true
```

Set it in `init(testingWithEntitled:)` (after the `isEntitled` assignment on line 28):

```swift
isEntitled = entitled
hasResolvedEntitlement = true
```

#### 2. Unit tests for the new flag
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify

Add new test (after `isEntitledIsFalseByDefault`, before `seamSetsEntitlement`):

```swift
@Test
func hasResolvedEntitlementIsFalseByDefault() {
    let store = EntitlementStore()
    #expect(!store.hasResolvedEntitlement)
}
```

Extend `seamSetsEntitlement` to also assert the resolved flag (add to both branches):

```swift
@Test
func seamSetsEntitlement() {
    let entitled = EntitlementStore(testingWithEntitled: true)
    #expect(entitled.isEntitled)
    #expect(entitled.hasResolvedEntitlement)
    let notEntitled = EntitlementStore(testingWithEntitled: false)
    #expect(!notEntitled.isEntitled)
    #expect(notEntitled.hasResolvedEntitlement)
}
```

### Verification

#### Automated
- [x] `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -only-testing:SingleThreadTests/EntitlementStoreTests` passes
- [x] Existing `isEntitledIsFalseByDefault`, `isEntitledSurvivesStoreRecreation`, and `nonMatchingProductIDDoesNotSetEntitlement` still pass

#### Manual
- [ ] Code review: confirm `hasResolvedEntitlement = true` is set at exactly the same sites as `isEntitled` assignment — `refreshEntitlement()` end and `init(testingWithEntitled:)`

---

## Phase 2: Testable state injection — unresolved seam + `--seed` field

### Changes

#### 1. Unresolved initializer on `EntitlementStore`
**File**: `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`
**Action**: modify

Add new public init after `init(testingWithEntitled:)` (after line 32):

```swift
/// UI-test seam: leaves both `isEntitled` and `hasResolvedEntitlement`
/// false with no observation task, so the UI deterministically renders
/// the pre-resolution state (no upgrade button, no action cluster).
public init(testingWithEntitlementUnresolved: ()) {
    observationTask = nil
}
```

(`isEntitled` and `hasResolvedEntitlement` stay at their `false` defaults; no explicit assignment needed.)

#### 2. `entitlementUnresolved` field on `UITestingSeed`
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

Add the new field to the public struct properties (after `isEntitled` on line 29):

```swift
public let entitlementUnresolved: Bool
```

Add to the doc-comment JSON schema block (around line 18, inside the example JSON):

```json
//   "entitlementUnresolved": true  // optional, defaults to false; when true,
//                                  // the entitlement store starts unresolved
//                                  // so the pre-resolution render is testable
```

In `SeedPayload`, add the property (after `isEntitled` on line 116):

```swift
var entitlementUnresolved: Bool = false
```

In `SeedPayload.init(from decoder:)`, add decode (after `hasHidden` decode, before closing brace of init):

```swift
entitlementUnresolved = try container.decodeIfPresent(Bool.self, forKey: .entitlementUnresolved) ?? false
```

In `SeedPayload.CodingKeys` (after `hasHidden` on line 155):

```swift
case entitlementUnresolved
```

In `SeedPayload.materialize()` — update the `UITestingSeed` constructor call to pass the new field (add after `hasHidden`):

```swift
return UITestingSeed(
    reminders: createdReminders,
    calendars: createdCalendars,
    excludedListTitles: Set(excludedLists),
    completionCount: completionCount,
    isEntitled: isEntitled,
    hasHidden: hasHidden,
    entitlementUnresolved: entitlementUnresolved)
```

#### 3. 3-way entitlement store in `seededStore`
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

Replace the 2-way entitlement store logic in `seededStore` (lines 298-300):

```swift
let entitlementStore = seed.isEntitled
    ? EntitlementStore(testingWithEntitled: true)
    : EntitlementStore()
```

With a 3-way switch that checks `entitlementUnresolved` first:

```swift
let entitlementStore: EntitlementStore
if seed.entitlementUnresolved {
    entitlementStore = EntitlementStore(testingWithEntitlementUnresolved: ())
} else if seed.isEntitled {
    entitlementStore = EntitlementStore(testingWithEntitled: true)
} else {
    entitlementStore = EntitlementStore()
}
```

#### 4. Unit tests for unresolved seam
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify

Add new test (after `seamSetsEntitlement`):

```swift
@Test
func unresolvedSeamLeavesFlagsFalse() {
    let store = EntitlementStore(testingWithEntitlementUnresolved: ())
    #expect(!store.isEntitled)
    #expect(!store.hasResolvedEntitlement)
}
```

#### 5. Unit tests for seed field
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

Add two new tests (after `completionCountAndIsEntitledDefaultWhenAbsent`):

```swift
@Test
func parsesEntitlementUnresolved() {
    let args = [
        "--seed",
        #"{"reminders":[{"title":"A"}],"entitlementUnresolved":true}"#
    ]
    let seed = UITestingSeed.fromLaunchArguments(args)

    #expect(seed?.entitlementUnresolved == true)
    #expect(seed?.isEntitled == false)  // default when not present
}

@Test
func entitlementUnresolvedDefaultsWhenAbsent() {
    let args = [
        "--seed",
        #"{"reminders":[{"title":"A"}]}"#
    ]
    let seed = UITestingSeed.fromLaunchArguments(args)

    #expect(seed?.entitlementUnresolved == false)
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -only-testing:SingleThreadTests/EntitlementStoreTests` passes — includes `unresolvedSeamLeavesFlagsFalse` + existing tests
- [ ] `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -only-testing:SingleThreadTests/UITestingSeedTests` passes — includes `parsesEntitlementUnresolved` and `entitlementUnresolvedDefaultsWhenAbsent` + existing tests

#### Manual
- [ ] None

---

## Phase 3: Presentation — gate the iOS bottom-bar freemium cluster

### Changes

#### 1. Gate `bottomBar` render on `hasResolvedEntitlement`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `bottomBar` extension, inside the `#if os(iOS)` branch (lines 678-685), add the unresolved guard as the first branch:

Replace:

```swift
                #if os(iOS)
                    if !viewModel.store.canMutate {
                        upgradePrompt
                    } else if viewModel.showsActionButtons {
                        actionCluster
                    } else {
                        micButton
                    }
```

With:

```swift
                #if os(iOS)
                    if !viewModel.store.entitlementStore.hasResolvedEntitlement {
                        EmptyView()
                    } else if !viewModel.store.canMutate {
                        upgradePrompt
                    } else if viewModel.showsActionButtons {
                        actionCluster
                    } else {
                        micButton
                    }
```

The `else` / non-iOS `micButton` branch and all branches above (macOS, error, feedback, dictation, unavailable-text) are unchanged.

#### 2. UI test — unresolved renders no upgrade button
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add new test in the `// MARK: - Freemium gate` section (after `testActionClusterAppearsWhenEntitledAtCap`):

```swift
@MainActor
func testUnresolvedEntitlementRendersNoUpgradeButton() {
    let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"entitlementUnresolved":true}"#
    let app = launchApp(seedJSON: seed)

    // While entitlement is unresolved, the upgrade button must not exist —
    // neither the gated prompt nor the action cluster should flash in.
    XCTAssertFalse(
        app.buttons["upgradeButton"].waitForExistence(timeout: 2),
        "Upgrade button must not appear when entitlement is unresolved")
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows` passes — new `testUnresolvedEntitlementRendersNoUpgradeButton` green
- [ ] Existing `testUpgradePromptAppearsWhenGated` and `testActionClusterAppearsWhenEntitledAtCap` still pass (unchanged seeds)
- [ ] `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -only-testing:SingleThreadTests/EntitlementSyncTests` passes — `pushAllIncludesEntitledWhenFlagEnabled` still asserts `context["isEntitled"] == false` (watch payload contract preserved)

#### Manual
- [ ] Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"isEntitled":false}'` — upgrade prompt appears in bottom bar (no regression)
- [ ] Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"isEntitled":true}'` — action cluster appears (no regression)
- [ ] Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"entitlementUnresolved":true}'` — bottom bar freemium slot is blank (no upgrade button, no action cluster)

---

## Testing Checkpoints

- **After Phase 1** — `EntitlementStoreTests` green: flag defaults `false`; seam sets `true`.
- **After Phase 2** — `EntitlementStoreTests` + `UITestingSeedTests` green: unresolved seam leaves both flags `false`; seed decodes/defaults `entitlementUnresolved`.
- **After Phase 3** — `SingleThreadUITestsFlows` freemium tests green (unresolved → no `upgradeButton`; gated/entitled unchanged) + `EntitlementSyncTests` green.
- **Full gate (once, parent)** — `./scripts/test.sh`.

Each checkpoint is independently re-runnable via the named `-only-testing:` suite. Do not advance past a failing stage.

## Cross-cutting note

`hasResolvedEntitlement` and `isEntitled` are two booleans kept in sync — resolved is set at exactly the `isEntitled` assignment site (single method today). A future edit adding an assignment site must set both; this invariant is asserted indirectly by Phase 1's `seamSetsEntitlement` extension which checks both flags after the synchronous seam.
