# Structure Outline — macOS first-class UX affordances (VAR-760)

## Approach

Make the existing multiplatform app target feel native on macOS from the menu bar outward: a `CommandMenu` (Complete/Skip/appearance), `MenuBarExtra` (live next-reminder `.menu` dropdown, hidden when nothing is due), app-menu About/Quit polish, and macOS local notifications via a platform-agnostic `NotificationScheduler` extracted from the iOS-only blob in `AppViewModel`. Model stays platform-agnostic; UI diverges inline `#if os(...)`.

The only genuinely new *logic* in this ticket is the notification scheduler and its schedule/cancel decision — everything else wires already-tested `ReminderStore` methods from new macOS chrome. So the testable foundation goes first (bottom), then AppViewModel plumbing, then app commands, then the topmost presentational strip. macOS is unit-test + `make mac-run` only (no macOS UI tests, by decision).

---

## Stage 1: `NotificationScheduler` foundation (SingleThreadCore) — bottom layer

Extract the ~100-line iOS-only notification blob into a platform-agnostic, `@MainActor` scheduler in Core, behind a protocol seam over `UNUserNotificationCenter` (unmockable as a concrete class). Green tests prove schedule/cancel/permission/decision behavior with zero device or signing dependency.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/NotificationScheduler.swift` (new), `SingleThreadTests/NotificationSchedulerTests.swift` (new)

**Key changes**:
- `protocol UserNotificationCentering` — `requestAuthorization(options:) async throws -> Bool`, `authorizationStatus() async -> UNAuthorizationStatus`, `add(_:) async throws`, `removeAllPendingNotificationRequests()`, `pendingNotificationRequests() async -> [UNNotificationRequest]`; `extension UNUserNotificationCenter: UserNotificationCentering` adapting its existing async APIs.
- `@MainActor final class NotificationScheduler` with `init(center: any UserNotificationCentering = UNUserNotificationCenter.current())`.
- `static let idleReminderIdentifier = "app.alanvardy.SingleThread.idle-reminder"` (moved from `AppViewModel`).
- `static func decideAction(visibleCount:hasHidden:enabled:intervalHours:) -> Action` — pure decision, `enum Action { case schedule(effectiveIntervalHours: Int); case cancel }` (mirrors current cancel-first/guard semantics: `!enabled` or `!(count > 0 || hasHidden)` → `.cancel`; interval `≤ 0` → 48 fallback).
- `func scheduleNotificationIfNeeded(visibleCount:hasHidden:enabled:intervalHours:options:) async` — `.cancel` clears all; `.schedule` builds the `UNMutableNotificationContent` + `UNTimeIntervalNotificationTrigger` and `add`s one request under `idleReminderIdentifier`.
- `func cancelNotifications() async` — `removeAllPendingNotificationRequests()`.
- `func requestPermissionIfNeeded(options:) async -> PermissionOutcome` — `enum PermissionOutcome { alreadyDetermined; granted; denied }`; requests only when `.notDetermined`, throws mapped to `.denied`.

**Tests**: `NotificationSchedulerTests` — `decideAction` truth table (disabled→cancel; empty→cancel; interval fallback; hasHidden), plus fake-center assertions: schedule adds exactly one request with `idleReminderIdentifier`; cancel clears; permission `.notDetermined` requests with the injected `options`, denial→`.denied`, already-granted→`.alreadyDetermined`. Sad paths: `add` throws → no crash, nothing scheduled.

**Verify**: `make test` (or targeted `-only-testing:SingleThreadTests`); `make mac-test` confirms the new Core file compiles on macOS too.

---

## Stage 2: AppViewModel rewiring + macOS scheduling triggers — service/plumbing layer

`AppViewModel` becomes a thin client of the scheduler: iOS path re-wired with **no behavior change**; macOS gains schedule-on-launch + schedule-on-reminders-changed, cancel when nothing is due.

**Files**: `SingleThread/AppViewModel.swift` (only)

**Key changes**:
- `private let scheduler = NotificationScheduler()`; platform options resolved once — `#if os(macOS)` → `[.alert, .sound]`, `#else` → `[.alert, .badge]`.
- Replace the bodies of iOS `scheduleNotificationIfNeeded` / `cancelNotifications` / `requestNotificationPermissionIfNeeded` with `scheduler.…` calls (reading `NotificationKeys` / `store.visibleReminders.count` / `store.hasHidden` as parameters); `requestPermissionIfNeeded` maps `.denied` → `UserDefaults.standard.set(false, forKey: NotificationKeys.enabled)` (preserves today's key-flip).
- `idleReminderIdentifier` references updated to `NotificationScheduler.idleReminderIdentifier`.
- macOS trigger: extend the shared `#if os(iOS) || os(macOS)` `store.onRemindersChanged` wiring so macOS also calls `scheduler.scheduleNotificationIfNeeded(...)` (cancel-first via `decideAction`); add one schedule call at launch (via `MacAppDelegate.applicationDidFinishLaunching`).
- Keep `pendingSummary` / `lastScheduleSummary` / `summary(requests:)` / `refreshPendingSummary()` as the iOS-only `--ui-testing-notifications` seam (they stay in AppViewModel; they read the scheduler's center).

**Tests**: no new AppViewModel suite exists and this stage is thin glue — the decision logic is already covered in Stage 1. Regression = the iOS notification **UI** tests still pass unchanged (`NotificationSchedulingUITests`, `NotificationsUITests`, `NotificationsSettingsUITests`); macOS compiles + unit run green.

**Verify**: `make mac-test`; `./scripts/test.sh` (iOS notification UI tests are the regression guard); manual `make mac-run` — first schedule shows the macOS permission prompt and, with the sandbox/hardened-runtime caveat (design Open Risk), a signed build delivers the notification.

---

## Stage 3: App commands — `CommandMenu` + app-menu polish (About / Quit / appearance)

MacOS app menu gets Complete/Skip for the current reminder plus a System/Light/Dark `Picker`, and proper About/Quit entries — all calling the store directly (exposure already exists: `appViewModel.store` is `internal`; stage-2 note below is a confirm, not a wiring change).

**Files**: `SingleThread/SingleThreadApp.swift` (add `.commands`), `SingleThread/SingleThreadApp+Commands.swift` (new, small, `#if os(macOS)`)

**Key changes**:
- A macOS-gated command builder, e.g. `func appCommands(store: ReminderStore, appearanceMode: Binding<AppearanceMode>) -> some Commands`, composed of `CommandGroup(replacing: .appInfo)` (About — reuses the var-651 About modal), `CommandGroup(replacing: .appTermination)` (Quit), and `CommandMenu("Reminder")` (Complete → `store.completeCurrentReminder()`; Skip → `store.skipCurrentReminder()`, both operating on `store.visibleReminders.first`).
- Appearance `Picker` bound to the existing `@AppStorage("appearanceMode")` key — the existing `ContentView` `.onChange → handleAppearanceMode` path applies it; no new write logic.
- ⌘ shortcut rule: leave Complete/Skip in the `CommandMenu` **without** keyboard shortcuts so they don't shadow the card-scoped `"c"`/`"s"` (design Open Risk).
- Confirm `viewModel.store` is reachable in the `App` body (already `internal` — no change expected).

**Tests**: no headless `String(describing:)` channel exists for `Commands`; the new logic is `ReminderStore` calls already covered by `ReminderStoreTests`/`ReminderStoreGateTests`. Regression = `AppearanceModeTests` (mapping unchanged) + macOS unit run.

**Verify**: `make mac-build`; `make mac-test`; manual `make mac-run` (menu items activate, About opens, Quit exits, appearance Picker switches and applies).

---

## Stage 4: `MenuBarExtra` — live next-reminder dropdown, hidden when nothing is due

The headline macOS affordance: a `.menu`-style menu-bar item showing the next due reminder with Complete/Skip/"Open SingleThread" items; entirely hidden when `visibleReminders` is empty.

**Files**: `SingleThread/SingleThreadApp.swift` (add `MenuBarExtra` scene, macOS-gated), `SingleThread/MenuBarExtraOptions.swift` (new, small, `#if os(macOS)` — content factored as a `View` so it's headless-testable)

**Key changes**:
- `MenuBarExtra("SingleThread", systemImage: "checkmark.circle") { MenuBarExtraOptions(store:) }` with `.menuBarExtraStyle(.menu)` in the `App` scene, gated `#if os(macOS)`.
- `MenuBarExtraOptions` renders `store.visibleReminders.first` title + due info; Complete/Skip buttons call `store.completeCurrentReminder()` / `skipCurrentReminder()`; "Open SingleThread" item calls `NSApp.activate` + focus/open the main window.
- Hide-when-empty: the "hidden entirely when nothing is due" requirement needs conditional scene inclusion (`SceneBuilder` `if`, macOS 14+ — confirmed fine at `MACOSX_DEPLOYMENT_TARGET = 26.5`) rather than an empty-menu item. Flag for Plan to confirm mechanism; empty-content across the board is the fallback.
- Lifetime: the extra builds from the same `viewModel.store` singleton the window uses, so it never goes stale (design Open Risk).

**Tests**: `SingleThreadTests/MenuBarExtraOptionsTests.swift` — headless-view convention (`String(describing: view.body)`): with a seeded first reminder, output contains the reminder title + "Complete"/"Skip"/"Open SingleThread"; with empty `visibleReminders`, the options view renders nothing (menu hidden). No macOS UI test (by decision).

**Verify**: `make mac-build`; `make mac-test`; manual `make mac-run` (item appears only when something is due; Complete/Skip mutate the reminder; Open reopens the window).

---

## Testing Checkpoints (resume-if-context-resets)

1. Stage 1 green → `NotificationSchedulerTests` passes on Linux-free unit run **and** `make mac-test`.
2. Stage 2 green → iOS notification UI tests unchanged + `make mac-test` + `make mac-build`.
3. Stage 3 green → `AppearanceModeTests` unchanged + `make mac-build` + `make mac-test`.
4. Stage 4 green → `MenuBarExtraOptionsTests` passes + `make mac-build` + `make mac-test`.
5. Final → full `./scripts/test.sh` once (parent/dedicated phase), incl. the macOS `-only-testing:SingleThreadTests` step.

## Open questions to confirm during `/5_plan` (small design amendments, not re-designs)

1. **macOS has no notifications-enable surface** (`NotificationsSettingsView` compiles out; macOS settings expose 3 bindings). With `notificationsEnabled` defaulting to `false`, macOS scheduling would never fire. Likely intent: macOS schedules whenever anything is due and treats the `enabled` toggle as an iOS-only concept — confirm before Stage 2.
2. **Permission-request timing on macOS**: no toggle to trigger `requestPermissionIfNeeded`; request lazily once (`.notDetermined`) at first launch/data-change vs. an explicit surface.
3. **Foreground presentation**: no `UNUserNotificationCenterDelegate` today; macOS may need `.banner`/`.list` `willPresent` handling to show a notification while the app is active (design Open Risk) — decide whether Stage 2 or a later shim owns the delegate.
4. **MenuBarExtra "hidden entirely"** mechanism (SceneBuilder `if` vs. empty content) — resolve the exact conditional-scene shape in Plan.