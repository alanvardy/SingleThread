#if os(iOS)
    @testable import SingleThread
    import Testing
    import UIKit

    @MainActor
    struct AppDelegateTests {
        @Test
        func replayingSystemAfterLightClearsWindowOverride() throws {
            // `UIWindow(frame:)` is deprecated in iOS 26, so build the test
            // window off the host app's connected `UIWindowScene`. It is never
            // shown or made key, so it doesn't disturb the live key window.
            let scene = try #require(
                UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)

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
    }
#endif
