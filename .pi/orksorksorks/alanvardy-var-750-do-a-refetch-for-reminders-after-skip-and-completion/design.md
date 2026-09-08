# Design Discussion

## Current State

SingleThread reads Apple Reminders through EventKit and exposes them through a
`@MainActor @Observable ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`).
The store's `reminders` array is populated by `reload()`, which fetches
incomplete reminders via `predicateForIncompleteReminders` and prunes stale
skip IDs through `ReminderSkipLogic.resolve` (`:363-374`).

**Completion** on iOS saves to EventKit, waits 200 ms, then reloads — the
refetched list naturally drops the completed reminder (`:185-190`). On watchOS,
completion removes the reminder from the in-memory array (`:173`) and relays a
fire-and-forget `sendMessage` to the phone (`SkippedReminderSyncService.swift:210-217`,
`replyHandler: nil`). There is **no post-relay refetch** — the watch list is at
the mercy of the next explicit reload. If that reload arrives before the phone
processes the relay, the still-incomplete reminder re-appears and can be
completed again, producing a double `completionCounter.increment()` on the phone.

**Skipping** is purely an in-memory `skippedIDs` filter (`:286-296`). It never
refetches. A reminder completed on another device stays in the list
indefinitely (filtered out of `visibleReminders` but still present in
`reminders`); it only drops on the next reload from a different trigger
(pull-refresh, show-undated toggle, relaunch, or a subsequent mutation).

**No EventKit change observation** exists anywhere in the codebase. Every
refetch is an explicit `reload()` call site. The App Group `UserDefaults` is
the cross-process source of truth for skip IDs, preferences, and the
completion counter.

**Tests** for skip use `loadsReminders: false` (no-op `reload()`) except for
one clear-skipped test (`ReminderStoreTests.swift:326`). No existing test
covers a cross-device completion arriving between a skip and a refetch.

## Desired End State

After every **skip** and **watchOS completion**, the store refetches from
EventKit and drops any reminders that are now completed. The UI responds
instantly (optimistic) but eventually converges with the store.

Verification:
1. **Skip + cross-device completion**: Skip a reminder on device A. Device B
   completes that reminder. Device A's next explicit reload (from any trigger)
   shows it gone. The skip's background refetch also catches it.
2. **Watch complete + phone lag**: Watch completes a reminder, relays it.
   Before phone processes the relay, watch pull-refreshes. The reminder does
   NOT re-appear.
3. **Defensive filter invariant**: After every `reload()`, `reminders` contains
   zero completed reminders (`reminders.allSatisfy { !$0.isCompleted }`), even
   if the predicate returned something unexpected.
4. **Existing behavior preserved**: iOS completion/undo/delete/add flow
   unchanged. Skip UX remains instant (no added latency). Watch completion UX
   remains instant. Undo still works.

## Patterns to Follow

- **`ResumptionGate` + `withCheckedContinuation`** for EventKit bridging
  (`ReminderStore.swift:465-475`, `ResumptionGate.swift:19-50`). No new
  continuation patterns needed — the existing `reload()` handles fetching.
- **`skipGeneration` gate pattern** (`ReminderStore.swift:429-455`) — if a
  deferred operation needs to be discarded after a superseding state change,
  capture and compare generations. The background-skip-refetch should capture
  the generation and discard its result if a clear happened in between.
- **`canMutate` gate** (`:132-134`) — already guards all mutation entry points.
  No changes needed.
- **App Group `UserDefaults` for cross-process state** (`AppGroup.swift:5-16`).
  The pending-completion set for watchOS should persist in `AppGroup.defaults`
  so it survives process termination.
- **200 ms settle before EventKit refetch** (`ReminderStore.swift:416-419`) —
  applies only to EventKit writes. Skip doesn't write to EventKit, so no settle
  needed. The background refetch after skip is fire-and-forget, no settle delay.
- **`@MainActor @Observable` store** — all new state and mutations stay on the
  main actor. No `nonisolated` additions needed.
- **`InMemoryEventStore` for unit tests** (`InMemoryEventStore.swift:60` filters
  completed from fetches). New tests with `loadsReminders: true` exercise the
  full save → refetch round-trip against this store.
- **`--seed` launch-arg seam for UI tests** (`UITestingSeed.swift:31-52`,
  `AppViewModel.swift:272-303`) — the standard way to drive deterministic
  write-path UI tests. Use for new cross-device-completion scenarios.

### Patterns to AVOID

- **Don't add EventKit change observation** (`EKEventStoreChanged`) — the
  codebase intentionally drives all refetches explicitly. Adding notification
  observers would introduce a parallel refresh path with different timing
  guarantees. Stick with explicit call sites.
- **Don't add timers or interval-based refresh** — no precedent, adds complexity
  and battery cost. Widget's 15-min timeline policy is the only interval.
- **Don't change the settle delay or remove it** — it's load-bearing for
  real-EventKit consistency (`:416-418`), and `InMemoryEventStore` can't
  replicate the real database's timing. Leave it at 200 ms.
- **Don't add message deduplication to `SkippedReminderSyncService`** — WCSession
  delivery semantics are opaque; dedupe at that layer would be fragile. The
  watch-side pending-completion set is the correct lever.

## Design Decisions

1. **Skip refetch: optimistic UI + background reconcile** (Q1, Option C).
   `skipCurrentReminder()` continues to apply `skippedIDs` instantly for
   immediate UI feedback. A fire-and-forget `Task` captures the current
   `skipGeneration`, calls `await reload()`, and discards the result if the
   generation changed (a clear happened). No settle delay — skip doesn't write
   to EventKit. Acknowledged trade-off: the refetch may cause a brief flicker
   if a concurrently-completed reminder drops off during user interaction.

