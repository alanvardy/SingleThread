# Implementation Summary

Organized the single flat `SettingsView` `Form` into a root `List` menu with four
themed sub-views, bound through a single `@Observable` `SettingsBindings` bag. A
`showList` watch-sync prerequisite slice landed first.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `40563de` | Show List Watch Sync |
| 2     | `5da3ea7` | SettingsBindings Bag + Interface Sub-View |
| 3     | `cc56663` | Reminder + Filtering & Sorting Sub-Views |
| 4     | `aacd87d` | Background Sub-View + Root List Menu |
| 5     | `dc2c20f` | UI Test Adjustments + Final Gate |

## Automated Checks

- [x] **Phase 1** — watch sync tests pass (`make watch-test`: all `WatchSyncPipelineTests`,
  incl. 4 new `showList` cases); existing unit tests green; Debug build green; lint 0 violations.
- [x] **Phase 2** — Debug build green; `SettingsViewTests` (updated `settingsViewContainsAllPreferenceRows` + new `interfaceSettingsViewContainsExpectedRows`) pass; full unit suite green; format/lint clean.
- [x] **Phase 3** — Debug build green; `SettingsViewTests` (four focused tests) pass; full unit suite green; format/lint clean.
- [x] **Phase 4** — Debug build green; full unit suite green; `make periphery` — no unused code; format/lint clean.
- [x] **Phase 5** — full `./scripts/test.sh` gate passes (exit 0: format, lint, periphery, build, unit + UI tests incl. accessibility audit on both iPhone 17 and iPad (A16)); full `SingleThreadUITests` suite passes on iPhone 17 (16/16 incl. `testAccessibilityAudit`, appearance tests, ActionButtons audit, and both persistence tests).

### Important fix surfaced by Phase 5 (product regression)

The `SettingsBindings` bag was originally created *inside* the `.sheet(isPresented:)`
content closure in `ContentView`. Because the sheet's write-back `.onChange(of: bag.<key>)`
writes back to `@AppStorage`, each write re-evaluates `ContentView.body`, which re-ran the
closure and built a **fresh bag with the original defaults** — so toggles snapped back and
never persisted. This was a genuine bug from the Phases 2–4 refactor, exposed by the relaunch
persistence UI tests, and fixed in `dc2c20f`:

- The bag is now a `@State private var settingsBag: SettingsBindings?` on `ContentView`,
  recreated once when the sheet opens (via `.onChange(of: isShowingSettings)`) and cleared on
  dismiss, so it stays stable for the sheet's lifetime.
- The sheet body now uses `if let bag = settingsBag { SettingsView(...) }` with a unified
  `.onChange` write-back chain (iOS-only prefs gated with `#if os(iOS)`), replacing the old
  duplicated `#if/#else` construction.

With this fix, toggling Show list / Background in the sub-views persists across relaunch
(the UI tests `testShowListTogglePersistsAcrossRelaunch` and
`testBackgroundToggleHidesAndPersistsAcrossRelaunch` now pass).

## Manual Verification Items (from the plan)

These were gathered from `plan.md` and are intentionally left unchecked for the user to confirm.

- [ ] **Phase 1** — No UI changes; verify that `showList` appears in the app context when a change triggers `pushAll()` (toggle Show list on iPhone pushes the value to a paired watch).
- [ ] **Phase 2** — Open settings → "Interface" NavigationLink visible at top → tap pushes to Interface sub-view showing Appearance, Text Size, Show microphone, and (iOS) Allow landscape + Show action buttons.
- [ ] **Phase 2 (risk)** — Toggle "Allow landscape" in Interface sub-view → verify orientation lock applies. (Fallback to a direct `@Binding` if `.onChange` doesn't fire — not needed based on automated results, but confirm manually.)
- [ ] **Phase 3** — Settings menu shows "Interface", "Reminder", "Filtering & Sorting" NavigationLinks.
- [ ] **Phase 3** — Tap Reminder → Show date / Show list / Recurrence indicator / Reminder alerts toggles visible.
- [ ] **Phase 3** — Tap Filtering & Sorting → Sort By picker, Show undated toggle, Excluded Lists NavigationLink visible.
- [ ] **Phase 3** — Toggle Show date → widget reload fires (verify WidgetKit timeline).
- [ ] **Phase 4** — Settings opens to a clean four-row menu with icons: Interface, Reminder, Filtering & Sorting, Background.
- [ ] **Phase 4** — Each row pushes to correct sub-view.
- [ ] **Phase 4** — Done button dismisses the sheet.
- [ ] **Phase 4** — All toggles, pickers, and Excluded Lists functionality unchanged.
- [ ] **Phase 4** — TextSizeModifier applies to all pushed sub-views (scaled text).
- [ ] **Phase 5** — Settings menu renders four rows, each navigable.
- [ ] **Phase 5** — Background toggle persistence survives relaunch.
- [ ] **Phase 5** — Show list toggle persistence survives relaunch.
- [ ] **Phase 5** — Accessibility audit passes with `List` root.

## Notes / Observations for Review

- The plan's Phase 1 and Phase 5 verification commands for watch tests use
  `-scheme SingleThread ... -only-testing:SingleThreadWatchTests`, but the watch test target
  lives in the `SingleThreadWatch` scheme. The correct invocation is `make watch-test`
  (runs on a watchOS simulator). Intent was satisfied; the plan text is inaccurate.
- UI test `flipToggle` now falls back to tapping the outer switch element when no nested
  switch child exists, which was needed because the persisted-state assertion relies on a
  stable flip in the pushed sub-views.
- Intermittent `FBSOpenApplicationServiceError` simulator-launch messages appear during
  UI/watch runs; the gate re-recovers and the overall run reports success — this is
  environment flakiness, not a code issue.
- `SettingsBindings` still declares the iOS-only prefs (`allowsLandscape`,
  `enableActionButtons`) unconditionally because `#if` is not valid in a Swift init
  parameter list; defaults mirror `ContentView` exactly. Only relevant to a hypothetical
  non-iOS target, which this project does not build.
