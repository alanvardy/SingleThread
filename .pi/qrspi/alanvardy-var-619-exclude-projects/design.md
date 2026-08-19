# Design Discussion — Exclude Projects (VAR-619)

## Current State

**Settings screen.** `SettingsView` (`SingleThread/SettingsView.swift:7`) owns no state
(`:5-6`); every preference is a `@Binding` fed from `ContentView`'s `@AppStorage`
(`ContentView.swift:115-127`). It is a `Form` in a `NavigationStack` with a `Done`
toolbar button (`SettingsView.swift:35-36,61-67`), uses `Picker` over `CaseIterable`
enums and `Toggle`s (`:36-59`), and has two platform-specific initializers — iOS 4-binding
and `#else` 3-binding (`:10-30`). Previewed with `.constant(...)` (`:87-110`).

**Fetch → display.** `ReminderStore.reload()` (`ReminderStore.swift:159-181`) builds an
EventKit predicate for *incomplete* reminders in the window 30-days-ago → end-of-today
with **`calendars: nil`** (`:164-168`); the `calendars:` argument is dead — no caller
ever supplies a restricted list. The show/hide decision happens in
`visibleReminders` (`:59-63`): skip-exclusion (`!skippedIDs.contains(...)`) then sort.
`visibleReminders.first` drives both the phone (`ContentView.swift:142,230,302`) and the
watch (`SingleThreadWatch/WatchReminderView.swift:57,66`).

**Calendar surface.** No calendar/list model exists; `EKCalendar` appears only as a type,
never enumerated (`EventKitStoring.swift:14-17`). The only calendar touch is write-path
`defaultCalendarForNewReminders()` (`EventKitStoring.swift:57`). `EKSource`,
`calendarIdentifier`, and `calendars(for:)` are absent from the codebase.

**Skip persistence (the model to mirror).** `SkippedReminderStore` is a thin `UserDefaults`
wrapper over App Group key `"skippedReminderIdentifiers"` (`ReminderSkip.swift:111-133`;
`AppGroup.swift:8,13-14`). `ReminderStore` owns `skippedIDs: Set<String>` (`:41`) and a
`skipStore` (`:210`); `ReminderSkipLogic.resolve` prunes stale IDs against fetched reminders
(`ReminderSkip.swift:12-15`); mutations go through `applySkipSet` which saves + fires
`onSkipSetChanged`/`onRemindersChanged` (`ReminderStore.swift:222-226`).

**Cross-surface sync.** `SkippedReminderSyncService` pushes the full skip array via
`updateApplicationContext` latest-wins (`SkippedReminderSyncService.swift:56-63`, receive
`:79-89`), keyed by `PayloadKey.skippedReminderIdentifiers` (`:118-121`). Wired on the
phone and watch (`SingleThreadApp.swift:17-41`, `SingleThreadWatchApp.swift:14-20`). The
watch has **no App Group entitlement** (`project.pbxproj:785-833`), so it resolves to
`.standard` defaults — it learns skip state only through this sync. The widget reads the
App Group directly and builds a short-lived `ReminderStore` per operation
(`SingleThreadWidget/NextThingWidget.swift:51-65`).

## Desired End State

A "Projects" section in `SettingsView` lists the user's reminder lists (from EventKit
`calendars(for: .reminder)`), each a toggle; selected lists are *excluded*. Reminders in
excluded projects are hidden from `visibleReminders` everywhere — phone, widget, watch —
while raw `reminders`, skip behavior, completion, and dictation are untouched. Exclusions
persist across launches (App Group `UserDefaults`) and sync phone↔watch over
WatchConnectivity.

**Verification checklist.**
- Excluding a project hides its reminders immediately after `reload()` (phone `ContentView`,
  widget `makeEntry`, watch `WatchReminderView`).
- Exclusion persists after relaunch; survives the App Group / `.standard` fallback
  (`AppGroup.swift:13-14`).
