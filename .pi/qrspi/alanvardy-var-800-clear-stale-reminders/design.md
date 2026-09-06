# Design Discussion — Clear stale reminders

Branch: `alanvardy-var-800-clear-stale-reminders`. All file:line refs verified against
the working tree; most come from `.pi/qrspi/<branch>/research.md`.

## Current State

All three surfaces (iOS/macOS app, watchOS app, widget) derive a single "current"
Apple Reminder from the same `ReminderStore.reload()` funnel. The funnel is already
fresh every call — `reload()` rebuilds the predicate and awaits 1-2 EventKit fetches
with no memoization of results (`ReminderStore.swift:439-491`), applies the
pending-completion filter so a completed card is never shown (`:478`, `:641-648`),
wholesale-replaces `reminders` (`:479`), then reconciles skip/pending/exclusion
state against the fetch (`:487-490`).

Advancement is **structural, not explicit**: a completion/deletion elsewhere removes
the reminder from the fetched incomplete set, so `listContent` re-derives
`visibleReminders.first` automatically (`ReminderStore.swift:146-171`). There is no
"advance to next" code — and none is needed.

The problem is purely **timing**. Nothing notices an out-of-band completion/deletion
until a Group-I reload trigger fires (`research.md` Q3): relaunch, pull-to-refresh,
macOS refresh button, preference change, phone-side watch mutation, in-app mutation,
or a widget-intent/timeline refresh. Zero `EKEventStoreChanged` observers exist, zero
`Task.sleep` loops exist, and scene-phase/`applicationDidBecomeActive` do **not**
refetch (`research.md` Q3, Q6). The widget refreshes only on `Timeline(policy:
.after(15 * 60))` (`NextThingWidget.swift:44-50`).

## Desired End State

When the currently-displayed reminder is completed or deleted outside the app (on
another device or directly in Apple Reminders), **each surfaced platform re-checks on
its own** and advances to the next reminder without a manual refresh:

- **iOS/macOS app** — near-instant re-check via `.EKEventStoreChanged`, with a slow
  polling fallback; active only while a reminder is on screen.
- **watchOS app** — same hybrid re-check against its own local store
  (`WatchAppViewModel.swift:13-19`), active only while a reminder is shown.
- **Widget** — timeline policy shortened **15 → 5 minutes** (`NextThingWidget.swift:44-50`);
  no other widget change.

Verification of correctness: existing tests already prove the *detection* side — a
completed-elsewhere reminder dropped on refetch (`ReminderStoreTests.swift:283-312`,
`:979-990`; watch variant `ReminderStoreWatchTests.swift:55-66`). New tests will prove
the *trigger* side — that the re-check coordinator invokes `reload()` on the right
cue and idles when nothing is displayed. Distinguishable outcome: on-screen reminder
advances without any user gesture.

## Patterns to Follow

**Good — match these:**
- Fresh-fetch funnel: reuse `store.reload()` as the sole re-check action — do not
  re-implement dropping logic (`ReminderStore.swift:439-491`).
- Injected async-closure seam for time: `ReminderStoreSettle` typealias
  (`ReminderStore.swift:10-12`) is the house idiom for making sleep injectable. The
  rechecker's sleep follows it.
- Hook/layer separation: Core never touches UserDefaults/WatchConnectivity/WidgetKit;
  app/watch view models wire `on*` hooks and own lifecycle (`AppViewModel.swift`,
  `WatchAppViewModel.swift`). The rechecker lives in Core, is **started/stopped by the
  view models**, and touches only EventKit + `ReminderStore`.
- Auto-cancelling `.task` as start/stop point (`.task` modifiers at
  `ContentView.swift:249-257`, `WatchReminderView.swift:59-61`) — start the rechecker
  where `store.start()` is already called.
- Explicit `@MainActor` in Core (`ReminderStore.swift:14`) — the coordinator annotates
  `@MainActor`, not `Task { @MainActor in }`.
- Deterministic tests: `InMemoryEventStore` + `noopSettle` + `withCheckedContinuation`
  rendezvous (`research.md` Q7). No real-sleep tests.
- Re-entrancy guard precedent: `refreshManual` already serializes overlapping reloads
  (`ContentViewModel.swift:182-198`) — reuse the idea for overlapping poll/observer
  ticks.

**Do NOT follow — flag these:**
- Unstructured fire-and-forget `Task { [weak self] ... }` with no handle (skip task
  `ReminderStore.swift:395-405`, ghost card `WatchReminderViewModel.swift:104-116`). A
  polling loop must be cancellable and tracked, unlike these one-shots.
