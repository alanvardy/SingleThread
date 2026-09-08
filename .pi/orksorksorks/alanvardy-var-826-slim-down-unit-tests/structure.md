# Structure Outline — Slim down unit tests

## Approach

Pure test-side restructuring in horizontal layers, bottom-up. The bottom
layer centralizes duplicated fixtures into one shared file per test bundle;
every subsequent stage (dead-tooling removal, multi-store test splits,
cross-target mirror deletion) builds on that canonical fixture surface. No
production code, no UI suites, no new targets, no `.serialized` removal.
Coverage baseline captured at start; guardrail comparison at end.

---

## Stage 1: Shared test-fixture files (Foundation)

**What**: Create one fixture file per bundle holding every duplicated
fake/fixture in a single canonical copy. Delete the per-file copies and
update all callers to import from the shared file. This is purely
mechanical — same bodies, new home. Everything above depends on fixtures
being canonical.

**Files**:
- **New**: `SingleThreadTests/TestFixtures.swift`
- **New**: `SingleThreadWatchTests/TestFixtures.swift`
- **Edited**: every test file that currently declares its own copy of a
  moved fixture (≈12 iOS files + ≈6 watch files)

**Key changes** (iOS `TestFixtures.swift`):

```
// — Canonical fixtures, SingleThreadTests bundle —
// (access level removes need for per-file fileprivate copies)

let sharedTestEventStore: EKEventStore   // was fileprivate in 5 files

func makeReminder(title: String, in store: EKEventStore) -> EKReminder
// — 7 byte-identical 3-statement bodies consolidated into one

class TestFakeTranscriber: SpeechTranscribing {
    // — merges MicToggleFakeTranscriber + ActionButtonFakeTranscriber
    //   + GlowFakeTranscriber (transcribe/requestAuthorization bodies
    //   textually identical; full surface includes refreshCallCount +
    //   liveStatus so every consumer compiles)
    var refreshCallCount: Int
    var liveStatus: LiveTranscriptionStatus
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func transcribe() -> AsyncStream<LiveTranscriptionStatus>
}

struct FakeSession: SkipSyncSession {
    // — canonical copy from SkippedReminderSyncServiceTests.swift:15-38
    var lastMessage: [String: Any]
    func sendMessage(_ message: [String: Any], replyHandler: ...) // no-op
    func updateApplicationContext(_ ctx: [String: Any]) throws
}

func inListReminder(title: String, listTitle: String) -> EKReminder
// — 9-line byte-identical body (iOS 651-659), now once

// Background-fetcher fakes (from BackgroundImageStoreTests.swift):
class FakeBackgroundFetcher: BackgroundImageFetching { ... }
actor FetchGate { ... }
class GatedBackgroundFetcher: BackgroundImageFetching { ... }
// SeededFetcher (from SettingsViewTests.swift:416-435)
```

**Key changes** (watch `TestFixtures.swift`):

```
let sharedWatchEventStore: EKEventStore
// — was fileprivate in 4 files (each with ~20-line SIGTRAP doc comment)

func watchReminder(title: String, dueDate: Date?, ...) -> EKReminder
// — 3 identical declarations consolidated; canvasReminder variant stays

struct WatchFakeSession: SkipSyncSession {
    // — canonical copy from WatchSyncPipelineTests.swift:9-29
}

func inListReminder(title: String, listTitle: String) -> EKReminder
// — watch copy (568-576), byte-identical to iOS but kept separate
//   per design decision: no cross-bundle fixture import
```

**Per-file deletions** (representative):
- `ReminderStoreGateTests.swift`: delete `makeReminder` (:169), delete
  `sharedTestEventStore` (:177); add `import` (none needed — same module)
- `MicrophoneToggleTests.swift`: delete `MicToggleFakeTranscriber`
  (:10-41); use `TestFakeTranscriber`
- `ActionButtonTests.swift`: delete `ActionButtonFakeTranscriber`
  (:102-121) + comment (:99-100); use `TestFakeTranscriber`
- `CompletionGlowTests.swift`: delete `GlowFakeTranscriber` (:137-148)
  + comment (:134-135); use `TestFakeTranscriber`
- `SkippedReminderSyncServiceTests.swift`: delete `FakeSession` (:15-38),
  `inListReminder` (:651-659)
- `WatchSyncPipelineTests.swift`: delete `WatchFakeSession` (:9-29),
  `inListReminder` (:568-576)
- `BackgroundImageStoreTests.swift`: delete `FakeBackgroundFetcher`
  (:438-446), `FetchGate` (:450-479), `GatedBackgroundFetcher` (:482-506)
