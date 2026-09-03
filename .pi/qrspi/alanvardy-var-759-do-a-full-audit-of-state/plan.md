# Implementation Plan

## Overview

Produce a read-only state audit report under `.pi/qrspi/<branch>/audit/` that inventories every persisted and shared in-memory state value across all four targets, identifies reachable invalid/contradictory state combinations, ranks findings by risk severity, and provides enum sketches for the highest-value clusters. No app code changes land in this ticket — the audit report is the work product.

---

## Phase 1: Fact base — citation-verified source index

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
- [x] `bash audit/verify-citations.sh` exits 0 — all pinned `lineText` match source
- [x] `bash audit/verify-citations-self-test.sh` exits 0 — corruption is caught
- [x] Triplet invariant: for each of the 23 persisted-key `id`s, count rows with `node=declaration` ≥ 1, `node=read` ≥ 1, `node=write` ≥ 1 (manual grep check: `awk -F'\t' '$1=="sortOption" && $3=="declaration"' audit/factbase.tsv | wc -l`, etc.)
- [x] All 23 production keys present: `cut -f1 audit/factbase.tsv | sort -u | grep -c -E '^(appearanceMode|textSize|allowsLandscape|showMicrophoneButton|backgroundEnabled|backgroundFadePercent|backgroundPinned|enableActionButtons|showSwipePrompt|showUndoButton|notificationsEnabled|notificationIntervalHours|showUndatedReminders|sortOption|showDate|showList|showRecurrence|showAlarms|showCompletionGlow|skippedReminderIdentifiers|excludedListTitles|completionCount|pendingCompletionIdentifiers)$'` = 23

#### Manual
- [ ] Spot-check 5 random rows: open the file at that line, verify the text matches
- [ ] Check that `audit/factbase.tsv` has no empty cells (no bare tabs with missing values)

---

## Phase 2: Inventory — key-centric and store-mirror cross-reference

### Changes

#### 1. Create `audit/inventory.md`
**File**: `.pi/qrspi/<branch>/audit/inventory.md`
**Action**: create

**Content structure**:

