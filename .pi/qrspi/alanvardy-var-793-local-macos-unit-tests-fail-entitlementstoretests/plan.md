# Implementation Plan

## Overview

Fix two macOS-local `EntitlementStoreTests` failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`) by introducing a process-lifetime shared `SKTestSession` with upfront `clearTransactions()`, replacing flaky fixed-duration sleeps with a bounded-poll helper, and adding a host-dirt canary that diagnoses stale StoreKit state before tests run. The fix is horizontal: each layer is independently verified against `make mac-test` before the next begins.

---

## Phase 1: Bounded-Poll Helper

Replace the two different async-wait primitives in the test suite with a single deterministic polling helper. Pure refactor on the non-StoreKit path — eliminates a known flake source independent of any StoreKit isolation fix.

### Changes

#### 1. Add `wait(for:timeout:)` helper
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — add private method to `EntitlementStoreTests` struct

Insert after `// SKTestSession for driving StoreKit in test.` (line 10) and before `isEntitledIsFalseByDefault` (line 12):

```swift
    /// Polls `condition` every 50 ms until it returns `true` or `timeout`
    /// nanoseconds elapse. Returns `true` if the condition was met, `false` on
    /// timeout.
    private func wait(
        for condition: @autoclosure @escaping () -> Bool,
        timeout nanoseconds: UInt64 = 2_000_000_000
    ) async -> Bool {
        var waited: UInt64 = 0
        while !condition(), waited < nanoseconds {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 50_000_000
        }
        return condition()
    }
```

#### 2. Replace inline poll in `initialRefreshSettlesResolvedFlag`
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — lines 82–85

Replace:
```swift
        var waited: UInt64 = 0
        while !store.hasResolvedEntitlement, waited < 2_000_000_000 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 50_000_000
        }
```

With:
```swift
        _ = await wait(for: store.hasResolvedEntitlement)
```

#### 3. Replace fixed sleep in `isEntitledSurvivesStoreRecreation`
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — line 57

Replace:
```swift
        try await Task.sleep(nanoseconds: 200_000_000)
```

With:
```swift
        _ = await wait(for: second.hasResolvedEntitlement)
```

### Verification

