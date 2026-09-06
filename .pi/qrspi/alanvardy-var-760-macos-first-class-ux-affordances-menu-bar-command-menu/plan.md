# Implementation Plan

## Overview

Turn the existing multiplatform app into a first-class macOS citizen from the menu bar outward: a `CommandMenu` (Complete/Skip/appearance) plus About/Quit app-menu polish, a live `MenuBarExtra` dropdown for the next due reminder (hidden when nothing is due), and macOS local notifications via a platform-agnostic `NotificationScheduler` extracted out of `AppViewModel`'s iOS-only blob. Model code stays platform-agnostic (`SingleThreadCore`); all UI divergence is inline `#if os(...)` or one small macOS-gated file.

> **Post-implementation integration note (rebase onto moved main)**: while this branch was in flight, `origin/main` absorbed
> the var-792 branch (which had received this ticket's `NotificationScheduler.swift` + `NotificationSchedulerTests.swift`
> files through a cross-worktree incident and then **evolved them** — key-injected `NotificationScheduler` with
> `scheduleIfNeeded(reminderCount:, hasHidden:)`/`cancelAll()`/`requestPermissionIfNeeded()`, `pendingSummary`/
> `lastScheduleSummary` moved inside, `UserNotificationCentering` + `FakeUserNotificationCenter` extracted to their own
> Core file) and the var-796 branch (which **deleted the iOS notification UI tests** — `NotificationSchedulingUITests`,
> `NotificationsUITests`, and parts of the flows suite). The conflict resolution therefore: (1) adopted main's merged
> scheduler + its iOS wrappers wholesale (Phase 1 became plan.md-only), (2) kept only this ticket's macOS additions
> (shared scheduler property, `scheduleNotificationsForMacOS()` trigger, macOS enabled-key default) adapted to main's
> API, and (3) replayed Phases 3-4 unchanged. The Phase 2 iOS UI-regression gate no longer exists because its suites
> were deleted on main; iOS scheduling semantics are covered by main's `NotificationSchedulerTests` + the iOS unit run.

**Resolved design amendments** (from `structure.md` open questions):

1. **macOS has no notifications-enable surface** → macOS always passes `enabled: true` to the scheduler, i.e. schedules whenever anything is due. The `enabled` toggle stays an iOS-only concept.
2. **Permission timing on macOS** → `requestPermissionIfNeeded` is called lazily at the same trigger as scheduling; it self-guards on `.notDetermined`, so it prompts at most once, and only when something is actually due.
3. **Foreground presentation** → **no** `UNUserNotificationCenterDelegate`/`willPresent` is added this ticket. The notification is a long-delay idle reminder meant to fire while the user is away; a foreground banner would be redundant with the visible in-app UI, and adding a delegate is a new behavior (not a rewire) that contradicts "no iOS behavior change". Deferred as a follow-up shim if requested.
4. **MenuBarExtra "hidden entirely"** → conditional scene inclusion (`SceneBuilder` `if`), enabled by converting `viewModel` to an observed `@State` (below). Fallback if runtime insertion misbehaves: always include the extra and let `MenuBarExtraOptions` return empty content (it already does when `visibleReminders.first == nil`).

**Deviation from structure**: the "schedule at launch via `MacAppDelegate.applicationDidFinishLaunching`" trigger is dropped in favor of the existing `store.onRemindersChanged` wiring. The initial `start() → reload()` fires `onRemindersChanged` at every launch (verified: `reload()` ends with `onRemindersChanged?()`), so schedule-on-data-change already covers launch. This keeps Stage 2 self-contained in `AppViewModel.swift` (matching "Files: AppViewModel.swift (only)") and avoids fragile delegate-adaptor wiring; permission request is folded into the same trigger.

---

## Phase 1: `NotificationScheduler` foundation (SingleThreadCore)

### Changes

#### 1. New platform-agnostic scheduler
**File**: `SingleThreadCore/Sources/SingleThreadCore/NotificationScheduler.swift`
**Action**: create