```markdown
# State Inventory

## Suite Accessor

| Component | Value | Source |
|---|---|---|
| suiteName | `group.app.alanvardy.SingleThread` | `AppGroup.swift:8` |
| defaults accessor | `UserDefaults(suiteName:) ?? .standard` (un-cached, recomputed per access) | `AppGroup.swift:10-14` |

## `.standard` Keys (12)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `appearanceMode` | `.system` | String rawValue | `ContentView.swift:72` | `ContentView.swift:72`, `AppearanceMode.swift:79-86`, `AppDelegate.swift:44-46` | `ContentView+Settings.swift` (bag→@AppStorage), `UITestingSeed.swift:63-85` (reset) | yes | ios, widget |
| ... | ... | ... | ... | ... | ... | ... | ... |

## App Group Keys (11)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `showUndatedReminders` | `false` | `object as? Bool ?? false` | `ContentView.swift:115` | ... | ... | yes | ios, watchOS, widget |
| ... | ... | ... | ... | ... | ... | ... | ... |

## Dual-Read-Path Keys

List of keys with `@AppStorage` plus an independent raw read, with both read sites cited:

| Key | @AppStorage Site | Raw Read Site(s) |
|---|---|---|
| `enableActionButtons` | `ContentView.swift:96` | `ContentViewModel.swift:45-49` |
| `notificationsEnabled` | `ContentView.swift:109` | `AppViewModel.swift:127` |
| `notificationIntervalHours` | `ContentView.swift:112` | `AppViewModel.swift:131-132` |
| `allowsLandscape` | `ContentView.swift:79` | `AppDelegate.swift:53-56` |
| `appearanceMode` | `ContentView.swift:72` | `AppearanceMode.swift:79-86` via `AppDelegate.swift:44-46` |
| `showDate` | `ContentView.swift:121` | `ShowDatePreference.swift:20` |
| `showList` | `ContentView.swift:124` | `ShowListPreference.swift:20` |
| `showRecurrence` | `ContentView.swift:127` | `ShowRecurrencePreference.swift:20` |
| `showAlarms` | `ContentView.swift:129` | `ShowAlarmsPreference.swift:20` |
| `showCompletionGlow` | `ContentView.swift:132` | `ShowCompletionGlowPreference.swift:19-21` |
| `sortOption` | `ContentView.swift:118` | `SortOptionStore.swift:34-39` |
| `showUndatedReminders` | `ContentView.swift:115` | `ShowUndatedRemindersPreference.swift:19` |

## Single-Path Keys

| Key | Path | Site |
|---|---|---|
| `textSize` | @AppStorage only | `ContentView.swift:75` |
| `showMicrophoneButton` | @AppStorage (+registerDefaults only) | `ContentView.swift:83` |
| `backgroundEnabled` | @AppStorage only | `ContentView.swift:86` |
| `backgroundFadePercent` | @AppStorage only | `ContentView.swift:89` |
| `backgroundPinned` | @AppStorage + BackgroundImageStore mirror | `ContentView.swift:92` |
| `showSwipePrompt` | @AppStorage only | `ContentView.swift:101` |
| `showUndoButton` | @AppStorage only | `ContentView.swift:106` |
| `skippedReminderIdentifiers` | store read/write only (App Group) | `ReminderSkip.swift:124,132,136` |
| `excludedListTitles` | store read/write only (App Group) | `ExcludedListStore.swift:7,15,19` |
| `completionCount` | store read/write only (App Group) | `CompletionCounterStore.swift:11,24-47` |
| `pendingCompletionIdentifiers` | store read/write only (App Group, watch-only) | `PendingCompletionStore.swift:21,70,83` |

## Store Mirror Table

| Store | Property | Mirrors Key | Kind | Notes |
|---|---|---|---|---|
| `ReminderStore` | `sortOption` (:70) | `sortOption` | persisted | Direct assignment bypasses hooks (:68-69 doc) |
| `ReminderStore` | `showsUndatedReminders` (:122-127) | `showUndatedReminders` | persisted | `didSet` fires `onShowUndatedRemindersChanged` |
| `ReminderStore` | `skippedIDs` (:56) | `skippedReminderIdentifiers` | persisted | private(set) |
| `ReminderStore` | `excludedListTitles` (:57) | `excludedListTitles` | persisted | private(set) |
| `ReminderStore` | `completionCounter` (:106) | `completionCount` | persisted | let; counter store reads/writes internally |
| `ReminderStore` | `pendingCompletions` (:464) | `pendingCompletionIdentifiers` | persisted | private; watch-only |
| `ReminderStore` | `reminders` (:55) | — | transient | private(set); populated by `reload()` |
| `ReminderStore` | `hasHidden` (:62) | — | transient | private(set); set in `reload()` |
| `ReminderStore` | `availableLists` (:64) | — | transient | private(set) |
| `ReminderStore` | `authorizationStatus` (:65) | — | transient | private(set) |
| `ReminderStore` | `skipGeneration` (:468) | — | transient | private |
| `ReminderStore` | `loadsReminders` (:66) | — | immutable | let |
| `ReminderStore` | `entitlementStore` (:110) | — | value ref | let; see `EntitlementStore` |
| `ReminderStore` | `undoStore` (:115) | — | transient | let; `#if !os(watchOS)` |
| `ReminderStore` | `visibleReminders` (:129) | — | computed | |
| `ReminderStore` | `allSkipped` (:138-140) | — | computed | `!reminders.isEmpty && visibleReminders.isEmpty` |
| `ReminderStore` | `canMutate` (:144-145) | — | computed | `isEntitled \|\| completionCounter.count < 100` |
| `ReminderStore` | `hasResolvedEntitlement` (:151) | — | computed | forwards `entitlementStore.hasResolvedEntitlement` |
| `EntitlementStore` | `isEntitled` (:54) | — | transient | StoreKit-derived, never persisted |
| `EntitlementStore` | `hasResolvedEntitlement` (:60) | — | transient | set adjacently with `isEntitled` (:104-105) |
| `EntitlementState` (watch) | `isEnabled` (:17) | — | transient | set from WC context only |
| `WatchReminderViewModel` | `isShowingCompletionTransition` (:47) | — | transient | set with `transitionReminder` |
| `WatchReminderViewModel` | `transitionReminder` (:51) | — | transient | `EKReminder?` |
| `WatchReminderViewModel` | `completionTransitionBuffer` (:55) | — | transient | 0.5 s |
| `CompletionGlow` | `isActive` (:21) | — | transient | |
| `CompletionGlow` | `duration` (:26) | — | transient | default 0.50 |
| `DictationViewModel` | `isDictating` (:22) | — | transient | |
| `DictationViewModel` | `dictationText` (:23) | — | transient | |
| `DictationViewModel` | `dictationError` (:24) | — | transient | |
| `DictationViewModel` | `creationFeedback` (:25) | — | transient | `.success`/`.failure`; auto-clears |
| `ReminderDictation` | `isRecording` (:107) | — | transient | `@ObservationIgnored` members nearby |
| `UndoStore` | `lastCompletedReminder` (:19) | — | transient | iOS-only |
| `UndoStore` | `hasUndoableReminder` (:21) | — | computed | |
| `BackgroundImageStore` | `imageData` (:69) | — | transient | mirrors photo files on disk |
| `BackgroundImageStore` | `photographer` (:71) | — | transient | |
| `BackgroundImageStore` | `photographerURL` (:73) | — | transient | |
| `BackgroundImageStore` | `isRefreshing` (:76) | — | transient | |
| `BackgroundImageStore` | `isPinned` (:81) | `backgroundPinned` | persisted | mirrors @AppStorage key |
| `BackgroundImageStore` | `isFetching` (:198) | — | transient | |
| `ResumptionGate` | `hasResumed` (:28) | — | transient | plain class, no observation |
| Watch `Show*State` (×5) | `isEnabled` (:18) | show-* (×5) | persisted | double-persisted (service + `.apply()`); `.standard` |
| `SettingsBindings` | 19 mutable props (:63-81) | mirrors 19 @AppStorage | transient | per-sheet bag; never writes directly |
| `AppViewModel` | `lastShow*` shadow caches (:401-405) | show-* (×5) | transient | diffed for `pushAll()` trigger |
| `AppViewModel` | `pendingSummary` (:108) | — | transient | test-only |
| `AppViewModel` | `lastScheduleSummary` (:112) | — | transient | test-only |
| `ContentViewModel` | `showsActionButtons` (:45-49) | `enableActionButtons` | computed | live raw `UserDefaults.standard.bool` read |

## Notable Transient State (Acknowledged, Not Exhaustive)

- `ContentView.@State isShowingSettings` (:257), `isShowingPurchase` (:261) — sheet presentation flags
- `WatchReminderViewModel.isRefreshing` (:43), `isShowingRefreshConfirmation` (:44) — refresh UI state
```

**Key constraints**:
- Every `file:line` citation in inventory.md must exist in `factbase.tsv` (cite-check via grep)
- Dual-read-path set must match exactly the 12 keys from research Q1 (re-verified at implementation time): `enableActionButtons`, `notificationsEnabled`, `notificationIntervalHours`, `allowsLandscape`, `appearanceMode`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `sortOption`, `showUndatedReminders`
- Store mirror table must confirm: no `ObservableObject` exists; every store is `@Observable final class` except `WatchAppViewModel`/`ResumptionGate` (plain classes) and the widget (no view model)

### Verification

#### Automated
- [x] Cite-check: every `*.swift:<line>` citation string in `audit/inventory.md` appears as a row in `audit/factbase.tsv` — `grep -oE '[A-Za-z]+\.swift:[0-9]+' audit/inventory.md | sort -u | while read cite; do grep -q "$cite" audit/factbase.tsv || echo "MISSING: $cite"; done` produces no output
- [x] `bash audit/verify-citations.sh` still exits 0 (fact base remains clean)
- [x] 23-key split: count `.standard` key rows = 12, count App Group key rows = 11 in `inventory.md`
- [x] Store mirror table row count matches research Q2's enumerated stores (approximately 35 rows)

#### Manual
- [ ] Dual-read-path set enumerated in `inventory.md` matches the list above (12 keys) — no more, no fewer
- [ ] Store mirror table confirms no `ObservableObject` reference exists — `grep ObservableObject audit/inventory.md` produces no matches
- [ ] Every store in the mirror table is `@Observable final class` or explicitly noted as plain class / no view model

---

## Phase 3: Combinatorial clusters + cross-target divergence analysis

### Changes

#### 1. Create `audit/clusters.md`
**File**: `.pi/qrspi/<branch>/audit/clusters.md`
**Action**: create

**Content structure**:

```markdown
# Combinatorial Clusters & Cross-Target Divergence

