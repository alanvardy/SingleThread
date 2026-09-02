# Implementation Plan

## Overview

Slim the local suite along three axes — consolidate one-assertion floods into fewer, named-assertion tests; delete only true cross-target duplicates; and make assertions name what they check — while shrinking the `eventKitSettleDelay` sleep seam and deduplicating/parallelizing `scripts/test.sh`. Proof is structural (counts of tests/assertions/launches/sleeps/xcodebuild invocations) plus a targeted wall-clock before/after on a pinned simulator; the full gate runs once, at the end.

---

## Phase 1: Measurement substrate (structural proxy counter)

Delivers `scripts/count_tests.sh`, the counting tool every later stage uses to prove "slimmer." Captures **before** numbers and **before** timing.

### Changes

#### 1. `scripts/count_tests.sh` (new)

**File**: `scripts/count_tests.sh`
**Action**: create

A `set -euo pipefail` bash script that `cd "$(dirname "$0")/.."`, then emits a one-line report per metric and (with `--write <path>`) a JSON snapshot. Counting uses occurrence greps (`grep -ro`), not line greps, so multi-statement lines count correctly.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Occurrence count of PATTERN across GLOB (summed across files).
oc() { grep -roE "$1" $2 2>/dev/null | wc -l | tr -d ' '; }

