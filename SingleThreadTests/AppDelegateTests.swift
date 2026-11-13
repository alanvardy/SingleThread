#if os(iOS)
    @testable import SingleThread
    import Testing
    import UIKit

    @MainActor
    struct AppDelegateTests {
        @Test
        func replayingSystemAfterLightClearsWindowOverride() {
            // Build a scene-independent window so the test does not depend on
            // the host app's `connectedScenes` ordering/timing (which flaked on
            // iPad in the full-suite CI run). `UIWindow(frame:)` is deprecated
            // only for iOS 26+ deployment targets; this target is 17.0, so it
            // compiles without a deprecation warning. The window is never shown
            // or made key, so it doesn't disturb the live key window.
            let window = UIWindow(frame: .zero)

            AppDelegate.applyAppearance(.light, to: [window])
            #expect(window.overrideUserInterfaceStyle == .light)

            AppDelegate.applyAppearance(.system, to: [window])
            #expect(window.overrideUserInterfaceStyle == .unspecified)
        }

        @Test
        func allowsLandscapeTrueReturnsAllButUpsideDown() {
            UserDefaults.standard.set(true, forKey: "allowsLandscape")
            let delegate = AppDelegate()
            let app = UIApplication.shared
            let mask = delegate.application(
                app,
                supportedInterfaceOrientationsFor: nil)
            #expect(mask == .allButUpsideDown)
        }

        @Test
        func allowsLandscapeFalseReturnsPortrait() {
            UserDefaults.standard.set(false, forKey: "allowsLandscape")
            let delegate = AppDelegate()
            let app = UIApplication.shared
            let mask = delegate.application(
                app,
                supportedInterfaceOrientationsFor: nil)
            #expect(mask == .portrait)
        }

        @Test
        func missingKeyDefaultsToLandscapeAllowed() {
            UserDefaults.standard.removeObject(forKey: "allowsLandscape")
            let delegate = AppDelegate()
            let app = UIApplication.shared
            let mask = delegate.application(
                app,
                supportedInterfaceOrientationsFor: nil)
            #expect(mask == .allButUpsideDown)
        }

        @Test
        func forcedLandscapePinsLandscapeOnly() {
            // Regression: the harness used to request landscape geometry while
            // portrait stayed supported, so the Duo cover display never rotated
            // and the outer landscape shot came out 1398 x 2034.
            #expect(
                AppDelegate.supportedOrientations(
                    forcedOrientation: "landscape",
                    allowsLandscape: true) == .landscape)
            #expect(
                AppDelegate.supportedOrientations(
                    forcedOrientation: "landscape",
                    allowsLandscape: false) == .landscape)
        }

        @Test
        func nonLandscapeForcedValueFallsBackToPreference() {
            #expect(
                AppDelegate.supportedOrientations(
                    forcedOrientation: "portrait",
                    allowsLandscape: true) == .allButUpsideDown)
            #expect(
                AppDelegate.supportedOrientations(
                    forcedOrientation: nil,
                    allowsLandscape: false) == .portrait)
        }
    }
#endif
