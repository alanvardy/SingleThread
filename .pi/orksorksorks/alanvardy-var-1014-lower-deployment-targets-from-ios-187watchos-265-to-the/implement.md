# Implementation Summary

All three phases of the VAR-1014 plan are implemented, verified, committed, and
the full CI-identical gate (`./scripts/test.sh`) passed via the `run-gate` skill
(covered HEAD `a6931e17`, the tip committed before launch). No floor value was
changed by this ticket; the only production-file diff is `scripts/test.sh`
(gate hardening).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `9fef14f8` | Prove iOS 17.0 floor — red probes at 16.0 (gate drift, SPM consumer-floor, `build-for-testing`) naming `Observable()`/`ObservationTracked()` + `requestFullAccessToReminders()` "only available in iOS 17.0 or newer"; landed gate green; build + targeted suites + `ui-test` + smoke launch (EventKit auth prompt, grant→fetch) on the degraded iOS 26.0 sim |
| 2     | `df53dc62` | Prove watchOS 11.0 floor — gate drift red at 10.0; 9.0 red naming `Observable()` + `EKAuthorizationStatus.fullAccess` "only available in watchOS 10.0 or newer"; 10.0 green-but-rejected; `watch-build`/`watch-test`/`watch-ui-test` green on the degraded watchOS 26.0 sim; `lib_TestingInterop.dylib` verdict: NOT needed on 26.0 |
| 3     | `ca5c8d1b` | Gate hardening: per-platform literal-count guards (8/6/6 + 1/1/1) replacing the collapsed totals; corrected macOS-listing claim; `verification.md` + PR #201 body written; probes 3a–3d red/green proven; `make mac-test` at 26.5; format/lint clean |
| —     | `a6931e17` | chore: correct gate-cover commit SHA in verification record |
| —     | *(this commit)* | plan.md gate checkbox + verification.md verdict + this summary |

## Automated Checks

- [x] Probe 1a: `probe-ios16.0-drift-gate.log` — `❌ Deployment-target drift`, `✗ IPHONEOS = 17.0 (expected 16.0)` ×8, never reached `==> Unit tests`
- [x] Probe 1b: `probe-ios16.0-package-floor.log` — SPM consumer-floor enforced: `error: compiling for iOS 16.0, but module 'SingleThreadCore' has a minimum deployment target of iOS 17.0`
- [x] Probe 1c: `probe-ios16.0-build.log` — 190 availability errors naming `Observable()`/`ObservationTracked()`/`ObservationRegistrar` + `requestFullAccessToReminders()` (sourced `EKEventStore.h:88`)
- [x] Landed gate green after every probe; floor files restored (8×17.0 / 1×`.iOS 17.0`); `make build` + suites (34/12/9/2 ok cases, N>0) + `make ui-test` green on the probe sim
- [x] Probe 2a: `probe-watchos10.0-drift-gate.log` — `✗ WATCHOS = 11.0 (expected 10.0)`, no unit-test phase
- [x] Probe 2b: `probe-watchos9.0-build.log` — `'Observable()' is only available in watchOS 10.0 or newer` + `'fullAccess' … watchOS 10.0` (`InMemoryEventStore.swift:38`)
- [x] Probe 2c: `probe-watchos10.0-build.log` — BUILD SUCCEEDED (green-but-rejected: only buys Series 4/5/SE1, not a product goal)
- [x] `probe-watchos-landed-gate.log` — `✓ All deployment-target + package-floor literals match`; watch-build/watch-test/watch-ui-test all green (probe pair `5EAA9B61-…`)
- [x] Probes 3a–3d: `probe-gate-watchos-swap.log` (`✗ WATCHOS literal count 5`), `probe-gate-literal-removed.log` (count 5 again), `probe-gate-package-removed.log` (`✗ package .watchOS count 0`), `probe-gate-clean.log` (`✓ … iOS 17.0 × 8, watchOS 11.0 × 6, macOS 26.5 × 6; package .iOS 1, .watchOS 1, .macOS 1`)
- [x] `make format` / `make lint` exit 0; `make mac-test` at `platform=macOS`, floor still 26.5
- [x] Full gate via `run-gate`: **PASS** (covered `a6931e17`; 658 passed / 3 known local-only macOS `EntitlementStoreTests` annotated; `gate.md` saved). Run 1 aborted at the watch UI stage on the name-only `WATCH_TEST_SIM` ambiguity (documented env issue); run 2 with the UDID pin (`3F69EA19-…`, CI's own pattern) completed every stage
- [ ] CI on PR #201 green — **cannot report pre-merge** (`ci.yml` triggers on pushes to `main` only); the CI-identical full gate passed locally instead; CI adjudicates post-merge

## Manual Verification Items (from the plan)

- [ ] `probe-runtimes.md` records the exact downloaded iOS runtime build, the created device UDID, and the named verification gap — **done by subagents** (iOS 26.0/23A343, `DD998B17-…`; gap: catalog serves no pre-26 runtime)
- [ ] Smoke launch on the iOS sim reaches the reminder list; EventKit authorization prompt observed (grant → list renders) — **done** (prompt observed; grant path fetches lists; deny path not exercised); outcome written into `probe-runtimes.md`
- [ ] Probe logs + `probe-runtimes.md` committed under the artifact directory — **done**
- [ ] `probe-runtimes.md` records the watchOS runtime build + device UDID, the pairing used, and the `lib_TestingInterop` verdict — **done** (watchOS 26.0/23R353, `09529744-…`, pair `5EAA9B61-…`, verdict: NOT needed on 26.0)
- [ ] Smoke launch on the watchOS sim renders the reminder list — **done** (stable PID, no crash-respawn; UI smoke test passed)
- [ ] All watch probe logs + `probe-runtimes.md` updates committed — **done**
- [ ] `verification.md` exists, lists every probe log, runtime versions/UDIDs, the macOS-listing correction, and the named gap — **done** (+ gate verdict appended)
- [ ] PR #201 body updated with the proof, the correction, and "no new unit test — the gate is the test" — **done** via `gh pr edit 201` (86-line body; PR still draft)
- [ ] No floor value changed: `git diff origin/main -- project.pbxproj Package.swift` is empty — **verified** (only `53124c3e`'s landed content)
- [ ] Only production-file diff is `scripts/test.sh` — **verified** (`44 insertions, 39 deletions`; Gate hardening)

## Notes / observations (out of phase scope)

- **Named verification gap** (both platforms): the Xcode 27.0 catalog serves **no pre-26 iOS/watchOS runtime** (17.x–25.x refused; no importable `.dmg`); the runtime leg validated on iOS 26.0 / watchOS 26.0 only. Compile-time probes unaffected (SDK annotations + deployment target). Stated in `probe-runtimes.md`, `verification.md`, and the PR body.
- **PR #201 title** still reads "…to the proven floor (iOS 17.0/watchOS 10.0)"/"10.0" — stale vs the shipped watchOS 11.0 ship floor. Plan scoped PR edits to the body only; title left untouched for the user to decide.
- **Gate run 1** aborted at the watch UI stage: name-only `WATCH_TEST_SIM` cannot resolve with three watchOS runtimes present (the var-1016 known issue); re-run with UDID pin passed. No source change was needed.
- One-off flake during Phase 3 probe 3d (`SettingsViewTests.showMenuBarExtraRoundTripsThroughContentView`) passed in isolation and in the authoritative gate run — no recurrence.