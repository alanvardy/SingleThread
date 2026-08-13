# Research Findings

## Q1: Trace how the app's persistence layer works end-to-end

### Findings
- **Single `@Model`**: `final class Item`, annotated `@Model`, lives in `SingleThread/Item.swift:10-20`. It has exactly one persisted property, `var timestamp: Date` (`Item.swift:20`), set by `init(timestamp: Date)` (`Item.swift:14-16`). Imports are `Foundation` + `SwiftData` (`Item.swift:7-8`).
- **Container construction**: `SingleThreadApp` (`@main struct SingleThreadApp: App`, `SingleThread/SingleThreadApp.swift:10-11`) builds a stored `sharedModelContainer` (`SingleThreadApp.swift:12-23`):
  - `Schema([Item.self])` — `SingleThreadApp.swift:13-15`
  - `ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)` — `SingleThreadApp.swift:16` (on-disk persistence)
  - `try ModelContainer(for: schema, configurations: [modelConfiguration])` — `SingleThreadApp.swift:19`; failure is `fatalError` (`SingleThreadApp.swift:21`).
- **Injection**: `.modelContainer(sharedModelContainer)` is applied to the root `WindowGroup { ContentView() }` (`SingleThreadApp.swift:26-29`), injecting a `ModelContext` into the environment.
- **Read path**: `ContentView` declares `@Query private var items: [Item]` (`SingleThread/ContentView.swift:46`) — a no-predicate, no-sort fetch of all `Item` records. The query auto-reflects inserts/deletes; no explicit `save()` call exists anywhere.
- **Write path**: `@Environment(\.modelContext) private var modelContext` (`ContentView.swift:45`); `addItem()` inserts `Item(timestamp: Date())` via `modelContext.insert(newItem)` (`ContentView.swift:48-53`); `deleteItems(offsets:)` removes via `modelContext.delete(items[index])` (`ContentView.swift:55-61`). Both are wrapped in `withAnimation`.
- **Connectivity**: `SingleThreadApp.swift` wires schema (`Item`) → container → environment; `ContentView.swift` consumes it via `@Query` + `@Environment(\.modelContext)`. This is the only `@Model` and only `@Query` in the app source tree.

## Q2: How does `ContentView` build its list interface?

### Findings
- **Body structure** (`SingleThread/ContentView.swift:13-41`): `body` wraps a `NavigationViewWrapper` (`ContentView.swift:14`) around a `List` (`ContentView.swift:15`).
- **Row rendering** (`ContentView.swift:16-23`): `ForEach(items) { item in ... }` renders a `NavigationLink` per item. The label (`ContentView.swift:20`) and the destination (`ContentView.swift:18`) both display the same string — `Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))`; the destination prefixes `"Item at "`. Each row shows **only the formatted timestamp** — the `Item` model has no other fields. `.onDelete(perform: deleteItems)` (`ContentView.swift:23`) enables swipe-to-delete.
- **`NavigationViewWrapper`** (`ContentView.swift:64-78`): a generic `private struct NavigationViewWrapper<Content: View>` that, on macOS (`#if os(macOS)`, `ContentView.swift:68`), renders a `NavigationSplitView` with `content()` in the sidebar and a static `Text("Select an item")` detail (`ContentView.swift:69-73`). On all other platforms it returns `content()` unchanged (`#else`, `ContentView.swift:74-76`) — no enclosing `NavigationStack`/`NavigationView` is created inside `ContentView` itself.
- **Toolbar** (`ContentView.swift:28-39`): iOS-only `EditButton()` in `.navigationBarTrailing` placement (`#if os(iOS)`, `ContentView.swift:29-33`), plus a universal plus button `Label("Add Item", systemImage: "plus")` (`ContentView.swift:34-38`).
- **macOS layout**: `.navigationSplitViewColumnWidth(min: 180, ideal: 200)` (`ContentView.swift:25-27`).

## Q3: Which platforms and deployment targets does the project support?

### Findings
- **`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`** on all three targets — iOS device/simulator, macOS, visionOS (xrOS) device/simulator. App Debug `project.pbxproj:421`, Release `:465`; test target `:491`/`:517`; UI test target `:542`/`:567`.
- **Deployment targets all `26.5`**: `IPHONEOS_DEPLOYMENT_TARGET` (app `:411`/`:455`), `MACOSX_DEPLOYMENT_TARGET` (app `:414`/`:458`), `XROS_DEPLOYMENT_TARGET` (app `:428`/`:472`); mirrored on test (`:484-498`) and UI test (`:535-549`) targets.
- **`TARGETED_DEVICE_FAMILY = "1,2,7"`** (iPhone, iPad, visionOS) — app `:427`/`:471`.
- **`SDKROOT = auto`** — app `:419`/`:463`.
- **`objectVersion = 77`** (`project.pbxproj:6`) — synchronized file groups; new `.swift` files are auto-discovered.
- **Platform conditionals in code** are all in `ContentView.swift`:
  - `#if os(macOS)` — `ContentView.swift:25`, `:68`
  - `#if os(iOS)` — `ContentView.swift:29`
  - `#else` / `#endif` — `ContentView.swift:74`, `:27`, `:33`, `:76`
  - No `#if os(...)` / `@available` / `canImport` in `Item.swift`, `SingleThreadApp.swift`, or either test target.
