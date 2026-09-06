#if os(iOS)
    import SingleThreadCore
    import UIKit

    /// Bridges UIKit orientation locking into the SwiftUI `App` lifecycle.
    ///
    /// Registered via `@UIApplicationDelegateAdaptor` in `SingleThreadApp`.
    /// Reads `allowsLandscape` from `UserDefaults` directly so the persisted
    /// lock takes effect at launch — before any SwiftUI view appears —
    /// avoiding a wrong-orientation flash.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        /// Applies the persisted appearance to every window in every connected
        /// scene, and on demand to explicit windows. The `.system` sentinel
        /// (`.unspecified`) clears any prior override so the window re-follows
        /// the device — replaying Light → System converges reliably.
        static func applyAppearance(_ mode: AppearanceMode, to windows: [UIWindow]? = nil) {
            let targets = windows
                ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            for window in targets {
                window.overrideUserInterfaceStyle = mode.windowOverrideStyle
            }
        }

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

        func applicationDidBecomeActive(_: UIApplication) {
            print("SimVerify: app active")
            Self.applyAppearance(AppearanceMode.load())
        }

        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
            let allowsLandscape = OrientationPreference().isLandscapeEnabled
            return allowsLandscape ? .allButUpsideDown : .portrait
        }
    }
#endif

#if os(macOS)
    import AppKit

    /// Bridges the persisted appearance into every `NSWindow`, mirroring the
    /// iOS `AppDelegate` seam. Registered via `@NSApplicationDelegateAdaptor`.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        // MARK: Internal

        /// Re-applies `mode` to every open window. `.system` sets `nil`,
        /// clearing the explicit appearance so the window follows the system.
        static func applyAppearance(_ mode: AppearanceMode) {
            for window in NSApp.windows {
                window.appearance = mode.appKitAppearance
            }
        }

        func applicationDidFinishLaunching(_: Notification) {
            applyLaunchAppearance()
        }

        func applicationDidBecomeActive(_: Notification) {
            applyLaunchAppearance()
        }

        // MARK: Private

        private func applyLaunchAppearance() {
            Self.applyAppearance(AppearanceMode.load())
        }
    }
#endif
