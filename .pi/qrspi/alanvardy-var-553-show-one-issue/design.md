# Design Discussion

## Current State

SingleThread reads the user's Reminders via EventKit and shows a **list** of
qualifying reminders. The data path is a three-layer chain:

- **`ReminderStore`** (`ReminderStore.swift:37-45`) — a `@MainActor @Observable
  final class` owning one `EKEventStore` (`:42`) and exposing
  `private(set) var accessStatus` + `private(set) var reminders: [EKReminder]`
  (`:44-45`). `load()` (`:47-68`) handles authorization, builds a
  `predicateForIncompleteReminders` (`:63-66`), and fetches via a
  `withCheckedContinuation` wrapper (`:90-99`).
- **`ContentView.visibleReminders`** (`ContentView.swift:35-51`) — a *derived*
  computed property that `compactMap`s over `reminderStore.reminders`, keeping
  only incomplete overdue/due-today items via the pure `dueStatus` classifier
  (`ReminderFilter.swift:15-31`), then sorts ascending by due date (`:50`).
- **`ReminderRow`** (`ContentView.swift:86-97`) — renders title + formatted due
  date, red when `.overdue`.

The store is injected at the app root via `.environment(reminderStore)`
(`SingleThreadApp.swift:15-18`, `:23`) and read with `@Environment` in the view
(`ContentView.swift:32`). Loads happen on `.task` (`:18-20`) and on scene-active
(`:21-27`). Access states render as `ProgressView` / `ContentUnavailableView`
(denied) / `ContentUnavailableView` (empty) / `List`+`ForEach` (`:53-77`).

**The critical gap:** the app *requests* full read-write access
(`ReminderStore.swift:103`) but has **no write path** — no
`eventStore.save(_:commit:)` anywhere, and `isCompleted` is only ever read into
the classifier (`ReminderFilter.swift:20`; `ContentView.swift:42`). `reminders`
is `private(set)` (`ReminderStore.swift:45`).

macOS wraps content in a `NavigationSplitView` with a static
`Text("Select a reminder")` detail (`ContentView.swift:103-108`); iOS is a bare
passthrough (`:109-111`). There are no centering primitives in use — layout
relies on system containers (Q5 of research).

## Desired End State

The app shows **exactly one** overdue/due-today reminder at a time, centered on
screen in a rounded-rect card, with a **Complete** button at the bottom.
Tapping Complete:

1. Marks that reminder `isCompleted = true` and persists via
   `eventStore.save(reminder, commit: true)`.
2. On success, removes it from the in-memory `reminders` array, so the derived
   "current" reminder becomes the next overdue/due-today reminder instantly.
3. On failure, shows a short error message and does **not** advance.

Completing the last qualifying reminder lands on the existing empty state
(`ContentView.swift:64-65`). The change must persist to the system Reminders
store (verifiable by relaunching / checking the Reminders app).

Verify by:
- Build passes on `iPhone 17` simulator and a macOS destination.
- Exactly one reminder renders, centered, with a bottom Complete button.
- Completing advances to the next; completing the last shows the empty state.
- The completed reminder is gone after app relaunch (persistence confirmed).
- Denied / not-determined / empty states still render correctly.
- `./scripts/test.sh` is green (Swift Testing + SwiftFormat + SwiftLint).
- Save-failure path shows an error and keeps the current reminder.

## Patterns to Follow

- **`@MainActor @Observable final class` store with `private(set)` state**
  (`ReminderStore.swift:37-45`) — the write method joins this store, not a new
  object. State stays observable so the view re-renders on removal.
- **Derived display data, not stored state** (`ContentView.swift:35-51`) — the
  "current" reminder is `visibleReminders.first`, recomputed each render. No
  index/cursor to keep in sync.
- **`ContentUnavailableView` for empty/denied states** (`ContentView.swift:58-65`)
  — reuse the existing "No overdue or due-today reminders" empty state for the
  post-completion case.
- **Lifecycle-driven loads** — keep `.task` + `.onChange(of: scenePhase)`
  (`ContentView.swift:18-27`) untouched.
- **Pure classifier stays put** (`ReminderFilter.swift:15-31`) — no changes to
  `dueStatus`; its `DueStatus` enum (`:10-13`) drives the overdue red styling.