- **App icon gap**: `Assets.xcassets/AppIcon.appiconset/Contents.json` declares only `"platform": "ios"` (`:5`, `:13`, `:21`) and `"idiom": "mac"` (`:28`+) entries — no visionOS icon despite the multi-platform build config.

## Q4: What entitlements, Info.plist keys, and capabilities are configured?

### Findings
- **No `.entitlements` file** and **no committed `Info.plist`** exist. `GENERATE_INFOPLIST_FILE = YES` on all targets (app `project.pbxproj:400`/`:444`; tests `:483`/`:509`; UI tests `:534`/`:559`). No `CODE_SIGN_ENTITLEMENTS` setting and no `SystemCapabilities` section anywhere in the pbxproj.
- **App capabilities** (app Debug `:391-428`, Release `:435-472`):
  - `ENABLE_APP_SANDBOX = YES` — `:396`/`:440`
  - `ENABLE_HARDENED_RUNTIME = YES` — `:397`/`:441`
  - `ENABLE_USER_SELECTED_FILES = readonly` — `:399`/`:443`
  - `REGISTER_APP_GROUPS = YES` — `:418`/`:462` (toggle only; no `com.apple.security.application-groups` entitlement/group string is declared)
  - `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 6NWX2DHB9Q` — `:395`/`:439`, `:307`/`:369`
  - `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread` — `:416`/`:460`
- **Generated Info.plist keys** (`INFOPLIST_KEY_*`, `:401-410` Debug / `:445-454` Release): scene-manifest generation, indirect input events, launch-screen generation, default status-bar style, and iPhone/iPad supported orientations. No `INFOPLIST_KEY_NS*UsageDescription` keys.
- **No privacy / system-data access**: grep across the repo found zero `NS*UsageDescription` keys and zero references to Camera, Microphone, Location, Photos, Contacts, Calendar, Reminders, EventKit, HealthKit, HomeKit, Bluetooth, CoreLocation, UserNotifications, AVFoundation, PhotoKit, etc. Sources import only `SwiftData`, `SwiftUI`, `Foundation` (`SingleThreadApp.swift:7-8`, `ContentView.swift:7-8`, `Item.swift:6-7`).

## Q5: How are dates and timestamps represented, stored, and formatted?

### Findings
- **Representation/storage**: a single `Date` property `timestamp` on the `Item` `@Model` (`Item.swift:20`), persisted on disk (`isStoredInMemoryOnly: false`, `SingleThreadApp.swift:16`).
- **Creation**: `Item(timestamp: Date())` captures the wall-clock instant at insert time (`ContentView.swift:50`).
- **Formatting**: two display sites, both `Text(_:format:)` with `Date.FormatStyle(date: .numeric, time: .standard)` — detail destination (`ContentView.swift:18`) and row label (`ContentView.swift:20`). No explicit locale or time zone, so output follows device defaults.
- **Ordering**: the `@Query` has no sort descriptor (`ContentView.swift:46`), so rows are not ordered by `timestamp`.
- **Absent date/time APIs**: no `DateFormatter`, `Calendar`, `TimeInterval`, `DateComponents`, relative-date formatting, date comparison, filtering, scheduling, or time-zone/locale overrides anywhere in app sources or tests.

## Q6: How are unit tests and SwiftUI previews structured?

### Findings
- **Unit tests use Swift Testing**: `import Testing` and `struct SingleThreadTests { @Test func example() { ... } }` (`SingleThreadTests/SingleThreadTests.swift:7-15`). The single `example()` test has an empty body and does **not** instantiate a `ModelContainer`.
- **UI tests use XCTest**: `import XCTest` + `final class SingleThreadUITests: XCTestCase` (`SingleThreadUITests/SingleThreadUITests.swift:7-9`); tests `testExample` (`:22-29`) and `testLaunchPerformance` (`:32-37`) launch the full app via `XCUIApplication().launch()`. `SingleThreadUITestsLaunchTests.swift` adds a launch-screen screenshot attachment (`:22-36`). Neither UI test sets up a model container — they use the app's real `sharedModelContainer`.
- **Preview**: the sole `#Preview` provides an in-memory container — `ContentView().modelContainer(for: Item.self, inMemory: true)` (`ContentView.swift:80-83`).
- **Test invocation**: `make test` and `scripts/test.sh` run `-only-testing:SingleThreadTests` (unit only; UI tests are not run). `Makefile:8-9`, `scripts/test.sh:29-32`.

