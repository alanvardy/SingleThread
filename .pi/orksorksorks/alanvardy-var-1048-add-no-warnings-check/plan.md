# Implementation Plan

## Overview

Keep `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` as the primary lever and add a
log-scan backstop: a new sourced helper `scripts/check-warnings.sh` wraps every
`xcodebuild` in `scripts/test.sh`, `tee`s live output to a log, and scans each
log for source-located `warning:` diagnostics filtered by a checked-in
allowlist. The same check runs on CI's five build steps. The tree ends up
warning-free (or explicitly allowlisted), so the gate is green from day one.

**Frozen contract (Phase 1, unchanged through Phase 4) —**
`scripts/check-warnings.sh`:

```bash
WARNING_PATTERN='^[^:]+:[0-9]+:[0-9]+: warning: '   # ERE, line-anchored
ALLOWLIST="${ALLOWLIST:-scripts/xcodebuild-warnings.allow}"  # repo-root-relative

run_xcodebuild <log> <cmd> [args...]   # tee to <log> (truncated per run),
                                       # preserves cmd exit status, scans only
                                       # when cmd exited 0
check_warnings <log> [<log>...]        # prints non-allowlisted offenders + count;
                                       # exit 1 if any / allowlist missing
allowlist_match <line>                 # internal, exposed for the fixture self-test
```

Scanned shape is design decision 2: only `<path>:<line>:<col>: warning: …`.
No xcodebuild meta-warnings, no location-less diagnostics.

**Two deliberate deviations from `structure.md`, both correctness fixes** (see
"Deviations" at the end): `run_xcodebuild` truncates its log (structure said
`tee -a`, which makes the Phase 1 red→green rerun impossible), and the Phase 1
red-first injection targets `SingleThreadTests/` rather than `SingleThread/`
(the inherited target turns the injected warning into a *build error*, so the
scan is never reached).

---

## Phase 1: Walking skeleton — one real build, scanned, gate goes red

A deliberately introduced warning in `SingleThreadTests` makes the wrapped first
build step fail the gate with the offender printed; a clean tree passes. Proves
the whole path (live tee → log → anchored scan → allowlist → exit 1) and
captures the first real warning inventory.

### Changes

#### 1. `scripts/check-warnings.sh` (new, executable)

**Action**: create. Full contents:

```bash
#!/usr/bin/env bash
# Compiler-warning backstop for the CI-identical gate.
#
# xcodebuild streams diagnostics to stdout/stderr and nothing else in this repo
# captures or parses them. This helper tees each build to a log, then scans the
# log for source-located warnings and fails on any not matched by the allowlist.
#
# Sourced by scripts/test.sh; also runnable standalone:
#   bash scripts/check-warnings.sh <log> [<log>...]
#
# Contract (frozen):
#   WARNING_PATTERN  ERE matching one source-located compiler warning
#   ALLOWLIST        repo-root-relative allowlist path (override via env)
#   run_xcodebuild <log> <cmd> [args...]
#   check_warnings <log> [<log>...]
#   allowlist_match <line>
#
# Scanned shape: <path>:<line>:<col>: warning: <message> only. xcodebuild
# meta-warnings ("Run script build phase ... will be run during every build")
# and location-less diagnostics are deliberately not matched.

WARNING_PATTERN='^[^:]+:[0-9]+:[0-9]+: warning: '
ALLOWLIST="${ALLOWLIST:-scripts/xcodebuild-warnings.allow}"

# Print one offender. Plain by default; GitHub Actions annotation under Actions.
print_offender() {
    echo "    $1"
}

# 0 when <line> matches any non-comment allowlist pattern, 1 otherwise.
allowlist_match() {
    [[ -f "$ALLOWLIST" ]] || return 1
    local line="$1" pattern
    while IFS= read -r pattern; do
        [[ -z "${pattern//[[:space:]]/}" ]] && continue
        [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ $pattern ]] && return 0
    done < "$ALLOWLIST"
    return 1
}

# Scan one or more logs; return 1 when any offender is not allowlisted.
check_warnings() {
    if [[ ! -f "$ALLOWLIST" ]]; then
        echo "❌ warning allowlist not found: $ALLOWLIST (fail closed)" >&2
        return 1
    fi
    local log line offenders=0
    for log in "$@"; do
        [[ -f "$log" ]] || continue
        while IFS= read -r line; do
            allowlist_match "$line" && continue
            offenders=$((offenders + 1))
            print_offender "$line"
        done < <(grep -E "$WARNING_PATTERN" "$log" || true)
    done
    if [[ "$offenders" -gt 0 ]]; then
        echo "❌ $offenders compiler warning(s) not allowlisted (see $ALLOWLIST)" >&2
        return 1
    fi
    echo "    ✓ no un-allowlisted compiler warnings"
    return 0
}

# Run a build command, tee it to <log>, preserve its exit status, scan only on
# success. The `|| status=${PIPESTATUS[0]}` idiom keeps `tee` from masking a
# build failure and keeps `set -e` from aborting before the scan.
run_xcodebuild() {
    local log="$1"; shift
    mkdir -p "$(dirname "$log")"
    : > "$log"
    local status=0
    "$@" 2>&1 | tee -a "$log" || status=${PIPESTATUS[0]}
    if [[ "$status" -ne 0 ]]; then
        echo "❌ build failed (exit $status); log: $log" >&2
        return "$status"
    fi
    check_warnings "$log"
}

# Standalone entry point (no-op when sourced by scripts/test.sh).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    if [[ "$#" -eq 0 ]]; then
        echo "Usage: $0 <log> [<log>...]" >&2
        exit 2
    fi
    check_warnings "$@"
fi
```

