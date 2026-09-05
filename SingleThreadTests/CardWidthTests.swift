import CoreGraphics
@testable import SingleThread
import Testing

struct CardWidthTests {
    @Test
    func maxContentWidthScalesBelowCeiling() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 200) == 120)
    }

    @Test
    func maxContentWidthPinsAtCeiling() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 1000) == 340)
    }

    @Test
    func maxContentWidthHitsCeilingAtBoundary() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 340 / 0.6) == 340)
    }

    @Test
    func maxContentWidthIsNonNegativeAtZeroViewport() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 0) == 0)
    }
}
