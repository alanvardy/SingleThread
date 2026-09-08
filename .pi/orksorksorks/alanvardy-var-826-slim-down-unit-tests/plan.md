# Implementation Plan — Slim down unit tests

## Overview

Reduce the unit-test surface to a smaller, cheaper-to-maintain suite that asserts
the same behaviors: centralize per-bundle test fixtures into one canonical file
per bundle, delete seam-identical cross-target copies and dead tooling, and split
brute-force multi-store test bodies into single-scenario tests — with no production
code, UI-suite, or target-topology changes, and a coverage guardrail at the end.

All line numbers below were verified against the working tree at HEAD `d216b6f`
(except where noted as "re-grep at edit time" — deletions shift line numbers).

**Verified-in-session destinations** (structure.md's `OS=18.4` is stale for this
machine):
- iOS: `platform=iOS Simulator,name=iPhone 17,OS=27.0` (UDID `1583C89D-E474-483E-A40C-2FDA4C0134CD`)
- watch: `Apple Watch Series 11 (46mm)` exists under both watchOS 26.5 and 27.0
  — `make watch-test` may hang on the ambiguous name; if so, override
  `WATCH_TEST_SIM='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0'`.

---

## Phase 1: Shared test-fixture files (Foundation)

Create one fixture file per bundle holding the single canonical copy of every
duplicated fake/fixture, delete the per-file copies, and update callers. This is
purely mechanical — same bodies, new home — with one change: every moved fixture
**drops its `private`/`fileprivate` and becomes module-internal** (that is what
makes it visible across the bundle). No new target; Xcode auto-discovers new
`.swift` files (objectVersion 77).

**Deviation from structure.md (flagged):** `inListReminder` is declared exactly
once per bundle (iOS 651–659, watch 568–576). The duplication is cross-target,
which this ticket keeps separate (no cross-bundle import). It is therefore **not
moved** in Phase 1. The watch copy is deleted in Phase 4 together with its only
consumer, `excludedTitlesRefreshFiltersVisibleReminders`. The iOS copy stays in
`SkippedReminderSyncServiceTests.swift` (its consumer is kept).

**Note on distinct single-owner helpers that stay put** (not byte-identical to
the canonical `makeReminder`, single declaration, own store — out of scope):
- `ReminderSkipTests.swift:255` `makeReminder(title:priority:dateComponents:calendarTitle:)`
- `RescheduleSheetTests.swift:53` `makeReminder(due:)`
- `UndoStoreTests.swift:50` `makeReminder()` (its own `private let eventStore`)
- `ReminderStoreTests.swift:915` `CompletedReturningEventStore.makeReminder` (protocol method)
- `EventKitStoringTests.swift:119` `FakeEventStore.makeReminder` (protocol method)
These are `private` members in their own types/files; they legally shadow the new
internal module-level `makeReminder` and are left untouched.

### Changes

#### 1. New canonical iOS fixture file
**File**: `SingleThreadTests/TestFixtures.swift`
**Action**: create

