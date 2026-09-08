# Design Discussion

Decision record for VAR-620: add a user-selectable "sort by" preference to the
settings screen so the user controls reminder ordering everywhere "the current
reminder" is derived.

## Current State

Ordering is a single hard-coded comparator with one production call site.

- `ReminderSort.areInIncreasingOrder(_:_:)` (`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift:7`)
  is the only ordering path. Tiers: priority rank (`:8-19`, via
  `ReminderPriority.rank(for:)` `ReminderSkip.swift:72-79`) → due date soonest
  first, dated before undated (`:21-32`) → title tiebreak (`:34`).
- `ReminderStore.visibleReminders` (`ReminderStore.swift:59-63`) filters skipped
  IDs then sorts; this is the sole consumer of the comparator (`:62`). "Current
  reminder" is simply `visibleReminders.first`, read by every surface:
  `ContentView.swift:230,302`, `WatchReminderView.swift:66`,
  `NextThingWidget.swift:59`, `ReminderIntents.swift:17-21,40-47`, and
  `ReminderStore.swift:101-104,136-157`.
- Preferences are `String, CaseIterable` enums in the app target
  (`AppearanceMode.swift:8-40`, `TextSize.swift:8-48`) persisted via
  `@AppStorage` string literals on `ContentView` (`ContentView.swift:115-127`).
  They carry SwiftUI computed props (`colorScheme`/`dynamicTypeSize`/
  `systemImage`/`title`) and are handed to `SettingsView` as `Binding`s
  (`ContentView.swift:68-79`) into state-free `Picker`/`Toggle` rows
  (`SettingsView.swift:11-71`).
- The only Core-side persisted value is the skip list
  (`SkippedReminderStore`, `ReminderSkip.swift:111-133`), stored in the App
  Group suite (`AppGroup.swift:13-14`) and synced phone↔watch by
  `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:57-64,81-89`).
- `SingleThreadCore` is compiled into four processes (app, watch, widget,
  intents), each with its own `ReminderStore`, EventKit fetch, and UserDefaults
  access. The widget holds the App Group entitlement (`project.pbxproj:844,872`);
  the watch does not (`project.pbxproj:787-833`), so `AppGroup.defaults` falls
  back to local `.standard` there (`AppGroup.swift:14`).

## Desired End State

A "Sort By" picker in Settings with three options — **Priority** (today's
compound order), **Due Date** (soonest first), **Title** (A→Z). The choice is a
persisted preference that reaches the phone, macOS, widget, intents, **and**
watch, so `visibleReminders.first` reflects it in every process.

Verification:

- Unit: option-by-option comparator coverage in `ReminderSortTests` +
  `ReminderStoreTests` asserting `visibleReminders` order per option.
- View: `SettingsViewTests` `String(describing: view.body)` asserts "Sort By";
  enum tests cover raw values + presentation props.
- Manual/UI: change sort on iPhone, confirm widget + watch show the same first
  reminder; confirm default install keeps today's order (no behavior change).

## Patterns to Follow

- **Pure-core enum + app-target presentation.** `ReminderPriority`
  (`ReminderSkip.swift:50-79`) keeps logic in Core with no SwiftUI, while
  `AppearanceMode`/`TextSize` add `title`/`systemImage` in the app target. The
  new `SortOption` follows both halves.
- **Storage seam via a small store struct.** `SkippedReminderStore`
  (`ReminderSkip.swift:111-133`) is a thin `defaults`+`key` wrapper defaulting to
  `AppGroup.defaults`. Mirror it as `SortOptionStore` rather than reading user
  defaults inline in `ReminderStore`.
- **Layers wire hooks; Core stays storage-agnostic.** `onSkipSetChanged` /
  `onRemindersChanged` are assigned by the app layer
  (`SingleThreadApp.swift:26-43`); Core never reads `UserDefaults.standard`.
  `ReminderStore` should learn the sort via injection, not by reading defaults.
- **WatchConnectivity channel reuse.** Extend `SkippedReminderSyncService` (or a
  sibling) rather than introducing a second WCSession/context pipeline; it already
  owns the session, delegate, and payload-key enum
  (`SkippedReminderSyncService.swift:57-64,81-89`).
- **Swift Testing + `String(describing: view.body)`** conventions
  (`ReminderSkipTests.swift:237-304`, `SettingsViewTests.swift:7-36`).
- **Do NOT follow:** duplicating a key as a raw literal across layers — today
  `"allowsLandscape"` is duplicated (`ContentView.swift:122` vs
  `AppDelegate.swift:34,36`). Use `SortOptionStore`'s key and `@AppStorage`
  constant together; add a single shared constant if both must reference it.

## Design Decisions