Notes:
- `set -euo pipefail` lives **inside** the executable guard so sourcing never
  mutates `test.sh`'s shell options.
- An invalid ERE in the allowlist makes `[[ =~ ]]` return 2 → no match → the
  line becomes an offender → the gate fails loudly. Fail-closed, no guard needed.
- `ALLOWLIST=/dev/null` is a valid way to disable allowlisting during inventory
  capture (`-f /dev/null` is true and it has no patterns).

#### 2. `scripts/xcodebuild-warnings.allow` (new)

**Action**: create.

```
# Compiler-warning allowlist for scripts/check-warnings.sh.
#
# One extended-regexp per line; blank lines and lines starting with '#' are
# ignored. A diagnostic line from an xcodebuild log is allowed when it matches
# ANY pattern here. Everything else fails the gate.
#
# Keep entries narrow and append a one-line rationale. Only diagnostics that
# genuinely cannot be fixed in this repo belong here -- never use this file to
# silence a warning we could fix at the source.

# StoreKitTest's SDK headers reference a symbol deprecated in iOS 18. The header
# is toolchain-owned, so the diagnostic cannot be fixed in this repo. This is the
# same diagnostic behind the SingleThreadTests warnings-as-errors carve-out
# (SingleThread.xcodeproj/project.pbxproj:856/885); the log scan sees it because
# `build-for-testing` compiles SingleThreadTests on the iOS destination too.
# Reconciled against the real diagnostic text in Phase 3.
.*StoreKitTest\.framework/Headers/.*: warning: .*
```

#### 3. `scripts/test.sh` (modify)

**Action**: modify.

**3a — source the helper before the `cd`** (top of file, right after line 2's
`set -euo pipefail`). `cd "$(dirname "$0")/.."` happens at current line 46, and
`$(dirname "$0")` is not stable after it, so resolve the directory first:

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/check-warnings.sh"
```

**3b — define the log directory** after the `cd "$(dirname "$0")/.."` line
(currently line 46), before the SIM resolution block:

```bash
cd "$(dirname "$0")/.."

LOG_DIR="$DERIVED_DATA/logs"
```

(`$DERIVED_DATA` is `DerivedData`, set at current line 24; `DerivedData/` is
already gitignored, so `DerivedData/logs/` needs no `.gitignore` change.)

**3c — wire the iOS `build-for-testing` step** (current `test.sh:252-256`):

```bash
    echo ""
    echo "==> Building…"
    run_xcodebuild "$LOG_DIR/ios-build.log" xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing
```

**3d — add the fail-fast self-test step** after the SwiftLint step
(current `test.sh:248-249`) and before `echo "==> Building…"`:

```bash
    echo ""
    echo "==> Warning-check self-test…"
    bash "$SCRIPT_DIR/tests/warning-check/run.sh"
```

#### 4. `scripts/tests/warning-check/run.sh` (new)

**Action**: create. Self-test; asserts exit codes for every checker behaviour.
Uses a `pass`/`fail` counter and exits 1 if any case failed.

```bash
#!/usr/bin/env bash
# Fixture self-test for scripts/check-warnings.sh.
#
# A pattern-matching gate check fails OPEN when its regex drifts: every fixture
# below would "pass" if the pattern stopped matching. These cases are the
# regression guard for that.
set -euo pipefail
cd "$(dirname "$0")/../../.."

CHECKER="$PWD/scripts/check-warnings.sh"
FIXTURES="$PWD/scripts/tests/warning-check/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
expect_exit() { # <expected> <actual> <label>
    if [[ "$1" -eq "$2" ]]; then
        echo "    ✓ $3"
        pass=$((pass + 1))
    else
        echo "    ✗ $3 (expected exit $1, got $2)"
        fail=$((fail + 1))
    fi
}

# Exercise the function API directly.
source "$CHECKER"
ALLOWLIST="$FIXTURES/allow"

echo "==> warning-check fixtures"

# 1) clean log passes
status=0; check_warnings "$FIXTURES/clean.log" >/dev/null || status=$?
expect_exit 0 "$status" "clean log passes"

# 2) one warning fails
status=0; check_warnings "$FIXTURES/one-warning.log" >/dev/null || status=$?
expect_exit 1 "$status" "one warning fails"

# 3) allowlisted-only log passes
status=0; check_warnings "$FIXTURES/allowlisted-only.log" >/dev/null || status=$?
expect_exit 0 "$status" "allowlisted-only log passes"

