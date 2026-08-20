# Design Discussion

Branch: `alanvardy-var-629-local-ios-simulator-singlethread-app-never-activates-via`
Debug task: unblock the manual on-simulator verification path (cold-launch
appearance, runtime toggling, device-appearance following) so it can verify an
app that never reaches foreground via headless `simctl launch`.

## Current State

- App entry `@main SingleThreadApp: App`, `init()` reads launch args,
  builds `ReminderStore`, loads sort, (iOS) activates `WCSession` —
  `SingleThreadApp.swift:15-56`. iOS delegate registered via
  `@UIApplicationDelegateAdaptor(AppDelegate.self)` — `SingleThreadApp.swift:73-74`.
- **The iOS delegate observes only one lifecycle transition**: `applicationDidBecomeActive`
  → `applyAppearance` — `AppDelegate.swift:45-47`. No iOS
  `applicationWillEnterForeground` / `DidFinishLaunchingWithOptions` / scene-delegate
  hooks exist (grep-verified). macOS has `applicationDidFinishLaunching` +
  `applicationDidBecomeActive` — `AppDelegate.swift:77-89`. The active/foreground
  handoff is **serial-driven, not app-driven** (research Q1, Q5 cross-cutting).
- The only foreground-driven *work* is view-driven: `ContentView.body` `.task`
  calls `store.start()` on view appearance — `ContentView.swift:64-67`.
