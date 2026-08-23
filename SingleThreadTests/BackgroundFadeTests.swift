@testable import SingleThread
import Testing

// MARK: - Background Fade Tests

@MainActor
struct BackgroundFadeTests {
    @Test
    func defaultIsFiftyPercent() {
        #expect(BackgroundFade.defaultValue == 50)
    }

    @Test
    func allValuesAscendInTenPercentSteps() {
        #expect(BackgroundFade.allValues == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
    }

    @Test
    func opacityConvertsPercentToFraction() {
        #expect(BackgroundFade.opacity(for: 0) == 0)
        #expect(BackgroundFade.opacity(for: 50) == 0.5)
        #expect(BackgroundFade.opacity(for: 100) == 1)
    }

    @Test
    func opacityClampsOutOfRangePersistedValues() {
        #expect(BackgroundFade.opacity(for: -30) == 0)
        #expect(BackgroundFade.opacity(for: 130) == 1)
    }
}
