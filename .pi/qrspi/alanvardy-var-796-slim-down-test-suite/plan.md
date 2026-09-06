# Implementation Plan

## Overview

Add a `UserNotificationCentering` protocol seam to make notification-scheduling logic unit-testable; extract scheduling into a `NotificationScheduler` service; add `--ui-testing-noop-settle` and `--ui-testing-reduced-glow` launch args to skip production timing in UI tests; cut ~30 redundant UI tests whose behavior is already proven at the unit layer. ~52 iOS UI tests → ~22.

---

## Phase 1: Protocol seam — `UserNotificationCentering`

Declare the protocol, add the real `UNUserNotificationCenter` conformance, and ship a recording fake. No production wiring yet.

### Changes

#### 1. New protocol + fake
**File**: `SingleThreadCore/Sources/SingleThreadCore/UserNotificationCentering.swift`
**Action**: create

```swift
import UserNotifications

/// Test seam: wraps the UNUserNotificationCenter surface the app calls so tests
/// can inject a recording fake. Follows the EventKitStoring / SpeechTranscribing pattern.
@MainActor
public protocol UserNotificationCentering: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
}

// Real conformance
extension UNUserNotificationCenter: UserNotificationCentering {
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

// Recording fake for unit tests.
// @unchecked Sendable: mutable stored-property writes are
// confined to @MainActor in the test target.
public final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    // MARK: Authorization

    public var authorizationRequested = false
    public var authorizationOptions: UNAuthorizationOptions?
    /// Injected result for requestAuthorization — default true.
    public var authorizationResult = true

    // MARK: Authorization status

    /// The status `authorizationStatus()` returns. Default `.notDetermined`.
    public var authorizationStatusOverride: UNAuthorizationStatus = .notDetermined

    // MARK: Scheduling

    public private(set) var addedRequests: [UNNotificationRequest] = []

    // MARK: Removal

    public private(set) var removedPendingIdentifiers: [String] = []
    public private(set) var removedDeliveredIdentifiers: [String] = []

    // MARK: Init

    public init() {}

    // MARK: UserNotificationCentering

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequested = true
        authorizationOptions = options
        return authorizationResult
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusOverride
    }

    public func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.pped(contentsOf: identifiers)
    }
}
```

**Design deviation**: the protocol exposes `authorizationStatus() async -> UNAuthorizationStatus` instead of `notificationSettings() async -> UNNotificationSettings`. `UNNotificationSettings` has no public initializer, so a fake cannot vend different authorization statuses. The app only reads `.authorizationStatus` from the settings object — this simpler protocol captures exactly what the app needs and lets the fake return any status.

#### 2. Protocol tests
**File**: `SingleThreadTests/UserNotificationCenteringTests.swift`
**Action**: create

Six tests against `FakeUserNotificationCenter`:

```swift
import SingleThreadCore
import Testing
import UserNotifications

@MainActor
struct UserNotificationCenteringTests {
    @Test
    func fakeRecordsAuthorizationRequest() async throws {
        let fake = FakeUserNotificationCenter()
        _ = try await fake.requestAuthorization(options: [.alert, .badge])
        #expect(fake.authorizationRequested)
        #expect(fake.authorizationOptions == [.alert, .badge])
    }

    @Test
    func fakeRecordsAuthorizationFailure() async throws {
        let fake = FakeUserNotificationCenter()
        fake.authorizationResult = false
        let result = try await fake.requestAuthorization(options: [])
        #expect(!result)
    }

    @Test
    func fakeRecordsAddedRequest() async throws {
        let fake = FakeUserNotificationCenter()
        let content = UNMutableNotificationContent()
        content.title = "Test"
        let request = UNNotificationRequest(identifier: "id", content: content, trigger: nil)
        try await fake.add(request)
        #expect(fake.addedRequests.count == 1)
        #expect(fake.addedRequests[0].dentifier == "id")
    }

    @Test
    func fakeRecordsRemovedPending() {
        let fake = FakeUserNotificationCenter()
        fake.removePendingNotificationRequests(withIdentifiers: ["a", "b"])
        #expect(fake.removedPendingIdentifiers == ["a", "b"])
    }

    @Test
    func fakeRecordsRemovedDelivered() {
        let fake = FakeUserNotificationCenter()
        fake.removeDeliveredNotifications(withIdentifiers: ["x"])
        #expect(fake.removedDeliveredIdentifiers == ["x"])
    }

    @Test
    func fakeReturnsInjectedAuthorizationStatus() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .denied
        let status = await fake.authorizationStatus()
        #expect(status == .denied)
    }
}
```

