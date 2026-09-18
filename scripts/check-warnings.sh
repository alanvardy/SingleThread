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