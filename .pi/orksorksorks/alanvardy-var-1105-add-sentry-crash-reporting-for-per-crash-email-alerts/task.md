# Task

Integrate Sentry (`sentry-cocoa`) crash/error reporting into the SingleThread iOS and
macOS app — the repo's first third-party SPM dependency — so a per-crash email alert with a
symbolicated stack reaches the author within minutes of any crash. Crash/error reporting only:
no performance tracing, no sessions, no PII, no reminder content. Scope is the iOS + macOS
app target first (watch/widget follow-up only if capture proves worthwhile).

Work spans: wiring the Sentry remote package into the Xcode project and linking it to the
SingleThread target only; `SentrySDK.start` init from the app/AppDelegate driven by a pure,
unit-testable `SentryOptions` factory; unit-tested privacy invariants (`sendDefaultPii =
false`, `tracesSampleRate = 0`, session tracking off, a beforeBreadcrumb/beforeSend scrub
proving no reminder title/note/list name ever reaches an event); a PrivacyInfo.xcprivacy
privacy manifest; updating in-app privacy copy and the App Store Connect privacy label
(Diagnostics -> Crash Data) so they no longer falsely claim data is "never sent to a third
party"; `ci_scripts/ci_post_xcodebuild.sh` uploading archive dSYMs via sentry-cli for
symbolication; Sentry alert-rule setup; Swift Testing unit tests; and a docs/CrashReporting.md
triage guide. Gate remains ./scripts/test.sh, plus make format, make lint, make periphery.