```swift
@testable import SingleThread
import EventKit
import SingleThreadCore
import Speech
import WatchConnectivity

// MARK: - Shared EKEventStore + reminder builders

/// A single `EKEventStore` kept alive to back the test reminders. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor let sharedTestEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
func makeReminder(
    title: String,
    priority: Int = 0,
    dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
func makeCalendar(title: String) -> EKCalendar {
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = title
    return calendar
}

/// Builds a reminder that lives in a calendar titled `list`, so exclusion
/// filtering (which matches `calendar.title`) can be exercised.
/// Construction only — never saved through EventKit.
@MainActor
func inListReminder(title: String, list: String) -> EKReminder {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = list
    reminder.calendar = calendar
    return reminder
}

// MARK: - Fake sync session

final class FakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var lastMessage: [String: Any]?
    var pushShouldThrow = false

    func activate() { activated = true }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow { throw NSError(domain: "test", code: 1) }
        lastContext = applicationContext
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler _: ((any Error) -> Void)?) {
        lastMessage = message
    }
}

// MARK: - Fake transcriber

/// Superset of the three former per-file fakes (`MicToggleFakeTranscriber`,
/// `ActionButtonFakeTranscriber`, `GlowFakeTranscriber`). Their
/// `requestAuthorization`/`transcribe` bodies were textually identical; this
/// keeps the full surface (`refreshCallCount`, `liveStatus`) so every former
/// consumer compiles unchanged.
@MainActor
final class TestFakeTranscriber: SpeechTranscribing {
    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        liveStatus = authorizationStatus
    }

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    /// The status `refreshAuthorizationStatus()` re-reads — the test mutates
    /// this to simulate a Settings change while the app is backgrounded.
    var liveStatus: SFSpeechRecognizerAuthorizationStatus

    private(set) var refreshCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func refreshAuthorizationStatus() {
        refreshCallCount += 1
        authorizationStatus = liveStatus
    }

    func transcribe(
        onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String {
        ""
    }
}

// MARK: - Background-fetcher fakes

final class FakeBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    var stubbedData: [URL: Result<Data, Error>] = [:]

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return try stubbedData[url]!.get()
    }
}

/// One-shot rendezvous that parks a fetch in-flight so a test can observe
/// `isRefreshing` before releasing it.
actor FetchGate {
    func wait() async {
        if wasHit { return }
        wasHit = true
        hitSignal?.resume()
        await withCheckedContinuation { parked = $0 }
    }

    func waitUntilHit() async {
        if wasHit { return }
        await withCheckedContinuation { hitSignal = $0 }
    }

    func open() {
        parked?.resume()
        parked = nil
    }

    private var parked: CheckedContinuation<Void, Never>?
    private var hitSignal: CheckedContinuation<Void, Never>?
    private var wasHit = false
}

/// Parks the first (endpoint) fetch behind a gate, then serves valid data.
final class GatedBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    init(endpointURL: URL) {
        self.endpointURL = endpointURL
    }

    let gate = FetchGate()
    var endpointData: Data = .init()
    var imageData: Data = .init()

    func fetchData(from url: URL) async throws -> Data {
        let isEndpoint = url == endpointURL
        if isEndpoint { await gate.wait() }
        return isEndpoint ? endpointData : imageData
    }

    private let endpointURL: URL
}

/// Serves the store's endpoint payload and photo so tests can seed a populated
/// store without touching the network.
final class SeededFetcher: BackgroundImageFetching, @unchecked Sendable {
    func fetchData(from url: URL) async throws -> Data {
        if url == Self.endpoint {
            let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
                + "\"photographer_url\":\"https://unsplash.com/@neom\"}"
            return Data(json.utf8)
        }
        return BackgroundTestFixtures.jpegData
    }

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!
}
```

#### 2. New canonical watch fixture file
**File**: `SingleThreadWatchTests/TestFixtures.swift`
**Action**: create

```swift
import EventKit
import SingleThreadCore
import WatchConnectivity

// MARK: - Shared watch EKEventStore + reminder builder

/// A single `EKEventStore` kept alive to back the test reminders. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

// MARK: - Fake session for testing

final class WatchFakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var pushShouldThrow = false

    func activate() { activated = true }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow { throw NSError(domain: "test", code: 1) }
        lastContext = applicationContext
    }

    func sendMessage(
        _: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler _: ((any Error) -> Void)?) {}
}
```

#### 3–13. Delete per-file copies (iOS bundle)

Each edit deletes only the fixture block; callers are unchanged because the
canonical names/signatures are identical. No new imports are required (same
module). Apply in any order; line numbers are HEAD positions.

