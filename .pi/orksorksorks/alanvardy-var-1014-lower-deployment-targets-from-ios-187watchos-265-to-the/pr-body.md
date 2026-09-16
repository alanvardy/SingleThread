## What changed

This PR **lands no floor values** — it converts the floors already committed by
`53124c3e` (iOS **17.0** / watchOS **11.0** / macOS **26.5**) into *evidence*, and
hardens the deployment-target gate so per-platform literal drift can no longer
slip through.

- **Proof**: red-probe ladders below the floor (iOS 16.0, watchOS 9.0) that fail
  with availability errors naming the exact pinning APIs; a watchOS 10.0 build
  recorded as green-but-rejected; runtime smoke on degraded (non-default-dot)
  runtimes; an SPM consumer-floor probe that resolves a design open risk.
- **Gate hardening**: `scripts/test.sh`'s `verify_deployment_target()` now
  counts literals **per platform** (pbxproj 8/6/6 + Package.swift 1/1/1) instead
  of one collapsed total — a watchOS literal swapped for a macOS one used to
  still total 20 and pass; today it fails (probes 3a–3d red/green in the logs).
- **Only production-file diff across all phases**: `scripts/test.sh`.

## Verified floor tuple

> **iOS 17.0 / watchOS 11.0 / macOS 26.5** — gate output on the clean tree:
> `✓ All deployment-target + package-floor literals match (iOS 17.0 × 8, watchOS 11.0 × 6, macOS 26.5 × 6; package .iOS 1, .watchOS 1, .macOS 1)`

## Probe table (the evidence)

| Floor | Verdict | Exact API named by the compiler |
|---|---|---|
| iOS 16.0 | **red** | `'Observable()' is only available in iOS 17.0 or newer` + `protocol 'EventKitStoring' requires 'requestFullAccessToReminders()' to be available in iOS 16.0 and newer` |
| SPM consumer < package floor | **red** | `error: compiling for iOS 16.0, but module 'SingleThreadCore' has a minimum deployment target of iOS 17.0` — the SPM consumer floor is enforced **at iOS 17.0** (design open risk resolved) |
| iOS 17.0 | **green** | builds, installs, launches, EventKit prompt + grant path fetch on the probe runtime |
| watchOS 9.0 | **red** | `'Observable()' is only available in watchOS 10.0 or newer` + `'fullAccess' is only available in watchOS 10.0 or newer` (`EKAuthorizationStatus.fullAccess`) |
| watchOS 10.0 | **green-but-rejected** | compiles clean at 10.0, but rejected as the ship floor: buys only Apple Watch Series 4/5/SE (1st gen) reach — not a product goal; landing stays 11.0 (Series 6+ reach unchanged) |
| watchOS 11.0 | **green** | watch build + unit/UI suites pass; smoke launch renders without crashing |

Full compiler diagnostics and logs: `.pi/orksorksorks/alanvardy-var-1014-lower-deployment-targets-from-ios-187watchos-265-to-the/` (`probe-ios16.0-build.log`, `probe-ios16.0-package-floor.log`, `probe-watchos9.0-build.log`, `probe-watchos10.0-build.log`, …); summary in `verification.md`.

## Gate hardening

- `verify_deployment_target()` uses per-platform counters (iOS/watchOS/macOS for
  the pbxproj; `.iOS`/`.watchOS`/`.macOS` for the package), with count guards
  `8/6/6` and `1/1/1` and a per-platform summary line.
- Probes (each red run never reached `==> Unit tests`; each mutation restored
  with `git checkout --`, tree clean between):
  - 3a `probe-gate-watchos-swap.log` — watchOS literal swapped for a macOS one
    (total still 20): now fails `✗ WATCHOS literal count 5 (expected 6)`. The
    old total-only guard passed this class of drift.
  - 3b `probe-gate-literal-removed.log` — one watchOS literal removed: fails
    `✗ WATCHOS literal count 5 (expected 6)`.
  - 3c `probe-gate-package-removed.log` — package `.watchOS` removed: fails
    `✗ package .watchOS count 0 (expected 1)`.
  - 3d `probe-gate-clean.log` — unchanged tree: gate green with the exact
    per-platform tuple.

## macOS-listing correction

`53124c3e`'s comment claimed the store's macOS requirement derives from
`IPHONEOS_DEPLOYMENT_TARGET`, not `MACOSX_DEPLOYMENT_TARGET` — **verified
false**. The app target is a native macOS build (`SUPPORTED_PLATFORMS` includes
`macosx`, macOS-only entitlements, no Catalyst), so the Mac App Store listing
derives from **`MACOSX_DEPLOYMENT_TARGET`** (macOS 26.5, unchanged). The
`scripts/test.sh` comment now states this correctly.

## Named verification gaps (not hidden)

- The **Xcode 27.0 (27A266a) download catalog serves no pre-26 iOS/watchOS
  runtime** — every 17.x–25.x build is refused (`not available for download`),
  no importable `.dmg`, no older Xcode. A genuine iOS 17.x / watchOS 11.x
  **runtime** run is impossible in this environment.
- The runtime leg therefore degraded to the strongest available older-than-default
  dot release: **iOS 26.0 (23A343)** and **watchOS 26.0 (23R353)**. The
  compile-time reds are unaffected (availability comes from SDK + deployment
  target); a ≤ 25.x runtime run remains **unverified locally**.
- `lib_TestingInterop.dylib`: **NOT needed on watchOS 26.0** — the
  `scripts/test.sh` bundling workaround addresses a **26.5-specific** simruntime
  defect that does not reproduce on 26.0 (watch UI runner passed unmodified).
- The EventKit **deny** path of the iOS smoke was not exercised (grant path
  confirmed); the full `./scripts/test.sh` gate runs once after this commit
  (async gate subagent), and CI on this PR is authoritative.

## Test story

**No new unit test** — deliberately. The only production change is
`verify_deployment_target()` in `scripts/test.sh`; its regression surface is the
drift probes themselves, which are red/green-proven (probes 3a–3d above) rather
than asserted by a unit test. The repo policy's unit-test requirement is
satisfied by the gate's per-platform assertions plus the captured probe
evidence in `verification.md` and the committed probe logs.