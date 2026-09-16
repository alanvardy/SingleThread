# Implementation Summary

VAR-1018 — App Intents for "What's Next", "Complete Current Task", "Skip Current Task".

All four plan phases implemented, verified, and committed (one commit per phase) on
`alanvardy-var-1018-app-intents`. `plan.md` has every automated verification item checked;
all remaining unchecked items are manual.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `1153f573` | Walking skeleton — `WhatsNextIntent` reachable from the system (`ReminderIntentSupport` + outcome enum, `AppShortcutsProvider`, `requestFullAccessCallCount`, 3 six-language App-catalog keys, 6 support tests + 2 intent tests) |
| 2     | `6e06a95f` | `CompleteCurrentTaskIntent` — `.completed` outcome + `completeOutcome`, second `AppShortcut`, 2 six-language catalog keys, 4 completeOutcome tests + `makeGatedStore` fixture |
| 3     | `f3df1ed1` | `SkipCurrentTaskIntent` — `.skipped` outcome + synchronous `skipOutcome` (durable via `skipCurrentReminderImmediately`), third `AppShortcut`, 2 six-language catalog keys, 4 skipOutcome tests |
| 4     | `90b377a9` | Hardening — `.nothingLeftToDo` outcome + `noVisibleOutcome` fallback, `Everything is skipped for now.` key, two phrases per shortcut, 3 new/renamed support tests, title-collision test, `make mac-build` green |

Each commit also carries the `plan.md` checkbox updates for its phase. The branch-bootstrap
`DELETEME` was removed in the Phase 1 commit. All commits pushed to `origin/alanvardy-var-1018-app-intents`
(remote tip `90b377a9`). Note: push after Phase 1 required `--force-with-lease` because the
mandated `git rebase origin/main` had rewritten the stale bootstrap commit; the remote's old
tip was verified to be its ancestor (same DELETEME content).

## Automated Checks

Across all four phases (each verified with `make format`, `make lint`, targeted
`scripts/test-one.sh` suites, `make test`, `make build`; Phase 4 additionally `make mac-build`):

- [x] `ReminderIntentSupportTests` — 16 cases green in Phase 4 state (makeStore ×3, nextOutcome ×4, completeOutcome ×4, skipOutcome ×4, distinguishHidden/empty + non-empty dialog)
- [x] `ReminderIntentsTests` — 7 cases green (widget intents + all three new intents discoverable/titled, no title collisions)
- [x] `LocalizationTests` — all green incl. `catalogsHaveAllSixLanguages` (new App-catalog keys carry all six languages; no Core-catalog contingency needed)
- [x] `make build` — iOS simulator build `** TEST BUILD SUCCEEDED **` in all four phases (AppShortcutsProvider compiles, incl. under Phase 4's final two-phrase form; no `shortcutTileColor`/`nonisolated` additions demanded)
- [x] `make mac-build` (Phase 4) — `** BUILD SUCCEEDED **` under local Xcode 27.0 macOS SDK
- [x] `make format` / `make lint` — 0 violations, no `@Test` renamed
- [x] `make test` — only the 3 documented pre-existing local-only `EntitlementStoreTests` failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`); no other failures in any phase (annotated, not debugged, per AGENTS.md)

## Manual Verification Items (from the plan)

- [ ] Phase 1: Install the built app on a simulator/device with Reminders access; long-press the app icon → the menu shows **"What's Next"**; run it → the current task's title is spoken/shown. **If absent, apply Risk 2 fallback before Phase 2.**
- [ ] Phase 1: Seed an empty reminder list (or deny Reminders access) → running the shortcut speaks the "nothing to do" / access message instead of failing.
- [ ] Phase 2: Run "Complete Current Task" from the Shortcuts app **and** the app-icon long-press menu; confirm the Reminders item flips to completed and the widget/app reflect it; the dialog names the task.
- [ ] Phase 2: Re-run with an empty list → "nothing to do" dialog, no error.
- [ ] Phase 3: Run "Skip Current Task" from the app-icon long-press menu; confirm the dialog names the task and the task disappears from the list.
- [ ] Phase 3: **Durability**: immediately relaunch the app and confirm the skipped task is still skipped (the synchronous write survived).
- [ ] Phase 4: Set the simulator/device locale to a non-English language (e.g. `de` or `ja`) and run each shortcut: dialogs and short titles render translated, not raw English.
- [ ] Phase 4: Confirm the app-icon long-press menu lists all three shortcuts with the expected short titles.
- [ ] Phase 4: **CI floor**: the `AppShortcut` initializer used is available since iOS 17 and `shortcutTileColor` is defaulted, so Xcode 26.6 should accept it; confirm via the `run-gate` subagent's iOS build. If CI's 26.6 SDK rejects the provider, add `static var shortcutTileColor: ShortcutTileColor { .indigo }`.
- [ ] Phase 4: Siri phrasing, Spotlight, and the physical-device app-icon menu are manual only and not covered by any local gate; spot-check Siri if a device is available.

## Observations for the final review

- **`AppShortcuts.xcstrings` was not auto-extracted** by either `make build` or `make mac-build`
  (only `Localizable.xcstrings` exists under `SingleThread/Resources/`). Per the plan's conditional,
  no phrase translations were filled. If CI's Xcode 26.6 extraction differs, the phrases catalog
  may appear there — worth confirming in the review/gate.
- **Design-phase artifacts were never committed**: `design.md`, `research.md`, `structure.md`,
  `conventions.md`, `task.md`, `large.md`, `questions.md` under `.pi/orksorksorks/alanvardy-var-1018-app-intents/`
  remain untracked (only `plan.md` was committed with Phase 1). They predate the implement step;
  decide whether to include them before merge.
- **Small worker adaptations from plan literals** (all semantic-preserving, compiled/passed):
  `perform()` bodies use the Swift if-expression form; the Phase 4 `makeStore` fixture passes
  `hasHidden` after `authorizationStatus` to match `ReminderStore`'s declaration order; extra
  doc comments on outcome cases.
- **UI tests**: none added — there is no UI-test seam for system intent invocation (per AGENTS.md policy).
- **Full gate**: the CI-identical `./scripts/test.sh` has NOT yet run — launch it once via the
  `run-gate` skill (one async gate subagent, managed worktree) after review.