## Cluster 1: Completion-Transition (watchOS)

### State Vector
| Field | Type | Source |
|---|---|---|
| `isShowingCompletionTransition` | Bool | `WatchReminderViewModel.swift:47` |
| `transitionReminder` | `EKReminder?` | `WatchReminderViewModel.swift:51` |
| `CompletionGlow.isActive` | Bool | `CompletionGlow.swift:21` |

### Reachability Matrix

| `isShowingCompletionTransition` | `transitionReminder` | `glow.isActive` | Reachability | Renders |
|---|---|---|---|---|
| false | nil | inactive | **reachable** (resting state) | Normal card |
| true | ≠nil | active | **reachable** (complete path, glow enabled, no re-entry) | Ghost card + green overlay (`WatchReminderView.swift:79-81,97-98`) |
| true | ≠nil | inactive | **reachable** (buffer window: glow expired, card still shown) | Ghost card without glow overlay |
| true | nil | — | **unreachable** (proven: no path sets `isShowingCompletionTransition` without also setting `transitionReminder` — both set together under guard :66-67) | N/A |
| false | ≠nil | — | **unreachable** (proven: `transitionReminder` only set when flag is true, cleared together :78-81) | N/A |
| — | — | active when glow disabled | **unreachable** (proven: glow gate `showCompletionGlowState.isEnabled` :69; disabled → never set :68-69,85-86) | N/A |

### Transition Path
1. User taps Complete → guard `!isShowingCompletionTransition` (:66) → sets flag true, snapshots `store.visibleReminders.first` as `transitionReminder` (:67)
2. If `showCompletionGlowState.isEnabled` → `glow.trigger()` (:69)
3. Timed clear at `glow.duration + completionTransitionBuffer` (:72-84) → both flag and reminder set nil (:78-81); if complete fails → nil + no glow (:85-86)
4. Ghost-card buttons live (act on next visible reminder) except Complete (blocked by :66 guard)

**Documentation Drift**: `AppViewModel.swift:211` comment claims production glow is 0.25 s; actual default is 0.50 (`CompletionGlow.swift:26`)

## Cluster 2: Empty / All-Done / First-Card Branch Ordering

### State Vector
| Field | Type | Source |
|---|---|---|
| `reminders` (store) | `[EKReminder]` | `ReminderStore.swift:55` |
| `hasHidden` | Bool | `ReminderStore.swift:62` |
| `allSkipped` | computed Bool | `ReminderStore.swift:138-140` |
| `authorizationStatus` | `EKAuthorizationStatus` | `ReminderStore.swift:65` |

`allSkipped = !reminders.isEmpty && visibleReminders.isEmpty`

### iOS Branch Order (`ContentView.swift:355-455`, behind auth gate `:339-349`)

| `reminders` | `allSkipped` | `hasHidden` | Reachability | Renders |
|---|---|---|---|---|
| non-empty | false | — | **reachable** (normal) | First visible reminder card (:390) |
| non-empty | true | — | **reachable** (all visible reminders skipped) | All-Done card (:358), refreshable with `clearSkipped: true` (:371-374), no bottomBar |
| empty | false | false | **reachable** (fresh install) | "No Reminders yet" (:373) |
| empty | false | true | **reachable** (all hidden, none visible) | `emptyStateCopy(hasHidden: true)` → "Nothing due" (`ContentViewModel.swift:58-74`) |
| `empty ∧ allSkipped=true` | — | — | **unreachable** (proven: `allSkipped` requires `!reminders.isEmpty` at `ReminderStore.swift:138-140`) | N/A |

**Branch priority**: `allSkipped` checked first (:358) — wins over `hasHidden` when reminders non-empty but all skipped.

### Watch Branch Order (`WatchReminderView.swift:77-91`)

| Condition | Renders |
|---|---|
| `isShowingCompletionTransition` (ghost) | All-Done card (:82-83, def :155-160) |
| `visibleReminders.first` exists | First card (:84-85) |
| else (empty) | No-Reminders (:86-88), subtitle `hasHidden ? "Nothing due…" : "No Reminders yet"` (:169) |

### Widget Branch Order (`NextThingWidget.swift:55-95`)
**Different from iOS and watch**: auth checked first, empty checked *before* all-skipped.

| Condition | Entry State | Order |
|---|---|---|
| `authorizationStatus ≠ .fullAccess` | `.noAccess` | 1st (:55-58) |
| `allSkipped == true` (but only reachable from non-empty) | `.allDone` | 3rd (:83-87) — checked **after** `.empty` |
| `reminders.isEmpty` | `.empty(hasHidden)` | 2nd (:74-79) — checked **before** `.allDone` |
| has visible first card | `.reminder(ReminderDisplay)` | 4th (:89-95) |

**Divergence**: widget checks `isEmpty` before `allSkipped`, but `allSkipped` requires non-empty (so no unreachable path). However, the ordering *flips*: on iOS, `allSkipped` outranks empty-subtitle selection; on widget, `isEmpty` outranks `allSkipped` in the entry state enum — semantically equivalent but structurally divergent (risk: future changes to one branch ordering may miss the others).

Rendering consumes `NextThingEntry.State` via exhaustive `switch` (:140) — enum defined :10-14.

## Cluster 3: Entitlement Gate