| # | File | Delete |
|---|------|--------|
| 3 | `SingleThreadTests/ListContentTests.swift` | `sharedTestEventStore` (:5) and `makeReminder(title:)` (:83–88) |
| 4 | `SingleThreadTests/ReminderDisplayTests.swift` | `sharedTestEventStore` (:6) and `makeReminder(title:)` (:160–165, re-grep) |
| 5 | `SingleThreadTests/EventKitStoringTests.swift` | `sharedTestEventStore` (:557), `makeReminder(title:)` (:561–565), `makeCalendar(title:)` (:568–572). **Keep** `FakeEventStore.makeReminder` (:119). |
| 6 | `SingleThreadTests/ReminderStoreGateTests.swift` | `makeReminder(title:priority: = 5)` (:169–175) and `sharedTestEventStore` (:177) |
| 7 | `SingleThreadTests/ReminderStoreTests.swift` | `sharedTestEventStore` (:1122), `makeReminder(title:priority:dateComponents:)` (:1126–1134), `makeReminder(title:calendarTitle:)` (:1136–1143). **Keep** `CompletedReturningEventStore.makeReminder` (:915). |
| 8 | `SingleThreadTests/SkippedReminderSyncServiceTests.swift` | `FakeSession` (:15–38) and `inListReminder` (:648–659, incl. doc comment) |
| 9 | `SingleThreadTests/MicrophoneToggleTests.swift` | `MicToggleFakeTranscriber` (:10–42, incl. the `// MARK:` comment); rename its ~4 uses to `TestFakeTranscriber` |
| 10 | `SingleThreadTests/ActionButtonTests.swift` | comment (:99–100) + `ActionButtonFakeTranscriber` (:102–121); rename uses to `TestFakeTranscriber` |
| 11 | `SingleThreadTests/CompletionGlowTests.swift` | comment (:134–135) + `GlowFakeTranscriber` (:137–148); rename uses to `TestFakeTranscriber` |
| 12 | `SingleThreadTests/BackgroundImageStoreTests.swift` | `FakeBackgroundFetcher` (:438–446), `FetchGate` (:450–479), `GatedBackgroundFetcher` (:482–506). **Keep** `private static let endpoint/randomEndpoint/imageURL` (:508–510) — test bodies still use `Self.endpoint` etc. |
| 13 | `SingleThreadTests/SettingsViewTests.swift` | `SeededFetcher` (:416–435) |

For 9–11, the fake's `init(authorizationStatus:)` default and all members are a
superset, so call sites compile after a pure type-name replacement. Confirm each
site by grepping the old fake name after editing (must be zero hits).

#### 14–18. Delete per-file copies (watch bundle)

| # | File | Delete |
|---|------|--------|
| 14 | `SingleThreadWatchTests/ReminderStoreWatchTests.swift` | `sharedWatchEventStore` + SIGTRAP doc (:7–10) and `watchReminder(_:)` (:14–18) |
| 15 | `SingleThreadWatchTests/WatchReminderViewModelTests.swift` | `sharedWatchEventStore` + doc (:7–13) and `watchReminder(_:)` (:17–22). **Keep** `makeWatchReminderViewModel` (:28–51). |
| 16 | `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift` | `sharedWatchEventStore` + doc (:7–11) **only**. **Keep** its local no-arg `watchReminder()` (:15–20) — a distinct body (fixed title `"Buy groceries"`); it now resolves against the internal `sharedWatchEventStore`. |
| 17 | `SingleThreadWatchTests/WatchReminderViewRegressionTests.swift` | `sharedWatchEventStore` + doc (:7–15) **only**. **Keep** `canvasReminder()` (:19–26) (distinct body, resolves against internal `sharedWatchEventStore`). |
| 18 | `SingleThreadWatchTests/WatchSyncPipelineTests.swift` | `WatchFakeSession` (:9–29, incl. the "Private copy…" doc comment on :7). **Do not** touch `inListReminder` here (deleted in Phase 4). |

**Collision note (resolved):** the four `sharedWatchEventStore` declarations were
identical but file-private; moving one canonical internal copy and deleting the four
locals has no name collision (the locals no longer exist).

