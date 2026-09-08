Q1 findings: Multi-platform configuration of SingleThread.xcodeproj

Source of truth: SingleThread.xcodeproj/project.pbxproj (1240 lines, objectVersion 77,
preferredProjectObjectVersion 77), schemes, entitlements, SwiftPM package, CI.

== 0. Target inventory ==

Seven PBXNativeTargets exist (project.pbxproj:238-406; project targets list at
project.pbxproj:462-470):
- SingleThread — app, productType com.apple.product-type.application (project.pbxproj:264)
- SingleThreadTests — com.apple.product-type.bundle.unit-test (project.pbxproj:288)
- SingleThreadUITests — com.apple.product-type.bundle.ui-testing (project.pbxproj:311)
- SingleThreadWatch — watchOS app, com.apple.product-type.application (project.pbxproj:334)
- SingleThreadWatchUITests — com.apple.product-type.bundle.ui-testing (project.pbxproj:380)
- SingleThreadWatchTests — com.apple.product-type.bundle.unit-test (project.pbxproj:404)
- SingleThreadWidget — com.apple.product-type.app-extension (project.pbxproj:357)

There is NO separate WatchKit-App / WatchKit-Extension split. The watch side is a SINGLE
watchOS application target SingleThreadWatch (product ref SingleThreadWatch.app,
project.pbxproj:334), sourcing the whole SingleThreadWatch/ folder via
fileSystemSynchronizedGroups (project.pbxproj:325), with generated-plist keys
INFOPLIST_KEY_WKWatchOnly = NO and
INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.SingleThread
(project.pbxproj:948-949 and 976-977). All source groups are PBXFileSystemSynchronizedRootGroup
with empty Sources/Resources phases (project.pbxproj:110-160, 470-530 area).

== 1. Platform declarations and build settings per target ==

All configs below are duplicated identically in Debug and Release; where one line is cited,
the sibling in the next block is the Release twin. Project-level Debug config:
project.pbxproj:614-675; project-level Release: project.pbxproj:677-728. Project level declares
NO platform settings (no SDKROOT, no SUPPORTED_PLATFORMS, no deployment targets) — only
compiler warnings, DEVELOPMENT_TEAM = 6NWX2DHB9Q, SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
(and ONLY_ACTIVE_ARCH/ENABLE_TESTABILITY in Debug). TargetAttributes set TestTargetID only for
SingleThreadTests and SingleThreadWatchTests (project.pbxproj:421, 437).

== 1.1 SingleThread (app) ==
Debug block project.pbxproj:730-779; Release block project.pbxproj:781-830.
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" (772 / 822)
- SDKROOT = auto (770 / 820)
- TARGETED_DEVICE_FAMILY = "1,2" (778 / 828)
- IPHONEOS_DEPLOYMENT_TARGET = 18.7 (762 / 812)
- MACOSX_DEPLOYMENT_TARGET = 26.5 (765 / 815)
- CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = SingleThread/AppGroup.entitlements (737 / 787)
- CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*] = SingleThread/AppGroup.entitlements (738 / 788)
- CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = SingleThread/SingleThread.entitlements (739 / 789)
- CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development" (740 / 790)
- LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks" (763 / 813)
- LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = "@executable_path/../Frameworks" (764 / 814)
- GENERATE_INFOPLIST_FILE = YES (748 / 798); no INFOPLIST_FILE (fully generated)
- iOS-only INFOPLIST_KEY conditionals: UIApplicationSceneManifest_Generation[sdk=iphoneos*]
  and [sdk=iphonesimulator*] = YES (752-753 / 802-803),
  UIApplicationSupportsIndirectInputEvents[sdk=iphoneos*|iphonesimulator*] (754-755 / 804-805),
  UILaunchScreen_Generation[sdk=…] (756-757 / 806-807), UIStatusBarStyle[sdk=…] (758-759 / 808-809),
  UISupportedInterfaceOrientations_iPad/_iPhone (760-761 / 810-811)
- Unconditional INFOPLIST_KEYs: NSMicrophone/NSReminders/NSSpeechRecognition usage strings
  (749-751 / 799-801)
- macOS hardening: ENABLE_APP_SANDBOX = YES (744 / 794), ENABLE_HARDENED_RUNTIME = YES (745 / 795),
  ENABLE_USER_SELECTED_FILES = readonly (747 / 797), REGISTER_APP_GROUPS = YES (769 / 819)
- SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (774 / 824); SWIFT_VERSION = 6.0 (777 / 827)

== 1.2 SingleThreadTests ==
Debug project.pbxproj:831-859; Release project.pbxproj:861-889.
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" (847 / 876); SDKROOT = auto (845 / 874)
- TARGETED_DEVICE_FAMILY = "1,2" (856 / 885)
- IPHONEOS_DEPLOYMENT_TARGET = 18.7 (840 / 869); MACOSX_DEPLOYMENT_TARGET = 26.5 (841 / 870)
- BUNDLE_LOADER = $(TEST_HOST) (835 / 864);
  TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThread.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SingleThread"
  (857 / 886)
- GENERATE_INFOPLIST_FILE = YES (839 / 868); no entitlements, no per-sdk conditionals
- SWIFT_TREAT_WARNINGS_AS_ERRORS = NO with inline comment: StoreKitTest headers contain an
  iOS-18-deprecated symbol so the module PCM fails under warnings-as-errors (852-854 / 881-883);
  the only iOS-family target relaxing warnings-as-errors
- SWIFT_VERSION = 6.0 (855 / 884)
- packageProductDependencies: SingleThreadCore (project.pbxproj:283)

== 1.3 SingleThreadUITests ==
Debug project.pbxproj:890-912; Release project.pbxproj:914-936.
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" (904 / 928); SDKROOT = auto (902 / 926)
- TARGETED_DEVICE_FAMILY = "1,2" (909 / 933)
- IPHONEOS_DEPLOYMENT_TARGET = 18.7 (897 / 921); MACOSX_DEPLOYMENT_TARGET = 26.5 (898 / 922)
- TEST_TARGET_NAME = SingleThread (910 / 934); GENERATE_INFOPLIST_FILE = YES (896 / 920)
- SWIFT_VERSION = 6.0 (908 / 932); no entitlements, no per-sdk conditionals, no package dependency

== 1.4 SingleThreadWatch (watchOS app) ==
Debug project.pbxproj:937-963; Release project.pbxproj:965-991.
- SDKROOT = watchos (953 / 981)
- SUPPORTED_PLATFORMS = "watchos watchsimulator" (956 / 984)
- TARGETED_DEVICE_FAMILY = 4 (961 / 989)
- WATCHOS_DEPLOYMENT_TARGET = 26.5 (962 / 990)
- GENERATE_INFOPLIST_FILE = YES (945 / 973); INFOPLIST_KEY_CFBundleDisplayName = SingleThread
  (946 / 974), INFOPLIST_KEY_NSRemindersFullAccessUsageDescription (947 / 975),
  INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.SingleThread (948 / 976),
  INFOPLIST_KEY_WKWatchOnly = NO (949 / 977)
- SKIP_INSTALL = YES (954 / 982)
- SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (958 / 986); SWIFT_VERSION = 6.0 (960 / 988)
- No CODE_SIGN_ENTITLEMENTS, no LD_RUNPATH, no per-sdk conditionals
- packageProductDependencies: SingleThreadCore (project.pbxproj:326)

== 1.5 SingleThreadWatchUITests ==
Debug project.pbxproj:1055-1075; Release project.pbxproj:1077-1097.
- SDKROOT = watchos (1066 / 1088); SUPPORTED_PLATFORMS = "watchos watchsimulator" (1068 / 1090)
- TARGETED_DEVICE_FAMILY = 4 (1072 / 1094); WATCHOS_DEPLOYMENT_TARGET = 26.5 (1074 / 1096)
- TEST_TARGET_NAME = SingleThreadWatch (1073 / 1095); GENERATE_INFOPLIST_FILE = YES (1062 / 1084)
- SWIFT_VERSION = 6.0 (1071 / 1093)

== 1.6 SingleThreadWatchTests ==
Debug project.pbxproj:1099-1121; Release project.pbxproj:1123-1145.
- SDKROOT = watchos (1111 / 1135); SUPPORTED_PLATFORMS = "watchos watchsimulator" (1113 / 1137)
- TARGETED_DEVICE_FAMILY = 4 (1118 / 1142); WATCHOS_DEPLOYMENT_TARGET = 26.5 (1120 / 1144)
- BUNDLE_LOADER = $(TEST_HOST) (1103 / 1127);
  TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThreadWatch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SingleThreadWatch"
  (1119 / 1143)