```swift
import Foundation
import UserNotifications

/// Protocol seam over `UNUserNotificationCenter` (unmockable as a concrete
/// class) so schedule/cancel/permission behavior is unit-testable with a fake.
protocol UserNotificationCentering {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

extension UNUserNotificationCenter: UserNotificationCentering {
    /// `UNUserNotificationCenter` exposes `notificationSettings()`, not a
    /// direct authorization-status accessor; adapt it.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// Platform-agnostic owner of the "idle reminder" local notification.
/// Explicitly `@MainActor` because `SingleThreadCore` does NOT enable the
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default used by the app target.
@MainActor
final class NotificationScheduler {
    enum Action: Equatable {
        case schedule(effectiveIntervalHours: Int)
        case cancel
    }

    enum PermissionOutcome: Equatable {
        case alreadyDetermined
        case granted
        case denied
    }

    /// Stable request identifier — moved verbatim from `AppViewModel`.
    static let idleReminderIdentifier = "app.alanvardy.SingleThread.idle-reminder"

    init(center: any UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Pure schedule/cancel decision, split out for direct unit testing.
    /// Mirrors the current cancel-first/guard semantics.
    static func decideAction(
        visibleCount: Int,
        hasHidden: Bool,
        enabled: Bool,
        intervalHours: Int
    ) -> Action {
        guard enabled else { return .cancel }
        guard visibleCount > 0 || hasHidden else { return .cancel }
        let effectiveHours = intervalHours > 0 ? intervalHours : 48
        return .schedule(effectiveIntervalHours: effectiveHours)
    }

    /// Schedules (or cancels) the single idle-reminder notification.
    /// Returns the added request so the caller can render the UI-test summary;
    /// `nil` when nothing was scheduled (cancelled or the add failed).
    @discardableResult
    func scheduleNotificationIfNeeded(
        visibleCount: Int,
        hasHidden: Bool,
        enabled: Bool,
        intervalHours: Int,
        options _: UNAuthorizationOptions
    ) async -> UNNotificationRequest? {
        switch Self.decideAction(
            visibleCount: visibleCount,
            hasHidden: hasHidden,
            enabled: enabled,
            intervalHours: intervalHours) {
        case .cancel:
            await cancelNotifications()
            return nil
        case .schedule(let effectiveHours):
            // Always clear stale requests first, matching the prior iOS order.
            center.removeAllPendingNotificationRequests()

            let content = UNMutableNotificationContent()
            content.title = String(
                localized: "SingleThread", table: "Localizable", bundle: .main)
            content.body = String(
                localized: "You have \(visibleCount) reminders waiting — open SingleThread!",
                table: "Localizable",
                bundle: .main)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Double(effectiveHours * 3600),
                repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.idleReminderIdentifier,
                content: content,
                trigger: trigger)

            do {
                try await center.add(request)
                return request
            } catch {
                // Silently skip — the next trigger retries.
                return nil
            }
        }
    }

    func cancelNotifications() async {
        center.removeAllPendingNotificationRequests()
    }

    /// Requests authorization only when `.notDetermined`; maps a thrown
    /// request or a `false` grant to `.denied`.
    func requestPermissionIfNeeded(options: UNAuthorizationOptions) async -> PermissionOutcome {
        switch await center.authorizationStatus() {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: options)
                return granted ? .granted : .denied
            } catch {
                return .denied
            }
        default:
            return .alreadyDetermined
        }
    }

    /// Exposed so `AppViewModel`'s iOS `--ui-testing-notifications` seam reads
    /// pending requests through the same center the scheduler uses.
    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    private let center: any UserNotificationCentering
}
```

Note: `options` is currently unused by the scheduling body (options matter only when requesting permission); it is kept in the signature so the iOS/macOS call sites pass their platform options explicitly and the permutation surface is unchanged. If SwiftLint flags the unused parameter, name it `options _:` as above.

#### 2. Scheduler unit tests
**File**: `SingleThreadTests/NotificationSchedulerTests.swift`
**Action**: create