### State Vector
| Field | Type | Source |
|---|---|---|
| `EntitlementStore.isEntitled` | Bool | `EntitlementStore.swift:54` |
| `EntitlementStore.hasResolvedEntitlement` | Bool | `EntitlementStore.swift:60` |
| `completionCounter.count` | Int | `CompletionCounterStore.swift:24-27` |
| `canMutate` | computed Bool | `ReminderStore.swift:144-145` |

`canMutate = entitlementStore.isEntitled || completionCounter.count < 100` (strict `<`, no named constant)

### Reachability Matrix — iOS Bottom Bar (`ContentView.swift:615-645`)

| `hasResolvedEntitlement` | `isEntitled` | `count` | `canMutate` | Renders |
|---|---|---|---|---|
| false | false | any | false | `EmptyView()` (:626-627) — unresolved, show nothing |
| true | false | < 100 | true | Mic/action cluster (:628-633) |
| true | false | ≥ 100 | false | Upgrade prompt (:629-630, `UpgradePromptButton` `PurchaseSettingsView.swift:174-196`) |
| true | true | any | true | Mic/action cluster |

### Reachability Matrix — Watch Card (`WatchReminderView.swift:219-224`)

| `canMutate` | `entitlementState.isEnabled` | Renders |
|---|---|---|
| false | false | Static "Upgrade on your iPhone" (:219-224, def :139-153) |
| true | false | Live buttons (silent no-op mutations) |
| false | true | Live buttons (silent no-op mutations) |
| true | true | Live buttons (functional) |

**Boundary**: at exactly 100 the gate closes — `count < 100` not `<= 100`. Test coverage: `ReminderStoreGateTests.swift:18-38`.

**No named constant**: literal `100` scattered across `ReminderStore.swift:145`, `WatchAppViewModel.swift:27`, `ReminderStoreGateTests.swift:25,31,45,58,83,132`, `ReminderStoreTests.swift:591`, `SingleThreadUITestsFlows.swift:640,662,674,701`.

## Cluster 4: Dictation State

### State Vector
| Field | Type | Source |
|---|---|---|
| `DictationViewModel.isDictating` | Bool | `DictationViewModel.swift:22` |
| `DictationViewModel.dictationText` | String | `DictationViewModel.swift:23` |
| `DictationViewModel.dictationError` | String? | `DictationViewModel.swift:24` |
| `DictationViewModel.creationFeedback` | `CreationFeedback?` | `DictationViewModel.swift:25` |
| `ReminderDictation.isRecording` | Bool | `ReminderDictation.swift:107` |

### Reachability Matrix

| `isDictating` | `isRecording` | `dictationText` | `dictationError` | `creationFeedback` | Reachability | Renders |
|---|---|---|---|---|---|---|
| false | false | "" | nil | nil | **reachable** (idle) | Mic button |
| true | true | live text | nil | nil | **reachable** (actively recording) | Live text + pulsing recording indicator (`ContentView.swift:615-622`) |
| true | false | partial | nil | nil | **reachable** (gap: mic tore down, parse/add/sleep still running — `isDictating` only cleared in `finally` :87) | "Recording" indicator shown but mic not capturing |
| true | — | — | ≠nil | nil | **reachable** (error during dictation) | Error wins render (`ContentView.swift:606-610`) |
| true | — | — | — | `.success`/`.failure` | **reachable** (feedback window, 1 s after speech ends :81-82) | Feedback icon while still dictating (`ContentView.swift:612-613`) |
| false | true | — | — | — | **unreachable** (proven: `isRecording` true only while `prepareRecording` succeeds :93; teardown resets :94, :153; no path sets `isRecording` without `isDictating` first) | N/A |

**Key finding**: `isDictating` remains true during the 1 s feedback window after speech ends (`finally` block :87), so the UI shows "Recording" when the mic is not capturing. `isRecording` is false during parse/add phases after teardown (:94) but `isDictating` still true.

**`showMicrophoneButton=false`**: suppresses mic-holders only, not error/recording/feedback branches. Watch has no dictation UI.

## Divergence Sites: App Group vs `.standard`

### Divergence Site Index (11 sites)

| # | Site | Description | Source |
|---|---|---|---|
| 1 | Phone service store construction | `AppViewModel.swift:31-37` — service built with default (App Group) stores | `AppViewModel.swift:31-37` |
| 2 | Watch service explicit `.standard` | `WatchAppViewModel.swift:155-161` — 7 stores injected `.standard`, `SkippedReminderStore()` left default | `WatchAppViewModel.swift:155-161` |
| 3 | Phone @AppStorage pinned App Group | `ContentView.swift:115-132` — 11 keys use `store: AppGroup.defaults` | `ContentView.swift:115-132` |
| 4 | Phone preference observer diffs group only | `AppViewModel.swift:380-392` — `UserDefaults.didChangeNotification` on `AppGroup.defaults`, diffs only 5 `lastShow*` | `AppViewModel.swift:368-400` |
| 5 | Widget reads true App Group | `NextThingWidget.swift:61-73` — widget runs with group entitlement, no fallback | `NextThingWidget.swift:59-73` |
| 6 | Watch launch restore `.standard` | `WatchAppViewModel.swift:31,37` — `SortOptionStore().load()`/`ShowUndatedRemindersPreference(defaults: .standard)` | `WatchAppViewModel.swift:30-37` |
| 7 | Watch count asymmetry | Service counter `.standard` (:161) vs receive write `AppGroup.defaults` (:186) vs UI-test seed `AppGroup.defaults` (:27) vs store default `AppGroup.defaults` | `WatchAppViewModel.swift:27,161,186` |
| 8 | Phone seed unclamped count | `AppViewModel.swift:294` — `AppGroup.defaults.set(count)` unclamped | `AppViewModel.swift:294` |
| 9 | Reset clears both suites | `UITestingSeed.swift:52-58` — wipes both `.standard` and App Group | `UITestingSeed.swift:52-58` |
| 10 | PendingCompletionStore doc | `PendingCompletionStore.swift:7-11` — notes watchOS no-App-Group fallback | `PendingCompletionStore.swift:7-11` |
| 11 | Test stores isolate suites | `EntitlementSyncTests.swift:124-127` — UUID keys "never touches `AppGroup.defaults`" | `EntitlementSyncTests.swift:124-127` |

