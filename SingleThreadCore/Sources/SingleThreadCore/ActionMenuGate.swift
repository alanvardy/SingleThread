import Foundation

/// Decides whether the three-action menu (Skip / Reschedule / Delete) replaces
/// the direct Skip button. Pure so every platform — iOS, macOS, watch — gates
/// identically: the user opted in via Settings AND mutation is currently
/// allowed AND there is a reminder to act on.
public enum ActionMenuGate {
    public static func showsActionMenu(
        enableActionButtons: Bool,
        canMutate: Bool,
        hasVisibleReminder: Bool) -> Bool {
        enableActionButtons && canMutate && hasVisibleReminder
    }
}
