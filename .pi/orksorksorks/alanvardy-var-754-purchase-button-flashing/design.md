# Design Discussion

## Current State

The freemium gate is a single predicate — `canMutate = entitlementStore.isEntitled ||
completionCounter.count < 100` (`ReminderStore.swift:136-138`) — rendered at three
sites: the iOS bottom bar swaps the mic slot for `UpgradePromptButton`
(`ContentView.swift:679-680`), the settings row becomes a NavigationLink
(`SettingsView.swift:101-107`), and the watch swaps action buttons for the
"Upgrade on your iPhone" prompt (`WatchReminderView.swift:219`).

`EntitlementStore.isEntitled` is a plain `Bool` defaulting to `false`
(`EntitlementStore.swift:46`). At boot the init observation task runs
`refreshEntitlement()` then `observeTransactionUpdates()` (`EntitlementStore.swift:17-21`),
and `refreshEntitlement()` assigns `isEntitled` only after the
`Transaction.currentEntitlements` async loop finishes (`EntitlementStore.swift:80-91`).
The store is constructed inside `SingleThreadApp.init()` via a default parameter
(`AppViewModel.swift:32` → `ReminderStore.swift:27,40,102`), before any view
evaluates. So the first body pass races the refresh: a genuinely-purchased user
at the 100-completion cap reads `false` for a few frames, and the bottom bar
renders `upgradePrompt` (`ContentView.swift:679`) before snapping to the action
cluster — the reported flash.

`false` is ambiguous here: it means both "not purchased" and "not yet known".
The codebase has no "unknown" state — the closest precedents are
`ReminderStore.authorizationStatus` defaulting to `.notDetermined` and rendering
a `ProgressView` (`ReminderStore.swift:57`; `ContentView.swift:341-342`), and
`PurchaseSettingsView`'s nil `product` rendering a stable "Loading…" row
(`PurchaseSettingsView.swift:124-132`). Entitlement has neither a sentinel nor a
loader.

## Desired End State

For a user who has already purchased, the app opens **without** the "Upgrade to
unlimited" button ever appearing — the bottom bar shows the correct (entitled)
UI as soon as entitlement is known, and shows nothing in the freemium slot while
it is not. For a free-tier user under the cap, nothing changes: they still see
the mic/action controls; for a gated free user (cap exhausted, no purchase) the
upgrade prompt appears once entitlement is resolved — with no observable flash
in either direction.

Verification:
- **Unit** (`EntitlementStoreTests`): a fresh `EntitlementStore()` starts with
  `hasResolvedEntitlement == false`; it becomes `true` after a refresh (seam-driven);
  `testingWithEntitled:` sets it `true` immediately.
- **UI** (`SingleThreadUITestsFlows`): a new "unresolved" seam renders **no**
  `upgradeButton` in the freemium slot; the existing gated test
  (`testUpgradePromptAppearsWhenGated`, `SingleThreadUITestsFlows.swift:729-749`)
  and entitled test (`testActionClusterAppearsWhenEntitledAtCap`,
  `:751-761`) still pass unchanged.
- **Sync** (`EntitlementSyncTests`): unchanged — the `"isEntitled"` context key
  and its `false` default contract (`EntitlementSyncTests.swift:33`) are preserved.

## Patterns to Follow

- **`@Observable` + dependency tracking, no `.onChange`** — views read
  `canMutate` and re-evaluate when the observable flag mutates
  (`ReminderStore.swift:136-138`; `ContentView.swift:679`). The resolved flag
  should ride the same mechanism: add the property to `EntitlementStore`, read
  it in `bottomBar`, no `.onChange` needed.
- **Additive `private(set)` observable flag** — mirror `isEntitled`
  (`EntitlementStore.swift:46`): `public private(set) var hasResolvedEntitlement`,
  only the store writes it.
- **Not-known → static surface / nothing, not a loader** — the watch's static
  "Upgrade on your iPhone" prompt (`WatchReminderView.swift:219-221`) and the
  iOS `.notDetermined → ProgressView` (`ContentView.swift:341-342`) are the two
  idioms. For a sub-100ms window a bottom-bar spinner (`PurchaseSettingsView.swift:124-132`)
  is noise; rendering nothing is the closest match to "err on the side of not
  showing."
- **Test seams are init-only and synchronous** — `testingWithEntitled:`
  (`EntitlementStore.swift:25-32`) and the `--seed isEntitled` wiring
  (`AppViewModel.swift:298-300`) settle state before first frame; the new
  unresolved seam should follow the same shape so UI tests can assert the
  pre-resolution render deterministically.

**Patterns NOT to follow:**
- Do **not** persist/cache entitlement — research confirms `isEntitled` is always
  re-derived from `Transaction.currentEntitlements` (`EntitlementStore.swift:80-91`);
  the only durable freemium value is `"completionCount"`
  (`CompletionCounterStore.swift:12-15`). The fix must stay in-memory.