- **`Date.FormatStyle`** for the due-date text (`ContentView.swift:92`).
- **`#if os(...)`** platform guards as used today (`ContentView.swift:72-74`).
- **Swift Testing** (`SingleThreadTests.swift:15-86`) for any new pure logic
  (none expected; the write path is EventKit-coupled and verified manually).

Do **not** follow:
- The static `NavigationSplitView` + `Text("Select a reminder")` detail
  (`ContentView.swift:103-108`) — removed; a single centered card has no sidebar.
- The macOS `navigationSplitViewColumnWidth` modifier (`ContentView.swift:72-74`)
  — dies with the split view.
- The `List`+`ForEach` of all reminders (`ContentView.swift:67-70`) — replaced by
  a single-card layout; don't keep list scaffolding around it.
- Don't introduce stored "current index" state — the codebase has no such
  pattern and it would desync after `load()` on scene-active.

## Design Decisions

1. **Completion write-back — save then local removal (Option A)**:
   Add `ReminderStore.complete(_ reminder: EKReminder) async throws` that sets
   `reminder.isCompleted = true`, calls `try eventStore.save(reminder, commit: true)`,
   and only on success removes the reminder from `reminders`. Local removal
   gives instant advance with no refetch/flicker; the store already owns
   `reminders` and is the right place for the first mutation path.

2. **"Current" reminder — derived (Option A)**: a computed
   `currentReminder: VisibleReminder? { visibleReminders.first }`. Matches the
   existing derived-data pattern (`ContentView.swift:35-51`); after removal the
   sorted remainder's `.first` is automatically the next overdue/due-today item.

3. **Save-failure handling — minimal (Option A)**: the `Complete` action
   `do/catch`es the save; on failure it sets a transient error state surfaced as
   a short inline message/alert and does not remove the reminder, so the current
   card stays for a retry. Optimistic advance (Option B) is rejected because a
   non-persisted completion contradicts the task's "write back to Reminders."

4. **macOS layout — drop the split view (Option A)**: `NavigationViewWrapper`
   becomes a plain passthrough on all platforms (or is deleted outright; its
   only remaining job was the split view). The centered card renders in the full
   window on macOS, identical to iOS.

5. **Centered card presentation (Option B)**: a `VStack` of
   `Spacer` / reminder card / `Spacer` / `Complete` button, with `.padding()`.
   The reminder (title + formatted due date, red when `.overdue`) sits in a
   rounded-rect card using a subtle material fill (`.regularMaterial` +
   `.clipShape(RoundedRectangle(...))`). The `Complete` button is disabled while
   a save is in flight to prevent double-taps.

6. **Refresh strategy unchanged**: load on `.task` and on scene-active
   (`ContentView.swift:18-27`). Because `predicateForIncompleteReminders`
   (`ReminderStore.swift:63-66`) excludes completed items, a background reload
   cannot resurrect a just-completed reminder.

7. **Scope of the reminder set unchanged**: still only incomplete overdue /
   due-today reminders (`ReminderFilter.swift:15-31`). No future/upcoming
   reminders, no completed-reminder history.

## What We're NOT Doing

- No list view of reminders anywhere (the `List`/`ForEach` is removed).
- No create / edit / delete / reschedule / snooze of reminders.
- No manual reordering or "skip" of the current reminder.
- No upcoming/future reminders — still excluded by `dueStatus`.
- No stored "current index" / cursor state.
- No optimistic UI on save failure (we don't advance unless the save succeeded).
- No SwiftData involvement — EventKit remains the single source of truth.
- No visionOS-specific work; no changes to `ReminderFilter` or its tests.
- No offline cache of reminders.

## Open Risks

- **`save(_:commit:)` is the codebase's first write** — needs manual verification
  on device/simulator with real Reminders data; CI cannot exercise it.
- **Sync/conflict errors** — the minimal error UX means a failed save leaves the
  reminder current and requires the user to retry; there's no automatic retry.
- **Material card styling on macOS** — `.regularMaterial` renders differently on
  macOS vs iOS; needs a visual check on both destinations.
- **Wide macOS windows** — a single centered card in a large window may look
  sparse; acceptable for now, revisit if it feels broken.
- **Ordering after removal** — advance correctness depends on the remaining
  array staying sorted (it does: removal preserves order); no re-sort needed.
- **TCC prompts not automatable** — permission flows stay outside the test
  scaffold, as today.
