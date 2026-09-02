# Q6 Findings — In-App Purchases configuration & archiving/distribution (what EXISTS)

Repo: /Users/vardy/dev/alanvardy-var-721-testflight-macos (worktree HEAD c7a86c2 "chore: questions")
All refs are working-tree files unless marked "git history".

## 1. Products.storekit — the StoreKit configuration file

`SingleThread/Products.storekit` (whole file, JSON):
- :2 — config `"identifier": "05D6F4BA"`.
- :4-22 — exactly one product:
  - :5 `"displayName": "Unlock"`; :6 `"family": "app.alanvardy.SingleThread.unlimited"`; :7 `"type": "nonConsumable"`; :8 `"subscriptionGroupID": ""`; :9 `"hostBundleID": "app.alanvardy.SingleThread"`; :10 `"referenceName": "Unlock"`; :11-13 price entry `["USD", 2.99]`; :14 `"id": "app.alanvardy.SingleThread.unlimited"`.
  - :3/:16-21 — empty arrays: `nonRenewingSubscriptions`, `consumableProducts`, `autoRenewableSubscriptions`, `subscriptionGroups`.
  - No description field and no per-locale localization entries in the file.

How the file is wired (no pbxproj reference):
- The project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77; `SingleThread.xcodeproj/project.pbxproj:3-4,110-112`), and target `SingleThread` has `fileSystemSynchronizedGroups = (SingleThread)` (`project.pbxproj:276-280`). `Products.storekit` therefore has NO `PBXFileReference`/`PBXBuildFile` entry (grep of pbxproj for `Products.storekit` = 0 hits) — Xcode's synchronized-folder mechanism picks it up and it lands in the app bundle.
- Scheme wiring: `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme:88-92` — `<LaunchAction buildConfiguration="Debug">` contains `<StoreKitConfigurationFileReference identifier="../SingleThread/Products.storekit">`. The watch scheme `SingleThreadWatch.xcscheme` has zero StoreKitConfigurationFileReference occurrences.

## 2. EntitlementStore (purchase flow; storefront/currency handling)

`SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift` (full read):
- :9-10 — `@MainActor @Observable public final class EntitlementStore`.
- :42 — `public static let unlockProductID = "app.alanvardy.SingleThread.unlimited"` (single source of truth; also `AGENTS.md:62-68`).
- :48 — `public private(set) var isEntitled: Bool = false` — in-memory only, NOT UserDefaults-backed.
- :20-28 — `init()` spawns `Task { refreshEntitlement(); observeTransactionUpdates() }`.
- :34-38 — `init(testingWithEntitled:)` seam — sets `isEntitled` directly, no observation loop (used by the `--seed` UI-test wiring and unit tests).
- :53-60 — `sync()` calls `AppStore.sync()`, then `refreshEntitlement()`; logger `Logger(subsystem: "app.alanvardy.SingleThread", category: "EntitlementStore")` (:64-66).
- :79-87 — `observeTransactionUpdates()`: `for await verificationResult in Transaction.updates`; `case .verified` → `transaction.finish()` → `refreshEntitlement()`.
- :90-99 — `refreshEntitlement()`: iterates `Transaction.currentEntitlements`, `isEntitled = true` only when `transaction.productID == Self.unlockProductID` (:95-97).
- No explicit storefront/currency code — price display lives in the view layer via `Product.displayPrice`.

Purchase UI and call sites:
- `SingleThread/PurchaseSettingsView.swift:71` — `private static let unlockProductID = EntitlementStore.unlockProductID`.
- :137-147 — `loadProduct()`: `Product.products(for: [Self.unlockProductID])`, first match, error/empty states.
- :150-168 — `purchase(_:)`: `product.purchase()`; on `.success` → `await entitlementStore.sync()` (:158-159); `.userCancelled`/.pending/unknown → no-op.
- :59-70 — `Restore Purchases` (id `restorePurchasesButton`) → `entitlementStore.sync()`; shown only when not entitled.
- :202-216 — `PurchaseSheet` wrapper; `SingleThread/ContentView.swift:249` presents `PurchaseSheet`, :500 `UpgradePromptButton` (freemium gate prompt); `SingleThread/SettingsView.swift:100,154` also hosts `PurchaseSettingsView`.
- `SingleThread/AppViewModel.swift:299-300` — `--seed` UI-test seam picks `EntitlementStore(testingWithEntitled: true/false)`.
- Watch: NO StoreKit surface — `SingleThreadWatch/WatchReminderView.swift:134` comment `itself has no StoreKit surface, so the user upgrades on the iPhone`. Entitlement arrives over WatchConnectivity: `SingleThreadWatch/WatchAppViewModel.swift:162` (local `EntitlementStore()`, `sendsEntitled: false`), :228 `onEntitlementReceived` → `EntitlementState`; `SingleThreadCore/Sources/SingleThreadCore/EntitlementState.swift:3-11` is a plain in-memory `@Observable` holder (no StoreKit). `SkippedReminderSyncService.swift:126-130` (`onEntitlementReceived`), :194-199 (main-actor read of `entitlementStore.isEntitled`), :281 (`static let entitled = "isEntitled"` payload key).

