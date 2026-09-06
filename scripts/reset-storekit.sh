#!/usr/bin/env bash
set -euo pipefail

# Clears the local host StoreKit transaction store so macOS unit tests run
# against a clean sandbox. The store is the per-user encrypted SQLCipher DB
# held by the `storekitagent` LaunchAgent
# (`~/Library/Group Containers/group.com.apple.storekit/Library/Caches/storeUser.db`),
# not the plain-SQLite Octane paths that older scripts guessed at.

STORE_DIR="$HOME/Library/Group Containers/group.com.apple.storekit/Library/Caches"
STORE_FILES=(storeUser.db storeUser.db-wal storeUser.db-shm)
AGENT="gui/$(id -u)/com.apple.storekitagent"

echo "==> Locating the host StoreKit store…"
if [ ! -d "$STORE_DIR" ]; then
    echo "    No StoreKit store at $STORE_DIR — nothing to clear."
    echo "    (legacy fallbacks checked historically:"
    echo "      ~/Library/Application Support/App Store/StoreKit.db"
    echo "      ~/Library/Caches/com.apple.storekitagent/Octane/"
    echo "      ~/Library/Caches/com.apple.appstoreagent/Octane/)"
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
    echo "    No store files found in $STORE_DIR — nothing to clear."
    echo "    (the store directory contains:)"
    ls -la "$STORE_DIR"
    echo "    The host store may already be clean."
    exit 0
fi

echo "    Found: ${present[*]} in $STORE_DIR"
echo "    (legacy fallbacks checked historically:"
echo "      ~/Library/Application Support/App Store/StoreKit.db"
echo "      ~/Library/Caches/com.apple.storekitagent/Octane/"
echo "      ~/Library/Caches/com.apple.appstoreagent/Octane/)"

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
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "    PID $pid still alive after SIGTERM — sending SIGKILL."
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done

    local waited=0
    while [ "$waited" -lt 20 ]; do
        if ! lsof "$STORE_DIR/storeUser.db" >/dev/null 2>&1; then
            echo "    Store released (bounded wait ~$((waited * 5))s)."
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

# ---------------------------------------------------------------------------
# Back up the store (the repo's .bak-<epoch> convention) then remove it so
# the next agent launch creates a fresh, empty store.
# ---------------------------------------------------------------------------
STAMP="$(date +%s)"
echo "==> Backing up store files to *.bak-$STAMP…"
for f in "${STORE_FILES[@]}"; do
    if [ -e "$STORE_DIR/$f" ]; then
        mv "$STORE_DIR/$f" "$STORE_DIR/$f.bak-$STAMP"
        echo "    $f -> $f.bak-$STAMP"
    fi
done

echo "==> Restarting the StoreKit agent…"
if launchctl kickstart "$AGENT" 2>/dev/null; then
    echo "    Agent restarted via 'launchctl kickstart $AGENT'."
else
    # The agent is RunAtLoad=false and on-demand; the next StoreKit client
    # (e.g. the next `make mac-test`) spawns it automatically. `storekitd`
    # itself is simulator-scoped and not involved in host reads.
    echo "    launchctl kickstart unavailable; the next StoreKit client will spawn the agent on demand."
fi

echo ""
echo "==> Done. Run 'make mac-test' to verify — hostStoreKitIsClean should now pass."