```swift
import Testing
@testable import SingleThreadCore

@Suite(.serialized)
struct NotificationSchedulerTests {
    // MARK: decideAction truth table

    @Test
    func decideActionCancelsWhenDisabled() {
        let result = NotificationScheduler.decideAction(
            visibleCount: 1, hasHidden: false, enabled: false, intervalHours: 24)
        #expect(result == .cancel)
    }

    @Test
    func decideActionCancelsWhenNothingDue() {
        let result = NotificationScheduler.decideAction(
            visibleCount: 0, hasHidden: false, enabled: true, intervalHours: 24)
        #expect(result == .cancel)
    }

    @Test
    func decideActionSchedulesWhenVisible() {
        let result = NotificationScheduler.decideAction(
            visibleCount: 2, hasHidden: false, enabled: true, intervalHours: 24)
        #expect(result == .schedule(effectiveIntervalHours: 24))
    }

    @Test
    func decideActionSchedulesWhenOnlyHidden() {
        let result = NotificationScheduler.decideAction(
            visibleCount: 0, hasHidden: true, enabled: true, intervalHours: 12)
        #expect(result == .schedule(effectiveIntervalHours: 12))
    }

    @Test
    func decideActionFallsBackTo48Hours() {
        #expect(
            NotificationScheduler.decideAction(
                visibleCount: 1, hasHidden: false, enabled: true, intervalHours: 0)
                == .schedule(effectiveIntervalHours: 48))
        #expect(
            NotificationScheduler.decideAction(
                visibleCount: 1, hasHidden: false, enabled: true, intervalHours: -5)
                == .schedule(effectiveIntervalHours: 48))
    }

    // MARK: fake-center behavior

    @Test
    func scheduleAddsSingleRequestWithStableIdentifier() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(center: fake)
        let request = await scheduler.scheduleNotificationIfNeeded(
            visibleCount: 1, hasHidden: false, enabled: true, intervalHours: 2, options: [.alert])

        #expect(request != nil)
        #expect(fake.addedRequests.count == 1)
        #expect(fake.addedRequests.first?.identifier == NotificationScheduler.idleReminderIdentifier)
        #expect(fake.removeAllCallCount >= 1)
    }

    @Test
    func scheduleCancelsWhenDisabled() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(center: fake)
        let request = await scheduler.scheduleNotificationIfNeeded(
            visibleCount: 1, hasHidden: false, enabled: false, intervalHours: 2, options: [.alert])

        #expect(request == nil)
        #expect(fake.addedRequests.isEmpty)
        #expect(fake.removeAllCallCount == 1)
    }

    @Test
    func cancelClearsPendingRequests() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(center: fake)
        await scheduler.cancelNotifications()
        #expect(fake.removeAllCallCount == 1)
    }

    @Test
    func permissionRequestsOnceWhenNotDetermined() async {
        let fake = FakeUserNotificationCenter(authorizationStatus: .notDetermined, grantResult: true)
        let scheduler = NotificationScheduler(center: fake)
        let outcome = await scheduler.requestPermissionIfNeeded(options: [.alert, .sound])

        #expect(outcome == .granted)
        #expect(fake.requestedOptions == [.alert, .sound])
    }

    @Test
    func permissionDeniedMapsToDenied() async {
        let fake = FakeUserNotificationCenter(authorizationStatus: .notDetermined, grantResult: false)
        let scheduler = NotificationScheduler(center: fake)
        #expect(await scheduler.requestPermissionIfNeeded(options: [.alert]) == .denied)
    }

    @Test
    func permissionAlreadyDeterminedSkipsRequest() async {
        let fake = FakeUserNotificationCenter(authorizationStatus: .authorized, grantResult: false)
        let scheduler = NotificationScheduler(center: fake)
        #expect(await scheduler.requestPermissionIfNeeded(options: [.alert]) == .alreadyDetermined)
        #expect(fake.requestedOptions == nil)
    }

    @Test
    func permissionThrowMapsToDenied() async {
        let fake = FakeUserNotificationCenter(authorizationStatus: .notDetermined, requestThrows: true)
        let scheduler = NotificationScheduler(center: fake)
        #expect(await scheduler.requestPermissionIfNeeded(options: [.alert]) == .denied)
    }

    @Test
    func addThrowingDoesNotCrash() async {
        let fake = FakeUserNotificationCenter(addThrows: true)
        let scheduler = NotificationScheduler(center: fake)
        let request = await scheduler.scheduleNotificationIfNeeded(
            visibleCount: 1, hasHidden: false, enabled: true, intervalHours: 2, options: [.alert])
        #expect(request == nil)
    }
}

/// In-memory `UserNotificationCentering` for the scheduler tests.
private final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    var authorizationStatusToReturn: UNAuthorizationStatus
    var grantResult: Bool
    var requestThrows: Bool
    var addThrows: Bool
    var addedRequests: [UNNotificationRequest] = []
    var removeAllCallCount = 0
    var pendingToReturn: [UNNotificationRequest] = []
    var requestedOptions: UNAuthorizationOptions?

    init(
        authorizationStatus: UNAuthorizationStatus = .authorized,
        grantResult: Bool = true,
        requestThrows: Bool = false,
        addThrows: Bool = false
    ) {
        authorizationStatusToReturn = authorizationStatus
        self.grantResult = grantResult
        self.requestThrows = requestThrows
        self.addThrows = addThrows
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        if requestThrows { throw NotificationSchedulerTestError.fake }
        return grantResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusToReturn
    }

    func add(_ request: UNNotificationRequest) async throws {
        if addThrows { throw NotificationSchedulerTestError.fake }
        addedRequests.append(request)
    }

    func removeAllPendingNotificationRequests() {
        removeAllCallCount += 1
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingToReturn
    }
}

private enum NotificationSchedulerTestError: Error {
    case fake
}
```

