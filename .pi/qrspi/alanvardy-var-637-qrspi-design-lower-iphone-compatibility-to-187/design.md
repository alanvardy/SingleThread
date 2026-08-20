# Design Discussion

## Current State

- Every deployment target in `SingleThread.xcodeproj/project.pbxproj` is the hardcoded literal
  `26.5` across all 16 occurrences:
  - iOS app `SingleThread`: `IPHONEOS_DEPLOYMENT_TARGET` (`:617` Debug, `:667` Release) and
    `MACOSX_DEPLOYMENT_TARGET` (`:620`, `:670`).
  - `SingleThreadTests`: `IPHONEOS_DEPLOYMENT_TARGET` (`:695`, `:720`), `MACOSX_DEPLOYMENT_TARGET` (`:696`, `:721`).
  - `SingleThreadUITests`: `IPHONEOS_DEPLOYMENT_TARGET` (`:744`, `:768`), `MACOSX_DEPLOYMENT_TARGET` (`:745`, `:769`).
  - `SingleThreadWatch`: `WATCHOS_DEPLOYMENT_TARGET` (`:809` Debug, `:837` Release).
  - `SingleThreadWidget`: `IPHONEOS_DEPLOYMENT_TARGET` (`:853`, `:884`). It declares `macosx` in
    `SUPPORTED_PLATFORMS` (`:863`, `:894`) but sets **no** `MACOSX_DEPLOYMENT_TARGET` — a latent gap
    that never surfaces because the widget is only ever built for iOS.
- `SingleThreadCore/Package.swift` declares its floor as three separate string literals in one
  `platforms:` array: `.iOS("26.5")` (`:7`), `.watchOS("26.5")` (`:8`), `.macOS("26.5")` (`:9`).
- These are kept in lockstep **by value only** — there is no single source of truth and **no
  consistency mechanism** anyone. The value is duplicated manually across the 16 pbxproj literals
  and 3 package literals, and nothing cross-checks package minimums against deployment targets.
- **There is zero OS-version gating in the source.** No `@available`/`#available`, no `systemVersion`
  checks, no `.requires`, no runtime feature-availability gating. The only conditional compilation
  is platform gating (`#if os(iOS)` / `#if os(macOS)` / `#if os(watchOS)`); the only runtime check is
  `recognizer.isAvailable` for on-device speech (`SingleThread/ReminderDictation.swift:54`), a
  capability flag, not an OS-version gate.
- **Every API family used sits below 18.7**, so none forces a feature cut or raises the new minimum:
  - Observation `@Observable` → iOS 17.0 (`SingleThreadCore/.../ReminderStore.swift:6`).
  - EventKit full-access (`fullAccess` / `requestFullAccessToReminders`) → iOS 17.0
    (`ReminderStore.swift:107-113`, `ContentView.swift:225`, `WatchReminderView.swift:33`).
  - WidgetKit interactive `Button(intent:)` / `containerBackground(_:for:)` → iOS 17.0
    (`NextThingWidget.swift:127,135,86`).
  - AppIntents / `LocalizedStringResource` → iOS 16.0 (`ReminderIntents.swift:7-41`).
  - Other SwiftUI modifiers (`tint`, `foregroundStyle`, `confirmationDialog`, `.labelStyle`) → iOS
    14-15.0. Everything is comfortably below the 18.7 goal floor.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is project-level (`project.pbxproj:528`, `:583`), so any
  availability/floor warning raised when building at 18.7 becomes a **hard compile failure** — this
  is our backstop that a mistakenly-low deployment target cannot silently pass.
- CI pins `runs-on: macos-26` (host) and `setup-xcode` `xcode-version: '26.6'` (SDK) in
  `.github/workflows/ci.yml` (`:13,26` / `:74,87`, matrix `iPhone 17` / `iPad (A16)` at `:16,77`).
  `Makefile` (`SIM` = iPhone 17 at `:1`) and `scripts/test.sh` (`:5-7`) never pin or validate a
  deployment target value.

## Desired End State

The iOS app — and, per decision, every target and the Swift package — declares **18.7** as its
minimum supported iOS/macOS/watchOS version, **without removing, gating, or degrading any existing
features**. Concretely:

- Every `*_DEPLOYMENT_TARGET` literal in `project.pbxproj` (iOS app, test targets, UI tests, watch,
  widget) reads **18.7**, not 26.5.
- Every platform floor in `SingleThreadCore/Package.swift` (`:7-9`) reads **18.7**.
- `scripts/test.sh` gains a **config guard** that fails fast if any deployment target / package
  platform diverges from 18.7 (the missing consistency mechanism).
- The full build + unit + UI-test pipeline runs clean at 18.7 before commit.

**Correctness verification** — the build output is the canonical proof:
1. A clean build of every target at target 18.7 with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and
   `CLANG_WARN_UNGUARDED_AVAILABILITY` proves no Swift/SDK availability warnings were emitted — the
   API floors are all ≤ iOS 17.0, well below 18.7.
