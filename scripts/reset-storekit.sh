#!/usr/bin/env bash
set -euo pipefail

# This script targets the real per-user store under $HOME; running as root
# (sudo) would point $HOME at /var/root and silently no-op, so refuse that.
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run this as the GUI user, not root (sudo changes \$HOME to /var/root)." >&2
    exit 1
fi

# Clears the local per-user StoreKit transaction store. The store is the
# encrypted SQLCipher DB held by the `storekitagent` LaunchAgent
# (`~/Library/Group Containers/group.com.apple.storekit/Library/Caches/storeUser.db`),
# not the plain-SQLite Octane paths that older scripts guessed at.
# NOTE: clearing these files is necessary but NOT sufficient to clear
# account-scoped entitlement state, which the next StoreKit read re-seeds
# (see the var-793 note at the end of this script).

STORE_DIR="$HOME/Library/Group Containers/group.com.apple.storekit/Library/Caches"
STORE_FILES=(storeUser.db storeUser.db-wal storeUser.db-shm)
AGENT="gui/$(id -u)/com.apple.storekitagent"

print_legacy_hint() {
    echo "    (legacy fallbacks checked historically:"
    echo "      ~/Library/Application Support/App Store/StoreKit.db"
    echo "      ~/Library/Caches/com.apple.storekitagent/Octane/"
    echo "      ~/Library/Caches/com.apple.appstoreagent/Octane/)"
}

echo "==> Locating the host StoreKit store..."
if [ ! -d "$STORE_DIR" ]; then
    echo "    No StoreKit store at $STORE_DIR -- nothing to clear."
    print_legacy_hint
    echo "    The host store may already be clean."
    exit 0
fi

present=()
for f in "${STORE_FILES[@]}"; do
    if [ -e "$STORE_DIR/$f" ]; then
        present+=("$f")
    fi
done

if [ "${#present[@]}" -eq 0 ]; then
    echo "    No store files found in $STORE_DIR -- nothing to clear."
    echo "    (the store directory contains:)"
    ls -la "$STORE_DIR"
    echo "    The host store may already be clean."
    exit 0
fi

echo "    Found: ${present[*]} in $STORE_DIR"
print_legacy_hint

# ---------------------------------------------------------------------------
# Stop the daemon that holds the store. `launchctl kill`/`stop` are refused
# for this system-owned LaunchAgent, so signal the process directly. SIGTERM
# is often deferred while active connections are open, so fall back to
# SIGKILL after a short grace period, then wait (bounded) for the files to be
# released.
# ---------------------------------------------------------------------------
release_lock() {
    local pids=""
    pids=$(lsof "$STORE_DIR/storeUser.db" 2>/dev/null | awk 'NR > 1 {print $2}' | sort -u || true)

    if [ -z "$pids" ]; then
        echo "==> No process holds $STORE_DIR/storeUser.db (already stopped)."
        return 0
    fi

    echo "==> Stopping StoreKit agent process(es): $(echo "$pids" | tr '\n' ' ')"
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    sleep 3
    # Re-derive holders after the grace period: the pre-SIGTERM $pids snapshot
    # is stale by now and a blind SIGKILL could hit a reused PID.
    local live_pids=""
    live_pids=$(lsof "$STORE_DIR/storeUser.db" 2>/dev/null | awk 'NR > 1 {print $2}' | sort -u || true)
    for pid in $live_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "    PID $pid still alive after SIGTERM -- sending SIGKILL."
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done

    local waited=0
    while [ "$waited" -lt 20 ]; do
        if ! lsof "$STORE_DIR/storeUser.db" >/dev/null 2>&1; then
            echo "    Store released (bounded wait ~$((waited / 2))s)."
            return 0
        fi
        sleep 0.5
        waited=$((waited + 1))
    done

    echo "    ERROR: store still held by:"
    lsof "$STORE_DIR/storeUser.db" || true
    return 1
}

release_lock

# Re-check the lock is still released immediately before renaming: the agent
# can respawn on-demand between the bounded wait above and the backup below.
if lsof "$STORE_DIR/storeUser.db" >/dev/null 2>&1; then
    echo "    ERROR: store re-acquired between release and backup; aborting."
    lsof "$STORE_DIR/storeUser.db" || true
    exit 1
fi

# ---------------------------------------------------------------------------
# Back up the store (the repo's .bak-<epoch> convention) then remove it so
# the next agent launch creates a fresh, empty store.
# ---------------------------------------------------------------------------
STAMP="$(date +%s)"
echo "==> Backing up store files to *.bak-$STAMP..."
for f in "${STORE_FILES[@]}"; do
    if [ -e "$STORE_DIR/$f" ]; then
        mv "$STORE_DIR/$f" "$STORE_DIR/$f.bak-$STAMP"
        echo "    $f -> $f.bak-$STAMP"
    fi
done

echo "==> Restarting the StoreKit agent..."
if launchctl kickstart "$AGENT" 2>/dev/null; then
    echo "    Agent restarted via 'launchctl kickstart $AGENT'."
else
    # The agent is RunAtLoad=false and on-demand; the next StoreKit client
    # (e.g. the next `make mac-test`) spawns it automatically. `storekitd`
    # itself is simulator-scoped and not involved in host reads.
    echo "    launchctl kickstart unavailable; the next StoreKit client will spawn the agent on demand."
fi

echo ""
echo "==> Done. Run 'make mac-test' to verify."
echo ""
echo "    NOTE (var-793): clearing these files is necessary but not always"
echo "    sufficient. The test run itself re-seeds the store from account-"
echo "    scoped sandbox state, so a dirty host may STILL fail the two"
echo "    real-StoreKit tests (isEntitledSurvivesStoreRecreation,"
echo "    initialRefreshSettlesResolvedFlag) plus hostStoreKitIsClean. That"
echo "    is expected and diagnosed by the canary. The remaining avenue is"
echo "    Xcode -> Debug -> StoreKit -> Manage Transactions... while the"
echo "    development app is running (no command-line equivalent exists)."