# 4) mixed log fails and prints ONLY the non-allowlisted offender
out=""; status=0
out="$(check_warnings "$FIXTURES/mixed.log" 2>&1)" || status=$?
expect_exit 1 "$status" "mixed log fails"
if [[ "$out" == *"Bar.swift:7:5"* && "$out" != *"SKTestSession.h"* ]]; then
    echo "    ✓ mixed log prints only non-allowlisted offenders"
    pass=$((pass + 1))
else
    echo "    ✗ mixed log offender filtering wrong"
    fail=$((fail + 1))
fi

# 5) near-miss log passes (meta-warning + ': warning:' inside test prose)
status=0; check_warnings "$FIXTURES/near-miss.log" >/dev/null || status=$?
expect_exit 0 "$status" "near-miss log passes"

# 6) missing allowlist fails closed
status=0; ALLOWLIST="$TMP/does-not-exist" check_warnings "$FIXTURES/clean.log" >/dev/null || status=$?
expect_exit 1 "$status" "missing allowlist fails closed"
ALLOWLIST="$FIXTURES/allow"

# 7) run_xcodebuild preserves a failing command's exit status
status=0
run_xcodebuild "$TMP/fail.log" "$FIXTURES/fake-fail.sh" >/dev/null 2>&1 || status=$?
expect_exit 7 "$status" "run_xcodebuild preserves exit 7"

# 8) run_xcodebuild scans on success (clean command passes)
status=0
run_xcodebuild "$TMP/clean.log" "$FIXTURES/fake-clean.sh" >/dev/null 2>&1 || status=$?
expect_exit 0 "$status" "run_xcodebuild scans clean command"

# 9) run_xcodebuild fails on a command that emits a warning
status=0
run_xcodebuild "$TMP/warn.log" "$FIXTURES/fake-warning.sh" >/dev/null 2>&1 || status=$?
expect_exit 1 "$status" "run_xcodebuild fails on emitted warning"

# 10) run_xcodebuild truncates a stale log (rerun is green)
status=0
run_xcodebuild "$TMP/warn.log" "$FIXTURES/fake-clean.sh" >/dev/null 2>&1 || status=$?
expect_exit 0 "$status" "run_xcodebuild truncates stale log"

# 11) standalone entry point: red on warning, green on clean
status=0; ALLOWLIST="$FIXTURES/allow" bash "$CHECKER" "$FIXTURES/one-warning.log" >/dev/null || status=$?
expect_exit 1 "$status" "standalone entry point fails on warning"
status=0; ALLOWLIST="$FIXTURES/allow" bash "$CHECKER" "$FIXTURES/clean.log" >/dev/null || status=$?
expect_exit 0 "$status" "standalone entry point passes clean"

echo ""
if [[ "$fail" -gt 0 ]]; then
    echo "❌ warning-check: $fail fixture(s) failed"
    exit 1
fi
echo "✅ warning-check: $pass fixture(s) passed"
```

Note: `ALLOWLIST` is a plain global assignment around the function calls — not
a `VAR=val func` prefix — because bash's semantics for assignments preceding a
function call are not portable.

#### 5. `scripts/tests/warning-check/fixtures/` (new, 8 files)

**Action**: create.

`fixtures/allow`:
```
# Fixture allowlist (self-test only). Mirrors scripts/xcodebuild-warnings.allow:
# one ERE per line, '#' comments allowed.
.*StoreKitTest\.framework/Headers/.*: warning: .*
```

`fixtures/clean.log`:
```
CompileSwift normal arm64 /Users/x/dev/SingleThread/Foo.swift
Ld /Users/x/dev/DerivedData/Build/Products/Debug/SingleThread.app/Contents/MacOS/SingleThread
** BUILD SUCCEEDED **
```

`fixtures/one-warning.log`:
```
CompileSwift normal arm64 /Users/x/dev/SingleThread/Foo.swift
/Users/x/dev/SingleThread/Foo.swift:42:9: warning: variable 'unusedThing' was never used; consider replacing with '_'
** BUILD SUCCEEDED **
```

`fixtures/allowlisted-only.log`:
```
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/StoreKitTest.framework/Headers/SKTestSession.h:118:1: warning: 'SKTestSession' is deprecated: first deprecated in iOS 18.0
** BUILD SUCCEEDED **
```

`fixtures/mixed.log`:
```
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/StoreKitTest.framework/Headers/SKTestSession.h:118:1: warning: 'SKTestSession' is deprecated: first deprecated in iOS 18.0
/Users/x/dev/SingleThread/Bar.swift:7:5: warning: initialization of immutable value 'y' was never used; consider replacing with '_' assignment
** BUILD SUCCEEDED **
```

`fixtures/near-miss.log` (deliberately no line-anchored source diagnostic):
```
warning: Run script build phase 'Embed lib' will be run during every build because it does not specify any outputs. To address this warning, either add output dependencies to the script phase, or configure it to run in every build by unchecking "Based on dependency analysis".
    note: saw foo.swift:1:1: warning: deprecated API inside test output prose