(If the test target has a shared fake already, reuse it; otherwise this private fake is self-contained. `NotificationSchedulerTestError` is only needed if the fake throws via a non-`CancellationError` path — a plain `struct TestError: Error {}` works equally.)

### Verification

#### Automated
- [x] `make mac-test` passes — the scheduler foundation + its tests (`NotificationSchedulerTests`/`UserNotificationCenteringTests`) now come from main's merged var-792 evolution of this phase's work; all pass except the two pre-existing StoreKit `EntitlementStoreTests` (local sandbox, fail on clean main too).
- [x] `make test` passes (iOS unit run — shared scheduler compiles for iOS, iOS notification wrappers intact)
- [x] `make format` then `make lint` pass (SwiftLint `--strict` clean)

#### Manual
- [ ] None — behavior is headless; the macOS notification delivery check happens in Phase 2's manual step.

---

## Phase 2: AppViewModel rewiring + macOS scheduling triggers

### Changes

#### 1. Reimport + scheduler property
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

- Move `import UserNotifications` out of the `#if os(iOS)` block and into a new `#if os(iOS) || os(macOS)` block (alongside the existing `WidgetKit` import), because the macOS trigger now references `UNAuthorizationOptions`:

```swift
#if os(iOS)
    import EventKit
    import WatchConnectivity
#endif
#if os(iOS) || os(macOS)
    import UserNotifications
    import WidgetKit
#endif
```

- Add the scheduler property next to the existing `store` declaration (unconditional — used by both iOS wrappers and the macOS trigger):

```swift
let store: ReminderStore
let backgroundImage: BackgroundImageStore
let usesInMemoryStore: Bool
private let scheduler = NotificationScheduler()
```

#### 2. Replace the iOS notification method bodies
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify (inside the existing `#if os(iOS)` block)

- Delete `static let idleReminderIdentifier` (moved to `NotificationScheduler.idleReminderIdentifier`; no external symbol references it — only the UI-test string literal `NotificationSchedulingUITests.swift:55`, whose value is unchanged).
- Rewrite the three methods as thin scheduler clients, preserving the exact iOS scheduling semantics and the `--ui-testing-notifications` seam:

```swift
func scheduleNotificationIfNeeded() async {
    await refreshPendingSummary()
    let request = await scheduler.scheduleNotificationIfNeeded(
        visibleCount: store.visibleReminders.count,
        hasHidden: store.hasHidden,
        enabled: UserDefaults.standard.bool(forKey: NotificationKeys.enabled),
        intervalHours: UserDefaults.standard.integer(forKey: NotificationKeys.intervalHours),
        options: [.alert, .badge])
    if let request {
        lastScheduleSummary = Self.summary(requests: [request])
    }
    await refreshPendingSummary()
}
```

(Only divergence: the old code set `lastScheduleSummary = nil` when `center.add` threw; the new code leaves it untouched on failure — unreachable via UI tests, shadowed by `pendingSummary` in practice.)

```swift
func cancelNotifications() async {
    await scheduler.cancelNotifications()
    await refreshPendingSummary()
}

func requestNotificationPermissionIfNeeded() async {
    let outcome = await scheduler.requestPermissionIfNeeded(options: [.alert, .badge])
    if outcome == .denied {
        UserDefaults.standard.set(false, forKey: NotificationKeys.enabled)
    }
}
```

- Update `refreshPendingSummary()` (still iOS-only, still gated on `--ui-testing-notifications`) to read through the scheduler's center:

