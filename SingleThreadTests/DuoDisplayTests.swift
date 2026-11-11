@testable import SingleThread
import Testing

struct DuoDisplayTests {
    @Test
    func knownMachineInOuterPortraitIsRecognised() {
        #expect(DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: true))
    }

    /// Sad: the Duo's inner display is regular width.
    @Test
    func knownMachineWithRegularWidthIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: false, isRegularHeight: true))
    }

    /// Sad: the Duo's outer landscape is compact height.
    @Test
    func knownMachineWithCompactHeightIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: false))
    }

    @Test
    func otherMachinesAreNeverRecognised() {
        for machine in ["iPhone17,1", "iPad13,1", "", "arm64"] {
            #expect(!DuoDisplay.isOuterPortrait(
                machine: machine, isCompactWidth: true, isRegularHeight: true))
        }
    }

    @Test(arguments: ["iPhone19,4", "iPhone17,1", "", "iPad13,1"])
    func sizeClassMatrixFiresOnlyForKnownMachine(machine: String) {
        for horizontal in [true, false] {
            for vertical in [true, false] {
                #expect(DuoDisplay.isOuterPortrait(
                    machine: machine, isCompactWidth: horizontal, isRegularHeight: vertical)
                    == (machine == "iPhone19,4" && horizontal && vertical))
            }
        }
    }

    /// Sad: whitespace / newline / lowercase identifiers must not match.
    @Test(arguments: ["iPhone19,4 ", "iPhone19,4\n", "iphone19,4"])
    func malformedMachinesAreNotOuterPortrait(machine: String) {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: machine, isCompactWidth: true, isRegularHeight: true))
    }
}