- Do **not** fold "unknown" into `canMutate` or the silent mutation guards
  (`ReminderStore.swift:174,223,248,300,331`) — those are deterministic and
  unrelated to the flash.
- Do **not** add `.disabled()` to the bottom-bar controls — gating is render
  presence + silent guards today (research Q2); introducing disabled state here
  would be a new pattern.
- Do **not** reuse the product-load `.onChange(of:)` reset idiom
  (`PurchaseSettingsView.swift:59-65`) — it exists to reset `@State`; the
  bottom bar has no such local state.

## Design Decisions

1. **Resolved state representation — additive flag**: Add
   `public private(set) var hasResolvedEntitlement: Bool = false` to
   `EntitlementStore`; set `true` at the end of `refreshEntitlement()`
   (`EntitlementStore.swift:80-91`) and in `init(testingWithEntitled:)`
   (`:25-32`). `isEntitled` keeps its `false` default. — Minimal and additive;
   preserves the false-default contract asserted by
   `EntitlementStoreTests.swift:13-15` and `EntitlementSyncTests.swift:33`, and
   leaves the watch `"isEntitled"` context key (`SkippedReminderSyncService.swift:281`)
   untouched.

2. **Unresolved render — nothing in the freemium slot**: In the iOS branch
   (`ContentView.swift:678-685`), gate the whole cluster on
   `store.entitlementStore.hasResolvedEntitlement`; when unresolved, render
   nothing (the bottom bar keeps its error/feedback/dictation/recording branches
   above it). — Never shows a wrong element to anyone; most conservative reading
   of "err on the side of not showing"; a typically <100ms empty slot is
   imperceptible.

3. **`canMutate` unchanged — rendering-only**: `canMutate` stays
   `entitlementStore.isEntitled || completionCounter.count < 100`
   (`ReminderStore.swift:136-138`); the flag only suppresses the upgrade prompt.
   — Mutation semantics stay deterministic and independent of StoreKit timing;
   free users' mic/action buttons and the silent guards are unaffected.

4. **Scope — iOS only**: The watch's parallel window
   (`EntitlementState.isEnabled == false` → `WatchReminderView.swift:219-221`)
   is out of scope. Its flag arrives over WatchConnectivity with no initial
   `pushAll()` at iOS launch (research Q5) and no timing guarantee; it already
   renders a *static* prompt rather than a flash. Deferring it could hide the
   prompt indefinitely. — Matches the task (iOS bottom bar) and avoids the
   sync-timing risk.

5. **Test seam — unresolved initializer + seed field**: Add
   `init(testingWithEntitlementUnresolved:)` (sets neither flag, no observation
   task) and a `--seed` `entitlementUnresolved` field (default `false`) wired in
   `AppViewModel.seededStore` (`AppViewModel.swift:282-314`), so UI tests can
   deterministically observe the pre-resolution render. — Existing seams can't
   observe the flash (research Q6); a dedicated seam reproduces and regression-
   guards it directly. The real `sync()`/purchase path stays unit-only (FB22237318).

## What We're NOT Doing

- **Not** touching the watch entitlement lifecycle or `EntitlementState`.
- **Not** changing `canMutate`, the mutation guards, or the completion counter.
- **Not** persisting or caching entitlement, or adding a restore-on-launch
  `AppStore.sync()`.
- **Not** adding a bottom-bar spinner/placeholder — the window is sub-frame.
- **Not** refactoring `isEntitled` into a tri-state enum or touching the watch
  sync payload shape.
- **Not** attempting to make the positive `Transaction.currentEntitlements`
  re-derivation automatable (blocked by FB22237318) — out of scope.
- **Not** reworking `CompletionCounterStore` observability (`count` is a
  non-observable `UserDefaults` read, `CompletionCounterStore.swift:18-21`) —
  a mid-session cap-crossing flash is a separate issue.

## Open Risks

- **The positive re-derivation path is untested**: no automated test exercises a
  real verified transaction flowing through `refreshEntitlement()`; the new
  flag's `true` transition on the production path relies on the StoreKit 2
  implementation (research Open Areas). The unit test asserts the seam-driven
  transition, not the StoreKit-driven one.
- **Two-boolean consistency**: `hasResolvedEntitlement` and `isEntitled` must be
  kept in sync (resolved is set exactly where `isEntitled` is assigned). Risk is
  low (single method) but a future edit adding an assignment site must remember
  the flag.
- **Free-user perception**: a free user under the cap now has the mic/action
  cluster suppressed for the same unresolved window. If the refresh is ever slow
  (network storekitd contention), the bottom bar could look empty for longer
  than intended. Accepted for now; could revisit with a placeholder if reported.
- **UI-test flake surface**: the new unresolved seam renders "nothing", so the
  test asserts non-existence via a bounded wait — as long as entitlement never
  resolves under the seam (no observation task), this is deterministic.
