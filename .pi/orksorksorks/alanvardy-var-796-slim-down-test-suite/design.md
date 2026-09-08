# Design Discussion

## Current State

The test suite has 577 tests (470 iOS unit, 38 watch unit, 52 iOS UI, 17 watch UI) across 80 files. Total run time is unknown empirically — no var-796 timing data exists — but structural costs are well-enumerated (`research.md` Q1-Q2):

**Structural cost drivers:**
- **73 app launches** (56 iOS + 17 watch; `research.md` Q2). iOS: 33 from `SingleThreadUITestsFlows.swift` alone, including 3 relaunch-persistence tests with multiple `terminate()` calls (`Flows:301,425,529`).
- **15s of unconditional `Task.sleep`** in notification UI tests: 3s × 4 tests (`NotificationSchedulingUITests.swift:33-40`) + 2s+1s (`NotificationsUITests.swift:58,60`), plus `usleep` after toggle flips.
- **200ms EventKit settle per mutation** — `RemonderStore.swift:38-40` default, called at complete/undo/delete/add/reschedule/skip (`:249,:280,:307,:340,:370,:396`). Production `AppViewModel.makeStore` never injects a substitute (`AppViewModel.swift:257-285`), so every mutation tap in every UI test pays this. Unit tests sidestep it via `noopSettle` (`RemonderStoreTests.swift:12`).
- **Compound UX durations**: 0.5s glow (`CompletionGlow.swift:35-42`), 1s minimum display (`ContentViewModel.swift:186-187`).
- **519s of `waitForExistence` budgets** across UI test files (upper bounds, return on appearance).
- **All 20 iOS + 4 watch suites are serialized** (`research.md` Q6) — mostly on file-scope `EKEventStore` fixtures. Given CI already runs with `-parallel-testing-enabled NO` (`ci.yml:68-77,136-146`), this is not a local wall-clock lever.

**Coverage duplication**: 40 of 69 UI tests duplicate behaviors already proven at the unit layer — complete, delete, undo, skip, show-list/glow persistence, freemium gate, priority marker, settings navigation, background/pin, deep link, reschedule, action-menu gate, nudge threshold (`research.md` Q3). The remaining 29 are integration-only: notification scheduling/cancel (6 tests, zero unit coverage), relaunch persistence (3), rendered copy, purchase sheet restore, a11y audits, watch dialog wiring, live WCSession receive, interval-picker options, iPad frame geometry.

**The notification gap**: `UNUserNotificationCenter` is the only remaining heavily-tested system service without a protocol seam (`research.md` Q4). Scheduling logic lives in `AppViewModel.swift:80-138` against the real center. Tests use `--ui-testing-notifications` seam labels (`AppViewModel.swift:414`, `ContentView+iOS.swift:16-33`) and `XCUIApplication` SpringBoard Allow probes (`NotificationsUITests.swift:32-35`, `NotificationSchedulingUITests.swift:21-25`). The `EventKitStoring` protocol (`EventKitStoring.swift:8`) is the proven pattern for this exact problem.

## Desired End State

A faster test suite where slow-integration tests are replaced by fast unit tests wherever possible. Specifically:

1. **Notification scheduling logic is unit-tested** — new protocol seam `UserNotificationCentering` wraps `UNUserNotificationCenter`, follows the `EventKitStoring` pattern (protocol → real conformance → fakes). 4 `NotificationSchedulingUITests` + 2 `NotificationsUITests` collapse to 0–1 E2E smoke test. The 15s of guaranteed `Task.sleep` and SpringBoard dialog handling disappear from the critical path.

2. **~20 redundant UI tests are removed** — the 40 duplicated tests (`research.md` Q3 classification) are audited; ~20 are cut where the unit coverage is thorough and the UI test adds only gesture/render residue. High-value integration-only tests (relaunch persistence trio, watch live-exclusion, a11y audits, rendered copy, iPad frame geometry) are kept.

3. **Timing injection seam extends to UI tests** — `--ui-testing-noop-settle` and `--ui-testing-reduced-glow` launch args let UI tests bypass the 200ms EventKit settle (`RemonderStore.swift:38-40`), 0.5s glow, and 1s minimum-display durations. Following the existing `--ui-testing-glow` pattern (`AppViewModel.swift:216-221`). Compounding savings across every mutation-bearing UI test.

