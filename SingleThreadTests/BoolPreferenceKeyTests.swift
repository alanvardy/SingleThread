import SingleThreadCore
import Testing

struct BoolPreferenceKeyTests {
    /// Every case's rawValue matches the exact string the old structs' `key` defaults used.
    @Test(arguments: [
        (BoolPreferenceKey.showDate, "showDate"),
        (BoolPreferenceKey.showRecurrence, "showRecurrence"),
        (BoolPreferenceKey.showAlarms, "showAlarms"),
        (BoolPreferenceKey.showCompletionGlow, "showCompletionGlow"),
        (BoolPreferenceKey.showList, "showList"),
        (BoolPreferenceKey.showUndatedReminders, "showUndatedReminders")
    ])
    func keyStringsMatchExistingHardcodedKeys(_ key: BoolPreferenceKey, _ expected: String) {
        #expect(key.rawValue == expected)
    }

    @Test
    func allCasesIsExhaustive() {
        #expect(BoolPreferenceKey.allCases.count == 6)
    }

    /// Compile-time Sendable conformance check.
    @Test
    func isSendable() {
        let key: any Sendable = BoolPreferenceKey.showDate
        _ = key
    }
}
