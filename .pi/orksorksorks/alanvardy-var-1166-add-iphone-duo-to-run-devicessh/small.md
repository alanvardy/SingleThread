# Task

Make `scripts/run-devices.sh` build, install, and launch SingleThread on the
new "iPhone Duo" device, in addition to the iPhone 16 Pro that already
receives builds. The user now has this second iPhone and wants it to get a
build on every `./scripts/run-devices.sh` run.

Why: the new phone must receive dev builds the same way the existing iPhone 16
Pro does, so the user can test on both devices from one command.

## Why SMALL

Single dev script (`scripts/run-devices.sh`), ≤5 files, follows the existing
device-discovery pattern; no schema/migration, no new subsystem, no design or
sign-off decision, and no script test infrastructure (only
`scripts/tests/warning-check/` exists).

## Key files (from recon)

- `scripts/run-devices.sh` — the entire change surface.
  - The script **already discovers devices dynamically** each run (header
    comment, lines ~19-22), and there is **no hardcoded "iPhone 16 Pro" / device
    list anywhere in the repo** (a repo-wide search for `16 pro` / `iphone duo`
    / `duo` found nothing outside this ticket).
  - The iOS device filter lives in the embedded Python at lines ~82-113:
    requires `hardwareProperties.platform == "iOS"` and
    `hardwareProperties.deviceType in ("iPhone", "iPad")`, then Developer Mode
    enabled, then a reachable connection (`transportType` non-null,
    `tunnelState` not `unavailable`, connection state not `unavailable`).
  - Likely causes the Duo is skipped, to confirm during recon: it reports a
    `deviceType` outside `("iPhone", "iPad")`, Developer Mode is off, or the
    CoreDevice tunnel is `unavailable` (locked / off-network) so it lands in the
    unreachable log and counts as a failed step.
- `DEVICES_JSON_IN` env seam (lines ~16, 56-66) lets you feed a saved
  `xcrun devicectl list devices -j` inventory for offline filter checks.
- Verify with `xcrun devicectl list devices` to see how the Duo is reported
  (`deviceType`, `developerModeStatus`, connection/tunnel state), then adjust
  the filter (or device handling) so the Duo qualifies — without regressing the
  existing iPhone 16 Pro / iPad behavior.
