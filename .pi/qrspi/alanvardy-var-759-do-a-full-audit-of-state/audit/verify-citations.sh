#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
FACTBASE="$SCRIPT_DIR/factbase.tsv"
FAIL_FILE="$(mktemp)"
echo "0" > "$FAIL_FILE"
TOTAL=0

while IFS=$'\t' read -r id target node file line lineText; do
  TOTAL=$((TOTAL + 1))
  actual="$(sed -n "${line}p" "$REPO_ROOT/$file" 2>/dev/null || echo "FILE_NOT_FOUND:${file}:${line}")"
  if [ "$actual" != "$lineText" ]; then
    echo "MISMATCH: id=$id file=$file line=$line"
    echo "  expected: $lineText"
    echo "  actual:   $actual"
    count="$(cat "$FAIL_FILE")"
    echo "$((count + 1))" > "$FAIL_FILE"
  fi
done < <(tail -n +2 "$FACTBASE")

echo "Verified $TOTAL citations."
failures="$(cat "$FAIL_FILE")"
rm -f "$FAIL_FILE"
if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures citation(s) do not match source."
  exit 1
fi
echo "PASS: all citations match source."