### Verification
#### Automated
- [x] `swiftformat --lint SingleThreadTests/ SingleThreadWatchTests/ && swiftlint lint --strict` clean (no unused-declaration warnings from moved fixtures)
- [x] iOS suites that consume moved fixtures:
    ```
    xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath DerivedData \
      -only-testing:SingleThreadTests/ReminderStoreTests \
      -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests \
      -only-testing:SingleThreadTests/MicrophoneToggleTests \
      -only-testing:SingleThreadTests/ActionButtonTests \
      -only-testing:SingleThreadTests/CompletionGlowTests \
      -only-testing:SingleThreadTests/BackgroundImageStoreTests \
      -only-testing:SingleThreadTests/SettingsViewTests \
      -only-testing:SingleThreadTests/ListContentTests \
      -only-testing:SingleThreadTests/ReminderDisplayTests \
      -only-testing:SingleThreadTests/ReminderStoreGateTests
    ```
- [x] `make watch-test` green (overrides `WATCH_TEST_SIM` with `,OS=27.0` if the name hangs)
- [x] `make periphery` clean (clean `DerivedData/` first) — moved fixtures show one declaration site

#### Manual
- [ ] `grep -rn "MicToggleFakeTranscriber\|ActionButtonFakeTranscriber\|GlowFakeTranscriber" SingleThreadTests/` returns nothing
- [ ] `grep -rn "sharedTestEventStore\|sharedWatchEventStore" SingleThreadTests/ SingleThreadWatchTests/` shows only the two canonical declarations (+ no `private` copies)

---

## Phase 2: Dead and rotten tooling removal

Standalone cleanups gated on the stable Phase 1 fixture landscape so
`count_tests.sh` comments describe the tree as it exists at this point.

### Changes

#### 1. Delete the dead UI base class
**File**: `SingleThreadUITests/SingleThreadUITestCase.swift`
**Action**: delete (65 lines; 0 subclasses; 0 external references — Periphery hides
it via `.periphery.yml:15-16`, so confirm the delete manually).

- [x] `grep -rn "SingleThreadUITestCase" .` returns nothing after deletion.
  (verified: zero references in code/config/scripts; only pre-existing
  `.pi/orksorksorks/*` historical research docs from other tickets mention the
  former class name — those are tracked docs, not live references; Periphery
  also reports "No unused code detected")

#### 2. Fix `count_tests.sh`
**File**: `scripts/count_tests.sh`
**Action**: modify

Regenerate each hardcoded trailing comment from a fresh run (the values below are
the fresh-run numbers verified at HEAD `d216b6f`), delete the two structurally-dead
pattern blocks, and add a note about the real settle. Output keys for the surviving
metrics stay stable.

Replace lines 8–24 region with:

```bash
unit_ios=$(oc '@Test' 'SingleThreadTests/*.swift')        # 521
unit_watch=$(oc '@Test' 'SingleThreadWatchTests/*.swift') # 44
unit_total=$((unit_ios + unit_watch))                     # 565
expect=$(oc '#expect' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')          # 1197
require=$(oc '#require' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')        # 73
issue=$(oc 'Issue\.record' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')     # 6
# Mean = (#expect + #require) / @Test  → 1270/565 = 2.25. Issue.record lives in
# guard else-branches alongside a #require/#expect, so it is excluded from the mean.
mean=$(awk "BEGIN { printf \"%.2f\", ($expect + $require) / $unit_total }")
launches_ios=$(oc '\.launch\(\)' 'SingleThreadUITests/*.swift')      # 2
launches_watch=$(oc '\.launch\(\)' 'SingleThreadWatchUITests/*.swift') # 1
# The real 200 ms settle lives at ReminderStore.swift:39 (typealias
# ReminderStoreSettle); it is injectable and tests use noopSettle /
# --ui-testing-noop-settle, so no fixed sleep-pattern metric is counted.
xcodebuild=$(grep -c 'xcodebuild' scripts/test.sh)                    # 11
```

Then delete the `settle=$(oc 'Task\.sleep…eventKitSettleDelay' …)` block and the
`forced=$(oc 'Task\.sleep…400_000_000' …)` block, the `settle_sleeps`/`forced_400ms`
`echo` lines in `report()`, and the `settle_sleeps`/`forced_400ms` keys in the
`--write` JSON block. The `unnamed=$(…)` line and everything else is unchanged.