- Widget intents run with nil `on*` hooks and rely on WidgetKit auto-reload
  (`ReminderIntents.swift:4-6`). Do not add manual reload wiring to the widget; the
  5-min policy is the widget's entire mechanism.
- Stale in-memory notification count (`AppViewModel.swift:177-180`): related staleness
  bug, but fixing it by re-scheduling on each tick is explicitly out of scope here.

## Design Decisions

1. **Hybrid detection — `.EKEventStoreChanged` + polling fallback.** Observer gives
   near-instant advance on external change; a slow poll is the eventual-consistency
   backstop for cases the notification misses. Both handlers funnel into the single
   `store.reload()`. Debounce/coalesce is mandatory: the observer also fires on our own
   EventKit writes, so overlapping ticks must collapse to one reload.
2. **On-screen gating — re-check active only while a reminder is shown.** Gate on
   `store.listContent == .reminder` (`ReminderStore.swift:161-171`). When `.empty` or
   `.allDone`, both the observer and the poll idle. This scopes the work to the ticket
   ("currently displayed reminder no longer incomplete") and descopes "a new reminder
   appeared elsewhere".
3. **Full `reload()` per tick.** No cheap pre-check/fetch. The verified path already
   drops completed-elsewhere reminders (`ReminderStoreTests.swift:979-990`), and a
   second fetch path would add a stale-state edge case for zero correctness gain.
4. **Coordinator extraction — `StaleReminderRechecker` in Core.** Owns the loop task +
   observer, with injected `sleep` and `reload` (Q5=B). Interface (draft):
   `init(store:reminders load, sleep: @escaping @Sendable (Duration) async -> Void,
   reload: @escaping () async -> Void)`, plus `start()` / `stop()`. Tests inject a
   no-op sleep and a recording `reload`.
5. **Platform rollout — iOS/macOS + watch get the foreground rechecker; widget gets
   5-min policy.** Widget stays per-refresh construction and stays on
   `Timeline(policy: .after(...))`; only the constant changes
   (`NextThingWidget.swift:44-50`). Poll fallback interval default **60 s** (named
   constant, tunable); observer is the primary path.
6. **Lifecycle attach — view-model owned, `.task`-scoped.** `ContentViewModel` /
   `WatchReminderViewModel` start the rechecker after `store.start()` and stop it on
   task cancellation (auto-cancel via `.task`). iOS/macOS foreground only; no
   background execution.

## What We're NOT Doing

- No background execution (`BGTaskScheduler`) or scene-phase refetch on iOS/macOS.
- No "new reminder appeared elsewhere" detection while the list is empty/all-done.
- No cheap-guard second fetch path; no change to the drop/advancement logic itself.
- No change to the stale notification-scheduling count (`AppViewModel.swift:177-180`) —
  tracked separately.
- No new WatchConnectivity or sync-payload changes; no widget reload wiring beyond the
  timeline policy constant.
- No `reset()`/cache-semantics work beyond the existing `refreshSourcesIfNecessary()`
  call already inside `reload()` (`ReminderStore.swift:442`).

## Open Risks

- **`.EKEventStoreChanged` semantics are unproven in-tree** (zero observers today) and
  its OS-level delivery on cross-device sync is not observable from this repo
  (`research.md` Open Areas). The poll fallback is the safety net for this exact
  uncertainty.
- **Observer store filter**: `ReminderStore.eventStore` is `private` (init assigns it;
  not in the public block). The coordinator may observe `.EKEventStoreChanged` with
  `object: nil` (global) and debounce, or Core exposes the store for object-filtered
  observation. Needs a small decision at implementation.
- **Debounce/coalesce correctness**: our own writes + poll ticks + observer can overlap
  a single `reload()`; must serialize (guard per decision 1) without deadlocking or
  starving the next external change.
- **watchOS `EKEventStoreChanged` availability/frequency** — the observer path on
  watch is new; watch already reloads on every phone push, so the marginal value there
  is the safety poll.
- **Interval tuning** (poll fallback 60 s, widget 300 s) is a starting value; drift or
  battery impact on watch may warrant adjustment after real-device use.
- **Testability of the loop**: injected sleep must not loop forever under test; use a
  one-shot or continuation-gated sleep plus explicit `stop()`/cancellation, mirroring
  the rendezvous style in `ReminderStoreTests.swift:295-311`.