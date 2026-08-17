@testable import SingleThread
import Testing
import UIKit

#if os(iOS)
    @MainActor
    struct AppDelegateTests {
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