1. **Option set: three sorts, default Priority.** `SortOption` cases `.priority`,
   `.dueDate`, `.title`, default `.priority` = current behavior so existing users
   see no change. Deterministic full orders: `.priority` = rank → date → title
   (identical to `ReminderSort.swift:8-34`); `.dueDate` = date (dated before
   undated) → title; `.title` = case-insensitive title → date as tiebreak.

2. **`SortOption` enum lives in `SingleThreadCore` (pure), presentation in the
   app target.** Core gets `enum SortOption: String, CaseIterable, Sendable` and
   the comparator moves under it (see #3). `title`/`systemImage` are added in an
   extension in `SingleThread/` (e.g. `SortOption+Presentation.swift`), matching
   how Core's `ReminderPriority` avoids SwiftUI while `AppearanceMode` provides it.

3. **Comparator API: option-aware, backward-compatible.** Add
   `ReminderSort.areInIncreasingOrder(_:_:using option: SortOption) -> Bool`;
   keep the existing 2-arg form delegating to `.priority` so the test helper
   `titles(of:)` (`ReminderSkipTests.swift:298`) and any callers keep compiling.
   `visibleReminders` passes `store.sortOption` (`ReminderStore.swift:62`).

4. **`ReminderStore` learns the sort via an injectable property, not defaults.**
   `public var sortOption: SortOption = .priority` on `ReminderStore`; changing it
   re-sorts `visibleReminders` automatically (it is `@Observable`). A
   `setSortOption(_:)` method assigns and fires two hooks — `onSortOptionChanged`
   (push to watch) and `onRemindersChanged` (reload widget timelines, reusing the
   existing `WidgetCenter` wiring at `SingleThreadApp.swift:40-43`). Layers inject
   the value at launch and on change; Core stays free of `UserDefaults` reads.

5. **Persistence: App Group via `SortOptionStore`.** New
   `SortOptionStore(defaults: UserDefaults = AppGroup.defaults, key: String = "sortOption")`
   with `load() -> SortOption` (default `.priority`) and `save(_:)`, mirroring
   `SkippedReminderStore`. The phone writes it through
   `@AppStorage("sortOption", store: AppGroup.defaults)` on `ContentView` so the
   widget (entitled, `project.pbxproj:844,872`) reads the shared value directly.

6. **Cross-process propagation: widget/intents read App Group; watch gets it via
   WatchConnectivity.** `NextThingProvider.makeEntry` (`NextThingWidget.swift:51-60`)
   and both intents (`ReminderIntents.swift:17-21,40-47`) call
   `store.setSortOption(SortOptionStore().load())` before `reload()`. The watch
   (no entitlement) relies on sync: extend the WCSession context with a
   `sortOption` payload key; the iPhone pushes on `onSortOptionChanged`, the watch
   receives it, saves via its local `SortOptionStore()` (which falls back to
   `.standard`), and applies `store.setSortOption(_:)` through a
   `service.onSortOptionReceived` hook (mirrors `onCompleteReminderReceived`,
   `SingleThreadApp.swift:27-29`).

## What We're NOT Doing

- No sort **direction** toggle (ascending/descending) — out of scope for "sort by."
- No "Created"/"Modified" sort key — `creationDate` is unused/unproven in this
  codebase and not part of the chosen option set.
- No per-list/multi-list ordering UI; the picker is a single global preference.
- No changes to the EventKit eligibility window (`ReminderDateFilter`,
  `ReminderStore.swift:159-167`) — sorting only reorders the already-filtered set.
- No new WatchConnectivity service; we extend the existing one.
- No migration story: pre-existing installs default to `.priority`, which is
  exactly today's behavior.

## Open Risks

- **Combined application context.** `SkippedReminderSyncService.pushSkipIDs`
  currently sends a context containing only the skip key
  (`SkippedReminderSyncService.swift:57-64`). Adding sort means the push must emit
  a context with *both* keys; otherwise a skip push could drop/override the sort
  value on the watch. `updateApplicationContext` is latest-wins, so the sync
  service likely needs to hold combined state and push it atomically.
- **`@Observable` + side-effect timing.** `setSortOption` fires hooks; callers
  assigning at launch must do so before the command-center `WidgetCenter` wiring
  runs, or guard against redundant pushes (e.g. skip when unchanged) on every
  startup.
- **Mac's WatchConnectivity absence.** macOS uses the same `@AppStorage` +
  `SortOptionStore` read but has no watch sync; ensure the `#if os(iOS)` guards in
  the sync service (`SkippedReminderSyncService.swift:3-4`) keep macOS compiling.
- **Watch read-only EventKit.** Watch surfaces apply the sort only to what its
  own fetch returns (`WatchReminderView.swift:66`); if fetch sets ever diverge
  between phone and watch, "first" can still differ even with a shared sort.
- **`systemImage` untested** (existing gap for `AppearanceMode`/`TextSize`); new
  `SortOption` presentation props should get coverage to avoid repeating it.