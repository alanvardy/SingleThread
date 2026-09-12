#if os(macOS)
    /// Single source of truth for the "Show in Menu Bar" preference: the
    /// `UserDefaults.standard` key and its opt-out default. Consumed by the
    /// `@AppStorage` sites in `SingleThreadApp` and `ContentView`.
    enum MenuBarExtraPreference {
        static let key = "showMenuBarExtra"
        static let defaultValue = true
    }
#endif
