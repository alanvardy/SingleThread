# Research Findings

Codebase: SingleThread Xcode project (iOS app + watchOS app + widget + Swift local package). All deployment/OS-version values currently read **26.5**.

## Q1: Where the minimum OS deployment target is expressed, per target, and how they relate

### Findings
- **Project-level configs set no deployment target.** The two project configs (`PBXProject "SingleThread"`, Debug `51AA3EF7` / Release `51AA3EF8`) set only build-flag settings (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` at `project.pbxproj:528,583`; `DEBUG_INFORMATION_FORMAT = dwarf` / `dwarf-with-dsym` at `:503,566`; `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` at `:499,562`; `LastUpgradeCheck = 2660` at `:321`; `objectVersion = 77` at `:6`). There is no project-wide `*_DEPLOYMENT_TARGET`.
- Each native target carries its own platform-specific deployment target as a **hardcoded literal** (16 occurrences, all `26.5`):
  - iOS app `SingleThread`: `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (`:617` Debug, `:667` Release) and `MACOSX_DEPLOYMENT_TARGET = 26.5` (`:620` Debug, `:670` Release). `SDKROOT = auto` (`:625,675`), `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`:627,677`), `TARGETED_DEVICE_FAMILY = "1,2"` (`:633,683`).
  - `SingleThreadTests`: `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (`:695,720`), `MACOSX_DEPLOYMENT_TARGET = 26.5` (`:696,721`); same SDKROOT/SUPPORTED_PLATFORMS/devices (`:700,702,707` / `:725,727,732`).
  - `SingleThreadUITests`: `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (`:744,768`), `MACOSX_DEPLOYMENT_TARGET = 26.5` (`:745,769`); SDKROOT/supported/devices `:749,751,756` / `:773,775,780`.
  - `SingleThreadWatch`: `WATCHOS_DEPLOYMENT_TARGET = 26.5` (`:809` Debug, `:837` Release). `SDKROOT = watchos` (`:800,828`), `SUPPORTED_PLATFORMS = "watchos watchsimulator"` (`:803,831`), `TARGETED_DEVICE_FAMILY = 4` (`:808,836`). No `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`.
  - `SingleThreadWidget`: `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (`:853` Debug, `:884` Release) only. `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`:863,894`), `TARGETED_DEVICE_FAMILY = "1,2"` (`:868,899`). No `SDKROOT`, no `MACOSX_DEPLOYMENT_TARGET` (see Q4).
- `SingleThreadCore/Package.swift` declares all three OS minimums as string literals in one `platforms:` array: `.iOS("26.5")` (`:7`), `.watchOS("26.5")` (`:8`), `.macOS("26.5")` (`:9`). No `.tvOS` / `.visionOS`.
- **Relationship:** `SingleThreadCore` is a local Swift package (`XCLocalSwiftPackageReference`, `relativePath = SingleThreadCore` at `:965`; product dep at `:972`). Its product `SingleThreadCore` is consumed by app (`packageProductDependencies` at `:213`), `SingleThreadTests` (`:237`), `SingleThreadWatch` (`:283`), `SingleThreadWidget` (`:306`). `SingleThreadUITests` links it with an **empty** list (`:261-262`).
- **Lockstep status:** Currently in lockstep *by value* only — every platform declaration in both files reads `26.5`. There is **no single source of truth**; the value is duplicated manually as 16 literals in `project.pbxproj` and 3 in `Package.swift`. Nothing enforces equality between the two files.

## Q2: SwiftUI / Observation / AppKit / AppIntents APIs with an inherent OS floor, and OS-version gating

### Findings
- **No OS-version gating exists in the codebase.** Searches across all `.swift` files for `@available`, `#available`, `@unavailable`, `systemVersion`, `operatingSystemVersion`, `.requires` found **zero runtime OS-version checks**.
  - Only `ProcessInfo` usage is UI-test argument detection, not version gating: `SingleThread/SingleThreadApp.swift:16` (`ProcessInfo.processInfo.arguments.contains("--ui-testing")`); `SingleThreadWatch/SingleThreadWatchApp.swift:11` (same).
  - The only `.requires`-like matches are documentation/property, not version checks: `SingleThreadCore/Sources/SingleThreadCore/ReminderDictationParser.swift:50` (doc comment), `ReminderDateFilter.swift:11` (doc comment), `SingleThread/ReminderDictation.swift:112` (`requiresOnDeviceRecognition` SFSpeech property).
  - `recognizer.isAvailable` (`SingleThread/ReminderDictation.swift:54`) is a runtime capability check, not OS-version gating.
- **The only conditional compilation is platform gating** (`#if os(iOS)` / `#if os(macOS)` / `#if os(watchOS)`), never version gating:
  - `SingleThread/AppDelegate.swift:1` (`#if os(iOS)`), `:62` (`#if os(macOS)`, `import AppKit`)
  - `SingleThread/Color+CrossPlatform.swift:3-4` (`#if os(macOS)` AppKit / `#else` UIKit)
  - `SingleThread/AppearanceMode.swift:1-6` (UIKit vs AppKit imports)
  - `SingleThread/SingleThreadApp.swift:4-10,40-48,61-67`; `SingleThread/SettingsView.swift:3-5`
  - `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:25-39` (`#if !os(watchOS)`)
  - `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (`#if os(watchOS)` in `completeReminder`)
  - `SingleThread/ReminderDictation.swift:104-108,135-137` (`#if os(iOS)`)
- **API families used that carry an inherent OS floor** (all below the configured `26.5` target, so none currently raises the minimum — they matter only if the target is lowered):
  - **Observation**: `@Observable` / `@ObservationIgnored` — `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:6`, `SingleThread/ReminderDictation.swift:23,80-87` → floor iOS 17.0 / macOS 14.0 / watchOS 10.0.
  - **AppIntents**: `AppIntent`, `IntentResult`, `perform()` — `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:7,18,30,41` → iOS 16.0 / macOS 13.0 / watchOS 9.0.
  - **AppIntents + WidgetKit interactive buttons**: `Button(intent:)` — `SingleThreadWidget/NextThingWidget.swift:127,135` → iOS 17.0 / macOS 14.0 / watchOS 10.0.
  - **LocalizedStringResource** (AppIntents titles) — `ReminderIntents.swift:14,37` → iOS 16.0 / macOS 13.0.
  - **EventKit full-access API**: `EKAuthorizationStatus.fullAccess`, `requestFullAccessToReminders()` — `ReminderStore.swift:107-113,261-271`, `EventKitStoring.swift:14,42-43`, `ContentView.swift:225`, `NextThingWidget.swift:56-57`, `WatchReminderView.swift:33` → iOS 17.0 / macOS 14.0 / watchOS 10.0.
  - **WidgetKit `containerBackground(_:for:)`** — `NextThingWidget.swift:86` → iOS 17.0 / watchOS 10.0.
  - **SwiftUI `.onChange(of:)` two-parameter closure** — `SingleThreadApp.swift:57` → iOS 17.0 / macOS 14.0.
  - SwiftUI `.tint(_:)` — `NextThingWidget.swift:131,140`, `WatchReminderView.swift:89,95` → iOS 15.0; `.foregroundStyle(_:)` — `NextThingWidget.swift:149-155`, `WatchReminderView.swift:105,113,160` → iOS 15.0; `.labelStyle(.iconOnly)` — `NextThingWidget.swift:128,137`, `WatchReminderView.swift:85,92` → iOS 14.0; `.confirmationDialog` — `WatchReminderView.swift` (~`:131`) → iOS 15.0.
  - **`#Preview` macro** (dev-time only) — `ContentView.swift:470+`, `WatchReminderView.swift:214+`, `NextThingWidget.swift:195+`, `SettingsView.swift:192+` → Xcode 15 / iOS 17 SDK.
  - **AppKit** (`NSWindow`, `NSAppearance`, `NSApp`) — `AppDelegate.swift:62-91`, `Color+CrossPlatform.swift:4,12`, `AppearanceMode.swift:5,34-42`, tests `AppDelegateTests.swift`, `AppearanceModeTests.swift:8` → macOS only (no iOS floor).
  - **Speech/AVFoundation**: `SFSpeechRecognizer` — `ReminderDictation.swift:1-2,54,112` → iOS 13.0 (`requiresOnDeviceRecognition`).
  - **WatchConnectivity**: `WCSession` — `SingleThreadApp.swift:22-30` → iOS 9.0 / watchOS 2.0.

### Summary
- The source calls these APIs unconditionally and relies entirely on the `26.5` deployment target; no runtime/compile-time version gate compensates for a lower target with code changes.

## Q3: Package platform minimums vs. target deployment targets; toolchain behavior

### Findings
- `SingleThreadCore/Package.swift` (`:6-10`) declares the package's `platforms` array with **string literals** `"26.5"` for `.iOS`, `.watchOS`, `.macOS` — a floor, not a pin. `// swift-tools-version: 6.0` at `:1`.
- The package is a **local Swift package** (`XCLocalSwiftPackageReference` at `project.pbxproj:963-966`, `relativePath = SingleThreadCore`); consumed by product `SingleThreadCore` (`project.pbxproj:966-972`) from the app (`:213`), tests (`:237`), watch (`:283`), widget (`:306`). `SingleThreadUITests` does not link the product (`:261`).
- **Currently no disagreement exists**: every target deployment target and every package platform minimum is `26.5`, exactly equal.
- **Consistency mechanism: none exists.** `26.5` is duplicated manually between `Package.swift` and every target's `*_DEPLOYMENT_TARGET`. No script, Makefile target, or CI step cross-checks package platform minimums against deployment targets (confirmed via repo-wide grep; only literal declarations exist, no validation logic). No `Package.resolved` file exists (local package, no remote deps).
- **Toolchain behavior on a mismatch** (SPM min-deployment-target `max()` composition semantics — not directly observed because current values agree): the `platforms` floor composes with the consuming target's deployment target as the **maximum**. Target ≥ package minimum → fine. Target < package minimum → the package minimum wins and the effective target is **raised**; this surfaces as a build-time error/warning-level condition (agent-reported diagnostic shape: "module 'SingleThreadCore' has a minimum deployment target of iOS 26.5…"), not a silent silent pass. This was not empirically captured in this repo (all values equal).

## Q4: watchOS app and widget vs iOS app deployment targets

### Findings
- **iOS app target** (`SingleThread`): `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (Debug `:617`, Release `:667`), `MACOSX_DEPLOYMENT_TARGET = 26.5` (`:620,:670`), `SDKROOT = auto` (`:625,:675`), `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`:627,:677`), `TARGETED_DEVICE_FAMILY = "1,2"` (`:633,:683`).
- **watchOS app** (`SingleThreadWatch`): `WATCHOS_DEPLOYMENT_TARGET = 26.5` (`:809` Debug, `:837` Release), `SDKROOT = watchos` (`:800,:828`), `SUPPORTED_PLATFORMS = "watchos watchsimulator"` (`:803,:831`), `TARGETED_DEVICE_FAMILY = 4` (`:808,:836`). No iPhone/macOS deployment target — consistent since it declares no such platform.
- **Widget** (`SingleThreadWidget`): `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (`:853` Debug, `:884` Release), `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`:863,:894`), `TARGETED_DEVICE_FAMILY = "1,2"` (`:868,:899`).
- **Divergences / omissions:**
  - **Widget omits a deployment target for a platform it declares**: `SUPPORTED_PLATFORMS` includes `macosx` (`:863,:894`) but **no `MACOSX_DEPLOYMENT_TARGET` is set** — only `IPHONEOS_DEPLOYMENT_TARGET`, in both Debug and Release. The iOS app, tests, and UI tests all set `MACOSX_DEPLOYMENT_TARGET = 26.5` for that same platform list. This is not a current problem because the widget is only built for iOS (embedded in the iOS app), and CI/Makefile never build the widget for macOS.
  - **Widget omits `SDKROOT`** entirely — it is the only target with no `SDKROOT` (app/tests/UITests use `auto` `:625,675,700,725,749,773`; watch uses `watchos` `:800,828`). It falls back to the SDK default.
  - **No inheritance gap**: project-level configs (`:499-590`) set no deployment target, `SDKROOT`, `SUPPORTED_PLATFORMS`, or `TARGETED_DEVICE_FAMILY`; all are target-level `XCBuildConfiguration` literals, not `$(inherited)` references.
