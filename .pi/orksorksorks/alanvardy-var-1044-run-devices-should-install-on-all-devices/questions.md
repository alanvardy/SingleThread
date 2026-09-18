# Research Questions

## Context

Focus areas: `scripts/run-devices.sh` (the multi-platform install/launch
script using xcrun devicectl) and its sibling scripts in `scripts/`; the
SingleThreadWatch target and its shared scheme inside SingleThread.xcodeproj;
the Makefile watch targets and the `.github/workflows/ci.yml` watch jobs; the
app-group/companion identity shared between the iOS app and the watch app;
and the xcrun devicectl command surface on this machine (real-device
inventory and help text). On-disk test/build plumbing (scripts/test.sh, CI)
is in scope where it documents how watch builds are driven today.

## Questions

1. How does `scripts/run-devices.sh` flow — from env configuration, through
   iOS device discovery via `xcrun devicectl list devices -j` (the exact
   JSON fields filtered on), the build leg, the per-device install/launch
   loop, the macOS host leg, and its error handling and cleanup?

2. How is the SingleThreadWatch target defined — build settings
   (SDKROOT, SUPPORTED_PLATFORMS, TARGETED_DEVICE_FAMILY,
   WATCHOS_DEPLOYMENT_TARGET, PRODUCT_BUNDLE_IDENTIFIER,
   WKCompanionAppBundleIdentifier, CODE_SIGN_STYLE, SKIP_INSTALL,
   PRODUCT_NAME), product type, and its shared scheme's build/test/launch
   actions?

3. Where are the identifiers that must agree between the iOS app and the
   watch app defined — the App Group suite name, companion app bundle id,
   app-group entitlements, Info.plist keys — and how do the phone and watch
   reference each other (AppGroup.swift, entitlements files,
   WatchConnectivity usage)?

4. What does `xcrun devicectl` on this machine report right now: run
   `xcrun devicectl list devices -j` once and describe each attached/paired
   device's fields (platform, deviceType, identifier,
   connectionProperties/transportType, developerModeStatus, reachability);
   and from devicectl help pages describe the `device install app` and
   `device process launch` subcommands and their platform-relevant options.
   If no watchOS device is present, say so explicitly and note which fields
   would need to be observed with watch hardware attached.

5. How do Makefile and `.github/workflows/ci.yml` build and test the watch
   today — the watch-build/watch-test/watch-ui-test targets and the CI
   lint watch-build and watch-ui-tests jobs: exact destinations
   (generic/platform=...), -derivedDataPath usage, product paths
   (Debug-watchsimulator etc.), simulator pinning, and any signing flags?

## Notes for researchers

- Answer the one question assigned to you. Describe what exists. Do not
  suggest improvements or propose solutions.
- Condensed report, ≤100 lines, with file:line references.
- Work inside the target repo and the exact areas your question names; no
  web searches, no global tours, no toolchain verification. Answer in one
  pass and return your condensed report after no more than ~12 tool calls;
  if something is not findable in that budget, say so rather than looping.
