# Structure Outline

## Approach

Schedule a single `UNTimeIntervalNotificationTrigger`-based local
notification on background transition when enabled and reminders are
pending, cancel on foreground. Gate behind a new Notifications
sub-view (toggle + interval picker) under Interface settings,
opt-in (defaults OFF). No background task, no delegate, no watchOS.

---

## Stage 1: Persistence — `@AppStorage` Keys & Settings Wiring

Add two new `@AppStorage` keys and thread them through the existing
settings plumbing. No UI, no notification code — a pure data layer
that the next stages consume.

**Files**: `SingleThread/ContentView.swift`, `SingleThread/SettingsBindings.swift`, `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`

**Key changes**:
- `@AppStorage("notificationsEnabled") private var notificationsEnabled = false`
  — iOS-only `#if os(iOS)`, `.standard` suite (line ~175, alongside `enableActionButtons`)
- `@AppStorage("notificationIntervalHours") private var notificationIntervalHours = 48`
  — iOS-only `#if os(iOS)`, `.standard` suite
- `SettingsBindings`:
  - New init params `notificationsEnabled: Bool = false` and `notificationIntervalHours: Int = 48`
  - New stored properties `var notificationsEnabled: Bool` and `var notificationIntervalHours: Int`
- `makeSettingsBag()`: pass `notificationsEnabled` and `notificationIntervalHours`
  under the existing `#if os(iOS)` block
- Write-back chain: `.onChange(of: bag.notificationsEnabled)` and `.onChange(of: bag.notificationIntervalHours)`
  alongside the existing iOS-only `.onChange` handlers (~line 123–127)
- `UITestingSeed.persistedKeys`: add `"notificationsEnabled"` and `"notificationIntervalHours"`

**Tests**: No dedicated test suite — the keys are exercised by the Settings UI
test in Stage 2 and the end-to-end UI test in Stage 5. Manual verification:
launch app, set a breakpoint in `makeSettingsBag()`, confirm the two new
values are present in the bag.

**Verify**: `make build` succeeds — no new code references UserNotifications
yet, so no linkage or entitlement changes needed.

---

## Stage 2: Settings UI — `NotificationsSettingsView`

A new settings sub-view with a Toggle and interval Picker, reached via
NavigationLink from the Interface section. This stage wires the UI to
the persistence layer but does not schedule anything.

**Files**: `SingleThread/NotificationsSettingsView.swift` (new), `SingleThread/SettingsView.swift`

**Key changes**:
- `NotificationsSettingsView: View` — takes two bindings:
  ```swift
  @Binding var notificationsEnabled: Bool
  @Binding var notificationIntervalHours: Int
  ```
  Body: `Form` with a `Toggle("Enable reminder notifications", ...)` and a
  `Picker("Remind after", selection: $notificationIntervalHours)` in `.menu`
  style with options `[24, 48, 72]`, labeled "24 hours" / "48 hours" / "72 hours".
  Picker is always visible (not gated on toggle state).
- `SettingsView` body (~line 46): add a `NavigationLink` under the Interface
  row pointing to `NotificationsSettingsView`, passing
  `$bindings.notificationsEnabled` and `$bindings.notificationIntervalHours`.
  Use `Label("Notifications", systemImage: "bell.badge")`.
  Gate with `#if os(iOS)` (macOS has no notification plan).

**Tests**: `SingleThreadUITests/NotificationsSettingsUITests.swift` (new):
- `testNotificationsToggleExists`: launch app (any seed), open Settings gear,
  assert `staticTexts["Notifications"]` exists, tap it, assert
  `switches["Enable reminder notifications"]` exists and is off by default.
- `testIntervalPickerOptions`: tap the picker, assert "24 hours", "48 hours",
  "72 hours" options appear.

**Verify**: `make ui-test` passes for the new test class. The toggle/picker
persist across app restarts because Stage 1 already wired the keys.

---

## Stage 3: Notification Engine — Scheduling, Cancellation & Permission

Add `UserNotifications` framework linkage, the Info.plist usage description,
and the core scheduling/cancellation/permission logic on `AppViewModel`,
wired to `scenePhase` in `ContentView`.

**Files**: `SingleThread/AppViewModel.swift`, `SingleThread/ContentView.swift`,
`SingleThread.xcodeproj/project.pbxproj`, `SingleThread/Info.plist` (if not
auto-generated — verify)

**Key changes**:

- **pbxproj**: add `UserNotifications.framework` to the iOS app target's
  `PBXFrameworksBuildPhase` (weak-linked for iOS 18+ compatibility).
- **Info.plist**: no new key needed — local notifications do not require a
  usage description string (unlike speech/reminders).
