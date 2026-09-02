#!/usr/bin/env bash
# Prune regenerable Xcode build artifacts to reclaim disk space.
#
# Safe by construction: every target is a cache Xcode rebuilds on demand.
#   1. Stale GUI DerivedData (project folders + *.noindex caches) older than
#      PRUNE_AGE_DAYS (default 7). The repo's own ./DerivedData (used by
#      `make` and scripts/test.sh) is never touched.
#   2. Orphaned simulator devices (xcrun simctl delete unavailable).
#   3. Pruned git worktree bookkeeping (git worktree prune).
#
# Intentionally left alone: simulator runtimes, iOS/watchOS DeviceSupport and
# Archives — those need a conscious decision (see AGENTS.md → Disk hygiene).
#
# Usage:
#   ./scripts/prune-build-artifacts.sh [-n|--dry-run]
#   PRUNE_AGE_DAYS=14 ./scripts/prune-build-artifacts.sh
#
# Runs weekly (Sun 03:30) via
# ~/Library/LaunchAgents/com.singlethread.prune-build-artifacts.plist.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI_DD="${GUI_DD:-$HOME/Library/Developer/Xcode/DerivedData}"
AGE_DAYS="${PRUNE_AGE_DAYS:-7}"

DRY_RUN=1
if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=0
fi

log() { printf '%s\n' "$*"; }

delete_path() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "    [dry-run] would delete $1"
    else
        rm -rf -- "$1"
        log "    deleted $1"
    fi
}

prune_gui_derived_data() {
    if [[ ! -d "$GUI_DD" ]]; then
        log "==> GUI DerivedData ($GUI_DD): not present; nothing to prune."
        return
    fi
    log "==> Pruning GUI DerivedData entries older than ${AGE_DAYS}d in $GUI_DD"
    local removed=0
    while IFS= read -r -d '' entry; do
        removed=$((removed + 1))
        delete_path "$entry"
    done < <(
        find "$GUI_DD" \
            -maxdepth 1 -mindepth 1 -type d \
            -mtime "+$AGE_DAYS" -print0
    )
    log "    found $removed stale entr(y/ies)."
}

prune_unavailable_simulators() {
    log "==> Removing unavailable simulator devices (xcrun simctl delete unavailable)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "    [dry-run] skipped"
    else
        xcrun simctl delete unavailable || log "    (simctl reported a problem; continuing)"
    fi
}

prune_worktrees() {
    log "==> Pruning dead git worktree bookkeeping"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "    [dry-run] skipped"
    else
        git -C "$REPO_ROOT" worktree prune
    fi
}

report() {
    log ""
    log "==> Disk usage"
    df -h / | awk 'NR == 1 || /\/$/' | sed 's/^/    /'
    log ""
    log "==> Installed simulator runtimes"
    xcrun simctl runtime list | sed 's/^/    /'
    log ""
    log "==> GUI DerivedData remaining ($GUI_DD)"
    du -sh "$GUI_DD" 2>/dev/null | sed 's/^/    /' || log "    (empty or missing)"
    log ""
    log "==> Device support (kept; re-fetched on demand by Xcode)"
    du -sh "$HOME/Library/Developer/Xcode/"{iOS,watchOS}" DeviceSupport" 2>/dev/null | sed 's/^/    /' || true
}

prune_gui_derived_data
prune_unavailable_simulators
prune_worktrees
report