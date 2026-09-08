# Structure Outline

## Approach

After every skip and watchOS completion, `ReminderStore` refetches from EventKit so completed reminders drop out of the list. Skip stays optimistic (instant `skippedIDs` filter) with a generation-gated background `reload()`; watch completion tracks the completed identifier in a persisted `pendingCompletions` set that `reload()` filters against until the phone processes the relay; and every `reload()` ends with a defensive `!isCompleted` filter. Built bottom-up: new persisted state → pure reconcile logic → `reload()` integration → skip refetch → watch completion insertion → UI tests.

---

## Stage 1: Persistence — `PendingCompletionStore`

The bottom-most layer: a new App-Group-backed `UserDefaults` wrapper for the pending-completion identifiers, mirroring `SkippedReminderStore`. Green tests prove the set round-trips, defaults empty, and `save` **replaces** (never unions) — the invariant every higher layer relies on.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/PendingCompletionStore.swift` (new)
**Key changes**:
- `public struct PendingCompletionStore` — new
  - `public init(defaults: UserDefaults = AppGroup.defaults, key: String = "pendingCompletionIdentifiers")`
  - `public func load() -> Set<String>`
  - `public func save(_ identifiers: Set<String>)`

**Tests**: `SingleThreadTests/PendingCompletionStoreTests.swift` (new)
- `loadDefaultsToEmptySet` (happy)
- `saveLoadRoundTrips` (happy)
- `saveReplacesPreviousValue` (sad: second `save` drops prior IDs — no union)
- `usesInjectedSuiteNotStandard` (sad: App-Group divergence guard, mirrors `AppGroupTests`)

**Verify**: `make test` (full unit gate) green; targeted `-only-testing:SingleThreadTests/PendingCompletionStoreTests` for iteration.

---

## Stage 2: Pure reconcile logic — `PendingCompletionLogic`

Pure, EventKit-free logic (like `ReminderSkipLogic`) that computes which fetched reminders to show and which pending IDs to prune. Tested in isolation before `reload()` consumes it.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/PendingCompletionLogic.swift` (new)
**Key changes**:
- `public nonisolated enum PendingCompletionLogic` — new
  - `public static func filtering(fetched: [EKReminder], pending: Set<String>) -> [EKReminder]` — drop reminders whose `calendarItemIdentifier ∈ pending`
  - `public static func pruned(pending: Set<String>, fetchedIdentifiers: Set<String>) -> Set<String>` — intersection; IDs absent from the fetch drop out
  - `public static func removingCompleted(_ reminders: [EKReminder]) -> [EKReminder]` — the defensive `!isCompleted` filter

**Tests**: `SingleThreadTests/PendingCompletionLogicTests.swift` (new), reminders built via `InMemoryEventStore.makeReminder`
- `filteringDropsPendingIdentifiers` / `filteringKeepsNonPending` (happy)
- `prunedKeepsOnlyFetchedIDs` / `prunedEmptiesWhenNothingFetched` (happy + sad)
- `removingCompletedDropsCompletedOnly` (happy; completed reminder still passes if unfiltered)

**Verify**: `make test` green; targeted `-only-testing:SingleThreadTests/PendingCompletionLogicTests`.

---

## Stage 3: `reload()` integration — filter, prune, defend

Wire Stages 1–2 into `ReminderStore.reload()` so the fetch path guarantees its invariants. `ReminderStore` gains a pending store and a pending set; `reload()` loads pending state, filters `shown`, prunes + re-saves, and applies the defensive filter. This is the shared foundation every trigger (skip refetch, watch completion, any existing reload site) builds on.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Key changes**:
- `ReminderStore.init(...)` — add `pendingCompletionStore: PendingCompletionStore = PendingCompletionStore()` (and optional `pendingCompletions: Set<String> = []` seed for tests)
- `private var pendingCompletions: Set<String>` — internal only; not surfaced to the UI (no `@Published`/computed additions)
- `public func reload(clearSkipped: Bool = false) async` — before `reminders = shown`, insert: load pending set → `shown = PendingCompletionLogic.filtering(fetched: shown, pending:)` → `shown = PendingCompletionLogic.removingCompleted(shown)`; after skip-prune, `pendingCompletions = PendingCompletionLogic.pruned(pending:fetchedIdentifiers:)` + `pendingCompletionStore.save(...)`. Post-condition: `reminders.allSatisfy { !$0.isCompleted }`.

**Tests**: `SingleThreadTests/ReminderStoreTests.swift` (extend; `loadsReminders: true` + `InMemoryEventStore`, plus a fake `EventKitStoring` that returns a completed reminder for the defensive filter)
- `reloadFiltersPendingCompletions` (happy: fetched id ∈ pending is hidden)
- `reloadPrunesStalePendingCompletions` (happy: pending id absent from fetch is dropped from set + persisted)
- `reloadKeepsPendingWhenStillFetched` (sad: still-incomplete pending id stays hidden, stays in set)
- `reloadDefensivelyDropsCompletedReminder` (sad: fake store returns a completed reminder; it never reaches `reminders`)

**Verify**: `make test` green; targeted `-only-testing:SingleThreadTests/ReminderStoreTests`.

---

## Stage 4: Skip refetch — background reconcile

