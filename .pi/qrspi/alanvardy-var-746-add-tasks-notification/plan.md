# Implementation Plan

## Overview

Add an opt-in iOS local notification that fires after a configurable idle
interval (24/48/72 hours) when the app backgrounds with pending reminders.
Gated behind a new Notifications sub-view under Settings → Interface, with
an enable toggle (default OFF) and interval picker.

---

## Phase 1: Persistence — `@AppStorage` Keys & Settings Wiring

### Changes

#### 1. Add `@AppStorage` keys in ContentView

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Two new `@AppStorage` properties after the existing `showSwipePrompt` block
(~line 179), inside the existing `#if os(iOS)` group:

```swift
#if os(iOS)
    @AppStorage("notificationsEnabled")
    private var notificationsEnabled = false

    @AppStorage("notificationIntervalHours")
    private var notificationIntervalHours = 48
#endif
```

These use `.standard` suite (no explicit `store:`), matching
`enableActionButtons` and `allowsLandscape` — iOS-only UI preferences.

#### 2. Add properties to `SettingsBindings`

**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add two parameters to `init` with matching defaults:

```swift
notificationsEnabled: Bool = false,
notificationIntervalHours: Int = 48,
```

Add two stored properties alongside existing vars:

```swift
var notificationsEnabled: Bool
var notificationIntervalHours: Int
```

Note: No `#if os(iOS)` wrapping — the compiler does not support conditional
compilation inside a parameter list or stored-property block for an
`@Observable` class. The macOS branch simply never reads these properties.

#### 3. Pass new values in `makeSettingsBag()`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `#if os(iOS)` branch of `makeSettingsBag()`, add the two new arguments
after `showSwipePrompt`:

```swift
notificationsEnabled: notificationsEnabled,
notificationIntervalHours: notificationIntervalHours,
```

#### 4. Add write-back `.onChange` handlers

**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `.sheet` modifier's `.onChange` chain, inside the existing
`#if os(iOS)` block (after `showSwipePrompt` write-back at ~line 127),
add:

```swift
.onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
.onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
```

#### 5. Register keys in `UITestingSeed.persistedKeys`

**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

In the `persistedKeys` array (~line 57), add the two new keys:

```swift
"notificationsEnabled",
"notificationIntervalHours",
```

Insert alphabetically would be after `"isEntitled"` and before
`"showMicrophoneButton"`, but exact position is cosmetic — append to end
of the array is also fine and avoids accidental reorder bugs.

### Verification

#### Automated
- [x] `make build` passes (clean compile, no new warnings)
- [x] `make format && make lint` passes (no style/lint violations)

#### Manual
- [ ] Launch app on iOS simulator, set breakpoint in `makeSettingsBag()`,
  confirm `notificationsEnabled` is `false` and `notificationIntervalHours`
  is `48` in the constructed bag.

---

## Phase 2: Settings UI — `NotificationsSettingsView`

### Changes

#### 1. Create `NotificationsSettingsView`

**File**: `SingleThread/NotificationsSettingsView.swift`
**Action**: create

New file following the exact pattern of `ReminderSettingsView.swift`:

```swift
import SwiftUI

/// Notification preferences: enable toggle and interval picker, both
/// #if os(iOS) gated since notifications are iOS-only.
struct NotificationsSettingsView: View {
    @Binding var notificationsEnabled: Bool
    @Binding var notificationIntervalHours: Int

    var body: some View {
        Form {
            Toggle(isOn: $notificationsEnabled) {
                Label("Enable reminder notifications", systemImage: "bell.badge")
            }
            Picker("Remind after", selection: $notificationIntervalHours) {
                Text("24 hours").tag(24)
                Text("48 hours").tag(48)
                Text("72 hours").tag(72)
            }
            .pickerStyle(.menu)
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        NotificationsSettingsView(
            notificationsEnabled: .constant(false),
            notificationIntervalHours: .constant(48))
    }
}
```

The picker is always visible (not gated on toggle state), matching the design
decision that the user should see the interval before opting in.

