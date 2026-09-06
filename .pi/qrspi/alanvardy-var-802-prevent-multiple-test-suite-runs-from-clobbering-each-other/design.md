# Design Discussion

## Current State

Two surfaces where concurrent test runs can interfere, and they are wildly
asymmetric:

**Local (this machine): the whole interference surface, zero enforcement.**
- Every invocation shares one fixed `DerivedData` (`test.sh:15`, `Makefile:9`).
  Nothing makes it per-invocation, and all 8 phases of the full gate share it
  sequentially in one bash process (`set -euo pipefail`, `test.sh:3`, phases
  `test.sh:211-292`). A second concurrent `make`/`test.sh` writes the same path.
- No lock, semaphore, or serialization machine exists anywhere (research Q6).
  "One xcodebuild test process at a time" is a convention only
  (`AGENTS.md:19-22`). Documented damage: a full gate twice OOM-killed by a
  concurrent `xcodebuild` from another session (var-783 `implement.md:33-37,
  76-82`), plus `Busy`/`RequestDenied` runner-launch flake storms on a shared
  base simulator (var-755 `phase6-evidence.md:28-39`), and a degraded reused
  watch sim (`phase6-evidence.md:67-71`).
- Simulators are reused across runs: no shutdown/erase/terminate anywhere in
  local automation (research Q2); the only cleanup is age-gated XCTestDevices
  pruning (`test.sh:17-18`, `test.sh:53-84`, invoked `test.sh:104`). Watch UI
  depends on a manually paired watch (`.pi/skills/simulator-pairing/SKILL.md:12-15`).
- Persisted app state: `--seed` is the only blanket reset (`UITestingSeed.swift:62-68`);
  `--ui-testing` deliberately retains state (`AppViewModel.swift:214-258`), and
  some UI tests *depend* on cross-launch retention
  (`SingleThreadUITestsFlows.swift:132-198`, `SingleThreadUITestCase.swift:47-61`).

**CI (GitHub Actions): already substantially isolated.**
- Fresh `macos-26` VM per job discards all job-local FS/simulator state; a
  workflow-level `concurrency` group with `cancel-in-progress: true` serializes
  runs per ref (`ci.yml:8-10`); the watch job creates a fresh unpaired watch per
  run (`ci.yml:391-401`).
- Residual risk is narrow: the iOS DerivedData cache key is device-agnostic and
  byte-identical across all 4 jobs × 2 devices (`ci.yml:43, 111, 172, 231`), so
  iPhone/iPad legs restore each other's products (whichever leg saves first wins
  the entry); and `TestResults.xcresult` (`ci.yml:80`) is a fixed, non-device-
  qualified artifact name.

Every documented incident is environmental (contention/flake/OOM), never a logic
bug; every prior fix landed in CI/build config, not test code (research Q6).

## Desired End State

- **Local**: the "one at a time" convention is already enforced on `main`
  (`b82e54f` re-execs `test.sh` under `/usr/bin/lockf`, waiting on a shared
  flock rather than failing fast). What remains is a gate that begins from a
  deterministic simulator state (shutdown → reboot → verified watch pair).
- **CI**: the four iOS jobs' DerivedData caches are keyed per device, and
  `TestResults.xcresult` is device-qualified, so no cross-leg restore race or
  artifact-name collision.
- **Verification**: (1) full `./scripts/test.sh` passes after the change;
  (2) launching a second `./scripts/test.sh` while one is running fails fast
  rather than running; (3) CI keys differ between iPhone and iPad legs; (4) the
  watch-pair/sim-reboot preamble runs without regressing the existing paired-watch flow.

## Patterns to Follow

- `build-for-testing` → `test-without-building` for everything except macOS's
  combined `test` action (`test.sh:236/244`, `test.sh:288-292`) — keep this.
- UDID resolution + pre-boot: `resolve_sim_udid()` + `preboot_sim()` with
  `simctl bootstatus -b` (`test.sh:22-36, 44-51`) — extend, don't replace.
- Age-gated cleanup that never disturbs in-flight runs (`test.sh:50-84`) — the
  new lock must respect the same "don't yank a live run" principle.
- Local/CI divergence is deliberate and load-bearing: local iOS unit runs
  `-parallel-testing-enabled YES` (`test.sh:234`) while CI pins `NO`/`1`
  everywhere (`ci.yml:76-77`). Do **not** unify them.