Test Suite 'Selected tests' started at 2026-01-01 00:00:00.000
Test Case '-[SingleThreadUITests testLaunch]' passed (0.123 seconds)
** BUILD SUCCEEDED **
```

`fixtures/fake-fail.sh`:
```bash
#!/usr/bin/env bash
echo "CompileSwift normal arm64 /Users/x/dev/SingleThread/Foo.swift"
echo "fake build failed" >&2
exit 7
```

`fixtures/fake-clean.sh`:
```bash
#!/usr/bin/env bash
echo "** BUILD SUCCEEDED **"
exit 0
```

`fixtures/fake-warning.sh`:
```bash
#!/usr/bin/env bash
echo "/Users/x/dev/SingleThread/Foo.swift:42:9: warning: variable 'unusedThing' was never used"
exit 0
```

Then `chmod +x scripts/check-warnings.sh scripts/tests/warning-check/run.sh scripts/tests/warning-check/fixtures/fake-*.sh`.

### Verification

#### Automated
- [x] `bash scripts/tests/warning-check/run.sh` → exits 0, prints `✅ warning-check: 13 fixture(s) passed` (11 numbered cases + 2 extra assertions).
- [x] `bash -n scripts/check-warnings.sh` → no syntax errors.
- [x] `make lint` → SwiftFormat/SwiftLint unaffected (no Swift changed).

#### Manual
- [ ] Red-first (scan path): add `let warningsProbe = FileManager.default` (unused) to a
      file in `SingleThreadTests/`, then run a wrapped iOS build from a scratch
      script (`/tmp/red.sh`, run with `bash /tmp/red.sh`):

      ```bash
      #!/usr/bin/env bash
      set -euo pipefail
      cd /Users/vardy/dev/alanvardy-var-1048-add-no-warnings-check
      source scripts/check-warnings.sh
      SIM="platform=iOS Simulator,id=$(tr -d '[:space:]' < .simulator_id)"
      run_xcodebuild DerivedData/logs/ios-build.log xcodebuild -scheme SingleThread \
        -destination "$SIM" -configuration Debug -derivedDataPath DerivedData build-for-testing
      ```

      Expect exit 1 with `.../warningsProbe...` offender line printed and
      `❌ 1 compiler warning(s) not allowlisted`. Revert the edit and rerun:
      expect exit 0 and `✓ no un-allowlisted compiler warnings` (proves the log
      truncation, since `DerivedData/logs/ios-build.log` already held the warning).
- [ ] Compiler-lever check (documents that the two levers are separate): add
      `let warningsProbe = FileManager.default` (unused) to a file in
      `SingleThread/`, run the same wrapped build → exit 1 from the **build**
      (`error: variable 'warningsProbe' was never used`), no offender line.
      Revert.
- [ ] Confirm `git status --porcelain` shows only the intended new/modified files
      (`DerivedData/` is ignored).
- [ ] Capture the real warning inventory (design's Open Risk spike) and write it
      to `(<artifact_directory>)inventory-phase1.md`. From the repo root:

      ```bash
      #!/usr/bin/env bash
      # /tmp/inventory.sh
      set -uo pipefail
      cd /Users/vardy/dev/alanvardy-var-1048-add-no-warnings-check
      mkdir -p DerivedData/logs
      source scripts/check-warnings.sh
      ALLOWLIST=/dev/null
      check_warnings DerivedData/logs/ios-build.log 2>&1 | grep -E 'warning: ' | sort -u | tee /tmp/warnings-ios.txt
      ```

      (Run the iOS build first, as above.) Record every distinct `warning:` line:
      this is Phase 3's input. If the iOS build already contains the StoreKitTest
      diagnostic, confirm the allowlist regex in `scripts/xcodebuild-warnings.allow`
      matches it; if the text differs, correct the entry now.

---

## Phase 2: Full local gate coverage — every step, all three modes

Any warning emitted by any build the local gate runs now fails it — `make check`,
`make test` and `make ui-test` alike.

### Changes

#### 1. `scripts/test.sh` — route the remaining nine call sites

**Action**: modify. Replace each bare `xcodebuild …` with
`run_xcodebuild "<log>" xcodebuild …`, keeping every existing flag and
continuation. Exact sites (current line numbers) and log names:

| Step | Current lines | New log |
|---|---|---|
| watch build | 282-286 | `$LOG_DIR/watch-build.log` |
| iOS UI `test-without-building` | 294-298 | `$LOG_DIR/ios-ui-test.log` |
| watch `build-for-testing` | 302-307 | `$LOG_DIR/watch-build-for-testing.log` |
| watch UI `test-without-building` | 324-329 | `$LOG_DIR/watch-ui-test.log` |
| watch unit `test-without-building` | 332-336 | `$LOG_DIR/watch-unit-test.log` |
| macOS unit `test` (full) | 340-347 | `$LOG_DIR/mac-unit-test.log` |
| macOS unit `test` (unit-only) | 355-360 | `$LOG_DIR/mac-unit-only.log` |
| iOS UI `build-for-testing` (ui-only) | 369-373 | `$LOG_DIR/ios-ui-build.log` |
| iOS UI `test-without-building` (ui-only) | 378-382 | `$LOG_DIR/ios-ui-test-only.log` |

Example (watch build):

```bash
    echo ""
    echo "==> Watch build…"
    run_xcodebuild "$LOG_DIR/watch-build.log" xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build