### Verification
#### Automated
- [x] `make lint` clean
- [x] `make periphery` clean (confirm `SingleThreadUITestCase.swift` is gone)
- [ ] `bash scripts/count_tests.sh` — output has no `settle_sleeps`/`forced_400ms` lines; `unit_tests: 565`, `expect: 1197`, `require: 73`, `assertion_mean: 2.25`, `launches: 3`, `xcodebuild: 11`, `unnamed_expect: 1009`

#### Manual
- [ ] `git status` shows `SingleThreadUITests/SingleThreadUITestCase.swift` deleted

---

## Phase 3: Split brute-force multi-store tests

The 9 `@Test` bodies in `ReminderStoreTests.swift` that each build 2–4 stores
inline are split into single-scenario functions (2–4 each). Assertions are
preserved verbatim; only the multi-store bodies are partitioned. Every new test
uses `makeReminder`/`sharedTestEventStore`/`InMemoryEventStore` from Phase 1.

### Changes

#### 1. `SingleThreadTests/ReminderStoreTests.swift`
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify — replace each of the 9 bodies below with the listed single-scenario `@Test`s.

1. `visibleRemindersFiltersSkippedAndEmpty` (3 stores) →
   - `visibleRemindersFiltersSkippedReminder` — filtered store; `#expect(visible.count == 1)` + `#expect(visible.first?.title == "B")`
   - `visibleRemindersEmptyWhenAllSkipped` — allSkipped store; `#expect(visibleReminders.isEmpty)`
   - `visibleRemindersEmptyWhenNoReminders` — empty store; `#expect(visibleReminders.isEmpty)`

2. `visibleRemindersSortsByPriorityThenDate` (2 stores) →
   - `visibleRemindersSortsByPriorityAscending` — byPriority store; `#expect(map(\.title) == ["high", "low"])`
   - `visibleRemindersSortsDatedBeforeUndated` — byDate store; `#expect(map(\.title) == ["dated", "undated"])`

3. `visibleRemindersFiltersExcludedListTitles` (3 stores) →
   - `visibleRemindersFiltersExcludedListTitles` — excluded/kept store; `#expect(map(\.title) == ["B"])`
   - `visibleRemindersKeepsNilCalendarWhenListExcluded` — keepsNil store; `#expect(count == 1)`
   - `visibleRemindersEmptyWhenEveryListExcluded` — allExcluded store; `#expect(visibleReminders.isEmpty)`

4. `setSortOptionReordersAndNotifies` (3 stores) →
   - `setSortOptionDueDateReordersVisibleReminders` — reorderStore; both `#expect`s on default `.priority` then `.dueDate`
   - `setSortOptionFiresSortOptionAndRemindersChangedHooks` — hookStore; `#expect(received == .title)` + `#expect(remindersChanged)`
   - `setSortOptionNotifiesOncePerIdenticalSet` — idempotent store; `#expect(fired == 1)`

5. `skipCurrentReminderNoOpsAndNotifies` (3 stores) →
   - `skipCurrentReminderNoOpsWhenNoVisibleReminders` — empty store; `#expect(skippedIDs.isEmpty)`
   - `skipCurrentReminderSkipsVisibleReminder` — store with `rem`; `withCheckedContinuation` rendezvous + `#expect(skippedIDs.contains(rem.calendarItemIdentifier))`
   - `skipCurrentReminderFiresRemindersChangedHook` — hookStore; `withCheckedContinuation` only (resuming proves the hook fired)

6. `completeCurrentReminderCompletesVisibleAndNoOpsOtherwise` (3 stores) →
   - `completeCurrentReminderNoOpsWhenNoneVisible` — none store; `#expect(!completedNone)`
   - `completeCurrentReminderNoOpsWhenAllSkipped` — allSkipped store; `#expect(!completedSkipped)` + `#expect(reminders.count == 1)`
   - `completeCurrentReminderCompletesVisibleReminder` — visibleStore; `#expect(completedVisible)` + `#expect(rem.isCompleted)`

