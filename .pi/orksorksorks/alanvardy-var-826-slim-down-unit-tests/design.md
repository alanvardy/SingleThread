# Design Discussion — Slim down unit tests

All paths relative to repo root; line numbers from research.md (verified against HEAD d216b6f).

## Current State

The unit test surface is `SingleThreadTests` (iOS, Swift Testing, ~521 `@Test`) plus
`SingleThreadWatchTests` (watch, ~44 `@Test`) (research.md Q3/Q7). Total 565 `@Test`
across 19 files, all 27 `@Suite` are `@Suite(.serialized)` (research.md Q3). The suites
exercise `SingleThreadCore` through shared seams: `InMemoryEventStore` (the de-facto
fixture, ~104 refs across 12 iOS test files), the `--seed`/`--ui-testing*` launch args,
and App Group `UserDefaults` keys (research.md Q4/Q5).

Duplication is real but structurally local, not cargo-cult wholesale: there are **no
full-file or full-suite duplicates** (research.md Q1). It clusters in three places:

1. **Cross-target mirror (iOS↔watch).** Near-verbatim blocks: `WatchFakeSession` is 21 of
   24 lines identical to `FakeSession` (`WatchSyncPipelineTests.swift:9-29` vs
   `SkippedReminderSyncServiceTests.swift:15-38`); ≈84 near-verbatim watch lines mirror
   iOS sync tests; `inListReminder` byte-identical in 2 files (iOS 651-659, watch 568-576);
   watch re-composes ~7 iOS tests into mega-test `receiveAppliesEveryPresentKey`
   (`WatchSyncPipelineTests.swift:69-131`). The divergence between pairs is **seam-driven**:
   pair 2 (sync layer) uses `InMemoryEventStore` on both sides (only fake-session name +
   key prefix differ), while pair 1 uses a real `EKEventStore` (`sharedWatchEventStore`) on
   watch vs `InMemoryEventStore` on iOS (research.md Q1).
2. **Intra-file fixture re-declaration.** `makeReminder` declared 9× in 8 files (none
   importable, all file-private); 3 fake transcribers with ~9 textually-identical lines
   (`MicrophoneToggleTests.swift:10-41`, `ActionButtonTests.swift:102-121`,
   `CompletionGlowTests.swift:137-148`); 2 fake sessions; 4 background-fetcher fakes;
   `sharedWatchEventStore`/`watchReminder` repeated 4×/3× (research.md Q4).
3. **Multi-layer restatement.** Persisted App Group keys are asserted in 3-7 files each
   (`showCompletionGlow` in 7, `showDate` + `enableActionButtons` in 5 each) — mostly the
   "receive → persist → hook / absent key no-op" trio re-typed ~8× across iOS/watch
   (research.md Q2).

Maintenance-cost signals (research.md Q3): `file_length` disabled on 4 files incl. the two
largest test files `ReminderStoreTests.swift` (1143) and `SkippedReminderSyncServiceTests.swift`
(660); 9 brute-force multi-store `@Test` bodies unique to `ReminderStoreTests.swift`;
`SingleThreadUITestCase.swift` (65 lines) is entirely dead (0 subclasses);
`scripts/count_tests.sh` is mechanically accurate but its hardcoded comments are stale and
2 patterns (`settle_sleeps`, `forced_400ms`) reference symbols that no longer exist.

Prior slimming set the precedent (research.md Q6): var-755 (552→398 `@Test`,
single-assertion heuristic), var-796 (criterion: delete where a lower layer proves the
behavior), var-819 (whole-file UI deletions). None ever deleted a unit test file; the
near-verbatim pair-2 copies, the dead base class, and the 9 `makeReminder` copies **all
still exist** — that is this ticket's target.

## Desired End State

A unit suite that is smaller and cheaper to maintain — same asserted behaviors, no
restated-with-identical-seam coverage, no dead fixtures or tooling — while preserving every
behavior that a distinct seam or layer genuinely proves.

Concretely, after this change:

- **Fixture duplication is centralized** per bundle: one shared fixture file in
  `SingleThreadTests/` and one in `SingleThreadWatchTests/`, holding the single canonical
  copy of each fake/fixture (`makeReminder`, fake transcriber, fake session, `inListReminder`,
  `sharedWatchEventStore`/`watchReminder`, background-fetcher fakes). Per-file copies deleted.
- **Seam-identical cross-target copies are gone**: the pair-2 verbatim watch blocks and the
  re-composed mega-test are removed; watch-only sync receive tests and the whole pair-1
  real-`EKEventStore` watch suite remain.
- **Dead and rotten tooling is removed/fixed**: `SingleThreadUITestCase.swift` deleted;
  `count_tests.sh` stale comments and dead patterns corrected; brute-force multi-store test
  bodies split into single-scenario tests.
- **No production code, no UI suite, no target topology changes** (see "What We're NOT Doing").

Verification of correctness:
- Targeted suites pass after each phase (`-only-testing:` per conventions.md; `make
  watch-test` for the watch bundle).
- `make lint` stays clean (`--strict`, every warning is an error) and `make periphery` flags
  no newly-dead symbols.
- `make coverage` (Makefile:40-51) run **once** at the end as a guardrail: the report shows
  no coverage cliff in `SingleThreadCore` lines previously exercised by removed tests vs the
  pre-change baseline (coverage bundle produced before starting, then compared after).
- Full `./scripts/test.sh` gate green via the `run-gate` skill (run once, async).

## Patterns to Follow

- **Per-bundle fixture files under the existing test dirs, not a new target.** Xcode
  auto-discovers `.swift` files in synchronized groups (objectVersion 77) — adding files
  needs no pbxproj edits (AGENTS.md). Keep the file-private convention's *intent* (fixtures
  live in test target, never shipped) while removing its *cost* (re-typing).
- **Delete-where-lower-layer-proves** (var-796 criterion, research.md Q6): remove a test
  only when a lower layer asserts the identical behavior with an equivalent seam; keep
  distinct seams (`InMemoryEventStore` vs real `EKEventStore`; synchronous watch vs
  continuation-based iOS; render-layer row-visibility
  `ShowDateTests`/`ShowAlarmsTests`/`ShowRecurrenceTests`).
- **Swift Testing conventions**: `@Suite`/`@Test`, `#expect` with messages, `withCheckedContinuation`
  rendezvous for async (research.md Q1); test names must NOT start with `test`/`testing`
  (SwiftFormat strips → phantom diffs, conventions.md). Force-unwrapping banned outside tests;
  fixture relaxation via `SingleThreadTests/.swiftlint.yml`.
- **Keep `@Suite(.serialized)`** — serialization is load-bearing (real App Group keys,
  MainActor timing, shared `EKEventStore` fixtures; conventions.md). Do not attempt parallel
  conversion.
- **Keep the `UITestingSeedTests` harness suite** (16 tests) — it is the only coverage of the
  App Group side of `resetPersistedState` and the `--seed` clean-slate guarantee
  (research.md Q5); it is not slimming fodder.

**Patterns to NOT follow (flag and do not reproduce):**
- File-private fixture copying "because it cannot be imported across bundles" — solved
  in-bundle by Q1-Decision 1 rather than by re-typing (research.md Q4).
- Hardcoded trailing comments in `count_tests.sh` that drift from the tree (research.md Q3).
- Brute-force "build N stores in one `@Test` body" (research.md Q3) — splits muddy intent
  and make failures harder to attribute.

## Design Decisions

1. **Fixture deduplication — in-bundle shared fixture files (Q1-A).** Add
   `SingleThreadTests/TestFixtures.swift` (or similar) and a watch-side counterpart; move the
   duplicated fakes/fixtures there; delete per-file copies. Chosen over a new shared
   test-support target (pbxproj object IDs + scheme wiring, and the watch seam deliberately
   differs) and over leaving as-is (bakes in ~90 lines of triplication forever).

