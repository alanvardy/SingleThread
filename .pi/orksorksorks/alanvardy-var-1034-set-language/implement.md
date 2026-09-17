# Implementation Summary

All 6 phases of the language-picker plan (VAR-1034) are implemented and pushed
on `alanvardy-var-1034-set-language`. The full CI-identical gate
(`./scripts/test.sh`) has **not yet run** — it is owned by the `run-gate` skill
(see "Remaining full-gate work" below).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `accf9502` | walking skeleton — language picker switches the Interface screen |
| 2     | `f346a101` | shared strings become deferred localized resources |
| 3     | `1e32d5e7` | language sync to watch and widget |
| 4     | `311e2818` | reminder and main-screen surfaces localized |
| 5     | `d1c8aaac` | settings, purchase, and about surfaces localized |
| 6     | `e161c0a6` | hardening — locale change sticks everywhere |

Branch tip: `e161c0a6` (fast-forward chain `accf9502 → f346a101 → 1e32d5e7 →
311e2818 → d1c8aaac → e161c0a6`), pushed to origin.

## Automated Checks (all passed)

- [x] **Phase 1**: `AppLanguageTests` 6/6 · `SettingsViewTests` 16/16 ·
  `AppearanceModeTests` 5/5 · `TextSizeTests` 7/7 · `make build` · format+lint.
- [x] **Phase 2**: `LocalizationTests` 5/5 · `AppLanguageTests` 7/7 (incl.
  `sharedStringResolvesToEveryShippedLanguage`) · `ReminderRecurrenceFormatterTests`
  2/2 · `ReminderDisplayTests` 9/9 · `ShowRecurrenceTests` 1/1 ·
  `SingleThreadTests` 8/8 · `ReminderPriorityTests` 3/3 · `ReminderSkipLogicTests`
  2/2 · `ReminderNotesFormatterTests` 2/2 · `ReminderSortTests` 11/11 ·
  `make watch-build` · `make build` · format+lint.
- [x] **Phase 3**: `AppLanguageSyncTests` 3/3 · `make watch-test` 53/53 (incl.
  `watchAppLanguageReceiveUpdatesLocaleState`) · `make watch-build` · format+lint.
- [x] **Phase 4**: `LocalizationTests` 5/5 · `SingleThreadTests` 9/9 (incl.
  `rescheduleStringResolvesInGerman`) · `SortOptionTests` 5/5 · format+lint ·
  `String(localized:)` audit (only Phase-5-scope sites + helper remained).
- [x] **Phase 5**: `LocalizationTests` 5/5 (144 App keys) · `SettingsViewTests`
  16/16 · format+lint · `String(localized:)` audit (only the `resolved(in:)`
  helper remained).
- [x] **Phase 6**: UI test `testLanguageSelectionChangesVisibleString` 1/1
  (Appearance → Darstellung flip inside the presented sheet, no relaunch) ·
  UI test `testUnsupportedStoredLanguageFallsBackToSystem` 1/1 (unsupported
  `klingon` degrades to `.system`) · format+lint · final audits: sole prod
  `String(localized:)` is the `resolved(in:)` helper body
  (`LocalizedString+Shared.swift:111`); no `SharedStrings.` accessor consumed as
  a bare `String`.

Key decisions made during implementation (with evidence):
- **No `.id(locale)` / no sheet `.environment`** — the nav-title/sheet
  re-localization risk from the design did not materialize on the iOS 27 SDK:
  the UI test proves an already-presented sheet + pushed row re-localize live
  via the root `.environment(\.locale)` driven by `@Observable`
  `AppLocaleState.current`.
- **macOS `Commands` has no `.environment`** — the command menus resolve via
  `resolvedInAppLanguage()` (non-View pattern, consistent with plan deviation 3).
- **`test-one.sh`'s time bound is its 2nd positional arg** — needed for the
  cold UI-test builds (600 s default was too short).

## Manual Verification Items (gathered from plan.md — NOT yet done; user confirms)

