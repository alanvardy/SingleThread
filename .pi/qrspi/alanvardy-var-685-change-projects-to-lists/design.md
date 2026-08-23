# Design Discussion

## Current State

Groups of reminders are named "project" at every layer, while EventKit's native
concept is a reminder *list* (`EKCalendar` for `.reminder`). Research found a
consistent vertical slice:

- **UI**: `ExcludedProjectsView` (`SingleThread/SettingsView.swift:12`) with
  `excludedProjects: Set<String>` binding (:39), pushed via
  `Label("Excluded Projects", systemImage: "eye.slash")` (:183); navigation
  title :34, footer copy :31.
- **Store**: `ReminderStore.excludedProjectTitles` (`ReminderStore.swift:49`),
  mutated via `setExcludedProjectTitles` (:310, persists + fires
  `onExcludedProjectsChanged` + `onRemindersChanged`) and
  `refreshExcludedProjectTitles` (:320, receive-only, no persist). Filtering by
  calendar title string at :110; reload from disk at :301.
- **Persistence**: `ExcludedProjectStore`
  (`SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift:4`)
  with literal key `"excludedProjectTitles"` (:7) in App Group defaults
  (`AppGroup.swift:10`). Two instances per device converge on the same key.
- **Sync**: `PayloadKey.excludedProjectTitles = "excludedProjectTitles"`
  (`SkippedReminderSyncService.swift:236`), pushed phone→watch only via
  `updateApplicationContext` (:107-115); received at :183-186.
- **Seed seam**: UI-test seed JSON key `"excludedProjects"` (`UITestingSeed.swift:78`)
  and launch arg `--ui-testing-excluded` (consumed `SingleThreadWatchApp.swift:74-89`);
  `persistedKeys` reset list contains raw literal `"excludedProjectTitles"`
  (`UITestingSeed.swift:51-62`).
- **No migration infrastructure exists**: every persisted/payload read is a
  direct typed read with silent default fallback. No protocol version field on
  WatchConnectivity.
- Known pre-existing issues: `pushExcludedProjectTitles` sends a single-key
  application context that **clobbers other context keys** unlike
  `pushSortOption` which re-carries skips (:107-115 vs :118-128); the watch's
  push hook wiring (`SingleThreadWatchApp.swift:48`) is unreachable because
  nothing on watch calls `setExcludedProjectTitles`.

## Desired End State