```

Example (macOS unit, full mode — note `CODE_SIGNING_ALLOWED=NO` is an argument
to `xcodebuild`, so it stays inside the wrapped command):

```bash
    run_xcodebuild "$LOG_DIR/mac-unit-test.log" xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadTests
```

The two `test-without-building` watch steps (324-336) and the watch
`build-for-testing` step share the same `$DERIVED_DATA`; each gets its own log
file. The `_watch_runner` `lib_TestingInterop.dylib` copy between
`build-for-testing` and `test-without-building` is untouched.

#### 2. `scripts/test.sh` — clear stale logs at gate start

**Action**: modify. Immediately after `LOG_DIR="$DERIVED_DATA/logs"` (added in
Phase 1):

```bash
LOG_DIR="$DERIVED_DATA/logs"
rm -rf "$LOG_DIR"
```

(Each `run_xcodebuild` already truncates its own log; this removes logs from
steps that no longer run, e.g. after switching modes.)

#### 3. `scripts/test.sh` — structural guard against bare `xcodebuild`

**Action**: modify. Add next to `verify_deployment_target()` (house style), and
call it right after the existing `verify_deployment_target` call (current line
`test.sh:225`):

```bash
# Every xcodebuild invocation must go through run_xcodebuild so its output is
# scanned for compiler warnings. A bare call is a silent hole in the gate.
verify_xcodebuild_wrapped() {
    local script="$SCRIPT_DIR/test.sh"
    local bare
    bare="$(grep -cE '^[[:space:]]*xcodebuild' "$script" || true)"
    echo "==> Verifying every xcodebuild is wrapped"
    if [[ "$bare" -ne 0 ]]; then
        echo "    ✗ $bare bare xcodebuild invocation(s) in $script"
        echo "      Route them through run_xcodebuild <log> xcodebuild …"
        exit 1
    fi
    printf "    ✓ no bare xcodebuild invocations\n"
}
```

```bash
verify_deployment_target
verify_xcodebuild_wrapped
```

#### 4. `scripts/tests/warning-check/run.sh` — multi-log case

**Action**: modify. Insert after case 5 (before the missing-allowlist case):

```bash
# 5b) multiple logs aggregate; any offender fails
status=0; check_warnings "$FIXTURES/clean.log" "$FIXTURES/one-warning.log" >/dev/null || status=$?
expect_exit 1 "$status" "multi-log aggregation fails"
```

Update the closing `✅ warning-check: N fixture(s) passed` count in the summary
(no code change needed — it prints `$pass`).

### Verification

#### Automated
- [x] `bash scripts/tests/warning-check/run.sh` → exits 0, includes
      `✓ multi-log aggregation fails`.
- [x] `bash -n scripts/test.sh` → no syntax errors.
- [x] `grep -cE '^[[:space:]]*xcodebuild' scripts/test.sh` → `0`.
- [x] `bash -c 'source scripts/check-warnings.sh; ALLOWLIST=scripts/xcodebuild-warnings.allow; check_warnings DerivedData/logs/ios-build.log DerivedData/logs/watch-build.log'`
      → exits 0 on a clean tree (reuses the `ios-build.log` and `watch-build.log`
      produced by the Phase 3 capture).

#### Manual
- [ ] Run the wrapped watch build through `run_xcodebuild` (same `/tmp/red.sh`
      pattern) and confirm `DerivedData/logs/watch-build.log` is created and the
      command exits 0.
- [ ] Run `make test` (unit-only mode) on a clean tree → exits 0 and creates
      `DerivedData/logs/mac-unit-only.log`.
- [ ] Run `make ui-test` (ui-only mode) on a clean tree → exits 0 and creates
      `DerivedData/logs/ios-ui-build.log` + `ios-ui-test-only.log`.
- [ ] Confirm `DerivedData/logs/` has no phantom failure after a rerun
      (`rm -rf` + per-run truncation).
- [ ] Do **not** run the full `make check` here — it is the post-phase gate
      (`run-gate` skill, async, managed worktree).

---

## Phase 3: Warning-free tree — remediation + allowlist

The gate is green on a clean tree: every warning surfaced in Phases 1–2 is
either fixed in source/config or allowlisted with a one-line rationale.

### Changes

#### 1. Inventory capture (no repo file)

**Action**: run the capture script, then act on its output. It runs the three
warning-producing build shapes without `set -e` so all three complete, then
prints the deduped union of source-located warnings.

```bash
#!/usr/bin/env bash
# /tmp/capture-warnings.sh — Phase 3 inventory capture (run with bash)
set -uo pipefail
cd /Users/vardy/dev/alanvardy-var-1048-add-no-warnings-check
mkdir -p DerivedData/logs
SIM="platform=iOS Simulator,id=$(tr -d '[:space:]' < .simulator_id)"
FMT='^[^:]+:[0-9]+:[0-9]+: warning: '