```swift
private func refreshPendingSummary() async {
    guard ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications") else { return }
    pendingSummary = Self.summary(requests: await scheduler.pendingNotificationRequests())
}
```

`summary(requests:)`, `pendingSummary`, and `lastScheduleSummary` stay exactly as they are (the `#if os(iOS)` block).

#### 3. macOS scheduling trigger
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify (extend the existing `#if os(iOS) || os(macOS)` wiring)

```swift
#if os(iOS) || os(macOS)
    store.onRemindersChanged = { [weak self] in
        WidgetCenter.shared.reloadAllTimelines()
        #if os(macOS)
        Task { @MainActor in
            await self?.scheduleNotificationsForMacOS()
        }
        #endif
    }
#endif
```

Add the macOS helper (in a new `#if os(macOS)` region):

```swift
#if os(macOS)
    /// Schedules (or cancels) the macOS idle-reminder notification. Treats the
    /// iOS-only `notificationsEnabled` toggle as always-on (there is no macOS
    /// surface for it), requests permission lazily/once only when something is
    /// due, and relies on `decideAction` to cancel when nothing is due.
    private func scheduleNotificationsForMacOS() async {
        if store.visibleReminders.count > 0 || store.hasHidden {
            _ = await scheduler.requestPermissionIfNeeded(options: [.alert, .sound])
        }
        await scheduler.scheduleNotificationIfNeeded(
            visibleCount: store.visibleReminders.count,
            hasHidden: store.hasHidden,
            enabled: true,
            intervalHours: 0, // macOS has no interval surface; 48h fallback applies
            options: [.alert, .sound])
    }
#endif
```

`onRemindersChanged` fires on the initial `start() → reload()` at every launch, so this also covers "schedule on launch" without a `MacAppDelegate` hook (see the note at the top of this plan).

### Verification

#### Automated
- [x] `make mac-build` passes (macOS compiles the shared scheduler + macOS trigger)
- [x] `make mac-test` passes (macOS unit run green — incl. main's `NotificationSchedulerTests` + this ticket's `MenuBarExtraOptionsTests`; only the two pre-existing StoreKit `EntitlementStoreTests` fail)
- [x] Targeted iOS regression — **superseded**: the iOS notification UI suites (`NotificationSchedulingUITests`/`NotificationsUITests`) were deleted on main by var-796 before this branch landed; iOS scheduling semantics are guarded by main's `NotificationSchedulerTests` + the iOS unit run instead.

#### Manual
- [ ] `make mac-run` — on first launch with a due reminder, macOS shows the notification permission prompt; after granting and with a signed/entitled build (see design Open Risk: sandbox + hardened runtime), a notification is scheduled for the due reminder.

---

## Phase 3: App commands — `CommandMenu` + About/Quit/appearance polish

### Changes

#### 1. Observe the composition root
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Convert the eagerly-built view model to an observed `@State` so the `App` body reacts to store changes (required for the Phase 4 `MenuBarExtra` hide and the menu `.disabled` state). Add `import SingleThreadCore` (for `AppearanceMode`/`ReminderStore`), an `@AppStorage` appearance binding, and an `@State` About-flag:

```swift
import SwiftUI
import SingleThreadCore
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main
struct SingleThreadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
                appViewModel: viewModel)
                #if os(macOS)
                .sheet(isPresented: $showAbout) {
                    NavigationStack { AboutView() }
                }
                #endif
        }
        #if os(macOS)
        .commands {
            appCommands(
                store: viewModel.store,
                appearanceMode: $appearanceMode,
                showAbout: $showAbout)
        }
        #endif
    }

    @Environment(\.openURL)
    private var openURL

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif

    @State private var viewModel = AppViewModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    #if os(macOS)
        @State private var showAbout = false
    #endif
}
```

Notes:
- The explicit `init()` is removed — `@State private var viewModel = AppViewModel()` constructs it once per app instance (same lifetime as before). Default MainActor isolation on the app target lets `AppViewModel()` initialize inline.
- `appearanceMode` is read-only here as a source of truth for the Picker binding; the existing `@AppStorage("appearanceMode")` in `ContentView` and its `.onChange → handleAppearanceMode` path still apply the value. Both read/write the same `.standard` key, so they stay in sync via `UserDefaults` observation.
- `AboutView()` is wrapped in `NavigationStack` because it owns `.navigationTitle("About")`.
- Confirm `viewModel.store` compiles: `store` is already `internal`, so no store-exposure change is needed (the Stage-2 note was a confirm, not a wiring change).

