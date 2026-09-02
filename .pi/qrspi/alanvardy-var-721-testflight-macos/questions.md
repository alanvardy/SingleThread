# Research Questions

## Context

This is a multi-target Xcode project (iOS app, watchOS app, widget, and unit/UI
test bundles) built around a local SwiftPM package (`SingleThreadCore`). Many
layers carry platform-specific branches: the app target's build configuration,
`#if os(...)`-gated framework usage in the sources, the app lifecycle and
composition root, the persistence/entitlement setup, the build-and-test
automation, and the in-app-purchase code. Explore how each of these areas is
structured today, with particular attention to the macOS-capable build path
that is already configured in the project (the app target's supported
platforms, a macOS entitlements file, and macOS build/test steps in the local
and CI tooling).

## Questions

1. **Target & build configuration** — How is the app target (and its test,
   watch, and widget companions) configured for multiple platforms in
   `SingleThread.xcodeproj/project.pbxproj`? Enumerate the platform
   declarations (`SUPPORTED_PLATFORMS`, `SDKROOT`, `TARGETED_DEVICE_FAMILY`,
   deployment targets) and the per-SDK build settings — `CODE_SIGN_ENTITLEMENTS[sdk=…]`,
   `CODE_SIGN_IDENTITY[sdk=…]`, Info.plist generation keys, `LD_RUNPATH` —
   for both Debug and Release. How are the watch-app and widget embed
   dependencies filtered per platform (`platformFilter`)? What product does a
   `-destination "platform=macOS"` build of the `SingleThread` scheme produce
   (native Mac app vs Catalyst)?

2. **Platform-gated code** — Which frameworks and APIs used across the app
   sources, the `SingleThreadCore` package, the widget, and the test bundles
   are platform-specific or behave differently on macOS? For each of
   WatchConnectivity, WidgetKit, Speech + AVAudioEngine (dictation),
   UserNotifications, EventKit, and SwiftUI/UIKit/AppKit: where is it imported
   and how is its use guarded by `#if os(...)` (or `@available`)? List any uses
   that are NOT platform-gated.

3. **Runtime lifecycle & composition on macOS** — How do the app's entry
   points and composition root behave per platform: `SingleThreadApp` (Scene
   and delegate adaptors), `AppDelegate` / `MacAppDelegate` (appearance
   bridging), `AppViewModel` (store construction, `--ui-testing` / `--seed`
   launch-argument seams, WatchConnectivity wiring), and `ContentView`'s
   platform branches? Trace what the macOS path looks like end-to-end from
   launch to first rendered view, including how the EventKit-backed
   `ReminderStore` is created and authorized on macOS.

4. **Persistence & entitlements** — What persisted stores exist (App Group
   `UserDefaults` suite, skipped-reminder store, preference stores such as
   sort/show-date/appearance) and which are shared or gated per platform?
   Compare the two entitlement files — iOS `AppGroup.entitlements` vs macOS
   `SingleThread.entitlements`: which capabilities differ between them, and
   how is the shared app group deployed on each platform?

5. **Build/test automation coverage** — What do the local (`Makefile`
   `mac-build`/`mac-test`, the macOS step in `scripts/test.sh`,
   `scripts/simverify.sh`, `scripts/run-devices.sh`) and CI
   (`.github/workflows/ci.yml` `mac-tests` job) macOS pipelines actually run
   today — build vs unit test vs UI test, signing modes
   (`CODE_SIGNING_ALLOWED=NO`), deployment-target validation — and what
   macOS-relevant verification is exercised nowhere?

6. **Purchases & distribution configuration** — How are in-app purchases
   configured in this repo (Products.storekit, `EntitlementStore.unlockProductID`,
   StoreKitTest usage in tests, any IAP entitlements or Info.plist keys), and
   what exists today for archiving/distributing any platform (release scheme
   configuration, archive/export or upload tooling, app-record or signing
   references in the repo, docs/, or `linear-project.md`)?