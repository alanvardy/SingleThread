# Design Discussion — Sentry Crash Reporting for SingleThread

## Current State

- **One app entry point.** `@main struct SingleThreadApp: App` (`SingleThread/SingleThreadApp.swift:10`)
  compiles for iOS + macOS; the platform split is `#if os(iOS)`/`#if os(macOS)` inside the body
  (`:13-45`). There is **no custom `init`**; the earliest app-authored code is
  `@State private var viewModel = AppViewModel()` (`:55`), and the composition root is
  `@MainActor @Observable AppViewModel.init` (`SingleThread/AppViewModel.swift:27-73`).
  Delegate bridging exists but is appearance/orientation-only (`SingleThreadApp.swift:65-70`,
  `SingleThread/AppDelegate.swift:9-84`). Watch/widget are separate `@main` entry points.
- **Privacy copy is the single disclosure source and is test-pinned.** `PrivacyGuideContent.sections(in:)`
  returns exactly **4** sections (`SingleThread/PrivacySettingsContent.swift:32-63`); the
  `background` section claims "This is the app's only network request" (`:59-64`); `closingLine`
  claims "no analytics, no tracking, and no advertising" (`:67-69`). Copy is localized through
  `LocalizedStringResource(...).resolved(in:)` (`:80-93`), with translations in
  `SingleThread/Resources/Localizable.xcstrings:4495-4531` (6 languages). `PrivacySettingsContentTests.swift`
  asserts the 4-section count + vardy.cc literal (`:13-29`) and the no-analytics closing line (`:32-46`).
- **One SPM dependency, local only.** Project-level `packageReferences` holds a single
  `XCLocalSwiftPackageReference "SingleThreadCore"` (`project.pbxproj:458-460`, `:1228-1233`);
  per-target scope is the `packageProductDependencies` list, and **six** targets currently link
  `SingleThreadCore` (`:261-262`, `:285-286`, `:309-310`, `:332-333`, `:355-356`, `:402-403`).
  Release uses `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (`:714`); Debug is `dwarf` (`:651`).
- **Gaps:** no `PrivacyInfo.xcprivacy` anywhere, no `ci_scripts/`, no dSYM upload, no crash
  reporting of any kind. The repo has no third-party (remote) package today.

## Desired End State

A crash in the shipped iOS or macOS app produces a Sentry event whose stack is symbolicated and
whose per-crash email alert reaches the author within minutes — with a proven *absence* of
reminder content, and with in-app + App Store disclosures that are true again. Concretely:

1. `sentry-cocoa` (9.26.x line) is a remote SPM package linked **only** to the `SingleThread`
   target; `SingleThreadCore`, watch, widget and the UI-test target do not see it.
2. A pure `SentryConfiguration` value type decides *what* to report; a thin `SentryBootstrap`
   adapter turns it into `SentryOptions` and calls `SentrySDK.start` once, at launch, on the
   main thread, on both platforms. A missing/empty DSN yields `nil` ⇒ SDK never starts.
3. `CrashReportingPreference` (default **on**) backs an opt-out toggle in Settings; turning it
   off calls `SentrySDK.close()`, turning it on re-starts the SDK.
4. `SentryScrubber` allow-list plus `beforeSend`/`beforeBreadcrumb` guarantee a constructed
   event/breadcrumb carrying a reminder title, note, or list name comes out with none of it.
5. `PrivacyInfo.xcprivacy` exists on the app target (own UserDefaults/App-Group + Sentry's
   static-link reason codes), the in-app guide gains a 5th `crashReports` section and drops the
   "only network request" absolute, and the ASC label gains Diagnostics → Crash Data.
6. Xcode Cloud uploads archive dSYMs via `ci_scripts/ci_post_xcodebuild.sh` + `sentry-cli`;
   a Sentry alert rule emails per crash; `docs/CrashReporting.md` documents triage.

**Verification:** unit tests below are green; `./scripts/test.sh` passes once at the end
(one `run-gate` subagent); a deliberately triggered test crash on a Debug simulator build shows
an event in the Sentry dashboard, and a real archive on Xcode Cloud symbolicates.

## Patterns to Follow

- **Injectable-preference value type (the toggle's model):** `OrientationPreference`
  (`SingleThreadCore/Sources/SingleThreadCore/OrientationPreference.swift:1-38`) — a small pure
  struct holding injected `UserDefaults` + key, default resolved with `?? true`, a single shared
  `defaultsKey`. `CrashReportingPreference` mirrors it (`isEnabled` defaults to `true`).
  Because the preference is **not** shared with the watch, `UserDefaults.standard` is correct
  here — this is the documented reason `OrientationPreference` doesn't use the App Group.
- **Localized copy + pinned lookup:** add the new section through the existing
  `localized(_:in:)` helper and `PrivacyGuideContent.sections` (`PrivacySettingsContent.swift:80-93`);
  never `String(localized:…)`, which ignores the interface-language pin.
- **Swift Testing layout:** flat `SingleThreadTests/<Subject>Tests.swift`, `import Testing`,
  `@Test`, `#expect`, single `struct <Name>Tests`, app code via `@testable import SingleThread`
  (`PrivacySettingsContentTests.swift:1-2`). Names must **not** start with `test`/`testing`.
