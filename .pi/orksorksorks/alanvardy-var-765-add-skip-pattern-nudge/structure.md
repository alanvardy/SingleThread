# Structure Outline

## Approach

Persist a per-reminder skip count (`[String: Int]`) in the App Group suite, increment it only on local interactive skips, surface a nudge banner→modal when a count crosses 6 (Delete / Reschedule / View in Reminders on iOS; Delete only on watch), sync counts latest-wins via WatchConnectivity, and reset/prune counts on action, complete, and window exit.

---

## Stage 1: Persistence — `SkipCountStore` + `"skipCounts"` key (bottom-most layer)

Delivers a standalone store that owns the new `[String: Int]` map under `"skipCounts"`, decoupled from the skip-set lifecycle so a `reconcileSkipState` prune can't wipe counts. Registers the key in the `--seed` reset seam so seeded UI tests can't leak count state.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkipCountStore.swift` (new), `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` (`persistedKeys`)

**Key changes**:
- `struct SkipCountStore { init(defaults: UserDefaults = AppGroup.defaults, key: String = "skipCounts"); func load() -> [String: Int]; func save(_ counts: [String: Int]) }` — new store, shaped after `SkippedReminderStore` (`ReminderSkip.swift:121-137`) and the `[String: TimeInterval]` dict precedent in `PendingCompletionStore`.
- `UITestingSeed.resetPersistedState()` — add `"skipCounts"` to `persistedKeys` so `--seed` clears it from both suites (else skip counts leak between seeded UI tests).

**Tests**: new `SingleThreadTests/SkipCountStoreTests.swift` covering round-trip save/load (happy path) + empty default `[:]` and UUID-keyed isolation (sad paths); extend `UITestingSeedTests.swift` to assert `"skipCounts"` is cleared by reset.

**Verify**: build + `make test` green for `SkipCountStoreTests` and `UITestingSeedTests` (targeted `-only-testing:SingleThreadTests` allowed). Products: `"skipCounts"` round-trips through `AppGroup.defaults`, never `.standard` on iPhone.

---

## Stage 2: Store — skip-count lifecycle + threshold trigger in `ReminderStore`

Delivers the only writer of counts: increment on local interactive skip (not on sync-receive), reset on delete/complete/reschedule, prune on window exit, and a `skipCount(for:)` accessor. Fires `onSkipNudgeRequested` when a count first crosses 6.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`, `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift` (or new `SkipCountLogic`)

**Key changes**:
- `ReminderStore` gains an injected `SkipCountStore` (new init param, beside `skipStore`).
- `func skipCount(for identifier: String) -> Int` — accessor consumed by view models.
- Increment inside `skipCurrentReminder()` (`:314-327`) and `skipCurrentReminderImmediately()` (`:345-352`) only — **never** in the sync-receive/reconcile path (double-count guard).
- `var onSkipNudgeRequested: ((String) -> Void)?` — fires when the incremented count crosses `> 5`.
- Reset/remove the count in `completeReminder(identifier:)`, `deleteReminder(identifier:)` (both branches), and `rescheduleReminder` (stage 3).
- `reconcileSkipState` (`:551-562`) prunes counts for ids absent from the fetched in-window set — mirrors the existing skip-set prune.
- Pure rule: `enum SkipCountLogic { static func shouldNudge(_ count: Int, threshold: Int = 6) -> Bool }` — count `> 5`.

**Test seam (add here, consumed by Stage 5/6)**: extend `UITestingSeed` with an optional `skipCounts: [String: Int]` field and preload it in `AppViewModel.seededStore` (or a `--ui-testing-skip-count` preset if `--seed` is unusable) so UI tests can reach count 6 without 6 taps. Drive the write flows via `--seed '<json>'`.

