# Implementation Summary

Ticket: **Allow disabling of macOS dock widget** — PR #194 (draft)

Shipped surface is the macOS **menu bar extra** (the "dock widget" misnomer is called out in the PR
description): a Settings → Interface "Show in Menu Bar" toggle (default on) backed by
`UserDefaults.standard["showMenuBarExtra"]` and bound to the `MenuBarExtra` scene via
`isInserted:`, so the icon appears/disappears live. Everything `#if os(macOS)`-gated.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `8dc631f7` | Preference constant + defaults (`MenuBarExtraPreference`, test suite) |
| 2     | `0a8d4d2b` | Settings data plumbing (bag member, `@AppStorage`, write-back, 3 tests) |
| 3     | `87a64e6e` | Settings UI — macOS-only Interface toggle (+localization, 2 content tests) |
| 4     | `4a3f7807` | Scene wiring — `isInserted` effect (`SingleThreadApp`) |
| Final | `87f94776` | Remove branch bootstrap marker (`git rm DELETEME`) |
| —     | `0a825346` | chore: finalize implement summary + plan checkboxes (artifacts) |

## Automated Checks

- [x] Phase 1: `make mac-test` (new suite passes; only the 3 documented pre-existing
      local-only `EntitlementStoreTests` failures remain) — targeted
      `MenuBarExtraPreferenceTests` ran exactly **2 cases** — `make format` + `make lint` clean
- [x] Phase 2: `make mac-test` — targeted `SettingsViewTests` includes the 3 new cases
      (`showMenuBarExtraRoundTripsThroughBag`, `showMenuBarExtraDefaultsToShownInBag`,
      `macOSBagDefaultsToShown`) — `make build` (iOS) passes — format + lint clean
- [x] Phase 3: `make mac-test` — targeted `SettingsViewTests` includes
      `interfaceSettingsViewContainsMenuBarToggle` + `interfaceSettingsViewOmitsMenuBarToggleCopy`
      (exact-once counts held, no fallback needed) — `make build` (iOS) passes (toggle gated out) —
      `.xcstrings` validated via `json.load` (see note) — format + lint clean
- [x] Phase 4: `make mac-build` passes — `make build` (iOS) passes — `make mac-test` no new
      failures — format + lint clean
- [x] `isInserted:` icon-removal effect: **UNVALIDATED in CI** (framework behaviour, no seam, no
      test-only helper — Periphery `--strict` would flag it). Covered by manual checks only.
- [x] Full CI-identical gate (`./scripts/test.sh`) — ran via the run-gate skill (async gate
      subagent, managed worktree) at branch tip `0a825346`. **Verdict: all stages PASS** (format,
      lint `--strict`, iOS build, watch build, Periphery "No unused code detected", iOS UI,
      watch UI, watch unit) — **643 cases passed**; only the 3 documented pre-existing local-only
      macOS `EntitlementStoreTests` fail on this machine (CI green on fresh runners). Gate log:
      `/tmp/gate-alanvardy-var-815.log`. First attempt aborted at the Watch UI stage on an
      ambiguous name-only Apple Watch destination (two watch runtimes installed); re-run with
      `SIM` + `WATCH_TEST_SIM` pinned passed cleanly end-to-end. No orphaned processes or crash
      dumps left behind.
- [x] Plan's conditional Periphery fix — **not triggered**: `make periphery` reported
      "No unused code detected" for `SettingsBindings.showMenuBarExtra`; no `// periphery:ignore`
      added.

## Manual Verification Items (from the plan)

- [ ] Phase 3: `make mac-run`; open Settings (gear) → **Interface**: the "Show in Menu Bar" toggle
      is visible below "Show action buttons" with its caption.
- [ ] Phase 3: Toggle it off, close the sheet, reopen Settings → it reads off.
- [ ] Phase 3: Quit and relaunch the app, reopen Settings → still off.
- [ ] Phase 4: With the toggle **off**, the menu bar icon disappears immediately (no relaunch).
- [ ] Phase 4: Relaunch the app → the icon is still gone (persisted).
- [ ] Phase 4: Open Settings → Interface, toggle **on** → the icon returns immediately.
- [ ] Phase 4: With the icon visible, ⌘-drag it off the menu bar → reopen Settings → the toggle
      reads off.
- [ ] Phase 4: Confirm the app's Dock icon and ⌘-Tab entry remain (recovery path intact; not
      `LSUIElement`).
- [ ] Phase 4: Reset the preference between checks with
      `defaults delete app.alanvardy.SingleThread showMenuBarExtra`.
- [ ] Final: Confirm every checkbox above is ticked and the macOS manual checklist in Phase 4
      passed on a real macOS run.
- [ ] Final: Merge with `gh pr merge 194 --rebase --delete-branch` (merge commits and squashes are
      disabled).

## Notes / Observations

- **Actor isolation**: `MenuBarExtraPreference.key`/`defaultValue` are `@MainActor`-isolated in the
  app target (per-target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); the iOS/iOS-shared test
  targets are not. Phase 1's test suite needed an explicit `@MainActor` annotation (matched to the
  existing `MenuBarExtraOptionsTests` convention); `SettingsViewTests` was already `@MainActor`.
- **`plutil -lint` quirk**: on this machine `plutil -lint` fails to JSON-detect `.xcstrings` on the
  *unmodified* file too (pre-existing toolchain quirk, not this change). The `.xcstrings` edit was
  validated with `python3 -c json.load` (both keys, 6 languages each). CI's Xcode build consumes
  it as-is.
- **Pre-existing local-only test failures** (not debugged, per AGENTS.md): the three macOS
  `EntitlementStoreTests` failures (`isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — CI mac-tests are green on fresh
  runners.
- SwiftFormat's `organizeDeclarations` dropped an explicit `@Suite` attribute in Phase 1 and
  normalized a one-line `if let` in Phase 2 — cosmetic.
- Plan deviation noted up front (Overview): `SettingsBindings.init` uses a plain `= true` literal
  (the macOS-only preference type can't be referenced from the cross-platform bag); protected by
  the `macOSBagDefaultsToShown` drift-guard test.