7. `lifecycleGuardsRespectLoadsRemindersFlag` (2 stores) →
   - `reloadResumesOnMainActorAfterOffMainFetch` — offMain store; `#expect(reminders.map(\.title) == ["A"])`
   - `loadsRemindersFalseNoOpsStartAndReload` — masked store; the 4 `#expect`s on `.showsUndatedReminders`, `.authorizationStatus`, and both `.reminders.isEmpty`

8. `hasHiddenReflectsSeedsAndSets` (2 stores + 2 static calls) →
   - `hasHiddenDefaultsToFalse` — store; `#expect(!store.hasHidden)`
   - `hasHiddenSeedsFromInit` — seeded store; `#expect(seeded.hasHidden)`
   - `hasHiddenForMatchesShownAndAllIncompleteSets` — the two `ReminderStore.hasHiddenFor(...)` assertions (false when sets match, true when one is hidden) in one test (pure-function checks, no stores)

9. `allSkippedReflectsState` (4 stores) →
   - `allSkippedTrueWhenAllRemindersSkipped` — allSkipped store; `#expect(allSkipped.allSkipped)`
   - `allSkippedFalseWhenNoReminders` — empty store; `#expect(!empty.allSkipped)`
   - `allSkippedFalseWhenVisibleReminderExists` — visible store; `#expect(!visible.allSkipped)`
   - `allSkippedTrueWhenEveryReminderExcluded` — excluded store; `#expect(excluded.allSkipped)`

Net effect: ~9 `@Test` deleted, ~26 `@Test` added (all single-scenario). Each uses
the shared `makeReminder`/`InMemoryEventStore` builders; `noopSettle` and
`seededCounter` are unchanged (not touched here).

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath DerivedData -only-testing:SingleThreadTests/ReminderStoreTests` green
- [ ] `make lint` clean — the file was 1143 lines; splits add lines, so confirm `file_length` disable (`.swiftlint.yml:33-35` warn 650/err 800) still applies; if not, note in PR

#### Manual
- [ ] No `#expect` was dropped: diff should show the same set of assertions, partitioned, with no new logic

---

## Phase 4: Delete seam-identical cross-target mirror (pair 2)

Cut the watch tests that re-prove the identical `InMemoryEventStore` seam the iOS
bundle already covers, where the only deltas are the fake-session name and the
`wtest-*` vs `test-*` key prefix. Keep watch-only receive tests and all of
`ReminderStoreWatchTests` (real `EKEventStore` seam).

### Changes

#### 1. `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify — delete these `@Test` functions (re-grep names at edit time;
delete whole function bodies):

- `receiveAppliesEveryPresentKey` — the 63-line mega-test that re-composes ~7 iOS
  split tests (skip/exclude/undated/sort/date/count/glow in one body + 12 `#expect`).
  iOS equivalents live in `SkippedReminderSyncServiceTests.swift`.
- `excludedTitlesRefreshFiltersVisibleReminders` — iOS twin
  `receivedExclusionRefreshFiltersVisibleReminders` (`SkippedReminderSyncServiceTests.swift:406-436`).
- `receiveSkipCountsSavesAndFiresHookOnWatch` — iOS twin
  `receiveSkipCountsSavesAndFiresHook` (`:606-624`).
- The file-level `inListReminder` (bottom of file) — now unreferenced (its only
  consumer was `excludedTitlesRefreshFiltersVisibleReminders`).

**Keep** — no iOS twin / distinct seam:
- `pushAllFromWatchOmitsShowDate`, `pushAllFromWatchOmitsShowListWhenFlagged`,
  `pushAllFromWatchIncludesSkipCountsAndOmitsPhoneOnlyKeys` — watch-only push
  behavior (phone-only keys omitted).