**Tests**: `ReminderStoreTests` — one increment per interactive skip, receive-path does not increment, `skipCount(for:)` returns 0 for unknown then N, threshold fires once at 6 (not at 5), complete/delete reset the count, reconcile prunes the count (injected `InMemoryEventStore` + `noopSettle` + `withCheckedContinuation`); `ReminderSkipTests`-style `@Test(arguments:)` table for `shouldNudge`.

**Verify**: build + `make test` (unit-only) green for `ReminderStoreTests` + the new logic tests. Products: counts increment/reset/prune correctly and the hook fires only on the 6th skip.

---

## Stage 3: Store — `rescheduleReminder(identifier:to:)` mutation

Delivers the app's first due-date write as a small, tested `ReminderStore` method (not `EKReminder` mutation scattered into views). Consumed by the iOS nudge modal.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`, `SingleThreadTests/EventKitStoringTests.swift` (extend `FakeEventStore` to record `save` of a mutated reminder)

**Key changes**:
- `func rescheduleReminder(identifier: String, to due: DateComponents) async -> Bool` — `#if !os(watchOS)`: set `dueDateComponents` on the matching `EKReminder`, `eventStore.save(commit: true)`, settle, reload; returns success (watch returns `false` — action omitted there). Resets that reminder's skip count (per DD5).
- Reuses the `completeCurrentReminder()` / `deleteReminder(identifier:)` shape (guards → mutate → save → settle → reload).

**Tests**: `EventKitStoringTests` — due-date write persists via `FakeEventStore` and reload fires (happy path); unknown identifier / non-iOS guard is a no-op (sad path). `ReminderStoreTests` — reschedule resets the count.

**Verify**: build + `make test` green for `EventKitStoringTests` + `ReminderStoreTests`. Products: a single due-date mutation exists, tested in isolation from any view.

---

## Stage 4: Transport — `"skipCounts"` in `SkippedReminderSyncService` (bidirectional, latest-wins)

Delivers count snapshots alongside the existing skip-set payload. Receive is authoritative (not deferred-to-next-reload), matching the "Patterns NOT to follow" guard.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, `SingleThread/AppViewModel.swift`, `SingleThreadWatch/WatchAppViewModel.swift`

**Key changes**:
- Add `PayloadKey.skipCounts` (`"skipCounts"`) to the enum (`:268-283`) and include `countStore.load()` in `pushAll()` (`:167-202`).
- `apply(context:)` (`:308`): on receive, `SkipCountStore.save(_:)` **then** `onSkipCountsReceived` — mirror the skip receive shape (`:317-323`).
- New hook `var onSkipCountsReceived: (([String: Int]) -> Void)?`.
- Wire it on **both** platforms: watch → `store.reload()` (mirror `WatchAppViewModel.swift:174-178`); iPhone → either wire the hook to reconcile, or guarantee `reconcileSkipState` re-reads the count store — counting must not drift on the phone.
- Widget: writes counts via App Group only, no live push (matches skip IDs today).

**Tests**: `SkippedReminderSyncServiceTests` (`FakeSession`) — push includes `skipCounts`, receive saves + fires hook, absent key is a no-op; `WatchSyncPipelineTests` (`WatchFakeSession`) — watch receives every key incl. `skipCounts`, still omits phone-only keys. Extend fake-session fixtures to carry the new key.

**Verify**: build + `make test` green for the two sync suites. Products: counts round-trip both directions without double-counting on receive.

---

## Stage 5: Presentation — iOS nudge (banner + sheet + 3 actions) + localization

Delivers the in-card dismissible banner (swipe-prompt idiom) whose tap opens a `.sheet` modal with Delete, Reschedule, and View in Reminders. This is the first consumer of Stages 1–4.

**Files**: `SingleThread/ReminderCardView.swift` (banner, mirror `:127-172`), `SingleThread/ContentView.swift` (sheet + actions, mirror `:245-250`, deep link reuse `:407-425`), `SingleThread/ContentViewModel.swift` (nudge state + `rescheduleCurrentReminder(to:)` forwarding), `SingleThreadCore/.../LocalizedString+Shared.swift` (`SharedStrings` for shared copy), `SingleThread/Resources/Localizable.xcstrings`