### Watch Double-Persistence Detail

For five `show*` keys on the watch receive path (excluding `showUndatedReminders` and `showCompletionGlow` which each have their own pattern):

1. Service store writes `.standard` via `SkippedReminderSyncService.swift:337-359` (stores injected `.standard`)
2. Hook's `Show*State.apply()` writes `.standard` again via `preference.set(value); isEnabled = value` (`ShowDateState.swift:25-28`, identical in all five)

Each `Show*State` constructs its own `Show*Preference(defaults: .standard)` (:30) independently of the service store — same key, same suite, two writers.

### Watch Counter Echo Risk

Watch `pushAll()` reads counter from its `.standard` store at `WatchAppViewModel.swift:161`. Phone receive writes counter to `AppGroup.defaults` at `WatchAppViewModel.swift:186`. On a group-registered watch, these are different containers — the watch can echo a stale `.standard` counter value back to the phone's App Group.

## Open Areas (Not Asserted)

| Area | Reason |
|---|---|
| Group-registered watch behavior | All watch tests run `.standard` because `AppGroup.defaults` falls back (`AppGroup.swift:10-14`); real cross-container divergence is unverifiable on simulator |
| Second `EntitlementStore` on watch | `WatchAppViewModel.swift:162` — a never-read instance inside the service; interplay with `canMutate` only partially traced |
| `--ui-testing-live-excluded` interaction | `WatchAppViewModel.swift:237-246` injects WC context 5 s post-launch; phone-side receive hooks only partially traced |
| Phone receipt of non-`pushAll` contexts | Watch `allSends* = false` (`WatchAppViewModel.swift:154-163`); unverified whether any other path could push a mis-handled context |
```

### Verification

#### Automated
- [ ] Every `reachable` combo's `path` note resolves in `factbase.tsv` — grep each cited `file:line` from every reachable row
- [ ] Every `unreachable(proven)` claim: the stated impossibility is verified by checking no write path exists in `factbase.tsv` that could produce the claimed vector (e.g. `empty ∧ allSkipped`: `allSkipped` requires `!reminders.isEmpty` per `ReminderStore.swift:138-140`)
- [ ] All four cluster matrices have zero bare `undefined` cells (only the four listed open areas are marked undefined)
- [ ] All 11 divergence sites carry `file:line` citations that resolve in Stage 2's `inventory.md`
- [ ] `bash audit/verify-citations.sh` still exits 0

#### Manual
- [ ] Walk the completion-transition reachability path: read `WatchReminderViewModel.swift:66-86`, verify the `true,nil` row is correctly proven unreachable
- [ ] Walk the allSkipped impossibility: read `ReminderStore.swift:138-140`, confirm `allSkipped` requires non-empty reminders
- [ ] Verify widget branch ordering divergence: compare `NextThingWidget.swift:55-95` against `ContentView.swift:355-455` and `WatchReminderView.swift:77-91`
- [ ] Spot-check 3 divergence site citations against source

---

## Phase 4: Enum assessment — advisory pointers + top-candidate sketches

### Changes

#### 1. Create `audit/enums.md`
**File**: `.pi/qrspi/<branch>/audit/enums.md`
**Action**: create

**Content structure**:

```markdown
# Enum Assessment

## Overview

All bare-Bool/Int clusters are enumerated. Only the three highest-value
candidates receive full enum sketches; the rest get advisory pointers
with `file:line` citations per decision #3.

## Enum Sketch 1: CompletionTransition (watchOS)

**Replaces**: `isShowingCompletionTransition` (Bool) + `transitionReminder` (EKReminder?) + `CompletionGlow.isActive` (Bool)
**Sources**: `WatchReminderViewModel.swift:47,51`, `CompletionGlow.swift:21`

### Sketch

```swift
enum CompletionPhase: Equatable {
  case resting
  case completing(reminder: EKReminder, glowActive: Bool)
  // buffer window: glow expired, card still shown
  case completing(reminder: EKReminder, glowActive: Bool) // glowActive=false = buffer
}
```

Note: `completing(reminder:glowActive:)` captures both the glow-active and buffer (glow-expired-but-card-shown) states with a single case + Bool parameter. The `transitionReminder?` and flag Bool collapse into one optional associated value.

### Transition logic sketch

```swift
private var completionPhase: CompletionPhase = .resting

func completeCurrentReminder() {
  guard completionPhase == .resting else { return }
  guard let snapshot = store.visibleReminders.first else { return }
  let glowActive = showCompletionGlowState.isEnabled
  completionPhase = .completing(reminder: snapshot, glowActive: glowActive)
  if glowActive { glow.trigger() }
  Task {
    // ... EventKit work ...
    try? await Task.sleep(for: .seconds(0.5 + 0.5))
    completionPhase = .resting
  }
}
```

### Patterns
- **Persistence**: none — transient watch-only state; no rawValue/CaseIterable/defaultsKey needed
- **Presentation**: extension on the enum in the watch app target (presentation-concern separation)

## Enum Sketch 2: EntitlementGate (iOS + watchOS)

**Replaces**: `isEntitled` (Bool) + `hasResolvedEntitlement` (Bool) + `completionCounter.count` (Int) + magic literal `100`
**Sources**: `EntitlementStore.swift:54,60`, `CompletionCounterStore.swift:24-27`, `ReminderStore.swift:144-145`

### Sketch

```swift
enum EntitlementTier {
  case unresolved
  case freemium(completionsUsed: Int, cap: Int)
  case unlimited
  // or: case premium — naming bikeshed deferred

  var canMutate: Bool {
    switch self {
    case .unresolved: false
    case .freemium(let used, let cap): used < cap
    case .unlimited: true
    }
  }
}
```

### Constants extract

```swift
extension EntitlementTier {
  static let freemiumCap = 100  // single source of truth
}
```

