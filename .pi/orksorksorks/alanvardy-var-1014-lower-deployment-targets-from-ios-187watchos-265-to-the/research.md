# Research Findings

## Q1: project.pbxproj deployment targets

### Findings
- **20 `*_DEPLOYMENT_TARGET` literals total** (grep-verified): 8× `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, 6× `MACOSX_DEPLOYMENT_TARGET = 26.5`, 6× `WATCHOS_DEPLOYMENT_TARGET = 26.5`. (The ticket's "17" is stale; `scripts/test.sh:140` asserts `EXPECTED_TARGET_LITERALS=20`.)
- Line map (`project.pbxproj`, Debug/Release pairs): app 765/768 + 815/818; SingleThreadTests 843/844 + 872/873; SingleThreadUITests 900/901 + 924/925; SingleThreadWatch 965 + 993 (watchOS only); SingleThreadWidget 1009 + 1040 (iOS only); SingleThreadWatchUITests 1077 + 1099; SingleThreadWatchTests 1123 + 1147. Config→target binding via XCConfigurationList (`project.pbxproj:1149-1231`).
- Project-level configs (Debug `51AA3EF7` / Release `51AA3EF8`, lines 609-746) carry **no** deployment-target settings.
- `SDKROOT = auto` (app/Tests/UITests Debug+Release: 773/823, 848/877, 905/929); `SDKROOT = watchos` (watch targets: 956/984, 1069/1091, 1114/1138); absent for project configs and Widget.
- `SUPPORTED_PLATFORMS`: `"iphoneos iphonesimulator macosx"` (app/Tests/UITests: 775/825, 850/879, 907/931); `"watchos watchsimulator"` (watch targets: 959/987, 1071/1093, 1116/1140); `"iphoneos iphonesimulator"` (Widget: 1019/1050); absent project-level.
- `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` (project Debug:647, Release:710) — the availability warning gate; no `#available`-related flags elsewhere in the file.
- Comment at Tests Debug:853 / Release:882: "StoreKitTest's headers contain an iOS-18-deprecated symbol…", paired with `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` (856/885) — evidence that lowering min-OS affects warnings-deprecated symbols.
- Non-OS version settings present: `SWIFT_VERSION = 6.0` (all targets), `CURRENT_PROJECT_VERSION = 2`, `MARKETING_VERSION = 1.1`, `TARGETED_DEVICE_FAMILY` (`"1,2"` app, `4` watch). `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`/`[sdk=macosx*]` (762-764, 812-814) gate by platform family, no version literals.

## Q2: SPM package platform declarations

### Findings
- **Exactly one SPM manifest in the repo**: `SingleThreadCore/Package.swift` (no Package.swift in app/watch/widget/test trees — those are plain source dirs consumed as Xcode native targets).
- `Package.swift:1` `// swift-tools-version: 6.0`; `:6-10` `platforms: [ .iOS("18.7"), .watchOS("26.5"), .macOS("26.5") ]` — one array, three independent hardcoded string entries (no shared constant); `:14-18` one library target, no dependencies.
- Consumers: `project.pbxproj:1229-1232` `XCLocalSwiftPackageReference "SingleThreadCore"` + `:1236-1240` `XCSwiftPackageProductDependency`; all seven native targets list the product dependency (262, 286, 310, 333, 356, 403).
- Today package minimums and every consumer deployment target are **identical** (iOS 18.7 / watchOS 26.5 / macOS 26.5).
- No in-repo machinery handles an app-min < package-min divergence — no script/setting detects or reconciles it; behavior would be SPM/toolchain-governed and is **not verifiable in-repo**.

## Q3: @Observable macro floor

