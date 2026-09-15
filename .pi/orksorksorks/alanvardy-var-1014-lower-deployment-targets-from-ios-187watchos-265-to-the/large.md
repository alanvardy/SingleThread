# Task

Lower the deployment targets from iOS 18.7 / watchOS 26.5 to a proven lower floor so the App Store listing no longer requires the newest point release. The hard floor is iOS 17.0 / watchOS 10.0 (pinned by `@Observable` — 23 uses across the four source trees — and `EKAuthorizationStatus.fullAccess` / `requestFullAccessToReminders` in the EventKit store code); the ticket recommends iOS 17.0 / watchOS 11.0 as the sweet spot, with watchOS 10.0 only if Series 4/5/SE 1 reach is wanted.

The work spans: `SingleThreadCore/Package.swift` platforms plus 17 `IPHONEOS_DEPLOYMENT_TARGET` / `WATCHOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` literals in `project.pbxproj` (and any release notes / store metadata stating the OS requirement); re-probing the iOS 16.0 and watchOS 9.0 boundaries against the actual diff; verifying runtime behaviour (pre-Liquid-Glass UI on iOS ≤ 18 / watchOS ≤ 25) since no iOS 17/18 runtime is installed locally; and a full `./scripts/test.sh` gate (deployment-target change invalidates DerivedData and needs a clean Periphery index).

## Why LARGE

- **CONVENTION_RISK** — the 17 shared build-config literals plus SPM package platforms are shared build/CI config with a backward-compatibility constraint against an OS-feature floor (`@Observable`/EventKit full-access APIs), touching all four source trees (iOS, watchOS, macOS, Core) plus store metadata.
- **DESIGN_SIGN-OFF** — the watchOS floor is a product trade-off (11.0 sweet spot vs 10.0 to gain Series 4/5/SE 1, which pair only with iOS 17) and the iOS floor changes the store's derived macOS requirement; a human must choose the floor.
- Broad reach (multiple modules, all platform targets, runtime verification on hardware/older sim runtime) — LARGE's pipeline (research → design → plan → implement → review) fits.