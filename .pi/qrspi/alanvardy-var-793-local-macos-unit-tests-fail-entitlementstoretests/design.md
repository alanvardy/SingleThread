# Design Discussion

## Current State

`EntitlementStore` (`SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`) is
`@MainActor @Observable` (`:11-12`). Its `init()` (`:18-23`) spawns a main-actor task that runs
`refreshEntitlement()` (`:20`) then `observeTransactionUpdates()` (`:21`). `refreshEntitlement()`
(`:102-113`) iterates `Transaction.currentEntitlements` (`:104`), flags an entitled transaction
with `productID == Self.unlockProductID` (`:49-51`, `app.alanvardy.SingleThread.unlimited`), then
writes `isEntitled` and `hasResolvedEntitlement = true` unconditionally (`:111-112`) — the resolved
flag settles even on an empty account.

`isEntitled` is in-memory only (`:58`, `:111-112`); it is never cached to UserDefaults, keychain, or
files (research Q3; `var-754/research.md:56`). The single persistent artifact is the OS-managed
StoreKit transaction store — which is exactly what is dirty on this dev machine.

`SingleThreadTests/EntitlementStoreTests.swift` (89 lines) is `@MainActor @Suite(.serialized)` with
7 tests. Three create **per-test local** sessions — `SKTestSession(configurationFileNamed: "Products")`
+ `disableDialogs = true` (`:43-44, :63-64, :77-78`) — that live by scope exit and are never
`end()`-ed or `clearTransactions()`-ed. The two failing tests both create a session yet still read
host state through a fresh real `EntitlementStore()`:

- `isEntitledSurvivesStoreRecreation` (`:41-59`): fixed 200 ms sleep, then `#expect(!second.isEntitled)`.
- `initialRefreshSettlesResolvedFlag` (`:72-88`): 50 ms poll ≤ 2 s, then
  `#expect(store.hasResolvedEntitlement)` + `#expect(!store.isEntitled)`.

Root cause: the local host's StoreKit store still holds an entitled transaction from earlier manual
Mac testing, and `Transaction.currentEntitlements` leaks it into the init-time refresh. CI `mac-tests`
is green because runners are fresh (`ci.yml:270-320`); the local stage (`scripts/test.sh:286-292`)
runs unsigned (`CODE_SIGNING_ALLOWED=NO`). This is the sixth recurrence (var-781/789/792/794/796);
`var-789/plan.md:297` recorded that an in-test `clearTransactions()` made the two tests pass **in
isolation** but "the full suite re-creates the leak", and `var-642/implement.md:35` recorded
`AppStore.sync()` hanging in-suite after earlier sessions wedge storekitd.

## Desired End State

- The macOS unit stage of `./scripts/test.sh` passes deterministically **even on a dirty host**,
  without weakening real StoreKit coverage.
- The two tests keep their strict assertions: a fresh real `EntitlementStore()` on an effectively
  empty account stays `!isEntitled`, and the init refresh settles `hasResolvedEntitlement`.
- A host-dirt canary fails loudly with a one-line reset instruction, instead of two opaque StoreKit
  failures.
- CI behavior is unchanged (still green; no new flake sources introduced).

## Patterns to Follow

- **Keep `@Suite(.serialized)`** for StoreKit-touching suites — established convention
  (research Q5; `var-755/research.md:105`; `conventions.md` "one SKTestSession per process").
- **Seams for deterministic positives**: `testingWithEntitled:` / `testingWithEntitlementUnresolved:`
  (`EntitlementStore.swift:32, :39-41`) stay the mechanism for the positive-case tests
  (`seamSetsEntitlement`, `unresolvedSeamLeavesFlagsFalse`) — untouched.
- **Bounded polling over fixed sleeps** for async settlement — already used at
  `EntitlementStoreTests.swift:82-85`; extend it to the other async test (decision H1).
- **Per-test state cleanup** convention exists (`defer { removeObject }`, research Q6) but covers
  *only* UserDefaults — **no StoreKit-state reset exists anywhere** (research Q6 bottom line). This
  ticket introduces the first StoreKit test-state convention.
- **NOT to follow** — per-test throwaway sessions relying on deallocation for isolation: that is the
  anti-pattern that re-seeds the leak (`var-789/plan.md:297`, `var-642/implement.md:35`).
- **NOT to follow** — fixed-duration `Task.sleep` as a synchronization primitive (flaky on slow hosts).
- **NOT to follow** — in-suite `AppStore.sync()` (wedges storekitd; `var-642/implement.md:35`).