#### 2. macOS command builder
**File**: `SingleThread/SingleThreadApp+Commands.swift`
**Action**: create (`#if os(macOS)` whole file)

```swift
#if os(macOS)
import AppKit
import SingleThreadCore
import SwiftUI

/// macOS app-menu chrome: About/Quit in the app menu, Complete/Skip for the
/// current reminder, and a System/Light/Dark appearance Picker. Store mutations
/// route through `ReminderStore` so `guard canMutate` stays authoritative; the
/// appearance Picker reuses `@AppStorage("appearanceMode")` and the existing
/// `.onChange → handleAppearanceMode` write path.
func appCommands(
    store: ReminderStore,
    appearanceMode: Binding<AppearanceMode>,
    showAbout: Binding<Bool>
) -> some Commands {
    CommandGroup(replacing: .appInfo) {
        Button("About SingleThread") {
            showAbout.wrappedValue = true
        }
    }

    CommandGroup(replacing: .appTermination) {
        Button("Quit SingleThread") {
            NSApplication.shared.terminate(nil)
        }
    }

    CommandMenu("Reminder") {
        Button("Complete Reminder") {
            Task { @MainActor in await store.completeCurrentReminder() }
        }
        .disabled(store.visibleReminders.first == nil)

        Button("Skip Reminder") {
            Task { @MainActor in store.skipCurrentReminder() }
        }
        .disabled(store.visibleReminders.first == nil)
    }

    CommandMenu("Appearance") {
        Picker("Appearance", selection: appearanceMode) {
            Text("System").tag(AppearanceMode.system)
            Text("Light").tag(AppearanceMode.light)
            Text("Dark").tag(AppearanceMode.dark)
        }
    }
}
#endif
```

Notes:
- Complete/Skip carry **no** `.keyboardShortcut`, per the design Open Risk, so they don't shadow the card-scoped `"c"`/`"s"` shortcuts in `ContentView+ActionMenu.swift`.
- `Task { @MainActor in ... }` is required here (not redundant): menu `Button` action closures are non-isolated, so a MainActor hop is needed before calling the `@MainActor` `ReminderStore` methods.

### Verification

#### Automated
- [x] `make mac-build` passes
- [x] `make mac-test` passes (regression: `AppearanceModeTests` `#if os(macOS)` branches unchanged)
- [x] `make format` then `make lint` pass (new file)

#### Manual
- [ ] `make mac-run` — Application menu has "About SingleThread" (opens the About sheet) and "Quit SingleThread" (exits); the Reminder menu's Complete/Skip mutate the current reminder; the Appearance Picker switches System/Light/Dark and the change applies immediately.

---

## Phase 4: `MenuBarExtra` — live next-reminder dropdown, hidden when nothing is due

### Changes

#### 1. Menu-bar scene
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify (extend `body`)

Inside `body`, after the `WindowGroup` (and before or after the `.commands` — sibling scene):

```swift
#if os(macOS)
if !viewModel.store.visibleReminders.isEmpty {
    MenuBarExtra("SingleThread", systemImage: "checkmark.circle") {
        MenuBarExtraOptions(store: viewModel.store)
    }
    .menuBarExtraStyle(.menu)
}
#endif
```

Notes:
- **Hide entirely**: `@SceneBuilder` `if` around the `MenuBarExtra` hides the item when no reminder is due. Reactivity comes from `@State private var viewModel` (added in Phase 3) + `visibleReminders` being an `@Observable` derived property, so `body` re-evaluates when reminders change.
- **Fallback** (if runtime insertion proves flaky on manual check): remove the `if`, always include the extra, and rely on `MenuBarExtraOptions` returning empty content when `visibleReminders.first == nil`.
- **Lifetime**: the extra and the window both read the same `viewModel.store` singleton, so the strip never goes stale — and is hidden/emptied as soon as the single visible reminder completes.

#### 2. Options view
**File**: `SingleThread/MenuBarExtraOptions.swift`
**Action**: create (`#if os(macOS)` whole file)