### Findings
- `@Observable` is the `Observable` macro from the **Swift framework (standard library)** under Swift 6.0 toolchain (`.swift-version` = `6.0`); no `import Observable` anywhere; no SPM dependency; `.mise.toml` pins only linters (swiftlint 0.65.0, swiftformat 0.62.1, periphery 3.8.0).
- **No per-OS availability annotation for `Observable` found in the local toolchain** (`/usr/lib/swift` holds runtime dylibs only); its floor is whatever Swift 6.0 enforces. `CLANG_WARN_UNGUARDED_AVAILABILITY` (pbxproj:647/710) does not annotate it.
- **21 `@Observable` annotations across 21 files + 2 doc mentions = 23 total mentions** (matches ticket):
  - SingleThread/ (7): SettingsBindings.swift:23, AppViewModel.swift:16, ContentViewModel.swift:14, DictationViewModel.swift:9, BackgroundImageStore.swift:54, SettingsViewModel.swift:10, ReminderDictation.swift:30.
  - SingleThreadCore/ (7 + 2 doc): EntitlementStore.swift:7(doc)/:11, EntitlementState.swift:9, CompletionMomentumOverlay.swift:14, CompletionGlow.swift:12, ReminderStore.swift:15, UndoStore.swift:7(doc)/:9, PreferenceHolder.swift:8.
  - SingleThreadWatch/ (7): ShowListState.swift:8, ShowCompletionGlowState.swift:7, ShowRecurrenceState.swift:8, WatchReminderViewModel.swift:12, ShowEnableActionButtonsState.swift:12, ShowDateState.swift:8, ShowAlarmsState.swift:8.
  - SingleThreadWidget/: **none**.
- Same-framework co-located macros sharing the floor: `@MainActor` (ReminderStore.swift:14, AppViewModel.swift:15, plus inlined `Task { @MainActor in … }` at AppViewModel.swift:36,411,414,444,462), `@Sendable` (ReminderStore.swift:10, AuthorizationRequiring.swift:20), `@AppStorage` (ContentView.swift:72-115, ContentView+Settings.swift:43-45).

## Q4: EventKit authorization APIs

### Findings
- Protocol: `EventKitStoring.swift:10` (`authorizationStatus(for:)`), `:14` (`requestFullAccessToReminders() async throws -> Bool`); `extension EKEventStore: EventKitStoring` (`:46-48`) delegates `authorizationStatus` to `Self`, and `requestFullAccessToReminders` resolves against the framework `EKEventStore`.
- Test seam: `InMemoryEventStore.swift:37-39` (always `.fullAccess`), `:45-47` (always `true`).
- `ReminderStore.swift`: init param `:33`, state `:74` (`.notDetermined`), `start()` `:451-458` (`.fullAccess` → `reload()` else `requestAccess()`), `requestAccess()` `:535-547` (call at `:539`, grant → `:540-541`, no-grant/catch → `:542/:545` re-query).
- Consumers: ContentView.swift:30,47,58 + `authGatedContent` switch `:381-391`; ContentViewModel.swift:135 (`start()` from `.task`); AppViewModel.swift:250-266 (`--ui-testing` seam seeds `.fullAccess`); ContentView+Previews.swift:47-82; WatchReminderView.swift:18,32,49-57,406-455; WatchAppViewModel.swift:156,165; NextThingWidget.swift:71. Tests: ReminderStoreTests.swift:1038,1046; EventKitStoringTests.swift:13,29,56,65.
- **EventKit is a system framework** shipped in both the iPhoneOS and WatchOS SDK platforms.
- **SDK header availability annotations (installed iPhoneOS SDK)** — this is the hard-floor evidence:
  - `Headers/EKEventStore.h:88` — `requestFullAccessToRemindersWithCompletion:` → `API_AVAILABLE(ios(17.0), macos(14.0), watchos(10.0))`
  - `Headers/EKEventStore.h:84` — `requestFullAccessToEventsWithCompletion:` → same `ios(17.0), macos(14.0), watchos(10.0)`
  - `Headers/EKEventStore.h:52` — `authorizationStatusForEntityType:` → `NS_AVAILABLE(10_9, 6_0)` (macOS 10.9 / iOS 6.0)
  - `Headers/EKEventStore.h:95` — old `requestAccessToEntityType:` → `API_DEPRECATED(ios(6.0,17.0), macos(10.0,14.0), watchos(1.0,10.0))`
- The **Swift-named** `requestFullAccessToReminders()` / `EKAuthorizationStatus.fullAccess` are **not textually present** in the C headers or `.swiftinterface`; they come via the compiled EventKit Swift module. The minimum-OS introduction is annotated at C level on the completion-based method: **iOS 17.0 / macOS 14.0 / watchOS 10.0** — matching the ticket's hard floor (macOS note: 14.0 is the classic-macOS scheme; the package currently declares macOS 26.5).

## Q5: OS-version-dependent code patterns