## Q7: How does the build and CI pipeline work?

### Findings
- **Makefile**: shared `SIM := platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); targets `build` (`:5-6`), `test` (`:8-9`, `-only-testing:SingleThreadTests`), `clean` (`:11-12`), `lint` (`:14-16`, swiftformat `--lint` + swiftlint `--strict`), `format` (`:18-20`, swiftformat + swiftlint `--fix`).
- **`scripts/test.sh`**: bash with `set -euo pipefail` (`:1-2`); runs formatting (`:10-12`), SwiftFormat check (`:15-16`), SwiftLint `--strict` (`:19-20`), Debug build (`:23-26`), unit tests (`:29-32`) — CI-identical sequence.
- **GitHub Actions** (`.github/workflows/ci.yml`): triggers on `push`/`pull_request` to `main` (`:3-7`). Two jobs:
  - `test` (`:10-40`): `macos-26`, `setup-xcode@v1` with `26.6`, clears `DEVELOPMENT_TEAM` via `GITHUB_ENV` (`:19-20`), caches DerivedData (`:22-26`), then Build + Unit tests (each `timeout-minutes: 20`, iOS Simulator `iPhone 17`).
  - `lint` (`:42-56`): `macos-26`, `brew install swiftlint swiftformat`, SwiftFormat check + SwiftLint `--strict`.
- **SwiftFormat** (`.swiftformat`): `--swiftversion 6.0` (`:2`), 4-space indent (`:5`); enabled `blankLinesAroundMark`, `organizeDeclarations`, `preferSwiftTesting` (`:11-13`); disabled `andOperator`, `isEmpty`, `trailingClosures`, `trailingCommas`, `wrapMultilineStatementBraces` (`:14-18`); `--exclude SingleThreadUITests` (`:21`).
- **SwiftLint** (`.swiftlint.yml`): includes all three source dirs (`:2-5`); disables XCTest-centric rules because the project uses Swift Testing (`:8-14`); thresholds `line_length` 120/150, `cyclomatic_complexity` 12/15, `type_body_length` 500/600, `file_length` 650/800 (`:16-31`); `force_cast`/`force_try` warnings (`:33-37`); opt-in rules list (`:40-52`); `identifier_name` exclusions `id, e, d, rt, to, gvm` (`:55-62`). CI runs SwiftLint with `--strict`, making every warning an error.
- **Concurrency build settings**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set on the app target (`project.pbxproj:422-423` Debug, `:466-467` Release); `SWIFT_VERSION = 6.0` (`:426`/`:470`). Test/UI-test targets set `SWIFT_VERSION = 6.0` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` but not `SWIFT_DEFAULT_ACTOR_ISOLATION` (`:492-495`, `:518-521`, `:543-546`, `:568-571`). Debug `DEBUG_INFORMATION_FORMAT = dwarf` (`:306`), Release `dwarf-with-dsym` (`:368`).

## Cross-Cutting Observations
- The app is a minimal SwiftUI + SwiftData template: one `@Model` (`Item.timestamp`), one `@Query`, one view (`ContentView`), one scene (`WindowGroup`). All persistence, UI, and date logic is concentrated in three files under `SingleThread/`.
- The `NavigationViewWrapper` abstraction is the single cross-platform shim — macOS gets a `NavigationSplitView`, everything else a bare passthrough; there is no `NavigationStack` anywhere in app code.
- iOS is the only exercised platform: `Makefile`, `scripts/test.sh`, and CI all target the `iPhone 17` iOS Simulator, despite `SUPPORTED_PLATFORMS` covering macOS and visionOS.
- The `ContentView` timestamp display is duplicated verbatim between the row label and the navigation destination (`ContentView.swift:18` vs `:20`).
- Unit testing infrastructure is a scaffold: one empty Swift Testing `example()` test and no model-container usage in tests; the `AGENTS.md`-documented convention `.modelContainer(for: Item.self, inMemory: true)` is only realized in the preview (`ContentView.swift:82`).

## Open Areas
- **App Groups**: `REGISTER_APP_GROUPS = YES` is set but no App Group identifier/entitlement is declared — the effective configuration is inert; no evidence in the codebase of how (or whether) it is meant to be used.
- **Unit-test container convention**: `AGENTS.md` says tests needing a container use `.modelContainer(for: Item.self, inMemory: true)`, but no test currently does; the intended test-container pattern is undocumented in code.
- **VisionOS specifics**: build settings and `TARGETED_DEVICE_FAMILY` include visionOS, but there is no visionOS app-icon entry (`AppIcon.appiconset/Contents.json`) and no visionOS-specific code paths — the visionOS slice's runtime behavior is not represented anywhere in code.