2. The package floor/target `max()` composition stays consistent (package floor = target = 18.7), so
   no "minimum deployment target of iOS 26.5" SPM raise is possible.
3. Unit tests, UI tests (accessibility audit), Periphery, SwiftFormat, SwiftLint all pass unchanged.
4. The config guard in `scripts/test.sh` proves the repo is, and stays, at 18.7.

## Patterns to Follow

- **Deployment targets are target-level XCBuildConfiguration literals** (`project.pbxproj:617-899`),
  not `$(inherited)` refs — each must be edited individually. Follow the existing repetition shape.
- **Package floor is a separate literal** in `SingleThreadCore/Package.swift:7-9`. Keep it equal to
  the target floor.
- **Reuse `scripts/test.sh` as the check-site for the new guard.** It already centralizes `SIM` /
  `SCHEME` overrides (`:5-9`) and runs the whole build/test/lint pipeline; adding a config guard
  there means CI (which mirrors it) validates deployment targets on every run.
- **Prefer cheap failable failures.** `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (`:528`) is the right
  enforcement model; the new guard extends the same "fail loudly" philosophy to config, which
  nothing currently checks.
- **Do NOT follow** the widget's pre-planned pattern of declaring `macosx` in `SUPPORTED_PLATFORMS`
  with no `MACOSX_DEPLOYMENT_TARGET` (`:863` vs nothing) — it is a silent gap that only survives
  because the widget macOS build is never exercised.

## Design Decisions

1. **Repo-wide uniform 18.7 (user Q1=B, Q2=repo-wide)**: Lower every deployment-target literal in
   `project.pbxproj` (iOS, macOS, watchOS across all 5 targets) *and* every platform floor in
   `Package.swift` to 18.7. Rationale: keeps the repo homogeneous (it was 26.5 everywhere), keeps
   tests' exercise at the same OS the app targets, and avoids a two-tier split. This exceeds the
   strict iOS task but is the requested scope; the bottom-line API floors (iOS 17 / macOS 14 /
   watchOS 10) all remain safe at 18.7.

2. **Package floor moved in lockstep with target (user Q1)**: `Package.swift:7-9` becomes
   `18.7` at the same time as the target change. No mismatch, no SPM `max()` floor raise, no
   build error introduced.

3. **Config guard added to `scripts/test.sh` (user Q3)**: a few lines that read the deployment
   target of each target and the three package platforms, asserting each equals `18.7`, and fail
   fast with a clear message on drift. This is explicitly for the repo's "no consistency mechanism"
   gap (research Q1/Q3).

4. **Clean-build-first verification (user Q4a)**: Apply the config change, then run a single
   `xcodebuild` build at 18.7 *before* the full pipeline to prove the bump is warning-free. Then run
   the full `scripts/test.sh` and treat a clean build + passing test suite as the acceptance signal.

## What We're NOT Doing

- **No feature removal, gating, or degradation.** 18.7 is above every used API floor (iOS 17 max),
  so no code changes of any kind are required or allowed to satisfy the new target.
- **No new runtime OS-version checks.** The source has zero availability gates today; we do not
  introduce `#available`/`#available iOS 18.7` guards or `systemVersion` branches into Swift files.
- **Not closing the widget's missing `MACOSX_DEPLOYMENT_TARGET` gap.** The widget is only built for
  iOS; fixing its macOS build stit is out of scope.
- **Not renumbering the version metadata** (that fields like `LastUpgrade`/`objectVersion`/CI
  workflow values — the scheme/SDK pinning is orthogonal to the app's minimum).
- **Not altering any target's `SDKROOT`, `SUPPORTED_PLATFORMS`, or `TARGETED_DEVICE_FAMILY`.**
  Only the deployment-target and package-floor literals change.

## Open Risks

- **Mac/watchOS validity risk**: 18.7 is a real *iOS* minimum, but macOS and watchOS version
  numbering differs; `MacOS XCode ** xcode-version 26.6 (CI) may reject a macOS/watchOS deployment
  target of 18.7 or warn on it. Decision 4a exists to surface this early. If 18.7 proves invalid
  only for macOS/watchOS, the safe fallback is to keep `MACOS..._DEPLOYMENT_TARGET` and
  `WATCHOS_DEPLOYMENT_TARGET` (and the package `.macOS`/`.watchOS` floors) at 26.5, keeping iOS the
  18.7 floor. This partial rollback must be guarded by the config guard too, so it exactly matches
  whatever values we land on.
- **Unexpected availability warnings**: although no used API exceeds iOS 17.0, an SDK-level
  availability warning could still fire. `SWIFT_TREAT_WARNINGS_AS_ERRORS` would surface it — good,
  but it means we pause and re-examine rather than letting a warning slip.
- **Package/target mismatch semantics un-observed**: The research did not empirically capture the
  SPM mismatch diagnostic text. Because we change Target and package in lockstep as a single
  commit, this risk is minimal, but a partial edit (e.g. only some targets) would produce the
  untested error path.