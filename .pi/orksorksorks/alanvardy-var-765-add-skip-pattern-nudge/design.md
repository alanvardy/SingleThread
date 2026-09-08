# Design Discussion

## Current State

Skip state today is a shallow `Set<String>` of calendar-item identifiers with no
per-reminder count, so the "skipped more than five times" signal does not exist
yet (`ReminderStore.swift:56`). The persisted form is a flat `[String]` in the
App Group suite under `"skippedReminderIdentifiers"`, managed by
`SkippedReminderStore` (`ReminderSkip.swift:124`, `AppGroup.swift:11,16-18`), with
load/save as `stringArray ?? []` / `set` (`ReminderSkip.swift:131-137`).

All skip writing funnels through one mutation point — `applySkipSet`
(`ReminderStore.swift:493-502`) — which updates `skippedIDs`, persists via
`skipStore`, fires `onSkipSetChanged`, and is gated by `skipGeneration` for race
safety. Interactive skips are `skipCurrentReminder()` (`:314-327`, settle→apply→reload)
and the widget's synchronous `skipCurrentReminderImmediately()` (`:345-352`, no reload).
`reconcileSkipState` (`:551-562`) prunes the persisted set against in-window ids on
every `reload()`; `clearSkippedState` (`:481-486`) is the all-done reset.

Reminder operations are thin: complete (`:188-266`), delete (`:262`, iOS
`eventStore.remove` / watch local-remove + relay), add (`:333`), skip, undo. **No**
operation edits a reminder's due date or splits it — zero production sites mutate
`dueDateComponents`/`recurrenceRule`. The only edit surface today is the iOS
context-menu "View in Reminders" deep link (`ContentView.swift:407-425`).

UI idioms: iOS uses custom surfaces (`.sheet` for settings/purchase,
`ContentView.swift:245-250`), swipe actions (`:428-441`), context menus, and the
in-card dismissible "Swipe left to skip" hint (`ReminderCardView.swift:127-172`).
watchOS uses a system `confirmationDialog` for delete/refresh
(`WatchReminderView.swift:206-221`) plus persistent on-canvas Complete/Skip buttons
(`:103-137`).

Sync is a latest-wins snapshot through `SkippedReminderSyncService.pushAll()`
(`SkippedReminderSyncService.swift:167-202`), carrying `skippedReminderIdentifiers`
plus 12 other typed keys via a private `PayloadKey` enum (`:268-283`). Receive
saves into the store then fires `onSkippedIdentifiersReceived` (`:317-323`).

## Desired End State

A persistent per-reminder skip count exists as a `[String: Int]` (identifier →
count) in the App Group suite, incremented on every local interactive skip
(iOS, watch, widget). When the user skips a reminder for the 6th time, the app
surfaces a gentle nudge — an inline in-card banner that, on tap, opens a modal
with the actions **Delete**, **Reschedule** (iOS), and **View in Reminders**
(iOS deep link; watch offers **Delete** only — no deep link or date picker on
watch today). Detecting the 6th skip requires no other code change than a threshold
read; reschedule requires one new `ReminderStore` mutation (set `dueDateComponents`
+ save). Counts sync bidirectionally, latest-wins, alongside the existing skip set.

Verification: unit tests for count increment/reset/prune and threshold firing;
sync tests for the new payload key both directions; iOS UI test driving 6 skips to
show the nudge and exercising each action; watch UI test reaching the nudge and
deleting. Full gate `./scripts/test.sh` passes.

## Patterns to Follow

- **Store pattern** — every persisted scalar/collection gets a small `struct` with
  `init(defaults: UserDefaults = AppGroup.defaults, key:)` and `load()`/`save(_:)`,
  e.g. `SkippedReminderStore` (`ReminderSkip.swift:121-137`), `ExcludedListStore`
  (`ExcludedListStore.swift:4-15`), `SortOptionStore` (`SortOption.swift:22-45`),
  `CompletionCounterStore`. Build `SkipCountStore` exactly this way; existing
  `[String: TimeInterval]` dict precedent in `PendingCompletionStore.swift:17`.
- **Single mutation point** — extend the `applySkipSet`-style discipline: the count
  increments in the interactive skip paths (`skipCurrentReminder`,
  `skipCurrentReminderImmediately`) *not* inside the sync-receive/reconcile path, so
  a remotely-received skip never double-counts.
- **Snapshots via `PayloadKey`** — add `"skipCounts"` to the combined `pushAll()`
  context and the `PayloadKey` enum (`SkippedReminderSyncService.swift:268-283`);
  mirror the existing receive shape (save then hook) for counts.
- **Hybrid prompt composition** — banner follows the dismissible swipe-prompt model
  (`ReminderCardView.swift:127-172`); the modal reuses the `.sheet` (iOS) and
  `confirmationDialog` (watch) surfaces already proven in the app.
- **Localization** — shared surface copy via `SharedStrings`
  (`LocalizedString+Shared.swift`); target-specific copy as inline literals. New
  copy must land in the 6-language catalogs (`en, zh-Hans, es, ja, de, fr`).
- **Deterministic tests** — inject `InMemoryEventStore` + no-op `settle:` +
  isolated UUID-keyed `UserDefaults` (`ReminderStoreTests.swift:12`), await
  `onSkipSetChanged`/`onRemindersChanged` via `withCheckedContinuation` (`:60-75`).
