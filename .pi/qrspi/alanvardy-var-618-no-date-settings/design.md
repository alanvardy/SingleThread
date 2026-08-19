# Design Discussion — "Show tasks with no date"

## Current State

- The settings screen exposes 4 preferences, all **root-level `@AppStorage` in
  `ContentView`** (`ContentView.swift:115-127`), injected into `SettingsView` as
  `@Binding`s (`SettingsView.swift:11-31`, `:75-80`). No `@AppStorage` exists in
  `SingleThreadWatch/`, `SingleThreadWidget/`, or `SingleThreadCore/`.
- `ReminderStore.reload(clearSkipped:)` fetches through a **single predicate
  with a non-nil date range** (`ReminderStore.swift:164-167`):
  `[overdueCutoff, endOfToday]` = `[30 days ago 00:00, today 23:59:59]`
  (`ReminderDateFilter.swift:28-49`). **Undated reminders are never fetched** —
  EventKit returns them only for a `nil`/`nil` predicate, which no call site
  passes. There is no post-fetch date filtering today (`reminders = fetched`,
  `ReminderStore.swift:169`).
- The current reminder is `visibleReminders.first`, where
  `visibleReminders` = skip-ID filter + `ReminderSort` (`ReminderStore.swift:59-63`).
  `ReminderSort` is priority → due date → title (`ReminderSort.swift:6-33`); a
  nil-`dueDateComponents` reminder sorts **after dated reminders at the same
  priority**, then falls to title order. Undated display code already tolerates
  nil: the date line is conditionally hidden in every surface
  (`ContentView.swift:242-243`, `WatchReminderView.swift:155`,
  `NextThingWidget.swift`).
- Cross-surface sync today: the **only** shared state is the skip-ID array —
  App Group (`"skippedReminderIdentifiers"`, `ReminderSkip.swift:111-128`,
  suite `AppGroup.swift:8`) for phone↔widget, and WatchConnectivity
  `updateApplicationContext` for phone↔watch (`SkippedReminderSyncService.swift:55-63`,
  receive `:79-92`). Everything else (fetch, sort, pick-first) is recomputed
  locally on each surface.

## Desired End State

A "Show tasks with no date" `Toggle` in Settings. When ON, reminders with
`dueDateComponents == nil` appear in the app, on the watch, and in the widget,
interleaved with dated reminders by the existing priority/date/title sort. When
OFF, behavior is byte-for-byte today's. The preference defaults to **off**,
persists, and is shared iOS + macOS (parallel to `showMicrophoneButton`).

**Verification:** a reminder with no due date is visible when ON (in the phone
app list, watch, and widget) and absent when OFF; the toggle survives relaunch
and propagates phone→watch; dated reminders outside the current window never
appear regardless of the toggle.

## Patterns to Follow

- **`@AppStorage` in `ContentView` + `Binding`-inject into `SettingsView`** —
  every existing preference uses this (`ContentView.swift:115-127`,
  `SettingsView.swift:11-31`). Add the toggle the same way.
- **App Group for phone↔widget, `updateApplicationContext` for phone↔watch** —
  the exact dual path `"skippedReminderIdentifiers"` already uses
  (`ReminderSkip.swift:111-128`, `SkippedReminderSyncService.swift:55-92`).
- **Single source of truth for "current reminder"** — every surface derives
  `visibleReminders.first` locally (`ReminderStore.swift:59-63`); do not
  synthesize or sync a "current reminder" payload.
- **`loadsReminders`-gated store + pre-populated init seams** for tests/previews
  (`ReminderStore.swift:13-33`, `ContentView.swift:13-36`); `--ui-testing` launch
  gate (`SingleThreadApp.swift:16`). All new logic must be seedable this way.
- **Pure `nonisolated enum` date helpers with `calendar`/`now` injection** for
  testability (`ReminderDateFilter.swift`); the new window predicate belongs here,
  tested in `ReminderDateFilterTests` (`SingleThreadTests.swift:26-76`).

**Patterns NOT to follow / to flag:**
- Do **not** rely on App Group to reach the **watch** — the watch target has no
  `CODE_SIGN_ENTITLEMENTS`, so its `AppGroup.defaults` silently falls back to
  `.standard` (research Q4; `AppGroup.swift:13-15`). Watch gets the toggle via
  WatchConnectivity, not App Group.
- Do **not** issue two independent `updateApplicationContext` payloads;
  each call replaces the whole dictionary, so a toggle push would clobber the
  skip-IDs (`SkippedReminderSyncService.swift:55-63`). Push one combined context.
- Do **not** use bare `@AppStorage("…")` (`.standard`) for the toggle value if
  the widget must read it — use `@AppStorage(_, store: AppGroup.defaults)`.

## Design Decisions

