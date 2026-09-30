# Implementation Plan

## Overview

Link `sentry-cocoa` (9.26.x) to the `SingleThread` target only, steer it through the pure
Sentry-free `SentryConfiguration` value type made real by a thin `SentryBootstrap` adapter, and
start it from a minimal `SingleThreadApp.init()`. Each phase is a vertical app-launch → config →
scrub → capture → disclosure/upload slice, so every phase builds and is independently demoable,
and the feature ships inert (empty DSN) until Xcode Cloud supplies the real one.

---

## Inputs the user must supply before the manual steps

These are operational, not code blockers — the code builds and tests green without them.

- **Sentry DSN** (`https://…@…ingest.us.sentry.io/…`) — for the Phase 1/2/3/6 dashboard checks.
- **`SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN`** — Xcode Cloud workflow Environment
  variables (token marked **Secret**) for the Phase 5 dSYM upload.
- **Sentry region/plan** — design assumes **US region, free Developer plan** (per-crash email
  included); revisit if that is wrong, it only changes the DSN host and dashboard.

> No user answer is required to start implementing: Phases 1–4 are all exercisable with an empty
> DSN / preference-off unit tests, and the DSN is only consumed through `Bundle.main`.

---

## Phase 1: Walking skeleton — a real crash reaches Sentry, end to end

### Pre-work: recon the resolved package (mandatory, do **not** use memory)

The exact `SentryOptions`/`Event`/`Breadcrumb` spellings must be read off the checked-out package
before writing `SentryBootstrap`/`SentryScrubber`. After the package reference is added (step 1.1)
run the build once so SPM checks out the source, then grep it:

```bash
# Source lands under the DerivedData checked-out packages dir:
find ~/Library/Developer/Xcode/DerivedData -type d -name 'sentry-cocoa-*' -maxdepth 6 | head
# Then, inside that checkout, confirm (record the exact names in a comment or commit message):
rg -n "enableAutoSessionTracking|enableCrashHandler|enableAppHangTracking" Sources
rg -n "attachScreenshot|attachViewHierarchy|enableUncaughtNSExceptionReporting" Sources
rg -n "var tracesSampleRate|var maxBreadcrumbs|var sendDefaultPii" Sources
rg -n "init\(|var message|var data|var category|var level" Sources/Sentry/SentryBreadcrumb.swift
```

If a name differs, use the resolved spelling — only the **intent** is fixed by the design.
`SentryOptions.beforeSend`/`beforeBreadcrumb` are ObjC callbacks; the `SentryScrubber` static
functions are `nonisolated` so the closure does not need `@MainActor` (Phase 2).

### Changes

#### 1.1 Add the `sentry-cocoa` remote SPM package to the project
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify (4 edits, all in the same object graph)

This is the repo's first remote package. Follow the existing `SingleThreadCore` wiring shape
exactly; only the `SingleThread` app target gets the product (the test target is added in Phase 2).

**(a)** Project `packageReferences` (currently the single local ref near the project object) —
add the remote ref:

```
			packageReferences = (
				51AA3F100000000000000001 /* XCLocalSwiftPackageReference "SingleThreadCore" */,
				51AA3F100000000000000003 /* XCRemoteSwiftPackageReference "sentry-cocoa" */,
			);
```

**(b)** New section next to `XCLocalSwiftPackageReference`:

```
/* Begin XCRemoteSwiftPackageReference section */
		51AA3F100000000000000003 /* XCRemoteSwiftPackageReference "sentry-cocoa" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/getsentry/sentry-cocoa";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 9.26.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */
```

**(c)** New product dependency in the `XCSwiftPackageProductDependency` section (the `Sentry`
product, not `SentryObjC`):

```
		51AA3F110000000000000004 /* Sentry */ = {
			isa = XCSwiftPackageProductDependency;
			package = 51AA3F100000000000000003 /* XCRemoteSwiftPackageReference "sentry-cocoa" */;
			productName = Sentry;
		};
```

**(d)** One `PBXBuildFile` in the `PBXBuildFile` section, one entry in the **SingleThread**
target's `packageProductDependencies`, and one entry in the SingleThread target's
`Frameworks` build phase (`51AA3ED3302D5C4500960DFC`):

```
		518BF49B302FCC80004C5968 /* Sentry in Frameworks */ = {isa = PBXBuildFile; productRef = 51AA3F110000000000000004 /* Sentry */; };
```

Do **not** touch `SingleThreadCore`, watch, widget, or `SingleThreadUITests`.

