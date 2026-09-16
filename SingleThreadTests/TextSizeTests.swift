@testable import SingleThread
import SingleThreadCore
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
        #expect(TextSize.system.title.resolved(in: Locale(identifier: "en")) == "System")
        #expect(TextSize.small.title.resolved(in: Locale(identifier: "en")) == "Small")
        #expect(TextSize.medium.title.resolved(in: Locale(identifier: "en")) == "Medium")
        #expect(TextSize.large.title.resolved(in: Locale(identifier: "en")) == "Large")
        #expect(TextSize.extraLarge.title.resolved(in: Locale(identifier: "en")) == "Extra Large")
    }
}
