# Research Questions

## Context

Focus on the iOS main reminder screen of the SingleThread app: the single
reminder card rendered inside a `List` row, the swipe-to-complete /
swipe-to-skip actions attached to that row, the Settings hierarchy and how
preference toggles flow from the UI into persistence, the `SingleThreadCore`
preference-struct conventions, any existing instructional or transient
overlay/text patterns on the main screen, and the unit- and UI-test
infrastructure (Swift Testing, `--seed` / `--ui-testing` launch seams) that
covers these areas. The watch app is out of scope.

## Questions

1. **How is the iOS reminder card composed, and how are its swipe actions
   wired?** Trace `SingleThread/ReminderCardView.swift` (the VStack children,
   their order and spacing, the trailing notes block) and its row inside
   `SingleThread/ContentView.swift` (`List`, `.listRowBackground`, paddings,
   `.frame(minHeight: viewHeight)`, centered alignment). Then trace the leading
   `.swipeActions(edge: .leading)` (complete) and trailing `.swipeActions(edge:
   .trailing)` (skip) — button labels, tints, handlers, and which view-model
   methods they call. Note any row-geometry constraints that would affect
   appended card content.

2. **How does the Settings UI work, and how does a toggle edit persist?** Map
   `SettingsView` (sections and `NavigationLink` destinations), the "Interface"
   sub-screen (`InterfaceSettingsView` — its pickers/toggles and `#if os(iOS)`
   gating), and `SettingsBindings` (the `@Observable` bag: properties, init
   defaults, and how sub-views receive `@Binding`s). Trace the write path:
   `makeSettingsBag()` in `ContentView`, the `.onChange(of: bag.X)` write-backs
   into `@AppStorage` properties, and which `@AppStorage` declarations use
   `AppGroup.defaults` vs `.standard`. Note any `SettingsViewModel` side-effect
   hooks.

3. **What are the conventions for persisted preference structs in
   `SingleThreadCore`?** Compare the `Show*Preference` types
   (`ShowCompletionGlowPreference`, `ShowDatePreference`, `ShowListPreference`,
   `ShowRecurrencePreference`, `ShowAlarmsPreference`, `ShowUndatedRemindersPreference`):
   init signature (`defaults: UserDefaults = AppGroup.defaults`, `key:` defaults),
   how each resolves a missing key (nil→true vs nil→false), read/write API
   naming, and how they are injected into view models (defaulted init params,
   read at use time). Identify which are iOS-only versus synced to the watch,
   and where `AppGroup.defaults` comes from.

4. **What instructional, transient, or secondary-text UI patterns already exist
   on the main screen?** Grep for prompt / hint / onboarding / tip / dismiss /
   instructional-style UI and report what (if anything) exists. Then describe
   the closest existing analogues: the completion-glow overlay and its
   `CompletionGlow` model (transient auto-dismiss overlay, `allowsHitTesting(false)`,
   accessibility handling), the `bottomBar` footnotes (dictation error text,
   creation feedback), the styling helpers (`controlPlate`, `BackgroundFade`,
   `.font(.caption)` / `.foregroundStyle(.secondary)` text conventions), and the
   `ReminderCardView` accessibility-element (.combine) pattern.

5. **How do iOS UI tests drive the main screen and settings?** Document the
   launch-arg seams — `--seed '<json>'` + `InMemoryEventStore` +
   `resetPersistedState()`/`persistedKeys` (and what a new persisted key must
   do to be reset), `--ui-testing` (deterministic single reminder,
   `enableActionButtons` pre-set), `--ui-testing-glow` — and the flow patterns
   in `SingleThreadUITestsFlows.swift`: swipe-right / swipe-left complete/skip
   tests, `app.switches["<label>"]` + `flipToggle` settings-toggle helpers, and
   the two-launch persistence-verification pattern. Note which accessibility
   labels/identifiers tests rely on, and that `SingleThreadUITests` runs an
   accessibility audit.

6. **What are the unit-test conventions for preferences, settings UI, and the
   card?** Survey `SingleThreadTests` (Swift Testing: `@Test`, `#expect`,
   `@Suite(.serialized)`, `@MainActor`): how preference structs are tested
   (unique fixture keys, `defer` cleanup, injected `UserDefaults`,
   missing-key-default vs set round trips), how settings views and the card are
   asserted via `String(describing:)` snapshots (`SettingsViewTests`,
   `ShowDateTests`), and how view models receive injected preferences
   (`CompletionGlowTests.makeViewModel` with a pre-set
   `ShowCompletionGlowPreference`). Note where tests must be added when a new
   persisted key or a new `SettingsBindings` property is introduced.