### Findings
- `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` at pbxproj:647 (Debug) and :710 (Release) — the only availability gate.
- **No `#available`, `__has_feature`, or runtime OS-version checks anywhere** (no CocoaVersion / operatingSystemVersion / version comparison).
- The actual mechanism is **Swift preprocessor conditionals**, compile-time only:
  - `#if os(iOS|watchOS|macOS)`: ReminderStore.swift:138,230,276,310,342,370,397,454; EventKitStoring.swift:26,50; InMemoryEventStore.swift:84; AboutView.swift:51; ContentView+Settings.swift:22,30,47,61; ReminderSettingsView.swift:36,63,79; SettingsView.swift:40,50.
  - `#if canImport(SwiftUI|UIKit|AppKit)`: CodeSpanFormatter.swift:3,122,137,143,146.
- Capability fallbacks (feature detection): AppGroup.swift:14-18 (`UserDefaults(suiteName:) ?? .standard` when group unavailable), ShowEnableActionButtonsState.swift:6, PendingCompletionStore.swift:8.
- Visual/effect code (per-platform, compile-time): CompletionGlow.swift:25-27 (watchOS 0.4 s envelope), ContentView.swift:264,267; WatchReminderView.swift:124,186; CodeSpanFormatter.swift:124-150 (watchOS gray / iOS `UIColor.secondarySystemBackground` / macOS `NSColor.underPageBackgroundColor`); ControlPlateModifier.swift:6,28,36 (`.shadow(radius: 4)`); ContentView+Settings.swift:7 (modifier-chain budget 13 macOS / 19 iOS).
- OS-version comments/constants: CodeSpanFormatter.swift:144 ("secondarySystemBackground is available iOS 13+"), :147 (macOS lacks it); Package.swift:7-9; ShowListState.swift:6 / ShowDateState.swift:6 / ShowAlarmsState.swift:6 / ShowRecurrenceState.swift:6 ("UserDefaults writes is OS-version-dependent"); scripts/test.sh:271 + `.pi/skills/simulator-pairing/SKILL.md:24` ("watchOS 26.5 simruntime").
- **No Liquid Glass / lucid / dynamic-island references** in any source — the app touches none of those APIs; all version-specific behavior is compile-time (`os`/`canImport`) or hardcoded-floor comments. `SingleThreadTests/AppDelegateTests.swift:13` notes an unused API "available only for newer deployment targets" vs this target's 18.7.

## Q6: Distribution metadata and CI/test infrastructure