#### 2. Add NavigationLink in `SettingsView`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

In the preferences `Section`, add a `NavigationLink` after the existing
`InterfaceSettingsView` link (~line 46). The new link is gated `#if os(iOS)`,
the same way InterfaceSettingsView conditions its iOS-only bindings:

```swift
#if os(iOS)
    NavigationLink {
        NotificationsSettingsView(
            notificationsEnabled: $bindings.notificationsEnabled,
            notificationIntervalHours: $bindings.notificationIntervalHours)
    } label: {
        Label("Notifications", systemImage: "bell.badge")
    }
#endif
```

The Reminder row already uses `systemImage: "bell.badge"` — that's fine;
the Label text distinguishes them.

#### 3. Create UI test file

**File**: `SingleThreadUITests/NotificationsSettingsUITests.swift`
**Action**: create

```swift
import XCTest

final class NotificationsSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(seedJSON: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", seedJSON]
        app.launch()
        return app
    }

    @MainActor
    func testNotificationsToggleExists() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)

        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // The Notifications row should be visible in the Settings list.
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 3))
        app.staticTexts["Notifications"].tap()

        // The toggle should exist and default to OFF.
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0", "Notifications should default to off")
    }

    @MainActor
    func testIntervalPickerOptions() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)

        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()

        // Tap the picker to reveal options.
        let picker = app.buttons["Remind after"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()

        XCTAssertTrue(app.buttons["24 hours"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["48 hours"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["72 hours"].waitForExistence(timeout: 2))
    }
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/NotificationsSettingsUITests` passes (toggle + picker render)
- [x] `make build` passes (new file compiles, macOS target ignores the new `#if os(iOS)` NavigationLink)
- [x] `make format && make lint` passes

#### Manual
- [ ] Launch app → gear → tap "Notifications" → see toggle OFF and picker at "48 hours"
- [ ] Turn toggle ON → background app → relaunch → gear → Notifications → toggle is still ON (persistence)

---

## Phase 3: Notification Engine — Scheduling, Cancellation & Permission

### Changes

#### 1. Pass `AppViewModel` into `ContentView`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add a new stored property and update the primary init:

```swift
#if os(iOS)
    let appViewModel: AppViewModel?
#endif
```

Update the primary `init` (the one called by `SingleThreadApp`) to accept and
store it. The preview inits do NOT need the parameter — they can leave it nil:

```swift
init(viewModel: ContentViewModel, appViewModel: AppViewModel? = nil) {
    self.viewModel = viewModel
    #if os(iOS)
        self.appViewModel = appViewModel
    #endif
}
```

**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Update the `ContentView` construction in `body` to pass `viewModel`:

```swift
ContentView(viewModel: viewModel.contentViewModel, appViewModel: viewModel)
```

#### 2. Add notification methods to `AppViewModel`

**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

Add `import UserNotifications` at the top, gated `#if os(iOS)`:

```swift
#if os(iOS)
    import UserNotifications
#endif
```

Add three new methods inside the class body (before the `private` marker,
alongside the other public/internal members):

```swift
#if os(iOS)
    /// Schedules a single local notification if the feature is enabled
    /// and reminders are pending. Always removes existing requests first
    /// so only one notification is ever scheduled.
    func scheduleNotificationIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        let count = store.visibleReminders.count
        guard count > 0 || store.hasHidden else { return }

        let intervalHours = UserDefaults.standard.integer(forKey: "notificationIntervalHours")
        let effectiveHours = intervalHours > 0 ? intervalHours : 48

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let content = UNMutableNotificationContent()
        content.title = "SingleThread"
        content.body = "You have \(count) reminders waiting — open SingleThread!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(effectiveHours * 3600),
            repeats: false)

        let request = UNNotificationRequest(
            identifier: "com.alanvardy.SingleThread.idle-reminder",
            content: content,
            trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Silently skip — the user won't get reminded this cycle.
            // The next background transition will retry.
        }
    }

    /// Cancels all pending local notifications.
    func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Requests notification authorization (.alert + .badge).
    /// No-op if already determined (granted or denied).
    func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .badge])
        default:
            break
        }
    }
#endif
```

