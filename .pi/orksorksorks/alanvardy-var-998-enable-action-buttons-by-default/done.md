# Done

- **Branch / head SHA**: `alanvardy-var-998-enable-action-buttons-by-default` @ `1f5a935e`
  (pushed to `origin`; PR #195, still **draft**, no CI checks run yet)
- **Mechanical checks**:
  - `make format` — clean, no content diff.
  - `make lint` (`swiftlint --strict`) — 0 violations, 0 serious in 188 files.
  - `make build` (iOS) — `** TEST BUILD SUCCEEDED **`.
  - `make mac-build` (macOS) — `** BUILD SUCCEEDED **`.
  - `scripts/test-one.sh SingleThreadTests` (full iOS unit target) — **568 cases ran, all passed**.
  - `make watch-test` (watch unit target, 26.5 runtime sim pinned by id) — **48/48 passed, 0 failed**.
  - Targeted: `EnableActionButtonsSyncTests` (4), `EnableActionButtonsMigrationTests` (3),
    `BoolPreferenceKeyTests` (3), `SettingsViewTests` (15), `ActionButtonTests` (5) — all pass;
    each reported >0 cases so no zero-match silent pass.
  - `./scripts/test.sh` **not re-run locally**: the pipeline already ran once via `run-gate`
    (`d53495ee`) and aborts at Periphery on the documented pre-existing local-only
    `ContentView.swift:337 Unused property 'isShowingPurchase'` false positive (local Xcode 27.0;
    CI-pinned 26.6 is green on equivalent `main`). Per repo convention, CI is authoritative.

- **Review outcome**:
  - **Blocker B1 — FIXED.** `pushAll()` used to put raw `bool(forKey:)` (absent ⇒ `false`) on the
    wire, so the first sync flipped a fresh paired device off and persisted it, defeating the
    ticket's fresh-install default-on. `SkippedReminderSyncService` now holds an injectable
    `enableActionButtonsStore` and **omits the key when it was never set** (`BoolPreferenceStore.isSet`),
    preserving the existing "absent key is a no-op" receive semantics. Added
    `pushAllOmitsNeverSetEnableActionButtons` + `pushAllSendsExplicitEnableActionButtonsOff`.
  - **macOS default-on — DONE (user-directed scope override).** `macShowActionMenu` now reads the
    shared `@AppStorage("enableActionButtons")` value (default `true`) instead of a raw
    `bool(forKey:)`, so macOS fresh installs match iOS/watch. `AppViewModel.handlePreferencesChanged`
    and `lastEnableActionButtons` resolve absent → `true` too, so toggling off from a fresh
    default-on still pushes.
  - **F1 — FIXED.** `existingAppGroupOffIsNotClobbered` now seeds both `.standard` (`true`) and the
    App Group (`false`); it fails if the migration guard copies unconditionally (previously it
    passed for a broken guard).
  - **F2 — FIXED.** Stale "the default is off" comment in `WatchAppViewModel.swift` reworded.
  - **Optional shared key — DONE.** Added `BoolPreferenceKey.enableActionButtons`; the WC payload
    key, the watch state, the app's raw reads, and the new store all reference it. `BoolPreferenceKey.allCases`
    count test updated 7 → 8.
  - **One-frame on→off flash — DEFERRED (deliberate).** Seeding `ContentViewModel.enableActionButtons`
    from the store at init would fix the single-frame mirror flash for toggled-off users, but it
    reintroduces cross-suite `UserDefaults` race flakiness (the mirror's literal default is currently
    parallel-safe) and the real tap gate already reads the `@AppStorage` value directly, so only the
    branch selection at `ContentView.swift:705` flickers before `.task` injects. Not worth the
    isolation risk; optional follow-up.
  - No other reviewer findings; all four read sites flip together, the settings-toggle write path is
    intact, and the new tests are non-tautological.

- **Remaining manual items**:
  - Plan's manual inspection checklist (migration guard byte-identical; `--ui-testing`/`--seed` force-true
    at `AppViewModel.swift:232,315`; settings toggle write path; sync push/apply) — all confirmed
    inspect-only by the phase subagents and re-verified for the changed lines here.
  - Run the authoritative CI (`./scripts/test.sh` on Xcode 26.6) — needs the draft PR marked ready;
    this also covers `SingleThreadUITests.testLaunchAndRenderSmoke` and the macOS suites.
  - Optional follow-up: eliminate the one-frame mirror flash (above).
