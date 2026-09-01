@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct TextSizeTests {
    @Test
    func systemMapsToNilDynamicTypeSize() {
        #expect(TextSize.system.dynamicTypeSize == nil)
    }

    @Test
    func smallMapsToSmallDynamicTypeSize() {
        #expect(TextSize.small.dynamicTypeSize == .small)
    }

    @Test
    func mediumMapsToMediumDynamicTypeSize() {
        #expect(TextSize.medium.dynamicTypeSize == .medium)
    }

    @Test
    func largeMapsToXLargeDynamicTypeSize() {
        #expect(TextSize.large.dynamicTypeSize == .xLarge)
    }

    @Test
    func extraLargeMapsToXXXLargeDynamicTypeSize() {
        #expect(TextSize.extraLarge.dynamicTypeSize == .xxxLarge)
    }

    @Test
    func allCasesCoverFiveCases() {
        #expect(TextSize.allCases == [.system, .small, .medium, .large, .extraLarge])
    }

    @Test
    func titlesAreHumanReadable() {
        #expect(TextSize.system.title == String.en("System", bundle: .main))
        #expect(TextSize.small.title == String.en("Small", bundle: .main))
        #expect(TextSize.medium.title == String.en("Medium", bundle: .main))
        #expect(TextSize.large.title == String.en("Large", bundle: .main))
        #expect(TextSize.extraLarge.title == String.en("Extra Large", bundle: .main))
    }
}
