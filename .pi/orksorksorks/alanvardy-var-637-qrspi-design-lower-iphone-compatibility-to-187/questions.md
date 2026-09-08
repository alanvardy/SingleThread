# Research Questions

## Context

The iOS Xcode project (and its local Swift Package) declare minimum supported
OS versions for the iOS app, watch app, widget, tests, and a local Swift
package. The source also uses a range of SwiftUI / Observation / concurrency
APIs. Focus on how these minimums are expressed and enforced, which APIs carry
an inherent OS floor, and how the build/test toolchain reacts to these values.

## Questions

1. Where and how is the minimum OS deployment target expressed for each
   target in the Xcode project (`SingleThread.xcodeproj/project.pbxproj`) and
   in the local Swift Package (`SingleThreadCore/Package.swift`)? How do these
   declarations relate to one another (app, tests, UI tests, watch, widget,
   core package), and are they kept in lockstep?

2. Which SwiftUI / Observation / AppKit / AppIntents APIs and frameworks used
   anywhere in the source carry an inherent minimum iOS deployment floor, and
   is there any OS-version gating in the codebase (e.g. `@available` /
   `#available` annotations, conditional `systemVersion` checks, feature
   availability flags, `.requires`)? Where do these appear, and what iOS
   version does each require?

3. How does the local Swift Package (`SingleThreadCore`) declare its minimum
   platform versions in `Package.swift`, and what does the Xcode/SPM toolchain
   do at build time when a package platform minimum and a target deployment
   target disagree? Is there an explicit consistency mechanism, or is a
   mismatch a silent/erroring condition?

4. How are the watchOS app and the widget extension configured relative to the
   iOS app's deployment targets? Which deployment targets and platform
   constraints do they set, how do they inherit or diverge from the iOS app,
   and which ones omit a deployment target despite declaring that platform?

5. Which parts of the build, test, and CI toolchain (xcodebuild scheme,
   Makefile, `scripts/test.sh`, `.github/workflows/ci.yml`, `.mise.toml`) pin,
   verify, or rely on deployment-target or OS-version values — and where would
   an invalid, missing, or inconsistent deployment target become visible
   (build failure, warning, or not caught at all)?