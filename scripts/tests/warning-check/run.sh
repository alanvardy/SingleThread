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
if [[ "$out" == *"Bar.swift:7:5"* && "$out" != *"SKTestTransaction.h"* ]]; then
    echo "    ✓ mixed log prints only non-allowlisted offenders"
    pass=$((pass + 1))
else
    echo "    ✗ mixed log offender filtering wrong"
    fail=$((fail + 1))
fi

# 5) near-miss log passes (meta-warning + ': warning:' inside test prose)
status=0; check_warnings "$FIXTURES/near-miss.log" >/dev/null || status=$?
expect_exit 0 "$status" "near-miss log passes"

# 5b) multiple logs aggregate; any offender fails
status=0; check_warnings "$FIXTURES/clean.log" "$FIXTURES/one-warning.log" >/dev/null || status=$?
expect_exit 1 "$status" "multi-log aggregation fails"

# 6) missing allowlist fails closed
status=0; ALLOWLIST="$TMP/does-not-exist" check_warnings "$FIXTURES/clean.log" >/dev/null || status=$?
expect_exit 1 "$status" "missing allowlist fails closed"
ALLOWLIST="$FIXTURES/allow"

# 6b) missing log fails closed (a typo'd path must not scan nothing silently)
status=0; check_warnings "$TMP/does-not-exist.log" >/dev/null || status=$?
expect_exit 1 "$status" "missing log fails closed"

# 7) run_xcodebuild preserves a failing command's exit status
status=0
run_xcodebuild "$TMP/fail.log" "$FIXTURES/fake-fail.sh" >/dev/null 2>&1 || status=$?
expect_exit 7 "$status" "run_xcodebuild preserves exit 7"

# 7b) ...even when the caller has NOT enabled pipefail (tee must not mask it)
status=0
set +o pipefail
run_xcodebuild "$TMP/fail-nopf.log" "$FIXTURES/fake-fail.sh" >/dev/null 2>&1 || status=$?
set -o pipefail
expect_exit 7 "$status" "run_xcodebuild preserves exit 7 without caller pipefail"

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

# 15) the allowlist is pinned to the exact header/line: an off-line diagnostic
# from the same header is NOT allowlisted
status=0; check_warnings "$FIXTURES/narrow-allowlist.log" >/dev/null || status=$?
expect_exit 1 "$status" "off-line warning in allowlisted header fails"

echo ""
if [[ "$fail" -gt 0 ]]; then
    echo "❌ warning-check: $fail fixture(s) failed"
    exit 1
fi
echo "✅ warning-check: $pass fixture(s) passed"