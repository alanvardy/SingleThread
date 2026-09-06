# Structure Outline

## Approach

Add a `UserNotificationCentering` protocol seam (matching the proven `EventKitStoring` pattern) to make notification-scheduling logic unit-testable; inject timing-override launch args into the UI-test host; then cut ~20 UI tests whose behavior is already proven at the unit layer. Each layer is fully tested before the next begins.

---

## Layer 1: Protocol seam — `UserNotificationCentering`

Declare the protocol, add the real `UNUserNotificationCenter` conformance, and ship a recording fake. No production wiring yet — this layer proves the contract shape and the fake's recording fidelity.

**Files**:
- **New**: `SingleThreadCore/Sources/SingleThreadCore/UserNotificationCentering.swift`
- **New**: `SingleThreadTests/UserNotificationCenteringTests.swift`

**Key changes**:
```swift
// UserNotificationCentering.swift — protocol wrapping the 5 UNUserNotificationCenter
// methods the app actually uses (design.md §DD3, research.md Q4)
protocol UserNotificationCentering: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
}

// Real conformance
extension UNUserNotificationCenter: UserNotificationCentering {}

// Recording fake
final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    private(set) var authorizationRequested = false
    private(set) var authorizationOptions: UNAuthorizationOptions?
    private(set) var authorizationResult = true   // injected for sad-path tests
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPending: [String] = []
    private(set) var removedDelivered: [String] = []
    private(set) var settingsResult = UNNotificationSettings(…) // default: notDetermined
}
```

**Tests** (`UserNotificationCenteringTests.swift`):
- `fakeRecordsAuthorizationRequest` — happy path
- `fakeRecordsAuthorizationFailure` — sad path (result = false)
- `fakeRecordsAddedRequest` — `add(_:)` stores the request
- `fakeRecordsRemovedPending` — identifiers captured
- `fakeRecordsRemovedDelivered` — identifiers captured
- `fakeReturnsInjectedSettings` — settings result round-trips

**Verify**: `make build` passes (new file compiles into SingleThreadCore + test target). Run `xcodebuild -only-testing:SingleThreadTests/UserNotificationCenteringTests -destination …` — all 6 tests green.

---

## Layer 2: Notification scheduling logic extracted and unit-tested

Extract the scheduling, cancellation, and permission-check logic from `AppViewModel.swift:80-138` into a new service that consumes `UserNotificationCentering`. Wire the real center in production; inject the fake in tests. The 6 notification UI tests (4 scheduling + 2 flow) are now covered at the unit layer.

**Files**:
- **New**: `SingleThreadCore/Sources/SingleThreadCore/NotificationScheduler.swift`
- **New**: `SingleThreadTests/NotificationSchedulerTests.swift`
- **Modified**: `SingleThread/AppViewModel.swift` — replace direct `UNUserNotificationCenter.current()` calls with the scheduler; inject real center in `makeStore()`

**Key changes**:
```swift
// NotificationScheduler.swift — a @MainActor service (iOS target has
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor)
@MainActor
final class NotificationScheduler {
    private let center: any UserNotificationCentering
    init(center: any UserNotificationCentering = UNUserNotificationCenter.current()) { … }

    func requestPermissionIfNeeded() async
    // Guards notificationSettings().authorizationStatus == .notDetermined,
    // then calls center.requestAuthorization(options: [.alert, .badge])

    func scheduleIfNeeded(reminderCount: Int, intervalHours: Int) async
    // Cancels pending, then schedules a new .timeInterval trigger with the
    // count in the body. Extracted from AppViewModel.swift:80-110.

    func cancelAll() async
    // removePendingNotificationRequests + removeDeliveredNotifications
}
```

**Test scenarios** (`NotificationSchedulerTests.swift`):
- `schedulesWhenAuthorized` — schedule call adds exactly one request
- `skipsScheduleWhenDenied` — authorizationStatus = .denied, no request added
- `requestsPermissionWhenNotDetermined` — `.notDetermined` → calls requestAuthorization
- `skipsPermissionWhenAlreadyAuthorized` — `.authorized` → no second request
- `cancelRemovesPendingAndDelivered` — `cancelAll()` clears both stores
- `scheduleReplacesExistingPending` — second schedule removes the first request's id
- `requestBodyContainsReminderCount` — the notification body string reflects the count
- `usesConfiguredInterval` — interval parameter flows into the trigger

**Verify**: Run `xcodebuild -only-testing:SingleThreadTests/NotificationSchedulerTests -destination …` — all tests green. Then run the full `./scripts/test.sh` gate to confirm the wiring doesn't break existing tests (the real `UNUserNotificationCenter.current()` is still the production default).

---

## Layer 3: Timing injection seams for UI tests

Add `--ui-testing-noop-settle` and `--ui-testing-reduced-glow` launch args so the UI-test host skips the 200 ms EventKit settle and shortens the glow. These are consumed in `AppViewModel.makeStore()` and the existing `--ui-testing-glow` path respectively; they require no new production types, only launch-arg parsing and injection.

