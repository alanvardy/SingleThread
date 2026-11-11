import CoreGraphics
@testable import SingleThread
import Testing

struct ChecklistLayoutTests {
    @Test
    func standardContextKeepsTheFortyPointGutter() {
        #expect(ChecklistLayout.horizontalInset(.standard) == 40)
    }

    @Test
    func duoOuterContextHalvesTheGutter() {
        #expect(ChecklistLayout.horizontalInset(.init(isDuoOuterPortrait: true)) == 20)
    }

    /// Anti-drift: the standard path must stay CardWidth at every viewport.
    @Test
    func standardWidthMatchesCardWidthAcrossTheDomain() {
        for width in stride(from: 0.0, through: 1500.0, by: 10.0) {
            #expect(
                ChecklistLayout.maxContentWidth(viewportWidth: width, context: .standard)
                    == CardWidth.maxContentWidth(viewportWidth: width))
        }
    }

    @Test
    func standardContextPreservesTheSixtyPercentCap() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 200, context: .standard) == 120)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 1000, context: .standard) == 340)
    }

    @Test
    func duoOuterWidthUsesTheLargerFractionBelowTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 200, context: .init(isDuoOuterPortrait: true)) == 160)
    }

    @Test
    func duoOuterWidthClampsAtTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 466, context: .init(isDuoOuterPortrait: true)) == 340)
    }

    /// Sad/boundary path: 425 is the exact 340 / 0.8 crossover.
    @Test
    func duoOuterWidthBoundaryIsFourTwentyFive() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 425, context: duo) == 340)
        #expect(abs(ChecklistLayout.maxContentWidth(viewportWidth: 424.9, context: duo) - 339.92) < 0.0001)
    }

    /// A safe-area-adjusted Duo outer viewport: the card must not exceed it.
    @Test
    func duoOuterWidthFitsTheSafeAreaAdjustedViewport() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(abs(ChecklistLayout.maxContentWidth(viewportWidth: 382, context: duo) - 305.6) < 0.0001)
    }

    @Test
    func widthIsNonNegativeAtZeroViewport() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 0, context: .standard) == 0)
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 0, context: .init(isDuoOuterPortrait: true)) == 0)
    }

    /// The three converted call sites must be bit-identical to the legacy layout on
    /// every non-Duo viewport, including the iPad.
    @Test
    func standardContextMatchesLegacyLayoutAtRealViewports() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 402, context: .standard) == 241.2)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 382, context: .standard) == 229.2)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 874, context: .standard) == 340)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 1024, context: .standard) == 340)
        #expect(ChecklistLayout.horizontalInset(.standard) == 40)
    }
}
