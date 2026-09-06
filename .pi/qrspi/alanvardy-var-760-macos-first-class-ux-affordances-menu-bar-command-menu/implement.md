# Implementation Summary

Ticket: var-760 — macOS first-class UX affordances (menu bar, command menu, notifications)
Branch: `alanvardy-var-760-macos-first-class-ux-affordances-menu-bar-command-menu`
PR: #159

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `c4dd6d1` | NotificationScheduler foundation (SingleThreadCore) — `UserNotificationCentering` protocol seam + `@MainActor` scheduler (decideAction / schedule / cancel / permission / pending) + 13 unit tests |
| 2     | `0e463fa` | AppViewModel rewiring + macOS scheduling triggers — scheduler replaces the iOS notification blob; `onRemindersChanged` triggers macOS schedule-on-data-change (covers launch via initial `start() → reload()`) |
| 3     | `2c1eeda` | App commands — `CommandMenu` ("Reminder" Complete/Skip, "Appearance" System/Light/Dark Picker), About/Quit app-menu groups via `appCommands` (`@CommandsBuilder` adaptation), `@State` view model + `@AppStorage` appearance |
| 4     | `66d213e` | MenuBarExtra — live next-reminder dropdown (`MenuBarExtraOptions`) + headless content tests |

All phases pushed to `origin` (branch is on top of current `origin/main` `bcea150`; one rebase absorbed main's mid-session moves — var-789 commits + the watch lint fix).

## Automated Checks

- [x] `make mac-build` passes (Phases 2-4)
- [x] `make mac-test` passes on macOS — all tests green **except 2 pre-existing StoreKit `EntitlementStoreTests`** (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`), proven to fail identically on the clean tree (Phase 1 worker verified) and untouched by this branch; CI's `mac-tests` job passes those on main, so they are a local macOS StoreKit-sandbox host quirk
- [x] `make test` passes (iOS unit run, Phase 1)
- [x] Targeted iOS notification UI regression (Phase 2): `NotificationSchedulingUITests` / `NotificationsUITests` / `NotificationsSettingsUITests` — all 8 tests pass **unchanged**, proving the extraction preserved iOS semantics
- [x] `make format` + `make lint` pass (0 violations, `--strict`; phases 1, 3, 4)
- [x] Full `./scripts/test.sh` gate run ONCE (parent, after all phases): format ✅ SwiftFormat check ✅ SwiftLint ✅ build ✅ watch build ✅ Periphery ✅ iOS unit ✅ iOS UI ✅ watch UI ✅ watch unit ✅ macOS unit — failed only on the 2 pre-existing `EntitlementStoreTests` above (GATE_EXIT 65, local-environment-only). CI (`.github/workflows/ci.yml`, run 34009151847) is running on the pushed head with all jobs queued/in-progress.

## Deviations from the plan (documented, all within plan intent)

1. **Scheduler API is `public`** (plan snippets showed internal): Phase 2 constructs it from the app target via plain `import SingleThreadCore`, matching `ReminderStore`/`EventKitStoring` conventions. `@MainActor` is also on the protocol (Swift 6 strict-concurrency requirement when awaiting the non-Sendable existential).
2. **`appCommands` uses `@CommandsBuilder`** (Phase 3): the plan's multi-`CommandGroup`/`CommandMenu` free function returning `some Commands` doesn't compile without the result-builder attribute — the standard SwiftUI mechanism for exactly this shape.
3. **MenuBarExtra is always-present, empty-content when nothing due** (Phase 4): the plan's primary "hide entirely" design — `if !visibleReminders.isEmpty { MenuBarExtra … }` inside the `@SceneBuilder` — crashes the Swift 6 compiler with an internal error ("failed to produce diagnostic for expression") on `SingleThreadApp.swift:14`. This is exactly the plan's documented fallback (design amendment 4); the extra's content view already returns empty content when no reminder is due. Both new files untouched by SwiftFormat.
4. **`lastScheduleSummary` survives an add failure** (Phase 2): old iOS code zeroed it on `center.add` throw; the scheduler wrapper leaves it untouched. Unreachable via UI tests; documented divergence.
5. **macOS scheduling trigger** follows the plan's deviation note: schedule-on-data-change (initial `reload()` fires `onRemindersChanged` at launch) instead of a `MacAppDelegate` `applicationDidFinishLaunching` hook; permission request folded into the same trigger (lazy, self-guarding on `.notDetermined`, macOS always `enabled: true`, 48h interval fallback).

## Manual Verification Items (from the plan)

- [ ] Phase 2: `make mac-run` — on first launch with a due reminder, macOS shows the notification permission prompt; after granting and with a signed/entitled build (design Open Risk: sandbox + hardened runtime), a notification is scheduled for the due reminder.
- [ ] Phase 3: `make mac-run` — Application menu has "About SingleThread" (opens the About sheet) and "Quit SingleThread" (exits); the Reminder menu's Complete/Skip mutate the current reminder; the Appearance Picker switches System/Light/Dark and the change applies immediately.
- [ ] Phase 4: `make mac-run` — the menu-bar item (always present under the compiler-crash fallback) shows the next due reminder's title/actions when one is due and an empty menu when none is due; Completing/Skipping mutates the reminder and clears the strip; "Open SingleThread" activates and fronts the window.

## Observations for review

- **StoreKit local quirk**: any reviewer running `./scripts/test.sh` locally will see the 2 `EntitlementStoreTests` fail on the macOS host; CI is authoritative for those.
- **Concurrency incident (resolved)**: during Phase 1, a concurrent var-792 worktree agent crossed `git stash` push/pop on the shared `refs/stash`; all work was recovered (backup `/tmp/concurrent_wip_backup_1788663562.patch`), nothing lost. Until var-792 finishes, avoid `git stash` on this repo.
- **Periphery** ran clean in the full gate — no dead code introduced.
- No macOS UI tests per var-788 decision (macOS verified by unit run + `make mac-run` manual items); no `UNUserNotificationCenterDelegate`/foreground banner per resolved amendment 3; no WidgetKit macOS work, no new persistence keys, no repeating timer (out of scope).