1. **Fetch strategy — nil/nil predicate + window filter (ON only).** When ON,
   `reload()` fetches `predicateForIncompleteReminders(withDueDateStarting: nil,
   ending: nil, calendars: nil)` and then keeps a fetched reminder iff
   `dueDateComponents == nil` **or** its date lies in `[overdueCutoff,
   endOfToday]`. When OFF it keeps the existing range predicate unchanged
   (`ReminderStore.swift:164-167`). The filter runs *before*
   `reminders = fetched` so skip pruning and empty-state checks see the same
   bounded set they do today. The `EventKitStoring` protocol already takes
   `Date?`/`Date?` (`EventKitStoring.swift:11-16`) — no protocol change; the
   nil/nil case is new to `FakeEventStore`.

2. **Preference — `@AppStorage("showUndatedReminders", store: AppGroup.defaults)`
   = false.** Declared in `ContentView` alongside the others, bound into
   `SettingsView` as a `Binding` and rendered as a `Toggle` next to "Show
   Microphone" (`SettingsView.swift:57-59`). The `store: AppGroup.defaults`
   differs from the other four preferences (which use `.standard`) because the
   widget must read the same value; App Group is the only shared container.

3. **Store plumbing — `public var showsUndatedReminders = false` on
   `ReminderStore`, read by `reload()`.** `ContentView` sets it in `.task`
   before `store.start()` and in `.onChange(of: showUndatedReminders)` before
   `await store.reload()`. `reload()`'s signature is unchanged, so every
   existing caller (`start()`, completion, add, pull-to-refresh) inherits the
   flag. Watch and widget set it before their own `reload()`s (below).

4. **Ordering — keep `ReminderSort` unchanged.** Undated reminders interleave
   by priority, sort after dated at equal priority, then alphabetically
   (`ReminderSort.swift:6-33`). Already covered by
   `visibleRemindersSortsDatedBeforeUndated` / `sortsDatedBeforeUndated`
   (`ReminderStoreTests.swift:58-72`, `ReminderSkipTests.swift:274-279`).

5. **Cross-surface scope — phone is source of truth; watch + widget mirror.**
   - **Phone → watch:** extend `SkippedReminderSyncService` to push one
     combined context `{skippedReminderIdentifiers, showUndatedReminders}` and
     add a receive hook for the toggle. `SingleThreadWatchApp` wires it to
     `store.showsUndatedReminders = value` + `await store.reload()`. The watch
     has no settings UI; it only receives.
   - **Phone → widget:** `store.reload()` already fires `onRemindersChanged` →
     `WidgetCenter.shared.reloadAllTimelines()` (`SingleThreadApp.swift:14-37`).
     `NextThingProvider.makeEntry()` reads `AppGroup.defaults.bool(forKey:
     "showUndatedReminders")`, sets the fresh store's flag, then `reload()`
     (`NextThingWidget.swift:44-64`).
   - Phone re-pushes the combined context on *both* toggle change and skip-set
     change so the single latest-wins dictionary stays coherent.

6. **No date line / no special chrome for undated reminders.** Existing
   conditional date rendering already hides the line when `dueDateComponents`
   is nil on every surface (`ContentView.swift:242-243`,
   `WatchReminderView.swift:155`, `NextThingWidget.swift`); no new badge,
   section, or "No date" label.

## What We're NOT Doing

- Not adding a watch settings screen — watch mirrors the phone toggle only.
- Not widening the dated window (`[overdueCutoff, endOfToday]` is unchanged);
  the only addition is undated reminders, never extra dated ones.
- Not changing sort precedence, skip/complete semantics, or dictation defaults
  — undated reminders skip/complete exactly like dated ones.
- Not introducing a new sync channel or payload protocol; the toggle rides the
  existing App Group + WatchConnectivity channels used by skip IDs.
- Not persisting the toggle in `.standard` UserDefaults (must be App Group for
  the widget).

## Open Risks

- **Unbounded fetch when ON:** the nil/nil predicate returns *all* incomplete
  reminders; the window filter bounds what's *shown* but not what's *fetched*.
  Acceptable for typical datasets; flag if sync/perf on large libraries matters.
- **High-priority undated can outrank low-priority dated** under Q4 ordering
  (`ReminderSort.swift:13-30`). Accepted; revisit only if product wants
  "all undated last" (would need a sort change + new tests).
- **Watch convergence timing:** the watch starts dated-only until the combined
  WC context arrives; `updateApplicationContext` auto-delivers on (re)connect,
  the same convergence property skip IDs rely on today (research Q4 "Open Areas").
- **Widget App Group read:** the widget reads the toggle via the shared App
  Group; `.standard` writes would be invisible to it. The `@AppStorage(store:)`
  choice (Decision 2) is load-bearing — verify in a widget test/run.
- **Skip-list interaction:** an undated skipped reminder is only in `reminders`
  (and thus pruneable/restorable) while the toggle is ON; toggling OFF prunes
  its skip-ID like any out-of-window reminder. No code change, but note the
  UX consequence.