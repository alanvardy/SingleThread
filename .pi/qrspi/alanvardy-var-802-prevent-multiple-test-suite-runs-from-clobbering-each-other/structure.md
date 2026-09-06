# Structure Outline

## Approach

Minimal targeted mitigation: add a deterministic simulator-lifecycle preamble to the local gate, and scope CI's DerivedData cache key + xcresult artifact name per-device. The local test-gate serialization (the "one xcodebuild test process at a time" convention) is **already enforced** on `main` (`b82e54f`: `lockf`-based flock at `$HOME/.cache/pi/test-gate.lock`), so no lock work is in scope here. No Swift code, test code, or persistence semantics change; DerivedData stays shared (the existing lock serializes writers).

---

## Stage 1: Simulator Lifecycle Preamble (`scripts/test.sh`)

**What this layer delivers**: Every gate invocation starts from a deterministic simulator state — all simulators are shut down, the resolved iPhone is booted, and the watch pair is verified. This eliminates the reused/degraded-sim failure class (var-755 `phase6-evidence.md:28-39, 67-71`).

**Files**: `scripts/test.sh`

**Key changes**:
- `prepare_simulators()` — runs early in the script (already serialized by the `lockf` test-gate lock):
  1. `xcrun simctl shutdown all` — kill everything; safe because the lock guarantees no other gate is mid-run
  2. `resolve_sim_udid()` + `preboot_sim()` — existing functions (`test.sh:22-36`), extended to apply to both `SIM` and `WATCH_TEST_SIM` (the watch is not pre-booted today; only iOS is)
  3. `assert_watch_pair()` — resolves the watch UDID from `WATCH_TEST_SIM`, resolves the phone UDID from `SIM`, runs `xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID"` if unpaired; follows the pairing skill's recovery path (`.pi/skills/simulator-pairing/SKILL.md:12-15`). Fails loudly with diagnostic output if pairing is impossible (no watch found, no phone found, pair command fails)
- Gate the `prepare_simulators` call: `make build` / `make build-for-testing` invoke `xcodebuild` directly (not `test.sh`), so they bypass the preamble and do not disturb a running gate's sims.
- Keep the watch pre-boot separate from CI (CI boots the watch explicitly at `cit.yml:403-406` and creates a fresh unpaired watch at `:391-401` — no change).

**Verification**:
1. Fresh gate: `./scripts/test.sh --unit-only` → sims are shut down, iPhone boots, watch pair verified (check `xcrun simctl list devices` before and after)
2. Degraded-watch scenario: manually unpair the watch (`simctl unpair`), run gate → watch is re-paired, gate proceeds
3. Missing-watch scenario: no watch device exists → `prepare_simulators` warns loudly, gate continues to the watch phase which fails with a clear xcodebuild error (does not hang)

**Verify**: run `./scripts/test.sh --unit-only && ./scripts/test.sh --unit-only` sequentially (two passes). Manually unpair watch → run → pairing re-established. Delete watch sim → run → clear warning.

---

## Stage 2: CI DerivedData Cache Key Per-Device (`ci.yml`)

**What this layer delivers**: Each iOS matrix leg (iPhone 17 / iPad (A16)) gets a distinct DerivedData cache key, so iPhone and iPad legs never restore each other's build products. This eliminates the cross-device cache race where whichever leg saves first wins the entry.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- In each of the 4 iOS jobs (`unit-tests`, `ui-tests-flows`, `ui-tests-launch-appearance`, `ui-tests-audits`), modify the `actions/cache@v4` key from the current identical string:
  ```
  derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles(...) }}
  ```
  to:
  ```
  derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ matrix.device }}-${{ github.ref_name }}-${{ hashFiles(...) }}
  ```
  — `${{ matrix.device }}` is already in scope via the job matrix (`device: ["iPhone 17", "iPad (A16)"]`).