### Verification

#### Automated
- [x] `make build` — new file compiles into SingleThreadCore + test target
- [x] `xcodebuild -scheme "$SCHEME" -destination "$SIM" -derivedDataPath "$DERIVED_DATA" test-without-building -only-testing:SingleThreadTests/UserNotificationCenteringTests` — 6 tests green

#### Manual
- [ ] None

---

## Phase 2: Notification scheduling logic extracted and unit-tested

Extract the scheduling, cancellation, and permission-check logic from `AppViewModel.swift:80-143` into a new `NotificationScheduler` service that consumes `UserNotificationCentering`. Wire the real center in production; inject the fake in tests.

### Changes

#### 1. New scheduler service
**File**: `SingleThreadCore/Sources/SingleThreadCore/NotificationScheduler.swift`
**Action**: create

```swift
import Foundation
import UserNotifications

/// Schedules and cancels local idle-notification reminders.
/// Consumes `UserNotificationCentering` so tests inject a recording fake.
@MainActor
public final class NotificationScheduler {
    // MARK: Lifecycle

    public init(
        center: any UserNotificationCentering = UNUserNotificationCenter.current(),
        enabledKey: String = "notificationsEnabled",
        intervalHoursKey: String = "notificationIntervalHours",
        idleIdentifier: String = "app.alanvardy.SingleThread.idle-reminder",
        defaults: UserDefaults = UserDefaults.standard) {
        self.center = center
        self.enabledKey = enabledKey
        self.intervalHoursKey = intervalHoursKey
        self.idleIdentifier = idleIdentifier
        self.defaults = defaults
    }

    // MARK: Public

    /// True only under `--ui-testing-notifications`; gates the status overlay.
    public var isUITestingNotifications: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications")
    }

    /// The last successfully-scheduled request snapshot (for UI-test seam).
    public private(set) var lastScheduleSummary: String?

    /// The current pending-notification snapshot (for UI-test seam).
    public private(set) var pendingSummary: String?

    /// Requests notification authorization (.alert + .badge) if status is
    /// `.notDetermined`. No-op otherwise (already granted or denied).
    /// When denied or the request throws, flips the enabled key to `false`
    /// so the UI toggle reflects reality.
    public func requestPermissionIfNeeded() async {
        let status = await center.authorizationStatus()
        switch status {
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .badge])
            } catch {
                defaults.set(false, forKey: enabledKey)
                return
            }
            if !granted {
                defaults.set(false, forKey: enabledKey)
            }
        default:
            break // already determined
        }
    }

    /// Cancels any pending idle reminder, then schedules a new one if
    /// notifications are enabled and `reminderCount > 0 || hasHidden`.
    /// The trigger fires after `intervalHours` (default 48h) with the
    /// reminder count in the body.
    public func scheduleIfNeeded(reminderCount: Int, hasHidden: Bool) async {
        await refreshPendingSummary()

        center.removePendingNotificationRequests(withIdentifiers: [idleIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [idleIdentifier])

        guard defaults.bool(forKey: enabledKey) else {
            lastScheduleSummary = nil
            return
        }
        guard reminderCount > 0 || hasHidden else {
            lastScheduleSummary = nil
            return
        }

        let intervalHours = defaults.integer(forKey: intervalHoursKey)
        let effectiveHours = intervalHours > 0 ? intervalHours : 48

        let content = UNMutableNotificationContent()
        content.title = String(localized: "SingleThread", table: "Localizable", bundle: .main)
        content.body = String(
            localized: "You have \(reminderCount) reminders waiting — open SingleThread!",
            table: "Localizable",
            bundle: .main)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(effectiveHours * 3600),
            repeats: false)

        let request = UNNotificationRequest(
            identifier: idleIdentifier,
            content: content,
            trigger: trigger)

        do {
            try await center.add(request)
            await refreshPendingSummary()
            lastScheduleSummary = Self.summary(requests: [request])
        } catch {
            lastScheduleSummary = nil
        }
    }

    /// Cancels all pending and delivered notifications.
    public func cancelAll() async {
        center.removePendingNotificationRequests(withIdentifiers: [idleIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [idleIdentifier])
        await refreshPendingSummary()
    }

    // MARK: Private

    private let center: any UserNotificationCentering
    private let enabledKey: String
    private let intervalHoursKey: String
    private let idleIdentifier: String
    private let defaults: UserDefaults

    private func refreshPendingSummary() async {
        guard isUITestingNotifications else { return }
        // Only the real center supports pendingNotificationRequests();
        // fake tests skip the summary path.
        guard let realCenter = center as? UNUserNotificationCenter else { return }
        let requests = await realCenter.pendingNotificationRequests()
        pendingSummary = Self.summary(requests: requests)
    }

    /// Renders a pending-notification snapshot as a stable key=value
    /// status string for the UI-test seam.
    private static func summary(requests: [UNNotificationRequest]) -> String {
        guard let first = requests.first else { return "count=0" }
        let interval = (first.trigger as? UNTimeIntervalNotificationTrigger)
            .map { Int($0.timeInterval.rounded()) } ?? -1
        return "count=\(requests.count)\nid=\(first.identifier)\nbody=\(first.content.body)\ninterval=\(interval)"
    }
}
```