- [ ] Launch under a non-English system locale (e.g. set simulator language to
  German), open Settings → Interface, pick **English** — “Darstellung” becomes
  “Appearance”, the Appearance/Text Size picker values flip too, and the language
  row shows the endonyms. No relaunch.
- [ ] Cold-launch the app — the Interface screen is still English (persisted via
  the App Group suite), and `AppGroup.defaults` shows `appLanguage = en`.
- [ ] Pick **System** — labels return to the device language.
- [ ] Launch, pick Deutsch: the main screen’s Complete/Skip/Delete/All Done/No
  Reminders labels, the recurrence summary on a repeating reminder, and the
  empty-state card all show German.
- [ ] `rg -n 'String\(localized:' SingleThread SingleThreadCore
  SingleThreadWatch SingleThreadWidget` — every remaining hit is debug-only or
  the `resolved(in:)` helper (verified by the Phase 4/5/6 audits; confirm on the
  final tree).
- [ ] Pair a watch sim, launch both apps, pick **日本語** on the phone; the watch
  UI flips without a relaunch.
- [ ] Put a widget on the Home Screen, change language on the phone; the widget
  timeline refreshes and the due-date row renders in the new language.
- [ ] Relaunch the watch app with the phone closed — it stays in 日本語
  (`.standard` seed).
- [ ] Run the reminder flows (card, dictate, reschedule, empty state, filter/sort
  settings) in **Deutsch** and **日本語** — no leftover English on any
  reminder-facing screen.
- [ ] Walk the full settings stack + purchase + about + macOS menu bar in
  **Deutsch** and **日本語** — no leftover English.
- [ ] Switch language while a reminder card and a reschedule sheet are open — the
  sheet’s chrome (DatePicker month names) follows the new locale.
- [ ] macOS (if in scope for the session): menu bar extra + Commands menu labels
  switch.

## Remaining full-gate work (review/merge step, per plan "Full gate")

- [ ] After all six phases are committed, launch the **`run-gate` skill** (one
  async gate subagent in a managed worktree, multi-hour timeout) to run
  `./scripts/test.sh` **once**. Do not `nohup` it ad-hoc.
- [ ] Before merging: `git rm DELETEME` (branch-bootstrap marker; currently
  un-deleted in the working tree).

## Observations / notes for review

- **Pre-existing macOS app-target break (not ours)**: `make mac-build` fails at
  HEAD *and* on `origin/main` — `SkipSyncSession` used in `AppViewModel.init`'s
  `session:` param is iOS/watchOS-only (since commit `0bcce49f`). `./scripts/test.sh`
  does not build macOS, so it does not gate the branch; CI `mac-tests` would be
  red for any main push until fixed. Flagged; not touched per "no refactoring".
- **Orphan `Purchase` catalog key**: added per the plan (design noted it
  missing), but the current code has no literal consumer (purchase screen uses
  `Unlock`/`Restore Purchases`/`Manage Purchase`). Invariant-safe; reviewers may
  drop it.
- **macOS-only edits** (Phase 5/6: `MenuBarExtraOptions`, `SingleThreadApp+Commands`,
  `MenuBarExtra` env, Appearance submenu tags) are not compile-verified locally
  (macOS target pre-broken); they were eye-reviewed and SDK-type-checked. CI
  mac-tests (when macOS target is fixed) will compile them.
- **Plan deviations applied**: enum titles → resources (dev 1), the Phase 2
  consumer set (dev 2), `nonisolated static storedEffectiveLocale` for non-View
  sites (dev 3), uncatalogued endonyms (dev 4), `--ui-testing-app-language` seam
  (dev 5), catalog-key-driven literal sweep (dev 6).
- **Infrastructure note**: the Phase 1 and Phase 5 first attempts died on
  engine/tooling failures (no work lost; relaunched); Phase 4 and Phase 6 hit
  their run deadlines mid-verification and were resumed with the same worker
  context (uncommitted work preserved and completed).