- **Target scoping in pbxproj:** follow the `SingleThreadCore` shape — one project-level
  `packageReferences` entry, one `XCSwiftPackageProductDependency`, and the product listed only
  in `SingleThread`'s (and the test target's) `packageProductDependencies`.
- **New `.swift` files need no pbxproj edit** (synchronized file groups). Adding a *remote
  package reference* does.
- **Settings toggle shape:** `Toggle(isOn:)` + `SettingsCaption` + `.accessibilityIdentifier`
  (`SingleThread/InterfaceSettingsView.swift:95-101`); bind through `SettingsBindings`
  (`SingleThread/SettingsBindings.swift`), not ad-hoc `@AppStorage` in the view.
- **Release dSYMs already configured** — no build-setting change is needed for symbolication.

### Patterns NOT to follow

- **Do not** put the Sentry import anywhere in `SingleThreadCore`: it is linked by the watch and
  widget targets, which must not acquire the dependency.
- **Do not** rely on Sentry's own `PrivacyInfo.xcprivacy` being merged: its manifest is **absent
  from SPM distributions** (sentry-cocoa #3853), so the app must declare Sentry's reason codes.
- **Do not** assume the in-app copy can stay unchanged — `privacyGuideContentHasNoAnalyticsClaim`
  and `privacyGuideContentCoversAllDisclosures` pin the exact text and will fail unless updated
  in the same commit.
- **Do not** use `UserDefaults.standard` for any value that must reach the watch (AGENTS.md),
  and do not use `AppGroup.defaults` for the crash toggle (it is device-local, not synced).

## Design Decisions

1. **Init hook:** `SentryBootstrap.startIfEnabled()` is called from a new, minimal
   `SingleThreadApp.init()`, before `@State viewModel` is constructed — earliest main-thread
   point, identical on iOS and macOS, and ahead of EventKit/`ReminderStore` construction.
2. **Factory boundary:** `SentryConfiguration` is a pure value type of primitives with
   `static func make(...) -> SentryConfiguration?` in the app target; tests assert its fields
   **without** importing Sentry. Only `SentryBootstrap` (and `SentryScrubber`) `import Sentry`.
   `nil` (disabled or empty DSN) ⇒ no `SentrySDK.start` call at all.
3. **Consent:** `CrashReportingPreference` default-on; `SettingsView` gains a "Share crash
   reports" toggle (Settings section with a caption explaining crash-only, no reminder content).
   Off ⇒ `SentrySDK.close()`; on ⇒ `start`.
4. **Capture scope:** automatic crash + app-hang + watchdog-termination tracking only
   (`enableCrashHandler`, `enableAppHangTracking`, `enableWatchdogTerminationTracking`). No
   manual `capture` calls in this ticket — no non-fatal error sites are enumerated by research,
   and every manual call would be a new content-leak surface.
5. **Privacy invariants:** `sendDefaultPii = false`, `tracesSampleRate = 0`, auto-session
   tracking off, screenshots/view-hierarchy off (defaults), `maxBreadcrumbs` small, environment
   derived from build config. **Exact `SentryOptions` property names must be read off the
   resolved 9.26.x package at implementation time — never copied from memory** (task constraint);
   this design names intent, not spellings.
6. **Scrub:** allow-list. `SentryScrubber.scrub(_ event:)` sets `user = nil` and replaces
   `extra`, `request`, `modules`, `tags` with only an allow-listed set, and rewrites every
   breadcrumb through `scrub(_ breadcrumb:)`, which keeps category/level/timestamp and drops
   message/data. Auto-breadcrumb categories that can carry text are not enabled. Unit tests
   construct an event with a reminder title/note/list name in `extra`, `user`, and breadcrumb
   data and assert none survive.
7. **DSN/source of truth:** custom `Info.plist` key populated from a build setting
   (`SENTRY_DSN`), empty by default ⇒ inert local builds and CI; Xcode Cloud supplies the real
   value. The DSN is not secret, but keeping it in build config keeps releases reproducible and
   source clean. Environment: `debug` under `#if DEBUG`, else the ASC-provided value.
8. **Sentry org:** **US data region, free Developer plan** (per-crash email alerts are included).
   ⚠️ Not specified by the user — stated reading, revisitable before implementation.
9. **Privacy manifest:** a hand-authored `PrivacyInfo.xcprivacy` on the app target declares
   Crash Data (`NSPrivacyCollectedDataTypeCrashData`, linked=false, tracking=false,
   purpose=AppFunctionality) and, aggregated for Sentry's static link, UserDefaults reason
   `CA92.1`, App-Group `1C8F.1`, SystemBootTime `35F9.1`, FileTimestamp `C617.1`;
   `NSPrivacyTracking = false`. macOS needs no manifest for enforcement but ships the same file.
10. **Privacy copy:** add a 5th `crashReports` section (crash/diagnostic info sent to Sentry,
    only while the toggle is on, never reminder content, US processing) and reword the
    `background` "only network request" sentence. The `reminders` section's "never sent to the
    author or any third party" stays — it is still true. Closing line stays.
11. **Symbolication:** `ci_scripts/ci_post_clone.sh` installs `sentry-cli`;
    `ci_scripts/ci_post_xcodebuild.sh` no-ops unless `CI_ARCHIVE_PATH` is set, then runs
    `sentry-cli debug-files upload --org … --project … "$CI_ARCHIVE_PATH"`, with
    `SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT` from Xcode Cloud env (never in-repo).
    Both scripts are executable with a shebang and non-zero-exit-safe guards.
12. **Alerting is documentation, not code:** the Sentry alert rule is dashboard setup captured in
    `docs/CrashReporting.md`, verified manually with a test crash. It is not gate-testable.

### Intended test inventory (Swift Testing, `SingleThreadTests/`)

- `SentryConfigurationTests` — PII off, tracing off, sessions off, screenshots off, DSN-empty ⇒
  `nil`, disabled preference ⇒ `nil`, environment mapping.
- `SentryScrubberTests` — reminder title/note/list name in `extra`/`user`/breadcrumb never
  survive; benign allow-listed fields do.
- `CrashReportingPreferenceTests` — absent key ⇒ enabled; set/toggle round-trip; injected
  defaults.
- `PrivacySettingsContentTests` (updated) — 5 sections, crash section names Sentry, all six
  languages resolve, non-English values differ.

## What We're NOT Doing

- No watch or widget integration (follow-up only if capture proves worthwhile).
- No performance tracing, no sessions, no metrics/logs, no screenshots or view-hierarchy
  attachments, no `sendDefaultPii`, no user identity.
- No manual non-fatal `capture(error:)` calls at catch sites (separate ticket).
- No custom breadcrumb instrumentation of app flows.
- No "we noticed a crash last run" user-facing prompt (legacy `onCrashedLastRun`/`lastRunStatus`
  stays unused).
- No EU data region, no paid-plan features, no self-hosted Sentry, no Sentry source-map/ProGuard
  concerns (irrelevant to Apple platforms).
- No new test target; no build-setting floor changes; no `verify_deployment_target()` edits.
- No change to background-image networking or `AppGroup.defaults` payload semantics.

## Open Risks

- **Exact options API.** `sentry-cocoa` 9.26.x property spellings (session-tracking flag, hang/
  watchdog names, `beforeSend` signature) are unverified; verify from the checked-out package
  before writing `SentryBootstrap`. Worst case the factory intent stands and only the adapter
  changes.
- **Privacy-manifest packaging under SPM/static linking.** Whether `PrivacyInfo.xcprivacy`
  written at the app-folder root is picked up by the synchronized file group without a pbxproj
  resource edit — verify with the Privacy Report on an archive.
- **Swift 6 strict concurrency across Sentry callbacks.** `beforeSend`/`beforeBreadcrumb` are
  ObjC callbacks not guaranteed `@MainActor`; the scrubber must be nonisolated and
  `Sendable`-safe. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` will surface any violation.
- **Xcode Cloud script behaviour is invisible to the gate.** `ci_scripts/` only runs on Xcode
  Cloud; a broken script fails a real archive, not CI. Mitigate with `bash -n`, careful `set -e`
  guards, and a manual archive check.
- **Periphery noise from a new SPM dependency** (conventions flag this) — treat SDK-side findings
  as expected; see the `periphery` skill rather than "fixing" them.
- **Local Debug builds use `dwarf`**, so locally captured crashes may be unsymbolicated; that is
  expected, not a bug.
- **Region/plan assumption** (US, free) is unconfirmed by the user.