- `--seed`/`--ui-testing` state semantics are load-bearing for UI tests
  (`UITestingSeed.swift:62-68`, `AppViewModel.swift:214-258`) — no teardown added.

**Patterns NOT to follow** (found but rejected):
- Do not copy CI's parallel-disable flags locally (`ci.yml:76-77` vs `test.sh:234`;
  they are a virtualized-runner clone workaround, var-755 plan.md:560).
- Do not add a lock to CI — fresh-VM + concurrency group already serialize; the
  lock is a local-machine mechanism only.
- Do not erase app/UserDefaults state before each test — it breaks the
  cross-launch retention tests (`SingleThreadUITestsFlows.swift:132-198`).

## Design Decisions

1. **Scope — minimal targeted mitigation (Q1-B).** Local serialization + CI
   cache/artifact scoping only. The OOM is real and cheap to fix; comprehensive
   isolation (per-invocation DerivedData, per-run sim clones) costs gate time and
   blast radius without corresponding safety.

2. **Local serialization — landed on `main` via `lockf` (supersedes an earlier
   `shlock` design).** `b82e54f` re-execs `scripts/test.sh` under
   `/usr/bin/lockf -k -t <timeout>` holding a shared flock at
   `$HOME/.cache/pi/test-gate.lock`, waiting (default 3600s) rather than
   failing, crash-safe (killing the holder releases the lock), bypassable via
   `PI_TEST_NO_LOCK=1`/CI. The `shlock` proposal (fail-fast pid lock + `trap` +
   stale-pid recovery) is dropped — `lockf` is strictly better for the OOM case.
   `make build`/`make build-for-testing` bypass `test.sh` and remain lock-free.

3. **DerivedData — keep shared (Q3-A).** The Q2 lock serializes writers, so the
   fixed `DerivedData` (`test.sh:15`) no longer gets concurrent xcodebuild
   processes. Preserves incremental-build speed; no per-invocation paths.

4. **Simulator lifecycle — shutdown + reboot + verified watch pair before the gate
   (Q4-B).** Pre-gate preamble in `test.sh`: `simctl shutdown all`, then boot the
   resolved iPhone and the watch, then assert the pair exists (else follow the
   pairing skill's `simctl pair` recovery, `.pi/skills/simulator-pairing/SKILL.md:12-15`).
   Gives deterministic boot state, kills the reused/degraded-sim failure class,
   and keeps local watch-UI pairing (which CI deliberately skips).

5. **CI scoping — device-scoped cache key + qualified artifact name (Q5-A).**
   Add `matrix.device` (and/or the resolved SIM id) to the iOS DerivedData cache
   key so iPhone/iPad legs never restore each other's products; device-qualify
   `TestResults.xcresult` (e.g. `TestResults-ipad.xcresult`) so the two
   `unit-tests` legs can't collide on the failure-only upload name.

## What We're NOT Doing

- No per-invocation/per-phase DerivedData paths (Q3-B/C).
- No per-run simulator clones (Q4-C); no CI-side lock (Q2 in CI is moot).
- No change to `--seed`/`--ui-testing`/`--reset-*` state semantics, the
  App-Group tier map, or any test code — the persistence surface is
  intentionally load-bearing.
- No coverage/periphery/lint changes; no new `.xcodeproj` targets or schemes.
- No new test suites beyond what verification needs.
- Not changing the macOS combined-`test` action or the watch build/test split.

## Open Risks

- **Lock granularity/staleness**: resolved on `main` — the `lockf` flock is
  held for the whole run and auto-released on kill; pid-reuse/stale-lock
  concerns don't apply. (The earlier `shlock` design carried these risks and is
  dropped.)
- **First CI run after the Q5 key change is a cache miss** and cache storage
  grows (8 device-scoped iOS entries instead of ~1 shared). Acceptable; call out
  in the PR.
- **Watch pairing automation is the local flakiest step** (the pairing skill
  exists precisely for this); the Q4 preamble may surface pair drift that was
  previously invisible. Confirm it fails *loudly* rather than silently proceeding.
- **XCTestDevices 1-hour age gate** (`test.sh:17-18`) vs runs longer than 1 h:
  the "APFS keeps open handles alive" claim is stated, not measured — the new
  lock adds a reason to retest a gate that outlives the prune window.
- **Artifact-name downstream consumers**: `TestResults.xcresult` is only
  uploaded `if: failure()` (`ci.yml:83, 86-87`) and never downloaded (research
  Q5), but any human convention that greps for `TestResults.xcresult` will break
  on the qualified name.