- Renames/orphans: selecting a project by title, then renaming it, leaves a harmless stale
  title in defaults (never existing → never matches) — documented, not "fixed".
- Widget with all projects excluded shows `.allDone`, not a crash
  (`NextThingWidget.swift:61-63` nil-checks `visibleReminders.first`).
- Unit tests (Swift Testing) for the new store, the `visibleReminders` filter, and the
  sync payload round-trip; existing `SettingsViewTests`/`ReminderStoreTests` still pass.

## Patterns to Follow

- **Store-owns-state, `@MainActor @Observable` hub** — `ReminderStore` is the single place
  state and mutations live (`ReminderStore.swift:5-7`); views stay thin. Exclusion state
  belongs here, not in the view.
- **Protocol seam over EventKit** — `EventKitStoring` (`EventKitStoring.swift:7-8`) is how
  `ReminderStore` talks to Apple APIs; the new `calendars(for:)` read must go through it and
  its `FakeEventStore`, following the existing `refreshSourcesIfNecessary`/`makeReminder`
  split (`EventKitStoring.swift:25-33`).
- **Thin `UserDefaults` struct wrapper** — mirror `SkippedReminderStore`
  (`ReminderSkip.swift:111-133`), including the `defaults:key:` init parameters that tests
  exploit for UUID-keyed isolation.
- **Hook-based fan-out, not direct cross-surface calls** — `onSkipSetChanged` /
  `onRemindersChanged` (`ReminderStore.swift:49-57`) are the only plumbing to widgets and
  WatchConnectivity (`SingleThreadApp.swift:34-41`). Add `onExcludedProjectsChanged` the same
  way.
- **Stateless settings + platform initializers + `.constant` previews** — `SettingsView`
  takes bindings only (`SettingsView.swift:75-80,10-30`, previews `:87-110`); add the new
  binding(s) to both initializers rather than inventing local state.
- **Preview/test init pre-populates state without touching EventKit** —
  `ReminderStore(loadsReminders:reminders:skippedIDs:authorizationStatus:)`
  (`ReminderStore.swift:23-34`); extend it with excluded titles so views/tests need no real
  store.
- **Swift Testing conventions** — `@MainActor`, `@Suite(.serialized)`, `#expect`,
  `#if !os(watchOS)` mirrors (`EventKitStoringTests.swift:111,186`; `ReminderStoreTests.swift:6`),
  `FakeEventStore` recording (`EventKitStoringTests.swift:8-103`).

**Deliberate divergences to flag.**
- **Title-as-identity, not `calendarIdentifier`** — the skip feature uses stable identifiers
  (`ReminderSkip.swift:19-23`); we diverge (decision 1) for human-readable, cross-device-local
  behavior. This is the one place we do NOT follow the existing convention.
- **Do NOT resurrect the dead `calendars:` predicate argument** — filtering stays in
  `visibleReminders` (decision 2), even though the parameter sits there unused.
- **Do NOT copy the reload-prune-does-NOT-save behavior** (`ReminderStore.swift:175-179`) —
  that's an existing wart. Exclusion writes flush to defaults immediately (decision 7).
- **Do NOT replicate the `nonisolated(unsafe)` hook** in the sync service — follow its own
  documented ban (`SkippedReminderSyncService.swift:60-70`): assign hooks before `activate()`.

## Design Decisions

1. **Identity = calendar title** (Q5 → B): persist human-readable list titles in
   `"excludedProjectTitles"`. Readable/debuggable in defaults. Trade-off accepted: duplicate
   titles collapse into one selection, renames orphan an exclusion; see Open Risks.
2. **Filter in `visibleReminders`** (Q1 → A): add `!excludedProjectTitles.contains($0.calendar?.title ?? "")`
   alongside the skip filter (`ReminderStore.swift:59-63`). Naive-nil handling: reminders with
   no calendar (title nil) are always shown. Watch/widget inherit it for free.
