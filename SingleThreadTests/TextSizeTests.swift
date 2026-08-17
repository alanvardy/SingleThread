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
    func largeMapsToLargeDynamicTypeSize() {
        #expect(TextSize.large.dynamicTypeSize == .large)
    }

    @Test
    func extraLargeMapsToXLargeDynamicTypeSize() {
        #expect(TextSize.extraLarge.dynamicTypeSize == .xLarge)
    }

    @Test
    func allCasesCoverFiveCases() {
        #expect(TextSize.allCases == [.system, .small, .medium, .large, .extraLarge])
    }

    @Test
    func titlesAreHumanReadable() {
        #expect(TextSize.system.title == "System")
        #expect(TextSize.small.title == "Small")
        #expect(TextSize.medium.title == "Medium")
        #expect(TextSize.large.title == "Large")
        #expect(TextSize.extraLarge.title == "Extra Large")
    }
}