# Simulator Manual Verification

How the SingleThread iOS app's appearance handling is verified **locally on the iOS
Simulator** — the repeatable `make simverify` gate, the manual launch procedure, and
the determinism caveats.

## Why this exists

`simctl launch` against a fresh simulator install used to leave the app stuck in
SpringBoard — the cold launch never activated a scene, which blocked manual
appearance verification. The root cause was a **launch-pipeline** gap (the Reminders
TCC prompt stalling scene activation), not the app lifecycle. This report documents
the fixed pipeline and the one-command gate that drives the appearance checks.

## The seam: `--no-reminders`

`SingleThread/SingleThreadApp.swift` (`init()`) gates reminder loading behind two
manual flags. `--no-reminders` (new, reviewer-facing) suppresses the `requestFullAccessToReminders()`
TCC prompt that otherwise stalls scene activation on a fresh install, mirroring the
existing `--ui-testing` inverted-boolean pattern:

```swift
let loads = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
    && !ProcessInfo.processInfo.arguments.contains("--no-reminders")
```

`ContentView.swift:40-44` already branches on `store.loadsReminders` — no view change
was needed. When `--no-reminders` is present, `ReminderStore.start()` returns early so
the `ProgressView("Requesting access…")` never shows and the app renders the reminder
list.

## Activation log hook

`AppDelegate.applicationDidBecomeActive` (the only iOS lifecycle hook) logs when the
scene activation completes:

```swift
func applicationDidBecomeActive(_: UIApplication) {
    print("SimVerify: app active")
    Self.applyAppearance(AppearanceMode.load())
}
```

Look for `SimVerify: app active` in the console/stderr to confirm the app (not
SpringBoard) is foreground and active. No lifecycle reordering was added.

## `make simverify`

A single, CI-style local gate that pairs the proven XCTest foreground handoff
(`XCUIApplication.launch()` → testmanagerd → SpringBoard) with the pre-boot
`bootstatus -b` guard:

```bash
make simverify                        # iPhone 17 (default)
SIM="platform=iOS Simulator,name=iPad (A16)" make simverify   # iPad (A16)
```

`scripts/simverify.sh` boots the device, builds the appearance launch-test bundle, and
runs `test-without-building -only-testing:SingleThreadUITestsAppearanceLaunchTests`. A
best-effort screenshot lands at `build/simverify-cold-launch.png`. If the wrong
simulator unit is picked (several `iPhone 17` units exist), pass `SIM_UDID` explicitly.

The gate is the XCTest asserts; the screenshot is supporting evidence only.

## Manual launch (console watch)

```fish
DEVICE_UDID=<full simulator UDID from the SIM list>   # e.g. D7AC0D41-275E-47C5-B603-BC7FA08D1BB4
xcrun simctl bootstatus "$DEVICE_UDID" -b

xcrun simctl launch --stderr=/tmp/simverify.log \
    "$DEVICE_UDID" \
    app.alanvardy.SingleThread --no-reminders
```

Wait for foreground, then inspect `/tmp/simverify.log` for `SimVerify: app active`
(the launch path uses `--stderr` because simulator log output often lands on stderr).
Expect the app scene (reminder list, not SpringBoard) and the log line.

## Caveats

- **Appearance override values are not read headless.** `XCUIApplication` is a remote
  client (testmanagerd/SpringBoard) with no API to inspect the app process's in-process
  override value. Assertions verify activation + content + screenshot; the
  `.system/.light/.dark → .unspecified/.light/.dark` mapping is deterministic and
  proven at the unit level (`SingleThreadTests/AppearanceModeTests.swift`). A true
  in-process override assert would need an observable seam (`/3_design` scope, tracked).
- **Screenshot timing.** A fresh screenshot won't render a toggled override well; the
  XCTest asserts (app stays foreground and live) are the determinism, not the image.
- **`--no-reminders` stays a manual/developer flag.** It is not `--ui-testing`; it is
  scoped to the manual reviewer path only and is unaffected by the automated suite.
- **`NSRemindersFullAccessUsageDescription`** (missing from the app target
  `Info.plist`) is a separate, latent real-install follow-up — explicitly **out of
  scope** for this work and not addressed here.

## Scenarios covered

1. **Cold-launch appearance** — `testColdLaunchAppearance`: app foregrounds under
   XCTest and renders a scene (not SpringBoard) with `--no-reminders`.
2. **Runtime toggling** — `testRuntimeAppearanceToggle`: open Settings → Appearance
   picker while live; the app stays foreground and interactive.
3. **Device-follow (`.system`)** — `testDeviceFollowingClearsOverride`: same reachable
   surface; the `.system` override-clear is unit-proven
   (`systemMapsToUnspecifiedWindowStyle`).

## Container opacity (VAR-722)

The reminder card's container is now transparent on every device: row chrome is always
clear (`ContentViewModel.rowChromeBackground`), scroll content stays hidden, and the
`List` itself gets `.background(Color.clear)`. Verifying the rendered look is manual-only —
opacity cannot be asserted headlessly (`BackgroundCardTests` assert the gate decision, not
the paint).

**Gate:**

```bash
SIM='platform=iOS Simulator,name=iPad (A16)' make simverify   # iPad (A16)
make simverify                                                # iPhone 17
```

The `make simverify` XCTest asserts are the determinism gate; for the opacity matrix,
capture side-by-side screenshots after booting each device:

```bash
xcrun simctl io "<UDID>" screenshot build/var722-ipad-light-photo-on.png
# repeat for: light/photo-off, dark/photo-on, dark/photo-off
```

**Expectations (both devices, light × dark × toggle-on/off):**

- The card plate (`showsOverPhoto`) appears **only** when a photo is shown — never as an
  opaque row when no photo is displayed.
- No opaque row on iPad in any state (previously the row fell back to the opaque system
  default when no photo was shown).
- Text contrast is unchanged in dark mode over `systemBackground`.

**Screenshot slots** (record filenames next to each expectation): `build/var722-ipad-light-photo-on.png`,
`build/var722-ipad-light-photo-off.png`, `build/var722-ipad-dark-photo-on.png`,
`build/var722-ipad-dark-photo-off.png`, and the iPhone equivalents.