3. **Enumerate projects via a new `EventKitStoring.calendars(for:)`** (Q2 → A): add the
   read to the protocol + `EKEventStore` conformance, expose `availableProjects: [String]`
   (sorted, deduplicated titles) from `ReminderStore`, populated during `reload()`.
   `FakeEventStore` gains a `returnedCalendars` config. Shows empty lists, which
   deriving-from-reminders would miss.
4. **Parallel `ExcludedProjectStore`** (Q3 → A): a new struct mirroring
   `SkippedReminderStore` (`UserDefaults = AppGroup.defaults`, key `"excludedProjectTitles"`),
   owned by `ReminderStore` as `excludedProjectTitles: Set<String>` alongside `skippedIDs`.
5. **Sync excluded titles over WatchConnectivity** (Q4 → A): extend `SkippedReminderSyncService`
   with an `ExcludedProjectStore` param, `pushExcludedProjectTitles(_:)`, a new
   `PayloadKey.excludedProjectTitles`, and receive handling in `didReceiveApplicationContext`.
   Wire `store.onExcludedProjectsChanged → pushExcludedProjectTitles` on both devices
   (mirroring `SingleThreadApp.swift:34`).
6. **Multi-select UI stays stateless**: a `Section("Excluded Projects")` in `SettingsView`'s
   `Form` rendering `ForEach` toggles over `availableProjects`, bound to a
   `Binding<Set<String>>` passed from `ContentView`; each toggle inserts/removes the title
   and calls `store.setExcludedProjectTitles(_:)`. New bindings added to **both** platform
   initializers + previews.
7. **Write-through persistence**: `setExcludedProjectTitles(_:)` always
   `excludeStore.save(...)` and fires `onExcludedProjectsChanged` + `onRemindersChanged`
   immediately — no stale-in-defaults-vs-memory divergence (unlike the skip reload prune).

## What We're NOT Doing

- **No EventKit predicate filtering** — the `calendars:` argument stays `nil`; the fetch
  still returns all incomplete reminders in the window.
- **No calendar/`EKSource` model** — we expose only titles (`[String]`), not a full
  list/calendar domain model; that's YAGNI for this feature.
- **No change to raw `reminders`** — `.count`/`.isEmpty` keep their current meaning. The
  widget's `.empty` vs `.allDone` boundary shifts slightly (all-excluded ⇒ `.allDone`),
  which is acceptable, not "fixed".
- **No rename/duplicate reconciliation** — title collisions and renames are accepted,
  documented, not auto-migrated.
- **No settings screen on watchOS** — the watch consumes exclusions via sync only.
- **No change to watch's read-only EventKit posture** — watch still fetch-only; it filters
  locally by title.
- **No project-list sync** — only the *excluded-title set* crosses devices; each device
  enumerates its own lists from EventKit.

## Open Risks

- **Duplicate titles**: two lists named e.g. "Work" become one toggle; excluded ⇒ both
  hidden. Non-unique identity is inherent to title-based selection.
- **Renames**: renaming an excluded list orphans the stored title; it lingers harmlessly in
  defaults (never matches) until the user re-selects. No cleanup is planned.
- **Title drift across devices**: local "On My iPhone" lists are entirely device-local, so a
  synced exclusion of one won't resolve on the other (matches skip-list behavior for
  device-local calendars).
- **Nil calendar**: `EKReminder.calendar` is optional; current plan always *shows* such
  reminders. Rare but possible for partially-deleted/recurrence-edge reminders.
- **Watch naming**: attaching a second `UserDefaults` store to a class named
  `SkippedReminderSyncService` is slightly misleading; a rename to e.g.
  `ReminderExpressSyncService` is optional cleanup, deferred to avoid churn.
- **Enumeration timing**: `availableProjects` loads in `reload()`; if settings opens before
  the first fetch resolves, the section is momentarily empty until `reload()` completes.