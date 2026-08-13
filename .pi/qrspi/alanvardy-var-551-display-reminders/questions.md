# Research Questions

## Context
Focus on how this app is structured end-to-end: its SwiftData persistence layer, the list-based SwiftUI interface, cross-platform configuration (iOS/macOS/visionOS), date and time handling, and the project's build, testing, and capability/entitlement configuration.

## Questions
1. Trace how the app's persistence layer works end-to-end: where is the SwiftData `@Model` defined, how is the `ModelContainer` configured in the app entry point, and how does the main view read and display stored records via `@Query`?
2. How does `ContentView` build its list interface — including the `NavigationViewWrapper` abstraction, toolbar items, and row rendering — and what information does each row currently show?
3. Which platforms and deployment targets does the Xcode project support, and how are platform-specific differences expressed in code (for example, `#if os(...)` conditionals)?
4. What entitlements, Info.plist permission keys, and app capabilities are currently configured in the Xcode project, and does the app request access to any system data or services?
5. How are dates and timestamps represented, stored, and formatted across the app, and what existing date- or time-based logic is present?
6. How are unit tests and SwiftUI previews structured in this project — which testing framework is used, and how do previews and tests provide a SwiftData model container?
7. How does the project's build and CI pipeline work (Makefile, `scripts/test.sh`, GitHub Actions), and what formatting and lint rules apply to new code?
