# Done

- **Branch / head SHA**: `alanvardy-var-1062-improve-sorting` @ `78261317`
  (`fix(VAR-1062): translate Default sort label into all six languages`).
  Pushed to `origin`. No rebase conflicts were present at review time; the
  branch was already an ancestor of `origin/main`.

## Feature

Add a selectable **Default** `SortOption` (raw API order, no reordering) and
rework the `ReminderSort` comparator chains:
`.priority` = priority → due date → title; `.dueDate` = due date → priority →
title; `.title` = title only; `.default` = no reordering. The old
`compareLists` list tie-break was removed. `ReminderStore.visibleReminders`
short-circuits to raw filtered order for `.default`, the single enforcement
point shared by phone, watch, widget and intents. `SortOptionStore` /
WatchConnectivity fallback stays `.priority` for backward compatibility, so
existing users keep Priority until they choose otherwise.

## Mechanical checks

- `make format` — clean (0/219 files reformatted).
- `make lint` (SwiftFormat `--lint` + `swiftlint lint --strict`) — **0
  violations, 0 serious in 212 files**.
- Targeted `scripts/test-one.sh` suites at review time:
  `LocalizationTests` 5/5, plus the implement-phase suites
  (`SortOptionTests`, `ReminderSortTests`, `ReminderStoreTests`,
  `FilterSortSettingsViewTests`, `SortOptionStoreTests`,
  `SkippedReminderSyncServiceTests`) all reported non-zero case counts and
  passed.
- Full CI-identical gate (`./scripts/test.sh`, dedicated async gate subagent,
  managed worktree, `SIM=platform=iOS Simulator,id=DDF65026-…`,
  `WATCH_TEST_SIM=platform=watchOS Simulator,id=3F69EA19-…`):
  - **Run 1 @ `4869eb5f`**: FAIL — prune/deployment/wrapper checks, format,
    SwiftFormat, SwiftLint, warning-check self-test (20/20), iOS build, watch
    build, Periphery, iOS UI, watch UI, watch unit all **PASS**; macOS unit
    FAIL on `LocalizationTests/catalogsHaveAllSixLanguages()` (real regression,
    see below) plus the three documented pre-existing `EntitlementStoreTests`
    failures. Log: `/tmp/gate-alanvardy-var-1062-improve-sorting.log`.
  - **Run 2 @ `78261317`**: every stage **PASS** — format/lint, warning-check
    self-test, iOS build, watch build, **Periphery "No unused code detected"**,
    iOS UI, watch UI, watch unit, and **all `LocalizationTests` pass**. The only
    non-zero leg is the documented pre-existing local-only macOS
    `EntitlementStoreTests` trio (`isEntitledSurvivesStoreRecreation`,
    `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — red on
    `origin/main` locally, green on fresh CI runners; no new regressions. Log:
    `/tmp/gate-alanvardy-var-1062-improve-sorting-2.log`.

## Review outcome

- **Blockers: one, found by gate run 1 and FIXED (`78261317`).**
  `LocalizationTests.catalogsHaveAllSixLanguages()` requires every catalog key
  to resolve in all six supported languages (en, zh-Hans, es, ja, de, fr), but
  the new `"Default"` key shipped en-only per `plan.md`'s localization decision.
  Fixed by adding zh-Hans/es/ja/de/fr (`默认` / `Predeterminado` / `デフォルト` /
  `Standard` / `Par défaut`); the existing test reproduced the bug and now
  passes. `plan.md` was back-patched and `implement.md` records the deviation.
- **Fixes worth doing now — APPLIED (`4869eb5f`).** Reviewer noted the public
  `ReminderSort.areInIncreasingOrder(_:_:using:)` doc omitted that `.default`
  imposes no ordering; doc now states `.default` always returns `false`.
- **Optional improvements — APPLIED (`4869eb5f`).** Documented that `.default`'s
  EventKit fetch order is not a stable order across reloads, and that `.title`
  keeps input order for duplicate titles (no secondary tie-break).
- **One bounded fresh-context reviewer, no other blockers.** Verified comparator
  chains, the `.default` short-circuit, cross-surface reach (widget/intents/watch
  all read `visibleReminders`), backward-compatible store/sync fallback, and that
  the new tests are non-vacuous; confirmed the deleted `compareLists` tests
  covered deleted logic and the priority→date→title fall-through stays covered by
  `sortsWithinSamePriorityByDateThenTitle`. No force unwraps, no concurrency
  concerns (value enum / pure `nonisolated` funcs).

## Remaining manual items

From `plan.md`; automated counterparts all passed, but these are on-device checks
the review lane could not perform:

- [ ] Run the app, open Settings → Filter & Sort, confirm "Default" appears first
  with its symbol, is selectable, and survives relaunch (persisted as `"default"`).
- [ ] With "Default" selected, confirm the list shows reminders in the API order;
  switch to the other three options and confirm the new chains (title-only
  ignores priority/date).
- [ ] Pick "Default" on the phone, then confirm the watch reflects the same
  selection after a sync and shows raw API order.
- [ ] CI is authoritative for the PR: all jobs (iPhone + iPad matrix, mac-tests,
  watch jobs, lint/warning-check self-test) must be green. The three local macOS
  `EntitlementStoreTests` failures will still present locally; expected and
  unrelated.