## Design Decisions

1. **Shared, process-lifetime session** — one `SKTestSession` created once and held by the `@MainActor`
   suite (static/file-scoped), reused by all three StoreKit tests, replacing the three per-test locals.
   Why: `var-789/plan.md:297` shows repeated session create/destroy cycles re-seed the host leak; a
   single long-lived session is the minimal change that tests the "deallocation restores host state"
   hypothesis head-on.

2. **`clearTransactions()` immediately after creation** — clear before any real `EntitlementStore()`
   reads, alongside `disableDialogs = true`. Why: the only positive observation we have is that
   clearing empties whatever the reads consult (`var-789/plan.md:297`, isolated pass). Clearing first
   guarantees the init refresh sees an empty store.

3. **Host-dirt canary (G1)** — a guard `@Test` that snapshots `Transaction.currentEntitlements` and
   fails with an actionable message (`"reset via Xcode Debug → StoreKit → Manage Transactions…"`) when
   non-empty. It turns the next dirty-host recurrence into one clear instruction instead of two cryptic
   failures. The snapshot must be taken **before** the shared session redirects process-wide reads;
   exact placement (suite `init` vs first-touch) is finalized during implementation, since Swift
   Testing offers no cross-suite ordering.

4. **Bounded-poll helper (H1)** — extract the 50 ms / ≤ 2 s poll from
   `initialRefreshSettlesResolvedFlag` (`:82-85`) into a local helper and replace the 200 ms
   `Task.sleep` in `isEntitledSurvivesStoreRecreation` (`:57`). Both strict asserts stay.

5. **Empirical gate-first** — implementation phase 1 is a build plus the full local macOS suite
   (`make mac-test`, `Makefile:26-27`), proving shared-session+clear holds across the **whole** suite,
   not just isolated tests. `var-789` only ever observed the isolated pass; nothing is "done" until
   the full suite is green on this machine.

6. **Fallback trigger** — if decision 2 fails to hold in the full suite (host leak survives clearing),
   escalate to the hybrid reset deferred in this phase: a `make reset-storekit` script that stops
   `storekitd`, deletes the local sandbox transaction store (path verified empirically on this host),
   and re-verifies empty — while keeping the canary and never relaxing the asserts.

## What We're NOT Doing

- NOT weakening or removing `!isEntitled` / `!second.isEntitled` — real StoreKit refresh coverage is
  the point of the ticket.
- NOT switching the two tests onto the `testingWithEntitled:` seam (seams remain for positive cases only).
- NOT changing assertions in the 4 non-StoreKit tests or `nonMatchingProductIDDoesNotSetEntitlement`.
- NOT adding `AppStore.sync()` or `buyProduct` to tests (`var-642/implement.md:35`; test comment
  `EntitlementStoreTests.swift:47-49`).
- NOT changing code signing or entitlements (no `com.apple.developer.in-app-purchases` exists
  repo-wide; signing is out of scope for a test-isolation fix).
- NOT (yet) shipping the host reset script — deferred unless decision 6 is triggered.
- NOT introducing xctestplan/scheme PreActions (none exist; `xcscheme:39-69`).
- NOT touching `UITestingSeed`/UserDefaults resets — orthogonal; those cover only the two defaults
  containers (research Q6), never StoreKit.

## Open Risks

- **Shared-session hypothesis unproven in the full suite** — `var-789:297` observed only isolated
  passes; the full-suite re-leak mechanism (session deallocation vs re-seed) is unanswerable from the
  repo (research Q2). Phase-1 experiment resolves; fallback = decision 6.
- **Canary masking** — if the shared session redirects process-wide reads, the guard snapshot may see
  the emptied session store rather than the host store, forcing the snapshot to move before session
  creation (suite `init`). If masking proves unavoidable, the canary still catches the real failure
  case (reads staying host-bound when isolation fails), which is its primary value.
- **`clearTransactions()` scope** — Apple documents it as clearing "the test environment"; the repo
  cannot confirm it clears the store the unsigned local build reads (`var-796/implement.md:46`,
  session "doesn't reach storekitd"). The isolated-pass record is encouraging, not proof.
- **Fallback path fragility** — the file-reset paths (Octane `store.db` vs `StoreKit.db`) are
  unverified on this machine (research Open Areas); reaching decision 6 means a path-discovery step first.
- **Test ordering** — Swift Testing guarantees no cross-test order; canary placement must not assume one.