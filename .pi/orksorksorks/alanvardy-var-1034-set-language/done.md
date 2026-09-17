# Done

- **Branch / head SHA**: `alanvardy-var-1034-set-language` · final code commit
  `a1d045e2` (rebased onto `origin/main` `da2a4915`, pushed; `DELETEME`
  removed in `068f7145`).
- **Mechanical checks**:
  - `make format` + `make lint` (SwiftFormat `--lint` + `swiftlint --strict`):
    **pass**, 0 violations (194 files, incl. the new
    `SingleThread/AppLanguage+Presentation.swift`).
  - `make build` (iOS `build-for-testing`, worktree sim
    `D4C34BCA-7C96-418E-BDD3-BB22738A69C7`): **TEST BUILD SUCCEEDED**.
  - Targeted iOS suites after every fix: `AppLanguageTests` (7/7),
    `AppLanguageSyncTests` (3/3), `LocalizationTests` (5/5),
    `SettingsViewTests` (all pass); UI tests
    `testLanguageSelectionChangesVisibleString`,
    `testUnsupportedStoredLanguageFallsBackToSystem`, and
    `testLaunchAndRenderSmoke` (accessibility audit) — **all pass**.
  - Full `./scripts/test.sh` (async gate subagent, worktree at `068f7145`):
    **aborted at the Periphery stage before any test suite ran.** 7 findings:
    5 are the documented local Xcode-27 index-reuse false positives
    (`appCommands` + the macOS-only `viewModel`/`appearanceMode`/
    `showMenuBarExtra`/`showAbout` in `SingleThreadApp.swift`; verified
    identical on `origin/main`, so not a regression), and 2 were genuine
    (fixed below). Re-scan after the fix shows the same 5 local-only findings
    plus a stale-index echo of the removed symbol. CI's build-in-scan
    Periphery is authoritative for the full gate.
- **Review outcome** (one bounded reviewer, fresh context; no P0/P1
  blockers found):
  - **Blockers fixed**: removed `AppLanguage.localeIdentifier` (unused public
    property; `retain_public: false` means CI Periphery would fail), and the
    unused `@testable import SingleThread` in `AppLanguageTests.swift`.
  - **Fixes worth doing now, applied**: the `--ui-testing-app-language` seam
    previously rewrote the staged raw value with the validated `.system`,
    so `testUnsupportedStoredLanguageFallsBackToSystem` could not observe the
    fallback it claimed to test. The rewrite is removed; the seam now leaves
    the staged value intact and `AppLocaleState` validates on its own startup
    read (UI test re-run green).
  - **Optional improvements, applied on request**: (P2-3) moved
    `AppLanguage.title` out of `SingleThreadCore` into the app target
    (`SingleThread/AppLanguage+Presentation.swift`), mirroring
    `SortOption`/`TextSize` — Core no longer names the App bundle.
    (Nit) `ContentView`'s refresh `accessibilityValue` now uses the existing
    `resolvedInAppLanguage()` / empty-`String` pattern instead of an empty-key
    `LocalizedStringResource`.
  - **Deferred / no action**: (P2-2) `nonisolated storedEffectiveLocale`
    reading `UserDefaults` off the main actor is fine — `UserDefaults` is
    documented thread-safe and the compiler accepted it; no change.
    (P2-4) the appLanguage sync key is pushed unconditionally rather than
    gated on "explicitly set"; behaviourally benign (`.system` ≈ device
    locale). The widget timeline-refresh question remains a manual check.
- **Remaining manual items** (from `implement.md`; not run here): the
  on-device/simulator checklist — non-English system locale picker flip, cold
  launch persistence, System reset, German/Japanese reminder + settings +
  purchase + about surfaces, watch paired flip, widget timeline refresh,
  watch-with-phone-closed relaunch, macOS menu bar. `make mac-build` remains
  broken on `origin/main` (iOS-only `SkipSyncSession`), so the macOS-only
  Command/MenuBarExtra edits are eye-reviewed only; CI `mac-tests` will
  compile them once the pre-existing macOS break is fixed.

## Follow-up fix (post-review): navigation titles

**Symptom reported**: switching Japanese → English left the Settings sheet's
root "Settings" header in Japanese until the sheet was closed and reopened.

**Root cause**: SwiftUI resolves a `LocalizedStringKey` `.navigationTitle` once,
against the system/per-app language, and does not re-resolve it when
`.environment(\.locale)` changes (iOS 18+ regression, still present in iOS 26).
Row labels and pushed screens re-evaluate; the root screen's title does not.

**Fix**: new `SingleThread/LocalizedNavigationTitle.swift`
(`localizedNavigationTitle`, which resolves the resource against
`@Environment(\.locale)`) and applied to every settings screen's title (Settings,
Interface, Notifications, Reminder, Filtering & Sorting, Background, Purchase,
Excluded Lists, Privacy, About). This keeps navigation state (no `.id(locale)`
stack re-key, which would pop to root and contradict the live pushed-screen
behaviour).

**Verification**: extended `testLanguageSelectionChangesVisibleString` to assert
the pushed title (`Oberfläche`) and the root title (`Einstellungen`) re-localize,
plus a second switch back to English in the same session. Red-first confirmed
against the pre-fix code (`TEST FAILED` on the root-title assertion), then green.
Affected unit suites re-run green (`SettingsViewTests`, `AboutViewTests`,
`SettingsSubscreenLayoutTests`, `MicrophoneToggleTests`, `AppLanguageTests`);
`make format`/`make lint` 0 violations.
