@testable import SingleThread
import SwiftUI
import Testing

/// `View.cardPlate(...)` wraps content in a `CardPlateModifier`. SwiftUI does
/// not inline a `ViewModifier`'s body into the host view's static type, so
/// `String(describing:)` cannot surface the `RoundedRectangle` it draws — the
/// shape is instead pinned through `SwipePromptTests.promptShownWhenEnabled`,
/// which still sees `RoundedRectangle` in the prompt's inline background chain.
/// These tests pin the modifier composition that reflection can observe.
@MainActor
struct CardPlateModifierTests {
    @Test
    func cardPlateAppliesCardPlateModifier() {
        let view = Text("test").cardPlate(fill: .blue)
        let description = String(describing: view)
        #expect(description.contains("CardPlateModifier"))
    }

    /// Sad path: the geometry-restore flag changes the modifier chain so the
    /// serialized description differs. This guards the `padding(-padding)`
    /// undo step.
    @Test
    func restoresGeometryFlagChangesModifierChain() {
        let withRestore = Text("test").cardPlate(fill: .blue, restoresGeometry: true)
        let withoutRestore = Text("test").cardPlate(fill: .blue, restoresGeometry: false)
        #expect(String(describing: withRestore) != String(describing: withoutRestore))
    }
}