**Design note**: the `pendingNotificationRequests()` query is real-center-omly, so the UI-test seam summary only works with the production default. The `isUITestingNotifications` gate is kept on the scheduler (was on `AppViewModel`); the status overlay in `ContentView+iOS` reads `scheduler.pendingSummary` / `scheduler.lastScheduleSummary`.

#### 2. Scheduler unit tests
**File**: `SingleThreadTests/NotificationSchedulerTests.swift`
**Action**: create

Eight tests against `FakeUserNotificationCenter`:

```swift
import Foundation
@testable import SingleThreadCore
import Testing
import UserNotifications

@MainActor
struct NotificationSchedulerTests {
    /// Builds a scheduler against a recording fake + ephemeral UserDefaults.
    private static func makeScheduler(
        center: FakeUserNotificationCenter = FakeUserNotificationCenter(),
        enabled: Bool = true,
        intervalHours: Int = 48) -> NotificationScheduler {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set(enabled, forKey: "notificationsEnabled")
        defaults.set(intervalHours, forKey: "notificationIntervalHours")
        return NotificationScheduler(
            center: center,
            defaults: defaults)
    }

    @Test
    func schedulesWhenEnabled() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 2, hasHidden: false)
        #expect(fake.addedRequests.count == 1)
        let request = fake.addedRequests.first
        #expect(request?.identifier == "app.alanvardy.SingleThread.idle-reminder")
        #expect(request?.content.body.contains("2 reminders") == true)
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 172800) // 48h default
    }

    @Test
    func skipsScheduleWhenDisabled() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake, enabled: false)
        await scheduler.scheduleIfNeeded(reminderCount: 5, hasHidden: false)
        #expect(fake.addedRequests.isEmpty)
    }

    @Test
    func skipsScheduleWhenNoReminders() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 0, hasHidden: false)
        #expect(fake.addedRequests.isEmpty)
    }

    @Test
    func schedulesWhenHasHidden() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 0, hasHidden: true)
        #expect(fake.addedRequests.count == 1)
    }

    @Test
    func requestsPermissionWhenNotDetermined() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .notDetermined
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.requestPermissionIfNeeded()
        #expect(fake.authorizationRequested)
        #expect(fake.authorizationOptions == [.alert, .badge])
    }

    @Test
    func skipsPermissionWhenAlreadyAuthorized() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .authorized
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.requestPermissionIfNeeded()
        #expect(!fake.authorizationRequested)
    }

    @Test
    func cancelRemovesPendingAndDelivered() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.cancelAll()
        #expect(fake.removedPendingIdentifiers.contains("app.alanvardy.SingleThread.idle-reminder"))
        #expect(fake.removedDeliveredIdentifiers.contains("app.alanvardy.SingleThread.idle-reminder"))
    }

    @Test
    func scheduleReplacesExistingPending() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 1, hasHidden: false)
        await scheduler.scheduleIfNeeded(reminderCount: 2, hasHidden: false)
        // Second schedule removes the first request's id        #expect(fake.removedPendingIdentifiers.count >= 2) // once each schedule
        #expect(fake.addedRequests.count == 2) // both schedules added

    @Test
    func usesConfigredInterval() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake, intervalHours: 24)
        await scheduler.scheduleIfNeeded(reminderCount: 1, hasHidden: false)
        let trigger = fake.addedRequests.first?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 86400) // 24h
    }
}
```