**Package resolution / fallback**: after the edit, `make build` resolves and checks out the
package (it has network access on this machine). SPM writes
`SingleThread.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — **commit
that file** as part of this phase. If resolution fails (offline), no code using `import Sentry`
can build; stop and report rather than vendoring the SDK by hand.

#### 1.2 Partial `Info.plist` carrying the DSN build-setting token
**File**: `SingleThread/Info.plist`
**Action**: create

`INFOPLIST_KEY_*` is an **allowlist** and silently drops custom keys, so it cannot carry
`SENTRY_DSN`. Use a real partial plist merged with the generated one (this is why the phase
adds one), matching the widget target's existing Info.plist precedent:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SENTRY_DSN</key>
	<string>$(SENTRY_DSN)</string>
</dict>
</plist>
```

`$(SENTRY_DSN)` resolves from a build setting or the process environment at build time; when
undefined it expands to the empty string, so local/CI builds stay inert. Xcode Cloud supplies it
via the workflow Environment variable (Phase 5 also patches the plist as a belt-and-braces path).

#### 1.3 pbxproj: reference the partial plist and exclude it from Resources
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

The `SingleThread` synchronized group would otherwise copy `Info.plist` as a bundle resource
(same reason the widget has an exception set). Add a new exception set object:

```
/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		51AA3ED90000000000000001 /* Exceptions for "SingleThread" folder in "SingleThread" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = 51AA3ED5302D5C4500960DFC /* SingleThread */;
		};
		51AA3F4E0000000000000000 /* Exceptions for "SingleThreadWidget" folder … */ = { … unchanged … };
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */
```

Add the `exceptions = ( … )` list to the `51AA3ED8302D5C4500960DFC /* SingleThread */` root group.

Then add `INFOPLIST_FILE = SingleThread/Info.plist;` beside `GENERATE_INFOPLIST_FILE = YES;` in
the **two** SingleThread app-target configurations (the Debug block ending `name = Debug;` and the
Release block ending `name = Release;` — the two blocks that contain
`TARGETED_DEVICE_FAMILY = "1,2"`).

#### 1.4 `SentryConfiguration` — the pure, Sentry-free value type
**File**: `SingleThread/SentryConfiguration.swift`
**Action**: create

```swift
import Foundation

/// Pure description of the crash-reporting configuration. Imports no Sentry so it
/// stays unit-testable; `SentryBootstrap` maps it to `SentryOptions`.
struct SentryConfiguration: Equatable, Sendable {
    let dsn: String
    let environment: String
    let maxBreadcrumbs: Int
    let sendDefaultPii: Bool
    let tracesSampleRate: Double

    /// `nil` when the DSN is missing/blank, which means "never call `SentrySDK.start`".
    static func make(dsn: String?, environment: String) -> SentryConfiguration? {
        guard let trimmed = dsn?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return SentryConfiguration(
            dsn: trimmed,
            environment: environment,
            maxBreadcrumbs: 20,
            sendDefaultPii: false,
            tracesSampleRate: 0)
    }

    /// Build-config-derived environment tag; unit tests assert the Debug branch.
    static var currentEnvironment: String {
        #if DEBUG
        return "debug"
        #else
        return "production"
        #endif
    }
}
```

#### 1.5 `SentryBootstrap` — the only SDK entry point
**File**: `SingleThread/SentryBootstrap.swift`
**Action**: create

```swift
import Foundation
import Sentry

/// Thin adapter from `SentryConfiguration` to `SentrySDK`. The only file besides
/// `SentryScrubber` that imports Sentry (Phase 2 adds the scrubber hooks).
enum SentryBootstrap {
    static func startIfEnabled() {
        guard CrashReportingPreference().isEnabled, // Phase 3 adds this gate
              let configuration = SentryConfiguration.make(
                  dsn: bundleDSN,
                  environment: SentryConfiguration.currentEnvironment) else {
            return
        }
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.maxBreadcrumbs = configuration.maxBreadcrumbs
            options.sendDefaultPii = configuration.sendDefaultPii
            options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableAutoSessionTracking = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            startIfEnabled()
        } else {
            SentrySDK.close()
        }
    }

    private static var bundleDSN: String? {
        Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String
    }
}
```

> In Phase 1 omit the `CrashReportingPreference` gate (it does not exist yet) and only add
> `beforeSend`/`beforeBreadcrumb` in Phase 2. `NSNumber(value:)` is the likely import shape;
> confirm the exact property types in recon (1 pre-work). `#if os(macOS)
> options.enableUncaughtNSExceptionReporting = true #endif` lands in Phase 6.

#### 1.6 Start the SDK at launch
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Add an explicit init that starts Sentry **before** the composition root is built, and make the
`@State` view model explicit so ordering is guaranteed (a default property initializer would run
before the init body):

```swift
init() {
    SentryBootstrap.startIfEnabled()
    _viewModel = State(initialValue: AppViewModel())
}
```