- GENERATE_INFOPLIST_FILE = YES (1107 / 1131); SWIFT_VERSION = 6.0 (1117 / 1141)
- packageProductDependencies: SingleThreadCore (project.pbxproj:396)

== 1.7 SingleThreadWidget (app extension) ==
Debug project.pbxproj:992-1022; Release project.pbxproj:1024-1053.
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" (1016 / 1047) — but NO SDKROOT and
  NO MACOSX_DEPLOYMENT_TARGET set at all (inherits SDK defaults)
- TARGETED_DEVICE_FAMILY = "1,2" (1021 / 1052); IPHONEOS_DEPLOYMENT_TARGET = 18.7 (1006 / 1037)
- CODE_SIGN_ENTITLEMENTS = SingleThread/AppGroup.entitlements — UNCONDITIONAL, no [sdk=…] qualifier
  (997 / 1028)
- GENERATE_INFOPLIST_FILE = YES (1001 / 1032) AND INFOPLIST_FILE = SingleThreadWidget/Info.plist
  (1002 / 1033). SingleThreadWidget/Info.plist is exempted from the synchronized folder via
  PBXFileSystemSynchronizedBuildFileExceptionSet with membershipExceptions = (Info.plist)
  (project.pbxproj:99-107; exception attached to the root group at project.pbxproj:135-139).
  The widget Info.plist contains only NSExtension/NSExtensionPointIdentifier =
  com.apple.widgetkit-extension (SingleThreadWidget/Info.plist)
- LD_RUNPATH_SEARCH_PATHS = ("@executable_path/Frameworks", "@executable_path/../../Frameworks")
  (1007-1009 / 1038-1040)
- SKIP_INSTALL = YES (1014 / 1045); SWIFT_VERSION = 6.0 (1020 / 1051)
- No per-sdk conditionals of any kind; packageProductDependencies: SingleThreadCore (349)

== 2. platformFilter / embedding of watch app and widget ==

- App target buildPhases include two copy phases after Resources (project.pbxproj:243-249):
  - Embed Watch Content (project.pbxproj:65-74): dstPath = $(CONTENTS_FOLDER_PATH)/Watch,
    dstSubfolderSpec = 16, containing build file SingleThreadWatch.app in Embed Watch Content
    which carries platformFilter = ios (project.pbxproj:15); phase listed at line 246.
  - Embed Foundation Extensions (project.pbxproj:76-85): dstPath = "", dstSubfolderSpec = 13,
    containing SingleThreadWidget.appex in Embed Foundation Extensions (project.pbxproj:16);
    NO platformFilter on this build file; phase listed at line 247.
- App dependencies (project.pbxproj:252-253; definitions 578-611):
  - 51AA3F27 app → SingleThreadWatch: platformFilter = ios (591)
  - 51AA3F49 app → SingleThreadWidget: platformFilter = ios (597)
  Both are PBXTargetDependency with PBXContainerItemProxy proxyType 1 into the same container
  portal (project.pbxproj:34-46).
- Watch test targets depend on SingleThreadWatch with NO platformFilter (601-604, 606-609).
- Consequence: building the SingleThread scheme for a macosx destination filters OUT both the
  watch-app and widget dependency + watch embed copy (only iphoneos/iphonesimulator satisfy
  platformFilter = ios). Widget embed has no build-file filter but its target dependency is
  filtered, so the widget is not built for macOS at all.

== 3. What -destination platform=macOS produces: NATIVE Mac app, NOT Catalyst ==

- SingleThread is a plain com.apple.product-type.application (project.pbxproj:264), product
  reference SingleThread.app (project.pbxproj:240).
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"; the string maccatalyst occurs NOWHERE
  in the project (grep for maccatalyst / SUPPORTS_MACCATALYST / DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER
  over SingleThread.xcodeproj returns zero matches). TARGETED_DEVICE_FAMILY never includes 6.
- SDKROOT = auto (770/820) resolves to the macosx SDK for macOS destinations; the macOS path uses
  dedicated macosx-SDK settings: CODE_SIGN_ENTITLEMENTS[sdk=macosx*] → SingleThread.entitlements,
  CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development, LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] =
  @executable_path/../Frameworks, App Sandbox + Hardened Runtime + REGISTER_APP_GROUPS, all of
  which are macOS-only features.
