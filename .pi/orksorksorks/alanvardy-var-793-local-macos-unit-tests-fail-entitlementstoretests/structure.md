# Structure Outline

## Approach

Fix two macOS-local `EntitlementStoreTests` failures by introducing a process-lifetime shared `SKTestSession` with upfront `clearTransactions()`, replacing flaky fixed-duration sleeps with a bounded-poll helper, and adding a host-dirt canary that diagnoses stale StoreKit state before tests run. The fix is horizontal: each layer is independently verified against the macOS unit suite (`make mac-test`) before the next begins.

---

## Stage 1: Bounded-Poll Helper

Replace the two different async-wait primitives in the test suite with a single deterministic polling helper. This is the safest bottom layer — a pure refactor on the non-StoreKit path that eliminates a known flake source (fixed `Task.sleep(200ms)`) independent of any StoreKit isolation fix.

**What this layer delivers**: A private helper that polls a condition at 50 ms intervals up to a 2 s ceiling, replacing both the existing polling loop in `initialRefreshSettlesResolvedFlag` and the fixed 200 ms sleep in `isEntitledSurvivesStoreRecreation`. The two tests that await the async refresh now share one deterministic wait primitive.

**Files**: `SingleThreadTests/EntitlementStoreTests.swift`

**Key changes**:
- `private func wait(for condition: @autoclosure @escaping () -> Bool, timeout nanoseconds: UInt64 = 2_000_000_000) async -> Bool` — new helper; polls `condition()` every 50 ms up to timeout; returns `true` if condition met, `false` on timeout.
- In `initialRefreshSettlesResolvedFlag` (`:82-85`): replace inline `while !store.hasResolvedEntitlement` / 50 ms sleep loop with `await wait(for: store.hasResolvedEntitlement)`.
- In `isEntitledSurvivesStoreRecreation` (`:57`): replace `try await Task.sleep(for: .milliseconds(200))` with `_ = await wait(for: second.hasResolvedEntitlement)` (poll for settlement, then read `!second.isEntitled`).

**Tests**: All 7 existing tests (5 non-StoreKit + 2 StoreKit). On CI (clean host): all pass. On dirty local host: the 5 non-StoreKit tests pass; the 2 StoreKit tests still fail with the same `!isEntitled == false` assertion (no regression).

**Verify**: `make mac-test` — 5 tests green, 2 tests fail identically to pre-stage (no new failures); CI stays green.

---

## Stage 2: Shared SKTestSession + clearTransactions

Introduce a single process-lifetime `SKTestSession`, created once and shared by all three StoreKit-touching tests. Clear its transaction store immediately after creation, before any `EntitlementStore()` read. This is the core isolation fix — the hypothesis is that a long-lived session with upfront clearing prevents the per-test create/destroy cycle from re-seeding the host leak (`var-789/plan.md:297`).

**What this layer delivers**: A static session at the suite level that all StoreKit tests use instead of per-test locals. `clearTransactions()` runs once, at session creation, guaranteeing the init-time `Transaction.currentEntitlements` read sees an empty store.

**Files**: `SingleThreadTests/EntitlementStoreTests.swift`

**Key changes**:
- `private static let testSession: SKTestSession = { … }()` — new static property, lazy-initialized on first access. Body: `let s = try! SKTestSession(configurationFileNamed: "Products")`; `s.disableDialogs = true`; `s.clearTransactions()`; `return s`.
- `isEntitledSurvivesStoreRecreation` (`:43-44`): remove `let session = …` + `session.disableDialogs = true`; use `Self.testSession` implicitly (no local binding needed — `Transaction.currentEntitlements` resolves against the active session).
- `nonMatchingProductIDDoesNotSetEntitlement` (`:63-64`): same.
- `initialRefreshSettlesResolvedFlag` (`:77-78`): same.
- `isEntitledIsFalseByDefault` and `hasResolvedEntitlementIsFalseByDefault` no longer read stale host state — the shared session ensures their fresh real `EntitlementStore()` init refresh sees an empty store.

**Tests**: All 7 tests. The two previously-failing tests now pass locally (`!isEntitled` assertion holds). The 5 non-StoreKit tests continue to pass. No test assertions are weakened.

**Verify**: `make mac-test` — all 7 `EntitlementStoreTests` pass on the dirty local host. **Gate requirement**: full-suite pass, not isolated pass. If `clearTransactions()` holds in the full suite, proceed to Stage 3. If the host leak re-appears in the full suite, skip Stage 3 and escalate to Stage 4 (fallback).