and change the property declaration to `@State private var viewModel: AppViewModel`. All other
`SingleThreadApp` members/body are unchanged. This is the earliest main-thread point and is
identical on iOS and macOS.

#### 1.7 `SentryConfigurationTests`
**File**: `SingleThreadTests/SentryConfigurationTests.swift`
**Action**: create

```swift
import Foundation
@testable import SingleThread
import Testing

struct SentryConfigurationTests {
    @Test
    func dsnIsTrimmedAndKept() {
        let config = SentryConfiguration.make(dsn: "  https://a@b.ingest.sentry.io/1  ", environment: "debug")
        #expect(config?.dsn == "https://a@b.ingest.sentry.io/1")
    }

    @Test
    func emptyDsnYieldsNil() {
        #expect(SentryConfiguration.make(dsn: nil, environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "", environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "   \n", environment: "debug") == nil)
    }

    @Test
    func privacyDefaultsAreSafe() {
        let config = SentryConfiguration.make(dsn: "https://a@b.ingest.sentry.io/1", environment: "production")
        #expect(config?.sendDefaultPii == false)
        #expect(config?.tracesSampleRate == 0)
        #expect((config?.maxBreadcrumbs ?? 0) > 0 && (config?.maxBreadcrumbs ?? .max) <= 50)
    }

    @Test
    func environmentMapsDebugBuild() {
        #if DEBUG
        #expect(SentryConfiguration.currentEnvironment == "debug")
        #else
        #expect(SentryConfiguration.currentEnvironment == "production")
        #endif
    }
}
```

Test names do **not** start with `test` (SwiftFormat strips that prefix).

### Verification

#### Automated
- [x] `make format` then `make lint` clean after the new files land
- [x] `SENTRY_DSN='https://<key>@<org>.ingest.us.sentry.io/<id>' make build` succeeds and resolves `sentry-cocoa` (`Package.resolved` written)
- [x] `scripts/test-one.sh SingleThreadTests/SentryConfigurationTests` passes (exit 0, cases matched)
- [x] `PlistBuddy -c 'Print :SENTRY_DSN' "$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/SingleThread.app/Info.plist' | head -1)"` prints the injected DSN (and the `build` without `SENTRY_DSN` prints an empty string)

#### Manual
- [ ] `SENTRY_DSN='…' make build`, boot the `iPhone 17` sim from `.simulator_id`, install/launch
- [ ] Temporarily add a throw-away button/`fatalError` behind a debug flag, trigger it, relaunch the app, and confirm a new event appears in the Sentry Issues dashboard with `environment=debug` and no user identity

---

## Phase 2: Privacy scrubber — no reminder content can leave the device

### Changes

#### 2.1 `SentryScrubber`
**File**: `SingleThread/SentryScrubber.swift`
**Action**: create

```swift
import Foundation
import Sentry

/// Allow-list scrubber applied to every event and breadcrumb before send.
/// Returns `nil` to drop a breadcrumb when its payload is not allow-listed.
enum SentryScrubber {
    /// Tag keys that carry app/device metadata only — never reminder content.
    static let allowedTags: Set<String> = ["environment", "release", "level"]

    nonisolated static func scrub(_ event: Event) -> Event? {
        event.user = nil
        event.extra = nil
        event.request = nil
        event.modules = nil
        event.tags = event.tags?.filter { allowedTags.contains($0.key) }
        event.breadcrumbs = event.breadcrumbs?.compactMap(scrub)
        return event
    }

    /// Keeps category/level/timestamp, drops the free-text message and data bag.
    nonisolated static func scrub(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        breadcrumb.message = nil
        breadcrumb.data = nil
        return breadcrumb
    }
}
```

Confirm `Event.extra`, `Event.modules`, `Event.request`, `Event.tags`, `Event.breadcrumbs`,
`Breadcrumb.message`, `Breadcrumb.data` are mutable optionals in the recon step; adapt if any are
non-optional or named differently.

#### 2.2 Wire the scrubber into `SentryBootstrap`
**File**: `SingleThread/SentryBootstrap.swift`
**Action**: modify

Inside the `SentrySDK.start { options in … }` closure add:

```swift
            options.beforeSend = { SentryScrubber.scrub($0) }
            options.beforeBreadcrumb = { SentryScrubber.scrub($0) }
```

#### 2.3 Link `Sentry` to the test target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Add the product to `SingleThreadTests` exactly as in 1.1(d): a `PBXBuildFile`
(`518BF49C302FCC80004C5968 /* Sentry in Frameworks */`), an entry in the tests target's
`packageProductDependencies` (`51AA3EE4302D5C4500960DFC`, currently containing only
`SingleThreadCore`), and an entry in the tests `Frameworks` phase (`51AA3EE2302D5C4500960DFC`).
This is required only because `SentryScrubberTests` constructs `Event`/`Breadcrumb`; the app
target still owns the feature.

