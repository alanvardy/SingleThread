# Structure Outline

## Approach

Unblock the manual on-simulator verification path by fixing the **launch pipeline**, not the app lifecycle: suppress the Reminders TCC prompt that stalls SpringBoard's scene activation, add an `applicationDidBecomeActive` log hook for activation evidence, gate all deterministic appearance asserts through the proven XCTest foreground handoff (`XCUIApplication.launch()` → testmanagerd → SpringBoard), and package it as a thin `make simverify` script + short report.

**Layer note (no DB/API here):** this is an iOS simulator app, not a web stack. The "layers" a vertical slice must cross are the **launch path** (`SingleThreadApp`), **lifecycle delegate** (`AppDelegate`), **EventKit store suppression** (`ReminderStore`), **verification** (Swift Testing unit + XCTest UI), and **repo automation** (script / Makefile / docs). Each phase below crosses every layer required for *that* function.

---

## Phase 1: Clean foreground launch (`--no-reminders`) + activation log

Unclamps the cold launch: without a TCC prompt the SpringBoard scene activation completes, and a log hook proves `applicationDidBecomeActive` actually fires. Everything later verifies depends on this.

**Files**: `SingleThread/SingleThreadApp.swift`, `SingleThread/AppDelegate.swift`

**Key changes**:
- `SingleThreadApp.swift:16` — extend the gate (inverted boolean, mirrors `--ui-testing`):
  ```swift
  let loads = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
      && !ProcessInfo.processInfo.arguments.contains("--no-reminders")
  ```
- `AppDelegate.swift:45-47` `applicationDidBecomeActive(_: UIApplication)` — one `print("SimVerify: app active (view-appearance)")` line before `applyAppearance`.

**Verify**: `make build`; manual
`xcrun simctl launch <udid> app.alanvardy.SingleThread` (fresh install) shows the app scene with **no Reminders TCC prompt**, and the console log contains the activation line. Existing `make test` stays green (gate is inverted — non-flag builds unchanged).

---

## Phase 2: Deterministic cold-launch appearance (seam + foreground)

Locks the three appearances to the launched window: `.system → .unspecified (follow device)`, `.light → .light`, `.dark → .dark`. Verified two ways — a pure mapping unit test and a XCUI foreground test.

**Files**: `SingleThread/AppearanceMode.swift` (read seam only), `SingleThreadUITests/SingleThreadUITestsAppearance.swift` (new), `SingleThreadUITests/.../SingleThreadUITestsAppearanceLaunchTests.swift` (new)

Notice: `AppearanceMode.windowOverrideStyle` / `AppDelegate.applyAppearance(_ mode, to windows: [UIWindow]? = nil)` already exist — Phase 2 **adds tests, not product code**. Persist `@AppStorage("appearanceMode")` via `ContentView.swift:141-142` before launch.

**Key changes**:
- New unit (`SingleThreadTests/AppearanceModeTests.swift`):
  ```swift
  @Test func appearanceMode_windowOverrideStyle_mapsSystemToUnspecified() { … }
  ```
- New UI test — `testColdLaunchAppearance()`:
  ```swift
  @MainActor
  func testColdLaunchAppearance() throws {
      let app = XCUIApplication()
      app.launchArguments = ["--no-reminders"]
      app.launch()
      // assert app reached active (static text present), assert window style via
      // a `UIWindowScene` override-inspection seam, attach screenshot.
  }
  ```

**Verify**: `make test` (new mapping unit test) and `make ui-test` (new launch test) pass; screenshot shows app content scene, not SpringBoard. This is the seam-design pass also *proves* `applicationDidBecomeActive` fires under XCTest (risk closure from design's "Open Risks").

---

## Phase 3: Runtime toggling + `.system` device-following (live asserts)

Confirms the delegate's `applyAppearance` seam re-applies on change: toggling the picker reapplies appearance; tapping `.system` clears the override so the window follows the device.

**Files**: `SingleThreadUITests/SingleThreadUITestsAppearance.swift` (add two tests), `SingleThread/ContentView.swift` (appearance picker already wired at `ContentView.swift:75-79`, `86`, `141-142` — no product change expected).

**Key changes**:
- New `testRuntimeAppearanceToggle()` — while running, change the appearance mode; assert `window.overrideUserInterfaceStyle` re-applies.
- New `testDeviceFollowingClearsOverride()` — set `.system`; assert override `.unspecified` (window re-follows device).
- If a toggled override isn't visible to XCUIApplication via screenshots (only the `.system`-cleared state is), assert via the `UIWindowScene` read seam and downgrade the toggle assert to a log-rendered-but-unspecified style; note in the report.

**Verify**: `make ui-test` passes all new cases. Manual `xcrun simctl io screenshot` captures a supporting before/after frame for the report.

---

## Phase 4: Repeatable gate script + reportable findings

Turns the verified flow into a one-command, CI-style, documented deliverable.

**Files**: `scripts/simverify.sh` (new), `Makefile`, `docs/SimulatorManualVerification.md` (new)

**Key changes**:
- `scripts/simverify.sh` — `SIM` honoring (default `iPhone 17`) + `WATCH`/`MAC` like `test.sh`; echoes the CI gate: `SIM_UDID=$(xcrun simctl list …)` → `simctl boot $SIM_UDID || true` → `simctl bootstatus $SIM_UDID -b` (**must keep**); then `xcodebuild … -only-testing:SingleThreadUITests*`; captures `xcrun simctl io screenshot`.
- `Makefile` — new `simverify:` target → `./scripts/simverify.sh` (mirrors `scripts/test.sh` conventions).
- `docs/SimulatorManualVerification.md` — three scenarios, the seam, the `simverify` incantation, and caveats (screenshot timing, `--no-reminders` stays manual, full-access `NSRemindersFullAccessUsageDescription` is a separate follow-up not included).

**Verify**: `make simverify` on `iPhone 17` (and `iPad (A16)` when needed) returns green; the doc's steps reproduce the manual screenshot.

---

## Testing Checkpoints

- **After Phase 1**: `make build` + existing tests green; manual launch shows no Reminders TCC prompt; console logs the `SimVerifier: app active` line.
- **After Phase 2**: unit + UI tests for cold-launch appearance pass; screenshot shows app content; the design-open risk (XCTest `applicationDidBecomeActive` fires) is retired.
- **After Phase 3**: toggle + `.system`-sentinel tests pass; device-following clears override deterministically.
- **After Phase 4**: `make simverify` is the single green gate; `docs/SimulatorManualVerification.md` is the reviewer-facing deliverable.
- **If stopped mid-plan**: Phase 1 alone already unblocks manual headless verification (clean launch + log hook); Phases 2-3 add deterministic asserts; Phase 4 is only the packaging.

---

## When to go back to /3_design

- If Phase 2 reveals XCTest cannot read `UIWindow.overrideUserInterfaceStyle` headless (the design flags this as an open risk), re-slide the seam rather than inventing a self-foreground.
- The design explicitly defers `NSRemindersFullAccessUsageDescription` (a latent real-install bug) — any attempt to "fix" it here should trigger a re-`/3_design`, not a silent scope change.
- Do **not** add a self-foreground CTA or a `simctl launch` foreground flag; those are explicitly forbidden non-patterns.

---

Next: run `/5_plan`