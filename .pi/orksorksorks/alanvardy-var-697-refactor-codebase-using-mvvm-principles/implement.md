# Implementation Summary

ViewModels refactoring (MVVM) — `Refactor codebase using MVVM principles` (VAR-697)

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `4d492c2` | Store-derived `allSkipped` |
| 2     | `43d6ffe` | `DictationViewModel` |
| 3     | `6206b56` | `ContentViewModel` |
| 4     | `23acd14` | `SettingsViewModel` |
| 5     | `b2e6013` | `AppViewModel` (iOS/macOS composition root) |
| 6     | `fb9ed26` | Watch ViewModels (`WatchReminderViewModel`, `WatchAppViewModel`) |

## Automated Checks
- [x] Phase 1: `make test` — `ReminderStoreTests.allSkipped*` truth-table tests + all suites green
- [x] Phase 1: `make ui-test` — "No Reminders"/"All Done" labels render identically
- [x] Phase 1: `make watch-ui-test` — watch empty/skipped states render identically
- [x] Phase 2: `make test` — `MicrophoneToggleTests` + `ReminderDictationTests` rewritten to use VM; all suites green
- [x] Phase 2: `make build` — iOS app compiles
- [x] Phase 2: `ContentView` has no `@State` dictation vars
- [x] Phase 3: `make test` — `ActionButtonTests`, `BackgroundCardTests`, `SingleThreadTests` green
- [x] Phase 3: `make ui-test` — same launch args/labels, accessibility audit passes
- [x] Phase 3: `make build` + `make mac-build` — iOS + macOS compile
- [x] Phase 4: `make test` — `SettingsViewTests` + new `SettingsViewModelTests` pass
- [x] Phase 4: `make build` + `make mac-build` — iOS + macOS compile
- [x] Phase 4: `make ui-test` — accessibility audit passes
- [x] Phase 5: `make test` — `SkippedReminderSyncServiceTests` still pass
- [x] Phase 5: `make ui-test` — all flows + accessibility audit pass unchanged
- [x] Phase 5: `make watch-ui-test` — sync: phone push → watch applies
- [x] Phase 6: `make watch-build` — compiles without errors
- [x] Phase 6: `make watch-ui-test` — same launch args/labels, passes
- [x] Phase 6: `./scripts/test.sh` — full gate: format + lint + build + periphery + unit + iOS UI + watch UI (EXIT=0, "All CI checks passed")

## Manual Verification Items (from the plan)
- [ ] Run app on simulator: see a reminder, skip it, verify "All Done" appears
- [ ] Run watch app: skip a reminder, verify "All Done" appears
- [ ] On simulator, grant speech permission: tap mic, speak "buy milk tomorrow", verify reminder appears with creation-feedback checkmark
- [ ] Run app: Complete/Skip cluster shows when `enableActionButtons` is ON and reminder visible; mic button shows when OFF; background appears when enabled + photo loaded
- [ ] Toggle "Show undated reminders" — list refreshes; toggle "Sort By" — order changes; toggle "Appearance" — mode switches
- [ ] Open Settings, toggle "Allow landscape" — orientation lock updates
- [ ] Toggle "Show date" in Settings — widget preview refreshes
- [ ] Toggle "Show date" in Settings on the phone, confirm the watch card updates without relaunch (requires paired watch simulator or device)
- [ ] `--seed` UI test launch: run `make ui-test` and verify the seeded store path still works
- [ ] Run watch app in simulator: reminder card renders, skip/complete works, refresh shows spinner; end-to-end sync: phone push → watch app updates without relaunch

## Notes / Adaptations from Plan
- **Phase 5** (AppViewModel): the plan's `setupSyncObservation()` snippet used `lazy var` local initials inside a `@Sendable` observer closure — a Swift 6 concurrency error. Implemented with plain stored `lastShow*` properties + a `Task { @MainActor in ... }` handoff to `handlePreferencesChanged()`. Behavior identical to plan intent.
- **Phase 6** (Watch): the confirmation-dialog `$isShowingRefreshConfirmation` binding required a `@Bindable` wrapper inside `reminderCard` (plan snippet didn't supply a binding). Sync-service wiring extracted to a `setupSyncService(arguments:)` helper to satisfy `function_body_length` lint. `MinimumDisplayDuration.remainingSleep` reused.
- Dead code flagged by Periphery in the full gate was removed (`ContentView.init(store:)` convenience init; unused `import SingleThreadCore` in `SettingsViewModel`).
- The full gate's Periphery step reads a shared Xcode GUI index store that could go stale; `make periphery` (CI-identical) passes clean. All phases verified via `./scripts/test.sh`.