xcodebuild -scheme SingleThread -destination "$SIM" -configuration Debug \
  -derivedDataPath DerivedData build-for-testing \
  2>&1 | tee DerivedData/logs/ios-build.log >/dev/null

xcodebuild -scheme SingleThreadWatch -destination "generic/platform=watchOS Simulator" \
  -configuration Debug -derivedDataPath DerivedData build \
  2>&1 | tee DerivedData/logs/watch-build.log >/dev/null

xcodebuild -scheme SingleThread -destination "platform=macOS" -configuration Debug \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO \
  test -only-testing:SingleThreadTests \
  2>&1 | tee DerivedData/logs/mac-unit-test.log >/dev/null

echo "=== distinct warning messages ==="
grep -hE "$FMT" DerivedData/logs/*.log \
  | sed -E 's/^[^:]+:[0-9]+:[0-9]+: warning: //' | sort | uniq -c | sort -rn
```

- The iOS `build-for-testing` step also compiles `SingleThreadTests` (scheme has
  no `-only-testing` filter) and the `SingleThreadWidget` target (app-target
  dependency, `pbxproj:472`), so it covers both those design-listed surfaces.
- Record the raw union to `(<artifact_directory>)inventory-phase3.md` before
  fixing anything.

#### 2. Source fixes

**Action**: modify whichever of `SingleThread/`, `SingleThreadWatch/`,
`SingleThreadWidget/`, `SingleThreadCore/Sources/SingleThreadCore/`,
`SingleThreadTests/` the inventory names. Decision rule per distinct message:

1. Can the diagnostic be removed by a source change (delete an unused binding,
   migrate off a deprecated API, fix a Swift 6 concurrency diagnostic)? → **fix
   it in source**. No fabricated snippets here: the fix is dictated by the
   captured message and must be the minimal edit that removes it.
2. Only genuinely unfixable, toolchain- or SDK-owned diagnostics → allowlist.

Hard constraints (design "What We're NOT Doing"):
- No pbxproj flag changes; `SingleThreadTests` stays `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` (`project.pbxproj:856,885`).
- No `-suppress-warnings` / `-Wno-*` / `.unsafeFlags` in `SingleThreadCore/Package.swift`.
- No CLI `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` override.
- No new `make` target, no new test target.

#### 3. `scripts/xcodebuild-warnings.allow`

**Action**: modify. For each allowlisted message add one ERE line, narrow and
anchored on the message text, directly under the `#` rationale comment:

```
# <why this diagnostic cannot be fixed in this repo (file/SDK, what it is)>
.*<message substring>.*
```

Reconcile the StoreKitTest entry created in Phase 1 with the actual message text
from `inventory-phase3.md` (any line matching the pattern means the entry is
load-bearing).

Split rule (from `structure.md`): if the inventory exceeds ~10 distinct items,
or a single fix touches package/SPM configuration, split this phase in two along
the same boundary (fix half → re-run Phase 2 verification → fix half) and record
the split.

### Verification

#### Automated
- [x] `bash scripts/tests/warning-check/run.sh` → exits 0.
- [x] `bash -c 'source scripts/check-warnings.sh; check_warnings DerivedData/logs/ios-build.log DerivedData/logs/watch-build.log DerivedData/logs/mac-unit-test.log'`
      → exits 0, prints `✓ no un-allowlisted compiler warnings`.
- [x] Red-first proof per allowlist entry: temporarily comment the entry out,
      re-run `check_warnings` on the log known to contain it → exits 1 naming
      exactly that diagnostic; restore the entry → exits 0.

#### Manual
- [ ] `make build` and `make watch-build` both succeed on the clean tree.
- [ ] Start a second `capture-warnings.sh` run and confirm the
      `distinct warning messages` list is empty (or fully matched by the
      allowlist — verify with `ALLOWLIST=/dev/null` showing only allowlisted lines).
- [ ] Full `make check` via the `run-gate` skill (async gate subagent, managed
      worktree, multi-hour timeout) is the authoritative green checkpoint; use a
      clean `DerivedData/` for the Periphery stale-index note. Do not run
      `./scripts/test.sh` ad-hoc with `nohup`.

---

## Phase 4: CI parity, diagnostics and docs

CI's own build steps enforce the same check with the same allowlist, and a
developer hitting a red gate sees exactly what failed.

### Changes

#### 1. `scripts/check-warnings.sh` — offender annotation output

**Action**: modify. Replace the Phase 1 `print_offender` body:

```bash
# Print one offender. Under GitHub Actions, emit an annotation so the warning
# appears on the PR diff; otherwise print a plain indented line.
print_offender() {
    local line="$1"
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        local file rest lnum msg
        file="${line%%:*}"
        rest="${line#*:}"
        lnum="${rest%%:*}"
        msg="${line#*: warning: }"
        echo "::warning file=$file,line=$lnum::$msg"
    else
        echo "    $line"
    fi
}
```

(`check_warnings` already prints the total offender count and the fail-closed
allowlist message.)

#### 2. `.github/workflows/ci.yml` — wrap the five build steps

**Action**: modify. Each build step gets the same shape: `mkdir -p`, `set +e`
around the `tee` pipeline, restore the captured status, then invoke the helper
standalone. The `set +e` / `[[ … ]] || exit` pair is required because Actions
runs `run:` with `bash -e`, so a bare `exit ${PIPESTATUS[0]}` would terminate
the step before the scan and a bare failing pipeline would abort it.

Shared preamble for every step (log path is literal; `DerivedData/` is
gitignored, and cwd is the workspace root):

```yaml
        run: |
          mkdir -p DerivedData/ci-logs
          set +e
          xcodebuild … 2>&1 | tee DerivedData/ci-logs/<name>.log
          status=${PIPESTATUS[0]}
          set -e
          [[ "$status" -eq 0 ]] || exit "$status"
          bash scripts/check-warnings.sh DerivedData/ci-logs/<name>.log
```

Steps and log names:

- `unit-tests` → `Build` (`ci.yml:52-58`) → `DerivedData/ci-logs/ios-unit-build.log`
- `ui-tests-smoke` → `Build` (`ci.yml:121-127`) → `DerivedData/ci-logs/ios-ui-build.log`
- `mac-tests` → `Build (macOS)` (`ci.yml:173-179`) → `DerivedData/ci-logs/mac-build.log`
- `lint` → `Watch build` (`ci.yml:237-241`) → `DerivedData/ci-logs/watch-build.log`
  (do **not** add `-derivedDataPath` here — that would change the build
  directory the following Periphery step at `ci.yml:245` relies on)
- `watch-ui-tests` → `Build watch app + tests` (`ci.yml:290-297`) →
  `DerivedData/ci-logs/watch-build-for-testing.log`

Example — `unit-tests` Build step, fully written out:

```yaml
      - name: Build
        timeout-minutes: 20
        run: |
          mkdir -p DerivedData/ci-logs
          set +e
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadTests \
            -showBuildTimingSummary 2>&1 | tee DerivedData/ci-logs/ios-unit-build.log
          status=${PIPESTATUS[0]}
          set -e
          [[ "$status" -eq 0 ]] || exit "$status"
          bash scripts/check-warnings.sh DerivedData/ci-logs/ios-unit-build.log
```

The test steps (`test-without-building`, `test`) are **not** wrapped: they emit
no compile diagnostics, and the design scopes the check to build steps.

#### 3. `.github/workflows/ci.yml` — self-test step in the `lint` job

**Action**: modify. Add after the `SwiftLint` step (`ci.yml:232`):

```yaml
      - name: Warning-check self-test
        timeout-minutes: 2
        run: bash scripts/tests/warning-check/run.sh
```

#### 4. `AGENTS.md` — document the check

**Action**: modify. Under `## Before Committing`, after the
"Run `make format` then `make lint`…" bullet, add:

```markdown
- The gate fails on any source-located compiler warning
  (`<path>:<line>:<col>: warning:`) in any build it runs. Unfixable
  toolchain/SDK diagnostics belong in `scripts/xcodebuild-warnings.allow` with a
  one-line rationale; never silence warnings via `Package.swift` flags or CLI
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` overrides. The checker's own fixtures live in
  `scripts/tests/warning-check/` and run early in `scripts/test.sh`.
```

#### 5. `scripts/tests/warning-check/run.sh` — annotation + cwd cases

**Action**: modify. Insert before the summary block:

```bash
# 12) GitHub Actions annotation output shape
GITHUB_ACTIONS=true
out="$(check_warnings "$FIXTURES/one-warning.log" 2>&1)" || true
unset GITHUB_ACTIONS
if [[ "$out" == *"::warning file=/Users/x/dev/SingleThread/Foo.swift,line=42::"* ]]; then
    echo "    ✓ annotation output shape"
    pass=$((pass + 1))
else
    echo "    ✗ annotation output shape wrong"
    fail=$((fail + 1))
fi

# 13) standalone entry point resolves an absolute allowlist from any cwd
mkdir -p "$TMP/other"
status=0
( cd "$TMP/other" && ALLOWLIST="$FIXTURES/allow" bash "$CHECKER" "$FIXTURES/clean.log" >/dev/null ) || status=$?
expect_exit 0 "$status" "absolute allowlist works from a non-repo cwd"

# 14) the default (repo-root-relative) allowlist fails closed outside the repo
status=0
( cd "$TMP/other" && bash "$CHECKER" "$FIXTURES/clean.log" >/dev/null 2>&1 ) || status=$?
expect_exit 1 "$status" "default allowlist fails closed outside the repo"
```

### Verification

#### Automated
- [x] `bash scripts/tests/warning-check/run.sh` → exits 0, includes
      `✓ annotation output shape`, `✓ absolute allowlist works from a non-repo cwd`,
      `✓ default allowlist fails closed outside the repo`.
- [x] `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "yaml ok"'`
      → `yaml ok` (Actions YAML parses).
- [x] `grep -c 'check-warnings.sh' .github/workflows/ci.yml` → `5`.
- [x] `grep -c 'DerivedData/ci-logs' .github/workflows/ci.yml` → `5`
      (actual `15` = 3 per build step — `mkdir -p` + `tee` + check arg — over the
      5 wrapped steps; all five steps wrapped as intended).
- [x] Every wrapped CI build step greps as tee + helper:
      `grep -n -A2 'tee DerivedData/ci-logs' .github/workflows/ci.yml` shows the
      `status=${PIPESTATUS[0]}` / `bash scripts/check-warnings.sh` pair after each.
- [x] `make lint` → unchanged (no Swift touched; `AGENTS.md`/YAML/sh not linted).

#### Manual
- [ ] Local dry run of the exact CI line against a captured log: inject a
      warning into `SingleThreadTests/`, run `/tmp/capture-warnings.sh` to
      produce `DerivedData/logs/ios-build.log`, then
      `bash scripts/check-warnings.sh DerivedData/logs/ios-build.log` → exits 1
      and prints the offender; revert → exits 0.
- [ ] `GITHUB_ACTIONS=true bash scripts/check-warnings.sh DerivedData/logs/ios-build.log`
      (with the injected warning) prints `::warning file=…,line=…::…`.
- [ ] Confirm no new `DerivedData/ci-logs` files are tracked
      (`git status --porcelain` clean apart from intended edits).
- [ ] CI itself is authoritative and cannot run locally: confirm all jobs green
      on the PR (`gh pr checks`). If a CI-only warning appears (CI builds
      `SingleThreadTests` on iOS sims and uses Xcode 26.6 vs local 27.0), fix or
      allowlist it in a follow-up commit on the same branch.

---

## Testing Checkpoints

| After | Must be green before advancing |
|---|---|
| Phase 1 | `bash scripts/tests/warning-check/run.sh`; wrapped iOS build red on a `SingleThreadTests` warning, green after revert; injected `SingleThread/` warning red via build error; inventory recorded |
| Phase 2 | fixture self-test incl. multi-log case; `grep -cE '^[[:space:]]*xcodebuild' scripts/test.sh` == 0; watch build + mac-unit-only + ui-only produce logs and scan clean |
| Phase 3 | fixture self-test; all captured logs have zero non-allowlisted offenders; each allowlist entry red-first proven; full `make check` (run-gate skill) green on a clean tree |
| Phase 4 | fixture self-test incl. annotation/non-repo-cwd cases; YAML parses; CI build steps wrapped; local dry run of the CI line red on an injected warning; PR CI green |

**Not in this ticket** (design "What We're NOT Doing"): flipping
`SingleThreadTests` to `YES`, `Package.swift` flags, CI calling `test.sh`
wholesale, `xcresulttool`-based extraction, new `make`/test targets, the
pre-existing macOS `EntitlementStoreTests` failures.

---

## Deviations from `structure.md`

1. **`run_xcodebuild` truncates its log** (`: > "$log"` before the `tee -a`
   pipeline) instead of relying on `tee -a` alone. Without this, the Phase 1
   red→green rerun appends the still-present warning line to the same log and
   the reverted tree still fails. Phase 2's `rm -rf "$LOG_DIR"` stays as
   cross-mode hygiene.
2. **Phase 1 red-first injection targets `SingleThreadTests/`, not
   `SingleThread/`.** With `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` inherited,
   a warning in the app target is promoted to an *error*, so the build fails
   before the scan and the scan is never exercised. Both cases are tested: the
   app-target injection proves the compiler lever, the `SingleThreadTests`
   injection proves the log scan.
3. **Zero-argument `check-warnings.sh` exits 2** (usage) rather than scanning
   nothing. Scanning zero logs and returning 0 is a silent fail-open; the
   structure text ("called with no args it scans `$1`") reads as a typo.
4. **CI uses `set +e` / `status=${PIPESTATUS[0]}` / `[[ … ]] || exit`** around
   the `tee` pipeline rather than a literal `exit ${PIPESTATUS[0]}` line before
   the helper call. Under Actions' `bash -e`, a bare `exit` would terminate the
   step before the scan, defeating the check. Log paths are literal
   (`DerivedData/ci-logs/…`) rather than `$DERIVED_DATA`-prefixed because two of
   the five jobs (lint, watch-ui-tests' lint sibling) do not export
   `DERIVED_DATA`; cwd is always the workspace root.
5. **A permanent `verify_xcodebuild_wrapped()` guard** is added to
   `scripts/test.sh` (structure listed the `grep` only as a Phase 2 verification
   command). It is cheap, matches the house `verify_deployment_target()` style,
   and prevents a future bare `xcodebuild` from silently reopening the hole.
6. **The fixture self-test is wired into `test.sh` in Phase 1** (design decision
   7 wants it early in the gate) and into CI's `lint` job in Phase 4; the
   structure phases mention the runner but not those two wiring points.