- CI/make treat it as native: .github/workflows/ci.yml mac-tests job runs
  xcodebuild -scheme SingleThread -destination "platform=macOS" -configuration Debug CODE_SIGNING_ALLOWED=NO
  build, then test -only-testing:SingleThreadTests on it (ci.yml mac-tests job). Makefile defines
  MAC_SIM := platform=macOS and mac-build/mac-test pass it (Makefile MAC_SIM / mac-build / mac-test).
  No platform=macOS,variant=Mac Catalyst destination appears anywhere.
- Product: a native SingleThread.app for macOS 26.5 (MACOSX_DEPLOYMENT_TARGET 26.5), with the
  watch app and widget excluded via platformFilter = ios (section 2).

== 4. Schemes ==

SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme:
- BuildAction: two BuildActionEntries — SingleThread.app (buildForTesting/Running/Profiling/
  Archiving/Analyzing = YES) and SingleThreadWatch.app (buildForTesting = YES, buildForRunning = NO,
  buildForProfiling = NO, buildForArchiving = YES, buildForAnalyzing = YES).
- TestAction (Debug): Testables = SingleThreadTests and SingleThreadUITests; no MacroExpansion
  element; shouldAutocreateTestPlan = YES.
- LaunchAction: BuildableProductRunnable → SingleThread.app plus StoreKitConfigurationFileReference
  identifier = ../SingleThread/Products.storekit (SingleThread.xcscheme:90-92).
- ProfileAction → SingleThread.app. No MacroExpansion entries exist in either scheme.

SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch.xcscheme:
- BuildAction: single entry SingleThreadWatch.app (all actions YES).
- TestAction (Debug): Testables = SingleThreadWatchUITests and SingleThreadWatchTests.
- LaunchAction/ProfileAction → SingleThreadWatch.app.

Note: the SingleThread scheme does not run-build the watch app (buildForRunning = NO), so a plain
xcodebuild -scheme SingleThread -destination platform=macOS build compiles only the app target.

== 5. Entitlement files ↔ CODE_SIGN_ENTITLEMENTS mapping ==

- SingleThread/AppGroup.entitlements: com.apple.security.application-groups =
  group.app.alanvardy.SingleThread only. Referenced by the app target for sdk=iphoneos* and
  sdk=iphonesimulator* (project.pbxproj:737-738, 787-788), and by the widget target
  unconditionally (997, 1028).
- SingleThread/SingleThread.entitlements: App Sandbox true, application-groups
  group.app.alanvardy.SingleThread, com.apple.security.device.audio-input true,
  com.apple.security.personal-information.calendars true. Referenced by the app target for
  sdk=macosx* ONLY (739, 789).
- Watch target and all test targets have no CODE_SIGN_ENTITLEMENTS.

== 6. SwiftPM package wiring (SingleThreadCore) ==

- Package declared as local: XCLocalSwiftPackageReference SingleThreadCore,
  relativePath = SingleThreadCore (project.pbxproj:1226-1228), referenced from PBXProject
  packageReferences (project.pbxproj:455-456). No remote package references exist.
- Product dependency SingleThreadCore (XCSwiftPackageProductDependency, project.pbxproj:1234-1236)
  is a packageProductDependencies entry of FIVE targets: SingleThread (256), SingleThreadTests
  (283), SingleThreadWatch (326), SingleThreadWidget (349), SingleThreadWatchTests (396). The two
  UI-test targets have none.
- SingleThreadCore/Package.swift: swift-tools-version 6.0; platforms .iOS("18.7"), .watchOS("26.5"),
  .macOS("26.5"); library product SingleThreadCore; resources .process("Resources").

== 7. Language/toolchain settings ==

- SWIFT_VERSION = 6.0 on every target (app 777/827, tests 855/884, UI tests 908/932,
  watch 960/988, watch UI 1071/1093, watch tests 1117/1141, widget 1020/1051).
- SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor only on app (774/824) and watch app (958/986).
- SWIFT_APPROACHABLE_CONCURRENCY = YES on app, both iOS test bundles, watch app and widget.
- SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES on app, SingleThreadTests,
  SingleThreadUITests, widget, SingleThreadWatchTests.
- Project-level LastUpgradeCheck = 2660, LastSwiftUpdateCheck = 2660, CreatedOnToolsVersion = 26.6
  for all targets (project.pbxproj:410-446).