4. **Suite serialization is accepted as inherent** — no refactoring of `@Suite(.serialized)` annotations or `test.sh` phase ordering. The `EKEventStore` one-per-host constraint and CI's disabled parallelism make this a non-lever.

**Verification**: run the full CI-local gate (`./scripts/test.sh`, `test.sh:196-296`) and confirm all remaining tests pass. Run `make coverage` and diff the unit-only coverage report to confirm no regressions in the behaviors moved from UI to unit.

## Patterns to Follow

### Good patterns — follow these

- **Protocol seam for system services**: `EventKitStoring` (`EventKitStoring.swift:8`) — declare protocol wrapping the system API, add real conformance on the system type (`:45`), create fake(s) for testing (`InMemoryEventStore.swift:13`, `FakeEventStore` at `EventKitStoringTests.swift:9`). The `SpeechTranscribing` (`ReminderDictation.swift:10`) and `BackgroundImageFetching` (`BackgroundImageStore.swift:14`) seams follow the identical pattern. Apply to `UNUserNotificationCenter`.

- **Launch-argument timing seams**: `--ui-testing-glow` (`AppViewModel.swift:216-221`) overrides `CompletionGlow.duration` in the test host. Extend this to settle (`RemonderStoreSettle` typealias, `RemonderStore.swift:12`) and minimum display (`MinimumDisplayDuration.remainingSleep`, `MinimumDisplayDuration.swift:6-10`).

- **Seeded, resettable UI tests**: `launchSeeded()` with `--seed` (`SingleThreadUITestCase.swift:22-35`) gives every test a clean deterministic starting state via `resetPersistedState()` (`AppViewModel.swift:303`). Keep this as the standard UI test launch pattern.

- **Unit tests use `noopSettle`**: `RemonderStoreTests.swift:12`, `RemonderStoreGateTests.swift:8` — every unit suite that constructs a `ReminderStore` uses `noopSettle` to skip the 200ms EventKit delay. The new timing seam for UI tests follows the same principle under a different name.

- **Fake-augmented `InMemoryEventStore` pattern**: `InMemoryEventStore` reports `.fullAccess` (`:37-42`) and returns `true` from `requestFullAccessToReminders` (`:45-47`), so `start()` short-circuits to `reload()`. The Reminders TCC dialog cannot appear under any test seam.

- **`make format` → `make lint` → build → test**: the commit gate (`conventions.md` §1). SwiftFormat excludes UI tests (`--exclude SingleThreadUITests`). Unit test names must not start with `test`/`testing`.

### Anti-patterns — do not repeat

- **Real `UNUserNotificationCenter` in tests is not a test seam**: `AppViewModel.swift:80-138` — direct `UNUserNotificationCenter.current()` calls forced tests into SpringBoard dialog probes (`NotificationsUITests.swift:32-35`) and `Task.sleep` waits. This is exactly the pattern `EventKitStoring` solved for EventKit — apply the same fix.

- **Production timing in test hosts**: `AppViewModel.makeStore` never injects `settle:` (`AppViewModel.swift:257-285`), so UI tests pay 200ms per mutation when unit tests pay 0ms. Same for glow (`CompletionGlow.swift:35-42`) and minimum display — production constants flowing into tests with no override path.

- **`test.sh` is not parallelizable without invasive restructuring**: `set -euo pipefail`, sequential phases (`test.sh:196-296`), one XCUIApplication per simulator. Reordering phases or overlapping runs is not a design target here.

- **UserDefaults divergence**: `AppGroup.defaults` vs `.standard` on iOS simulator (`AppGroup.swift:16-18`) — all persisted values must round-trip through `AppGroup.defaults`. The research confirms existing seams do this correctly; the notification seam introduces no new defaults keys.

## Design Decisions

1. **No profiling phase**: Act on the research's structural cost analysis — 15s guaranteed sleeps, 200ms settle per mutation, 73 launches, 40 duplicated UI tests, the notification no-seam gap, un-skippable UX durations. Profile after changes land to verify improvement.

2. **Cut ~20 clearly redundant UI tests**: Keep integration-only tests (relaunch persistence, watch live-exclusion, a11y audits, rendered copy, iPad geometry, purchase restore, interval picker). Cut the pure-duplication ones where the unit layer already proves the behavior thoroughly: complete, delete, undo, skip, show-list/glow toggles, freemium gate excluding the restore-button test, priority marker, background/pin selection, deep link, settings navigation, reschedule, nudge-banner dismissal.

