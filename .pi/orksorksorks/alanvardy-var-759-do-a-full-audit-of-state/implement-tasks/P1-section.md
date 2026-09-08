
### Changes

#### 1. Create `audit/` directory
**Action**: create directory `.pi/qrspi/<branch>/audit/`

#### 2. Create `audit/factbase.tsv`
**File**: `.pi/qrspi/<branch>/audit/factbase.tsv`
**Action**: create

Tab-separated file with header row followed by one row per state-value declaration/read/write. Columns:

```
id	target	node	file	line	lineText
```

**Schema**:
- `id`: stable logical key (e.g. `sortOption`, `completionCount`, `showDate`)
- `target`: `ios` | `watchOS` | `widget` | `core`
- `node`: `declaration` | `read` | `write` | `dualRead` | `hook` | `seam` | `wcPayload`
- `file`: repo-relative path (e.g. `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`)
- `line`: integer line number
- `lineText`: exact source text at that line, copied byte-for-byte

**Data sources** — compile from `research.md` Q1-Q7, re-verifying every line number at implementation time:

1. **`.standard` keys (12)**: declaration at `ContentView.swift:72-112` (`@AppStorage` lines), plus read/write sites from Q1 table, Q6 writer inventory, and Q5 sync paths.

2. **App Group keys (11)**: declaration at `ContentView.swift:115-132` (`@AppStorage(_, store: AppGroup.defaults)`), wrapper struct load/save lines (`Show*Preference.swift`, `SortOptionStore.swift:34-43`, `CompletionCounterStore.swift:24-47`), Q6 writers, Q5 sync receive.

3. **In-memory stores**: `ReminderStore.swift` properties (:55-70, :106, :464), `EntitlementStore.swift` properties (:54, :60), `EntitlementState.swift` (:17), `WatchReminderViewModel.swift` (:43-55), `DictationViewModel.swift` (:22-25), `ReminderDictation.swift` (:107-108), all `Show*State.swift` (:18, :25-28), `CompletionGlow.swift` (:21, :26), `UndoStore.swift` (:19), `BackgroundImageStore.swift` (:69-81), `ResumptionGate.swift` (:28).

4. **WatchConnectivity payload keys**: `SkippedReminderSyncService.swift:268-282` (`PayloadKey` enum), push sites (:167-199), receive sites (:308-367), hooks (:83-154).