### Patterns
- **Persistence**: `EntitlementStore` remains StoreKit-derived (not persisted); `completionCount` remains persisted as Int; the tier is computed from `isEntitled + count < cap`
- **Presentation**: on the enum (app-target type) or in extension for Core-owned — if Core owns, present in extension
- **Round-trip**: not applicable (computed, not persisted); the `completionCount` Int retains its current `CompletionCounterStore` persistence

## Enum Sketch 3: EmptyState (iOS + widget)

**Replaces**: `allSkipped` (computed Bool) + `hasHidden` (Bool) + `reminders.isEmpty` (implicit) + per-target branch ordering
**Sources**: `ReminderStore.swift:62,138-140`, `ContentView.swift:355-455`, `NextThingWidget.swift:55-95`, `WatchReminderView.swift:77-91`

### Sketch

```swift
enum ListContent {
  case noAccess
  case empty(hasHiddenSubtle: Bool)
  case allDone
  case reminder(ReminderDisplay)
}
```

This is effectively the widget's `NextThingEntry.State` (:10-14) generalized — the widget already has this enum but only within its own process. The sketch proposes extracting it to Core so all three targets consume the same enum.

### Patterns
- **Persistence**: none — derived/computed; no rawValue/CaseIterable needed
- **Presentation**: extension in Core (Core is SwiftUI-free); each target renders the enum with exhaustive `switch` per the widget's pattern (`NextThingWidget.swift:140`)

## Advisory Pointers (Full Enum Sketches NOT Produced)

### `show*` Bool cluster (6 keys)
**What**: `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders` — each is a separate Bool with its own wrapper struct, fallback, and dual-read path.
**Why not sketched**: The consolidation refactor (collapsing 6 × `Show*Preference` + `ShowUndatedRemindersPreference` into a single generic struct) is a higher-priority structural cleanup; turning them into an enum adds a dimension the struct consolidation should address first.
**Pointers**: `ShowDatePreference.swift:20`, `ShowListPreference.swift:20`, `ShowRecurrencePreference.swift:20`, `ShowAlarmsPreference.swift:20`, `ShowCompletionGlowPreference.swift:19-21`, `ShowUndatedRemindersPreference.swift:19`, `ShowDateState.swift:25-28` (×5 identical double-persistence), `ContentView.swift:121-132` (@AppStorage declarations).

### Dictation two-machine state
**What**: `isDictating` + `isRecording` + `dictationText` + `dictationError` + `creationFeedback` — five fields across two machines.
**Why not sketched**: The core divergence (`isDictating` outliving `isRecording`) is a timing-path bug, not a state-model gap; a state enum would not fix the overlap window. The fix is structural (pull `isDictating=false` into the `isRecording` teardown path), not a refactor.
**Pointers**: `DictationViewModel.swift:22-25,62-87`, `ReminderDictation.swift:93-94,107-109,153`.

### `BackgroundFade` Int namespace
**What**: `backgroundFadePercent: Int` with step=10, clamp 0...90, no enum cases. Already has `BackgroundFade.allValues` stride + `opacity(for:)`.
**Why not sketched**: The `BackgroundFade` namespace is already well-structured (case-less, Int range, computed opacity); converting to an enum would not improve type safety and would add persistence complexity for a single-key value.
**Pointers**: `BackgroundFade.swift:13-36`, `ContentView.swift:89`.

### Watch refresh UI flags
**What**: `isRefreshing` + `isShowingRefreshConfirmation` — two transient Bools.
**Why not sketched**: Two-state transient UI flags with straightforward clear paths; no combinatorial risk beyond the normal `isRefreshing`→`isShowingRefreshConfirmation`→clear sequence.
**Pointers**: `WatchReminderViewModel.swift:43-44`.
```

### Verification

#### Automated
- [ ] Three enum sketches present (count sections titled "Enum Sketch N:" = 3)
- [ ] Each sketch's `replaces` fields resolve as real keys in `factbase.tsv` — grep each field name
- [ ] Advisory pointers section enumerates all remaining bare-Bool/Int clusters from research Q4: `show*` ×6, dictation, `BackgroundFade`, watch refresh flags
- [ ] `bash audit/verify-citations.sh` still exits 0

#### Manual
- [ ] Sketch 1 (`CompletionTransition`) adheres to patterns: no persistence needed (transient watch-only), presentation on extension
- [ ] Sketch 2 (`EntitlementGate`) adheres to patterns: `canMutate` computed from enum, single `freemiumCap` constant
- [ ] Sketch 3 (`EmptyState`) mirrors widget's existing `NextThingEntry.State` shape (:10-14) generalized
- [ ] No full enum sketched for advisory-pointer items — pointers only, no case lists

---

## Phase 5: Severity ranking + prioritized action list

### Changes

#### 1. Create `audit/findings.md`
**File**: `.pi/qrspi/<branch>/audit/findings.md`
**Action**: create

**Content structure**:

```markdown
# Findings — Severity-Ranked

## Tier Classifications

| Tier | Label | Criteria |
|---|---|---|
| T1 | Reachable Contradiction/Data Loss | A reachable code path produces state the app cannot correctly interpret, or data can be silently lost |
| T2 | Cross-Target Divergence | Two targets disagree on what a key means or where it lives; same logical value lands in different containers depending on process |
| T3 | Dual-Read-Path Drift | Two read paths for the same key can observe different values within the same process lifetime |
| T4 | Hygiene / Naming / Doc Drift | Naming, documentation, or structural issues that don't directly cause incorrect behavior |

## T1: Reachable Contradictions

### T1.1 — Completion-transition: `isDictating` outlives `isRecording`
**Tier**: T1
**Evidence**: `DictationViewModel.swift:87` (isDictating cleared only in `finally`), `ReminderDictation.swift:94` (isRecording cleared early in `defer` teardown)
**Description**: The UI can show a "Recording" indicator for up to 1 second while the microphone is not capturing audio. `isDictating` is set true at `DictationViewModel.swift:62` and cleared in `finally` at `:87` (after 1 s sleep `:81-82`), but `isRecording` is cleared by the `defer` block at `ReminderDictation.swift:94` when `prepareRecording()`'s scope exits — before the parse/add/sleep phases. During the gap, `isDictating=true ∧ isRecording=false`: the UI renders the recording indicator but no speech is being captured.
**Action**: Pull `isDictating=false` into the `isRecording` teardown path so the UI never shows "Recording" when the mic is off. Separate ticket.

