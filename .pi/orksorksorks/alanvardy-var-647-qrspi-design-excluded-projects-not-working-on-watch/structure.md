# Structure Outline

## Approach
Fix the receive/refresh gap in `SkippedReminderSyncService`: a pushed `excludedProjectTitles`
payload currently lands only in the receiver's `ExcludedProjectStore` (UserDefaults) and is never
pushed into the live in-memory `ReminderStore.excludedProjectTitles`, so the counterpart's
`visibleReminders` never re-filters. Mirror the existing `showUndatedReminders` hook pattern: fire a
new service hook after `excludeStore.save(...)`, wire both app layers to a new non-pushing store
refresh, and cover each layer with a unit / UI test. Emit side is already correct — this is
receive-only, and the receive path must NOT call `setExcludedProjectTitles` (no echo).

## Phase 1: Received-exclusion round trip through the model layer

Delivers the end-to-end receive→re-render behavior at the store/service boundary: a received
exclusion payload is saved, surfaced through the new hook, refreshed into the in-memory set, and
`visibleReminders` re-filters — without refetching EventKit and without pushing back to the sender.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThreadTests/ReminderStoreTests.swift`, `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `ReminderStore.refreshExcludedProjectTitles(_ titles: Set<String>)` — **new** `@MainActor` public
  method. Assigns `excludedProjectTitles = titles`, fires `onRemindersChanged?()`, and deliberately
  does **not** fire `onExcludedProjectsChanged` (no push). Doc comment records the no-echo rule.
- `SkippedReminderSyncService.onExcludedProjectTitlesReceived: (( [String]) -> Void)?` — **new**
  `nonisolated(unsafe)` hook var, written before `activate()`, read on the delegate queue (same
  pattern as `onShowUndatedRemindersReceived`).
- `session(_: WCSession, didReceiveApplicationContext:)` — in the
  `PayloadKey.excludedProjectTitles` branch, after `excludeStore.save(receivedTitles)`, add:
  `let handler = onExcludedProjectTitlesReceived; handler?(receivedTitles)`. Keep key-gated; absent
  key stays a no-op.

**Verify**: `make test` passes (Swift Testing). New composition test in
`SkippedReminderSyncServiceTests.swift` links one service + shared `ReminderStore`/`ExcludedProjectStore`,
feeds `didReceiveApplicationContext: ["excludedProjectTitles": [...]]`, and asserts the store's
`visibleReminders` re-filters (project disappears). New unit test in `ReminderStoreTests.swift`
asserts `refreshExcludedProjectTitles` updates the set, fires `onRemindersChanged?()`, and does
**not** fire `onExcludedProjectsChanged`.

---

## Phase 2: Wire the hook into both app layers

Delivers the live end-to-end connection: a peer's exclusion push now re-renders the local
`visibleReminders` on **both** iPhone and watch (the phone had the same dormant gap — iOS currently
wires no exclusion receive handler at all).

**Files**: `SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`

**Key changes** (both files, inside the `#if os(iOS)` / `WCSession.isSupported()` init block, before
`activate()`):
- `service.onExcludedProjectTitlesReceived = { [weak store] titles in store?.refreshExcludedProjectTitles(Set(titles)) }`
  — new wiring, identical shape to the existing `onShowUndatedRemindersReceived` wiring
  (`SingleThreadWatchApp.swift:28-33`). `[weak store]` keeps the retain-cycle discipline.
- No change to the existing emit wiring (`onExcludedProjectsChanged → pushExcludedProjectTitles`).

**Verify**: `./scripts/test.sh` (or `make build`) builds both schemes and full CI passes. The
receive→device handoff needs a real `WCSession` and is **not** automation-provable — verify
manually: on a real simulator pair, toggle a project exclusion on the phone and confirm the watch's
card disappears without a launch / show-undated key / pull-to-refresh; and the reverse (watch →
phone). Flag in the PR that end-to-end receive→UI isn't unit-provable without a `WCSession` mock
seam.

---

## Phase 3: Watch UI regression test for exclusion filtering

**Goal**: prove the store's live exclusion set drives the on-screen results on the watch, so the
Phase 1 core behavior is guarded at the UI layer (the receive→UI gap is covered by Phase 1's
composition test; this covers the store→UI half).

**Files**: `SingleThreadWatchUITests/`

**Key change**: new XCTest in `SingleThreadWatchUITestsFlows.swift` (or new file in the bundle)
that launches with `--ui-testing` + a seeded project, excludes it through the store, and asserts the
reminder card / visible results no longer render that project. Uses the existing `--ui-testing`
store seam (`SingleThreadWatchApp.uiTestingStore()`), since no real `WCSession` is available.

**Verify**: watch UI test passes:
```
./scripts/test.sh --ui-only    # or the watch build+test lines with WATCH_TEST_SIM
```
Switch the UI test diffusion must pass along with `./scripts/test.sh` full.

---

## Testing Checkpoints

After **Phase 1** — a composition unit test proves a received exclusion round-trips through the
service hook into the store and re-filters `visibleReminders` (no EventKit refetch, no echo), and the
new `refreshExcludedProjectTitles` primitive is isolated. Rebuild of the SPM package compiles.

After **Phase 2** — both iOS and watch builds succeed; iPhone and watch Apps each wire
`onExcludedProjectTitlesReceived` before `activate()`; no regression in the full `./scripts/test.sh`.

After **Phase 3** — the watch UI test asserts a seeded excluded project no longer appears in the
visible results; full CI (`./scripts/test.sh`) is green.

Resume note: the change is **receive-only**. Foundational constraint — never route the receive path
through `setExcludedProjectTitles`, or an echo loop forms.