- **Lockstep**: all deployment values converge at exactly `26.5` across all three targets; only the platform-constraint set (`SDKROOT`, `SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY`) diverges per target.

## Q5: Where the build/test/CI toolchain pins or relies on deployment-target / OS-version values

### Findings
- **`project.pbxproj` is the only place deployment targets are pinned.** All `*_DEPLOYMENT_TARGET` literals live here (`:617,620,667,670,695,696,720,721,744,745,768,769,809,837,853,884`).
- **`Makefile`** does not pin or verify deployment-target / OS-version values. Only destinations and schemes: `SIM ?= platform=iOS Simulator,name=iPhone 17` (`:1`), `WATCH_SIM := generic/platform=watchOS Simulator` (`:2`), `MAC_SIM := platform=macOS` (`:3`); `-scheme SingleThread` (`:13,19,22,26,39,52,72`), `-scheme SingleThreadWatch` (`:16`), `periphery scan … -destination "$(SIM)"` (`:83`). No `IPHONEOS_DEPLOYMENT_TARGET`, no `-showBuildSettings`, no version assertion.
- **`scripts/test.sh`** likewise: `SIM` / `WATCH_SIM` / `MAC_SIM` (`:5-7`), `SCHEME` / `WATCH_SCHEME` (`:8-9`), and repeated `xcodebuild -scheme …` calls (`:91-182`). Only OS-adjacent logic is `cleanup_xctest_runtimes` / `RUNTIME_AGE_HOURS` (`:15-47`) pruning simulator runtime dirs by age — unrelated to deployment targets. No value is validated before `xcodebuild` runs.
- **`.github/workflows/ci.yml`** pins host toolchain and device names, not deployment target:
  - `runs-on: macos-26` (`:13,:74,:127,:179`) — host macOS.
  - `setup-xcode` with `xcode-version: '26.6'` (`:26,:87,:136,:186`) — selects the **Xcode/SDK**, which determines the SDK's valid deployment-target range for which `26.5` is valid.
  - Matrix `device: ["iPhone 17", "iPad (A16)"]` (`:16,:77`) and `SIM: platform=iOS Simulator,name=…` (`:18,:79`).
