# Design Discussion — Excluded Projects Not Refreshed on Watch (VAR-624)

## Current State

Excluded-project title state is persisted per-device in an `ExcludedProjectStore`
(UserDefaults) and shared phone↔watch over WatchConnectivity via
`SkippedReminderSyncService`. The set is held in-memory on
`ReminderStore.excludedProjectTitles` (`ReminderStore.swift:49`) and honored live by
`visibleReminders` on every access (`ReminderStore.swift:107`, filter at `:110`).
The receive/refresh round trip is broken:

- `SkippedReminderSyncService.didReceiveNotificationSession` handles
  `excludedProjectTitles` by `excludeStore.save(receivedTitles)` ONLY
  (`SkippedReminderSyncService.swift:176-177`). It sets no store hook, fires no
  notify, and triggers no `reload()`. This is the only membership-change receive key
  that lands purely in UserDefaults with no in-memory notify — contrast
  `showUndatedReminders` → hook (`:179-180`) and `sortOption` → store.save + hook
  (`:182-186`).
- `ReminderStore.excludedProjectTitles` is refreshed from `ExcludedProjectStore` in
  exactly one production path: the `reload()` else-branch `Set(excludeStore.load())`
  (`ReminderStore.swift:301`).
- On the watch, `reload()` runs only at (a) launch/`start()` (`WatchReminderView.swift:42`),
  (b) a `showUndatedReminders` key in a later combined context (`SingleThreadWatchApp.swift:28-31`),
  or (c) user pull-to-refresh (`WatchReminderView.swift:186-205`). No periodic refresh and no
  WatchConnectivity receive handler call it.
- Net: a phone-side exclusion push lands in the watch's UserDefaults but stays dormant in the
  watch's live in-memory store until one of those three triggers fires.

The emit side is already correct: toggle → `ReminderStore.setExcludedProjectTitles`
(`ReminderStore.swift:312-317`) → `onExcludedProjectsChanged` → `pushExcludedProjectTitles`
(phone `SingleThreadApp.swift:52`, watch `SingleThreadWatchApp.swift:43`) →
`updateApplicationContext(["excludedProjectTitles": titles])` (`SkippedReminderSyncService.swift:101-111`).
The bug is the receive/refresh side, not the emit.

## Desired End State

Exclusion state set on one device is reflected on the counterpart's live `visibleReminders`
without waiting for a launch, a show-undated key, or a manual refresh. Concretely:

- The sync service fires a new hook `onExcludedProjectTitlesReceived(_ [String])` after saving
  received titles — mirroring the `showUndatedReminders` hook pattern. No `ReminderStore` reference
  is held in the service.
- Each app layer wires that hook → a store refresh that re-reads `excludeStore.load()` into the
  in-memory set (no EventKit refetch), assigns the `@Observable` `excludedProjectTitles`
  property, and fires `onRemindersChanged?()`.
- The receive handler must NOT call `setExcludedProjectTitles` (which fires
  `onExcludedProjectsChanged` → pushes back to the sender). No echo/push loop.
- Applied on BOTH watch and phone receive paths. iOS currently wires no exclusion receive handler
  at all (`SingleThreadApp.swift:36-52` wires only complete/delete), so the phone has the same gap.

Verification: a unit composition test links one service + shared store and asserts the counterpart
store's `visibleReminders` re-filters after a pushed context; watch UI `--ui-testing` test asserts a
seeded project disappears from the card when excluded.

## Patterns to Follow

- **Receive-hook pattern**: `showUndatedReminders` and `sortOption` already flow hook → app handler →
  store update (`SkippedReminderSyncService.swift:179-186`). Mirror it for exclusions so the service
  stays store-agnostic.
- **write-once-before-`activate()` + `nonisolated(unsafe)` discipline**: hooks capturing the
  `@MainActor` store are written before `activate()` and read on the session delegate queue
  (`SkippedReminderSyncService.swift:56-72` doc comments). Follow for the new exclusion hook.
- **Key-gated receive**: every key is `if let ... as?` guarded (`SkippedReminderSyncService.swift:164-186`);
  an absent key is a no-op and never clobbers. Keep this independent-key model; do not force a full
  combined push.