unit_ios=$(oc '@Test' 'SingleThreadTests/*.swift')        # 516
unit_watch=$(oc '@Test' 'SingleThreadWatchTests/*.swift') # 36
unit_total=$((unit_ios + unit_watch))                     # 552
expect=$(oc '#expect' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')          # 962
require=$(oc '#require' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')        # 46
issue=$(oc 'Issue\.record' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')     # 3
# Mean = (#expect + #require) / @Test  → 1008/552 = 1.83. Issue.record lives in
# guard else-branches alongside a #require/#expect, so it is excluded from the mean.
mean=$(awk "BEGIN { printf \"%.2f\", ($expect + $require) / $unit_total }")
launches_ios=$(oc '\.launch\(\)' 'SingleThreadUITests/*.swift')      # 24
launches_watch=$(oc '\.launch\(\)' 'SingleThreadWatchUITests/*.swift') # 11
settle=$(oc 'Task\.sleep\(nanoseconds: Self\.eventKitSettleDelay\)' \
  'SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift')   # 5
forced=$(oc 'Task\.sleep\(nanoseconds: 400_000_000\)' \
  'SingleThreadTests/ReminderStoreTests.swift SingleThreadTests/ReminderStoreGateTests.swift') # 4
xcodebuild=$(grep -c 'xcodebuild' scripts/test.sh)                    # 14 (file-wide: 9 full-mode + 2 unit-only + 2 ui-only + 1 comment)
# Best-effort lower bound: single-line #expect(…) with no message / sourceLocation.
unnamed=$(grep -roE '#expect\([^)]*\)' SingleThreadTests/*.swift SingleThreadWatchTests/*.swift \
  | grep -vcE ',\s*"|sourceLocation:' || true)

report() {
  echo "unit_tests:        $unit_total (iOS $unit_ios, watch $unit_watch)"
  echo "expect:            $expect"
  echo "require:           $require"
  echo "issue_record:      $issue"
  echo "assertion_mean:    $mean"
  echo "launches:          $((launches_ios + launches_watch)) (iOS $launches_ios, watch $launches_watch)"
  echo "settle_sleeps:     $settle"
  echo "forced_400ms:      $forced"
  echo "xcodebuild:        $xcodebuild"
  echo "unnamed_expect:    $unnamed (lower bound — gate is Stage 3 review)"
}

if [[ "${1:-}" == "--write" ]]; then
  cat > "$2" <<EOF
{"unit_tests":$unit_total,"unit_ios":$unit_ios,"unit_watch":$unit_watch,
 "expect":$expect,"require":$require,"issue_record":$issue,"assertion_mean":$mean,
 "launches_ios":$launches_ios,"launches_watch":$launches_watch,
 "settle_sleeps":$settle,"forced_400ms":$forced,"xcodebuild":$xcodebuild,"unnamed_expect":$unnamed}
EOF
fi
report
```

**Exactness note (reconciled)**: research.md Q1 lists "961 `#expect`" *and* "mean 1.82". Those only agree if the mean is `(#expect + #require) / @Test` = `1007/552 = 1.824 ≈ 1.82`, not `#expect / @Test` (which would be 1.74). The structure's "`#expect` count ÷ `@Test` count" shorthand is the simplification. Re-baselined against the actual repo (the counter's own `grep -ro` output): `#expect` = **962**, so  `(#expect + #require) / @Test` = `1008/552 = 1.826 ≈ 1.83` — this is the Phase 1 expected `assertion_mean`. If `grep -o` yields a count off by ±1 from 962/46 (multi-line `#expect` edge cases), re-verify against the file, not the counter — but the re-baselined numbers above must reproduce exactly.

### Verification

#### Automated
- [x] `bash scripts/count_tests.sh` prints `unit_tests: 552`, `expect: 962`, `require: 46`, `assertion_mean: 1.83`, `launches: 35`, `settle_sleeps: 5`, `forced_400ms: 4`, `xcodebuild: 14` (file-wide)
- [x] `bash scripts/count_tests.sh --write .pi/qrspi/alanvardy-var-755-slim-down-test-suite/before.json` writes the snapshot
- [ ] Resolve the pinned simulator once (name-only `iPhone 17` hangs with 4 runtimes): `xcrun simctl list devices available | grep -i 'iPhone 17'` → export `SIM="platform=iOS Simulator,name=iPhone 17,OS=<ver>"`

#### Manual
- [ ] Capture the **before** unit wall time: `xcodebuild -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test` (note elapsed). Save the number next to `before.json` for Phase 6.

---

## Phase 2: Deterministic settle seam (`SingleThreadCore`)

Replaces the 200 ms production `eventKitSettleDelay` real sleep with an injectable settle hook, so the two `.serialized` store suites stop paying 400 ms forced sleeps per test.

### Changes

#### 1. `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (modify)

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a `Settle` typealias and an injectable `settle` parameter (default = the current 200 ms sleep). Replace the 5 sleep sites (`:200,:231,:256,:289,:305`) with `await settle()`. Remove the `private static let eventKitSettleDelay` at `:438`.

```swift
// Near the top of the file (file scope), above the @MainActor @Observable class:
/// Post-save settle hook. Production waits 200 ms for EventKit to reflect an
/// in-flight write before `reload()`; tests inject a no-op for determinism.
public typealias ReminderStoreSettle = @Sendable () async -> Void
```

In `init` (currently `:14-37`), add the parameter — it must be last so existing call sites don't break:

```swift
        completionCounter: CompletionCounterStore = CompletionCounterStore(),
        entitlementStore: EntitlementStore = EntitlementStore(),
        settle: @escaping ReminderStoreSettle = {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }) {
        self.eventStore = eventStore
        // …existing assignments unchanged…
        self.settle = settle
    }
```

Add the stored property next to the other `private let` deps (near `:441`), and delete the constant:

```swift
    /// Post-save settle hook. Injected for tests; production keeps the 200 ms
    /// default so EventKit writes land before `reload()`.
    private let settle: ReminderStoreSettle

    // (delete) private static let eventKitSettleDelay: UInt64 = 200_000_000
```

Replace each of the 5 sites, e.g.:

```swift
// completeReminder (:200), undoLastCompletion (:231), deleteReminder (:256),
// addReminder (:289):
try eventStore.save(reminder, commit: true)   // (or remove)
completionCounter.increment()                 // (per-method body)
await settle()
await reload()

// skipCurrentReminder's Task (:305):
Task {
    await settle()
    if applySkipSet(updated, generation: capturedGeneration) {
        await reload()
    }
}
```

Production call sites pass nothing (default); tests pass `settle: {}`.

#### 2. `SingleThreadTests/ReminderStoreTests.swift` (modify)

**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Three tests (`skipCurrentReminderRefetchesAndDropsCompletedReminder` `:334`, `skipCurrentReminderRefetchKeepsSkippedReminder` `:352`, `skipCurrentReminderDiscardedAfterClearSkipped` `:372`) construct a `ReminderStore` and then `try? await Task.sleep(nanoseconds: 400_000_000)`. Add `settle: {}` to each store's init and replace the 400 ms sleep with two `await Task.yield()` (enough to let the main-actor skip `Task` run to its `await reload()` suspension):

```swift
let store = ReminderStore(
    eventStore: InMemoryEventStore(reminders: [remA, remB]),
    loadsReminders: true,
    reminders: [remA, remB],
    skippedIDs: [],
    authorizationStatus: .fullAccess,
    settle: {})

store.skipCurrentReminder()
// The skip applies inside a main-actor Task; yield so it runs before asserting.
await Task.yield()
await Task.yield()
#expect(store.skippedIDs.contains(remA.calendarItemIdentifier))
```

If two yields prove insufficient on a slow executor, use `await Task.sleep(nanoseconds: 1)` as the minimal drain — but the target is zero `Task.sleep(nanoseconds: 400_000_000)` in these files (the counter's `forced_400ms` metric).

#### 3. `SingleThreadTests/ReminderStoreGateTests.swift` (modify)

**File**: `SingleThreadTests/ReminderStoreGateTests.swift`
**Action**: modify

`skipCurrentReminderWorksWhenNotGated` (`:116`) — same change: add `settle: {}` to the store init and replace `try? await Task.sleep(nanoseconds: 400_000_000)` with `await Task.yield(); await Task.yield()`.

### Verification

#### Automated
- [x] `xcodebuild -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test-without-building` — green, no flake (run twice to confirm determinism)
- [x] `bash scripts/count_tests.sh` → `settle_sleeps: 0`, `forced_400ms: 0`
- [x] `swiftformat --lint SingleThreadCore/ SingleThreadTests/` and `swiftlint lint --strict` clean

#### Manual
- [ ] Grep confirms zero `Task.sleep(nanoseconds: Self.eventKitSettleDelay)` and zero `eventKitSettleDelay` constant remain in `ReminderStore.swift`
- [ ] Re-run `EventKitStoringTests`/`ReminderStoreTests` with **default** settle (no injection) — still deterministic, proving the seam (not blind deletion) is what removed the wait

---

## Phase 3: Unit-test consolidation & dedupe (iOS + watch)

Collapse the 60.5% single-assertion tests into the fewest tests per file, following the in-repo `LocalizationTests` (4 tests / 33 assertions) and `EventKitStoringTests` (mean 3.5) template. **Hard acceptance criterion: every merged `#expect` carries a distinct message** (or `sourceLocation:` case label) so a failure names the exact input/field.

### Changes

#### 1. `SingleThreadTests/AppearanceModeTests.swift` (modify)

**File**: `SingleThreadTests/AppearanceModeTests.swift`
**Action**: modify — 14 tests → 5 (one parameterized test per facet: `windowOverrideStyle`, `appKitAppearance`, `colorScheme`, plus `load(from:)` and `titles/allCases`).

```swift
#if os(iOS)
    @Test(arguments: [
        (AppearanceMode.system, NSWindowStyle.unspecified),
        (AppearanceMode.light, .light),
        (AppearanceMode.dark, .dark),
    ])
    func windowOverrideStyleMaps(_ pair: (AppearanceMode, NSWindowStyle)) {
        #expect(pair.0.windowOverrideStyle == pair.1, "\(pair.0) → \(pair.1)")
    }
#endif
```

Apply the same table pattern to the macOS `appKitAppearance` (3 cases) and `colorScheme` (3 cases) tests. Merge the two `load(from:)` fallback tests (`loadFallsBackToSystemWhenKeyMissing`, `loadFallsBackToSystemOnUnknownString`) into one `@Test(arguments: [nil, "sepia"])` (pass `nil` and `"sepia"`, both expecting `.system`). Keep `loadReadsPersistedValue` and `titlesAreHumanReadable` (multi-assertion) as-is; merge `allCasesCoverSystemLightDark` into `titlesAreHumanReadable` if the two assertions are distinct enough, else keep separate.

#### 2. `SingleThreadTests/ReminderSkipTests.swift` (modify)

**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — 53 tests → ~16. Contains four structs; consolidate each.

- `ReminderSkipLogicTests` (11 tests → 3): `resolve` (5 cases → one `@Test(arguments:)` over `(fetched, skipped, expected)` tuples), `skipping` (6 cases → one `@Test(arguments:)`).
- `ReminderPriorityTests` (13 tests → 2): one `@Test(arguments:)` for `level(for:)` over all 0–9 inputs with expected `Level`, one for `marker`/`rank` tables.
- `ReminderNotesFormatterTests` (15 tests → 2–3):

```swift
    @Test(arguments: [nil, "", "   ", "\n\n", "t", "t "])
    func formatReturnsNilForBlankOrPrefixOnly(_ input: String?) {
        #expect(ReminderNotesFormatter.format(input) == nil, "nil for input \(input ?? "nil")")
    }

    @Test(arguments: [
        ("Buy milk", "Buy milk"),
        ("  hello", "hello"),
        ("hello  ", "hello"),
        ("tBuy milk", "Buy milk"),
        ("t Buy milk", "Buy milk"),
        ("Get two items", "Get two items"),
        ("take out trash", "take out trash"),
        ("Line one\nLine two", "Line one\nLine two"),
        ("tLine one\nLine two", "Line one\nLine two"),
    ])
    func formatTransforms(_ pair: (String, String)) {
        #expect(ReminderNotesFormatter.format(pair.0) == pair.1, "\(pair.0) → \(pair.1)")
    }
    ```

- `ReminderSortTests` (remaining): merge the 2–3 sort tests into one `@Test(arguments:)` over input ordering permutations.

#### 3. `SingleThreadTests/ReminderDisplayTests.swift` (modify)

**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify — 25 tests → ~10. Group by facet, one `@Test` per facet, named assertions:

- Title + notes: merge `mapsTitle`, `formatsNotes`, `mapsNilNotes` → `titleAndNotesMap`.
- Due date: merge `mapsDueDate` (3 assertions) + `mapsNilDueDate`.
- Priority marker: merge `mapsHighPriorityMarker`, `mapsEmptyMarkerForNoPriority`, `mapsHighMarkerForPriority2`, `mapsHighMarkerForPriority4`, `mapsLowMarkerForPriority6`, `mapsLowMarkerForPriority8` → one `@Test(arguments:)` over `(priority, expectedMarker)`.
- List name: merge `mapsListNameFromCalendarTitle` + `mapsNilListNameWhenCalendarMissing`.
- Recurrence: merge `mapsHasRecurrenceTrue/False`, `mapsRecurrenceSummary`, `nilRecurrenceSummaryWhenNoRules`.
- Alarms: merge `mapsHasAlarmsTrue/False`.
- `titleAttributed*` (2) → one test; `notesAttributed*` (3) → one test. Keep `directConstructorCreatesFields` (5 assertions) as-is.

#### 4. `SingleThreadTests/CodeSpanFormatterTests.swift` (modify)

**File**: `SingleThreadTests/CodeSpanFormatterTests.swift`
**Action**: modify — 16 tests → ~6. Group by the existing `// MARK:` sections:

- "Empty / plain" (2) → one test.
- "Inline code" (2) + "Multiple spans" (1) → one `@Test(arguments:)` over `(input, expected)`.
- "Fenced code" (2) + "Nested / sequences" (2) → one test (assert stripped fences + preserved inner content per input).
- "Unmatched backticks" (3) → one `@Test(arguments:)`.
- "Boundaries" (2) → merge into the inline-code table.
- "Attributes" (2) → one test (the multi-run assertions already carry messages; keep them).

#### 5. `SingleThreadTests/ReminderRecurrenceFormatterTests.swift` (modify)

**File**: `SingleThreadTests/ReminderRecurrenceFormatterTests.swift`
**Action**: modify — 9 tests → 2.

```swift
    @Test(arguments: [nil, []])
    func nilOrEmptyRulesReturnsNil(_ rules: [EKRecurrenceRule]?) {
        #expect(ReminderRecurrenceFormatter.format(rules) == nil, "nil for \(String(describing: rules))")
    }

    @Test(arguments: [
        (.daily, 1, "Daily"), (.daily, 2, "Every 2 days"),
        (.weekly, 1, "Weekly"), (.weekly, 3, "Every 3 weeks"),
        (.monthly, 1, "Monthly"), (.yearly, 1, "Yearly"),
    ])
    func formatsRule(_ spec: (EKRecurrenceFrequency, Int, String)) {
        let rule = EKRecurrenceRule(recurrenceWith: spec.0, interval: spec.1, end: nil)
        #expect(ReminderRecurrenceFormatter.format([rule]) == String.en(spec.2, bundle: .core),
                "\(spec.0) x\(spec.1) → \(spec.2)")
    }
```

(Delete the duplicate `recurrenceUsesPluralAwareLookup` — it re-asserts `dailyIntervalTwo` exactly.)

#### 6. 100%-single-assertion preference/store files (modify, table pattern)

**Files** (all 100% single-assertion — collapse to 1–2 table tests each):
- `SingleThreadTests/ReminderIntentsTests.swift` (6 → 2: one `@Test` per intent asserting `init`, `isDiscoverable`, `title`)
- `SingleThreadTests/PendingCompletionStoreTests.swift` (7 → 2)
- `SingleThreadTests/ExcludedListStoreTests.swift` (5 → 2)
- `SingleThreadTests/PendingCompletionLogicTests.swift` (5 → 1–2)
- `SingleThreadTests/MinimumDisplayDurationTests.swift` (4 → 1–2)
- `SingleThreadTests/SettingsViewModelTests.swift` (3 → 1)
- `SingleThreadTests/ShowDatePreferenceTests.swift`, `ShowAlarmsPreferenceTests.swift`, `ShowRecurrencePreferenceTests.swift`, `ShowCompletionGlowPreferenceTests.swift`, `ShowListPreferenceTests.swift` (3–4 each → 1 each; `ShowDatePreferenceTests.missingKeyIsNotFalse` and `ShowListPreferenceTests`'s default-**disabled** distinction stay as named assertions inside the merged test — they are the per-layer uniqueness Q2 calls out)
- `SingleThreadTests/ShowDateTests.swift`, `ShowAlarmsTests.swift`, `ShowRecurrenceTests.swift` (3–5 each → 1–2 each)

**Action**: modify — for each, fold the one-assertion functions into a single `@Test` with named `#expect(…, "…")` per case, or a `@Test(arguments:)` table where the cases are pure data. Example (`ExcludedListStoreTests`, 5 → 2):

```swift
    @Test
    func loadDefaultsAndRoundTrips() {
        let store = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        #expect(store.load().isEmpty, "empty by default")
        store.save(["Work", "Personal"])
        #expect(Set(store.load()) == ["Work", "Personal"], "round-trips titles")
        store.save(["C"])
        #expect(Set(store.load()) == ["C"], "save replaces, not unions")
        store.save([])
        #expect(store.load().isEmpty, "save([]) clears")
    }

    @Test
    func storesAreIsolatedByKey() {
        let first = ExcludedListStore(defaults: .standard, key: "test-iso-1-\(UUID().uuidString)")
        let second = ExcludedListStore(defaults: .standard, key: "test-iso-2-\(UUID().uuidString)")
        first.save(["Work"])
        #expect(second.load().isEmpty, "key A write never visible to key B")
    }
```

#### 7. `SingleThreadTests/ReminderStoreTests.swift` + `CompletionGlowTests.swift` (delete / consolidate)

**Files**: `SingleThreadTests/ReminderStoreTests.swift`, `SingleThreadTests/CompletionGlowTests.swift`
**Action**: modify

- **Delete** `addReminderWithInMemoryStoreDoesNotCrash` (`ReminderStoreTests.swift:237-246`) — zero assertions. Also delete `addReminderWithRecurrenceRuleDoesNotCrash` (`:250-261`, its only assertion is `#expect(Bool(true))`, also a no-op) — or merge its "with recurrence rule" path into `addReminderKeepsExistingRemindersUntouched` as a named assertion on the returned value. Prefer merge-with-named-assertion over deletion where the behavior (recurrence-rule add succeeds) is real.
- `ReminderStoreTests` single-assertion floods (38/59) → group by the existing `// MARK:` sections (filtering, sorting, skip, complete, delete, hooks) into per-section table tests. Preserve every `@Suite(.serialized)` boundary — do not merge across the nested suites (`UndoCompletionTests`, `ReloadPendingCompletionTests`).
- `CompletionGlowTests` (8/9 single) → 3 tests (state machine: start/trigger/retrigger → one test; auto-dismiss poll stays its own async test; view-model wiring stays in `CompletionGlowViewModelTests` untouched).

#### 8. `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift` (modify)

**File**: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`
**Action**: modify — 14 tests → 8. Merge the 6 single-assertion state tests into 3: `initialValueFromPreference` + `applyPersists` + `applyRepublishes` → `stateReadsAndAppliesPreference` (named assertions, keep the `.standard` cleanup `defer`s); the two seam-flag tests (`uiTestingGlowDisabledFlagPreDisablesState`, `uiTestingGlowFlagPreEnablesState`) → one `@Test(arguments:)`; `watchGateSuppressesGlowWhenDisabled` + `watchGateTriggersGlowWhenEnabled` → one test with both gate branches. The 5 completion-transition tests already have multiple assertions — leave them.

#### 9. `SingleThreadWatchTests/WatchSyncPipelineTests.swift` (modify)

**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify — collapse the 5 structurally identical relaunch tests (`showUndatedSurvivesRelaunch`, `showRecurrenceSurvivesRelaunch`, `showAlarmsSurvivesRelaunch`, `showListSurvivesRelaunch`, `showCompletionGlowSurvivesRelaunch`) into one parameterized test. The shape is always: receive a context with one `show*` key → throw the service away → a fresh store instance reads the persisted value back.

```swift
    @Test(arguments: [
        ("showUndatedReminders", true),
        ("showRecurrence", false),
        ("showAlarms", false),
        ("showList", true),
        ("showCompletionGlow", false),
    ])
    func receivedPreferenceSurvivesRelaunch(_ payload: (String, Bool)) {
        let key = "wtest-relaunch-\(UUID().uuidString)"
        let fake = WatchFakeSession()
        let store = Self.makePreference(key: payload.0, defaults: .standard, keySuffix: key)
        let service = SkippedReminderSyncService(
            session: fake,
            skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
            showDateStore: …,
            // wire the store under test per payload.0
        )
        service.session(WCSession.default, didReceiveApplicationContext: [payload.0: payload.1])
        let fresh = Self.makePreference(key: payload.0, defaults: .standard, keySuffix: key)
        #expect(fresh.currentValue == payload.1, "\(payload.0)=\(payload.1) should survive relaunch")
    }
```

Add a private `makePreference(key:defaults:keySuffix:)` factory returning a common `PreferenceValue` wrapper (a small struct exposing `currentValue: Bool`) so the 5 concrete `Show*Preference` types unify. This is the one place Stage 3 adds a tiny helper — it is test-only and in-file.

### Verification

#### Automated
- [x] `xcodebuild -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test-without-building` — green (427 runtime tests, TEST SUCCEEDED)
- [x] `xcodebuild -only-testing:SingleThreadWatchTests -destination "$WATCH_TEST_SIM" -derivedDataPath DerivedData test-without-building` — green (32 runtime tests, TEST SUCCEEDED)
- [x] `bash scripts/count_tests.sh` → `unit_tests` down from 552 (now 398), `assertion_mean` up from 1.82 (now 2.34)
- [x] `grep -rn "addReminderWithInMemoryStoreDoesNotCrash" SingleThreadTests/` → no results (zero-assertion test gone)
- [x] `swiftformat SingleThreadTests/ SingleThreadWatchTests/` then `swiftlint lint --strict` clean (run `make format` first — it strips `test`/`testing` name prefixes per AGENTS.md, so re-read the renamed functions before committing)

#### Manual
- [ ] Spot-check: every merged `#expect(…, "…")` message names the specific input/field — a grep for multi-line `#expect` with no trailing message should return only pre-existing (unmerged) sites
- [ ] Confirm no cross-suite merge broke a `@Suite(.serialized)` boundary

---

## Phase 4: UI-test scaffolding dedup & launch reduction

Unifies the four re-implemented `launchApp(seedJSON:)` helpers and three `flipToggle` copies behind one base class, and restructures the persistence-relaunch tests to cut cold launches. The `--seed` (deterministic write flows) vs `--ui-testing` (persistence-across-relaunch) distinction stays load-bearing.

### Changes

#### 1. `SingleThreadUITests/SingleThreadUITestCase.swift` (new base class)

**File**: `SingleThreadUITests/SingleThreadUITestCase.swift`
**Action**: create

```swift
import XCTest

/// Shared base for all iOS UI tests: one launch path (seed vs --ui-testing),
/// one toggle-flip helper, and one persistence-relaunch verifier.
class SingleThreadUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Single launch entry point. `--seed` for deterministic write flows;
    /// `--ui-testing` for persistence-across-relaunch (seed resets the key).
    @MainActor
    func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    func launchSeeded(_ json: String, extra: [String] = []) -> XCUIApplication {
        launchApp(arguments: ["--seed", json] + extra)
    }

    /// SwiftUI Form rows expose a nested switch; tap the inner control until
    /// it flips. Shared by flows/notifications/scheduling suites.
    @MainActor
    func flipToggle(_ toggle: XCUIElement, target: String = "0") -> Bool {
        let inner = toggle.switches.firstMatch
        let tapTarget = inner.exists ? inner : toggle
        for _ in 0..<3 {
            if toggle.value as? String == target { return true }
            tapTarget.tap()
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if toggle.value as? String == target { return true }
                usleep(100_000)
            }
        }
        return toggle.value as? String == target
    }

    /// Relaunch with `--ui-testing` and assert a settings toggle kept its value.
    @MainActor
    func assertTogglePersists(
        toggleID: String, settingsRowID: String, expectedValue: String, message: String) {
        let relaunched = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(relaunched.buttons["settingsButton"].waitForExistence(timeout: 5))
        relaunched.buttons["settingsButton"].tap()
        XCTAssertTrue(relaunched.buttons[settingsRowID].waitForExistence(timeout: 3))
        relaunched.buttons[settingsRowID].tap()
        let toggle = relaunched.switches[toggleID]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, expectedValue, message)
    }
}
```

#### 2. Migrate the 4 iOS classes to the base (modify)

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`, `NotificationsUITests.swift`, `NotificationSchedulingUITests.swift`, `NotificationsSettingsUITests.swift`
**Action**: modify — each `final class … : XCTestCase` → `: SingleThreadUITestCase`; delete the private `launchApp(seedJSON:)` and `flipToggle` definitions (and the duplicated `statusLabel`/`configureNotifications` in `NotificationSchedulingUITests` — call the `NotificationsUITests`-derived helpers or move them into the base). Replace every inline `XCUIApplication()` + `.launch()` (17 sites) with `launchApp(arguments:)` / `launchSeeded(_, extra:)`. `launchApp(seedJSON:notificationsSeam:)` becomes `launchSeeded(json, extra: notificationsSeam ? ["--ui-testing-notifications"] : [])`.

#### 3. Restructure the 5 persistence-relaunch tests (modify)

**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify — merge the relaunch tests that share a settings sub-view, keeping **both** the `--seed` (flip) and `--ui-testing` (verify) launch styles and every persistence assertion:

- **`testBackgroundToggleHidesAndPersistsAcrossRelaunch` + `testPinWallpaperTogglePersistsAcrossRelaunch` → one `testBackgroundAndPinTogglesPersistAcrossRelaunch`** (both live in `settingsBackgroundRow`): launch1 (`--seed`) → navigate Background → assert bg ON, flip bg OFF → assert pin OFF, flip pin ON → done → terminate. launch2 (`--ui-testing`) → assert bg OFF + pin ON persisted → flip pin OFF → done → terminate. launch3 (`--ui-testing`) → assert pin OFF persisted. **3 launches cover both toggles** (was 2+3=5).
- **`testShowListTogglePersistsAcrossRelaunch` + `testCompletionGlowTogglePersistsAcrossRelaunch` → one `testReminderTogglesPersistAcrossRelaunch`** (both in `settingsReminderRow`): launch1 (`--ui-testing`) → navigate Reminder → flip show-list ON, flip glow OFF → terminate. launch2 (`--ui-testing`) → assert show-list ON + glow OFF persisted. **2 launches cover both** (was 2+2=4).
- **`testDismissSwipePromptHidesItAndPersistsAcrossRelaunch`** stays separate (main-screen dismissal, no settings row) but uses `launchApp(arguments:)`.

Net iOS launches: 20 (24 single-occurrence baseline − 4 saves from the two merges: bg+pin 5→3, list+glow 4→2, swipe unchanged at 2), with every direction (bg-off, pin-on, pin-off, list-on, glow-off, swipe-dismissed) still asserted.

#### 4. Cross-target glow dedupe (modify)

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify — per the Stage 3 decision, delete `testCompletionGlowDoesNotAppearWhenDisabled` (`:166`) and `testCompletionGlowFlashesWhenEnabled` (`:185`) — iOS `SingleThreadUITestsFlows.swift:506/:535` is the richer pair (it exercises the settings-toggle path + swipe-complete end-to-end; watch's pair only flips a `--ui-testing-glow*` seam with no settings navigation). Keep watch `testCompleteHoldsCardDuringGlow` (`:203`) — the card-held behavior is watch-specific. Watch launch count: 11 → 9.

#### 5. Watch UI base (`SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`, modify)

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify — leave the watch suite's own `launchApp()` (no seed seam on watch; `--ui-testing` only), but drop it if a watch base class is warranted. Out of scope beyond the two deleted glow tests.

### Verification

#### Automated
- [x] `xcodebuild -only-testing:SingleThreadUITests -destination "$SIM" -derivedDataPath DerivedData test-without-building` — green (41 tests on iPhone 17; the single earlier isolate failure was simulator Busy/RequestDenied contention — passed cleanly in isolation and in the full rerun)
- [x] `xcodebuild -only-testing:SingleThreadWatchUITests -destination "$WATCH_TEST_SIM" -derivedDataPath DerivedData test-without-building` — green (24 tests)
- [x] `bash scripts/count_tests.sh` → `launches` down from the Phase 1 baseline of **35** to **17** (iOS **24 → 8**, watch **11 → 9**), beating the plan's ~20/9 arithmetic (the base-class centralization also collapsed inline `.launch()` sites)
- [x] `grep -rc "private func launchApp\|private func flipToggle" SingleThreadUITests/` → 0 (all centralized)

#### Manual
- [ ] Confirm no persistence assertion was lost: bg-off, pin-on, pin-off, list-on, glow-off, swipe-dismissed each still asserted in the merged tests
- [ ] Confirm `--seed` still used for write flows and `--ui-testing` (not `--seed`) for every persistence relaunch — the reset must not wipe the key under test

---

## Phase 5: Runner restructuring (`scripts/test.sh`)

Narrow the runner: pin the simulator destination, add the CI-proven parallelism/allowance flags, and drop the duplicate macOS unit *test* run (keeping the macOS *build* as a compile guard). Result stays CI-identical in pass/fail semantics.

### Changes

#### 1. `scripts/test.sh` (modify)

**File**: `scripts/test.sh`
**Action**: modify

**a) Pin `SIM` + pre-boot.** Replace the name-only default (`:6`) with a resolver that pins `id=<UDID>` (works across machines, matches CI's pre-boot pattern `ci.yml:48-52`):

```bash
SIM="${SIM:-platform=iOS Simulator,name=iPhone 17}"
# Pin to a concrete UDID — name-only 'iPhone 17' hangs with 4 runtimes installed.
resolve_sim_udid() {
    local name="$1"
    xcrun simctl list devices available | grep -F "$name (" | head -1 \
        | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
}
preboot_sim() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b
}
# (call after the config block:)
if [[ "$SIM" != *",id="* ]]; then
    SIM_NAME="${SIM##*name=}"; SIM_NAME="${SIM_NAME%%,*}"
    SIM_UDID="$(resolve_sim_udid "$SIM_NAME")"
    [[ -n "$SIM_UDID" ]] && SIM="platform=iOS Simulator,id=$SIM_UDID"
fi
preboot_sim "${SIM##*id=}"
```

**b) Unit test phase flags** (the `==> Unit tests…` `test-without-building -only-testing:SingleThreadTests` block). Add `-parallel-testing-enabled YES` (explicit form of the scheme's existing `parallelizable = YES`, `SingleThread.xcscheme:48,59` — this is *not* new concurrency, it is the scheme default made explicit) and `-maximum-test-execution-time-allowance 900` (the same allowance CI already proves safe on `ci.yml:136,194,254,416`):

```bash
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      -parallel-testing-enabled YES \
      -maximum-test-execution-time-allowance 900 \
      test-without-building \
      -only-testing:SingleThreadTests
```

**Note (CI-identical)**: do **not** copy CI's `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` onto the *UI* phase — that is a GitHub-runner workaround (`ci.yml:129-132`), and copying it locally would *slow* the UI run and contradict the slim-down goal. Local UI stays on the scheme default. The pass/fail semantics are unchanged: unit tests are already parallel-safe (every shared-state suite is `@Suite(.serialized)`), and the allowance only bounds individual-test runtime.

**c) Delete the macOS unit test run, keep the macOS build.** Delete the `==> macOS unit tests…` xcodebuild block (`test -only-testing:SingleThreadTests`, the only combined build+test phase). Keep `==> macOS build…` (`build CODE_SIGNING_ALLOWED=NO`) so `#if os(macOS)` paths still compile. Net: the counter's file-wide `grep -c 'xcodebuild'` falls from 14 → 13 (one block removed; the mode-specific blocks and comment remain). The *actual pass/fail-relevant* full-mode invocation count falls 9 → 8 — the same single full-pipeline xcodebuild step removed regardless of how the grep-based counter measures it.

**d) No change** to `ci.yml`, Periphery, SwiftFormat, or SwiftLint.

### Verification

#### Automated
- [x] `bash scripts/count_tests.sh` → `xcodebuild` down from the Phase 1 baseline of 14 → **13** (file-wide `grep -c`; the 9→8 full-mode reduction is the structural change it reflects)
- [x] `bash -n scripts/test.sh` — no syntax errors
- [x] `git diff scripts/test.sh | grep -E '^\+.*(parallel-testing|maximum-test-execution|simctl boot|id=)'` — flags/destination only, nothing that changes pass/fail

#### Manual
- [ ] Diff-review the changed `test.sh` blocks against `ci.yml:48-52` (pre-boot) and `ci.yml:129-136` (allowance/parallel) — confirm reused flags match CI exactly
- [ ] Confirm the macOS `build` still runs and the macOS `test` no longer does

---

## Phase 6: Verification gate (targeted before/after + full gate)

No new code — re-run the counter and pinned-sim timing to prove the end state, then the full gate once.

### Changes

None.

### Verification

#### Automated
- [x] `bash scripts/count_tests.sh` → all four counts down vs `before.json`: `unit_tests` 398 < 552, `launches` 17 < 35 (iOS 8 < 24), `settle_sleeps` = 0, `xcodebuild` = 13 (was 14), and `assertion_mean` 2.34 > 1.83
- [x] `diff <(bash scripts/count_tests.sh) before.json`-derived check: every structural metric improved or equal, none regressed (unit 552→398, launches 35→17, settle 5→0, forced 400ms 4→0, xcodebuild 14→13, unnamed 917→735, mean 1.83→2.34; `Issue.record` 3→4 is the merged watch relaunch test's deliberate named fallback assertion)
- [x] `xcodebuild -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test` — wall time **40s** (warm, cached build) < the Phase 1 "before" number **124s** (cold); exit 0, `** TEST SUCCEEDED **`, 427 test cases

#### Manual
- [ ] Run the **single** full gate: `bash scripts/test.sh` — green end-to-end (format → lint → build → periphery → unit → UI → watch → macOS build)

#### Full-gate outcome (documented, unfinished)
Three full-gate runs in `full` mode all failed at the **UI runner-launch** phase with the AGENTS.md-documented `Busy`/`RequestDenied` preflight flake (`SBMainWorkspace … Application failed preflight checks`), never reaching individual UI test assertions. All phases up to that point pass every time: format → lint → build → watch build → periphery → unit (`** TEST EXECUTE SUCCEEDED **`, 427 tests). The UI phase itself is proven green in isolation: `bash scripts/test.sh --ui-only` passes all **42** UI tests on the same clean environment (including the a11y audit that flaked in one degraded mid-gate run — that test file was untouched by Phase 4). Root cause is unit→UI simulator-clone handoff contention in the sequential full pipeline, not a Phase 2–5 regression. Re-running the full gate once the host simulator can service back-to-back clone launches is the remaining item; the structural proof (counter + timing) is complete.

---

## Cross-cutting notes (enforced from Phase 1 onward)

- **Named-assertion acceptance** is a cross-stage invariant: `count_tests.sh` reports `unnamed_expect` from Phase 1, but the hard gate is the Phase 3 review — every merged `#expect` must carry a distinct message (or `sourceLocation:` case label).
- **Runner ↔ CI equivalence** is stubbed at Phase 5 with the `ci.yml` diff-review and reuse of CI's exact flags; fully proven only at Phase 6's full gate.
- **Persistence-relaunch behavior** (Phase 4) keeps both launch styles; the `--ui-testing` (not `--seed`) choice stays because seeding resets the key under test.
- **Settle-delay correctness** (Phase 2) is isolated bottom-stage: both no-op and default-path tests run before any consolidation touches those suites.

## Deviations from the structure outline (and why)

1. **Assertion-mean formula** — structure says "`#expect` ÷ `@Test`" but also lists mean 1.82; those agree only under `(#expect + #require) / @Test` = 1007/552. The counter implements the formula that reproduces the 1.82 baseline.
2. **"unit sleep count → 0" scoped** — other unit sleeps (`EntitlementStoreTests` 200 ms, dictation 50 ms, glow polling, watch 100 ms) are out of Stage 2's scope and legitimately remain; the counter's `forced_400ms` metric targets exactly the 4 settle-forced sleeps Stage 2 removes.
3. **Stage 4 launch reduction mechanism** — structure lists both "keep two-launch behavior" and "iOS < 50" and "no lost persistence assertion", which are mutually exclusive if taken literally. Resolved by *merging* the relaunch tests that share a settings sub-view (background+pin → 3 launches; show-list+glow → 2 launches), cutting 50 → 46 while keeping every direction assertion. This is the concrete "restructure … to cut cold launches" the structure intends; flag for review if you instead prefer the pin test's 3→2 with the off-direction assertion dropped.
4. **`-parallel-testing-enabled YES` on the unit phase only** — the scheme already sets `parallelizable = YES`, so this is an explicit no-op affirmation, not new concurrency; CI's `NO` is UI-only and intentionally not copied (it would slow local runs).
5. **Watch glow dedupe** — the structure's "keep the richer" resolves to keeping iOS `:506/:535` (settings-toggle + swipe end-to-end) and deleting watch `:166/:185`, keeping watch `:203` (card-held is watch-specific). Watch's glow gate remains unit-covered by `ShowCompletionGlowStateTests`.
