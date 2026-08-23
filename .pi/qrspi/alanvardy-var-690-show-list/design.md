# Design — VAR-690 "Show list"

## Current State

**Reminder data flow.** `ReminderStore` holds raw `[EKReminder]`
(`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:47`); every surface renders
`visibleReminders.first`. `ReminderDisplay` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:11-16`)
has four fields (title, notes, dueDate, priorityMarker) populated in `init(reminder: EKReminder)`
and is consumed **only by the widget** (`SingleThreadWidget/NextThingWidget.swift:9,:167-185`).
The iOS card (`SingleThread/ReminderCardView.swift:25-39`) re-applies the same formatters inline
against raw `EKReminder`. Field parity is maintained by hand.

**Calendar/list access.** Only two runtime `calendar.title` read sites exist, both in Core:
the exclusion filter (`ReminderStore.swift:110`) and `availableProjects`
(`ReminderStore.swift:287-291`). No rendering surface currently shows the list name.

**Boolean preferences.** All `@AppStorage` declarations live in `SingleThread/ContentView.swift`.
Shared-with-widget prefs (`showUndatedReminders`, `sortOption`, `showDate`) use
`AppGroup.defaults` (:213-220); everything else uses `.standard` (:188-211). The widget reads
prefs straight from the shared container at timeline build time (`NextThingWidget.swift:55-62`),
so App Group storage is sufficient for widget propagation — no extra refresh wiring needed.
SettingsView owns no state — pure bindings back to ContentView (`SingleThread/SettingsView.swift:58-59`).

**Labels.** "Enable action buttons" (`SettingsView.swift:162-164`, iOS-gated) and
"Show Undated" (:166-168) each occur once in app code; unit tests assert both strings
(`SingleThreadTests/SettingsViewTests.swift:53-60`). Casing across settings rows is mixed:
Title Case ("Show Microphone", "Show Date", "Allow Landscape") alongside sentence-case
"Enable action buttons".

**Test seams.** String-snapshot unit tests over `String(describing: view.body)`
(`SingleThreadTests/ShowDateTests.swift:11-23`). UI tests assert toggles persist across relaunch
using the `--ui-testing` relaunch pattern, because `--seed` wipes persisted keys
(`SingleThreadUITests/SingleThreadUITestsFlows.swift:145-170`; reset list at
`SingleThreadApp.swift:47-58`). XCUI queries match **visible labels**, not identifiers —
e.g. `app.switches["Show Date"]` (`SingleThreadUITestsFlows.swift:126-140`).

## Desired End State

1. When a reminder is displayed on the iOS card and the widget, the name of its list
   (calendar title) shows beneath/beside the existing content, styled as secondary text.
2. A new "Show list" toggle appears in iOS Settings; default **off**; persists in
   `AppGroup.defaults`; the widget honors the same key.
3. Labels renamed and casing normalized to sentence case across Settings rows.
4. Verified by: string-snapshot unit tests (row shown/hidden), preference round-trip tests
   (missing key → false), updated label assertions, and a relaunch-persistence UI test.

## Patterns to Follow

- **Populate derived fields in `ReminderDisplay.init(reminder:)`**
  (`ReminderDisplay.swift:11-16`) — this is where `listName` belongs.
- **App Group storage for any pref the widget reads** — follow `showDate` on iOS
  (`ContentView.swift:219`, `AppGroup.swift:7-15`).
- **Typed preference wrapper with explicit default + round-trip tests** — mirror
  `ShowDatePreference` (`ShowDatePreferenceTests.swift:6-40`), but default `false`.
- **Conditional card rows gated on BOTH preference and data**, as the due-date row does
  (`ReminderCardView.swift:34-38`): hide when pref off *or* calendar title nil/empty.
- **String-snapshot unit tests** for shown/hidden cases (`ShowDateTests.swift:11-23`).
- **`--ui-testing` (not `--seed`) for persistence-across-relaunch UI tests**
  (`SingleThreadUITestsFlows.swift:145-170`).

### Patterns NOT to Follow

- **Inline `EKReminder` formatting duplicated per surface** (`ReminderCardView.swift:25-39`,
  `WatchReminderView.swift:164-178`) — this duplication is why list-name display would rot;
  do not add a fifth copy.
- **Divergent per-platform storage** like watch-side `.standard` `showDate`
  (`SingleThreadWatchApp.swift:26-29`) — out of scope here, but don't extend the pattern.
- **Hardcoding new user-visible strings without checking test/XCUI dependencies** — labels
  are load-bearing for queries (`app.switches["Show Date"]`).

## Design Decisions

1. **Source of truth: extend `ReminderDisplay`** (chosen 1A). Add `listName: String?`
   populated from `reminder.calendar?.title` in `init(reminder:)`. To actually route iOS
   through it, `ReminderCardView` changes its input from `EKReminder` to `ReminderDisplay`;
   `ContentView.reminderList` wraps with `ReminderDisplay(reminder:)`
   (`ContentView.swift:342-345`) and test factories wrap their seeded reminders likewise.
   This starts the documented REMOVAL PLAN (`ReminderDateFilter.swift:6-22`) instead of
   adding a third copy of the formatting logic.
2. **Scope: iOS card + widget; watch excluded** (chosen 2B). Store `showList` in
   `AppGroup.defaults` so the widget reads it at render time (`NextThingWidget.swift:55-62`);
   gate the widget's list-name line identically. No WatchConnectivity changes — WC context
   keys stay as-is (`SkippedReminderSyncService.swift:234-241`).
3. **Default off** (chosen 3B). Missing key ⇒ `false`, preserving today's card look for
   existing users. Encode via a small typed wrapper mirroring `ShowDatePreference` but
   inverted default, plus round-trip/missing-key tests.
4. **Sentence-case normalization of all Settings row titles** (chosen 4B):
   "Allow landscape", "Show microphone", "Show date", "Show undated reminders",
   "Show action buttons" (+ section headers left as-is unless trivially inconsistent).
   Update every test asserting old strings: `SettingsViewTests.swift:53-60`,
   UI-test label checks for "Show Date" (`SingleThreadUITestsFlows.swift:126-140`).
5. **Testing shape** (agreed): snapshot unit tests for the list-name row (shown with title /
   hidden when pref off / hidden when calendar nil), preference round-trip tests,
   updated rename assertions, and one relaunch-persistence UI test using `--ui-testing`;
   add `showList` to the `--seed` reset key list (`SingleThreadApp.swift:47-58`).
6. **Widget styling**: render `listName` as secondary-style text near the date line
   (`NextThingWidget.swift:167-185`), hidden when nil or pref off; no colorized priority
   parity work in this ticket.

## What We're NOT Doing

- No watch app changes (no list name on the watch card, no WC sync of `showList`).
- No full conversion of watch/widget surfaces onto shared rendering components.
- No accessibility identifiers introduced (separate concern).
- No localization infrastructure.
- No changes to sorting, filtering, or `availableProjects` logic.
- Not renaming the underlying storage key `showUndatedReminders` — only the visible label.
- Not fixing the `showsOverPhoto` plate-rendering test gap noted in research Open Areas.

## Open Risks

- **Renaming visible labels breaks XCUI queries** matched by text ("Show Date"); all flows
  referencing renamed rows must be grepped and updated, or UI tests fail in CI.
- **`ReminderCardView` input swap** touches `ContentView` and several unit-test factories;
  expect mechanical but broad edits. If it balloons, fall back to passing `EKReminder` +
  computing `listName` via `ReminderDisplay`'s static helper — decide at implementation time.
- Widget timeline freshness: prefs are read at build time; if users report staleness after
  toggling, an explicit `WidgetCenter.reloadAllTimelines()` on `showList` change may be needed
  (precedent: `SettingsView.swift:174`).
- macOS branch of `SettingsView` shares the bindings; confirm sentence-cased labels render
  sensibly there (no dedicated research coverage).