2. **Watch completion: pending-completion set** (Q2, Option B). After local
   removal, the completed identifier is stored in a `pendingCompletions:
   Set<String>` persisted in `AppGroup.defaults`. On every `reload()`, fetched
   reminders are filtered to exclude any identifier still in
   `pendingCompletions`. After filtering, identifiers no longer present in the
   fetched list are pruned from the set (phone has processed them). The set
   lives in `ReminderStore` and is loaded/saved alongside `skippedIDs` during
   `reload()`.

3. **Post-fetch defensive filter** (Q3, Option B). At the end of every
   `reload()`, after the fetched array is assigned to `reminders`, apply
   `reminders = reminders.filter { !$0.isCompleted }`. This is a cheap safety
   net against any edge case where `predicateForIncompleteReminders` returns a
   completed reminder (stale results, race between fetch and assignment, etc.).

4. **iOS completion: no changes** (Q4, Option A). The iOS completion path
   already performs save → 200 ms settle → `reload()`, which drops the
   completed reminder via the predicate. Combined with decision 3, it gains the
   defensive filter at no cost.

5. **Tests: unit + UI** (Q5, Option C). Unit tests in
   `SingleThreadTests/ReminderStoreTests.swift` with `loadsReminders: true` +
   `InMemoryEventStore`: pre-complete a reminder in the store, skip another,
   assert the pre-completed one is gone after reload. Additional tests for the
   pending-completion set lifecycle (add on watch completion, filter on reload,
   prune on confirmation). iOS UI test via `--seed`: seed two reminders,
   pre-complete one in the seed data, skip the other, assert only the
   non-completed, non-skipped one is visible.

### Design Detail: Pending-Completion Set Lifecycle

```
Watch complete:
  1. reminders.removeAll { id == identifier }          // instant removal
  2. pendingCompletions.insert(identifier)             // track it
  3. save pendingCompletions to AppGroup.defaults
  4. relay to phone (existing fire-and-forget)

Reload (any trigger):
  1. fetch reminders from EventKit (predicateForIncompleteReminders)
  2. load pendingCompletions from AppGroup.defaults
  3. show = fetched.filter { !pendingCompletions.contains($0.id) }
  4. show = show.filter { !$0.isCompleted }             // defensive
  5. stillPending = pendingCompletions ∩ Set(fetched.map(\.id))
  6. if stillPending ≠ pendingCompletions:
       pendingCompletions = stillPending
       save pendingCompletions to AppGroup.defaults     // prune processed
  7. reminders = show
```

The set naturally drains: when the phone processes the relay and the
`predicateForIncompleteReminders` stops returning the completed reminder, the
identifier is pruned from `pendingCompletions` (step 6). Until then, it's
filtered out (step 3). The max pending size is one completion per reload cycle
— negligible.

## What We're NOT Doing

- **NOT changing the iOS complete/undo/delete/add flow** — it already refetches.
- **NOT adding EventKit change observers, timers, or scene-phase refetches** —
  explicit reload sites only.
- **NOT modifying the sync protocol** (`SkippedReminderSyncService` message
  format, send/receive semantics, or adding acks/dedupe to `sendMessage`).
- **NOT changing `skipCurrentReminderImmediately()`** — the widget's synchronous
  path stays as-is (widgets build fresh stores per invocation anyway).
- **NOT adding a counter-increment on watch** — the completion counter remains
  iOS-only.
- **NOT refactoring `reload()` to a different concurrency model** — it stays
  `@MainActor` with the existing `withCheckedContinuation` bridge.
- **NOT surfacing pending-completion state to the UI** — it's an internal
  implementation detail. No new `@Published` or computed properties.

## Open Risks

1. **Flicker on background skip refetch**: if a reminder completed elsewhere
   drops off the list mid-interaction, the user may momentarily see it
   disappear. Mitigated by the fact that cross-device completions during active
   use are rare. If this becomes an issue, we can add a short debounce before
   updating `reminders` from the background refetch.

2. **Pending-completion set never pruning**: if the phone never processes a
   relayed completion (app killed, network lost), the identifier stays in the
   pending set forever, permanently hiding a still-incomplete reminder on the
   watch. Mitigation: the set is pruned at app launch by checking each pending
   identifier against EventKit — if the reminder is still incomplete and the
   identifier has been pending for > 5 minutes, remove it from the set and
   let it show again. (This is a safety valve, not a core path.)

3. **`predicateForIncompleteReminders` behavior**: the research notes this is
   only proxied by `InMemoryEventStore`'s filter (`InMemoryEventStore.swift:60`),
   not directly observable. If real EventKit sometimes returns recently-completed
   reminders in the predicate's results (e.g., during a save transaction), the
   defensive filter (decision 3) catches it. If it never does, the filter is a
   no-op.

4. **Watch app termination during pending window**: if the watch app is killed
   between completing a reminder and the phone processing the relay, the
   pending-completion set (in App Group UserDefaults) survives, so the reminder
   stays hidden on relaunch. This is correct behavior — the relay will be
   delivered when the phone wakes.

5. **Skip generation + background refetch race**: the background `Task` for the
   skip refetch captures `skipGeneration` at entry. If the user rapidly skips
   multiple reminders, multiple background Tasks fire in sequence. Each checks
   the generation in `applySkipSet`-style — only the most recent matters. The
   earlier tasks' reloads are harmless (their assignment is discarded by the
   later task's reload). This is bounded by the serial main actor and the
   generation gate.