- `SettingsViewTests.swift`: delete `SeededFetcher` (:416-435)
- Watch files declaring `sharedWatchEventStore`/`watchReminder`:
  `ReminderStoreWatchTests.swift`, `WatchReminderViewRegressionTests.swift`,
  `WatchReminderViewModelTests.swift`, `ShowCompletionGlowStateTests.swift`

**Edge case — name collision on `sharedWatchEventStore`**: the 4 current
declarations are identical; move the canonical one to
`WatchTestFixtures.swift` and delete the 4 per-file copies. The 20-line
SIGTRAP doc comment moves with it.

**Tests**: All existing suites pass unchanged — same fixture bodies, same
assertions. Verify by targeted suite runs:

```
# iOS — targeted suites that consume moved fixtures:
xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.4' \
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

# Watch:
make watch-test   # -only-testing:SingleThreadWatchTests
```

**Verify**: `make lint` clean (no unused-import warnings, no file-length
regressions); `make periphery` clean (no newly-dead symbols — moved
fixtures show one declaration site, consumed at all previous call sites).

---

## Stage 2: Dead and rotten tooling removal

**What**: Delete the fully-unreferenced `SingleThreadUITestCase.swift` base
class. Fix `count_tests.sh` stale comments and remove the two structurally
dead patterns (`settle_sleeps`, `forced_400ms`). These are standalone
cleanups that need the fixture landscape stable (Stage 1 done) so
`count_tests.sh` regenerated trailing comments match reality.

**Files**:
- **Deleted**: `SingleThreadUITests/SingleThreadUITestCase.swift` (65
  lines, 0 subclasses, 0 external references)
- **Edited**: `scripts/count_tests.sh`

**Key changes** (`count_tests.sh`):
- Regenerate each hardcoded trailing comment from a fresh run — the
  comments currently describe a pre-slimming tree; the computed values
  are already accurate
- Delete the `settle_sleeps` grep block (pattern `eventKitSettleDelay`
  has 0 hits in the tree; always returns 0)
- Delete the `forced_400ms` grep block (literal `400_000_000` has 0
  hits; always returns 0)
- Add a comment noting that the real 200 ms settle at
  `ReminderStore.swift:39` is not counted (injectable, tests use
  `noopSettle`/`--ui-testing-noop-settle`)
- Output keys (`unit_tests`, `expect`, `require`, `assertion_mean`,
  `launches`, `unnamed_expect`, `xcodebuild`) remain stable — only
  trailing comments and dead-pattern blocks change

**Tests**: No new tests. `make lint` clean (`.swiftlint.yml`
`.periphery.yml:15-16` exclusion for `**/SingleThreadUITests/**` may
hide the deletion from Periphery — confirm manually that the file is
gone and no `SingleThreadUITestCase` reference survives anywhere).

**Verify**:
```
make lint          # swiftformat --lint + swiftlint lint --strict
make periphery     # clean DeriveData/ first; no newly-dead symbols
bash scripts/count_tests.sh   # output keys stable, comments current
```

---

## Stage 3: Split brute-force multi-store tests

**What**: The 9 `@Test` bodies in `ReminderStoreTests.swift` that build
2–4 stores inline are split into single-scenario tests. Each split body
becomes 2–4 focused `@Test` functions, each building one store against
the now-canonical shared fixtures from Stage 1. Assertions preserve their
existing coverage; intent becomes attributable.

**Files**:
- **Edited**: `SingleThreadTests/ReminderStoreTests.swift`

**Key changes** — the 9 bodies split (current pattern → new):

```
// Current: allSkippedReflectsState() builds 4 stores in one body
//   → becomes:
@Test func skippedReflectsStateWhenAllSkipped()        // store 1
@Test func skippedReflectsStateWhenSomeSkipped()       // store 2
@Test func skippedReflectsStateWhenNoneSkipped()       // store 3
@Test func skippedReflectsStateAfterSkipCurrentReminder() // store 4

// Current: visibleRemindersFiltersSkippedAndEmpty() — 3 stores
//   → becomes 3 single-scenario tests

// Current: visibleRemindersFiltersExcludedListTitles() — 3 stores
// Current: setSortOptionReordersAndNotifies() — 3 stores
// Current: skipCurrentReminderNoOpsAndNotifies() — 3 stores
// Current: completeCurrentReminderCompletesVisibleAndNoOpsOtherwise() — 3
// Current: visibleRemindersSortsByPriorityThenDate() — 2 stores
// Current: lifecycleGuardsRespectLoadsRemindersFlag() — 2 stores
// Current: hasHiddenReflectsSeedsAndSets() — 2 stores
```

Approximate net: ~9 `@Test` deleted, ~25 `@Test` added (each single-scenario,
each using `makeReminder`/`sharedTestEventStore` from `TestFixtures.swift`).
Total `@Test` count in `ReminderStoreTests.swift` grows, but each function
now tests one thing — failures attribute to one scenario.