```swift
#if os(macOS)
import AppKit
import SingleThreadCore
import SwiftUI

/// `.menu`-style MenuBarExtra content: the next due reminder's title + due
/// date with Complete/Skip actions and an "Open SingleThread" launcher.
/// Renders nothing when no reminder is due (the scene is hidden upstream, but
/// this empty-content branch also serves as the documented fallback).
struct MenuBarExtraOptions: View {
    let store: ReminderStore

    var body: some View {
        if let reminder = store.visibleReminders.first {
            VStack(alignment: .leading, spacing: 8) {
                Text(reminder.title ?? "")
                    .font(.headline)
                if let due = reminder.dueDateComponents?.date {
                    Text(due, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button("Complete Reminder") {
                    Task { @MainActor in await store.completeCurrentReminder() }
                }
                Button("Skip Reminder") {
                    Task { @MainActor in store.skipCurrentReminder() }
                }
                Divider()
                Button("Open SingleThread") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
                }
            }
            .padding()
        }
    }
}
#endif
```

#### 3. Headless content tests
**File**: `SingleThreadTests/MenuBarExtraOptionsTests.swift`
**Action**: create (`#if os(macOS)` whole file)

```swift
#if os(macOS)
import Testing
import SingleThreadCore
@testable import SingleThread

@Suite(.serialized)
struct MenuBarExtraOptionsTests {
    @Test
    func rendersNextReminderActions() {
        let store = seededStore()
        let output = String(describing: MenuBarExtraOptions(store: store).body)
        #expect(output.contains("Buy groceries"))
        #expect(output.contains("Complete Reminder"))
        #expect(output.contains("Skip Reminder"))
        #expect(output.contains("Open SingleThread"))
    }

    @Test
    func rendersNothingWhenNoReminderDue() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [], calendars: []),
            loadsReminders: false)
        let output = String(describing: MenuBarExtraOptions(store: store).body)
        #expect(!output.contains("Complete Reminder"))
        #expect(!output.contains("Skip Reminder"))
        #expect(!output.contains("Open SingleThread"))
    }

    private func seededStore() -> ReminderStore {
        let inMemoryStore = InMemoryEventStore(reminders: [], calendars: [])
        let reminder = inMemoryStore.makeReminder(
            title: "Buy groceries",
            notes: nil,
            dueDate: nil,
            recurrenceRule: nil)
        return ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            entitlementStore: EntitlementStore(testingWithEntitled: true))
    }
}
#endif
```

Note: `visibleReminders` filters only by `skippedIDs` + `excludedListTitles` (verified), so a single un-skipped undated reminder renders regardless of `showsUndatedReminders`.

### Verification

#### Automated
- [x] `make mac-build` passes (via the documented fallback — the plan's conditional `if !visibleReminders.isEmpty` scene crashes the Swift 6 compiler with "failed to produce diagnostic for expression" in the SceneBuilder, so the extra is always included and `MenuBarExtraOptions` returns empty content when nothing is due)
- [x] `make mac-test` passes (new `MenuBarExtraOptionsTests` both green on macOS; only the two pre-existing StoreKit `EntitlementStoreTests` fail)
- [x] `make format` then `make lint` pass (new files)

#### Manual
- [ ] `make mac-run` — the menu-bar item (always present under the compiler-crash fallback) shows the next due reminder's title/actions when one is due and an empty menu when none is due; Completing/Skipping mutates the reminder and clears the strip; "Open SingleThread" activates and fronts the window.

---

## Testing Checkpoints (resume-if-context-resets)

1. **Phase 1 green** → `NotificationSchedulerTests` passes on `make mac-test` **and** `make test`.
2. **Phase 2 green** → iOS notification UI tests unchanged + `make mac-build` + `make mac-test`.
3. **Phase 3 green** → `AppearanceModeTests` unchanged + `make mac-build` + `make mac-test`.
4. **Phase 4 green** → `MenuBarExtraOptionsTests` passes + `make mac-build` + `make mac-test`.
5. **Final** → `make format` then `make lint`, then the full `./scripts/test.sh` ONCE (parent/dedicated final phase — includes the macOS `-only-testing:SingleThreadTests` step at `scripts/test.sh:286-292`). Do not re-run the full gate per phase.

## Out of scope (reiterate)

- No macOS UI tests (var-788 decision — macOS verified by unit run + `make mac-run`).
- No `UNUserNotificationCenterDelegate`/foreground-banner handling this ticket (see resolved amendment 3).
- No WidgetKit macOS investigation; no `.window`-style menu-bar strip; no appearance sync to widget/watch; no new persistence keys; no repeating timer.