/// Detects the Duo's outer screen. The machine identifier alone cannot tell the
/// outer display from the inner one, and the outer display rotates, so the match
/// requires the portrait-specific compact-width/regular-height size-class pair.
enum DuoDisplay {
    nonisolated static let outerPortraitMachines: Set<String> = ["iPhone19,4"]

    nonisolated static func isOuterPortrait(
        machine: String,
        isCompactWidth: Bool,
        isRegularHeight: Bool) -> Bool {
        outerPortraitMachines.contains(machine) && isCompactWidth && isRegularHeight
    }
}