- `receiveAppliesShowRecurrenceAndShowAlarms`, `receiveAbsentRecurrenceAndAlarmsKeysAreNoOps`,
  `receiveAppliesShowList`, `receiveAbsentShowListKeyIsNoOp` — watch-only receive tests.
- `receiveAppliesShowCompletionGlow` — retained for now: showCompletionGlow has the
  broadest iOS key fan-in (7 files) but its watch **seam** pairing is asserted by the
  `ShowCompletionGlowStateTests` state-holder suite rather than a 1:1 sync twin; treat
  as watch-side coverage and keep unless the Phase-5 coverage diff shows otherwise.
- `receivedPreferenceSurvivesRelaunch` — relaunch-persistence shape (parameterized);
  no verbatim iOS twin of this exact shape.
- `receiveAbsentKeysAreNoOps` — absent-key no-op for the skip/exclude/sort/undated/date
  set; keep (mirrors but is not byte-verbatim to any single iOS body).
- `WatchEnableActionButtonsSyncTests` suite and the `PreferenceValue`/`makePreference`/
  `makeService` helpers.

`WatchFakeSession` now resolves to `TestFixtures.swift` (Phase 1).

### Verification
#### Automated
- [ ] `make watch-test` green (remaining watch tests); override `WATCH_TEST_SIM` with `,OS=27.0` if the name hangs
- [ ] `make lint` clean
- [ ] `make periphery` clean — no `inListReminder`/dead-symbol warning for the watch bundle
- [ ] Confirm the `WatchSyncPipelineTests` suite still has `@Test`s (it does — the `pushAll`/`receive*` tests above remain); no `-only-testing:`/Makefile changes needed

#### Manual
- [ ] `grep -rn "receiveAppliesEveryPresentKey\|excludedTitlesRefreshFiltersVisibleReminders\|receiveSkipCountsSavesAndFiresHookOnWatch" SingleThreadWatchTests/` returns nothing

---

## Phase 5: Coverage guardrail + full gate

### Prep (do this FIRST, before Phase 1)
- [x] `make coverage` → save `build/Coverage.xcresult` as `build/Coverage.before.xcresult`
  (there is no in-repo baseline — capture it now; `build/` is gitignored)

### Post (after Phase 4)
- [ ] `make coverage` → compare:
  ```
  xcrun xccov view --report build/Coverage.before.xcresult > /tmp/cov-before.txt
  xcrun xccov view --report build/Coverage.xcresult      > /tmp/cov-after.txt
  ```
  Diff the `SingleThreadCore` files; confirm no line-coverage drop > 0% on lines
  previously exercised by the removed tests (expect zero drop — deleted tests
  re-proved identical seams that other retained tests still cover).
- [ ] Re-run `bash scripts/count_tests.sh` and update the trailing comments to the
  final counts (they drift after Phase 3's splits and Phase 4's deletions); expected
  direction: iOS `@Test` grows by ~17, watch `@Test` falls by ~3.
- [ ] Launch the full CI-identical gate ONCE via the `run-gate` skill (one dedicated
  async gate subagent in a managed worktree, multi-hour timeout). Do not run
  `./scripts/test.sh` inline, and do not `nohup` it.

### Verification
#### Automated
- [ ] Coverage diff shows no cliff on `SingleThreadCore`
- [ ] Full `./scripts/test.sh` gate green (async run-gate subagent returns a clean verdict)

#### Manual
- [ ] PR description notes the ~17 test-count increase from splits (net suite is smaller in *maintenance* and *duplication* even though `@Test` count is flat/slightly up), and why no UI-test changes were made

---

## Testing Checkpoints (resume markers)

1. **After Phase 1** — targeted iOS suites + `make watch-test` green; `make lint` + `make periphery` clean
2. **After Phase 2** — `make lint` + `make periphery` clean; `count_tests.sh` keys stable, no dead patterns
3. **After Phase 3** — `-only-testing:SingleThreadTests/ReminderStoreTests` green; `make lint` clean
4. **After Phase 4** — `make watch-test` green; `make lint` clean
5. **After Phase 5** — coverage diff clean; full gate green (async)