#### 3. Wire scheduler into AppViewModel
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

Three changes:

**(a) Add a `NotificationScheduler` property** (near the existing notification fields, ~line 48-60):

```swift
// In AppViewModel:
#if os(iOS)
    let notificationScheduler = NotificationScheduler()
#endif
```

**(b) Replace `scheduleNotificationIfNeeded()` body** (~lines 78-120) with a delegation to the scheduler:

```swift
#if os(iOS)
    func scheduleNotificationIfNeeded() async {
        await notificationScheduler.scheduleIfNeeded(
            reminderCount: store.visibleReminders.count,
            hasHidden: store.hasHidden)
    }
#endif
```

**(c) Replace `cancelNotifications()` body** (~lines 123-126):

```swift
#if os(iOS)
    func cancelNotifications() async {
        await notificationScheduler.cancelAll()
    }
#endif
```

**(d) Replace `requestNotificationPermissionIfNeeded()` body** (~lines 130-143):

```swift
#if os(iOS)
    func requestNotificationPermissionIfNeeded() async {
        await notificationScheduler.requestPermissionfNeeded()
    }
#endif
```

**(e) Update the `pendingSummary` / `lastScheduleSummary` getters** (~lines 63-69) to delegate to the scheduler:

```swift
#if os(iOS)
    var pendingSummary: String? { notificationScheduler.pendingSummary }
    var lastScheduleSummary: String? { notificationScheduler.lastScheduleSummary }
#endif
```

Remove the old `pendingSummary` and `lastScheduleSummary` stored properties and the `refreshPendingSummary()` / `summary(requests:)` private methods (~lines 411-435).

Remove the `idleReminderIdentifier` constant (~line 58) — now lives on the scheduler.

**(f) Keep the overlay wiring intact**: `ContentView+iOS.swift:16-33` reads `appViewModel?.pendingSummary` / `appViewModel?.lastScheduleSummary` — those now delegate to the scheduler, no content changes needed.

#### 4. Remove unused `UNUserNotificationCenter` import
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

If `UNUserNotificationCenter` is no longer directly referenced, remove the `import UserNotifications` (check if `UNMutableNotificationContent` etc. are still in AppViewModel — they move to the scheduler, so the import should be removable).

### Verification

