@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct DuoOuterPortraitTests {
    @Test
    func duoMachineInCompactRegularIsDuoOuter() {
        let context = DuoOuterPortrait.context(
            horizontal: .compact, vertical: .regular, machine: "iPhone19,4")
        #expect(context == .init(isDuoOuterPortrait: true))
    }

    /// Sad: the Duo's inner display must not change the layout.
    @Test
    func duoMachineInRegularRegularIsStandard() {
        let context = DuoOuterPortrait.context(
            horizontal: .regular, vertical: .regular, machine: "iPhone19,4")
        #expect(context == .standard)
    }

    /// Sad: a non-Duo phone in the same size classes must not change the layout.
    @Test
    func nonDuoMachineInCompactRegularIsStandard() {
        let context = DuoOuterPortrait.context(
            horizontal: .compact, vertical: .regular, machine: "iPhone17,1")
        #expect(context == .standard)
    }

    /// Fail-safe: the macOS / unknown-machine path.
    @Test
    func emptyMachineIsStandard() {
        #expect(DuoOuterPortrait.context(horizontal: .compact, vertical: .regular, machine: "")
            == .standard)
        #expect(DuoOuterPortrait.context(horizontal: nil, vertical: nil, machine: "iPhone19,4")
            == .standard)
    }

    /// Happy: the screenshot/test seam forces the Duo outer context even where
    /// `uname` reports the host arch and the size class is regular/regular.
    @Test
    func forceFlagReturnsDuoContext() {
        let context = DuoOuterPortrait.context(
            horizontal: .regular, vertical: .regular, machine: "arm64", forceDuoOuter: true)
        #expect(context == .init(isDuoOuterPortrait: true))
    }

    @Test
    func machineIdentifierIsReadable() {
        #if os(iOS)
            #expect(!DuoOuterPortrait.machineIdentifier.isEmpty)
            #expect(!DuoOuterPortrait.machineIdentifier.contains("\n"))
        #else
            #expect(DuoOuterPortrait.machineIdentifier.isEmpty)
        #endif
    }
}
