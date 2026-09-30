# Research Questions

## Context

Focus on the SingleThread iOS/macOS app's launch and lifecycle wiring, its dependency and
build configuration, its privacy-and-data-flow disclosure surface, and its test/CI
conventions. Two questions are external: the current state of the Sentry Go-native
`sentry-cocoa` SDK and Apple's privacy-manifest requirements. Answer factually from the
codebase and from current, source-backed web material (in your training data or via web
search); the goal is a precise map of what exists today and how the relevant pieces
connect, not a proposal.

## Questions

1. How is app startup and initialization wired in the iOS and macOS targets, and which target
   owns each entry point? Trace the `@main` SwiftUI App struct, the iOS `AppDelegate`
   bridging, and any startup/setup code — precisely where in the launch path a
   library-level init would hook in, across iOS and macOS (and note watch/widget entry files
   for contrast).

2. What is the app's privacy and data-flow disclosure surface? Enumerate the exact claims
   and text in `SingleThread/PrivacySettingsContent.swift`, how that content is localized
   and asserted in tests, and the app's actual network/data behaviors (the vardy.cc proxy
   helper, entitlements, App Group defaults) so the disclosures can be compared to reality.

3. How is dependency and build configuration expressed in the Xcode project and SPM?
   Document how `SingleThreadCore` (and any other package) is referenced and linked via
   `packageReferences`/build files in `project.pbxproj`, how a package dependency restricted
   to one target is represented, and the `DEBUG_INFORMATION_FORMAT`/dSYM build settings per
   configuration.

4. What are the repo's test-suite and CI conventions? Describe how `SingleThreadTests`
   organizes Swift Testing suites (import pattern, file layout, concurrency/`@MainActor`
   gating, platform gating), and how GitHub Actions (`ci.yml`) plus the gate script
   (`scripts/test.sh`) run, partition, and enforce warnings-as-errors on those tests.

5. What is the current state of the `sentry-cocoa` SDK (external)? Identify the current
   release, how it integrates via Swift Package Manager, and the API surface of
   `SentrySDK.start` and its options type for configuring crash/error reporting. Note any
   documented Swift 6 / strict-concurrency / `@MainActor` compatibility guidance for that
   version.

6. What are Apple's privacy-manifest and Xcode Cloud symbolication requirements (external)?
   Summarize Apple's guidance on what a `PrivacyInfo.xcprivacy` must declare when an app
   uses a third-party SDK like Sentry (third-party-SDK list, required-reason APIs), and the
   standard workflow for uploading archive dSYMs to Sentry from Xcode Cloud
   `ci_scripts/ci_post_xcodebuild.sh` via `sentry-cli`, including the environment variables.
