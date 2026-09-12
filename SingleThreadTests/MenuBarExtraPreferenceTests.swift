#if os(macOS)
    @testable import SingleThread
    import Testing

    @MainActor
    struct MenuBarExtraPreferenceTests {
        @Test
        func menuBarExtraPreferenceKeyIsStable() {
            // Pins the persistence literal: changing it silently orphans every
            // existing user's stored value.
            #expect(MenuBarExtraPreference.key == "showMenuBarExtra")
        }

        @Test
        func menuBarExtraPreferenceDefaultsToShown() {
            // An accidental flip to opt-in must fail loudly.
            #expect(MenuBarExtraPreference.defaultValue)
        }
    }
#endif