Freemium 100-completion counter (UserDefaults-backed):
- `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift:11-13` — defaults `AppGroup.defaults`, key `"completionCount"`; :19 `count` = `UserDefaults.integer(forKey:)` (0-default); :23-25 `increment()`; :29-32 `decrement()` (clamped >= 0, undo only); :36-38 `resetForTesting()` (test-only).
- Gate: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:144-145` — `canMutate = entitlementStore.isEntitled || completionCounter.count < 100`. `canMutate` guards at :182 (complete), :231 (undo), :256, :308, :339 (skip/delete/etc.). Counter increments once per successful non-watchOS EventKit save at :206; decrements on undo at :237. UI-test path seeds the literal key `"completionCount"` in `SingleThread/AppViewModel.swift:293-296`.

## 3. StoreKitTest usage in tests

`SingleThreadTests/EntitlementStoreTests.swift` (full read):
- :2 — `import StoreKitTest`; :8 — `@MainActor @Suite(.serialized) struct EntitlementStoreTests`.
- :12-16 — `isEntitledIsFalseByDefault`; :19-25 — `seamSetsEntitlement` (testing seam only).
- :27-47 — `isEntitledSurvivesStoreRecreation`: `SKTestSession(configurationFileNamed: "Products")` (:28), `session.disableDialogs = true` (:29), then seam store + fresh `EntitlementStore()` with `Task.sleep(200ms)` (:41-42). Comment (:31-37): `SKTestSession.buyProduct` cannot complete via `xcodebuild test` on this toolchain (Xcode 26.6, Apple FB22237318), so purchase-path coverage uses the `testingWithEntitled:` seam; SKTestSession retained for session-liveness assertions only.
- :48-58 — `nonMatchingProductIDDoesNotSetEntitlement`: second `SKTestSession(configurationFileNamed: "Products")` (:48), asserts not-entitled on an empty account.
- pbxproj side effects: `SingleThread.xcodeproj/project.pbxproj:850-853/:879-882` — `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` on the `SingleThreadTests` target (Debug/Release) with a comment citing a StoreKitTest iOS-18-deprecated-symbol PCM failure (project-wide is `YES`).
- Note: neither scheme's TestAction carries a StoreKitConfigurationFileReference; `SKTestSession(configurationFileNamed:)` resolves `Products` from the synchronized SingleThread folder via the test host bundle.

## 4. IAP entitlements / Info.plist keys / capabilities

- `com.apple.developer.in-app-purchases` — ZERO matches repo-wide (grep `in-app-purchases|InAppPurchases|in_app_purchase|In-App Purchase`). No `SystemCapabilities` entry exists in the pbxproj.
- Entitlements files (exhaustive — only two in the repo):
  - `SingleThread/AppGroup.entitlements` — only `com.apple.security.application-groups` → `group.app.alanvardy.SingleThread`. Wired for iOS: `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`/`[sdk=iphonesimulator*]` = `SingleThread/AppGroup.entitlements` (`project.pbxproj:737-738` Debug, `:787-788` Release). Also used by the widget target (`project.pbxproj:997` Debug, `:1028` Release).
  - `SingleThread/SingleThread.entitlements` — macOS-sandbox keys: `com.apple.security.app-sandbox = true`, `com.apple.security.application-groups` → `group.app.alanvardy.SingleThread`, `com.apple.security.device.audio-input = true`, `com.apple.security.personal-information.calendars = true`. Wired for macOS: `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` (`project.pbxproj:739` Debug, `:789` Release).
  - Watch target (`SingleThreadWatch`): NO CODE_SIGN_ENTITLEMENTS at all (`project.pbxproj:940-998`).
- Info.plist keys: all app/test targets use `GENERATE_INFOPLIST_FILE = YES` (`project.pbxproj:748,798,839,868,896,920,945,973,1001,1031,1061,1083`); the only physical Info.plist is `SingleThreadWidget/Info.plist` (widget NSExtension point `com.apple.widgetkit-extension`). NO IAP/StoreKit `INFOPLIST_KEY_*` anywhere. Existing app-target keys (Debug/Release, `project.pbxproj:749-761/:799-811`): `NSMicrophoneUsageDescription`, `NSRemindersUsageDescription`, `NSSpeechRecognitionUsageDescription`, `UIApplicationSceneManifest_Generation`, `UIApplicationSupportsIndirectInputEvents`, `UILaunchScreen_Generation`, `UIStatusBarStyle`, `UISupportedInterfaceOrientations_iPad/iPhone`. Watch keys: `WKCompanionAppBundleIdentifier`, `WKWatchOnly`, `CFBundleDisplayName`, `NSRemindersFullAccessUsageDescription` (`project.pbxproj:942-957/:977-992`).
- Versioning: every target `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` (app target `project.pbxproj:742,766` Debug, `:792,816` Release).
- Real-device StoreKit prerequisites exist as prose only: `AGENTS.md:68` (sandbox tester account) and `.pi/skills/storekit/SKILL.md` (sandbox tester + signed Paid Applications Agreement; empty `SKProductsRequest` until satisfied).

## 5. Project/build config relevant to archiving

- Project: objectVersion 77, `LastUpgradeCheck = 2660` (`project.pbxproj:3-4,414-417`); config list Debug+Release with `defaultConfigurationName = Release` (`project.pbxproj:1142-1212`).
- App target platform set: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `SDKROOT = auto`, `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, `MACOSX_DEPLOYMENT_TARGET = 26.5` (`project.pbxproj:762,765,770,772` Debug; `:812,815,820,822` Release). Test targets identical shape (`:840-847` etc.); widget `:1012-1018`; watch `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `WATCHOS_DEPLOYMENT_TARGET = 26.5` (`:952-962`, `:987-997`).
- Signing: `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM = 6NWX2DHB9Q` on every target (`project.pbxproj:649,712,741,791,836,865,893,938,970,980,983,1014,1044,1066,1088,1113,1137`). No provisioning-profile names, no manual signing identity anywhere (grep `PROVISIONING|App Record|app record|exportOptions|applicationLoad|AppRecord` = 0).
- Schemes: `SingleThread.xcscheme` BuildAction marks the iOS app entry `buildForArchiving = "YES"` (`:5-31`) AND the `SingleThreadWatch.app` entry `buildForArchiving = "YES"` (`:33-41`) — one scheme archives app + watch together. Both schemes' `ArchiveAction`: `buildConfiguration = "Release"`, `revealArchiveInOrganizer = "YES"`, nothing else (`SingleThread.xcscheme:113-117`; `SingleThreadWatch.xcscheme:96-100`). No `customArchiveName`, no pre/post-actions. Watch app embedded via `Embed Watch Content` (`project.pbxproj:15,266-269`); widget via `Embed Foundation Extensions` (`project.pbxproj:16,270-273`).

## 6. Distribution tooling survey — EXISTS vs ABSENT

Existing (build/test/device-run only; no archive/export/upload pipeline anywhere):
- `.github/workflows/ci.yml` — only workflow. Jobs: `unit-tests` (iOS Debug `build-for-testing` + `test-without-building`, :50-76), `ui-tests-flows` (:78-135), `ui-tests-launch-appearance` (:137-204), `ui-tests-audits` (:206-268), `mac-tests` (macOS Debug `build` with `CODE_SIGNING_ALLOWED=NO`, :293-308), `lint` (SwiftFormat/SwiftLint/watch build/Periphery, :310-367), `watch-ui-tests` (:369-465). No archive/export/upload steps; no secret inputs; `DEVELOPMENT_TEAM` emptied (:29,:96,:163,:230).
- `Makefile` — targets: build, watch-build, mac-build, mac-test, coverage(-ui|-all), test, ui-test, simverify, watch-ui-test, watch-test, check, clean, lint, format, periphery (`Makefile:5-21` .PHONY). All Debug or test-only; no archive/release/distribute/export/prune target.
- `scripts/` — `test.sh` (pipeline incl. macOS Debug `CODE_SIGNING_ALLOWED=NO build`, `scripts/test.sh:267-273`; deployment-target guard `:108-195`), `simverify.sh`, `run-devices.sh` (Debug-iphoneos build + `xcrun devicectl` install/launch on paired devices), `count_tests.sh`. No archive/export/notarize/upload script.
- `docs/` — only `docs/SimulatorManualVerification.md` (simulator appearance gate; notes missing `NSRemindersFullAccessUsageDescription` in app Info.plist as a `latent real-install follow-up` :115-117). No packaging/distribution doc.
- `linear-project.md` — one line: `SingleThread` (`linear-project.md:1`). Zero TestFlight/macOS/distribution/archive/App-Store references.
- `.gitignore` — fastlane ignore entries only (`:34-37`).
- Git history context: `d2ce99b` `Start using testflight` (ancestor of HEAD) only added macOS `mac-build`/`mac-test` Makefile targets, a macOS build+test step in `scripts/test.sh`, and the app-group key in `SingleThread.entitlements` — macOS *build* support was commit-named TestFlight, no upload tooling. `6732857` is a non-ancestor duplicate; `d0219c4` `Testflight macOS` (current branch) adds only a 1-line `DELETEME` placeholder (already gone). HEAD = `c7a86c2` `chore: questions`.

Explicitly ABSENT (grep/find evidence, repo-wide excluding .pi):
- No `xcodebuild archive` / `-exportArchive` / `-exportOptionsPlist` in any script, Makefile, CI job, or doc.
- No `exportOptions.plist`, no `fastlane/` directory (only .gitignore entries), no `Gemfile`.
- No `altool`, `notarytool`, `transporter`, ASC API-key usage; no `applicationLoad`/`AppRecord` tokens.
- No Apple ID / 8-char app-record / Application Loader references.
- No `.xcconfig`, no `.mobileprovision`, no manual provisioning settings.
- No IAP capability (SystemCapabilities) record; no `com.apple.developer.in-app-purchases` entitlement.
- No `StoreKitConfigurationFileReference` in any TestAction; none in the watch scheme at all.