**Key changes**:
- Banner state driven by `ContentViewModel` via `store.onSkipNudgeRequested` + `skipCount(for:)`; banner stays screen-reader reachable (no `.accessibilityHidden`, unlike the swipe hint).
- `rescheduleCurrentReminder(to: DateComponents)` forwards to `store.rescheduleReminder(identifier:to:)`; Delete reuses `deleteCurrentReminder()`; View in Reminders reuses the existing deep link.
- Actions reset the count (already done in Stages 2–3).
- New copy (banner text, modal title, "Reschedule") lands in all 6 languages (en, zh-Hans, es, ja, de, fr) across the app catalog + `SharedStrings`; reuse existing `deleteAction`.

**Tests**: `SingleThreadUITests` — seed `reminders` + `skipCounts` via the Stage-2 seam, assert the banner appears at count 6, tap-through Delete / Reschedule / View in Reminders (a11y identifiers per the existing scheme). Run the a11y audit unchanged.

**Verify**: build + `make ui-test` green for the new iOS UI test (targeted `-only-testing:SingleThreadUITests/...`, destination `,id=`-pinned). Local a11y audit may flag local-only `.hitRegion`/`.dynamicType` — not a CI break.

---

## Stage 6: Presentation — watch nudge (banner + confirmationDialog, Delete only) + localization

Delivers the watch variant: a non-disruptive nudge surfacing a system `confirmationDialog` offering Delete (no deep link or date picker on watch).

**Files**: `SingleThreadWatch/WatchReminderView.swift` (nudge + dialog, mirror `:206-221`), `SingleThreadWatch/WatchReminderViewModel.swift` (nudge state), `SingleThreadWatch/Resources/Localizable.xcstrings`

**Key changes**:
- nudge state wired from `store.onSkipNudgeRequested`; tapping opens `.confirmationDialog` with `Button(SharedStrings.deleteAction, role: .destructive)` → `store.deleteCurrentReminder()` (resets the count via Stage 2).
- New watch copy in `Localizable.xcstrings` (all 6 languages).

**Tests**: `SingleThreadWatchUITests` — reach the nudge and delete (use the `--ui-testing-skip-count` seam / preloaded store; `skipCounts` round-trips `.standard` on watch). Run the watch a11y audit.

**Verify**: build + `make watch-ui-test` green. Products: both surfaces show and act on the nudge end-to-end.

---

## Testing Checkpoints

After each stage's incremental gate, the following must be green before advancing (resume points if context resets):

1. `make test` — `SkipCountStoreTests` + `UITestingSeedTests` green (`"skipCounts"` round-trips + is reset by `--seed`).
2. `make test` — `ReminderStoreTests` + logic table tests green (increment/reset/prune + `shouldNudge` fires once at 6).
3. `make test` — `EventKitStoringTests` + `ReminderStoreTests` green (reschedule persists + resets count).
4. `make test` — `SkippedReminderSyncServiceTests` + `WatchSyncPipelineTests` green (push/receive `skipCounts`, no double-count).
5. `make ui-test` — new iOS nudge UI test green (banner at 6 → all three actions).
6. `make watch-ui-test` — new watch nudge UI test green (banner → Delete).
7. Final: parent runs the full `./scripts/test.sh` gate once; `make lint` + `make format` clean; `make periphery` clean.

**Cross-cutting note**: the deterministic UI-test seam (`seed.skipCounts` / `--ui-testing-skip-count`) is intentionally stubbed in Stage 2 because reaching count 6 via 6 live UI taps is slow and flaky — it is the one capability that can't be built purely bottom-up and is staged above its consumer.

**Deferred (per design)**: break-down ("smaller pieces"), recurrence-aware reschedule, and re-nudge cadence beyond "fire at first crossing" — all out of scope; decide re-fire policy (every +6 vs once) during Stage 2 implementation.