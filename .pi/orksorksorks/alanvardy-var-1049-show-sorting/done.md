# Done

- **Branch / head SHA**: `alanvardy-var-1049-show-sorting` @ `7d8ba46d` (the
  `done.md` commit that follows is docs-only). Rebased and pushed with
  `--force-with-lease`; no rebase conflicts were present at review time.

- **Mechanical checks**:
  - `make lint` (SwiftFormat `--lint` + `swiftlint --strict`): 0 violations /
    0 serious, 207 files.
  - `make build` (iOS simulator, pinned to this worktree's
    `SIM=platform=iOS Simulator,id=C79CE772-5A9D-492D-BDD2-6722DBAA9F09`):
    `** TEST BUILD SUCCEEDED **`.
  - `scripts/test-one.sh SingleThreadTests/FilteredRemindersListViewTests`: 5
    cases ran (nonzero), pass.
  - `scripts/test-one.sh SingleThreadTests/FilterSortSettingsViewTests`: 8
    cases ran (nonzero), pass.
  - Full CI-identical gate (`./scripts/test.sh`, dedicated async gate subagent,
    managed worktree, `SIM=platform=iOS Simulator,id=C79CE772-…`,
    `WATCH_TEST_SIM=platform=watchOS Simulator,id=3F69EA19-…`) at `7d8ba46d`:
    format/lint, iOS build, watch build, **Periphery clean**, iOS UI 3/3
    (incl. `performAccessibilityAudit`), watch unit 55/55, watch UI 1/1 — all
    **PASS**. **macOS unit: 673 passed / 3 failed — the documented
    pre-existing `EntitlementStoreTests` trio**
    (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
    `hostStoreKitIsClean`), red on `origin/main` locally and green on fresh CI
    runners; no new regressions. Gate ran twice: attempt 1 aborted in the
    SwiftFormat `organizeDeclarations` step under heavy foreign-gate CPU
    contention (proven environmental: the two files re-linted in 0.26 s, exit
    0), attempt 2 completed cleanly. Log:
    `/tmp/gate-alanvardy-var-1049-show-sorting.log`.

- **Review outcome**:
  - **Blockers: none.** One bounded fresh-context reviewer returned *ok with
    notes*: confirmed the pushed list is driven by
    `ReminderStore.visibleReminders`, reactivity holds (store is `@Observable`;
    the settings bindings re-render the sub-view and the destination is
    re-evaluated on re-entry), no force unwraps, store threaded as a plain
    `let` matching the existing `availableLists` style, and all four new keys
    carry six distinct translations.
  - **Fix applied** (`7d8ba46d`): the reviewer's only substantive finding was
    that the NavigationLink → `listDisplays` seam was untested — a regression
    passing `[]` to the destination would have passed every existing test. I
    probed that `String(describing: view.body)` recurses into the
    `NavigationLink` destination (it does) and added assertions to
    `filterSortSettingsViewListDisplaysMatchVisibleReminders` proving the
    pushed destination carries the store's ordered, filtered titles (`high`
    present, `skipped` absent).
  - **Optional improvements declined, with reason**:
    1. Per-row `.accessibilityIdentifier("filteredRemindersRow")` is the same
       on every row. No UI test covers this screen; the combined element label
       is correct for VoiceOver, and a unique-id scheme adds churn without a
       consumer.
    2. The `FilterSortSettingsView` doc lead "Takes only the bindings it
       needs" is now loose (it also takes `store`/`availableLists`/
       `isAIRankingAvailable`). Pre-existing wording; the same comment was
       already updated to state the store is read-only.
    3. `ForEach(…, id: \.offset)` — justified: `ReminderDisplay` is not
       `Identifiable`, titles are not unique, and rows are stateless snapshots
       never mutated in place.

- **Remaining manual items** (from `plan.md`; automated counterparts all
  passed):
  - Xcode → iOS app on `iPhone 17`: gear (`settingsButton`) → Filtering &
    Sorting → **View sorted and filtered list** — pushed screen titled "Sorted
    & Filtered" lists every reminder the main card would cycle through, in the
    current sort order.
  - Change Sort By, go back, re-enter: order matches the new setting.
  - Toggle "Show undated reminders" off, re-enter: undated reminders absent.
  - Open the list with a reminder that has a list and a due date: row shows
    title plus a "List · date" caption line.
  - Skip every visible reminder (or exclude the only list), re-enter:
    "No reminders match the current filters."
  - Xcode previews of `FilteredRemindersListView` and `FilterSortSettingsView`
    render without layout artefacts.
  - CI is authoritative for the PR: all jobs (iPhone + iPad matrix, mac-tests,
    watch jobs, lint/warning-check self-test) must be green. The three local
    macOS `EntitlementStoreTests` failures will still present locally;
    expected and unrelated.