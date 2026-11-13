# Task

Change `scripts/run-devices.sh` so the **regular iPhone and iPad legs run in the
simulator** instead of on physical hardware, while the **physical iPhone Duo**
and the **macOS leg stay exactly as they are**.

Concretely:

1. **Split the iOS discovery filter.** Today one inline-Python filter over
   `xcrun devicectl list devices -j` selects every physical `platform == iOS`,
   `deviceType in (iPhone, iPad)` entry, and one build/install/launch loop runs
   per entry — which sweeps in the physical `iPhone Duo`
   (`scripts/fixtures/devicectl-devices.json`: `Fixture iPhone Duo | iOS iPhone
   physical`). Split it so:
   * physical **Duo** keeps the existing `devicectl` build / `install` /
     `launch` path (targeting `Debug-iphoneos/SingleThread.app`);
   * regular physical iPhone/iPad entries are dropped from the device loop.
2. **Add a simulator leg** for a regular iPhone and a regular iPad:
   * Defaults `iPhone 17` and `iPad (A16)`, overridable via `SIM_IPHONE=` /
     `SIM_IPAD=`, resolved to UDIDs with the **same precedence as
     `scripts/test.sh:28-72`** (this worktree's `.simulator_id` → shared
     default, pinned by UDID; never a bare ambiguous `name=`).
   * Recipe to copy: `simctl boot` → `bootstatus -b` → build with
     `-destination` = the sim → `simctl install` → `simctl launch`, against the
     **sim** product path `Debug-iphonesimulator/SingleThread.app` (distinct
     from the `Debug-iphoneos/` path the Duo uses).
   * Respect the per-worktree simulator lock / window conventions (see the
     `simulator` skill) — do not boot a shared device another lane holds.
3. **Escape hatch:** add `IOS_TARGET=sim|device` (default `sim`) so the old
   all-physical behavior is one env var away. Document it in the header block.
4. **Two decisions the plan must resolve with the human** (the ticket flags
   both as "decision needed"):
   * Watch leg — leave on physical watches (ticket's assumption) or move to
     paired watch sims.
   * Duo identity — name match on `iPhone Duo` (fails open if renamed) vs a
     hardcoded `DUO_DEVICE_ID=` env override.
5. **Summary output** must report both legs honestly (Duo launched, sims
   launched, macOS status) instead of collapsing them into one line.
6. **Update `scripts/test-run-devices.sh` (223 lines):** the
   `"every paired physical iPhone installs (Duo included)"` flow assertion
   becomes Duo-only (1/1); the discovery-filter fixtures need a sim-vs-device
   split; flow tests need a **stubbed `simctl`**; cover both happy and sad
   paths (sim boot failure, missing sim product, Duo unreachable).

Why: each current run costs N device builds and needs unlocked, on-network
hardware for the phone/iPad legs — that friction is what this removes. Sims give
the same "app is running where I can poke at it" feedback without the hardware
dance. No new unit-test target is required — `scripts/test-run-devices.sh` is
the coverage. Out of scope: the watch leg (unless decided above), the macOS leg,
and CI.

## Why MEDIUM

M1 holds: approach known — 2 flagged decisions only, no new technology (`simctl`
is already used), and a working recipe exists to copy
(`scripts/appstore-screenshots.sh:548-551`) alongside a UDID-resolution pattern
(`scripts/test.sh:28-72`). M2 holds: no schema/migration, no new subsystem or
integration, no API/UI surface, no new test target; the two open items are
scoped choices resolvable at the plan gate. M3 holds: **MULTI_MODULE** (spans
`scripts/run-devices.sh`, `scripts/test-run-devices.sh`, and the devicectl
fixture) and **BROAD_TEST_SURFACE** (the flow-test harness must gain a stubbed
`simctl` plus sim-vs-device fixtures and sad-path cases). This is known-approach
work at a broad size — one plan step, then the standard implement → review tail.

## Key files

* `scripts/run-devices.sh` (468 lines) — the target; iOS discovery filter,
  device build/install/launch loop, leg counters, and Phase 3 summary, plus the
  `RUN_WATCH` / `RUN_MAC` env-var pattern to mirror for `IOS_TARGET`.
* `scripts/test-run-devices.sh` (223 lines) — the coverage; `extract_filter()`,
  `run_flow()` harness, the 3/3-launched assertion to retarget, and the fixture
  assertions.
* `scripts/fixtures/devicectl-devices.json` — device inventory fixture; contains
  the physical `Fixture iPhone Duo` and the sim entries that drive the
  sim-vs-device split.
* `scripts/appstore-screenshots.sh:548-551` — the working `simctl` boot/install/
  launch recipe to copy.
* `scripts/test.sh:28-72` — `.simulator_id` / shared-default UDID resolution and
  the multi-runtime ambiguity guard to replicate, not reinvent.
* `Makefile` / `scripts/test.sh` — check whether a new `IOS_TARGET`/fixture seam
  needs wiring into the test gate.