- **Lazy recompute via `@Observable`**: `visibleReminders` recomputes each access (`ReminderStore.swift:107`),
  so assigning the observable `excludedProjectTitles` property is sufficient to re-render. No refetch.
- **Existing test placement**: exclusion unit tests live in `SkippedReminderSyncServiceTests.swift`
  (push/receive/no-op, `:309-351`) and filtering/persistence in `ReminderStoreTests.swift`. Add to
  these; bespoke suites.

## Anti-Patterns — do NOT follow

- **Reusing `setExcludedProjectTitles` on receive** (`ReminderStore.swift:312-317`): it fires
  `onExcludedProjectsChanged` → hooked push → echo back to the sender-only, and it re-renders as
  a local change. The receive path must be a distinct, non-pushing refresh method.
- **Calling full `reload()` on receive**: heavy EventKit refetch + skip pruning for a change that
  only needs the in-memory exclusion set. Shows the current gap only fixes the case where
  `showUndatedReminders` also arrives. Use a targeted refresh.

## Design Decisions

1. **Refresh mechanism**: Option B. Add `ReminderStore.refreshExcludedProjectTitles(_ titles: Set<String>)`
   that assigns `excludedProjectTitles = titles` and fires `onRemindersChanged?()`. It must NOT fire
   `onExcludedProjectsChanged` (so no push). Title TBD; settles the semantic that received titles come
   off the wire directly rather than re-reading UserDefaults (avoiding a UserDefaults round-trip race).

2. **Notification mechanism**: a new service hook `onExcludedProjectTitlesReceived: (( [String]) -> Void)?`
   fired in the receive branch after `excludeStore.save(receivedTitles)`. Consistent with the
   showUndated/sort hooks; keeps the service free of a `ReminderStore` reference.

3. **App-layer wiring**: phone (`SingleThreadApp.swift`) and watch (`SingleThreadWatchApp.swift`) each set
   `service.onExcludedProjectTitlesReceived = { [weak store] titles in store?.refreshExcludedProjectTitles(titles) }`
   before `activate()`. Because the service holds only stores (not the store object), the wire is identical
   to the show-undated wire at `SingleThreadWatchApp.swift:28-33`.

4. **Scope to both peers**: although the report is watch-first, both wire the symmetric emit
   (`SingleThreadApp.swift:52 = `SingleThreadWatchApp.swift:43`), so a watch-side toggle has the same
   dormant-receive gap on the phone. Fix both.

5. **No echo loop**: the receive refresh path deliberately does not fire `onExcludedProjectsChanged`,
   so no push returns to the sender. Document this in the new method's doc comment.

## What We're NOT Doing

- **Startup/(re)connect exclusion seeding** — deferred;
  the excluded set is pushed only on change,
  and a lone exclusion push replaces (does not merge) the wire context, so a reconnect re-delivers only
  the last single-key context. Tracked separately.
- **Changing push semantics** (accumulating/merging contexts, full-snapshot pushes).
- **A `WCSession` mock seam for UI tests** — end-to-end receive→UI isn't UI-testable without one; flag in PR.
- **Refactoring `updateApplicationContext` latest-wins replace behavior or the other sync keys.**
- **Exclusion-list UI, offline/authorization-state work.**
- **Wire-format / protocol versioning changes.**

## Open Risks

- **Reconnect re-delivery of a lone single-key exclusion context**: an `updateApplicationContext` reconnect
  auto-deliver leaks skip/sort/showUndated if the last pushed context was exclusion-only. Tracked in the
  startup-seed ticket; this change does not compound it.
- **`@Observable` re-render**: verify the watch surface actually re-renders when `excludedProjectTitles`
  is assigned (via the existing observable property); add minimal wiring only if it does not.
- **Latest-wins receive race**: if a pushed exclusion lands while a local toggle is in flight, the last
  on the wire wins. Matches existing receive semantics; acceptable.
- **Coverage seam limits**: the receive→UI handoff can't be proven end-to-end without a real `WCSession`;
  composition unit test + watch UI `--ui-testing` filtering cover the two phases separately.