**Files**:
- **Modified**: `SingleThread/AppViewModel.swift` — parse new args in `init` / `makeStore`, pass `settle:` to `ReminderStore`
- **Modified**: `SingleThreadUITests/SingleThreadUITestCase.swift` — add the new args to `launchSeeded()` and `launchApp()`
- **Modified** (if needed): `SingleThreadTests/UITestingSeedTests.swift` — coverage for new arg parsing

**Key changes**:
```swift
// AppViewModel.swift — parse in init (follows existing --ui-testing-glow pattern, :216-221)
let noopSettle = CommandLine.arguments.contains("--ui-testing-noop-settle")
let reducedGlow = CommandLine.arguments.contains("--ui-testing-reduced-glow")

// In makeStore (around :257-285), inject settle when flagged:
settle: noopSettle ? noopSettle : defaultSettle

// In completionGlowDuration (around :216-221), shorten when flagged:
if reducedGlow { return 0.1 }  // vs existing 2.0s test-glow, 0.5s production
```

`noopSettle` is the existing `{ Thread.sleep(forTimeInterval: 0) }` closure from `ReminderStoreTests.swift:12` — either hoist it into `SingleThreadCore` as a public constant or define it in `AppViewModel` and pass it.

**Tests** — extent existing patterns:
- `UITestingSeedTests`: add cases for `--ui-testing-noop-settle` → settle is noop
- `UITestingSeedTests`: add case for `--ui-testing-reduced-glow` → glow duration ≤ 0.1s
- Smoke: launch one mutation-bearing UI test (e.g. `testCompleteOneReminder`) and confirm it doesn't timeout (sanity check only; timing assertions stay out of scope per design.md §"What We're NOT Doing")

**Verify**: `make build` passes. Run `make test` — all 470 unit tests green. Run one UI test with the new args: `xcodebuild -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testCompleteOneReminder -destination …` passes. No timing assertions; the checkpoint is correctness, not speed.

---

## Layer 4: UI test removal — cut ~20 redundant tests

Audit each of the 40 duplicated UI tests (research.md Q3) against its unit coverage. Cut the ones where the unit layer already proves the behavior thoroughly — complete, delete, undo, skip, show-list/glow toggles, freemium gate (excluding the restore-button test), priority marker, background/pin selection, deep link, settings navigation, reschedule, nudge-banner dismissal. Keep integration-only tests (relaunch persistence trio, a11y audits, rendered copy, iPad geometry, purchase restore, interval picker, watch live-exclusion, 0-1 notification E2E smoke test).

**Files**:
- **Modified**: `SingleThreadUITests/SingleThreadUITestsFlows.swift` — remove targeted test methods
- **Modified**: `SingleThreadUITests/ActionMenuUITests.swift` — remove duplicative tests
- **Modified**: `SingleThreadUITests/SkipNudgeUITests.swift` — remove duplicative tests
- **Modified**: `SingleThreadUITests/NotificationSchedulingUITests.swift` — gut or remove (keep 0-1 smoke test)
- **Modified**: `SingleThreadUITests/NotificationsUITests.swift` — gut or remove (keep a11y audit)
- **Modified**: `scripts/test.sh` — remove `-only-testing:` entries for deleted tests (if any explicit entries exist)

**Test changes** (no new tests — this layer removes, not adds):
- Before cutting each test, confirm the unit equivalent is green and comprehensive
- After cuts, the remaining ~32 UI tests must all pass
- The notification family collapses from 6 tests to 0-1 E2E smoke test; the smoke test (if kept) still hits the real `UNUserNotificationCenter` via the scheduler's production default

**Verify**: `./scripts/test.sh` full gate — all remaining unit + UI + watch + macOS tests pass. Optionally: `make coverage` diff to confirm the behaviors moved from UI to unit still show in the unit coverage report.

---

## Testing Checkpoints (for context resumption)

| After Layer | What must be green |
|---|---|
| 1 | 6 `UserNotificationCenteringTests` + `make build` |
| 2 | 8 `NotificationSchedulerTests` + `./scripts/test.sh` (no regressions) |
| 3 | All 470 unit tests + 1 smoke UI test with new args |
| 4 | `./scripts/test.sh` full gate — ~32 remaining UI tests, all unit tests |

---

## Cross-Cutting Notes

- **No new Xcode targets, no pbxproj edits** — new `.swift` files in `SingleThreadCore/` and `SingleThreadTests/` are auto-discovered (AGENTS.md: objectVersion 77 synchronized file groups).
- **Suite serialization is a non-lever** — no `@Suite(.serialized)` annotations are touched (design.md §DD5).
- **The relaunch-persistence trio keeps its 200 ms settle** — removing it could expose order-of-operations bugs the settle masks. The timing seams apply everywhere else (design.md §Open Risks).
- **Watch glow timing (`WatchReminderViewModel.completionTransitionBuffer`, 0.5s) is out of scope** — the `--ui-testing-reduced-glow` seam is iOS-only unless explicitly extended in a follow-up (design.md §Open Risks).
- **`UserNotificationCentering` is a `class`-constrained protocol** because `UNUserNotificationCenter` is a class and the fake needs mutation tracking; it's `@unchecked Sendable` because `UNUserNotificationCenter` is `@MainActor`-isolated.