- **`.mise.toml`** pins only tool versions (swiftlint `:2`, swiftformat `:3`, periphery `:4`) — no SDK/deployment-target pinning.
- **Where an invalid / missing / inconsistent deployment target becomes visible:**
  - **Build/test failure** at `xcodebuild` time: warning-as-error is active project-wide (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` at `project.pbxproj:528,583`) and `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` (`:499,562`), so Swift availability/deployment warnings above the declared target become **hard build failures** in every target.
  - The **package floor** is checked at SPM/package resolution (a target below the package minimum raises the effective target / errors — Q3).
  - **Not caught at all**: the widget's missing `MACOSX_DEPLOYMENT_TARGET` despite `macosx` in `SUPPORTED_PLATFORMS` is never surfaced, because no build step exercises the widget for macOS.
  - **Silently-passing risk**: a wrong-but-valid target (e.g. a typo'd `26.5` → `26.6`, or a lower value still within the SDK's valid range and above the package floor) is not cross-asserted; nothing in the Makefile / script / CI greps `-showBuildSettings` or asserts an expected deployment-target value.

## Cross-Cutting Observations
- Every deployment target, every package platform floor, and every `LastUpgradeVersion` (`xcschemes` = 2660) / `LastUpgradeCheck` = 2660 currently reads the same OS-era version (`26.5`); the toolchain's Xcode/SDK is `26.6` (CI) / scheme 2660. The *host* macOS and the *deployment target* are distinct concepts: CI pins `macos-26` (host) and `xcode-version: 26.6` (SDK), but nothing in the toolchain pins the app's stated deployment target.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is the key amplification mechanism: any warning raised by lowering the deployment target (availability, package floor, API sofa) becomes a compile error. This is project-level and inherited by all targets.
- Every target value across the repo is currently homogeneous (`26.5`); any future change must be applied in up to 16 `pbxproj` literals plus 3 `Package.swift` literals in lockstep, because there is no derivation/variable sharing between them.

## Open Areas
- Exact diagnostic text and error-vs-warning classification of an SPM package/target deployment-target mismatch was not empirically captured (no build run; repo currently has no mismatch). The behavior described (max() floor composition) is standard SPM semantics, not repo-observed.
- Whether a widget macOS build would currently compile given the missing `MACOSX_DEPLOYMENT_TARGET` was not exercised (never built for macOS).
- The precise list of OS-version floors per API family is asserted from the agent's Xcode/framework knowledge, not from repo-only evidence — floors were not empirically re-derived from SDK headers.