## Q3 Findings: Platforms, Deployment Targets & Conditionals

### 1. Supported platforms (project-level build configs)

`SingleThread.xcodeproj/project.pbxproj` contains three targets (app `SingleThread`, `SingleThreadTests`, `SingleThreadUITests`), each with Debug/Release configurations. All of them declare the same platform set.

**App target `SingleThread`** — Debug config (XCBuildConfiguration `51AA3EFA...`) and Release (`51AA3EFB...`):
- `SDKROOT = auto` — project.pbxproj:419 (Debug), :463 (Release)
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"` — project.pbxproj:421 (Debug), :465 (Release)
  - i.e. **iOS device, iOS Simulator, macOS, visionOS (xrOS), visionOS Simulator**
- `IPHONEOS_DEPLOYMENT_TARGET = 26.5` — project.pbxproj:411 (Debug), :455 (Release)
- `MACOSX_DEPLOYMENT_TARGET = 26.5` — project.pbxproj:414 (Debug), :458 (Release)
- `XROS_DEPLOYMENT_TARGET = 26.5` — project.pbxproj:428 (Debug), :472 (Release)
- `TARGETED_DEVICE_FAMILY = "1,2,7"` — project.pbxproj:427 (Debug), :471 (Release)
  - Family 1 = iPhone, 2 = iPad, 7 = visionOS (Apple Vision / xrOS device)

**Test target `SingleThreadTests`** — same values:
- `IPHONEOS_DEPLOYMENT_TARGET = 26.5` — :484 (Debug), :510 (Release)
- `MACOSX_DEPLOYMENT_TARGET = 26.5` — :485, :511
- `SDKROOT = auto` — :489, :515
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"` — :491, :517
- `TARGETED_DEVICE_FAMILY = "1,2,7"` — :496, :522
- `XROS_DEPLOYMENT_TARGET = 26.5` — :498, :524

**UI test target `SingleThreadUITests`** — same values:
- `IPHONEOS_DEPLOYMENT_TARGET = 26.5` — :535 (Debug), :560 (Release)
- `MACOSX_DEPLOYMENT_TARGET = 26.5` — :536, :561
- `SDKROOT = auto` — :540, :565
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"` — :542, :567
- `TARGETED_DEVICE_FAMILY = "1,2,7"` — :547, :572
- `XROS_DEPLOYMENT_TARGET = 26.5` — :549, :574

Related project metadata:
- `objectVersion = 77` (Xcode 26 / file-system-synchronized groups) — project.pbxproj:6
- `SWIFT_VERSION = 6.0` — project.pbxproj:426, 470, 493, 519, 544, 569
- `DEVELOPMENT_TEAM = 6NWX2DHB9Q` — project.pbxproj:224 (project Debug), 272 (project Release) and repeated in each target config

### 2. Platform conditionals in Swift sources

All `#if os(...)` conditionals are in `SingleThread/ContentView.swift`:

| Line | Code | Platform branch |
|------|------|-----------------|
| ContentView.swift:26 | `#if os(macOS)` | macOS |
| ContentView.swift:28 | `#endif` | — |
| ContentView.swift:30 | `#if os(iOS)` | iOS |
| ContentView.swift:34 | `#endif` | — |
| ContentView.swift:69 | `#if os(macOS)` | macOS |
| ContentView.swift:75 | `#else` | everything else (iOS/visionOS) |
| ContentView.swift:77 | `#endif` | — |

Specifics:
- ContentView.swift:26-28 — `.navigationSplitViewColumnWidth(min: 180, ideal: 200)` applied only on macOS.
- ContentView.swift:30-34 — `ToolbarItem(placement: .navigationBarTrailing) { EditButton() }` only on iOS.
- ContentView.swift:69-77 — `NavigationViewWrapper` body uses `NavigationSplitView` (content + detail "Select an item") on macOS; plain `content()` otherwise.

**No conditionals found** in:
- `SingleThread/Item.swift` — plain `@Model` class, no `#if`.
- `SingleThread/SingleThreadApp.swift` — plain `@main App` with `WindowGroup`, no `#if`.
- `SingleThreadTests/*.swift`, `SingleThreadUITests/*.swift` — grep for `#if os|#elseif os|#else|#endif|@available|canImport|TARGET_OS|platform` returned no matches.

No `@available`, `canImport`, or `TARGET_OS_*` conditionals were found in any Swift source.

### 3. Related note (existence only, not a recommendation)

`SingleThread/Assets.xcassets/AppIcon.appiconset/Contents.json` defines icon entries only for `"platform": "ios"` (Contents.json:5, :16, :27) and `"idiom": "mac"` (:28-:70). There is no visionOS (`idiom: vision` / `platform: xrOS`) icon entry, even though `SUPPORTED_PLATFORMS` and `TARGETED_DEVICE_FAMILY` include visionOS. Also note the app icon has no visionOS entries and the AppIcon is referenced via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (project.pbxproj:404, :448).

CI currently builds/tests only the iOS Simulator destination (`platform=iOS Simulator,name=iPhone 17`) — see `.github/workflows/ci.yml:22-38`, `scripts/test.sh:7`, `Makefile:1` — despite the multi-platform project config.