- **UI-test seams** — `--seed` for deterministic multi-reminder flows
  (`UITestingSeed.swift:31`); `--ui-testing` for persistence-across-relaunch (note:
  `--seed` wipes the 23-24 persisted keys via `resetPersistedState`, including any
  `"skipCounts"` key we add).

**Patterns NOT to follow:**

- **Do NOT replicate the phone's skipped `onSkippedIdentifiersReceived` wiring**
  (phone relies on next `reload()` to converge — `AppViewModel.swift:58` vs
  `WatchAppViewModel.swift:174-178`). Counting must be authoritative on receive or
  counts silently drift. Either wire the receive hook on both platforms or guarantee
  `reconcileSkipState` re-reads the count store.
- **Do NOT hide nudge copy behind `.accessibilityHidden`** — the swipe hint is
  deliberately screen-reader-hidden (`ReminderCardView.swift:128`), but the nudge is
  actionable and must be reachable.
- **Do NOT follow the "no due-date mutation exists" gap carelessly** — reschedule is
  the first producer of a due-date write; keep it a small, tested `ReminderStore`
  method rather than spreading `EKReminder` mutation into views.

## Design Decisions

1. **Data model — standalone `SkipCountStore`**: new `[String: Int]` under
   `"skipCounts"`, following the `SkippedReminderStore` shape. Keeps the skip-set
   lifecycle (prune/reconcile/clear) decoupled from count lifecycle so a
   `reconcileSkipState` prune can't accidentally wipe counts.

2. **Nudge presentation — hybrid**: inline in-card banner (non-disruptive, matches
   the swipe-prompt idiom) whose tap opens a modal — `.sheet` on iOS,
   `confirmationDialog` on watch. Banner hints the problem; the modal carries the
   three actions without interrupting the fast-cycle flow on every 6th skip.

3. **Nudge actions — Delete + Reschedule + View in Reminders (iOS); Delete (watch)**:
   reuses `deleteCurrentReminder()`; adds one new `rescheduleReminder(identifier:to:)`
   mutation (`dueDateComponents` write + `eventStore.save` + settle + reload);
   reuses the existing iOS deep-link. Break-down ("smaller pieces") is explicitly
   deferred — creating N reminders and deleting the original has no existing code to
   build on.

4. **Threshold & trigger**: nudge fires when a reminder's count crosses `6`
   (`> 5`, per the ticket). Increment happens on the local interactive skip only;
   the store exposes `skipCount(for:)` plus an `onSkipNudgeRequested?(identifier)`
   hook so `ContentViewModel`/`WatchReminderViewModel` own the presentation.

5. **Count reset policy — reset on action / complete, prune on window exit**:
   delete, reschedule, and complete all reset (or remove) that reminder's count.
   `reconcileSkipState` prunes counts for ids absent from the current in-window
   fetched set, matching the existing skip-set prune semantics (`:561`); a recurring
   reminder naturally re-zeros when it leaves and later re-enters the window.

6. **Sync — new `"skipCounts"` key, bidirectional, latest-wins**: added to
   `pushAll()` and `PayloadKey`, sent by phone and watch, `SkipCountStore.save()`
   on receive followed by `onSkipCountsReceived` → reload (watch) / reconcile (phone).
   Widget writes counts via App Group only (no live WCSession push — same as skip
   IDs today) and never shows the nudge itself.

7. **Reschedule scope — iOS-only, non-recurring first**: reschedule sets
   `dueDateComponents` on iOS; on watch the action is omitted (no date-picker
   precedent). Recurring reminders' reschedule semantics are flagged as a risk, not
   designed here.

## What We're NOT Doing

- **Break-down** ("smaller pieces") — deferred to a follow-up ticket; no create-many
  / split / delete-original machinery exists to build on.
- **Recurrence-aware reschedule** — editing occurrence patterns or series rules is
  out of scope; reschedule touches the simple due date only.
- **A cursor/index-based cycle** — the nudge keys off skip *count*, not a new
  position model; `.first`-of-`visibleReminders` remains the "current" reminder.
- **Nudge cadence tuning** — no re-arm/dismissal scheduling beyond "fire when the
  count first crosses 6, reset on action." Re-nudging on every later skip is out of
  scope (see risks).
- **Widget nudge UI** — the widget increments counts but renders no prompt; the
  nudge surfaces on the phone/watch.
- **Real WCSession end-to-end transport tests** — sync remains fake-session-tested,
  consistent with the existing suite.

## Open Risks

- **Latest-wins count races**: two devices skipping concurrently both increment their
  local count and push full snapshots; the later write clobbers the earlier
  (existing snapshot semantics). Acceptable for a nudge threshold; noted, not solved.
- **Recurring-reminder reschedule**: setting `dueDateComponents` on a reminder with a
  `recurrenceRule` may produce surprising next-occurrence behavior. Reschedule targets
  non-recurring reminders; recurring ones lean on Delete / View in Reminders.
- **Re-nudge behavior**: after firing once, an un-acted reminder skips again — does
  it re-nudge every skip or only once? Default: fire when the count first crosses 6;
  if dismissed without action, re-fire at the next multiple (e.g. every +6). Decide
  during implementation.
- **`--seed` wipes `"skipCounts"`**: `UITestingSeed.resetPersistedState`
  (`UITestingSeed.swift:58-66`) must gain the new key, or skip-count state leaks
  between seeded UI tests.
- **UI-test timing**: driving 6 skips through UI taps is slower/likely flakier than
  other flows; a `--seed`/`--ui-testing-skip-count` preset to preload counts (without
  wiping) may be warranted to keep tests deterministic.