Design note: `visibleReminders.count` is used for the notification body count.
Skipped and excluded reminders are already filtered out of `visibleReminders`,
and `hasHidden` is checked separately as a gate so the notification fires even
if all in-window reminders are excluded. When `count == 0 && hasHidden`, the
body reads "You have 0 reminders waiting" — acceptable for v1 (the prompt
to open the app is the primary signal).

**Important**: With Xcode 16 objectVersion 77, `import UserNotifications` in
a Swift source file auto-links the framework. No `project.pbxproj` edit is
needed for framework linkage.

#### 3. Add `scenePhase` observer to `ContentView`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add `@Environment(\.scenePhase)` property at the top of the private vars
alongside `reduceMotion` (~line 216):

```swift
@Environment(\.scenePhase)
private var scenePhase
```

On the root `ZStack`, add the `.onChange(of: scenePhase)` modifier.
The exact attachment point: on the `ZStack` itself (the outermost element
in `body`). Add it after the existing `.animation(...)` modifier
(~line 87):

```swift
.onChange(of: scenePhase) { _, phase in
    #if os(iOS)
        guard let appViewModel else { return }
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

#### 4. Add permission trigger on toggle-ON

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add `.onChange(of: notificationsEnabled)` alongside the other view-level
`.onChange` handlers (~line 91-98, near `showUndatedReminders`/`sortOption`/
`appearanceMode`):

```swift
#if os(iOS)
    .onChange(of: notificationsEnabled) { _, newValue in
        if newValue {
            Task { await appViewModel?.requestNotificationPermissionIfNeeded() }
        }
    }
#endif
```

This fires when the toggle flips ON — whether from the settings write-back
chain or direct mutation. If the user flips it OFF and back ON, the
permission request is a no-op (already determined).

#### 5. Create scheduling UI tests

**File**: `SingleThreadUITests/NotificationSchedulingUITests.swift`
**Action**: create

```swift
import UserNotifications
import XCTest

final class NotificationSchedulingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(seedJSON: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", seedJSON]
        app.launch()
        return app
    }

    /// Assert pending notification state after background/foreground transitions.
    /// Note: `UNUserNotificationCenter.current().pendingNotificationRequests()`
    /// is synchronous and available in test processes.
    @MainActor
    func testSchedulingOnBackground() async throws {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Enable notifications.
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        // Flip ON (default is OFF).
        toggle.tap()
        usleep(500_000)
        // Accept the permission alert if it appears.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        // Go back to main screen.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Background the app.
        XCUIDevice.shared.press(.home)
        // Wait for the background transition to complete scheduling.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertEqual(pending.count, 1, "One notification should be scheduled on background")
        let request = try XCTUnwrap(pending.first)
        XCTAssertEqual(request.identifier, "com.alanvardy.SingleThread.idle-reminder")
        XCTAssertTrue(request.content.body.contains("2 reminders"))

        // Clean up: cancel pending so this test doesn't leak.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @MainActor
    func testCancelOnForeground() async throws {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Enable notifications.
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        usleep(500_000)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Background, then foreground.
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        var pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertEqual(pending.count, 1, "Should be scheduled after background")

        // Bring app to foreground by reactivating.
        app.activate()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty, "Should be cancelled on foreground")
    }

    @MainActor
    func testNoScheduleWhenDisabled() async throws {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Toggle is OFF by default — just background.
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty, "No notification when toggle is off")
    }

    @MainActor
    func testNoScheduleWhenNoReminders() async throws {
        let app = launchApp(seedJSON: #"{"reminders":[]}"#)
        XCTAssertTrue(app.staticTexts["No Reminders"].waitForExistence(timeout: 5))

        // Enable notifications.
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        usleep(500_000)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty, "No notification when no reminders exist")
    }
}
```

**Note on system alert handling**: The `springboard` interstitials above follow
the standard XCTest pattern. The `Allow` button reference is locale-sensitive —
on non-English simulators, use `springboard.buttons.element(boundBy: 1)` as a
fallback. The test helper could be factored if reuse becomes common, but for
v1 inlining is fine.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/NotificationSchedulingUITests` passes
- [x] `make build` passes (new `import UserNotifications` auto-links framework)
- [x] `make lint` passes (no unused import — `UserNotifications` is consumed by `AppViewModel` methods)