- Foreground requires SpringBoard (`FBSystemService`) to activate the app's UI
  scene. Scene-based lifecycle comes from generated build settings
  (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphonesimulator*] = YES`,
  `project.pbxproj:607-608`), not a checked-in manifest.
- **Headless `simctl launch` has no foreground flag** (research Q3). CI never uses
  `simctl launch`; it relies on `xcrun simctl bootstatus <udid> -b` to gate boot
  (`ci.yml:41-43, 102-104`). The only repo spin that *works* is XCTest, whose
  `XCUIApplication.launch()` foregrounds via `testmanagerd` → SpringBoard
  (research Q4; `SingleThreadUITests.swift:18-20, SingleThreadUITestsLaunchTests.swift:22-25`).
- **EventKit prompt intercepts launch on fresh install**: `ContentView.swift:64-67`
  → `ReminderStore.start()` — `SingleThreadCore/.../ReminderStore.swift:105-118`;
  `authorizationStatus == .notDetermined` → `requestAccess()` → awaited
  `requestFullAccessToReminders()` — `ReminderStore.swift:261-271, 263`. The
  SpringBoard-owned TCC prompt can be the visible "never active" state. The iOS
  app target declares only the **legacy** `INFOPLIST_KEY_NSRemindersUsageDescription`
  (`project.pbxproj:605/655`), not the full-access key the code path requires.
- `--ui-testing` is the only real-app source of `loadsReminders=false`
  (`SingleThreadApp.swift:16`; set by UI tests at
  `SingleThreadUITests/SingleThreadUITests.swift:18`); it suppresses the prompt.
- No repo automation invokes `simctl launch`; the manual path is currently just
  notes — nothing lives in `scripts/` or `Makefile` (research Q3; verified `Makefile`,
  `scripts/test.sh` contain zero simctl calls).

## Desired End State

A manual, repeatable on-simulator path that reliably foregrounds the app so a
reviewer can verify three scenarios:

1. **Cold-launch appearance** — app launches into foreground; persisted
   `appearanceMode` (from `UserDefaults` key, `AppearanceMode.swift:66-72`)
   applied to windows (`overrideUserInterfaceStyle = mode.windowOverrideStyle`,
   `AppDelegate.swift:15-22`).
2. **Runtime toggling** — changing `view` → `SettingsView.appearanceMode`
   re-applies appearance (`ContentView.swift:75-79` → `AppDelegate.applyAppearance`).
3. **Device-appearance following** — the `.system` sentinel clears the override so
   the window re-follows the device (`CoverageMode.windowOverrideStyle`, `AppearanceMode.swift:24-29`).

**Success criteria**:
- `applicationDidBecomeActive` fires (activation evidence via log hook).
- Screen shows the app scene, not SpringBoard (`xcrun simctl io screenshot`).
- Deterministic appearance assertions pass when driven through the XCTest path
  (reusing the proven `XCUIApplication.launch()` foreground handoff).

## Patterns to Follow

- **Mirror `--ui-testing`'s launch-flag gate** for a manual `--no-reminders` flag:
  `loads = !ProcessInfo.processInfo.arguments.contains(...)` —
  `SingleThreadApp.swift:16`. Same inverted-boolean shape, different flag name,
  scoped to the manual path. `ContentView` already branches on `store.loadsReminders`
  (`ContentView.swift:40-44`), so no view change is needed.
- **Reuse the XCTest launch path for deterministic foregrounding** — the only path
  proven to drive the app to active is `XCUIApplication.launch()` via `testmanagerd`
  → SpringBoard (research Q4). Model a verification bundle on
  `SingleThreadUITests.swift` (launch args, wait-for-static-text, audit/style asserts).
- **Appearance assertion seam**: read `UIWindow.overrideUserInterfaceStyle` from a
  `UIWindowScene` (`applyAppearance` already iterates `connectedScenes` →
  `UIWindowScene` — `AppDelegate.swift:15-22`); assert the expected `UIUserInterfaceStyle`.

### Patterns NOT to follow
- **Do NOT make the app self-foreground.** The research is explicit that the app
  reacts to SpringBoard activation and should not request its own foreground.
  That is a non-pattern that would fight the platform lifecycle.
- **Do NOT invent a `simctl launch` foreground/background flag.** None exists
  (research Q3); rely on the serial-driven handoff via XCTest instead.

## Design Decisions

1. **Root cause (process-side, not app-side)**: the app never foregrounds headless
   because SpringBoard's scene activation never completes behind the TCC prompt and
   no self-foreground exists. Fix the *launch path*, not the app lifecycle. Using
   the proven XCTest foreground handoff for the manual path makes activation
   deterministic. Rationale: research Q1/Q5 (activation is serial-driven).
2. **Suppress the Reminders prompt via a `--no-reminders` flag**: reuses the existing
   `loadsReminders=false` gate so the cold-launch foreground is not blocked by a TCC
   prompt on a fresh install. Rationale: minimal, scoped, mirrors the proven
   `--ui-testing` mechanism (`SingleThreadApp.swift:16`).
3. **Verify via XCTest, not headless screenshot only**: the three appearance
   scenarios are asserted through `XCUIApplication` (deterministic), with
   `xcrun simctl io screenshot` captured as supporting visual evidence. Rationale:
   headless `simctl launch` cannot be trusted to foreground (research Q3).
4. **Deliverable = report + thin script + thin XCTest**: `scripts/simverify.sh`
   pre-boots (`bootstatus -b`) + builds + drives the appearance assertions, all
   `make simverify`; findings land in `docs/SimulatorManualVerification.md` (repo,
   not the qrspi workspace). Rationale: task calls for "report-ish" and a runnable
   path; the script mirrors existing `scripts/test.sh` conventions.

## What We're NOT Doing

- **Not fixing the missing `NSRemindersFullAccessUsageDescription` Info.plist key**
  (`project.pbxproj:605/655`) here. It is a latent real-install bug, tracked as a
  separate follow-up; out of scope for unblocking the manual verification path.
- **Not adding `applicationWillEnterForeground`/scene-delegate methods** beyond the
  activation log line needed for observability. No lifecycle reordering.
- **Not writing a custom foreground CTA flag or touching `simctl` internals**.
- **Not altering automated CI/unit/UI/accessibility tests** — those already pass
  and are unaffected by the manual-verification path.
- **Not changing** entitlements, sandbox, or App Group config.

## Open Risks

- **XCTest foreground determinism** cannot be observed headless in this design pass;
  the appearance assertions are only as reliable as the proven XCTest path — need to
  reintroduce and confirm `applicationDidBecomeActive` fires (via log line) before
  trusting the `simverify` gate.
- **Screenshot timing**: if manual/interactive runtime-toggling is desired later, a
  fresh-headless screenshot may not reflect a toggled override, so the script should
  lean on XCTest asserts for scenario 2/3, not screenshots.
- **`--no-reminders` semantics drift**: must stay a debug/manual flag and not get
  conflated with `--ui-testing` (different audiences: manual reviewer vs accessibility
  test). If they converge later, unify them, but keep the split for now.
- **Boot readiness**: skipping `bootstatus -b` in the thin script would reintroduce
  the boot gate failure CI guards in ci.yml:43/104 — the script must not skip it.