- `restore-keys` fallback prefixes must also include `matrix.device` so a ref-specific miss falls back to the same device on a sibling ref, not across devices.
- The `mac-tests` job and `watch-ui-tests` job already have their own prefix (`derived-data-mac-` / `watch-ui-derived-data-`) and are unaffected.

**Verification**:
1. Push to a PR branch → CI runs → inspect the "Restore cache" / "Save cache" step logs for two iOS legs of the same job — confirm the iPhone leg's key contains `iPhone 17` and the iPad leg's key contains `iPad (A16)` and they differ
2. First run is a cache miss on both (expected — new keys). Second push → a restore hit on each leg's own device-scoped key
3. Cache storage grows from ~1 shared iOS entry to ~8 device-scoped entries (one per job × per device) — acceptable per design decision 5

**Verify**: CI run log inspection (GitHub Actions web UI → cache steps). No local verification possible.

---

## Stage 3: CI xcresult Artifact Name Per-Device (`ci.yml`)

**What this layer delivers**: The two `unit-tests` matrix legs (iPhone 17 / iPad (A16)) upload their failure-only `TestResults.xcresult` with device-qualified names, so the two legs of the same job never collide on the artifact name.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- In the `unit-tests` job (`ci.yml:80`), change:
  ```
  -resultBundlePath TestResults.xcresult
  ```
  to:
  ```
  -resultBundlePath TestResults-${{ matrix.device }}.xcresult
  ```
  (e.g. `TestResults-iPhone 17.xcresult`, `TestResults-iPad (A16).xcresult`)
- In the upload-artifact step (`ci.yml:86-87`), change the `name` from `unit-test-results` to `unit-test-results-${{ matrix.device }}` so the two artifacts are distinct in the GitHub Actions UI
- `mac-tests` already uses `TestResults-mac.xcresult` (`ci.yml:313`) and is a single leg — no change needed
- The three iOS UI jobs and the watch job upload nothing and pass no `-resultBundlePath` — no change needed

**Verification**:
1. Push to a PR branch → CI runs → (ideally a failure) → inspect the artifacts tab — two distinct artifacts: `unit-test-results-iPhone 17` and `unit-test-results-iPad (A16)`
2. Even on a pass, confirm no artifact-name collision error in the logs (the `if: failure()` gating means the upload step is skipped on pass, but xcodebuild still writes the qualified `-resultBundlePath` to each VM's workspace root)

**Verify**: CI run log inspection. Induce a unit-test failure on a test branch to trigger the upload and confirm artifact names.

---

## Testing Checkpoints

| After Stage | What must be green before advancing |
|---|---|
| Stage 1 | Sequential gate passes (first gate's sims survive); unpaired watch is re-paired; missing watch warns loudly |
| Stage 2 | CI logs show device-qualified cache keys differ between iPhone/iPad legs; second push shows cache hits |
| Stage 3 | CI logs show device-qualified xcresult paths; failure artifact names are distinct |

---

## Notes

- **No Swift code changes** — all work is in `scripts/test.sh` (Stage 1) and `.github/workflows/ci.yml` (Stages 2-3).
- **No new test suites** — verification is manual (local pairing) and CI log inspection. There are no automated tests for shell scripts in this repo.
- **Local lock is out of scope** — the test-gate serialization already landed on `main` (`b82e54f` uses `/usr/bin/lockf`, not `shlock`). This plan builds on that lock rather than adding a second one.
- **Stage 1 runs under the existing lock** — `test.sh` re-execs under `lockf`, so `prepare_simulators` is automatically serialized against concurrent gates.
- **Watch pre-boot in Stage 1** is new (currently only iOS is pre-booted). This makes watch UI test startup deterministic locally and aligns with CI's explicit watch boot (`ci.yml:403-406`).
- **Stage 1 is local-only; Stages 2-3 are CI-only and independent of Stage 1** — they can be developed and verified in parallel, but the structure order reflects logical layering (local preamble, then cache scoping, then artifact naming).