Make `skipCurrentReminder()` refetch after applying the skip, so a cross-device completion falls out without a user-initiated reload. The deferred task already runs on the main actor with the `skipGeneration` gate; it now calls `await reload()` once the skip has applied. A clear that raced ahead discards the skip at `applySkipSet` (existing gate), so no stale refetch runs.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Key changes**:
- `public func skipCurrentReminder()` — inside the deferred `Task`, after `applySkipSet(updated, generation: capturedGeneration)` succeeds, `await reload()`. No settle sleep change; no `canMutate` change.

**Tests**: `SingleThreadTests/ReminderStoreTests.swift` (extend; `loadsReminders: true`)
- `skipCurrentReminderRefetchesAndDropsCompletedReminder` (happy: pre-complete reminder B in the store, skip A, wait > 200 ms settle, assert B gone and A ∈ `skippedIDs`)
- `skipCurrentReminderDiscardedAfterClearSkipped` (existing, extended to assert no stale refetch/skip re-applies after a clear) — sad path
- `skipCurrentReminderRefetchKeepsSkippedReminder` (sad: skipped-but-incomplete reminder stays fetched; only `skippedIDs` hides it)

**Verify**: `make test` green; targeted `-only-testing:SingleThreadTests/ReminderStoreTests`.

---

## Stage 5: Watch completion — pending-set insertion

On the watchOS branch of `completeReminder(identifier:)`, record the completed identifier in the persisted pending set before the fire-and-forget relay. Combined with Stage 3's `reload()` filtering, a watch pull-refresh/relaunch before the phone processes the relay can no longer resurrect the reminder (and can't double-increment the counter).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`, `scripts/test.sh`, `.github/workflows/ci.yml`
**Key changes**:
- `public func completeReminder(identifier: String) async -> Bool` — `#if os(watchOS)` branch: after `reminders.removeAll`, `pendingCompletions.insert(identifier)` + `pendingCompletionStore.save(pendingCompletions)`, then the existing `onCompleteReminder?(identifier)` relay.
- **CI coverage fix**: `SingleThreadWatchTests` already exists but is **not run by CI** (`ci.yml` only executes `SingleThreadWatchUITests`; `scripts/test.sh` likewise). Add `-only-testing:SingleThreadWatchTests` to the watch job and `scripts/test.sh` so this stage is guarded.

**Tests**: `SingleThreadWatchTests/ReminderStoreWatchTests.swift` (new; watchOS unit target, watch branch is live there)
- `completeReminderInsertsAndPersistsPendingCompletion` (happy: `PendingCompletionStore.load()` contains the id after completion)
- `reloadHidesPendingCompletion` (happy: `loadsReminders: true` + `InMemoryEventStore`; pending id is filtered from `reminders`)
- `completeReminderNoOpWhenIdentifierMissing` (sad: no insert when nothing removed)

**Verify**: `make watch-test` (`-only-testing:SingleThreadWatchTests`) green; `make test` still green (Core package compiles for iOS unchanged); CI watch job now executes `SingleThreadWatchTests`.

---

## Stage 6: UI/E2E regression guard

End-to-end confirmation that the user-visible flows hold: a skip plus a cross-device completion converges on the correct list. iOS uses the `--seed` seam (`loadsReminders: true`, real save → settle → reload round-trip). Watch completion is covered by Stage 5's watch unit tests — the watch UI seam (`--ui-testing`) uses `loadsReminders: false`, which no-ops `reload()`, so a watch UI test would require a new `--seed`-style seam; flagged as out of scope (see note below).

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Key changes**:
- New XCTest `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder`: `--seed` two reminders, pre-complete one in the seed data, skip the other, assert only the non-completed, non-skipped reminder is visible (and no resurrected completed card).

**Tests**: the new UI test above; existing `testSkipAdvancesToNextReminder`, `testCompleteViaSwipeRemovesReminder`, `testUndo...` must stay green.
**Verify**: `make ui-test` (`-only-testing:SingleThreadUITests`) green; final full gate `./scripts/test.sh`.

---

## Testing Checkpoints

Resume points if context resets — each stage's gate must be green before the next stage starts:

1. **Stage 1** — `make test` green with `PendingCompletionStoreTests` passing.
2. **Stage 2** — `make test` green with `PendingCompletionLogicTests` passing.
3. **Stage 3** — `make test` green with new `ReminderStoreTests.reload*` cases passing; invariant `reminders` has zero completed after `reload()`.
4. **Stage 4** — `make test` green with `skipCurrentReminderRefetches*` passing; existing skip-generation discard test still green.
5. **Stage 5** — `make watch-test` green with `ReminderStoreWatchTests` passing; `make test` unaffected.
6. **Stage 6** — `make ui-test` green with the new seed-driven UI test; final `./scripts/test.sh` green end-to-end.

## Cross-Cutting Notes

- **No transport/API layer** — the design explicitly does **not** change the WatchConnectivity protocol (`SkippedReminderSyncService` messages, acks, or dedupe), so there is no transport stage. The watch relay stays fire-and-forget; correctness comes from the pending set (Stages 1–5).
- **Watch E2E is unit-tested, not UI-tested**: the watch UI seam (`--ui-testing`, `loadsReminders: false`) cannot exercise `reload()`, so the "watch pull-refresh doesn't resurrect the completed reminder" verification lives in `SingleThreadWatchTests` (Stage 5). Adding a watch `--seed` seam to UI-test it would be a separate, larger change — call it out in the PR rather than silently skipping.
- **No schema/migration layer** — persistence is App-Group `UserDefaults`, not SQL; Stage 1 is the closest analog (new persisted key + accessor).
