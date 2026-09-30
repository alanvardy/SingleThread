# Done

- **Branch / head SHA**: `alanvardy-var-1105-add-sentry-crash-reporting-for-per-crash-email-alerts` @ `37a8ad41`
- **Mechanical checks**: full CI-identical `./scripts/test.sh` gate **PASS** on `37a8ad41`
  (log `/tmp/gate-sentry2.log`, final marker `✅ All CI checks passed.` — deploy-target/package-floor
  checks, wrapped-xcodebuild check, SwiftFormat, SwiftLint `--strict` (0 violations), warning-check
  self-test (20 fixtures), iOS build, watch build, Periphery (`No unused code detected`), iOS UI tests
  (incl. accessibility audit), watch UI tests, watch unit tests, macOS unit tests, and
  `✓ no un-allowlisted compiler warnings` in every build stage). Supporting local checks:
  `make format`/`make lint` clean, `make mac-build` BUILD SUCCEEDED, `make mac-test` exit 0,
  `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` 6/6 cases.
- **Review outcome**:
  - **Blocker found by the gate and fixed:** the first gate run failed deterministically at the macOS
    unit-test build — `SentryBootstrap.swift` set `options.attachScreenshot`/`attachViewHierarchy`,
    which sentry-cocoa 9.29.2 declares only for UIKit-backed platforms (`#if os(iOS) || os(tvOS) ||
    os(visionOS)`), so the native macOS target did not compile. Fixed in `37a8ad41` by guarding both
    assignments; the re-run gate passed.
  - **Fixes worth doing now applied** (review pass, `c0337404`): `SentryScrubber` now also nils
    `event.message`, `event.transaction`, and every `Exception.value` (keeping `type` and the stack
    trace), so the in-app "never includes any reminder, preference, or list content" disclosure is
    literally true including the macOS `NSException` path; stale `SentryBootstrap` doc parenthetical
    removed; `SettingsBindings` header corrected for the device-local `crashReportingEnabled`;
    `ci_post_xcodebuild.sh` PATH/`command -v sentry-cli` hardening; trailing newlines restored on the
    plists, ci scripts, and `docs/CrashReporting.md`; two new `SentryScrubberTests` cases.
  - **Optional declined:** tightening the sentry-cocoa `upToNextMajorVersion` 9.x requirement (the
    plan intentionally allows the 9.x line).
  - **Flake flagged, not a product defect:** on the first (contended) gate run — a parallel
    var-1112 gate was using a different simulator — one UI case
    (`testLanguageSelectionChangesVisibleString`) failed during simulator contention; the clean
    restarted run passed. Worth watching on CI, no local evidence of a defect.
  - Reviewers' residual risks (resolved-API spellings, `PrivacyInfo.xcprivacy` packaging, Xcode Cloud
    scripts) are covered by the gate and the manual items below.
- **Remaining manual items** (require a real Sentry DSN, Xcode Cloud, dashboard, or devices — from `plan.md`):
  - Phase 1: `SENTRY_DSN='…' make build`; boot/install/launch; trigger a deliberate crash and confirm a
    new event in Sentry with `environment=debug` and no user identity.
  - Phase 2: repeat that crash and confirm the dashboard event has symbols and **no** reminder
    title/note/list name anywhere.
  - Phase 3: toggle crash reporting off → crash → relaunch → no new event; toggle on → event again;
    confirm the toggle persists across relaunch.
  - Phase 4: archive a Debug build and confirm `PrivacyInfo.xcprivacy` is in the bundle; generate the
    Privacy Report (Crash Data + the four reason codes); confirm the in-app Privacy screen shows 5
    sections and the background section no longer claims "only network request"; set the App Store
    Connect App Privacy label (Diagnostics → Crash Data, not linked, not tracking, App Functionality).
  - Phase 5: run an Xcode Cloud archive and confirm the dSYM upload succeeds (needs `SENTRY_ORG`,
    `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` in the workflow Environment) and that a Release crash email
    is symbolicated; recreate the "email me on every new crash" issue alert in Sentry.
  - Phase 6: trigger the deliberate crash on iOS simulator and on macOS; on macOS trigger an uncaught
    `NSException` and confirm capture; toggle off before a crash on both platforms and confirm
    suppression.
- **Operational inputs still required from the user**: the Sentry DSN, and `SENTRY_ORG` /
  `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` (token as Secret) in the Xcode Cloud workflow Environment.
