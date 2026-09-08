# Design Discussion

## Current State

The app displays reminders via a shared `ReminderDisplay` struct (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:4-35`) with five fields: `title`, `notes`, `dueDate`, `priorityMarker`, `listName`. Two rendering surfaces consume it — `ReminderCardView` (iOS, `SingleThread/ReminderCardView.swift:15-23`) and `NextThingWidgetView` (widget, `NextThingWidget.swift:156-186`) — while the watch (`WatchReminderView.swift:164-181`) bypasses `ReminderDisplay` entirely, re-reading raw `EKReminder` fields with duplicated formatting.

Two display toggles exist today: `showDate` (default `true`, key `"showDate"`) and `showList` (default `false`, key `"showList"`). Both use the `ShowDatePreference` pattern (`ShowDatePreference.swift:8-27`) — a thin `UserDefaults` wrapper with `isEnabled`/`set(_:)`. iOS writes them via `@AppStorage(..., store: AppGroup.defaults)` (`ContentView.swift:221-225`); the widget reads them via the typed stores at entry-build time (`NextThingWidget.swift:58-59`); only `showDate` syncs to watch via `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:111-113,183-185`), and only `showDate` triggers `WidgetCenter.reloadAllTimelines()` on toggle (`SettingsView.swift:190`).

The sync pipeline follows a rigid 6-step pattern (research Q5): typed store → PayloadKey → pushAll inclusion → receive+persist branch → iOS hook → watch hook. Every synced preference (`showDate`, `showUndatedReminders`, `sortOption`, `excludedListTitles`) follows this exactly.

## Desired End State

Two new `EKReminder` attributes — **recurrence** and **alarms** — are surfaced in `ReminderDisplay`, rendered on all three surfaces with per-attribute display toggles, and synced to watch.

**Verification**: A reminder with a weekly recurrence and a time alarm renders a recurrence indicator and an alarm icon on iOS, watch, and widget; toggling either off in Settings hides it on all three surfaces (watch receives the change via WatchConnectivity within seconds).

## Patterns to Follow

| Pattern | Reference | Notes |
|---|---|---|
| Preference type shape | `ShowDatePreference.swift:8-27` | Thin struct: `init(defaults:key:)`, `isEnabled` (missing-key → default), `set(_:)` |
| Typed store, not raw literal | `ShowDatePreference` vs `NextThingWidget.swift:63` | **Do** use the typed wrapper everywhere; **do not** use raw `bool(forKey:)` |
| `@AppStorage` binding in ContentView | `ContentView.swift:221-225` | `store: AppGroup.defaults` — all new toggles go here |
| Settings toggle row | `SettingsView.swift:188-197` | `Toggle(isOn: $binding) { Label("...", systemImage: "...") }`; `onChange` only if widget reload needed |
| `ReminderCardView` gate pattern | `ReminderCardView.swift:41-45` | `if show<Feature>, let value = display.<field> { Text(...) }` |
| Watch state wrapper | `ShowDateState.swift:9-24` | `@Observable` class wrapping the preference; `apply(_:)` for sync receive |
| Sync pipeline (all 6 steps) | `SkippedReminderSyncService.swift:34-55,104-120,156-181,181-191` | PayloadKey → inject store → pushAll → receive → hook |
| Widget entry flag | `NextThingWidget.swift:18-19` | `shows<Feature>: Bool` on `NextThingEntry`; read from preference at `makeEntry` |
| Widget reload trigger rule | Research Q4 | Only `showDate` needs `WidgetCenter.reloadAllTimelines()` — other toggles embed flags at entry-build time |
| Unit test idiom for mapped fields | `ReminderDisplayTests.swift:7-67` | Real `EKReminder` via factory; assert field-by-field |
| Unit test idiom for toggle store | `ShowDatePreferenceTests.swift:6-24` | Unique key + defer cleanup; missing-key default + roundtrip |
| View assertion idiom | `ShowDateTests.swift:15-36` | `String(describing: body)` sentinel strings |

### Patterns to AVOID

- **Watch inline EKReminder formatting** (`WatchReminderView.swift:164-181`) — this is the duplication we're eliminating. All surfaces should consume `ReminderDisplay`.
- **Raw `bool(forKey:)` bypassing typed store** (`NextThingWidget.swift:63`) — use the typed wrapper.
- **`sendsShowDate` gating** (`SkippedReminderSyncService.swift:38,112-113`) — this was a shim to avoid pushing a key the watch didn't consume. After the watch refactor, new prefs **always** sync (no sends-flag gates needed).

## Design Decisions

1. **Refactor watch to `ReminderDisplay` before adding attributes**: The watch currently reads raw `EKReminder` fields inline at `WatchReminderView.swift:164-181`. Adding recurrence and alarm formatting there would create a third copy of the field-mapping logic. We'll change `reminderDetails(_:)` to accept `ReminderDisplay` instead of `EKReminder`, computed from `store.visibleReminders.first` at the call site. `WatchReminderView` still keeps the `store` for actions (complete, skip, delete, refresh) and auth gating — only the rendering path changes. This also means the watch finally renders `listName`, which it previously omitted.

2. **Individual toggles per attribute**: Each new attribute gets its own `ShowRecurrencePreference` / `ShowAlarmsPreference` type following the exact `ShowDatePreference` pattern. This matches the existing flat-toggle design in `SettingsView` and keeps each preference independently testable. No master "Show Details" toggle — users control each attribute individually.

3. **Both toggles default to `true`**: Unlike `showList` (defaults `false` because list names are noisy), recurrence and alarm info is compact and contextually useful. Users who don't want it can opt out. This is consistent with `showDate`'s default of `true`.

4. **All toggles sync to watch via the existing 6-step pipeline**: Each new preference gets a `PayloadKey`, injected store, `pushAll()` inclusion, receive+persist branch, `on…Received` hook, iOS `pushAll()` trigger on change, and watch `Show…State` wrapper. No `sends*` gating flags — after the watch refactor, the watch consumes all synced prefs. The `sendsShowDate` flag on `SkippedReminderSyncService` becomes a historical artifact (we don't remove it — scope discipline — but new prefs don't add equivalents).

5. **`ReminderDisplay` carries `hasRecurrence: Bool` + `recurrenceSummary: String?` and `hasAlarms: Bool`**: `hasAlarms` is a simple derived property (`!reminder.alarms?.isEmpty ?? false`). Recurrence is two fields: a Bool for compact indicators and an optional human-readable summary (e.g. "Weekly", "Every 2 days"). The summary is formatted via a new `ReminderRecurrenceFormatter` that maps `EKRecurrenceRule.frequency` + `interval` to a localized string. This keeps formatting logic in `SingleThreadCore` where all surfaces share it.

6. **Widget renders compact indicators, not full text**: The widget has limited space (`NextThingWidgetView.swift:156-186`). Recurrence shows as a "↻" symbol (or similar SF Symbol) with the summary beside it only in medium/large families. Alarms show as a "⏰" bell icon. Both are gated by `entry.showsRecurrence`/`entry.showsAlarms` flags. These toggles do **not** trigger `WidgetCenter.reloadAllTimelines()` — same as `showList`, the flags are embedded in the timeline entry at build time and the next auto-refresh picks up changes.

7. **Recurrence formatting is minimal**: We format only the first recurrence rule's frequency + interval into a short string (daily/weekly/monthly/yearly, with interval prefix for intervals > 1). We don't handle end dates, custom days-of-week, or complex rule combinations. If a reminder has no recurrence rules, `hasRecurrence` is `false` and `recurrenceSummary` is `nil`. If it has rules we can't concisely describe, `hasRecurrence` is `true` and `recurrenceSummary` is `nil` (shows just the indicator icon).

## What We're NOT Doing

- **Not surfacing**: `url`, `location`, `completionDate`, `creationDate`, `lastModifiedDate`, `startDateComponents`/`endDateComponents`, `timeZone`, `organizer`, `calendarItemExternalIdentifier`, `attachments` — these are out of scope.
- **Not adding a master "Show Details" toggle** — individual toggles only, matching the existing flat design.
- **Not refactoring `sendsShowDate` out of `SkippedReminderSyncService`** — it stays as-is for backward compatibility; new prefs simply don't add equivalent flags.
- **Not changing the watch's action/auth architecture** — store stays for complete/skip/delete/refresh; only the rendering path switches to `ReminderDisplay`.
- **Not adding recurrence/alarm editing** — display only. Users edit these in Apple's Reminders app.
- **Not supporting complex recurrence display** (end dates, day-of-week patterns, exception dates) — compact summary only.
- **Not adding new `WidgetCenter.reloadAllTimelines()` calls** for the new toggles.

## Open Risks

- **Watch `ReminderDisplay` refactor may reveal layout issues**: The watch currently omits list names. Adding `listName` (from `ReminderDisplay`) plus two new attribute rows could crowd the small screen. Mitigation: all new rows are toggle-gated and use `.font(.caption2)`; if layout is too tight, we can keep list name omitted on watch via a separate flag (but that's scope creep — try uniform first).
- **`EKRecurrenceRule` formatting edge cases**: Recurrence rules can have end dates, weekdays, set positions, and month-day qualifiers that our simple frequency+interval formatter won't capture. Risk: a reminder with a complex rule (e.g. "every 3rd Tuesday") shows only the generic indicator. Mitigation: this is explicitly scoped as "compact only" in decision 7; if users ask for richer display, that's a follow-up ticket.
- **WatchConnectivity payload size**: Each new Bool key adds a few bytes to the context dictionary. With only two new keys this is negligible, but worth noting if this pattern expands further.
- **Xcode target membership**: `ReminderDisplay` is already in `SingleThreadCore` (shared by all targets). `ReminderRecurrenceFormatter` must also live in `SingleThreadCore` so the watch and widget can import it. Verify the `SingleThreadWatch` and `SingleThreadWidget` targets can see new `SingleThreadCore` symbols before writing tests.