#### 2.4 `SentryScrubberTests`
**File**: `SingleThreadTests/SentryScrubberTests.swift`
**Action**: create

```swift
import Foundation
import Sentry
@testable import SingleThread
import Testing

struct SentryScrubberTests {
    @Test
    func reminderContentIsRemovedFromEvent() {
        let event = Event()
        event.extra = ["reminderTitle": "Buy milk", "note": "2%"]
        event.user = SentryUser(userId: "Buy milk")
        event.tags = ["reminderTitle": "Buy milk", "environment": "debug"]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
        #expect(scrubbed?.tags?["reminderTitle"] == nil)
        #expect(scrubbed?.tags?["environment"] == "debug") // allow-listed field survives
    }

    @Test
    func reminderContentIsRemovedFromBreadcrumb() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")
        breadcrumb.message = "Buy milk from the Grocery list"
        breadcrumb.data = ["note": "2%", "listName": "Grocery"]

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.data == nil)
        #expect(scrubbed?.category == "reminder") // benign structural field survives
    }
}
```

Confirm `Event()`, `SentryUser(userId:)`, `Breadcrumb(level:category:)` initializers in recon.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/SentryConfigurationTests` still passes
- [x] `make lint` clean (the `nonisolated` statics must not introduce Swift 6 warnings)

#### Manual
- [ ] Repeat the Phase 1 deliberate crash with `SENTRY_DSN` set; in the dashboard event confirm the stack/symbols are present and **no** reminder title/note/list name appears in `extra`, `user`, or breadcrumbs

---

## Phase 3: Consent toggle — the user can turn crash reporting off and back on

### Changes

#### 3.1 `CrashReportingPreference` (SingleThreadCore)
**File**: `SingleThreadCore/Sources/SingleThreadCore/CrashReportingPreference.swift`
**Action**: create

Mirrors `OrientationPreference`. Uses `UserDefaults.standard` (device-local, **not** App-Group
synced) and no Sentry import (SingleThreadCore is linked by watch/widget, which must stay clean).

```swift
import Foundation

/// Persists the crash-reporting consent flag in `UserDefaults.standard`.
///
/// Device-local by design: the watch and widget must not acquire the crash
/// reporter, so this key is deliberately *not* in the App Group and is not
/// synced over WatchConnectivity. An absent key resolves to `true` (reporting
/// enabled by default).
public struct CrashReportingPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public static let defaultsKey = "crashReportingEnabled"

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 3.2 `SentryBootstrap` consults the preference
**File**: `SingleThread/SentryBootstrap.swift`
**Action**: modify

`startIfEnabled()` already guards on `CrashReportingPreference().isEnabled` in the Phase 1
snippet; if Phase 1 omitted it, add the guard now. `setEnabled(_:)` already exists from Phase 1.

#### 3.3 `SettingsBindings` — store-backed consent property
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add an injectable preference parameter (defaulted, so existing call sites are unchanged):

```swift
    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        allowsLandscape: Bool = true,
        enableActionButtons: Bool = true,
        showSwipePrompt: Bool = true,
        showUndoButton: Bool = true,
        notificationsEnabled: Bool = false,
        notificationIntervalHours: Int = 48,
        showMicrophoneButton: Bool = true,
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = 50,
        backgroundPinned: Bool = false,
        showMenuBarExtra: Bool = true,
        crashReportingPreference: CrashReportingPreference = CrashReportingPreference()) {
        …
        self.crashReportingPreference = crashReportingPreference
    }
```

Add the computed, observable property next to the other App-Group/store-backed ones:

```swift
    var crashReportingEnabled: Bool {
        get {
            access(keyPath: \.crashReportingEnabled)
            return crashReportingPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.crashReportingEnabled) {
                crashReportingPreference.setEnabled(newValue)
                SentryBootstrap.setEnabled(newValue)
            }
        }
    }
```

and the private stored `private let crashReportingPreference: CrashReportingPreference`.

#### 3.4 `SettingsView` — the toggle
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

In the second `Section` (the one holding Privacy Policy / About), insert above the Privacy link:

```swift
                    Toggle(isOn: $bindings.crashReportingEnabled) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Share crash reports")
                                SettingsCaption(text: "Send crash and diagnostic data to help fix bugs.")
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .accessibilityIdentifier("crashReportingToggle")
```

(`SettingsCaption` takes a `LocalizedStringKey` literal and `Text` literal keys auto-localize.)

#### 3.5 New localization keys (all six languages)
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Add two keys, each with `"extractionState": "manual"` and all six languages — the
`LocalizationTests.catalogsHaveAllSixLanguages` and `nonEnglishValuesDifferFromEnglish` tests
fail otherwise (App catalog is guarded). Suggested values:

| Key | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|
| `Share crash reports` | 共享崩溃报告 | Compartir informes de fallos | クラッシュレポートを共有 | Absturzberichte teilen | Partager les rapports d'erreur |
| `Send crash and diagnostic data to help fix bugs.` | 发送崩溃和诊断数据，以帮助修复问题。 | Envía datos de fallos y diagnósticos para ayudar a corregir errores. | 問題の修正に役立てるため、クラッシュおよび診断データを送信します。 | Sende Absturz- und Diagnosedaten, um Fehler zu beheben. | Envoyez des données de plantage et de diagnostic pour aider à corriger les bugs. |

Use the `edit` tool with small unique anchors; do not paste whole catalog entries.

#### 3.6 `CrashReportingPreferenceTests`
**File**: `SingleThreadTests/CrashReportingPreferenceTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

struct CrashReportingPreferenceTests {
    @Test
    func absentKeyDefaultsToEnabled() throws {
        let defaults = try #require(UserDefaults(suiteName: "CrashReportingPreferenceTests.absent"))
        defaults.removePersistentDomain(forName: "CrashReportingPreferenceTests.absent")
        #expect(CrashReportingPreference(defaults: defaults).isEnabled)
    }

    @Test
    func toggleRoundTripsThroughInjectedDefaults() throws {
        let suite = "CrashReportingPreferenceTests.roundTrip"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preference = CrashReportingPreference(defaults: defaults)

        preference.setEnabled(false)
        #expect(!preference.isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == false)

        preference.setEnabled(true)
        #expect(preference.isEnabled)
    }
}
```

#### 3.7 `SettingsViewTests` addition
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add a focused test that the binding persists through the injected preference and that the toggle
copy is present in the view body:

```swift
    @Test
    func settingsBindingsCarriesCrashReporting() throws {
        let suite = "SettingsViewTests.crashReporting"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let bag = SettingsBindings(
            crashReportingPreference: CrashReportingPreference(defaults: defaults))

        #expect(bag.crashReportingEnabled) // default on
        bag.crashReportingEnabled = false
        #expect(!bag.crashReportingEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == false)
    }
```

and extend `settingsViewContainsNavigationLinkLabels`'s caption/label lists (or add a new
`settingsViewContainsCrashReportingToggle`) asserting `String(describing: view.body)` contains
`"Share crash reports"` and `"Send crash and diagnostic data to help fix bugs."`.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/CrashReportingPreferenceTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (proves the two new keys have six languages and differ from English)
- [x] `make lint` clean

#### Manual
- [ ] Launch a `SENTRY_DSN`-bearing build; Settings → toggle **off**; trigger the deliberate crash; relaunch → **no** new event
- [ ] Toggling **on** and repeating produces an event again (restart path works)
- [ ] Toggle remains off/on after an app relaunch (persistence)

---

## Phase 4: Truthful disclosures — manifest, in-app copy, App Store label

### Changes

#### 4.1 `PrivacyInfo.xcprivacy`
**File**: `SingleThread/PrivacyInfo.xcprivacy`
**Action**: create

