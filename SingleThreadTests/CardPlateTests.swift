@testable import SingleThread
import SwiftUI
import Testing

/// The shared card-plate styling decisions live on `CardPlate` so they can be
/// asserted headlessly. These tests pin the values before the modifier and
/// call-site migration touches them.
@MainActor
struct CardPlateTests {
    @Test
    func cornerRadiusIsTenPoints() {
        #expect(CardPlate.cornerRadius == 10)
    }

    @Test
    func promptBoxFillIsDarkGrey() {
        #expect(CardPlate.promptBoxFill == Color(red: 0.16, green: 0.17, blue: 0.18))
    }

    @Test
    func promptBoxFillOffWhiteInLightMode() {
        #expect(CardPlate.promptBoxFill(for: .light) == Color(white: 0.92))
    }

    @Test
    func promptBoxFillDarkGreyInDarkMode() {
        #expect(CardPlate.promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17, blue: 0.18))
    }

    @Test
    func plateFillOffWhiteInLightMode() {
        let fill = CardPlate.plateFill(for: .light)
        #expect(fill == Color(red: 0.96, green: 0.95, blue: 0.94))
    }

    @Test
    func plateFillBlackInDarkMode() {
        #expect(CardPlate.plateFill(for: .dark) == Color.black)
    }

    /// Sad path: the adaptive branch must produce different results — if both
    /// modes returned the same colour, the ternary would be dead.
    @Test
    func plateFillDarkDiffersFromLight() {
        let dark = CardPlate.plateFill(for: .dark)
        let light = CardPlate.plateFill(for: .light)
        #expect(dark != light)
    }
}
