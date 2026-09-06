#!/usr/bin/env bash
set -euo pipefail

echo "==> Stopping storekitd…"
launchctl stop com.apple.storekitd 2>/dev/null || true

# The host DB lives in one of two known locations. Try the per-user daemon DB
# first (observed on this machine), then the Octane layout.
DB_PATH=""
for candidate in \
    "$HOME/Library/Application Support/App Store/StoreKit.db" \
    "$HOME/Library/Caches/com.apple.storekitagent/Octane" \
    "$HOME/Library/Caches/com.apple.appstoreagent/Octane"; do
    if [ -f "$candidate" ] || [ -d "$candidate" ]; then
        DB_PATH="$candidate"
        break
    fi
done

if [ -z "$DB_PATH" ]; then
    echo "==> No StoreKit transaction store found at known paths. The host may already be clean."
    echo "    Checked:"
    echo "      ~/Library/Application Support/App Store/StoreKit.db"
    echo "      ~/Library/Caches/com.apple.storekitagent/Octane/"
    echo "      ~/Library/Caches/com.apple.appstoreagent/Octane/"
    exit 0
fi

echo "==> Found StoreKit store at: $DB_PATH"

if [ -f "$DB_PATH" ] && [[ "$DB_PATH" == *.db ]]; then
    # SQLite DB — drop transactions for the app's bundle ID.
    if command -v sqlite3 &>/dev/null; then
        echo "==> Clearing transactions for app.alanvardy.SingleThread…"
        sqlite3 "$DB_PATH" "DELETE FROM octane_transaction WHERE bundle_id = 'app.alanvardy.SingleThread';" 2>/dev/null || \
            echo "    (table may not exist or DB schema differs — this is non-fatal)"
    else
        echo "==> sqlite3 not found; truncating DB file…"
        :> "$DB_PATH"
    fi
elif [ -d "$DB_PATH" ]; then
    # Octane directory layout — find store.db files and truncate.
    find "$DB_PATH" -name "store.db" -type f | while read -r f; do
        echo "==> Found: $f"
        if command -v sqlite3 &>/dev/null; then
            sqlite3 "$f" "DELETE FROM octane_transaction WHERE bundle_id = 'app.alanvardy.SingleThread';" 2>/dev/null || true
        else
            :> "$f"
        fi
    done
fi

echo "==> Restarting storekitd…"
launchctl kickstart -k system/com.apple.storekitd 2>/dev/null || true

echo "==> Done. Run 'make mac-test' to verify."