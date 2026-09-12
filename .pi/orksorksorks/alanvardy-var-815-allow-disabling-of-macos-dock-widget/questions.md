# Research Questions

## Context

Focus areas: the Settings UI (SettingsView and its subscreens under SingleThread/), the settings-persistence layer (UserDefaults, the App Group suite, SettingsBindings), the SingleThreadWidget WidgetKit extension target and its project wiring, platform conditional compilation (#if os(...)), and the settings/persistence test suites plus their launch-arg seams. Report facts with file:line references only; this is a read-only survey of what exists.

## Questions

1. How is the Settings menu built? Trace from the gear entry point through SettingsView's NavigationStack rows into each settings subscreen (InterfaceSettingsView and siblings): what components form a settings row and a toggle surface (NavigationLink, Form, Toggle, Picker, SettingsCaption, accessibilityIdentifier), and how are rows gated per platform (#if os(iOS) vs os(macOS))?

2. How does a boolean setting flow from a settings toggle to durable storage and back to its effect? Trace the enableActionButtons setting end to end: the SettingsBindings observable bag, the @AppStorage declaration, bindings fill and onChange write-back, ContentView/ContentViewModel usage, and how the stored value is read at the point of effect on iOS (ActionMenuGate) versus macOS (AppGroup.defaults direct read).

3. What is the UserDefaults / App Group persistence API surface, and how do phone-watch synced values round-trip? Cover: UserDefaults.standard vs AppGroup.defaults suite semantics, register/defaults, bool(forKey:), didChangeNotification, @AppStorage annotations, one-time key migration between namespaces, UITestingSeed seeding, and the payload pack/unpack path for the enableActionButtons value in SkippedReminderSyncService including the watch-side consumer.

4. How is the SingleThreadWidget extension defined and embedded? Cover NextThingWidget (which WidgetKit Widget protocol members it implements, StaticConfiguration, supportedFamilies), the WidgetBundle, and the project wiring that embeds the .appex into the iOS app (pbxproj platformFilter, SUPPORTED_PLATFORMS, scheme tool settings). Also confirm precisely whether any macOS dock or widget-gallery registration/visibility API is referenced anywhere in the repo, or whether no such reference exists.

5. What platform-conditional patterns exist across the app sources? Enumerate concrete #if os(...) usages (iOS/macOS branches, else-if chains) with file:line references, per-platform extension-file splits (ContentView+iOS.swift, ContentView+ActionMenu.swift, Color+CrossPlatform.swift), and how unit/UI tests handle platform gating (e.g. constant stubs standing in for iOS-only toggle values on macOS, #if os(...) inside test files).

6. What test coverage exists for settings toggles, persistence, and sync? Inventory: unit test files covering settings bindings, UserDefaults, key migration, action-menu gate; watch sync pipeline tests; settings UI tests and their accessibility audit; and the launch-arg seams (--ui-testing, --seed with InMemoryEventStore) used to drive settings/config in iOS UI tests.