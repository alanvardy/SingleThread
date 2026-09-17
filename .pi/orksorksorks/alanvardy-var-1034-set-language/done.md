# Done

- **Branch / head SHA**: `alanvardy-var-1034-set-language` · final commit
  `0344ae46` (rebased onto `origin/main` `da2a4915`, pushed; `DELETEME`
  removed in `068f7145`).
- **Mechanical checks**:
  - `make format` + `make lint` (SwiftFormat `--lint` + `swiftlint --strict`):
    **pass**, 0 violations (193 files).
  - `make build` (iOS `build-for-testing`, worktree sim
    `D4C34BCA-7C96-418E-BDD3-BB22738A69C7`): **TEST BUILD SUCCEEDED**.
  - Targeted iOS suites after the fixes: `AppLanguageTests` (7/7),
    `AppLanguageSyncTests` (3/3), `LocalizationTests` (5/5) — **all pass**;
    the two new UI tests
    `testLanguageSelectionChangesVisibleString` and
    `testUnsupportedStoredLanguageFallsBackToSystem` — **both pass**.
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
  - **Deferred / optional**: (P2-2) `nonisolated storedEffectiveLocale`
    reading `UserDefaults` off the main actor is fine — `UserDefaults` is
    documented thread-safe and the compiler accepted it; no change.
    (P2-3) `AppLanguage.title` living in Core with `bundle: .main` is a
    consistency nit; low risk (only the app picker uses it, never the watch),
    deferred to avoid a refactor at merge time. (P2-4) the appLanguage sync
    key is pushed unconditionally rather than gated on "explicitly set";
    behaviourally benign (`.system` ≈ device locale) — comment-only.
    Optional nits: the empty-key `LocalizedStringResource("")` accessibility
    branch in `ContentView`, and the widget timeline refresh question — both
    left as-is (manual item below).
- **Remaining manual items** (from `implement.md`; not run here): the
  on-device/simulator checklist — non-English system locale picker flip, cold
  launch persistence, System reset, German/Japanese reminder + settings +
  purchase + about surfaces, watch paired flip, widget timeline refresh,
  watch-with-phone-closed relaunch, macOS menu bar. `make mac-build` remains
  broken on `origin/main` (iOS-only `SkipSyncSession`), so the macOS-only
  Command/MenuBarExtra edits are eye-reviewed only; CI `mac-tests` will
  compile them once the pre-existing macOS break is fixed.
