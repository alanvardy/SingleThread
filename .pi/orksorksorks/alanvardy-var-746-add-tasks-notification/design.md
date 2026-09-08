# Design Discussion

## Current State

**No notification infrastructure exists.** Zero hits for
`UNUserNotificationCenter`, `UNNotificationRequest`, or background modes
across all targets. No `aps-environment` entitlement, no
`UserNotifications.framework` linkage. `AppDelegate`
(`SingleThread/AppDelegate.swift:1-75`) has no `UNUserNotificationCenterDelegate`
conformance. (research.md Q1)

**No lifecycle observation beyond `.task`.** The app uses only SwiftUI
`.task` for setup (`ContentView.swift:88-90`). `AppDelegate` implements only
`applicationDidBecomeActive` (`AppDelegate.swift:45-48`). No
`@Environment(\.scenePhase)`, no enter-background / resign-active callbacks.
(research.md Q2)

**No app-activity timestamp is read or persisted anywhere.** Zero matches for
`lastOpened`, `lastActive`, `launchDate`. The only `Date()` persisted is
`BackgroundMetadata.fetchedAt` for wallpaper (`BackgroundImageStore.swift:44,154`).
(research.md Q2)

**The settings/preference pattern is well established.** `@AppStorage` keys
in `ContentView` (`ContentView.swift:151-198`) split across `.standard` (iOS-only
UI) and `AppGroup.defaults` (cross-target). `SettingsBindings`
(`SettingsBindings.swift:13-113`) snapshots values via `makeSettingsBag()`
(`ContentView.swift:534-571`), write-back via `.onChange` chains
(`ContentView.swift:118-138`). Sub-views take only needed bindings
(`InterfaceSettingsView.swift:8-9`). `UITestingSeed.persistedKeys`
(`UITestingSeed.swift:57-76`) is the de-facto key registry. (research.md Q3)

**Settings UI** is a `NavigationStack { List }` with preferences (Interface,
Reminder, Filtering & Sorting, Background, Purchase) and informational
(Privacy, About) sections (`SettingsView.swift:26-92`). `InterfaceSettingsView`
(`InterfaceSettingsView.swift:10-63`) has toggles + Pickers. (research.md Q3)

**ReminderStore can answer "are there pending reminders?"** via `reminders`
(raw in-window incomplete, `ReminderStore.swift:43`), `visibleReminders`
(minus skipped/excluded, `:111-116`), and `hasHidden` (outside-window boolean,
`:50`). `reload()` (`:287-347`) does a second broad fetch to populate `hasHidden`.
(research.md Q4)

**Deterministic test seams exist.** iOS: `--seed '<json>'` ↔ `UITestingSeed` +
`InMemoryEventStore` (`AppViewModel.swift:123-202`), `--ui-testing` fixture,
`UITestingSeed.resetPersistedState()` clearing all 18 keys. Time injected via
default-param `now: Date` (e.g. `ReminderDateFilter.swift:30,44,57`) — no
`DateProvider` type. (research.md Q6)

## Desired End State

When the feature is enabled:

1. The iOS app schedules a single local notification with a
   `UNTimeIntervalNotificationTrigger` whenever it transitions to the
   background and there are incomplete reminders pending.
2. The notification fires after a configurable interval (24, 48, or 72 hours)
   with a body like "You have 5 reminders waiting — open SingleThread."
3. When the app returns to the foreground (or finishes launching), all
   pending notifications are cancelled; a fresh one is scheduled on the
   next background transition.
4. The feature is gated by an enable/disable toggle plus an interval picker
   in a new Notifications sub-view under Interface settings.
5. The toggle defaults to **off** — the user must opt in.

**Verification**: a UI test launches with `--seed` reminders, navigates to
Settings → Notifications, enables the toggle, backgrounds, asserts a pending
notification request exists via `UNUserNotificationCenter.current()`
(reading pending requests is a synchronous API), then brings the app to
foreground and asserts no pending requests remain.

## Patterns to Follow

### Settings wiring (Patterns to FOLLOW)

1. `@AppStorage` in `ContentView` (`ContentView.swift:151-198`): new keys
   `notificationsEnabled` + `notificationIntervalHours` in `.standard`
   (iOS-only UI prefs, follows `allowsLandscape`/`showMicrophoneButton`).
2. `SettingsBindings` prop (`SettingsBindings.swift:68-99`): mirror defaults
   exactly in init (`:20-47`).
3. `makeSettingsBag()` (`ContentView.swift:534-571`): pass new values under
   `#if os(iOS)`.
4. Write-back chain (`ContentView.swift:118-138`): `.onChange(of: bag.X)`
   → `@AppStorage`.
5. `UITestingSeed.persistedKeys` (`UITestingSeed.swift:57-76`): add the two
   new keys so `resetPersistedState()` clears them.
6. Sub-view takes only needed bindings (`InterfaceSettingsView.swift:8-9`).
7. `NavigationLink` in `SettingsView` preferences section (`:46-64`).
8. **No Core preference-store struct** — `isEnabled`/`set(_:)` pattern
   (`ShowDatePreference.swift:8-32`) is for App-Group-backed cross-target keys;
   these are simple iOS-only `@AppStorage` values.

### Notification scheduling (Patterns to FOLLOW)

9. `@Environment(\.scenePhase)` on `ContentView` body — standard SwiftUI
   lifecycle. Call into `viewModel` for scheduling.