5. **Test seams**: `UITestingSeed.swift:63-85` (persistedKeys array — each key's line within the array re-verified), `AppViewModel.swift:294` (seed count write), `WatchAppViewModel.swift:27` (gated seam).

6. **Bypass writes**: every direct assignment or raw `UserDefaults` write from Q6 bypass-paths section.

7. **Dual-read sites**: every raw `UserDefaults` read supplementary to `@AppStorage` from Q1 dual-read summary.

**Coverage target**: every key has ≥1 declaration + ≥1 read + ≥1 write row; all 23 production persisted keys present. Include transient state rows for the four combinatorial clusters only (completion-transition, branch-ordering, entitlement gate, dictation).

**Implementation approach**: read each cited source file, extract the exact line text, and append a TSV row. Re-verify every line number — research.md warns of potential drift on `UITestingSeed.persistedKeys` sub-line numbering; check each line against the actual source.

#### 3. Create `audit/verify-citations.sh`
**File**: `.pi/qrspi/<branch>/audit/verify-citations.sh`
**Action**: create

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FACTBASE="$SCRIPT_DIR/factbase.tsv"
FAILURES=0
TOTAL=0

# Skip header line
tail -n +2 "$FACTBASE" | while IFS=$'\t' read -r id target node file line lineText; do
  TOTAL=$((TOTAL + 1))
  actual="$(sed -n "${line}p" "$REPO_ROOT/$file" 2>/dev/null || echo "FILE_NOT_FOUND:${file}:${line}")"
  if [ "$actual" != "$lineText" ]; then
    echo "MISMATCH: id=$id file=$file line=$line"
    echo "  expected: $lineText"
    echo "  actual:   $actual"
    FAILURES=$((FAILURES + 1))
  fi
done

echo "Verified $TOTAL citations."
if [ "$FAILURES" -gt 0 ]; then
  echo "FAIL: $FAILURES citation(s) do not match source."
  exit 1
fi
echo "PASS: all citations match source."
```

Note: since `while` runs in a subshell in bash when piped from `tail`, variables set inside the loop don't propagate. The script above is the conceptual shape — the actual implementation must use process substitution or a temp file to accumulate failures:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
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
```

#### 4. Create `audit/verify-citations-self-test.sh` (sad-path gate)
**File**: `.pi/qrspi/<branch>/audit/verify-citations-self-test.sh`
**Action**: create

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Copy factbase and deliberately corrupt one lineText
CORRUPTED="$(mktemp)"
head -n1 "$SCRIPT_DIR/factbase.tsv" > "$CORRUPTED"
# Change the first data row's lineText to a known-bogus value
tail -n +2 "$SCRIPT_DIR/factbase.tsv" | head -n1 | sed 's/\t[^\t]*$/\tCORRUPTED_TEXT_FOR_SELF_TEST/' >> "$CORRUPTED"
tail -n +3 "$SCRIPT_DIR/factbase.tsv" >> "$CORRUPTED"

# Run the verifier against corrupted copy; expect non-zero exit
if "$SCRIPT_DIR/verify-citations.sh" < "$CORRUPTED" 2>/dev/null; then
  echo "FAIL: self-test — verifier passed corrupted data (should have failed)"
  rm -f "$CORRUPTED"
  exit 1
fi
rm -f "$CORRUPTED"
echo "PASS: self-test — verifier correctly rejects corrupted citations"
```

Note: `verify-citations.sh` reads `$SCRIPT_DIR/factbase.tsv` directly, not stdin. The self-test script needs to either:
- (a) Create a temporary copy of the verifier that reads from a different path, or
- (b) Overwrite factbase.tsv temporarily and restore it.

Option (b) is simpler:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FACTBASE="$SCRIPT_DIR/factbase.tsv"
BACKUP="$(mktemp)"

cp "$FACTBASE" "$BACKUP"

# Corrupt the first data row's lineText
{
  head -n1 "$BACKUP"
  tail -n +2 "$BACKUP" | head -n1 | awk 'BEGIN{FS=OFS="\t"} {$(NF)="CORRUPTED_TEXT_FOR_SELF_TEST"; print}'
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
```

### Verification

#### Automated
- [ ] `bash audit/verify-citations.sh` exits 0 — all pinned `lineText` match source
- [ ] `bash audit/verify-citations-self-test.sh` exits 0 — corruption is caught
- [ ] Triplet invariant: for each of the 23 persisted-key `id`s, count rows with `node=declaration` ≥ 1, `node=read` ≥ 1, `node=write` ≥ 1 (manual grep check: `awk -F'\t' '$1=="sortOption" && $3=="declaration"' audit/factbase.tsv | wc -l`, etc.)
- [ ] All 23 production keys present: `cut -f1 audit/factbase.tsv | sort -u | grep -c -E '^(appearanceMode|textSize|allowsLandscape|showMicrophoneButton|backgroundEnabled|backgroundFadePercent|backgroundPinned|enableActionButtons|showSwipePrompt|showUndoButton|notificationsEnabled|notificationIntervalHours|showUndatedReminders|sortOption|showDate|showList|showRecurrence|showAlarms|showCompletionGlow|skippedReminderIdentifiers|excludedListTitles|completionCount|pendingCompletionIdentifiers)$'` = 23

#### Manual
- [ ] Spot-check 5 random rows: open the file at that line, verify the text matches
- [ ] Check that `audit/factbase.tsv` has no empty cells (no bare tabs with missing values)

---