#### Manual
- [ ] Launch app with real reminders → Settings → Notifications → toggle ON
- [ ] Background app (⌘⇧H in simulator) → check Notification Center for pending notification
- [ ] Foreground app → pending notification is cleared
- [ ] Disable toggle → background → no notification scheduled
- [ ] Empty reminders + toggle ON → background → no notification scheduled

---

## Phase 4: End-to-End UI Test Hardening

### Changes

#### 1. Create comprehensive end-to-end test

**File**: `SingleThreadUITests/NotificationsUITests.swift`
**Action**: create

```swift
import UserNotifications
import XCTest

final class NotificationsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(seedJSON: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", seedJSON]
        app.launch()
        return app
    }

    @MainActor
    func testFullNotificationFlow() async throws {
        let app = launchApp(
            seedJSON: #"{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}"#)

        // 1. Verify reminders are visible.
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // 2. Navigate to Settings → Notifications.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 3))
        app.staticTexts["Notifications"].tap()

        // 3. Assert toggle is OFF, picker shows "48 hours".
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.buttons["48 hours"].exists || app.staticTexts["48 hours"].exists)

        // 4. Enable toggle.
        toggle.tap()
        usleep(500_000)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        // 5. Change picker to "24 hours".
        let picker = app.buttons["Remind after"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        XCTAssertTrue(app.buttons["24 hours"].waitForExistence(timeout: 2))
        app.buttons["24 hours"].tap()

        // 6. Go back to main screen.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // 7. Background and verify notification.
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertEqual(pending.count, 1)
        let request = try XCTUnwrap(pending.first)
        XCTAssertTrue(request.content.body.contains("2 reminders"))
        // Interval should be ~86400s (24h), not 172800 (48h).
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 86400, accuracy: 1)

        // 8. Foreground and verify cancellation.
        app.activate()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let afterForeground = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertTrue(afterForeground.isEmpty)

        // 9. Re-open Settings → Notifications → verify persistence.
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()

        let persistedToggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedToggle.value as? String, "1", "Toggle should still be ON")

        // Picker text might be "24 hours" in a button or static text.
        let persistedPicker = app.buttons["Remind after"]
        XCTAssertTrue(persistedPicker.waitForExistence(timeout: 3))
        // The picker button label shows the current selection.
        XCTAssertTrue(persistedPicker.label.contains("24 hours"),
                      "Picker should still show 24 hours: got \(persistedPicker.label)")

        // Clean up.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)
        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))

        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()

        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }
}
```

#### 2. Full pipeline gate

No additional file changes. The Phase 4 test is additive verification.

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes (format → lint → build → periphery → unit tests → UI tests)
- [ ] Specifically: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/NotificationsUITests` passes

#### Manual
- [ ] Run through the full flow manually: enable toggle → change interval → background → verify OS notification center → foreground → verify cleared

---

## Testing Checkpoints

| Stage | Gate | What must be green |
|-------|------|--------------------|
| 1 | `make build && make lint` | Persistence keys compile, bag carries new values |
| 2 | `xcodebuild test ... -only-testing:SingleThreadUITests/NotificationsSettingsUITests` | Toggle + picker render and interact |
| 3 | `xcodebuild test ... -only-testing:SingleThreadUITests/NotificationSchedulingUITests` | Background schedules, foreground cancels, gated on toggle + reminders |
| 4 | `./scripts/test.sh` | Full pipeline + end-to-end UI test |

**If context resets**: resume at the next checkpoint — stages below are
independently tested and stable.