10. `AppViewModel` as scheduling owner (`AppViewModel.swift:19-80`): already
    owns `store` and composition root. Add `#if os(iOS)` gated methods.

### Patterns to AVOID

11. ❌ **`UNUserNotificationCenterDelegate` on `AppDelegate`** — we only
    schedule/cancel, not intercept foreground presentation.
12. ❌ **New `PreferenceStore` struct in `SingleThreadCore`** — indirection
    without value for iOS-only UI prefs.
13. ❌ **`BGTaskScheduler`** — requires new capability + framework.
14. ❌ **Watch notifications** — iOS-only; watch has no App Group entitlement.

## Design Decisions

1. **Scheduling trigger: background-transition with `UNTimeIntervalNotificationTrigger`.**
   When the app backgrounds (`.scenePhase == .background`) and the feature is
   enabled and reminders exist, schedule one notification with the configured
   interval. Cancel all pending when the app becomes active (`.active`).
   `UNNotificationRequest` survives termination — the OS fires it even if the
   app is killed. No background task, no capability changes, no framework
   additions beyond `import UserNotifications`.

2. **Pending-reminder check: `!reminders.isEmpty || hasHidden`.**
   Uses the store's existing `reload()` output: raw in-window reminders plus
   the boolean covering outside-window/undated reminders. No extra EventKit
   fetch. Skipped/excluded reminders count: skip is transient (resets on next
   `reload()`) and exclusion only hides from the visible list. If the user has
   reminders assigned to them, the notification serves its purpose.

3. **Scheduling code: `AppViewModel` method, called from `ContentView`'s
   `scenePhase` observer.** `AppViewModel` already owns the store and the
   composition root. Add `scheduleNotificationIfNeeded()` (background path)
   and `cancelNotifications()` (foreground path), both gated `#if os(iOS)`.
   `ContentView` observes `@Environment(\.scenePhase)` and calls the viewModel
   — this is ~5 lines in the view layer.

4. **Settings UI: new `NotificationsSettingsView` sub-view**, reached from
   the Interface section row in `SettingsView`. Contains a `Toggle` for
   enable/disable and a `Picker` (`.menu` style) for 24/48/72 hours. This
   follows the exact same pattern as `ReminderSettingsView` (separate sub-view
   in its own file, NavigationLink from SettingsSection, takes only needed
   bindings). Grouping under Interface would overcrowd that form.

5. **Notification content: dynamic count at schedule time.** Body reads
   "You have N reminders waiting — open SingleThread!" where N is the count
   of incomplete reminders (skipped/excluded removed, so the user isn't
   notified about reminders they've explicitly hidden). The count is captured
   when the notification is scheduled on background — it's a snapshot. The
   title is static: "SingleThread".

6. **Permission: request on first enable.** When the user toggles the
   notification switch ON for the first time, request `.alert` + `.badge`
   authorization via `UNUserNotificationCenter`. If denied, leave the toggle
   ON visually (the user chose to turn it on) but skip scheduling. Do not
   gate the toggle on authorization — the user's choice should persist even
   if they later grant permission in Settings.

7. **Interval default: 48 hours.** Matches the ticket spec. The picker
   offers 24h / 48h / 72h as fixed options, stored as an `Int` (hours).

## What We're NOT Doing

- **No background task** — no `BGTaskScheduler`, `UIBackgroundModes`, or wake-up
  daemon. The OS fires the already-scheduled notification.
- **No watchOS notifications** — the watch target has no notification
  infrastructure and no App Group entitlement. This is iOS-only.
- **No notification actions / categories** — no "Complete" or "Snooze" buttons
  on the notification. Tapping opens the app (default behavior).
- **No server-side push or remote notifications** — no `aps-environment`,
  no certificate, no backend.
- **No per-list filtering** — the notification fires based on total pending
  count across all lists, not configurable per calendar.
- **No notification on macOS** — the Catalyst/Mac target is not in scope.
- **No `lastOpenedAt` timestamp persisted** — the background-schedule model
  replaces the need for a "48h since last open" check. The scheduled
  notification covers the gap.

## Open Risks

1. **Authorization prompt timing.** Requesting notification permission on
   toggle-ON may feel jarring if it's the user's first interaction with
   the toggle. Mitigation: the toggle is OFF by default, and the picker
   is visible regardless (no conditional layout). The user explicitly
   opts in before seeing the prompt.

2. **Force-quit before backgrounding.** If the user kills the app from the
   app switcher (not a normal background transition), `scenePhase` may fire
   `.inactive` then `.background` — but the timing is not guaranteed to
   allow scheduling. If the notification isn't scheduled, the user never
   gets reminded. Acceptable for v1; the common case (swipe-to-home) works.

3. **iCloud reminder drift.** If a shared list adds reminders after the
   notification was scheduled, the count may be stale and the user could open
   the app to a different state. The notification still serves its purpose
   (prompting the user to open the app).

4. **Multiple-schedule defense.** If `scenePhase` fires `.background`
   multiple times in quick succession (e.g. Face ID prompt), duplicate
   notifications could be scheduled. Mitigation: always call
   `removeAllPendingNotificationRequests()` before scheduling the new one
   — the OS deduplicates by request identifier.

5. **Notification request identifier collision management.** Use a stable
   identifier (e.g. `"com.alanvardy.SingleThread.idle-reminder"`) so the
   same request is always replaced rather than accumulated.