The concept is called "list" everywhere — user-facing strings ("Excluded
Lists"), all Swift symbols and file names, the App Group UserDefaults key, the
WatchConnectivity payload key, the seed JSON key, and test names/fixtures.
Behavior is otherwise unchanged, except:

1. Exclusion pushes carry the skip set alongside exclusions (no context
   clobbering).
2. The watch app's unreachable push wiring is removed; exclusion sync is
   explicitly phone→watch only.

Verification: full `./scripts/test.sh` gate passes (unit + UI tests on iPhone
17 and iPad A16, lint, Periphery); grep finds no user-facing or symbol-level
"project(s)" referring to reminder groupings; updated unit tests pin the new
key strings.

## Patterns to Follow

- **Key constant defined once per surface** — payload keys live in one
  `PayloadKey` enum shared by both targets
  (`SkippedReminderSyncService.swift:234-242`); keep new keys there, never as
  inline literals at call sites.
- **Receive-only vs local-edit mutation split** — preserve the
  `set…` (persist + fire both hooks) / `refresh…` (no persist, reminders-changed
  only) pair (`ReminderStore.swift:310-327`) under their new names; it is what
  prevents sync echo loops.
- **Per-key gated receive** — independent `if let … as?` guards per payload key
  with absent-key no-op semantics (:168-202); keep this when renaming keys.
- **Tolerant seed decoding** — `decodeIfPresent … ?? []` for optional seed keys
  (`UITestingSeed.swift:78`); keep optional after rename.
- **Test fixtures attach titled `EKCalendar`s** — reuse the
  `makeReminder(title:calendarTitle:)` pattern (`ReminderStoreTests.swift:523`)
  and `inProjectReminder` shape (`SkippedReminderSyncServiceTests.swift:477`,
  renamed to list terminology).
- **Update `UITestingSeed.persistedKeys` in lockstep with any key change**
  (`UITestingSeed.swift:51-62`) or seeded relaunches leak state.
- **Do NOT follow** the single-key-context push of
  `pushExcludedProjectTitles` — it is the bug we are fixing; mirror
  `pushSortOption`'s re-carry-the-skips shape instead (:118-128).

## Design Decisions

1. **Persisted key: hard rename, no migration** — `"excludedProjectTitles"` →
   `"excludedListTitles"` in `ExcludedListStore`. Accepted cost: existing users'
   exclusions silently reset once; they re-toggle in Settings. No migration
   infrastructure exists and adding it for a low-stakes preference is not worth
   the complexity (user decision Q1=B).
2. **Wire key renamed in lockstep** — `PayloadKey` becomes
   `"excludedListTitles"` on both ends. Both targets compile the same enum from
   SingleThreadCore, so mixed-version pairs briefly stop syncing exclusions
   until both apps update (user decision Q2=A).
3. **Seed seam fully renamed** — seed JSON key `"excludedProjects"` →
   `"excludedLists"` and launch arg `--ui-testing-excluded` →
   `--ui-testing-excluded-list`. Test-only surface, zero device impact (Q3).
4. **Full mechanical symbol + file rename** — `ExcludedProjectStore` →
   `ExcludedListStore`, `ExcludedProjectsView` → `ExcludedListsView`,
   `excludedProjectTitles` → `excludedListTitles`, `availableProjects` →
   `availableLists`, `onExcludedProjectsChanged` → `onExcludedListsChanged`,
   `setExcludedProjectTitles` → `setExcludedListTitles`,
   `refreshExcludedProjectTitles` → `refreshExcludedListTitles`, plus file
   renames (`ExcludedProjectStore.swift`, `ExcludedProjectStoreTests.swift`)
   and test/helper renames (`inProjectReminder` → list naming). Compiler-driven;
   no behavior change (Q4).
5. **Fix context clobbering** — `pushExcludedListTitles` re-carries
   `skippedReminderIdentifiers` exactly like `pushSortOption`/`pushShowDate`.
   Add/update unit assertions pinning both keys present in the context
   (`SkippedReminderSyncServiceTests.swift:58,319` pattern).
6. **Remove dead watch push wiring** — delete the unreachable push-hook wiring
   in `SingleThreadWatchApp.swift:48`; add a comment noting exclusions are
   phone→watch only. Keep the receive path intact (Q5: fix both).
7. **UI copy** — "Excluded Projects" → "Excluded Lists"; footer becomes
   "Excluded lists are hidden from the reminder list." Update
   `SettingsViewTests.swift:55` assertion accordingly.

## What We're NOT Doing

- **No migration/fallback code** for old UserDefaults or wire keys (per Q1=B).
- **No identifier-based filtering** — filtering stays title-string based
  (`EKCalendar.title`); duplicate list titles remain indistinguishable.
- **No bidirectional watch editing** of exclusions — sync stays phone→watch.
- **No changes to unrelated keys** (`skippedReminderIdentifiers`, `sortOption`,
  `showDate`, `showUndatedReminders`) or to `NextThingWidget`'s literals beyond
  nothing — the widget reads none of the renamed keys.
- **No new iOS UI test for exclusions** — out of scope; the existing watchOS
  UI test covers the end-to-end flow. (Flagged here so its absence isn't read
  as an oversight.)
- **No protocol versioning/handshake** for WatchConnectivity.

## Open Risks

- **Mixed-version pairing gap**: until both devices update, exclusion edits
  made on the phone won't reach an outdated watch (silent key mismatch).
  Bounded and self-healing post-update.
- **One-time user-visible reset** of exclusions on upgrade (accepted in Q1).
- **Grep completeness**: "project" appears in unrelated contexts ("shopping
  list", mock name `mockReminderInProject`); mechanical rename must be
  reviewed by eye, not blind find-replace, to avoid collateral damage.
- **Raw-literal copies** must all move together: store default param,
  `PayloadKey`, `UITestingSeed.persistedKeys`, unit-test string assertions
  (`SkippedReminderSyncServiceTests.swift:58,319`). Miss one and tests will
  catch it — but only if they're all updated first.