- **`AppViewModel`** — new `#if os(iOS)` methods:
  ```swift
  /// Called when the app transitions to the background. Schedules a single
  /// notification if the feature is enabled and reminders are pending.
  func scheduleNotificationIfNeeded() async

  /// Called when the app becomes active. Cancels all pending notifications.
  func cancelNotifications()

  /// Requests notification authorization (.alert + .badge). No-op if already
  /// determined (denied or granted). Called on first toggle-ON.
  func requestNotificationPermissionIfNeeded() async
  ```
  Implementation detail: `scheduleNotificationIfNeeded()` checks
  `UserDefaults.standard.bool(forKey: "notificationsEnabled")` and
  `!store.reminders.isEmpty || store.hasHidden`. If both true, calls
  `UNUserNotificationCenter.current().removeAllPendingNotificationRequests()`
  then `add()` with identifier `"com.alanvardy.SingleThread.idle-reminder"`,
  trigger `UNTimeIntervalNotificationTrigger(timeInterval: Double(intervalHours * 3600), repeats: false)`,
  body `"You have \(count) reminders waiting — open SingleThread!"` where
  count = `store.visibleReminders.count` (skipped/excluded already removed).

  `cancelNotifications()` calls `removeAllPendingNotificationRequests()`.

  `requestNotificationPermissionIfNeeded()` calls
  `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])`.

- **`ContentView`** — `@Environment(\.scenePhase) private var scenePhase` on
  the struct (new property). A `.onChange(of: scenePhase)` modifier on the
  root `ZStack`:
  ```swift
  .onChange(of: scenePhase) { _, phase in
      #if os(iOS)
      switch phase {
      case .background:
          Task { await appViewModel.scheduleNotificationIfNeeded() }
      case .active:
          appViewModel.cancelNotifications()
      default:
          break
      }
      #endif
  }
  ```
  `appViewModel` must be passed into `ContentView` — check whether it already
  holds a reference or if one needs to be added (currently `ContentView` only
  holds `ContentViewModel`). If needed, add
  `let appViewModel: AppViewModel` to `ContentView` init and pass it from
  `SingleThreadApp`.

- **Permission trigger**: add `.onChange(of: notificationsEnabled)` in
  `ContentView` (alongside existing onChange handlers ~line 123):
  ```swift
  .onChange(of: notificationsEnabled) { _, newValue in
      if newValue {
          Task { await appViewModel.requestNotificationPermissionIfNeeded() }
      }
  }
  ```

**Tests**: `SingleThreadUITests/NotificationSchedulingUITests.swift` (new):
- `testSchedulingOnBackground`: launch with `--seed
  '{"reminders":[{"title":"Test"}]}'`, enable notifications toggle, background
  app via `XCUIDevice.shared.press(.home)`, then read
  `UNUserNotificationCenter.current().pendingNotificationRequests()` —
  assert one request exists with identifier `"com.alanvardy.SingleThread.idle-reminder"`.
- `testCancelOnForeground`: after the above, activate app, assert
  `pendingNotificationRequests().isEmpty`.
- `testNoScheduleWhenDisabled`: same seed, toggle OFF, background, assert no
  pending requests.
- `testNoScheduleWhenNoReminders`: empty seed, toggle ON, background, assert
  no pending requests.

**Verify**: `make ui-test` with `-only-testing:SingleThreadUITests/NotificationSchedulingUITests`
passes. `make build` succeeds with the new framework linkage.

---

## Stage 4: End-to-End UI Test Hardening

A single comprehensive UI test that exercises the full user journey —
the "verification" scenario from the design.

**Files**: `SingleThreadUITests/NotificationsUITests.swift` (new)

**Key change**:
- `testFullNotificationFlow()`:
  1. Launch with seed `{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}`
  2. Tap gear → tap "Notifications" row
  3. Assert toggle is OFF, picker shows "48 hours"
  4. Tap toggle ON (authorization prompt may appear — handle system alert if
     needed)
  5. Change picker to "24 hours"
  6. Background app (`XCUIDevice.shared.press(.home)`)
  7. Assert one pending notification exists with body containing "2 reminders"
  8. Foreground app
  9. Assert no pending notifications
  10. Re-open settings → Notifications → assert toggle still ON, picker still
      "24 hours" (persistence check from Stage 2)
- `testAccessibilityAudit` on the new Notifications screen: call
  `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])`
  on the NotificationsSettingsView.

**Tests**: The one new test class above.
**Verify**: `make ui-test` with `-only-testing:SingleThreadUITests/NotificationsUITests`
passes. The full `./scripts/test.sh` gate passes (format → lint → build →
periphery → unit tests → UI tests).

---

## Testing Checkpoints

| Stage | Gate | What must be green |
|-------|------|--------------------|
| 1 | `make build` | Persistence keys compile, bag carries new values |
| 2 | `make ui-test -only-testing:SingleThreadUITests/NotificationsSettingsUITests` | Toggle + picker render and interact |
| 3 | `make ui-test -only-testing:SingleThreadUITests/NotificationSchedulingUITests` | Background schedules, foreground cancels, gated on toggle + reminders |
| 4 | `./scripts/test.sh` | Full pipeline + end-to-end UI test |

**If context resets**: resume at the next checkpoint — the layers below are
already tested and stable. For example, if Stage 3 fails, Stages 1–2 are
independently mergeable.