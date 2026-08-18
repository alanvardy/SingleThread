#if os(iOS)
    import UIKit

    /// Bridges UIKit orientation locking into the SwiftUI `App` lifecycle.
    ///
    /// Registered via `@UIApplicationDelegateAdaptor` in `SingleThreadApp`.
    /// Reads `allowsLandscape` from `UserDefaults` directly so the persisted
    /// lock takes effect at launch — before any SwiftUI view appears —
    /// avoiding a wrong-orientation flash.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        /// Re-evaluates the orientation lock and requests an immediate rotation
        /// if the current orientation violates the new mask.
        ///
        /// Call this from SwiftUI when the `allowsLandscape` toggle changes.
        /// On iPad in Split View or Slide Over the request may be denied
        /// (`Code=101`), but the mask will still prevent auto-rotation.
        static func applyLock(allowsLandscape: Bool) {
            let mask: UIInterfaceOrientationMask = allowsLandscape
                ? .allButUpsideDown
                : .portrait
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let controller = scene.keyWindow?.rootViewController
            else { return }

            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("Orientation request failed: \(error.localizedDescription)")
            }
        }

        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
            let keyExists = UserDefaults.standard.object(forKey: "allowsLandscape") != nil
            let allowsLandscape = keyExists
                ? UserDefaults.standard.bool(forKey: "allowsLandscape")
                : true
            return allowsLandscape ? .allButUpsideDown : .portrait
        }
    }
#endif
