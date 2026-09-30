# Implementation Summary

All 6 phases of the Sentry crash-reporting plan implemented, verified, and committed (one commit
per phase, pushed to `origin/alanvardy-var-1105-add-sentry-crash-reporting-for-per-crash-email-alerts`).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `86857720` | Walking skeleton — a real crash reaches Sentry, end to end |
| 2     | `c9b6d033` | Privacy scrubber — no reminder content can leave the device |
| 3     | `c65b8a11` | Consent toggle — the user can turn crash reporting off and back on |
| 4     | `a54287b7` | Truthful disclosures — manifest, in-app copy, App Store label |
| 5     | `c6f1e452` | Symbolicated per-crash alert — dSYM upload + triage docs |
| 6     | `f0b7dcec` | Hardening — sad paths, both platforms, toolchain noise |

## Automated Checks

- [x] Phase 1: `make format` + `make lint` clean; `sentry-cocoa` 9.29.2 resolved (`Package.resolved` committed); `SentryConfigurationTests` (4 cases) pass; `SENTRY_DSN` injects into `Info.plist` (and empty when unset)
- [x] Phase 2: `SentryScrubberTests` (2) and `SentryConfigurationTests` pass; `make lint` clean
- [x] Phase 3: `CrashReportingPreferenceTests` (2), `SettingsViewTests` (16), `LocalizationTests` (5) pass; `make lint` clean
- [x] Phase 4: `PrivacySettingsContentTests` (4), `LocalizationTests` (5) pass; `make lint` clean
- [x] Phase 5: `bash -n` clean, both scripts executable, `shellcheck` clean
- [x] Phase 6: `SentryConfigurationTests` (5), `CrashReportingPreferenceTests` (3), `SentryScrubberTests` (4) pass; `make lint` clean; `make periphery` clean (no unused code detected)
- [ ] Full `./scripts/test.sh` gate — not run during implementation (belongs to the review step via the `run-gate` skill)

> Note: phases 2, 3, 6 were delegated to subagents that produced the correct code but timed out on
> the slow targeted test builds; the parent completed verification and committed them. The SIM
> destination is pinned to the available `iPhone 17` UDID `2BD7F165-…` (the repo's `.simulator_id`
> is stale and was left unmodified).

## Manual Verification Items (from the plan)

Gathered verbatim from `plan.md`; the user confirms these (some require a real Sentry DSN,
on-device/Xcode-Cloud runs, or dashboard access).

- **Phase 1**
  - [ ] `SENTRY_DSN='…' make build`, boot the `iPhone 17` sim from `.simulator_id`, install/launch
  - [ ] Temporarily add a throw-away button/`fatalError` behind a debug flag, trigger it, relaunch the app, and confirm a new event appears in the Sentry Issues dashboard with `environment=debug` and no user identity
- **Phase 2**
  - [ ] Repeat the Phase 1 deliberate crash with `SENTRY_DSN` set; in the dashboard event confirm the stack/symbols are present and **no** reminder title/note/list name appears in `extra`, `user`, or breadcrumbs
- **Phase 3**
  - [ ] Launch a `SENTRY_DSN`-bearing build; Settings → toggle **off**; trigger the deliberate crash; relaunch → **no** new event
  - [ ] Toggling **on** and repeating produces an event again (restart path works)
  - [ ] Toggle remains off/on after an app relaunch (persistence)
- **Phase 4**
  - [ ] Debug archive (`Product > Archive`, or `xcodebuild archive`) and confirm the built app contains the manifest (`PrivacyInfo.xcprivacy` in the app bundle)
  - [ ] Generate Privacy Report and confirm Crash Data + the four reason codes appear (SPM/static-linking merge)
  - [ ] In-app Privacy screen shows 5 sections and the background section no longer claims "only network request"
  - [ ] App Store Connect "App Privacy" label: Diagnostics → Crash Data, not linked, not used for tracking, purpose App Functionality
- **Phase 5**
  - [ ] Run an Xcode Cloud archive and confirm the log shows the dSYM upload succeeding; Sentry → Settings → Debug Files lists the new dSYMs (requires `SENTRY_ORG`/`SENTRY_PROJECT`/`SENTRY_AUTH_TOKEN` in the workflow Environment)
  - [ ] Install the Release build, trigger a deliberate crash, confirm the crash email arrives and the stack is symbolicated
- **Phase 6**
  - [ ] Trigger the deliberate crash on **iOS simulator** and on **macOS** (`make mac-build` + run); confirm both produce scrubbed, symbolicated-on-Release events
  - [ ] On macOS, trigger an uncaught `NSException` and confirm it is captured
  - [ ] Toggle off before a crash on both platforms and confirm suppression

## Inputs still required from the user (operational, not code blockers)

- **Sentry DSN** (`https://…@…ingest.us.sentry.io/…`) — for the dashboard manual checks.
- **`SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN`** — Xcode Cloud workflow Environment
  variables (token **Secret**) for the Phase 5 dSYM upload.
- Sentry region/plan confirmation (design assumed US region, free Developer plan).

## Deviations / notes surfaced during implementation

- `SentryScrubber` rebuilds clean breadcrumbs (preserving level/category/timestamp) instead of
  mutating in place, because sentry-cocoa 9.29 **deprecates** the `breadcrumb.data` setter; the
  same adaptation was applied to the test fixture via `setData(value:key:)`.
- SDK Swift renames used in tests: `User` (was `SentryUser`); `setData(value:key:)`.
- The app target is `@MainActor`-default, so `SentryConfigurationTests`/settings tests are
  `@MainActor`-annotated (matching `SettingsCaptionTests` precedent).
- No full-gate run, no Periphery app-side issues, no `xcodebuild-warnings.allow` edits.