# Structure Outline

## Approach

Add an in-memory `hasResolvedEntitlement` flag to `EntitlementStore` and gate the
iOS bottom-bar freemium cluster on it — rendering **nothing** while entitlement is
unresolved — so a purchased user never sees the "Upgrade to unlimited" prompt
flash before the StoreKit refresh lands. `canMutate`, the silent mutation guards,
the completion counter, and the watch sync payload stay untouched; iOS-only.

> **Layer-map note**: entitlement is never persisted (always re-derived from
> `Transaction.currentEntitlements` — research Q4), so there is no migration/schema
> layer. The bottom layer is the `@Observable` **state contract** on
> `EntitlementStore` itself. The "transport" role is filled by the **test seams**
> (init-only + `--seed`) that let every layer above deterministically produce the
> three states (entitled / not-entitled / unresolved).

---

## Stage 1: State contract — `EntitlementStore.hasResolvedEntitlement`

Delivers the resolved flag every later layer reads, settled on all three
init/refresh paths. Green tests prove the default is `false` ("not yet known")
and the synchronous seam flips it `true` — while preserving the existing
`isEntitled == false` default contract.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`

**Key changes**:
- `public private(set) var hasResolvedEntitlement: Bool = false` — new observable flag; `isEntitled` keeps its `false` default (ambiguous false stays, but is now disambiguated by the flag).
- `private func refreshEntitlement() async` — sets `hasResolvedEntitlement = true` immediately after `isEntitled = entitled` (the only async assignment site).
- `public init(testingWithEntitled entitled: Bool)` — also sets `hasResolvedEntitlement = true`.

**Tests** (`SingleThreadTests/EntitlementStoreTests.swift`):
- `hasResolvedEntitlementIsFalseByDefault` — `EntitlementStore()` → `#expect(!store.hasResolvedEntitlement)` (sad path: the unresolved window exists).
- `seamSetsEntitlement` (extend) — `testingWithEntitled: true` → `#expect(store.hasResolvedEntitlement)`.

**Verify**: `make test` (or `xcodebuild -only-testing:SingleThreadTests` with a pinned `,OS=` destination) — `EntitlementStoreTests` green; `isEntitledIsFalseByDefault` and `EntitlementSyncTests` still green (false-default contract intact).

> **Accepted gap**: the StoreKit-driven `true` transition through
> `refreshEntitlement()` cannot be unit-tested (FB22237318 — research Q4). It is
> covered by review + the seam asserting the same assignment site. Noted, not
> worked around.

---

## Stage 2: Testable state injection — unresolved seam + `--seed` field

Adds a deterministic "unresolved" path (no observation task, no refresh) so UI
tests can reproduce the pre-resolution render. Green tests prove the new seam
leaves both flags `false` and the seed decodes the new field (present and absent).

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`
- `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
- `SingleThread/AppViewModel.swift`

**Key changes**:
- `public init(testingWithEntitlementUnresolved:)` — new; sets neither `isEntitled` nor `hasResolvedEntitlement`, `observationTask = nil`.
- `UITestingSeed.entitlementUnresolved: Bool` — new `public let`.
- `SeedPayload.entitlementUnresolved: Bool = false` — decoded `?? false`; new `CodingKeys` case `entitlementUnresolved`.
- `AppViewModel.seededStore` — 3-way entitlement store: `seed.entitlementUnresolved ? EntitlementStore(testingWithEntitlementUnresolved:) : (seed.isEntitled ? EntitlementStore(testingWithEntitled: true) : EntitlementStore())`.

**Tests**:
- `SingleThreadTests/EntitlementStoreTests.swift` — `unresolvedSeamLeavesFlagsFalse`: `testingWithEntitlementUnresolved:` → `#expect(!isEntitled && !hasResolvedEntitlement)`.
- `SingleThreadTests/UITestingSeedTests.swift` — `parsesEntitlementUnresolved` (present) and `entitlementUnresolvedDefaultsWhenAbsent` (absent → `false`).

**Verify**: `make test` (or `-only-testing:SingleThreadTests`) — both suites green; `hasResolvedEntitlement` stays `false` under the new seam (deterministic pre-resolution state).

---

## Stage 3: Presentation — gate the iOS bottom-bar freemium cluster

Consumes the Stage 1 flag: suppresses the whole cluster (upgrade prompt, action
cluster, mic) while entitlement is unresolved. Green UI tests prove unresolved →
no upgrade button, and the existing gated/entitled tests pass unchanged.

**Files**: `SingleThread/ContentView.swift` (`bottomBar`, iOS branch `:678-685`)

**Key changes** (view-builder condition only; `bottomBar` stays `some View`, no new type):
- Inside the `#if os(iOS)` cluster, add the first branch:
  `if !viewModel.store.entitlementStore.hasResolvedEntitlement { EmptyView() } else if !viewModel.store.canMutate { upgradePrompt } …`. `canMutate` (`ReminderStore.swift:136-138`) and the macOS/non-iOS branches are unchanged.

**Tests** (`SingleThreadUITests/SingleThreadUITestsFlows.swift`, "Freemium gate" section):
- `testUnresolvedEntitlementRendersNoUpgradeButton` — seed `{"reminders":[…],"completionCount":100,"entitlementUnresolved":true}` → `XCTAssertFalse(app.buttons["upgradeButton"].waitForExistence(timeout: 2))` (deterministic: no observation task ⇒ never resolves).
- Regression: `testUpgradePromptAppearsWhenGated` and `testActionClusterAppearsWhenEntitledAtCap` unchanged and green.
- `SingleThreadTests/EntitlementSyncTests.swift` — unchanged; `pushAllIncludesEntitledWhenFlagEnabled` still asserts `context["isEntitled"] == false` (watch payload contract preserved).

**Verify**: `make ui-test` (or `-only-testing:SingleThreadUITests/SingleThreadUITestsFlows`) + `make test` — new + existing freemium UI tests green, sync tests green.

---

## Testing Checkpoints

- **After Stage 1** — `EntitlementStoreTests` green: flag defaults `false`; seam sets `true`.
- **After Stage 2** — `EntitlementStoreTests` + `UITestingSeedTests` green: unresolved seam leaves both flags `false`; seed decodes/defaults `entitlementUnresolved`.
- **After Stage 3** — `SingleThreadUITestsFlows` freemium tests green (unresolved → no `upgradeButton`; gated/entitled unchanged) + `EntitlementSyncTests` green.
- **Full gate (once, parent)** — `./scripts/test.sh`.
- **Resume note**: each checkpoint is independently re-runnable via the named `-only-testing:` suite. Do not advance past a failing stage.

## Cross-cutting note

`hasResolvedEntitlement` and `isEntitled` are two booleans that must be kept in
sync — resolved is set at exactly the `isEntitled` assignment site (single method
today). A future edit adding an assignment site must set both; this invariant is
asserted indirectly by Stage 1's `seamSetsEntitlement` extension.
