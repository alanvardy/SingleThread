# Implementation Plan

## Overview

The local test-gate serialization is already landed on `main` (`b82e54f`: `lockf`-based flock at `$HOME/.cache/pi/test-gate.lock`, wait-don't-fail, crash-safe, CI-bypassed) — so no local lock work is needed here. Remaining work: a deterministic simulator-lifecycle preamble locally, plus per-device scoping of CI's DerivedData cache key and xcresult artifact name. No Swift code, no test code, no persistence-semantics changes.

---

## Phase 1: Simulator Lifecycle Preamble (`scripts/test.sh`)

**Context**: `scripts/test.sh` re-execs itself under `/usr/bin/lockf` (`b82e54f`), so any code added here is automatically serialized against concurrent gates. `make build` / `make build-for-testing` invoke `xcodebuild` directly (not `test.sh`), so they bypass this preamble and stay lock-free.

### Changes

#### 1. Add `prepare_simulators()` function
**File**: `scripts/test.sh`
**Action**: modify — insert after `preboot_sim()` (after the `}` on line 36-ish) and before the `cd` on line ~38

```bash
# Bring simulators to a deterministic state before the gate: shutdown all, boot
# the resolved iPhone and watch, and verify the watch pair. Safe to run because
# the whole script is already serialized under the lockf test-gate lock.
prepare_simulators() {
    echo "==> Preparing simulators…"

    # 1. Shutdown everything for a clean slate.
    xcrun simctl shutdown all 2>/dev/null || true
    echo "    All simulators shut down."

    # 2. Resolve and pre-boot the watch sim (iOS is already pre-booted above).
    local watch_udid
    if [[ "$WATCH_TEST_SIM" == *",id="* ]]; then
        watch_udid="${WATCH_TEST_SIM##*id=}"
    else
        local watch_name
        watch_name="${WATCH_TEST_SIM##*name=}"; watch_name="${watch_name%%,*}"
        watch_udid="$(resolve_sim_udid "$watch_name")"
        if [[ -n "$watch_udid" ]]; then
            WATCH_TEST_SIM="platform=watchOS Simulator,id=$watch_udid"
        fi
    fi

    if [[ -n "${watch_udid:-}" ]]; then
        xcrun simctl boot "$watch_udid" 2>/dev/null || true
        xcrun simctl bootstatus "$watch_udid" -b
        echo "    Watch pre-booted: $watch_udid"
    else
        echo "    ⚠️  Could not resolve watch UDID — watch tests may fail."
    fi

    # 3. Assert the watch-phone pair exists for watch UI tests.
    if [[ -n "${watch_udid:-}" ]]; then
        local phone_udid="${SIM##*id=}"
        if ! xcrun simctl list pairs | grep -q "$watch_udid"; then
            echo "    Pairing watch ($watch_udid) with phone ($phone_udid)…"
            if xcrun simctl pair "$watch_udid" "$phone_udid" 2>/dev/null; then
                echo "    ✓ Watch paired."
            else
                echo "    ❌ Failed to pair watch with phone." >&2
                echo "    Manual pairing needed:" >&2
                echo "    xcrun simctl pair $watch_udid $phone_udid" >&2
                # Don't exit — let the gate proceed and fail at the watch UI phase
                # with a clearer xcodebuild error.
            fi
        else
            echo "    ✓ Watch-phone pair verified."
        fi
    fi

    echo "==> Simulators ready."
}
```

#### 2. Call `prepare_simulators()` early in the script
**File**: `scripts/test.sh`
**Action**: modify — insert `prepare_simulators` call after `cleanup_xctest_runtimes` (currently line ~104) and before the `verify_deployment_target` section

```bash
# Bring simulators to a deterministic state. Safe under the lockf test-gate lock.
prepare_simulators
```

The existing pre-boot of the iOS sim (`preboot_sim` on lines ~44-51) stays as-is; `prepare_simulators` adds the watch pre-boot, shutdown-all, and pair assert.

### Verification

#### Automated
- [ ] `./scripts/test.sh --unit-only` → sequential two runs both pass (lock released between runs, sims re-prepared each time)
- [ ] `./scripts/test.sh --unit-only && ./scripts/test.sh --unit-only` — both pass, no contention on the second run

#### Manual
- [ ] Unpair watch: `xcrun simctl unpair <watchUDID>` → `./scripts/test.sh --unit-only` → pairing re-established
- [ ] Delete watch sim → `./scripts/test.sh --unit-only` → "Could not resolve watch UDID" warning, gate proceeds
- [ ] Full gate `./scripts/test.sh` → watch tests pass after preamble boot + pair

---

## Phase 2: CI DerivedData Cache Key Per-Device (`ci.yml`)

### Changes

#### 1. All four iOS jobs — cache key and restore-keys
**File**: `.github/workflows/ci.yml`
**Action**: modify — identical edit in each of the four iOS jobs: `unit-tests`, `ui-tests-flows`, `ui-tests-launch-appearance`, `ui-tests-audits`

Each job's `actions/cache@v4` block has this pattern (repeated 4×):

**Old**:
```yaml
          key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThreadCore/**', 'SingleThreadWatch/**', 'SingleThreadWatchUITests/**', 'SingleThreadWidget/**', 'SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-
```

**New** (insert `${{ matrix.device }}-` after `${{ steps.xcode.outputs.version }}-` on all three lines):
```yaml
          key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ matrix.device }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThreadCore/**', 'SingleThreadWatch/**', 'SingleThreadWatchUITests/**', 'SingleThreadWidget/**', 'SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ matrix.device }}-${{ github.ref_name }}-
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ matrix.device }}-
```

Four identical replacements: one per iOS job. `mac-tests` and `watch-ui-tests` jobs are unaffected (already have their own prefix with no matrix).

### Verification

- [ ] Push to a PR branch → CI runs → inspect cache step logs for two iOS legs of the same job — iPhone leg's key contains `iPhone 17`, iPad leg's key contains `iPad (A16)`, they differ
- [ ] First push is a cache miss on both (expected — new keys). Second push → cache hit on each leg's own device-scoped key
- [ ] `mac-tests` and `watch-ui-tests` cache keys unchanged

---

## Phase 3: CI xcresult Artifact Name Per-Device (`ci.yml`)

### Changes

#### 1. `unit-tests` job — `-resultBundlePath` and artifact `name`
**File**: `.github/workflows/ci.yml`
**Action**: modify — two edits in the `unit-tests` job:

**Edit A** — xcodebuild `-resultBundlePath` step (ci.yml ~line 80):
**Old**:
```yaml
            -resultBundlePath TestResults.xcresult
```
**New**:
```yaml
            -resultBundlePath TestResults-${{ matrix.device }}.xcresult
```

**Edit B** — upload-artifact `name` (ci.yml ~lines 86-87):
**Old**:
```yaml
          name: unit-test-results
```
**New**:
```yaml
          name: unit-test-results-${{ matrix.device }}
```

### Verification

- [ ] Push to a PR branch with a unit-test failure → artifacts tab shows two distinct artifacts: `unit-test-results-iPhone 17` and `unit-test-results-iPad (A16)`
- [ ] On pass, confirm no artifact-name collision error in logs (different VMs, so the workspace-root xcresult paths don't collide either)
- [ ] `mac-unit-test-results` artifact name is unchanged

---

## Testing Checkpoints

| After Phase | What must be green before advancing |
|---|---|
| Phase 1 | Sequential gate passes (first gate's sims survive); unpaired watch is re-paired; missing watch warns but doesn't block |
| Phase 2 | CI logs show device-qualified cache keys differ between iPhone/iPad legs; second push shows cache hits |
| Phase 3 | CI logs show device-qualified xcresult paths; failure artifact names are distinct |

---

## Ordering & Dependencies

- **Phase 1 is local** (`scripts/test.sh`); **Phases 2-3 are CI-only** (`.github/workflows/ci.yml`) and independent of Phase 1.
- Phase 1 runs under main's existing `lockf` test-gate lock; no lock acquisition code is added.
- All three phases land in the same PR.

---

## What We're NOT Changing

- No local test-gate lock — already present on `main` via `lockf` (`b82e54f`)
- No Swift code, test code, or persistence semantics
- No per-invocation DerivedData paths
- No per-run simulator clones
- No CI-side lock (fresh VM + concurrency group already serialize)
- No change to `--seed`/`--ui-testing` state semantics
- No new test suites
- No change to `make build` / `make build-for-testing` (they bypass `test.sh` and stay lock-free)
- macOS `test` action stays combined; watch build/test split stays unchanged
- CI parallel-disable flags stay as-is (they are a virtualized-runner workaround)