#### Automated
- [x] `make mac-test` — 5 non-StoreKit tests pass; 2 StoreKit tests (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`) fail identically to pre-stage (no regression)
- [x] `make lint` passes (new helper uses `try?` — no new warnings)

#### Manual
- [ ] Confirm the two failing tests still fail with `!isEntitled == false` (not a different assertion or a timeout)

---

## Phase 2: Shared SKTestSession + clearTransactions

Introduce a single process-lifetime `SKTestSession`, created once and shared by all three StoreKit-touching tests. Clear its transaction store immediately after creation, before any `EntitlementStore()` read. This is the core isolation fix.

### Changes

#### 1. Add static shared session
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — add static property to `EntitlementStoreTests` struct

Insert after the `wait(for:timeout:)` helper and before `isEntitledIsFalseByDefault`:

```swift
    private static let testSession: SKTestSession = {
        let session = try! SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }()
```

Design note: `try!` is acceptable here — session creation with a bundled config that has worked for years is a precondition failure, not a recoverable error. The test suite cannot proceed without it.

####2. Remove per-test session locals from three tests
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify

In `isEntitledSurvivesStoreRecreation` (lines 43–44), remove:
```swift
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
```

In `nonMatchingProductIDDoesNotSetEntitlement` (lines 63–64), remove:
```swift
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
```

In `initialRefreshSettlesResolvedFlag` (lines 77–78), remove:
```swift
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
```

No other changes to these tests — the shared `Self.testSession` is active process-wide by the time any test runs (accessed lazily on first touch), so `Transaction.currentEntitlements` in fresh real `EntitlementStore()` inits resolve against it.

####3. Remove unused `throws` from two test signatures
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify

`isEntitledSurvivesStoreRecreation` — the `try SKTestSession(…)` was the only throwing call. After removal, change:
```swift
    func isEntitledSurvivesStoreRecreation() async throws {
```
to:
```swift
    func isEntitledSurvivesStoreRecreation() async {
```

`nonMatchingProductIDDoesNotSetEntitlement` — same. Change:
```swift
    func nonMatchingProductIDDoesNotSetEntitlement() throws {
```
to:
```swift
    func nonMatchingProductIDDoesNotSetEntitlement() {
```

`initialRefreshSettlesResolvedFlag` — same. Change:
```swift
    func initialRefreshSettlesResolvedFlag() async throws {
```
to:
```swift
    func initialRefreshSettlesResolvedFlag() async {
```

### Verification

#### Automated
- [ ] `make mac-test` — **all 7 `EntitlementStoreTests` pass in the full suite**, not isolated. Gate requirement: full-suite pass. If `clearTransactions()` holds, proceed to Phase 3. If the host leak re-appears in the full suite, skip Phase 3 and escalate to Phase 4.
- [ ] `make lint` passes

#### Manual
- [ ] Verify that `isEntitledIsFalseByDefault` and `hasResolvedEntitlementIsFalseByDefault` (which never created sessions before) now also see an empty store and pass
- [ ] Verify no `SKServiceErrorDomain Code=2` or config-saving errors in xcodebuild output (these appeared on this host previously; the shared session may still trigger them but they should be non-fatal)

---

## Phase 3: Host-Dirt Canary

Add a guard `@Test` that snapshots `Transaction.currentEntitlements` before the shared session is created. If the snapshot is non-empty, the test fails with an actionable one-line message directing the developer to reset via Xcode Debug → StoreKit → Manage Transactions.

### Changes

####1. Add pre-session host snapshot
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — add static property before `testSession`

Insert before the `testSession` static property (Swift initializes stored properties in declaration order, so this snapshot is taken before `testSession` creates and clears):

```swift
    /// Snapshot of `Transaction.currentEntitlements` taken **before** the shared
    /// `SKTestSession` is created, so it reflects the real host StoreKit store
    /// rather than the test-session-scoped store.
    private static let hostEntitlementSnapshot: Set<String> = {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        return ids
    }()
```

Note: the `for await` loop over `Transaction.currentEntitlements` (an `AsyncSequence`) must run in an async context. Since this is a static stored property initializer (non-async), we need a different approach. Two options:

**Option A** (simpler, recommended): Use a synchronous `AsyncSequence` consumption pattern via `Task` blocking:
```swift
    private static let hostEntitlementSnapshot: Set<String> = {
        let semaphore = DispatchSemaphore(value: 0)
        var ids = Set<String>()
        Task {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    ids.insert(transaction.productID)
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        return ids
    }()
```

**Option B**: Make the snapshot a lazy `async` property and `await` it in the canary test. But then `testSession` (declared after) might initialize first if another test touches it.

Go with **Option A** — it's a test-only static initializer, and `DispatchSemaphore` is fine for one-shot initialization. The `Task` inherits `@MainActor` from the suite, but `Transaction.currentEntitlements` is not actor-isolated and the semaphore wait on the main actor would deadlock. Instead, use a detached task:

```swift
    private static let hostEntitlementSnapshot: Set<String> = {
        let semaphore = DispatchSemaphore(value: 0)
        var ids = Set<String>()
        Task.detached {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    ids.insert(transaction.productID)
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        return ids
    }()
```

This runs on a background cooperative thread; `Transaction.currentEntitlements` iterates synchronously on an empty store and signals quickly.

####2. Add canary test
**File**: `SingleThreadTests/EntitlementStoreTests.swift`
**Action**: modify — add new test

Insert after the static properties and before `isEntitledIsFalseByDefault`:

```swift
    /// Fails with an actionable reset message when the host StoreKit sandbox
    /// holds entitled transactions from prior manual testing.
    @Test
    func hostStoreKitIsClean() {
        let ids = Self.hostEntitlementSnapshot
        #expect(
            ids.is Empty,
            "Host StoreKit sandbox has entitled transactions: \(ids.sorted()). " +
                "Reset via Xcode Debug → StoreKit → Manage Transactions…"
        )
    }
```

### Verification

#### Automated
- [ ] `make mac-test` — canary passes when host is clean; produces actionable failure with transaction IDs when host is dirty. Existing 7 tests continue to pass.
- [ ] `make lint` passes (`DispatchSemaphore` is fine — no `async`/`await` in the static init)

#### Manual
- [ ] On a dirty host: confirm the canary failure message lists the specific product IDs and the Xcode reset instruction
- [ ] On a clean host (or after reset): confirm canary passes

---

## Phase 4 (Conditional): Host StoreKit Reset Script

**Trigger**: Only if Phase 2's `clearTransactions()` fails to hold in the full suite — i.e. `make mac-test` still shows the two StoreKit tests failing after the shared-session change.

### Changes

#### 1. Create reset script
**File**: `scripts/reset-storekit.sh` (new)
**Action**: create

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "==> Stopping storekitd…"
launchctl stop com.apple.storekitd 2>/dev/null || true

# The host DB lives in one of two known locations. Try the per-user daemon DB
# first (observed on this machine), then the Octane layout.
DB_PATH=""
for candidate in \
    "$HOME/Library/Application Support/App Store/StoreKit.db" \
    "$HOME/Library/Caches/com.apple.storekitagent/Octane" \
    "$HOME/Library/Caches/com.apple.appstoreagent/Octane"; do
    if [ -f "$candidate" ] || [ -d "$candidate" ]; then
        DB_PATH="$candidate"
        break
    fi
done

if [ -z "$DB_PATH" ]; then
    echo "==> No StoreKit transaction store found at known paths. The host may already be clean."
    echo "    Checked:"
    echo "      ~/Library/Application Support/App Store/StoreKit.db"
    echo "      ~/Library/Caches/com.apple.storekitagent/Octane/"
    echo "      ~/Library/Caches/com.apple.appstoreagent/Octane/"
    exit 0
fi

echo "==> Found StoreKit store at: $DB_PATH"

if [ -f "$DB_PATH" ] && [[ "$DB_PATH" == *.db ]]; then
    # SQLite DB — drop transactions for the app's bundle ID.
    if command -v sqlite3 &>/dev/null; then
        echo "==> Clearing transactions for app.alanvardy.SingleThread…"
        sqlite3 "$DB_PATH" "DELETE FROM octane_transaction WHERE bundle_id = 'app.alanvardy.SingleThread';" 2>/dev/null || \
            echo "    (table may not exist or DB schema differs — this is non-fatal)"
    else
        echo "==> sqlite3 not found; truncating DB file…"
        :> "$DB_PATH"
    fi
elif [ -d "$DB_PATH" ]; then
    # Octane directory layout — find store.db files and truncate.
    find "$DB_PATH" -name "store.db" -type f | while read -r f; do
        echo "==> Found: $f"
        if command -v sqlite3 &>/dev/null; then
            sqlite3 "$f" "DELETE FROM octane_transaction WHERE bundle_id = 'app.alanvardy.SingleThread';" 2>/dev/null || true
        else
            :> "$f"
        fi
    done
fi

echo "==> Restarting storekitd…"
launchctl kickstart -k system/com.apple.storekitd 2>/dev/null || true

echo "==> Done. Run 'make mac-test' to verify."
```

#### 2. Add Makefile target
**File**: `Makefile`
**Action**: modify — add `reset-storekit` to `.PHONY` and add target

In the `.PHONY` line (currently `~:13`), append `reset-storekit`:
```
.PHONY: build watch-build test ui-test simverify mac-build mac-test mac-run mac-distribute coverage coverage-ui coverage-all check clean lint format periphery watch-ui-test watch-test reset-storekit
```

Add new target after `mac-distribute` (line ~31):
```makefile
reset-storekit:
	bash scripts/reset-storekit.sh
```

####3. Document the reset command
**File**: `.pi/skills/storekit/SKILL.md`
**Action**: modify — add after the existing list items

Add before the final line:
```markdown
- **Local host reset**: `make reset-storekit` stops `storekitd`, clears the
  local sandbox transaction store for `app.alanvardy.SingleThread`, and
  restarts the daemon. Use when `make mac-test` fails with
  `isEntitled == true` on a development Mac that has completed purchases
  (see `EntitlementStoreTests.hostStoreKitIsClean` for the canary guard).
```

### Verification

#### Automated
- [ ] `make lint` passes (no Swift changes)

#### Manual
- [ ] `make reset-storekit` runs without errors, finds and clears the store
- [ ] `make mac-test` — 7/7 `EntitlementStoreTests` pass on the previously-dirty host
- [ ] The canary (`hostStoreKitIsClean`) also passes after reset

---

## Final Gate

- [ ] `./scripts/test.sh` — full CI-identical pipeline passes locally (includes macOS unit tests last)
- [ ] `make lint` passes
- [ ] All changes committed on the ticket branch