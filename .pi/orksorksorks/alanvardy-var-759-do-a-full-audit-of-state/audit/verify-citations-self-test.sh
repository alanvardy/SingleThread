#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FACTBASE="$SCRIPT_DIR/factbase.tsv"
BACKUP="$(mktemp)"

cp "$FACTBASE" "$BACKUP"

# Corrupt the first data row's lineText
{
  head -n1 "$BACKUP"
  sed -n '2p' "$BACKUP" | awk 'BEGIN{FS=OFS="\t"} {$(NF)="CORRUPTED_TEXT_FOR_SELF_TEST"; print}'
  tail -n +3 "$BACKUP"
} > "$FACTBASE"

set +e
"$SCRIPT_DIR/verify-citations.sh"
rc=$?
set -e

cp "$BACKUP" "$FACTBASE"
rm -f "$BACKUP"

if [ "$rc" -eq 0 ]; then
  echo "FAIL: self-test — verifier passed corrupted data (should have failed)"
  exit 1
fi
echo "PASS: self-test — verifier correctly rejects corrupted citations"