**Risk**: `var-789` only observed isolated passes; the full-suite re-leak mechanism is unproven. This stage is the empirical gate.

---

## Stage 3: Host-Dirt Canary

Add a guard `@Test` that snapshots `Transaction.currentEntitlements` before the shared session redirects process-wide reads. If the snapshot is non-empty, the test fails with an actionable one-line message directing the developer to reset via Xcode Debug → StoreKit → Manage Transactions. This turns the next dirty-host recurrence into a single clear instruction instead of two opaque assertion failures.

**What this layer delivers**: A diagnostic test that catches stale host StoreKit state, failing loudly with a reset instruction before any StoreKit-dependent test runs.

**Files**: `SingleThreadTests/EntitlementStoreTests.swift`

**Key changes**:
- `@Test func hostStoreKitIsClean() async` — new test. Reads `Transaction.currentEntitlements` and iterates to collect product IDs of `.verified` transactions. Asserts empty with message: `"Host StoreKit sandbox has entitled transactions: <ids>. Reset via Xcode Debug → StoreKit → Manage Transactions…"`.
- Placement constraint: the canary must snapshot host state **before** `Self.testSession` is first accessed (lazy static). Swift Testing offers no cross-test ordering, so the canary test explicitly forces the snapshot before touching the session. Exact mechanism (static `let` pre-snapshot in a separate type, or a `static let` snapshot guard lazily resolved before `testSession`) is finalized during implementation.

**Tests**: The canary itself + all 7 existing tests. On a clean host (or after session clears), the canary passes (empty snapshot). On a dirty host where the leak survived Stage 2, the canary fails with the actionable message.

**Verify**: `make mac-test` — canary passes when host is clean; produces actionable failure when host is dirty. Existing 7 tests continue to pass.

---

## Stage 4 (Conditional): Host StoreKit Reset Script

Fallback triggered only if Stage 2's `clearTransactions()` fails to hold in the full suite. Provides a one-command host reset that clears the persistent StoreKit sandbox transaction store, making local test runs deterministic without further code changes.

**What this layer delivers**: A `make reset-storekit` target that stops `storekitd`, deletes/truncates the host transaction database, and verifies emptiness so `make mac-test` passes on the next run.

**Files**: `Makefile`, `scripts/reset-storekit.sh` (new)

**Key changes**:
- `scripts/reset-storekit.sh` — new script. Steps: (1) launchctl stop `com.apple.storekitd`, (2) identify the correct DB path — verify empirically between `~/Library/Caches/com.apple.storekitagent/Octane/` (Octane layout) and `~/Library/Application Support/App Store/StoreKit.db` (per-user daemon DB observed on this host per research Q5), (3) truncate/delete transactions for the app's bundle ID, (4) print confirmation. Path discovery is done during implementation; script errors on ambiguity rather than guessing.
- `Makefile`: `reset-storekit:` phony target → `bash scripts/reset-storekit.sh`.
- `AGENTS.md` / `.pi/skills/storekit/SKILL.md`: document the command as the canonical local reset procedure.

**Tests**: Manual verification — run `make reset-storekit`, then `make mac-test` — all `EntitlementStoreTests` pass. CI unchanged (does not invoke this target).

**Verify**: `make reset-storekit && make mac-test` — 7/7 pass on the dirty host. The canary (Stage 3) also passes after reset.

> **Superseded (var-793 final)**: the shipped `scripts/reset-storekit.sh` differs
> from this outline — it clears the per-user Group Containers store
> (`~/Library/Group Containers/group.com.apple.storekit/Library/Caches/storeUser.db`)
> and kills the `storekitagent` lock-holder by PID (`lsof`), not `storekitd`/Octane.
> The reset is necessary-not-sufficient on a purchased account (see implement.md).

---

## Testing Checkpoints

| After Stage | What Must Be Green |
|---|---|
| 1 | `make mac-test` — 5 non-StoreKit tests pass; 2 StoreKit tests fail identically to pre-stage (no regression) |
| 2 | `make mac-test` — all 7 `EntitlementStoreTests` pass in the **full suite**, not isolated |
| 3 | `make mac-test` — canary passes on clean host, fails with actionable message on dirty host; 7 existing tests pass |
| 4 (if needed) | `make reset-storekit && make mac-test` — 7/7 pass on previously-dirty host |