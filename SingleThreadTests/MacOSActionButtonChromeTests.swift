#if os(macOS)
    @testable import SingleThread
    @testable import SingleThreadCore
    import SwiftUI
    import Testing

    @MainActor
    struct MacOSActionButtonChromeTests {
        // MARK: Internal

        @Test
        func actionClusterButtonsUseControlPlateAndBorderlessChrome() {
            let view = makeContentView()
            #expect(String(describing: view.macCompleteButton).contains("SingleThreadButtonModifier"))
            #expect(String(describing: view.macCompleteButton).contains("ControlPlateModifier"))
            #expect(String(describing: view.macSkipButton).contains("SingleThreadButtonModifier"))
            #expect(String(describing: view.macSkipButton).contains("ControlPlateModifier"))
            #expect(String(describing: view.macDeleteButton).contains("SingleThreadButtonModifier"))
            #expect(String(describing: view.macDeleteButton).contains("ControlPlateModifier"))
        }

        @Test
        func actionMenuUsesBorderlessMenuStyleAndControlPlate() {
            let description = String(describing: makeContentView().macActionMenu)
            #expect(description.contains("BorderlessButtonMenuStyle"))
            #expect(description.contains("ControlPlateModifier"))
        }

        @Test
        func actionClusterDoesNotTintItsButtons() {
            // `.tint` reflects as _EnvironmentKeyWritingModifier<Optional<Color>>;
            // `.controlPlate` resolves its own fill from colorScheme, so the removed
            // green/orange/red tints must leave no Color writer behind.
            let tintMarker = "_EnvironmentKeyWritingModifier<Optional<Color>>"
            let view = makeContentView()
            #expect(!String(describing: view.macCompleteButton).contains(tintMarker))
            #expect(!String(describing: view.macActionMenu).contains(tintMarker))
            #expect(!String(describing: view.macSkipButton).contains(tintMarker))
            #expect(!String(describing: view.macDeleteButton).contains(tintMarker))
        }

        // MARK: Private

        private func makeContentView() -> ContentView {
            ContentView(viewModel: ContentViewModel(
                store: ReminderStore(loadsReminders: false),
                backgroundImage: BackgroundImageStore(),
                speechTranscriber: ReminderDictation()))
        }
    }

#endif
