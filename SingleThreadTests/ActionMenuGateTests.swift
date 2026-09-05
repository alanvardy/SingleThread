import SingleThreadCore
import Testing

/// Full 2×2×2 truth table for `ActionMenuGate`: enableActionButtons ×
/// canMutate × hasVisibleReminder. The menu shows only when all three hold.
struct ActionMenuGateTests {
    @Test(arguments: [
        (enableActionButtons: true, canMutate: true, hasVisibleReminder: true, expected: true),
        (enableActionButtons: true, canMutate: true, hasVisibleReminder: false, expected: false),
        (enableActionButtons: true, canMutate: false, hasVisibleReminder: true, expected: false),
        (enableActionButtons: true, canMutate: false, hasVisibleReminder: false, expected: false),
        (enableActionButtons: false, canMutate: true, hasVisibleReminder: true, expected: false),
        (enableActionButtons: false, canMutate: true, hasVisibleReminder: false, expected: false),
        (enableActionButtons: false, canMutate: false, hasVisibleReminder: true, expected: false),
        (enableActionButtons: false, canMutate: false, hasVisibleReminder: false, expected: false)
    ])
    func showsActionMenu(enableActionButtons: Bool, canMutate: Bool, hasVisibleReminder: Bool, expected: Bool) {
        let result = ActionMenuGate.showsActionMenu(
            enableActionButtons: enableActionButtons,
            canMutate: canMutate,
            hasVisibleReminder: hasVisibleReminder)
        #expect(result == expected)
    }
}