#### Automated
- [x] `xcodebuild -scheme "$SCHEME" -destination "$SIM" -derivedDataPath "$DERIVED_DATA" test-without-building -only-testing:SingleThreadTests/NotificationSchedulerTests` — 9 tests green
- [ ] `./scripts/test.sh` — full gate (format, lint, build, Periphery, all unit + UI + watch + macOS). All existing tests pass; no regressions from the wiring change.

#### Manual
- [ ] Build and run on iOS simulator — toggle notifications in Settings, background the app, verify notification is scheduled (check in Notification Center).

---

## Phase 3: Timing injection seams for UI tests

Add `--ui-testing-noop-settle` and `--ui-testing-reduced-glow` launch args so the UI-test host skips the 200ms EventKit settle and shortens the glow. Follows the exising `--ui-testing-glow` pattern.

### Changes

#### 1. Parse new launch args in AppViewModel
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In `makeContentViewModel` (near line 216-221, the existing `--ui-testing-glow` block):

```swift
// After the existing --ui-testing-glow block:
if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduced-glow") {
    viewModel.comletionGlow.duration = 0.1
}
```

In `makeStore` (~line 257-285), parse `--ui-testing-noop-settle`:

```swift
let noopSettle: ReminderStoreSettle = {}
let useNoopSettle = arguments.contains("--ui-testing-noop-settle")

// In the --ui-testing branch (around line 280), inject settle:
return (ReminderStore(
    eventStore: inMemoryStore,
    loadsReminders: false,
    reminders: [reminder],
    skippedIDs: [],
    authorizationStatus: .fullAccess,
    entitlementStore: EntitlementStore(testingWithEntitled: false),
    settle: useNoopSettle ? noopSettle : { try? await Task.sleep(nanoseconds: 200_000_000) }), false)
```

For `--seed` paths in `seededStore` (~line 302-333), similarly inject the `settle:` parameter when `useNoopSettle` is true.

#### 2. Add new args to UI test launches
**File**: `SingleThreadUITests/SingleThreadUITestCase.swift`
**Action**: modify

In `launchSeeded()` (~line 22-35):

```swift
@MainActor
func launchSeeded(_ json: String, extra: [String] = []) -> XCUIApplication {
    launchApp(arguments: [
        "--seed", json,
        "--ui-testing-noop-settle",
        "--ui-testing-reduced-glow"
    ] + extra)
}
```

In `launchApp()` (keep as-is — it accepts arbitrary arguments).

#### 3. Smoke-test a mutation-bearing UI test
**File**: No source changes — verification only.

Run one UI test with the new args to confirm the app doesn't timeout:

```bash
xcodebuild -scheme "$SCHEME" -destination "$SIM" -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testCompleteViaswipeRemovesReminder
```

### Verification

