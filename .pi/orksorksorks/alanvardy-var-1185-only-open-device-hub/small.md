# Task

Running `r` (the fish alias for `./scripts/run-devices.sh`) should present the
booted simulators in Xcode 27's **Device Hub** so the launched app is visible —
without opening a separate Simulator/Device Hub window for each simulator leg.

Today `scripts/run-devices.sh`'s `show_sim_window()` is called once per
simulator leg (iPhone, iPad, and Apple Watch). It cold-launches Device Hub via
`open -b com.apple.dt.Devices` and then deep-links each device with
`open "devices://device/open?id=<udid>"` (falling back to
`open -a Simulator --args -CurrentDeviceUDID <udid>` on older Xcode), which is
what produces a separate window per device. Change the run so Device Hub is
opened once and shows the running app on the simulators, keeping the old
Simulator.app fallback for Xcode versions without Device Hub. A window/show
failure must stay a reported note, not a failed step (current behaviour).

Scope is this dev script and its test harness only — no app, package, watch,
schema, or CI changes.

## Why SMALL
Localized change to one existing script (`scripts/run-devices.sh`) plus its
test file (`scripts/test-run-devices.sh`); the approach is a small edit to an
existing function that already implements the Device Hub path, with no schema,
new subsystem, shared/convention risk, or design decision. A–F all hold.

## Key files
- `scripts/run-devices.sh` — `show_sim_window()` (defined ~line 150);
  called in the iPhone/iPad simulator leg (~line 330) and the Apple Watch
  simulator leg (~line 490).
- `scripts/test-run-devices.sh` — stub `open`; the open-log assertions around
  lines 232–240 (`the simulator window uses the Device Hub deep link`,
  "the iPhone/iPad simulator window is pinned by UDID"); the watch-leg
  open-log assertions near line 290.
- `~/dev/dotfiles/fish/functions/r.fish` — `r` wraps `./scripts/run-devices.sh`
  (no change expected here).