**Tests**: The split functions *are* the tests. Each scenario's
assertions are preserved; no new behavior added.

**Verify**:
```
# Targeted suite only — ReminderStoreTests (the only file touched):
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.4' \
  -only-testing:SingleThreadTests/ReminderStoreTests

make lint   # file_length disable may still be needed (it was 1143 lines
            # before splits; splits add lines — flag if this pushes past
            # the 800 error threshold and note in PR)
```

---

## Stage 4: Delete seam-identical cross-target mirror (pair 2)

**What**: Cut the ≈84 near-verbatim watch sync lines and the re-composed
`receiveAppliesEveryPresentKey` mega-test from
`WatchSyncPipelineTests.swift`. These test the identical `InMemoryEventStore`
seam as the iOS side; only the fake-session class name and key prefix
differ. Watch-only receive tests (showRecurrence, showAlarms, showList)
and the whole pair-1 real-`EKEventStore` watch suite (`ReminderStoreWatchTests`)
are preserved — their seam is distinct.

**Files**:
- **Edited**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`

**Key changes** — deletions only:

```
// DELETE — near-verbatim copies (~84 lines):
//   excludedTitlesRefreshFiltersVisibleReminders (:196-227, 32 lines)
//     — iOS twin: receivedExclusionRefreshFiltersVisibleReminders
//       (SkippedReminderSyncServiceTests.swift:406-436)
//   receiveSkipCountsSavesAndFiresHookOnWatch (:435-454)
//     — iOS twin: receiveSkipCountsSavesAndFiresHook (:606-624)
//   receiveAppliesEveryPresentKey (:69-131, 63-line mega-test that
//     re-composes ~7 iOS split tests)
//   Any other verbatim "receive → persist → hook" bodies where the
//     only delta is key prefix `wtest-*` vs `test-*`

// KEEP — watch-only (no iOS twin):
//   showRecurrence receive tests (:229-296)
//   showAlarms receive tests (same region)
//   showList receive tests (:303-346)
//   WatchEnableActionButtonsSyncTests suite (:526-end)
//   makeService / makePreference helpers (:468-521)
```

After deletions, `WatchFakeSession` and `inListReminder` references in
remaining watch tests resolve to `WatchTestFixtures.swift` (Stage 1).

**Tests**: No new tests. Remaining watch tests must stay green.

**Verify**:
```
make watch-test   # -only-testing:SingleThreadWatchTests
make lint         # no unused-import / dead-symbol warnings
```

**Risk**: If a `-only-testing:` entry in `Makefile` or `scripts/test.sh`
references a now-empty suite, adjust it. Per conventions.md, new suites
need explicit entries — but here we're removing tests, not suites; verify
the `WatchSyncPipelineTests` suite still has remaining `@Test` functions
after cuts.

---

## Stage 5: Coverage guardrail

**What**: Compare the pre-change coverage bundle (captured before Stage 1)
against a post-change bundle. Confirm no coverage cliff in `SingleThreadCore`
lines previously exercised by removed tests. Run the full CI-identical gate
once via the `run-gate` skill.

**Prep** (before Stage 1):
```
make coverage   # produces build/Coverage.xcresult — save as
                # build/Coverage.before.xcresult (or copy aside)
```

**Post** (after Stage 4):
```
make coverage   # produces build/Coverage.xcresult — compare:
xcrun xccov view --report build/Coverage.before.xcresult > /tmp/cov-before.txt
xcrun xccov view --report build/Coverage.xcresult > /tmp/cov-after.txt
# Diff SingleThreadCore files; flag any line-coverage drop > 0%
# in previously-covered lines.
```

**Gate**: Launch ONE async gate subagent via the `run-gate` skill — this
runs `./scripts/test.sh` (format → lint → build → periphery → unit + UI
tests, both platforms, full CI matrix) in a managed worktree with a
multi-hour timeout. Do not run it inline; do not `nohup` it ad-hoc.

**Verify**: Coverage diff shows no regression on `SingleThreadCore` lines
that removed tests previously exercised. Full gate green.

---

## Testing Checkpoints

Resume markers — each is independently verifiable:

1. **After Stage 1**: targeted iOS suites + `make watch-test` green;
   `make lint` + `make periphery` clean
2. **After Stage 2**: `make lint` + `make periphery` clean;
   `count_tests.sh` output keys stable
3. **After Stage 3**: `-only-testing:SingleThreadTests/ReminderStoreTests`
   green; `make lint` clean (file-length disable may still apply)
4. **After Stage 4**: `make watch-test` green; `make lint` clean
5. **After Stage 5**: coverage diff shows no cliff; full `./scripts/test.sh`
   gate green (via async `run-gate` subagent)
