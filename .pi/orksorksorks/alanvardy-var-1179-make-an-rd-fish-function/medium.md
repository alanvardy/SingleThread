# Task

Add an `rd` fish function that builds, installs, and launches SingleThread **on
the physical iPhone Duo only** — skipping the regular iPhone/iPad simulator
legs, the Apple Watch leg, and the macOS leg. `r` is the current full-run
wrapper (`r.fish` → `./scripts/run-devices.sh`); `rd` is the narrow Duo-only
sibling.

Concretely:

1. **`rd` fish function.** Fish functions live in
   `~/dev/dotfiles/fish/functions/*.fish` (that directory is symlinked to
   `~/.config/fish/functions`), so add `rd.fish` there, following `r.fish`:
   `function rd --wraps=./scripts/run-devices.sh --description '…'` then invoke
   `./scripts/run-devices.sh` with whatever env selects the Duo-only mode below.
2. **A Duo-only mode on `scripts/run-devices.sh`.** Today there is no way to do
   this:
   * `IOS_TARGET=sim` (default) runs the sim iPhone/iPad legs **and** the
     physical Duo **and** the watch **and** macOS.
   * `IOS_TARGET=device` sweeps **every** paired physical iPhone/iPad and
     ignores `DUO_DEVICE_ID` (the embedded Python only honours it when
     `mode != "device"`, run-devices.sh ~line 239).
   * `RUN_WATCH=0` / `RUN_MAC=0` exist, but nothing skips the sim legs.
   Add the smallest flag that yields Duo-only (e.g. an `IOS_TARGET=duo` value,
   or make `DUO_DEVICE_ID` filter in `device` mode), document it in the header
   override block, and fix the summary so it reports the Duo leg honestly
   instead of printing a 0/0 sim line.
3. **Update `scripts/test-run-devices.sh`** (the existing `run_flow` / fixture
   harness): cover the new mode — a happy path that installs only the Duo and a
   sad path (no/unreachable Duo), without regressing the `sim` / `device`
   flows. Reuse `DEVICES_JSON_IN` and `scripts/fixtures/devicectl-devices.json`.

Why: the user wants a one-command "push this build to my phone" loop without
paying the sim + watch + macOS build/launch cost on every run.

## Why MEDIUM

M1 holds: approach known (wrap `run-devices.sh` exactly like `r.fish`, extend
the existing `IOS_TARGET` env pattern), 0–2 unknowns, no new technology — no
schema/migration, no new subsystem, no product trade-off. M2 holds: no
data-model/API/UI change; the only choices (flag shape, whether `rd` builds from
scratch or reuses `DerivedData`) are scoped and precedented by VAR-1175's
`IOS_TARGET` work. M3 holds: **MULTI_MODULE** (`scripts/run-devices.sh` +
`scripts/test-run-devices.sh` + the dotfiles `rd.fish`, i.e. two repositories)
and **BROAD_TEST_SURFACE** (the flow harness must gain a mode variant and a
sad-path case).

## Key files

* `scripts/run-devices.sh` (~540 lines) — the change surface: header override
  block (~lines 12–28), `IOS_TARGET`/`DUO_DEVICE_ID` env parsing (~72–76), the
  embedded Python discovery filter where `device` mode ignores `DUO_DEVICE_ID`
  (~211–263), the sim leg gated on `IOS_TARGET == "sim"` (~319–374), the Duo
  device loop (~390–434), the watch/macOS legs, and the summary (~510+).
* `scripts/test-run-devices.sh` (~310 lines) — `extract_filter()`, `run_flow()`,
  and the `IOS_TARGET=sim` / `IOS_TARGET=device` flow assertions to extend.
* `scripts/fixtures/devicectl-devices.json` — inventory fixture (contains the
  physical `Fixture iPhone Duo` plus sim entries).
* `~/dev/dotfiles/fish/functions/r.fish` — the wrapper pattern to copy.
* `~/dev/dotfiles/fish/functions/` — where `rd.fish` must be created (symlinked
  as `~/.config/fish/functions`).
* `.pi/orksorksorks/alanvardy-var-1175-run-the-regular-iphone-and-ipad-legs-in/`
  — the prior `IOS_TARGET` ticket's plan/medium artifacts: the naming and
  toggle conventions this change should mirror.
* `Makefile` / `scripts/test.sh` — check whether the new mode needs a
  `-only-testing` / gate entry (the flow tests live outside the Xcode gate).