### Findings
- **No market-facing OS-requirement text exists**: no README/CHANGELOG/release-notes/what's-new/fastlane/store metadata in `git ls-files`; `docs/` has only `SimulatorManualVerification.md` + `TestFlight-macOS.md`, with grep finding no OS-version phrasing; `exportOptions.plist:5-8` is app-store-connect export config (method/signingStyle/teamID `6NWX2DHB9Q`), no OS requirement; TestFlight-macOS.md requirements are portal/capability/signing-only.
- Internal OS-floor reasoning lives only in earlier QRSPI artifacts (e.g. `.pi/worksorksorks/…-var-637-…/research.md:35-43`, iOS 17.0 floors).
- CI (`ci.yml`): all Apple jobs `runs-on: macos-26` (6,66,127,168,238) + `xcode-version: '26.6'` (21-24,76-79,130-133,171-174,252-255); unit-tests matrix `["iPhone 17", "iPad (A16)"]` (8-10), ui-tests-smoke `["iPhone 17"]` (65-67); sims addressed by **name only** (`SIM=platform=iOS Simulator,name=…`, 12/70), UDID resolved + pre-booted (48-52,108-111); mac-tests uses `platform=macOS` (172); watch-ui-tests boots a fresh unpaired watch sim with the **latest watchOS runtime**, nailed by `id=` (214-226,244-259).
- DerivedData caching: `actions/cache` on `$workspace/DerivedData` (33-45,93-105,143-155,184-194,224-232); cache key includes `hashFiles(...project.pbxproj)` → **a pbxproj deployment-target edit busts the CI cache**.
- Simulator destination pinning precedence (Makefile:1-11): explicit `SIM=` > worktree `.simulator_id` > default `name=iPhone 17`; Makefile:14-17 exports `SIM` only when user-set; `scripts/test.sh:36-42` `resolve_sim_udid()` pins name-only dests (ambiguity-hang workaround), pre-boots (56-70); serving `.simulator_id` = BFB5C8FB-5ED5-48AD-9149-298E20FCB4E6.
- Periphery: `make periphery` = full scan `periphery scan --strict -- -destination "$(SIM)"` (Makefile:158); `scripts/test.sh:240-241` = `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`; CI lint job uses the full-scan form (ci.yml:260); `.periphery.yml` pins project/schemes SingleThread. `DERIVED_DATA := DerivedData` (Makefile:11, test.sh:16).
- **`verify_deployment_target()` gate (scripts/test.sh:130-192, invoked :193 before any build in every mode)**: defaults `DEPLOYMENT_TARGET_IOS=18.7` / `DEPLOYMENT_TARGET_OTHER=26.5`, **env-overridable** (138-139); asserts every one of the 20 pbxproj literals (8 iOS / 6 macOS / 6 watchOS) and all 3 Package.swift literals match, plus literal-count drift checks `EXPECTED_TARGET_LITERALS=20` / `EXPECTED_PACKAGE_LITERALS=3` (140-141); any drift → exit 1. Comment (131-137): "18.7 is NOT a valid watchOS or macOS deployment target under Xcode 26 — there is no 18.x version line for those platforms".
- Stale-index gotcha: AGENTS.md:28 (`make periphery` reads a stale build index after branch switches — clean `DerivedData/`); one-xcodebuild-at-a-time AGENTS.md:32-34; run-gate SKILL.md:19.
- watchOS sim runtime gotcha: local 26.5 simruntime missing `lib_TestingInterop.dylib`, worked around by bundling the Xcode lib into the watch UI test runner (test.sh:271-288; simulator-pairing SKILL.md:24).
- UI/smoke jobs disable parallel simulator clones (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`, ci.yml:88-91,153-155) citing EventKit/EKReminder SIGTRAP flakiness.

## Cross-Cutting Observations

- **One gate owns the floor**: `scripts/test.sh` `verify_deployment_target()` is the single enforcement point that all 20 pbxproj literals + 3 Package.swift literals must match, with env overrides `DEPLOYMENT_TARGET_IOS` / `DEPLOYMENT_TARGET_OTHER`. Any floor change must update the package, the pbxproj literals, and the gate's defaults (or invoke it with env overrides).
- **Hard-floor evidence pinned in the SDK**: EventKit's own headers annotate the full-access request floor at **iOS 17.0 / macOS 14.0 / watchOS 10.0** (EKEventStore.h:88) — confirming the ticket's hard floor. `@Observable`'s floor is toolchain-wideSwift 6.0, not per-OS, and unannotated locally.
- **No runtime OS branching exists**: all platform/version behavior is compile-time (`#if os()`, `canImport()`) plus the unguarded-availability warning gate; "pre-Liquid-Glass" runtime behavior cannot be verified from code — nothing in the sources references those APIs, and no iOS ≤18 / watchOS ≤25 runtime is installed locally.
- **Version-scheme asymmetry**: iOS and watchOS/macOS floors are on different version lines — 18.7 is invalid for watchOS/macOS (test.sh:131-137), and EventKit's `macos(14.0)` uses the classic scheme while the package declares macOS 26.5. Per-platform floors may legitimately differ (iOS 17.0 / watchOS 11.0 or 10.0 / macOS unchanged-at-26.5).
- Ticket-count drift: ticket predicted "17 pbxproj literals" — actual is **20** (the ticket's earlier analysis missed the watch test/UI-test configures and pairing). CI cache key busts on pbxproj hash, so the DerivedData cache self-invalidates on this change.
- Distribution-metadata surface is **empty** — no release notes/store copy in-repo to update (only docs/, TestFlight runbook, exportOptions.plist with an App Store team binding).

## Open Areas

- Exact minimum-OS introduction of the Swift-named `requestFullAccessToReminders()` (not present in C headers/`.swiftinterface`; lives in the compiled EventKit Swift module — annotated floor inferred from the completion-based C method only).
- `@Observable`'s per-OS floor: not annotated anywhere locally; whatever Swift 6.0 + availability checker enforces (this is the ticket's stated pin for iOS 17.0 / watchOS 10.0, unproven from local files).
- SPM/toolchain behavior when a consumer's deployment target is lower than a dependency package's declared platform minimum (no in-repo machinery; not toolchain-verified per research constraints).
- Runtime verification of "pre-Liquid-Glass" UI on iOS 17/18 and watchOS 10/11 — no such runtimes installed locally; CI runs latest runtimes (watchOS 26.5 simruntime per test.sh:271).
- `docs/SimulatorManualVerification.md` was not read in full by research (grep found no OS-version strings, but the manual's sim-verification steps may be affected by floor re-probing).