# Implementation Summary

Ticket: VAR-1175 — run the regular iPhone and iPad legs in simulators.
Branch: `alanvardy-var-1175-run-the-regular-iphone-and-ipad-legs-in`

## Commits

| Phase | Commit     | Description                                        |
|-------|------------|----------------------------------------------------|
| 1     | `40425634` | Walking skeleton — sim iPhone leg end-to-end       |
| 2     | `de664f63` | iPad simulator leg and sim sad paths               |
| 3     | `f46205ca` | Watch leg on watch simulators                      |

Bootstrap commit (parent): `b0b7b4f9` — plan/task artifacts added, `DELETEME`
marker removed (`git rm DELETEME`) as required before merge.

## What shipped

`scripts/run-devices.sh` now:

- Runs the **regular iPhone and iPad legs in simulators** by default
  (`IOS_TARGET=sim`), booting via `simctl bootstatus -b`, building with
  `-destination id=<udid>`, then `simctl install` / `simctl launch`.
- Keeps the **physical iPhone Duo** on devicectl in both modes.
  `DUO_DEVICE_ID=<udid>` wins when set, otherwise a case-insensitive
  substring match on the device name (`iPhone Duo`).
- Runs the **Apple Watch leg on a watch simulator**
  (`Apple Watch Series 11 (46mm)` by default); the physical watch discovery /
  devicectl install / launch path, `WATCH_UNREACHABLE*`,
  `WATCH_BUILD_NEEDED`, the launch-form bookkeeping and the 4016 messaging are
  gone. An unavailable watch sim is a notice, not a failure.
- Offers `IOS_TARGET=device` to restore the old all-physical iPhone/iPad sweep
  (the Duo is still deployed physically, and the watch still runs on a sim —
  there is deliberately no `WATCH_TARGET`).
- Resolves simulator names to concrete UDIDs (`resolve_sim_udid` copied from
  `scripts/test.sh`, anchored `index(s, n " (") == 1` match) so `iPhone 17`
  never picks up the leftover `Gate iPhone 17` sim; the iPhone prefers this
  worktree's `.simulator_id`, the iPad and watch never inherit it.
- Reports every leg honestly in the summary:
  `iPhone/iPad (sim): N/M launched` + `iPhone Duo (device): …` in sim mode,
  `iPhone/iPad (device): …` in device mode, `Apple Watch (sim): …` or
  `skipped (RUN_WATCH=0)`.

`scripts/test-run-devices.sh` was rewritten for the new behaviour and stays
offline-only (stubbed `xcrun`/`xcodebuild`/`open`, sim-vs-device fixtures).

## Automated Checks

- [x] `bash -n scripts/run-devices.sh` passes (all phases)
- [x] `bash -n scripts/test-run-devices.sh` passes
- [x] `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` passes
- [x] `bash scripts/test-run-devices.sh` passes — all filter and flow checks,
      including the sim happy path (`2/2 launched`), `IOS_TARGET=device`
      oracle, `DUO_DEVICE_ID`, boot failure, missing sim product, unresolvable
      iPad sim, watch launch, no-watch-sim notice, and watch boot failure
- [x] `make lint` passes (0 violations, 248 files)
- [x] No watch `devicectl` references remain in `scripts/run-devices.sh`
      (`WATCH_DEVICES|WATCH_UNREACHABLE|watchkitapp.*devicectl` → nothing; the
      `4016` alternative still matches two pre-existing **iOS-only** comments,
      which are in scope for neither this ticket nor Phase 3)
- [x] `test-run-devices.sh` needs no gate wiring:
      `rg -n 'test-run-devices' Makefile scripts/test.sh` returns nothing

## Observations (not changed — out of plan scope)

- Phase 3 used `resolve_ios_udid "$SIM_WATCH" "$DEFAULT_WATCH_SIM" 0` rather
  than the plan's literal `resolve_sim_udid "$SIM_WATCH"`, so the documented
  "empty → Apple Watch Series 11 (46mm)" default and the
  `SIM_WATCH=No Such Watch` sad path both behave as the header and tests say.
- The header still describes devicectl provisioning-device registration for
  the Duo (still accurate); the simulator legs don't need it.

## Manual Verification Items (from the plan)

- [ ] `IOS_TARGET=device DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_WATCH=0 RUN_MAC=0 ./scripts/run-devices.sh`
      emits the old all-physical discovery/filter messages and the `(device)`
      summary line.
- [ ] After the sim leg runs for real, confirm the booted worktree sim shows the
      app launched.
- [ ] `./scripts/run-devices.sh` (or `r`) boots the worktree iPhone sim **and**
      the iPad sim, installs/launches `SingleThread` on both, and the summary
      prints `iPhone/iPad (sim): 2/2 launched`.
- [ ] With `SIM_IPAD=No Such Device ./scripts/run-devices.sh`, the run reports
      the iPad as a failed step but still launches the Duo (if present) and
      macOS.
- [ ] `./scripts/run-devices.sh` (or `r`) boots an Apple Watch simulator,
      installs and launches `SingleThreadWatch`, and prints
      `Apple Watch (sim): 1 launched, 0 failed`.
- [ ] `RUN_WATCH=0 ./scripts/run-devices.sh` prints
      `Apple Watch (sim): skipped (RUN_WATCH=0)` and does no watch build.
- [ ] With `IOS_TARGET=device` and a Duo + watches present, only the Duo is
      touched on hardware and the watch still runs on the simulator.

## Post-plan gate (review step)

- [ ] `./scripts/test.sh` via the `run-gate` skill (build + lint + Periphery +
      unit + UI) — runs **once**, after the phases commit.
- [ ] `make format` + `make lint` before the final commit.