3. **Add `UserNotificationCentering` protocol seam**: New protocol in `SengleThreadCore` wrapping `UNUserNotificationCenter` — `requestAuthorization`, `notificationSettings`, `add(UNNotificationRequest)`, `removePendingNotificationRequests`, `removeDeliveredNotifications`. Real conformance wrapping `UNUserNotificationCenter.current()`. Fake for unit tests records sent/received. The 4 `NotificationSchedulingUITests` + 2 `NotificationsUITests` (total 6 tests, ~15s sleeps + SpringBoard) are replaced by unit tests against the fake, optionally keeping 1 E2E smoke test.

4. **Add `--ui-testing-noop-settle` and `--ui-testing-reduced-glow` launch args**: `--ui-testing-noop-settle` sets `settle: noopSettle` in the test host's `ReminderStore` construction. `--ui-testing-reduced-glow` reuses the existing `--ui-testing-glow` seam path (`AppViewModel.swift:216-221`) but with a shorter duration (e.g., 0.1s instead of 2.0s). Applied uniformly — no per-test opt-out since these are UX costs, not behaviors under test.

5. **Accept suite serialization**: No refactoring of `@Suite(.serialized)`, no reordering `test.sh` phases, no per-test `EKEventStore` fixture rewrite. CI already serializes (`ci.yml:68-77`), and local iOS unit is already parallel (the exception). Time spent on serialization reduction yields zero wall-clock improvement.

## What We're NOT Doing

- **Not reordering `test.sh` phases or adding parallel stages** — `set -euo pipefail` sequential is the right safety posture.
- **Not adding per-test timing instrumentation** — no `measure(` blocks, `XCTMetric`, `ContinuousClock`, or `-showBuildTimingSummary` in `test.sh`. Re-profile with `make coverage-all` after changes if needed.
- **Not touching the widget** — no widget test target exists, `NextThingWidget.swift` uses static EventKit, and the widget is out of scope.
- **Not adding a StoreKit purchase test** — `SKTestSession.buyProduct` is broken on Xcode 26.6 (`EntitlementStoreTests.swift:48-54`, FB22237318), and purchase-path coverage uses `init(testingWithEntitled:)` / `init(testingWithEntitlementUnresolved:)` (`EntitlementStore.swift:52-63`).
- **Not adding watch notification UI tests** — the watch has no `--ui-testing-notifications` seam overlay (`research.md` Q4), and adding one is out of scope.
- **Not modifying CI configuration** — CI has its own parallelization policy (:enabled) and retry logic (`ci.yml:144,203,264,425`) for different reasons. This design targets local speed.
- **Not adding new test targets or test runner infrastructure** — no new Xcode targets (pbxproj object-ID work), no new test schemes, no new test host configuration.

## Open Risks

- **Notification seam scope creep**: The `UNUserNotificationCenter` API surface is large. The protocol must wrap only the methods the app actually uses (`AppViewModel.swift:80-138`): `requestAuthorization(options:)`, `notificationSettings()`, `add(_:)`, `removePendingNotificationRequests(withIdentifiers:)`, and `removeDeliveredNotifications(withIdentifiers:)`. Resist the temptation to wrap the full API.

- **UI test removal verification**: Cutting ~20 tests means verifying each one's unit coverage is genuinely equivalent. Some "duplicated" tests may exercise edge cases the research missed — each removal needs a quick spot-check of the unit test's assertion set vs the UI test's flow. The plan phase should enumerate the exact file-and-line of every test to cut.

- **SpringBoard Allow test surviving the notification seam**: If we keep 1 notification E2E smoke test, it still needs the SpringBoard Allow dialog probe (`NotificationsUITests.swift:32-35`). This is currently handled but fragile — the dialog may or may not appear depending on prior TCC state.

- **Glow timing in watch tests**: `WatchReminderViewModel.completionTransitionBuffer` (0.5s, `WatchReminderViewModel.swift:79-81`) is separate from iOS `CompletionGlow.duration`. The `--ui-testing-reduced-glow` seam applies only to iOS unless explicitly extended to the watch `--ui-testing-glow` path (`WatchAppViewModel.swift:46-55`).

- **Settle removal in persistence tests**: The relaunch-persistence trio tests that state survives across process boundaries. Removing the 200ms settle could expose timing-dependent order-of-operations bugs in the EventKit layer that the settle masks. Keep the settle in these 3 tests unless proven safe.