### T1.2 — Watch counter echo: stale `.standard` value pushed to phone's App Group
**Tier**: T1
**Evidence**: `WatchAppViewModel.swift:161` (pushAll reads `.standard` counter), `WatchAppViewModel.swift:186` (receive writes `AppGroup.defaults`)
**Description**: On a group-registered watch, the phone writes `completionCount` into App Group; the watch receive hook also writes into App Group. But the watch's `pushAll()` reads from its `.standard` counter, which can hold a stale value from a prior receive cycle. The stale value can echo back, effectively rolling back the count.
**Action**: Unify the watch counter to a single container. Requires the group-registered watch harness (new test target). Separate spike ticket.

## T2: Cross-Target Divergence

### T2.1 — AppGroup-vs-`.standard` namespace collapse
**Tier**: T2
**Evidence**: `AppGroup.swift:10-14`, `WatchAppViewModel.swift:155-161`, `ContentView.swift:115-132`
**Description**: `AppGroup.defaults` is literally `.standard` when the group entitlement is absent (watchOS, previews, unregistered simulators). The watch explicitly pins 7 stores to `.standard`. On iOS, 11 keys live in the group container; on watchOS, the same logical keys live in `.standard` — the same logical value exists under one name across two containers depending on process. This is the root cause of the counter echo (T1.2) and the watch double-persistence.
**Action**: Top refactor candidate. Decide target topology (single suite? group on both? hybrid?) in a design-phase spike. The group-registered watch harness is a prerequisite. Separate spike + refactor tickets.

### T2.2 — Branch ordering divergence: widget checks empty before allSkipped
**Tier**: T2
**Evidence**: `ContentView.swift:355-455`, `WatchReminderView.swift:77-91`, `NextThingWidget.swift:55-95`
**Description**: iOS checks `allSkipped` before rendering empty-state copy; the widget checks `isEmpty` before `allSkipped` when building `NextThingEntry.State`. Semantically equivalent today (no unreachable path), but structurally divergent — future changes to one ordering may miss the others.
**Action**: Converge on a single `ListContent` enum (see Enum Sketch 3). Deferred to refactor ticket.

### T2.3 — Watch double-persistence on show* receive
**Tier**: T2
**Evidence**: `SkippedReminderSyncService.swift:337-359`, `ShowDateState.swift:25-28` (×5 identical)
**Description**: Received `showDate`/`showList`/`showRecurrence`/`showAlarms`/`showCompletionGlow` values are written twice into `.standard` — once by the service store and again by the hook's `Show*State.apply()`. Redundant but currently harmless because both writers target the same key-suite pair.
**Action**: Collapse to one write path during the sync-contract refactor.

### T2.4 — `showCompletionGlow` straddles suites
**Tier**: T2
**Evidence**: `ContentView.swift:132` (iOS stores in group), `AppViewModel.swift:247` (iOS reset removes from `.standard`), `ShowCompletionGlowState.swift:20` (watch pins `.standard`)
**Description**: iOS writes `showCompletionGlow` to App Group, but the reset seam removes it from `.standard`. On watchOS, the key lives in `.standard`. The key effectively exists in different suites depending on the writing process.
**Action**: Resolved by the suite-migration refactor (T2.1).

## T3: Dual-Read-Path Drift

### T3.1 — 12 keys with dual read paths
**Tier**: T3
**Evidence**: `ContentViewModel.swift:45-49` (`enableActionButtons`), `AppViewModel.swift:127,131-132` (`notificationsEnabled`/`intervalHours`), `AppDelegate.swift:53-56` (`allowsLandscape`), `AppearanceMode.swift:79-86` (`appearanceMode`), plus all 7 `show*` wrapper reads
**Description**: 12 keys are read through both `@AppStorage` (which SwiftUI observes) and a raw `UserDefaults.*` call. In normal operation both read the same underlying value, but `@AppStorage` refreshes on `UserDefaults.didChangeNotification` while raw reads reflect the value at call time. A write that lands after `@AppStorage`'s last observed notification but before a raw read could produce a transient divergence.
**Action**: Converge each key to a single read path during the refactor. Deferred.

## T4: Hygiene

### T4.1 — Magic literal `100` for freemium cap
**Tier**: T4
**Evidence**: `ReminderStore.swift:145`, `WatchAppViewModel.swift:27`, `ReminderStoreGateTests.swift:25,31,45,58,83,132`, `ReminderStoreTests.swift:591`, `SingleThreadUITestsFlows.swift:640,662,674,701`
**Description**: The freemium cap `100` is a bare literal scattered across 7+ sites with no named constant. The boundary is strict `<` (gate closes at exactly 100), and any future refactor must preserve this semantics.
**Action**: Extract `static let freemiumCap = 100` to a single source of truth. Deferred to the refactor ticket. Tests that reference the literal must update to use the constant.

### T4.2 — Doc drift: `AppGroup.swift:2-4` comment stale
**Tier**: T4
**Evidence**: `AppGroup.swift:2-4` — doc lists only skipped-reminder identifiers; suite actually carries 11 group keys
**Action**: Update doc comment to list all payload keys or link to the inventory. Deferred.

### T4.3 — Doc drift: `AppViewModel.swift:211` glow duration wrong
**Tier**: T4
**Evidence**: `AppViewModel.swift:211` — comment says production glow is 0.25 s; actual default is 0.50 (`CompletionGlow.swift:26`)
**Action**: Correct the comment. Deferred.

### T4.4 — 6 × duplicated `Show*Preference` structs
**Tier**: T4
**Evidence**: `ShowDatePreference.swift`, `ShowListPreference.swift`, `ShowRecurrencePreference.swift`, `ShowAlarmsPreference.swift`, `ShowCompletionGlowPreference.swift`, `ShowUndatedRemindersPreference.swift`
**Description**: Six near-identical structs each with hand-written `init(defaults:key:)` + `load()`/`save()` + per-key fallback values that differ (true/true/true/false/false/true/true). `SortOptionStore.swift:22-49` is the canonical prototype.
**Action**: Consolidate into a single generic `BoolPreferenceStore` parameterized by key + default. Deferred to refactor ticket.