#### Automated
- [ ] `make build` — compiles with new arg parsing
- [ ] `make test` — all 470+ unit tests green (including the new ones from Layers 1-2)
- [ ] One smoke UI test with new args passes (timing assertions out of scope — success = doesn't timeout)

#### Manual
- [ ] None

---

## Phase 4: UI test removal — cut ~30 redundent tests

Audit each of the duplicative UI tests against its unit coverage. Cut the ones where the unit layer already proves the behavior thoroughly. Keep integration-only tests.

### Tests to CUT

#### `SingleThreadUITests/NotificationSchedulingUITests.swift` — cut all 4

These are fully replaced by `NotificationSchedulerTests` (Layer 2). Delete all four test methods. Keep the file (it may be empty — that's fine with Xcode's auto-discovery; the empty class won't run tests).

- [ ] `testSchedulingOnBakground`
- [ ] `testCancelOnForeground`
- [ ] `testNoScheduleWhenDisabled`
- [ ] `testNoScheduleWhenNoReminders`

#### `SingleThreadUITests/NotificationsUITests.swift` — cut 1, keep 1

- [ ] CUT `testFullNotificationFlow` — scheduling + interval picker round-trip covered by `NotificationSchedulerTests` + `NotificationsSettingsUITests`
- [ ] KEEP `testAccessibilityAudit` — integration-only (a11y audit of notifications settings)

#### `SingleThreadUITests/SingleThreadUITestsFlows.swift` — cut 17, keep 12

**KEEP (12 integration-only):**
- `testListShowsSeededReminder` — rendered copy
- `testEmptyListShowsNoRemindersState` — rendered copy
- `testNothingDueShowsWhenRemindersHidden` — rendered copy
- `testSkipWithCrossDeviceComletionShowsOnlyRemainingReminder` — cross-device skip refetch (edge case with multi-step EK event flow)
- `testAboutModalShowsAttribution` — rendered copy
- `testBackgroundAndPinTogglesPersistAcrossRelaunch` — relaunch persistence
- `testReminderTogglesPersistAcrossRelaunch` — relaunch persistence
- `testCodeBlocksRenderWithoutBactickFences` — rendered copy
- `testSwipePromptAppearsUnderUITesting` — UI-only a11y label (SwipePromptTests deferrs)
- `testDismissSwipePromptHidesItAndPersistsAcrossRelaunch` — relaunch persistence (swipe-prompt key)
- `testPurchaseSheetHasRestoreButton` — no unit equivalent (restore button)
- `testBackgroundRefreshButtonExists` — layout integration

**CUT (17 — behavior dupliated at unit layer):**
- [ ] `testSkipAdvancesToNextReminder` — skip, ReminderStoreTests/ReminderSkipTests
- [ ] `testPriorityMarkerRendersForMidRangeValue` — priority marker, ReminderSkipTests
- [ ] `testSkipAllShowsAllDoneState` — skip-to-empty, ReminderStoreTests
- [ ] `testCompleteViaswipeRemovesReminder` — complete, ReminderStoreTests/ReminderStoreGateTests
- [ ] `testDeleteViaContextMenuRemovesReminder` — delete, EventKitStoringTests/ReminderStoreGateTests
- [ ] `testViewInRemindersOpensURL` — deep link, ReminderDeepLinkTests/ContentViewModelTests
- [ ] `testSettingsOpensAndShowsControls` — settings navigation, SettingsViewTests/SettingsViewModelTests
- [ ] `testCompletionGlowDoesNotApearWhenDisabled` — glow toggle, CompletionGlowTests
- [ ] `testCompletionGlowFlashesWhenEnabled` — glow active, CompletionGlowTests
- [ ] `testSwipePromptToggleRoundTripsViaSettings` — swipe prompt toggle, SwipePromptTests
- [ ] `testUndoButtonApearsAfterCompleteAndUndoRemovesReminder` — undo, UndoStoreTests/ReminderStoreTests
- [ ] `testUndoButtonHiddenWhenToggleOff` — undo toggle, UndoStoreTests
- [ ] `testUndoButtonDoesNotApearWithoutComletion` — undo state, UndoStoreTests
- [ ] `testUprgadePromptApearsWhenGated` — freemium gate, ReminderStoreGateTests (except restore button)
- [ ] `testActionClusterApearsWhenEntitledAtCap` — freemium gate entitled, EntitlementStoreTests
- [ ] `testUnresolvedEntitlementRendersNoUprgadeButton` — freemium gate unresolved, EntitlementStoreTests
- [ ] `testSettingsHasPurchseRow` — purchase row exists, EntitlementStoreTests

#### `SingleThreadUITests/ActionMenuUITests.swift` — cut all 4

All four test action-menu flows that are dupliated at the unit layer (ActionMenuGateTests, RescheduleSheetTests, EventKitStoringTests):

- [ ] `testActionMenuSkipAdvancesWhenToggleOn`
- [ ] `testActionMenuDeleteRemovesWhenToggleOn`
- [ ] `testActionMenuRescheduleShowsSheetWhenToggleOn`
- [ ] `testSkipActsDirectlyWhenToggleOff`

Keep the file (empty class). The action buttons rendering + a11y audit live in `ActionButtonsUITests.swift` (untouched).

#### `SingleThreadUITests/SkipNudgeUITests.swift` — cut 3, keep 1

- [ ] CUT `testSkipNudgeBannerApearsAfterSixthSkipAndDeletes` — nudge threshold, SkipCountStoreTests/ReminderStoreTests
- [ ] CUT `testSkipNudgeRescheduleActs` — nudge reschedule, RescheduleSheetTests
- [ ] CUT `testSkipNudgeViewInRemindersOpensURL` — nudge deep link, ReminderDeepLinkTests
- [ ] KEEP `testNudgedCardDoesNotSpannRowOnIPad` — iPad frame geometry (integration-only)

---

### Tests NOT touched (keep all)

These files are left unchanged:
- `SingleThreadUITests.swift` — full a11y audit (integration-only)
- `SingleThreadUITestsLaunchTests.swift` — launch + screenshot
- `SingleThreadUITestsApearanceLaunchTests.swift` — 3 cold-launch appearance tests
- `ActionButtonsUITests.swift` — 2 tests (action buttons render + a11y audit)
- `NotificationsSettingsUITests.swift` — 2 tests (toggle exists + interval picker options)
- `SingleThreadUITestCase.swift` — base class (modified in Phase 3, no test removal)

### Changes to test.sh

No changes needed. `scripts/test.sh` uses broad `-only-testing:SingleThreadUITests` target filters (the entire suite), not individual test names. Deleting test methods from within files doesn't affect the test runner invocation.

### Verification

#### Automated
- [ ] `./scripts/test.sh` — full gate passes. All remaining ~22 iOS UI tests + all unit + watch + macOS tests green.
- [ ] `make lint` — no dead code warnings for the cut tests.
- [ ] `make periphery` — no new dead-code detections from the scheduler wiring.

#### Manual
- [ ] Optionally: `make coverage` diff to confirm behaviors moved from UI to unit still show in the unit coverage report.

---

## Testing Checkpoints

| After Layer | What must be green |
|---|---|
| 1 | 6 `UserNotificationCenteringTests` + `make build` |
| 2 | 9 `NotificationSchedulerTests` + `./scripts/test.sh` (no regressions) |
| 3 | All unit tests + 1 smoke UI test with new args |
| 4 | `./scripts/test.sh` full gate — ~22 remaining iOS UI tests, all unit tests |

---

## Cross-Cutting Notes

- **No new Xcode targets, no pbxproj edits** — new `.swift` files in `SingleThreadCore/` and `SingleThreadTests/` are auto-discovered (`objectVersion 77`).
- **Suite serialization untouched** — no `@Suite(.serialized)` annotations are added or removed.
- **Relaunch-persistence trio keeps its 200ms settle** — `launchSeeded()` injects `--ui-testing-noop-settle`, but the persistence tests use `launchApp(arguments: ["--ui-testing"])` without the settle flag (they exercise `makeStore`'s `--ui-testing` branch at line ~279, which the plan's `useNoopSettle` check covers). Double-check during implementation: the `--ui-testing` path in `makeStore` must NOT inject `settle:` when the flag is absent, so the persistence tests keep the production 200ms default.
- **Watch glow timing out of scope** — `--ui-testing-reduced-glow` is iOS-only. Watch uses a separate `--ui-testing-glow` seam in `WatchAppViewModel`.
- **`NotificationScheduler` is `@MainActor`** because the iOS app target has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the service lives on the view model.
- **Status overlay seam preserved** — `ContentView+iOS.swift` reads `appViewModel?.pendingSummary` / `lastScheduleSummary` which now delegate to the scheduler; the `--ui-testing-notifications` flag and overlay rendering are unchanged. `isUITestingNotifications` lives on the scheduler instead of `AppViewModel`.
- **`noopSettle` is `{}`** — inline it directly in `AppViewModel.makeStore()`; no need to export from `SingleThreadCore`.