2. **Deletion criteria — structural/layered redundancy + end-of-run coverage safety check
   (Q2-A).** Delete on duplication and layered-redundancy evidence (var-796 precedent), then
   run `make coverage` once at the end to confirm no coverage cliff, not as a gate on every
   individual decision. Chosen over measure-first (slow, coverage% is a poor proxy for
   duplicate-value) and over a pure assertion-count heuristic (volume ≠ value).

3. **Cross-target mirror — cut seam-identical pair 2, keep seam-valuable pair 1 (Q3-A).**
   Delete the ≈84 near-verbatim watch sync lines + `receiveAppliesEveryPresentKey` mega-test
   (InMemoryEventStore both sides, only fake-session name + key prefix differ); preserve the
   whole `ReminderStoreWatchTests` suite (real `EKEventStore` on watchOS where InMemoryEventStore
   trims `save/remove/makeReminder`, `InMemoryEventStore.swift:84-118`) and the watch-only
   receive tests (`showRecurrence`/`showAlarms`/`showList`).

4. **Ancillary cleanup in scope (Q4-A).** Delete `SingleThreadUITestCase.swift`; correct
   `count_tests.sh` stale comments and remove the 2 dead patterns (`settle_sleeps`,
   `forced_400ms`); split the 9 multi-store `@Test` bodies in `ReminderStoreTests.swift`.
   Each is test-side, no coverage loss, individually verifiable.

5. **Scope boundaries (Q5-A, confirmed).** No production `SingleThreadCore` changes, no UI-suite
   changes, no `@Suite(.serialized)` removal, no new targets. Listed explicitly below.

## What We're NOT Doing

- **No production `SingleThreadCore` changes** — `InMemoryEventStore`, `UITestingSeed`,
  `AppGroup`, launch-arg seams, `ReminderStore.swift` settle hook all untouched.
- **No UI-test changes** — `SingleThreadUITests`/`SingleThreadWatchUITests` already minimal
  (var-819); leave the XCTest smoke suites alone (they keep `test…` names; SwiftFormat-excluded).
- **No `@Suite(.serialized)` → parallel conversion** — serialization reasons are real
  (App Group keys, MainActor timing, StoreKit sandbox).
- **No new Xcode targets or pbxproj edits** — fixture sharing stays in-bundle.
- **No cross-bundle fixture import** — the iOS/watch copies of a fixture remain separate
  (different seams are the point, per Q3).
- **No pivoting "slim down" into "fix untested behavior"** — the untested watch render gates
  (`WatchReminderView.swift:335-350`), `isNudged`/nudge banner, and glow overlay calls
  (research.md Q2) are coverage *gaps*, not bloat; adding tests for them is out of scope
  unless the user explicitly asks.

## Open Risks

- **Coverage guardrail costs a full coverage build** (`make coverage` bundles
  `SingleThreadTests` only); it produces no historical baseline to diff against, so the
  "before" bundle must be captured at the start of implementation (research.md Q7 notes zero
  recorded bundles exist in-repo).
- **Deleting pair-2 watch sync tests reduces watch-target `@Test` count** and could expose a
  missing `-only-testing:` entry if a suite empties — verify `Makefile` watch-test target and
  `scripts/test.sh` accordingly (conventions.md).
- **Fixture extraction may surface a name collision** (e.g. `sharedWatchEventStore` used in
  4 files with identical bodies but file-private scope); resolution must stay file:line-cited
  and lint-clean.
- **`count_tests.sh` edits** are low-risk but a CI/counting consumer may depend on its exact
  output fields — keep output keys stable while fixing comments and dead patterns.
- **Ambiguous watch simulator destinations** can hang targeted watch-test runs — pin
  `WATCH_TEST_SIM` / `,OS=<ver>` as conventions.md requires.
- **Known local-only macOS `EntitlementStoreTests` failures** — do not debug; CI is
  authoritative on fresh runners (AGENTS.md).

## Next

Run `!1` to structure the plan from this design.