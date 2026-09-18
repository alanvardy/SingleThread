# Structure Outline

## Approach

Keep `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` as the primary lever and add a
log-scan backstop: one new sourced helper (`scripts/check-warnings.sh`) wraps
each `xcodebuild` in `scripts/test.sh`, `tee`s live output to a log, and scans
the log for source-located `warning:` diagnostics, filtered by a checked-in
allowlist. Each phase is a thin end-to-end increment of the *gate* stack:
pattern logic → helper API → `test.sh` wiring → real build log → user-visible
exit status. Phases 1–2 add only wiring/logic (no product code); Phase 3 is the
one phase that changes source/product config.

**Contract introduced in Phase 1 and frozen for all later phases**:

```bash
# scripts/check-warnings.sh  (sourced by test.sh; also executable)
WARNING_PATTERN='^[^:]+:[0-9]+:[0-9]+: warning: '      # ERE, line-anchored
ALLOWLIST="${ALLOWLIST:-scripts/xcodebuild-warnings.allow}"

run_xcodebuild <log> <cmd> [args...]  # tee -a to <log>, preserves cmd exit status,
                                      # scans <log> only when cmd exited 0
check_warnings <log> [<log>...]       # prints non-allowlisted offenders + count; exit 1 if any
allowlist_match <line>                # internal, exposed for the fixture self-test
```

Scanned shape is the design's decision 2: `<path>:<line>:<col>: warning: …`
only — no xcodebuild meta-warnings, no location-less diagnostics.

---

## Phase 1: Walking skeleton — one real build, scanned, gate goes red

A deliberately introduced compile warning in the iOS app makes the wrapped
first build step fail the gate with the offender printed; a clean tree passes.
Proves the whole path (live tee → log → anchored scan → allowlist → exit 1) and
captures the first real warning inventory.

**Files**: `scripts/check-warnings.sh` (new), `scripts/xcodebuild-warnings.allow`
(new, header + `SingleThreadTests` StoreKitTest entry expected), `scripts/test.sh`
(one build step wired), `scripts/tests/warning-check/run.sh` + `fixtures/*.log`
(new).

**Key changes**:
- `scripts/check-warnings.sh` — the four functions above; called with no args it
  scans `$1`, and exits 1 if the allowlist file is missing (fail closed).
- `scripts/test.sh` — `source "$(dirname "$0")/check-warnings.sh"` near the top;
  `LOG_DIR="$DERIVED_DATA/logs"`; the iOS `build-for-testing` block
  (`test.sh:252-256`) becomes `run_xcodebuild "$LOG_DIR/ios-build.log" xcodebuild …`.
- `run_xcodebuild` must survive `set -euo pipefail` (`test.sh:2`): capture the
  command's status as `"$@" 2>&1 | tee "$log" || status=${PIPESTATUS[0]}` so
  `tee` cannot mask a build failure and `set -e` cannot abort before the scan.
- Fixture runner asserts exit codes: `clean.log`→0, `one-warning.log`→1,
  `allowlisted-only.log`(against `fixtures/allow`)→0, `mixed.log`→1 with only
  non-allowlisted lines printed, `near-miss.log` (a `: warning:` inside test
  output, plus "will be run during every build")→0; plus `fake-fail.sh` (exit 7
  → status preserved, no scan) and `fake-clean.sh`.

**Contract**: the four function names and the allowlist format above; the
"no location ⇒ not an offender" rule.

