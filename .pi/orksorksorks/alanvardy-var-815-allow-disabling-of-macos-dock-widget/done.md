# Done

- **Branch / head SHA**: `alanvardy-var-815-allow-disabling-of-macos-dock-widget` @ `edaa81dc` (PR #194, draft)
- **Mechanical checks**:
  - `swiftlint lint --strict` → 0 violations (187 files) — note: bare invocation; passing `--config .swiftlint.yml`
    suppresses the nested `SingleThreadTests/.swiftlint.yml` and yields 11 false force-unwrap errors.
  - `swiftformat --lint` → 0 files require formatting.
  - Targeted macOS run (`CODE_SIGNING_ALLOWED=NO`, `-only-testing:SingleThreadTests/{MenuBarExtraPreferenceTests,SettingsViewTests}`)
    → **25/25 passed**; confirmed all 7 relevant cases executed by name.
  - Full CI-identical gate (`./scripts/test.sh`) was run once via the `run-gate` skill on the pre-review SHA
    `2cf49d90` and passed (643 cases; only the 3 documented pre-existing local-only macOS `EntitlementStoreTests`
    fail on this machine, CI green on fresh runners). Not re-run after the review fixes — those changes are
    test-only and confined to `#if os(macOS)` blocks already exercised by the targeted run.
- **Review outcome**: One bounded `reviewer` pass over `main...HEAD`. **No blockers (P0/P1)** — mechanism
  (`MenuBarExtra(..., isInserted:)`), macOS gating, `UserDefaults.standard` storage (correctly not App Group),
  default-on, write-back plumbing, 6-language localization, and MainActor/Swift 6 correctness all match the design.
  Fixes applied (commit `edaa81dc`):
  1. `showMenuBarExtraRoundTripsThroughBag` → `showMenuBarExtraRoundTripsThroughContentView`: now constructs a real
     `ContentView`, asserts the absent-key default and `makeSettingsBag()` seeding, then assigns the `@AppStorage`
     property and verifies both the re-seeded bag and the persisted `UserDefaults.standard` value — no longer a
     `UserDefaults` self-round-trip.
  2. Removed the redundant `#expect(MenuBarExtraPreference.defaultValue != false)` in
     `MenuBarExtraPreferenceTests`.
  3. Renamed `interfaceSettingsViewOmitsMenuBarToggleCopy` → `interfaceSettingsViewRendersMenuBarToggleOnce`
     (it asserts exactly-once presence, not omission).
  Declined: reviewer's claim that the exactly-once count (`components(separatedBy:).count - 1`) is fragile —
  that expression counts occurrences robustly regardless of trailing render content.
  The unmockable `isInserted:` icon-removal effect remains `UNVALIDATED` in CI by design and is covered only by
  the manual macOS checks below (repo UI-test-exception policy).
- **Remaining manual items** (from `plan.md`, harness cannot run these):
  - `make mac-run`; Settings (gear) → **Interface**: "Show in Menu Bar" toggle visible below "Show action buttons" with caption.
  - Toggle off, close sheet, reopen → reads off; quit and relaunch → still off.
  - With toggle off, the menu bar icon disappears immediately (no relaunch); toggle on → returns immediately.
  - With the icon visible, ⌘-drag it off the menu bar → reopened Settings shows the toggle off.
  - Confirm the app's Dock icon and ⌘-Tab entry remain (recovery path intact; app is not `LSUIElement`).
  - Reset between checks: `defaults delete app.alanvardy.SingleThread showMenuBarExtra`.
  - Merge with `gh pr merge 194 --rebase --delete-branch` once the checklist and PR review are complete; the PR
    description calls out the "dock widget" misnomer and the Dock-icon-stays assumption.
