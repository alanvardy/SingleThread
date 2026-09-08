# Research Questions

## Context

This repo is a single Xcode target compiled for iOS and macOS
(`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`), with a shared
SwiftUI `ContentView` and a cross-platform background-photo pipeline
(fetch → persist → observable store → render). The render layer is currently
conditionally compiled for iOS only. Focus on how the two platforms diverge in
rendering, windowing, settings, and test coverage for this layer.

## Questions

1. Image rendering and conditional compilation: How does this codebase bridge
   UIKit (`UIImage`) and AppKit (`NSImage`) for views and images, and what
   `#if os(...)` / helper patterns exist (e.g. `Color+CrossPlatform`,
   `BackgroundImageStore.isDecodableImage`) that a cross-platform photo view
   could follow? Where do platform-gated view definitions currently live, and
   how are they referenced from shared views?

2. macOS window and content surface: How is the macOS `WindowGroup` / window
   configured in `SingleThreadApp.swift` and the app delegate, what paint does
   the window draw behind content (`Color.systemBackground`,
   `NSColor.windowBackgroundColor`), and how does the transparent `List` /
   scroll content show through on macOS — is there any windowing or layer
   surface that would need to change for a photo layer behind the list to be
   visible (e.g. window background styles, `ignoresSafeArea()` behavior)?

3. Settings surface on macOS: The Background settings row, enabled/fade/pin
   toggles, and refresh button currently compile and display on macOS while
   nothing renders. How are per-platform settings rows described in
   `SettingsView` / `SettingsBindings` / `BackgroundSettingsView`, and are
   there existing patterns for hiding or adapting a settings row per platform?

4. Test coverage and verification seams for the background feature: How are
   the background store, fade, card plate, and settings tested (unit and UI),
   which of those tests are platform-gated (`#if os(iOS)` etc.), and what
   launch-argument seams (`--seed`, `--ui-testing`) exist that could drive
   macOS verification? Is there any macOS UI-test harness today?

5. Prior analysis of the macOS platform gap: The QRSPI artifacts for earlier
   tickets (e.g. `alanvardy-var-721-testflight-macos`,
   `alanvardy-var-743-pin-wallpaper`, `alanvardy-var-722-opacity-issue-ipados`)
   examined or referenced the macOS photo gap. What did those findings and
   designs conclude about the background on macOS, including any suggested
   gating or rendering approaches that were considered or rejected?