**Tests**: `scripts/tests/warning-check/run.sh` (self-test above — happy, sad,
near-miss and exit-status cases).
**Verify**: `bash scripts/tests/warning-check/run.sh` passes; then red-first —
add a temporary unused `let x` in a `SingleThread/` file, run the wrapped iOS
`build-for-testing` with the worktree's pinned destination
(`-destination "platform=iOS Simulator,id=$(cat .simulator_id)"`), confirm exit 1
and the offender line; revert and confirm green. Record the captured
non-allowlisted inventory to the artifact directory (this is the spike the
design's Open Risks asks for).

---

## Phase 2: Full local gate coverage — every step, all three modes

Any warning emitted by any build the local gate runs now fails it —
`make check`, `make test` and `make ui-test` alike.

**Files**: `scripts/test.sh` (remaining call sites), `scripts/check-warnings.sh`
(untouched contract), `scripts/xcodebuild-warnings.allow`.

**Key changes**:
- Route the remaining call sites through the wrapper, one log each under
  `$LOG_DIR`: iOS UI build (`test.sh:369-373`), watch build (`:282-286`), watch
  build-for-testing (`:302-307`), watch UI/unit `test-without-building`
  (`:324-329`, `:332-336`), macOS unit full (`:340-347`) and unit-only
  (`:355-360`), iOS UI `test-without-building` (`:294-298`).
- `rm -rf "$LOG_DIR"` at gate start so a stale log cannot produce a phantom
  failure; `DerivedData/` is already gitignored (`.gitignore`), so no new ignore
  entry is needed.
- `test-without-building` steps are wrapped for uniformity; they emit no compile
  diagnostics, so their scan is a no-op.

**Contract**: `run_xcodebuild <log> <cmd…>` used verbatim for every build/test
step; no bare `xcodebuild` invocation remains in `scripts/test.sh`.

**Tests**: extend `scripts/tests/warning-check/run.sh` with a multi-log case
(`check_warnings a.log b.log` aggregates and exits 1).
**Verify**: `bash scripts/tests/warning-check/run.sh` passes; structural
assertion in the house `verify_deployment_target()` style —
`grep -cE '^\s*xcodebuild' scripts/test.sh` is `0`; targeted build-only run of
two wrapped steps (iOS build, watch build) produces logs and `check_warnings`
returns 0 on a clean tree. Full `make check` is deferred to the post-phase gate
(`run-gate` skill), not run here.

---

## Phase 3: Warning-free tree — remediation + allowlist

The gate is green on a clean tree: every warning surfaced in Phases 1–2 is
either fixed in source/config or allowlisted with a one-line rationale.

**Files**: whichever source/config files the captured inventory names
(`SingleThread/`, `SingleThreadWatch/`, `SingleThreadWidget/`,
`SingleThreadCore/Sources/`, `SingleThreadTests/`), plus
`scripts/xcodebuild-warnings.allow`.

**Key changes**:
- Fix real warnings at the source (unused bindings, deprecations, SwiftPM
  package diagnostics). Per design, no pbxproj flag flipping, no
  `Package.swift` `-suppress-warnings`/`.unsafeFlags`, no CLI
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` override.
- Only genuinely unfixable diagnostics go in the allowlist, each with a `#`
  rationale next to it; the StoreKitTest deprecated-symbol entry from Phase 1 is
  the first. `SingleThreadTests` stays at `NO` (`pbxproj:856,885`).
- If the inventory exceeds ~10 distinct items or one fix touches package
  configuration, split this phase in two along the same boundary and re-run the
  Phase 2 verify after each half.

**Contract**: `check_warnings` returns 0 on every log the local gate produces;
the allowlist is the only suppression surface.

**Tests**: no new unit test — this phase changes no product logic; the fixture
self-test is the regression guard for the checker, and each allowlist entry is
proved necessary by a red-first run (drop the entry, confirm the gate goes red
on exactly that diagnostic).
**Verify**: `bash scripts/tests/warning-check/run.sh` passes;
`make build` + `make watch-build` wrapped through the helper yield logs with
zero non-allowlisted offenders; then the full `make check` via the `run-gate`
skill is the authoritative green checkpoint (also on a clean `DerivedData/`, per
the Periphery stale-index note).

---

## Phase 4: CI parity, diagnostics and docs

CI's own build steps enforce the same check with the same allowlist, and a
developer hitting a red gate can see exactly what failed.

**Files**: `.github/workflows/ci.yml` (5 build steps), `scripts/check-warnings.sh`
(annotation output), `AGENTS.md`.

**Key changes**:
- Each `xcodebuild` build step (`ci.yml:52-58,121-127,173-179,237-241,290-297`)
  becomes `… 2>&1 | tee ci-<step>.log; exit ${PIPESTATUS[0]}` followed by
  `bash scripts/check-warnings.sh ci-<step>.log` — the same helper, runnable
  standalone with no `test.sh` sourcing.
- Diagnostics: print offenders as `::warning file=…,line=…::<message>` inside
  GitHub Actions when `$GITHUB_ACTIONS == "true"`, plain lines otherwise; print
  total offender count.
- Log hygiene: cap/clean the per-run logs (they live under the already-ignored
  `DerivedData/ci-logs/` locally; CI step logs are ephemeral).
- `AGENTS.md` "Before Committing" gains one sentence: the gate fails on any
  source-located compiler warning, and unfixable ones belong in
  `scripts/xcodebuild-warnings.allow` with a rationale.

**Contract**: `bash scripts/check-warnings.sh <log>…` is a valid standalone
entry point; allowlist path is repo-root-relative and resolvable from CI's cwd.

**Tests**: `scripts/tests/warning-check/run.sh` gains an annotation-mode case
(`GITHUB_ACTIONS=true` output shape) and an allowlist-path case run from a
non-repo cwd.
**Verify**: `bash scripts/tests/warning-check/run.sh` passes; `ruby -ryaml -e
'YAML.load_file(".github/workflows/ci.yml")'` parses; each of the five build
steps greps as `tee` + `check-warnings.sh`; the exact CI line runs locally
against a captured log and exits 1 on an injected warning. CI itself is the
authoritative check (cannot be run locally) — confirm green on the PR.

---

## Testing Checkpoints

| After | Must be green before advancing |
|---|---|
| Phase 1 | `bash scripts/tests/warning-check/run.sh`; wrapped iOS build red on injected warning, green after revert; inventory recorded |
| Phase 2 | fixture self-test + `grep -cE '^\s*xcodebuild' scripts/test.sh` == 0; two wrapped builds scan clean |
| Phase 3 | fixture self-test; all wrapped local build logs have zero non-allowlisted offenders; full `make check` (run-gate skill) green on a clean tree |
| Phase 4 | fixture self-test (incl. annotation/non-repo-cwd cases); YAML parses; local dry run of the CI line red on injected warning; PR CI green |

**Not in this ticket** (per design "What We're NOT Doing"): flipping
`SingleThreadTests` to `YES`, `Package.swift` flags, CI calling `test.sh`
wholesale, `xcresulttool`-based extraction, new `make`/test targets, the
pre-existing macOS `EntitlementStoreTests` failures.