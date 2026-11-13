import Foundation
import SwiftUI

/// Bridges the platform (`uname` machine identifier + SwiftUI size classes) to the
/// pure `DuoDisplay` / `ChecklistLayout` types. Fails safe to `.standard`: macOS,
/// the simulator, unknown machines and the Duo's inner/landscape displays all
/// resolve to `.standard`.
enum DuoOuterPortrait {
    /// `uname` machine identifier, e.g. "iPhone19,4". Empty where unavailable.
    static let machineIdentifier: String = {
        #if os(iOS)
            var info = utsname()
            guard uname(&info) == 0 else { return "" }
            return withUnsafeBytes(of: &info.machine) { raw in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
        #else
            return ""
        #endif
    }()

    /// Test/launch seam: inject the machine identifier and optionally force the
    /// Duo outer context, overriding the machine + size-class predicate.
    nonisolated static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        machine: String,
        forceDuoOuter: Bool = false) -> ChecklistLayout.Context {
        ChecklistLayout.Context(
            isDuoOuterPortrait: forceDuoOuter
                || DuoDisplay.isOuterPortrait(
                    machine: machine,
                    isCompactWidth: horizontal == .compact,
                    isRegularHeight: vertical == .regular))
    }

    static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?) -> ChecklistLayout.Context {
        context(
            horizontal: horizontal,
            vertical: vertical,
            machine: machineIdentifier,
            forceDuoOuter: LaunchArgument.isPresent(.forceDuoOuter))
    }
}
