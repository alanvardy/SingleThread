@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct SingleThreadButtonModifierTests {
    /// The shared modifier is the single decision point for chrome suppression.
    /// Reflection asserts the wrapper is wired (the `.buttonStyle` it applies
    /// inside `body` is not itself reflected — see plan "Notes on deviations").
    @Test
    func composedViewCarriesSingleThreadButtonModifier() {
        let view = Button("Done") {}
            .singleThreadButton()
        #expect(String(describing: view).contains("SingleThreadButtonModifier"))
    }

    /// The modifier is opt-in: a button routed to the platform `.bordered`
    /// style (the scoped-out text-button case) must not pick it up.
    @Test
    func unmodifiedBorderedButtonDoesNotCarrySingleThreadButtonModifier() {
        let description = String(describing: Button("Done") {}.buttonStyle(.bordered))
        #expect(description.contains("BorderedButtonStyle"))
        #expect(!description.contains("SingleThreadButtonModifier"))
    }
}
