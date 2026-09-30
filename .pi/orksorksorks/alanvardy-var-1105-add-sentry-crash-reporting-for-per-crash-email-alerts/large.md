# Task

Integrate Sentry (`sentry-cocoa`) crash/error reporting into SingleThread — the repo's
**first third-party dependency** — so a per-crash email alert with a symbolicated stack
reaches the author within minutes of any iOS/macOS crash (currently there is zero crash
reporting; App Store Connect offers no per-crash notification). Scope: iOS + macOS app
target first (watch/widget follow-up only if capture proves worthwhile), crash/error
reporting only — no performance tracing, no sessions, no PII, no reminder content.

Work spans: dependency wiring (pbxproj `packageReferences` on the `SingleThread` target
only), `SentrySDK.start` init from `SingleThreadApp.swift`/`AppDelegate.swift` driven by a
pure, unit-testable `SentryOptions` factory; unit-tested privacy invariants
(`sendDefaultPii = false`, `tracesSampleRate = 0`, session tracking off, plus a
`beforeBreadcrumb`/`beforeSend` scrub proving no reminder title/note/list name ever reaches
an event); a new `PrivacyInfo.xcprivacy` privacy manifest; updating the in-app
`PrivacySettingsContent.swift` copy and the App Store Connect privacy label (Diagnostics →
Crash Data) so they no longer falsely claim data is "never sent to a third party"; a new
`ci_scripts/ci_post_xcodebuild.sh` (and possibly `ci_post_clone.sh`) uploading archive
dSYMs via `sentry-cli` for symbolication (auth via Xcode Cloud env vars, never in-repo);
Sentry alert-rule setup; Swift Testing unit tests; and a `docs/CrashReporting.md` triage
guide. Gate remains `./scripts/test.sh` with warnings-as-errors, plus `make format`,
`make lint`, `make periphery`.

## Why LARGE

**UNKNOWNS** (new third-party technology: current `sentry-cocoa` release and its Swift
6.0 / `SWIFT_APPROACHABLE_CONCURRENCY` compatibility, the exact `SentryOptions` API for
that version — explicitly "do not copy option names from memory" — and Xcode Cloud
post-action env vars for locating archive dSYMs; plus open questions on watch/widget
scope, free-vs-paid plan, US-vs-EU data region). **NEW_SURFACE** (a brand-new third-party
integration/subsystem — the repo's first dependency). **CONVENTION_RISK** (touches shared
build/CI config — pbxproj packageReferences, Xcode Cloud `ci_scripts`, `.xcprivacy` —
and privacy/packaging-critical changes). **DESIGN_SIGN-OFF** (a product/privacy trade-off:
changing in-app and App Store privacy copy and choosing data region/plan). The repo
AGENTS.md also mandates a dedicated QRSPI research phase for exactly this class of task.