### T4.5 — `--seed` writes unclamped `completionCount`
**Tier**: T4
**Evidence**: `AppViewModel.swift:294` — `AppGroup.defaults.set(count, forKey:)` with arbitrary Int from seed JSON
**Description**: The `--seed` seam writes `completionCount` directly without clamping. Production only ever writes `count+1`, `max(0,count-1)`, or reset-0 (`CompletionCounterStore.swift:24-47`). Negative values read as 0-equivalent (0-defaulted `integer(forKey:)`) and huge values are gated-off under `< 100`, but the persisted value itself is outside production's domain. The seed seam exists to set up gating scenarios (e.g. 99 for near-cap, 100 for gated); the unclamped write is intentional but undocumented.
**Action**: Document the seed's unclamped-count behavior. Optionally clamp in the seed path to the counter's domain. Deferred.

## Prioritized Action List

Items for the refactor ticket (deferred per decision #1):

1. **Spike**: Group-registered watch harness — prerequisite for verifying cross-container behavior. Requires new test target + pbxproj changes.
2. **Spike**: Sync contract redesign — decide the target topology for App Group vs `.standard`, the union-vs-replace semantics, and the watch counter source-of-truth.
3. **Refactor**: Unify suite topology (T2.1, T2.4).
4. **Refactor**: Collapse 6 × `Show*Preference` into generic `BoolPreferenceStore` (T4.4).
5. **Refactor**: Converge dual-read-path keys to single read path (T3.1).
6. **Refactor**: Fix `isDictating`/`isRecording` overlap (T1.1).
7. **Refactor**: Unify watch counter container (T1.2).
8. **Refactor**: Extract `ListContent` enum for branch ordering (T2.2).
9. **Refactor**: Collapse watch double-persistence to single write (T2.3).
10. **Refactor**: Name the freemium cap constant (T4.1).
11. **Hygiene**: Fix doc comments — `AppGroup.swift:2-4` (T4.2), `AppViewModel.swift:211` (T4.3).
12. **Hygiene**: Document `--seed` unclamped count (T4.5).
```

### Verification

#### Automated
- [ ] Ordering invariant: no T2 finding appears before a T1 finding; no T3 before a T2; no T4 before a T3 — grep for tier labels and verify monotonic ordering
- [ ] Every finding cites ≥1 `factbase.tsv` entry — grep each `Evidence` file:line reference against `factbase.tsv`
- [ ] Every cluster from Stage 3 has at least one finding: completion-transition (T1.1), branch-ordering (T2.2), entitlement gate (T4.1), dictation (T1.1)
- [ ] Action list items are flagged as *deferred/separate ticket*, not in-scope for this ticket
- [ ] `bash audit/verify-citations.sh` still exits 0

#### Manual
- [ ] Tier definitions are consistent: T1 = data-loss/reachable contradiction, T2 = cross-target divergence, T3 = dual-read drift, T4 = hygiene
- [ ] T4.4 (6 × Show*Preference) does not accidentally claim a data-loss risk
- [ ] The action list names deferred tickets: constant for `100`, the two doc drifts, the sync-contract spike, the group-registered-watch harness — flagged as *future* tickets per decision #1

#### 2. Create `audit/index.md`
**File**: `.pi/qrspi/<branch>/audit/index.md`
**Action**: create

```markdown
# SingleThread State Audit — Assembled Report

## Artifacts

1. **[Fact Base](factbase.tsv)** — citation-verified source index. One row per declaration/read/write of every state value across all four targets, pinned to `file:line` + exact source text. Verified by `verify-citations.sh`.

2. **[Inventory](inventory.md)** — per-key tables (default, encoding, read/write sites, dual-read paths, targets) and store-mirror table (which `@Observable` property mirrors which persisted key; transient vs mirrored).

3. **[Clusters & Divergence](clusters.md)** — four combinatorial cluster matrices (completion-transition, branch ordering, entitlement gate, dictation) marking every combination reachable/unreachable/contradiction, plus 11 App Group vs `.standard` divergence sites.

4. **[Enum Assessment](enums.md)** — three concrete enum sketches for the highest-value clusters (completion-transition, entitlement gate, branch ordering) with advisory pointers for the remaining bare-Bool/Int clusters.

5. **[Findings](findings.md)** — severity-ranked findings (T1–T4) with evidence citations from the fact base, plus a prioritized action list mapping to deferred tickets.

## Verification

Run `bash audit/verify-citations.sh` from the `audit/` directory. Exit 0 means every cited `file:line` still matches source.

Run `bash audit/verify-citations-self-test.sh` to confirm the verifier catches deliberate corruption.

## Scope

This is a **read-only audit**. No code changes land in this ticket. All findings, enum sketches, and the action list inform a separately-ticketed refactor.
```

### Verification

#### Automated
- [ ] `audit/index.md` links all four layer artifacts (factbase.tsv, inventory.md, clusters.md, enums.md, findings.md)
- [ ] All five linked files exist in the `audit/` directory

#### Manual
- [ ] Read `audit/index.md` as a landing page — all links work, scope statement is clear

---

## Final Gate

Before declaring the audit complete, run the final verification suite:

- [ ] `bash audit/verify-citations.sh` exits 0 (all citations pinned to source, no drift)
- [ ] `bash audit/verify-citations-self-test.sh` exits 0 (verifier catches corruption)
- [ ] Inventory cite-check passes: all `inventory.md` file:line refs ⊆ `factbase.tsv`
- [ ] Cluster matrices fully annotated: zero bare `undefined` cells (only listed open areas)
- [ ] Three enum sketches only; `replaces` fields resolve
- [ ] Findings tier ordering monotonic: T1 before T2 before T3 before T4
- [ ] `index.md` links all five artifacts
- [ ] `./scripts/test.sh` remains green (app is untouched by design)
