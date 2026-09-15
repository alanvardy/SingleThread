# Design Discussion

> **Post-rebase status (2026-09-15): the floors below are already landed.**
> `origin/main` `53124c3e` (ticket VAR-1015) shipped the target end state of
> this design: pbxproj 8× iOS 17.0 / 6× watchOS 11.0 / 6× macOS 26.5,
> `Package.swift` 17.0 / 11.0 / 26.5, a three-value gate
> (`DEPLOYMENT_TARGET_IOS|WATCHOS|MACOSX`), and the updated
> `AppDelegateTests.swift:13` note. Therefore: the **Current State** section
> below is historical (it describes the pre-landing tree), decision 4's
> gate split is *done*, and the remaining work is **proof + runtime
> verification**, re-scoped in `structure.md`. Two corrections/notes:
> - Decision 3's macOS reasoning holds and is now *verified*: the app target is
>   a native macOS build (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator
>   macosx"`, `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, no Catalyst), so the Mac
>   listing derives from `MACOSX_DEPLOYMENT_TARGET` — `53124c3e`'s commit
>   message claiming it derives from `IPHONEOS_DEPLOYMENT_TARGET` is wrong.
> - The landed gate kept the literal-count guard collapsed (`other_target`
>   covers watchOS+macOS, total 20), so per-platform count drift is undetected;
>   structure Phase 3 restores the design's per-platform counts (8/6/6).

## Current State

The app declares its minimum OS floors in exactly two places, and a test
script enforces that they agree:

- **`SingleThreadCore/Package.swift:6-10`** — `platforms: [ .iOS("18.7"),
  .watchOS("26.5"), .macOS("26.5") ]`. One array, three independent hardcoded
  strings, no shared constant. All seven Xcode native targets consume this
  package (`project.pbxproj:1229-1240`).
- **`SingleThread.xcodeproj/project.pbxproj`** — 20 `*_DEPLOYMENT_TARGET`
  literals (grep-verified): 8× `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, 6×
  `WATCHOS_DEPLOYMENT_TARGET = 26.5`, 6× `MACOSX_DEPLOYMENT_TARGET = 26.5`,
  as Debug/Release pairs per target (line map in `research.md` Q1:
  765/815, 843/872, 900/924, 1009/1040 iOS; 965/993, 1077/1099, 1123/1147
  watchOS and macOS).
- **`scripts/test.sh:130-192` `verify_deployment_target()`**, invoked at
  `:193` before *any* build in every mode, asserts all 20 pbxproj literals
  plus all 3 Package.swift literals match two values: `DEPLOYMENT_TARGET_IOS`
  (default `18.7`) and **`DEPLOYMENT_TARGET_OTHER` (default `26.5`, covering
  watchOS *and* macOS together)** — env-overridable (`:138-139`). Literal-count
  drift is also asserted: `EXPECTED_TARGET_LITERALS=20`,
  `EXPECTED_PACKAGE_LITERALS=3` (`:140-141`).

The **hard floor** is set by EventKit, not by a product choice: the installed
iPhoneOS SDK annotates `EKEventStore.h:88`
(`requestFullAccessToRemindersWithCompletion:`) as
`API_AVAILABLE(ios(17.0), macos(14.0), watchos(10.0))`, and
`EKAuthorizationStatus.fullAccess` / `requestFullAccessToReminders()` are the
Swift-named overlays of that API. The code uses them unconditionally:
`ReminderStore.swift:451-458`, `:535-547`; protocol at
`EventKitStoring.swift:10,14`; test seam `InMemoryEventStore.swift:37-47`.
`@Observable` (23 mentions across 21 files, `research.md` Q3) is a Swift 6.0
stdlib macro whose per-OS floor is **not annotated locally**.

`CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE`
(`project.pbxproj:647/710`) plus project-wide
`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` means an unguarded call to an API newer
than the floor is a **build error** — so the floor is compiler-enforced, and
lowering it is safe-by-construction for availability, but also means the
compiler will tell us exactly which API pins the floor.

The target is a **unified multiplatform app**: `SDKROOT = auto`,
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`
(`project.pbxproj:773/823`), macOS-only entitlements at `:766/816`. The
macOS floor is therefore a real product floor, not just a macOS test-runner
artifact. There is **no runtime OS branching anywhere** — all platform
behaviour is compile-time (`#if os(...)` at 24 sites, `canImport` at 6,
`research.md` Q5); nothing references Liquid Glass or any newer-OS UI API.
There is **no market-facing OS text** in the repo (`research.md` Q6): no
README/CHANGELOG/release notes/store metadata; only `docs/`,
`exportOptions.plist` and internal `.pi/` artifacts.

## Desired End State

iOS floor **17.0**, watchOS floor **11.0**, macOS floor **unchanged at 26.5** —
enforced consistently across `Package.swift`, all 20 `project.pbxproj`
literals, and a gate that can express three independent per-platform values.

Correctness criteria, in order:

1. `scripts/test.sh`'s `verify_deployment_target()` passes with
   `DEPLOYMENT_TARGET_IOS=17.0`, `DEPLOYMENT_TARGET_WATCHOS=11.0`,
   `DEPLOYMENT_TARGET_MACOS=26.5`, asserting the three floors separately
   against per-platform literal counts (8 iOS / 6 watchOS / 6 macOS = 20; 3
   package literals).
2. A **red probe** proves the floor is real: with floors temporarily set to
   iOS 16.0 / watchOS 9.0 the build fails with availability errors naming
   `@Observable`/EventKit full-access; a watchOS 10.0 probe is recorded for
   completeness.
3. With floors at 17.0 / 11.0, `make build`, the targeted unit suites, and the
   UI suites build and pass **on an actual iOS 17.x simulator and an actual
   watchOS 11.x simulator** (both runtimes downloaded locally), not just on 26.
4. The full CI-identical `./scripts/test.sh` gate is green via the `run-gate`
   skill after phases commit.
5. The App Store iOS listing derives ≥ iOS 17.0 and the watch listing ≥
   watchOS 11.0 (no in-repo metadata to edit; the pbxproj value *is* the
   listing input).

## Patterns to Follow

- **Single enforcement point, extended not bypassed**: `verify_deployment_target()`
  (`scripts/test.sh:130-192`) is the one place floors are checked; it must
  learn three values rather than being skipped or overridden per-invocation.
  Its literal-count assertions (`:140-141`) are the anti-drift guard — keep
  them, split per platform.
- **pbxproj literals are Debug/Release pairs**: every floor edit lands twice
  per target (`research.md` Q1 line map). Never edit one side only.
- **Package mirrors pbxproj exactly**: today package minimums and every
  consumer target floor are identical (`research.md` Q2), and SPM requires a
  consumer's floor to be ≥ its dependency's declared minimum. Keeping the
  three values identical in both files is the only in-repo-verifiable
  arrangement. **Do not** declare the package lower than its consumers.
- **Availability errors as the probe instrument**: rely on
  `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` + warnings-as-errors to
  surface the pinning API; do not add exploratory `#available` guards to make
  a probe pass.
- **Compile-time platform selection stays compile-time**: keep `#if os(...)`
  (`ReminderStore.swift:138-454`, `ContentView+Settings.swift:22-61`, etc.)
  and `#if canImport(...)` (`CodeSpanFormatter.swift:3-146`) exactly as they
  are. A static floor needs no runtime branching.
- **Capability fallbacks are the established optional-feature idiom**:
  `AppGroup.swift:14-18` (`UserDefaults(suiteName:) ?? .standard`),
  `PendingCompletionStore.swift:8`,
  `ShowEnableActionButtonsState.swift:6` — reuse these for feature detection,
  never OS-version comparison.
- **Verification staging**: phases build and run targeted `-only-testing:`
  suites only; the full `./scripts/test.sh` runs **once** after phases commit
  via the `run-gate` skill (async gate subagent, managed worktree,
  multi-hour timeout) — never an ad-hoc `nohup`.
- **Simulator pinning**: explicit `SIM=` > worktree `.simulator_id` >
  `name=iPhone 17` (`Makefile:1-11`, `scripts/test.sh:36-70`). Old-runtime
  verification uses an explicit `SIM=` with a device type compatible with that
  runtime; do not disturb `.simulator_id`.

Patterns found that must **not** be followed here:

- The Tests-target warnings exception at `project.pbxproj:853/882`
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`, justified by a StoreKit symbol
  "iOS-18-deprecated"). Do not extend this exception to paper over a new
  availability warning from the lower floor; if the probe surfaces it,
  re-evaluate the exception explicitly.
- Stale `DerivedData/` reuse: `make periphery` reads a stale build index after
  a settings/branch change (`AGENTS.md:28`); a pbxproj edit changes the CI
  DerivedData cache key (`research.md` Q6) and must be paired with a clean
  index locally.
- No new `#available` runtime branches (none exist today) and no reliance on
  `docs/SimulatorManualVerification.md` text as a floor source.

## Design Decisions

1. **iOS floor = 17.0**: the SDK-annotated EventKit floor
   (`EKEventStore.h:88`) plus `@Observable`; maximal reach within the proven
   floor; 18.0 would drop iOS 17 users for no technical reason.
2. **watchOS floor = 11.0**: the ticket's sweet spot; watchOS 10.0 is
   technically legal (EventKit `watchos(10.0)`) but is the older
   Liquid-Glass boundary and only buys Series 4/5/SE 1 reach, which is not a
   stated product goal. Recorded as a deliberate, revisitable choice.
3. **macOS floor stays 26.5**: out of ticket scope, and a 14.0–15.0 macOS
   floor cannot be runtime-verified here (CI is `macos-26` only); shipping an
   unverified macOS floor is a bigger risk than leaving the Mac listing
   unchanged. Accepted consequence: the **Mac** App Store listing still
   requires macOS 26.5.
4. **Gate becomes three-value**: `DEPLOYMENT_TARGET_IOS` /
   `DEPLOYMENT_TARGET_WATCHOS` / `DEPLOYMENT_TARGET_MACOS`, with per-platform
   literal counts (8/6/6) and per-platform Package.swift assertions (3). The
   current `DEPLOYMENT_TARGET_OTHER` coupling (watchOS ≡ macOS) is the blocker
   for a watchOS-only drop and must be split, not worked around.
5. **Package.swift mirrors the pbxproj per platform**: `.iOS("17.0")`,
   `.watchOS("11.0")`, `.macOS("26.5")` — keeping consumer floor == package
   floor preserves today's invariant and avoids unverifiable SPM divergence
   behaviour.
6. **Floor proven by a red-probe ladder, not by annotation alone**: probe
   iOS 16.0 / watchOS 9.0 (expect failures naming `@Observable` and EventKit
   full-access), then iOS 17.0 / watchOS 10.0, then the final 17.0 / 11.0.
   Capture each probe's raw compiler output as an artifact. This converts the
   unannotated `@Observable` floor from an assumption into evidence.
7. **Runtime verification via downloaded older sim runtimes**: download the
   lowest available iOS 17.x and watchOS 11.x runtimes, boot compatible
   (pre-iPhone-17) device types, install and smoke-run the app, and run the
   targeted suites with an explicit `SIM=`. This is the only way to satisfy
   "runtime behaviour on pre-Liquid-Glass OS" locally.
8. **No runtime fallbacks introduced**: the floor is static and
   compiler-enforced, so zero `@available`/`#available` code is added; the
   diff is build config only (plus the gate).
9. **No new tests, no new test targets**: this is a configuration change whose
   regression surface is the gate itself; the gate's red/green probes are the
   test. Repository policy's "every change ships with a unit test" is
   satisfied by the `verify_deployment_target()` assertions (which fail on any
   drift) plus the probe evidence — stated explicitly in the PR rather than
   adding a synthetic test.
10. **Release notes / store metadata: nothing to update in-repo**, explicitly
    verified by `research.md` Q6.

## What We're NOT Doing

- Not lowering the **macOS** floor (stays 26.5); the Mac App Store listing
  requirement is unchanged and out of scope.
- Not targeting iOS 16 or watchOS 9/10 — 16.0/9.0 exist only as probe
  boundaries; 10.0 is a recorded-but-rejected option.
- Not adding runtime `#available`/`@available` branches or OS-version
  comparisons — compile-time `#if os()`/`canImport` remains the only idiom.
- Not touching Liquid Glass, `NSColor`/`UIColor` effect code, animation
  envelopes, or the `ControlPlateModifier` shadow beyond what the compiler
  forces.
- Not changing CI runners/Xcode (`macos-26`, Xcode 26.6), the CI simulator
  matrix, or the CI DerivedData caching scheme.
- Not changing `.simulator_id`, the default `name=iPhone 17` destination, the
  one-xcodebuild-at-a-time rule, or the watch-UI `lib_TestingInterop.dylib`
  workaround.
- Not extending the Tests-target `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`
  exception.
- No new test targets and no additions to CI matrix entries.
- Not adding a `docs/` OS-requirement page.

## Open Risks

- **`@Observable`'s per-OS floor is unproven** until the red probe; if iOS
  16.0 unexpectedly compiles, the true floor may be lower than 17.0 (not a
  problem) — but if it errors only at 16.0 with an unrelated API, that API
  becomes the real pin and must be recorded.
- **`EKAuthorizationStatus.fullAccess` / `requestFullAccessToReminders()`
  availability is inferred from the C-level completion method**
  (`EKEventStore.h:88`); the Swift overlay's own annotation is not locally
  inspectable. The probe is the arbiter.
- **SPM behaviour when a consumer floor is lower than a dependency's** is
  unverifiable in-repo; mitigated by keeping all three values equal, but the
  residual risk is that a lower package floor is simply ignored by the
  toolchain.
- **Older sim runtimes may not be downloadable/usable** for iOS 17.0 / watchOS
  11.0 exactly: only the lowest *available* 17.x/11.x build can be used, and
  `iPhone 17`/newest watch device types cannot boot them — a pre-17 device
  type and explicit `SIM=` are required. If no 17.x/11.x runtime is
  installable, decision 7 degrades to the strongest available older runtime
  and the gap must be *named* in the PR, not hidden.
- **Watch pairing on an older watchOS runtime** is unproven; the
  `lib_TestingInterop.dylib` workaround (`test.sh:271-288`,
  `simulator-pairing/SKILL.md:24`) is 26.5-specific and may not apply or be
  needed.
- **Gate edits must stay in lockstep**: the three-value split and its literal
  counts (8/6/6, 3) must be updated in the same commit as the pbxproj/package
  values, or every build fails at `verify_deployment_target()`.
- **`SingleThreadTests/AppDelegateTests.swift:13`** notes a newer-deployment-
  target-only API; lowering the iOS floor may turn that note stale or surface
  a new warning-as-error in the test target.
- **Two consecutive UI-stage contention failures** are the documented stop
  signal (`AGENTS.md:71-73`); old-runtime UI runs count toward that budget and
  CI remains authoritative.