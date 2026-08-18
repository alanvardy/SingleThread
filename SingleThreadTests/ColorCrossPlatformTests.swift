@testable import SingleThread
import SwiftUI
import Testing

// MARK: - Color.systemBackground

struct ColorCrossPlatformTests {
    @Test
    func systemBackgroundResolves() {
        let color = Color.systemBackground
        #expect(String(describing: color).isEmpty == false)
    }
}
