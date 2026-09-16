# Done

- **Branch / head SHA**: `alanvardy-var-1018-app-intents` @ `e5dea2e5` (pushed to `origin`).
  Code commits: Phase 1 `1153f573`, Phase 2 `6e06a95f`, Phase 3 `f3df1ed1`, Phase 4 `90b377a9`,
  artifacts `c6ca90f5`, review fixes `e5dea2e5`. `DELETEME` removed in Phase 1.
- **Mechanical checks**:
  - No rebase conflicts: branch was already rebased onto `main` (`74fcd2c6` == merge-base);
    pushed with `--force-with-lease` (fast-forward, no rewrite needed).
  - `make format` — clean (tree unchanged after the review-fix edits).
  - `make lint --strict` — 0 violations / 0 serious across 191 files.
  - Targeted suites at `e5dea2e5` — `ReminderIntentSupportTests` 17 cases,
    `ReminderIntentsTests` 9 cases, `LocalizationTests` 5 cases, all green
    (`scripts/test-one.sh`, pinned worktree sim).
  - `make mac-build` and `make watch-build` — both `** BUILD SUCCEEDED **`.
  - Full CI-identical gate (`./scripts/test.sh`, via the `run-gate` skill, managed
    worktree from the tip, log `/tmp/gate-1018b.log`): every non-macOS phase green
    (SwiftFormat check, SwiftLint, iOS build, watch build, Periphery "No unused code
    detected.", iOS UI smoke, watch UI smoke, watch unit suites). The macOS unit-test
    phase reported only local-only failures: the three documented pre-existing
    `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`,
    `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) plus one pre-existing
    parallel-`UserDefaults` flake `SettingsViewTests.showMenuBarExtraRoundTripsThroughContentView`
    (origin `24a2ec62`, on `main`, unrelated to this diff) that **passed** on an
    isolated re-run (`make mac-test` at the same tip → only the three known failures).
    CI mac-tests is authoritative. A first gate run at the pre-fix tip `c6ca90f5`
    reported exactly the three known failures and no other.
- **Review outcome**:
  - One bounded reviewer; **no P0 blockers**. Verified independently: no force-unwraps,
    no `@unchecked Sendable`, `perform()` correctly `@MainActor` on the Core
    type-level `@MainActor` seam, durable write awaited on the complete path and
    synchronous on the skip path, `makeStore` never prompts (proven by
    `requestFullAccessCallCount == 0`), AppIntents availability holds on the iOS 17
    floor, and all new catalog keys carry six languages.
  - **Fixes worth doing now applied** (commit `e5dea2e5`):
    1. **Message accuracy** — added `.cannotMutate` (free-tier cap) and `.failed`
       (EventKit write failure) to `ReminderIntentOutcome`; `completeOutcome`/
       `skipOutcome` guard `store.canMutate` before mutating, so a gated or failed
       write no longer reports "There's nothing to do right now." Two new
       six-language catalog keys; `design.md` decision 6/7, `plan.md` Phase 4, and
       `structure.md` Phases 2–4 back-patched.
    2. **Persistence test now proves persistence** — `InMemoryEventStore` records
       `saveCallCount`; the test asserts the completion reached EventKit.
    3. **Skip durability test** now asserts the injected `SkippedReminderStore` was
       written, not just the in-memory set.
  - **Optional improvements applied**: intent titles now resolve through the `.main`
    bundle for all three intents (replacing a trivial `.key ==` self-check); added
    direct `value(for:)` coverage; removed a duplicate empty-list case; also added a
    `.failed` test driven by an injectable `InMemoryEventStore.saveError` seam.
  - **Declined/deferred**: App Shortcut phrase localization (needs an
    `AppShortcuts.xcstrings` the build does not currently extract, and Siri phrase
    matching is unverifiable without a device) and the `makeGatedStore`
    standard-defaults / `showsUndatedReminders` nits — both recorded in
    `implement.md`.
- **Remaining manual items**:
  - The plan's on-device/Siri checks are still manual: install on a simulator/device
    with Reminders access, long-press the app icon → all three shortcuts appear; run
    each and confirm the dialog names the task; confirm a skipped task stays skipped
    after relaunch; set a non-English locale and confirm translated dialogs/short
    titles; spot-check Siri phrasing on a physical device.
  - Pre-existing flake, **not fixed** (out of scope): `SettingsViewTests` is not
    `.serialized` and `showMenuBarExtraRoundTripsThroughContentView` races
    `showMenuBarExtraDefaultsToShownInBag` over the shared `UserDefaults.standard`
    `showMenuBarExtra` key. Worth a separate scoped fix (add `.serialized` or isolate
    the suite's defaults).
  - App Shortcut phrase localization remains a documented gap; confirm whether CI's
    Xcode 26.6 extracts an `AppShortcuts.xcstrings` where local Xcode 27 did not.