The app target declares its own manifest **and** aggregates Sentry's static-link reason codes
(sentry-cocoa's own manifest is absent from SPM distributions — issue #3853).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCrashData</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
				<string>1C8F.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>35F9.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

If the synchronized group does **not** pick it up as a resource (verify in 4.4), add it to the
SingleThread target's Resources build phase and note the pbxproj addition here.

#### 4.2 `PrivacyGuideContent` — 5th section and reworded background copy
**File**: `SingleThread/PrivacySettingsContent.swift`
**Action**: modify

- Add `crashReports` as the 5th section (stable id `"crashReports"`), after `background`:
  title `"Crash Reports"`, body `"When crash reporting is enabled, SingleThread sends crash and diagnostic information to Sentry, our crash-reporting provider. This data is processed in the United States and never includes any reminder, preference, or list content. You can turn crash reporting off at any time in Settings."`
- Reword the `background` body to drop the "only network request" absolute:
  `"When the background is enabled, the background url and artist information is downloaded from a proxy at vardy.cc. This request never includes any reminder, preference, or list data. This proxy is used to store an API key for Unsplash and keep API usage reasonable."`
- Keep the `reminders` body's "never sent to the author or any third party" and `closingLine` unchanged.
- Update the file's doc comment (it says the copy hardcodes the data flows) to include Sentry crash reporting as a fourth flow.
- Update `sections(in:)`'s doc comment "four disclosure sections" → "five".

#### 4.3 xcstrings: swap the `background` key, add the `crashReports` keys
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

The English sentence is the key, so the background key changes. **Replace** the old
"When the background is enabled …" key (its en value and all 5 translations) with the new key and
values; then add the two new keys. Suggested values:

`When the background is enabled, the background url and artist information is downloaded from a proxy at vardy.cc. This request never includes any reminder, preference, or list data. This proxy is used to store an API key for Unsplash and keep API usage reasonable.`

| Language | Value |
|---|---|
| zh-Hans | 启用背景后，背景图片网址和摄影师信息会从 vardy.cc 的代理服务器下载。该请求绝不会包含任何提醒、偏好或列表数据。该代理用于存储 Unsplash 的 API 密钥并合理控制 API 使用量。 |
| es | Cuando el fondo está activado, la URL del fondo y la información del artista se descargan de un proxy en vardy.cc. La solicitud nunca incluye datos de recordatorios, preferencias ni listas. Este proxy se utiliza para almacenar una clave de API de Unsplash y mantener un uso razonable de la API. |
| ja | 背景を有効にすると、背景画像の URL とアーティスト情報が vardy.cc のプロキシからダウンロードされます。このリクエストにリマインダー、設定、リストのデータが含まれることはありません。このプロキシは Unsplash の API キーを保管し、API の利用量を適切に保つために使用されます。 |
| de | Wenn der Hintergrund aktiviert ist, werden die Hintergrund-URL und Künstlerinformationen von einem Proxy auf vardy.cc heruntergeladen. Die Anfrage enthält niemals Erinnerungs-, Einstellungs- oder Listendaten. Der Proxy speichert einen API-Schlüssel für Unsplash und hält die API-Nutzung im Rahmen. |
| fr | Lorsque l'arrière-plan est activé, l'URL de l'image et les informations sur l'artiste sont téléchargées depuis un proxy sur vardy.cc. La requête ne contient jamais de données de rappels, de préférences ou de listes. Ce proxy sert à stocker une clé API pour Unsplash et à maintenir une utilisation raisonnable de l'API. |

`Crash Reports` (title):

| Language | Value |
|---|---|
| zh-Hans | 崩溃报告 |
| es | Informes de fallos |
| ja | クラッシュレポート |
| de | Absturzberichte |
| fr | Rapports d'erreur |

`When crash reporting is enabled, SingleThread sends crash and diagnostic information to Sentry, our crash-reporting provider. This data is processed in the United States and never includes any reminder, preference, or list content. You can turn crash reporting off at any time in Settings.`

| Language | Value |
|---|---|
| zh-Hans | 启用崩溃报告后，SingleThread 会将崩溃和诊断信息发送给我们的崩溃报告服务提供商 Sentry。这些数据在美国处理，绝不会包含任何提醒、偏好或列表内容。您可以随时在“设置”中关闭崩溃报告。 |
| es | Cuando los informes de fallos están activados, SingleThread envía información de fallos y diagnósticos a Sentry, nuestro proveedor de informes de fallos. Estos datos se procesan en Estados Unidos y nunca incluyen contenido de recordatorios, preferencias ni listas. Puedes desactivar los informes de fallos en cualquier momento en Ajustes. |
| ja | クラッシュレポートが有効な場合、SingleThread はクラッシュおよび診断情報をクラッシュレポート提供元の Sentry に送信します。このデータは米国で処理され、リマインダー、設定、リストの内容が含まれることはありません。クラッシュレポートは設定でいつでもオフにできます。 |
| de | Wenn Absturzberichte aktiviert sind, sendet SingleThread Absturz- und Diagnoseinformationen an Sentry, unseren Anbieter für Absturzberichte. Diese Daten werden in den Vereinigten Staaten verarbeitet und enthalten niemals Inhalte von Erinnerungen, Einstellungen oder Listen. Du kannst Absturzberichte jederzeit in den Einstellungen deaktivieren. |
| fr | Lorsque les rapports d'erreur sont activés, SingleThread envoie des informations de plantage et de diagnostic à Sentry, notre fournisseur de rapports d'erreur. Ces données sont traitées aux États-Unis et ne contiennent jamais de contenu de rappels, de préférences ou de listes. Vous pouvez désactiver les rapports d'erreur à tout moment dans les Réglages. |

#### 4.4 `PrivacySettingsContentTests` updates
**File**: `SingleThreadTests/PrivacySettingsContentTests.swift`
**Action**: modify

- `privacyGuideContentCoversAllDisclosures`: `sections.count == 4` → `== 5`; add
  `#expect(sections.contains { $0.id == "crashReports" })` and
  `#expect(sections.first { $0.id == "crashReports" }?.body.contains("Sentry") == true)`.
- `privacyGuideContentResolvesInEveryInterfaceLanguage`: `== 4` → `== 5`.
- Keep the `vardy.cc` literal check, the closing-line checks, and the non-English-differs check
  (now also covering the new keys automatically via the index-based loop).

#### 4.5 App Store Connect label (dashboard, not code)
**Action**: manual

Set App Privacy → Data Types → **Diagnostics → Crash Data**, *not linked to identity*, *not used
for tracking*, purpose **App Functionality**. Record the change in the PR description.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/PrivacySettingsContentTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (new/replaced keys all six languages, non-English differs)
- [x] `make lint` clean

#### Manual
- [ ] Debug archive (`Product > Archive`, or `xcodebuild archive`) and confirm the built app contains the manifest:
      `find <archive>/Products/Applications/SingleThread.app -name 'PrivacyInfo.xcprivacy'`
- [ ] Open the archive in Xcode Organizer → **Generate Privacy Report** (or inspect the merged report) and confirm Crash Data + the four reason codes appear, proving SPM/static linking merged it
- [ ] In-app Privacy screen shows 5 sections and the background section no longer claims "only network request"

---

## Phase 5: Symbolicated per-crash alert — dSYM upload + triage docs

### Changes

#### 5.1 `ci_scripts/ci_post_clone.sh`
**File**: `ci_scripts/ci_post_clone.sh`
**Action**: create, `chmod +x`

```sh
#!/bin/sh
set -eu

# sentry-cli powers the dSYM upload in ci_post_xcodebuild.sh.
if ! command -v sentry-cli >/dev/null 2>&1; then
    brew install getsentry/tools/sentry-cli
fi

# Bake the release DSN into the app's Info.plist from the Xcode Cloud
# Environment variable. Left untouched locally, where $(SENTRY_DSN) expands
# to an empty string and the feature stays inert.
if [ -n "${SENTRY_DSN:-}" ]; then
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    /usr/libexec/PlistBuddy -c "Set :SENTRY_DSN $SENTRY_DSN" SingleThread/Info.plist
fi
```

#### 5.2 `ci_scripts/ci_post_xcodebuild.sh`
**File**: `ci_scripts/ci_post_xcodebuild.sh`
**Action**: create, `chmod +x`

```sh
#!/bin/sh
set -eu

# dSYMs only exist for archive actions.
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
    exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "sentry-cli: SENTRY_* upload credentials not set; skipping dSYM upload."
    exit 0
fi

sentry-cli debug-files upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$CI_ARCHIVE_PATH"
```

Both scripts must keep the executable bit (`chmod +x`) — Xcode Cloud requires a shebang + `+x`.

#### 5.3 `docs/CrashReporting.md`
**File**: `docs/CrashReporting.md`
**Action**: create

Document, at minimum:

- **Sentry org setup**: US data region, free Developer plan; the DSN lives only in the Xcode
  Cloud workflow Environment as `SENTRY_DSN` (non-secret) and is baked into Info.plist at build.
- **Xcode Cloud Environment**: `SENTRY_DSN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN`
  (Secret). No credential is committed.
- **Alert rule**: Sentry → Alerts → create an issue alert "email me on every new crash" (all
  events, no filters or severity threshold), recipient = the author's email. Note it is dashboard
  config, not gate-testable.
- **Triage steps**: open Issues → confirm the crash is symbolicated (dSYM UUID matches the
  shipped build), read the stack, file/fix in Linear, mark Resolved.
- **dSYM upload**: which script uploads, that a late upload needs event reprocessing, and that
  Debug builds use `dwarf` so only Release/Xcode Cloud crashes symbolicate.

### Verification

#### Automated
- [x] `bash -n ci_scripts/ci_post_clone.sh ci_scripts/ci_post_xcodebuild.sh` exits 0
- [x] `test -x ci_scripts/ci_post_clone.sh && test -x ci_scripts/ci_post_xcodebuild.sh`
- [x] `shellcheck ci_scripts/*.sh` (if installed) reports nothing fatal

#### Manual (cannot be exercised by the gate)
- [ ] Push to a branch that triggers an Xcode Cloud archive; confirm the build log shows the
      dSYM upload succeeding and Sentry → Settings → Debug Files lists the new dSYMs
- [ ] Install the Release build, trigger a deliberate crash, confirm the crash email arrives and
      the stack is symbolicated in the dashboard

---

## Phase 6: Hardening — sad paths, both platforms, toolchain noise

### Changes

#### 6.1 `SentryBootstrap` macOS exception reporting + robustness
**File**: `SingleThread/SentryBootstrap.swift`
**Action**: modify

Inside the `SentrySDK.start` closure, add (macOS only, confirmed present in recon):

```swift
            #if os(macOS)
            options.enableUncaughtNSExceptionReporting = true
            #endif
```

Re-check the toggle cycle: `setEnabled(false)` on a never-started SDK must call
`SentrySDK.close()` safely, and `setEnabled(true)` after `close()` must re-`start`.

#### 6.2 Sad-path tests
**Files**: `SingleThreadTests/SentryConfigurationTests.swift`,
`SingleThreadTests/CrashReportingPreferenceTests.swift`,
`SingleThreadTests/SentryScrubberTests.swift`
**Action**: modify

Add, at minimum:

- `SentryConfigurationTests.emptyDsnIsNeverStarted` — whitespace-only and missing DSN both yield
  `nil` (already partly covered; add the `"\n\t"` and non-String Info.plist value cases if easy).
- `CrashReportingPreferenceTests.offOnOffCycle` — disable → enable → disable, asserting
  `isEnabled` each time and that the persisted value tracks it.
- `SentryScrubberTests.eventWithoutTagsStaysClean` — an event with no tags/breadcrumbs scrubs to
  a non-nil event with nil extras (proves no crash on the empty sad path).
- `SentryScrubberTests.breadcrumbWithoutDataSurvives` — a breadcrumb with only
  category/level/timestamp returns non-nil.

#### 6.3 Toolchain triage
**Files**: `scripts/xcodebuild-warnings.allow` (only if required)
**Action**: modify only if a genuine toolchain/SDK diagnostic appears

- Run `make lint`, `make periphery`, and the three targeted suites.
- Periphery will likely flag SDK-internal symbols from `sentry-cocoa`; per the `periphery` skill,
  SDK-side findings are expected and are **not** fixed or ignored ad hoc. If an app-side symbol is
  genuinely unused, remove it.
- If `xcodebuild` emits a source-located warning, fix it. Only a truly unfixable
  toolchain/SDK warning gets one line in `scripts/xcodebuild-warnings.allow` with a rationale.
- If the local Xcode 27 Periphery result disagrees with CI's 26.6, treat CI as authority (see the
  `periphery` skill); clean `DerivedData/` and rerun before concluding.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/SentryConfigurationTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/CrashReportingPreferenceTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes
- [x] `make lint` clean
- [x] `make periphery` reviewed; any app-side finding resolved, SDK-side documented
- [ ] Full `./scripts/test.sh` run **once** via the `run-gate` skill (managed worktree) — not `nohup`, not re-run per phase

#### Manual
- [ ] Trigger the deliberate crash on **iOS simulator** and on **macOS** (`make mac-build` + run);
      confirm both produce scrubbed, symbolicated-on-Release events
- [ ] On macOS, trigger an uncaught `NSException` and confirm it is captured
- [ ] Toggle off before a crash on both platforms and confirm suppression

---

## Testing checkpoints

- After Phase 1: `SentryConfigurationTests` green + one dashboard event → proceed.
- After Phase 2: `SentryScrubberTests` green + no reminder text in the dashboard event → proceed.
- After Phase 3: `CrashReportingPreferenceTests` + `SettingsViewTests` + `LocalizationTests` green
  + toggle-off suppresses capture → proceed.
- After Phase 4: `PrivacySettingsContentTests` + `LocalizationTests` green + Privacy Report shows
  the manifest → proceed.
- After Phase 5: `bash -n` clean + symbolicated Release crash and alert email confirmed → proceed.
- After Phase 6: `make lint`, `make periphery`, targeted suites green → run the full
  `./scripts/test.sh` gate once via `run-gate`.

## Notes / deviations from `structure.md` (and why)

1. **Real partial `Info.plist` instead of `INFOPLIST_KEY_SENTRY_DSN`.** Apple's
   `INFOPLIST_KEY_*` settings are an allowlist; a custom key is silently dropped at build time.
   The plan uses the widget target's existing `Info.plist` + synchronized-group-exception
   precedent, which is the only reliable way to get `SENTRY_DSN` into the bundle.
2. **`ci_post_clone.sh` also patches `Info.plist`** (a one-line `PlistBuddy` guarded on
   `SENTRY_DSN`) in addition to the `$(SENTRY_DSN)` build-setting token, because custom Xcode
   Cloud env vars are not reliably layered into build settings. Both paths write the same key.
3. **`SingleThreadApp.init()` uses `_viewModel = State(initialValue:)`** rather than relying on
   the `@State` default initializer, so `SentryBootstrap.startIfEnabled()` genuinely runs before
   the composition root (a default property initializer runs first).
4. **Phase 3 touches `Localizable.xcstrings`** (new toggle title/caption) and Phase 4 rewrites the
   background body key — both are required by the guarded `LocalizationTests`, even though
   `structure.md` only listed the catalog under Phase 4.
5. **`SentryConfiguration.currentEnvironment` is a static on the pure type** (not in
   `SentryBootstrap`) so the debug/release mapping is unit-testable without importing Sentry.
6. **`singleThreadApp.init()` / scrubber / bootstrap** remain the only app-side Sentry entry
   points; no manual `capture` calls were added (design scope).
