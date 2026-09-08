# Research Findings

Branch: `alanvardy-var-692-make-buttons-more-visible`

## Q1: Mic button, recording indicator, and creation feedback icons in the bottom bar

### Findings
- All three render as **56×56 circular icon bubbles** in `SingleThread/ContentView.swift`:
  - `micButton` (ContentView.swift:489–499): `Image(systemName: "mic.fill")`, `.font(.title2)`,
    `.foregroundStyle(.white)`, `.frame(width: 56, height: 56)`, `.background(.blue, in: Circle())`,
    `.shadow(radius: 4)`. Accessibility label "Dictate reminder", trait `.isButton`.
  - `recordingIndicator` (ContentView.swift:504–513): identical geometry — `"mic.fill"`,
    `.title2`, white glyph, 56×56 frame, `.background(.red, in: Circle())`, `.shadow(radius: 4)` —
    plus `.symbolEffect(.pulse, options: .repeating)`; label "Recording".
  - `creationFeedbackView(for:)` (ContentView.swift:515–523): same 56×56 white-glyph circle,
    background color comes from `CreationFeedback.backgroundColor`
    (`SingleThread/CreationFeedback.swift:22–27`: success = `.green`, failure = `.red`);
    glyph from `systemImage` (`checkmark` / `xmark`, CreationFeedback.swift:15–20);
    `.shadow(radius: 4)`; label "Task created"/"Task creation failed".
- Layering: these are **not** overlays. They sit inside `bottomBar` (ContentView.swift:409–446),
  a `VStack(spacing: 8)` placed in a `ZStack(alignment: .bottom)` over/under the reminder
  `List` / empty-state ScrollView (ContentView.swift:342, 403). Priority order inside the stack:
  error text → creation feedback → recording indicator + live dictation text → action cluster or
  mic button. `.padding(.bottom, 16)` lifts it off the screen edge.
- Feedback lifecycle: set after a successful/failed save, cleared after a fixed 1-second sleep
  (ContentView.swift:608–612).

## Q2: Settings gear button (top-trailing overlay)

### Findings
- Rendered via `.overlay(alignment: .topTrailing)` on the root ZStack
  (SingleThread/ContentView.swift:96–112).
- Label: `Image(systemName: "gearshape")`, `.font(.title3)`, `.foregroundStyle(.secondary)`,
  `.frame(width: 44, height: 44)`, `.contentShape(Rectangle())` for the hit target
  (ContentView.swift:99–104).
- **No fill or background of its own** — no `.background`, no tint, no circle plate. It is a bare
  secondary-colored glyph floating over whatever is behind (including the photo layer).
- Positioned with `.padding(.top, 8)` / `.padding(.trailing, 12)`
  (ContentView.swift:108–109); accessibility label "Settings", trait `.isButton`.

## Q3: Appearance determination/application and scheme-adaptive patterns

### Findings
- `AppearanceMode` (`.system` / `.light` / `.dark`) is persisted as a String under key
  `"appearanceMode"` via `@AppStorage` (ContentView.swift:317–319) and read back with fallback to
  `.system` in `AppearanceMode.load(from:)` (AppearanceMode.swift:53–59).
- Mapping to UIKit: `windowOverrideStyle` → `.unspecified` / `.light` / `.dark`
  (AppearanceMode.swift:21–29).
- Application is at the **window level**: `AppDelegate.applyAppearance(_:to:)` sets
  `window.overrideUserInterfaceStyle` on every window of every connected scene
  (AppDelegate.swift:18–28). Called at launch/activation from
  `applicationDidBecomeActive` (AppDelegate.swift:42–44) and on change from ContentView's
  `.onChange(of: appearanceMode)` (ContentView.swift:139–147).
- Views read effective scheme through `@Environment(\.colorScheme)` — the only current example is
  `ReminderCardView.colorScheme` (ReminderCardView.swift:76–77).
- The `showsOverPhoto` plate pattern (ReminderCardView.swift:64–71): when true, card gets
  `padding(12)` → `.background { RoundedRectangle(cornerRadius: 10)
    .fill(colorScheme == .dark ? Color.black : Color.white) }` → `padding(-12)` (negative padding
  restores outer list metrics). White plate in light mode, black in dark mode.
  Gate upstream: `backgroundDisplayed` = backgroundEnabled && photo data exists
  (ContentView.swift:76–78), passed at ContentView.swift:352; row chrome clears with
  `.listRowBackground(backgroundDisplayed ? Color.clear : nil)` (ContentView.swift:353).
- No other control currently switches colors on scheme; mic/gear/action buttons use fixed colors.

## Q4: Background photo layer compositing and the "blue background"

### Findings
- Root ZStack paints `Color.systemBackground.ignoresSafeArea()` first
  (ContentView.swift:82), then inserts `BackgroundPhotoLayer` (iOS-only,
  ContentView.swift:83–88) before content views.
- `BackgroundPhotoLayer` (BackgroundImageStore.swift:163–191): renders only when `isEnabled` and
  image data decodes; uses `Color.clear.overlay { Image(...).resizable().scaledToFill() }` so
  `scaledToFill` cannot expand layout, `.ignoresSafeArea()`, `.opacity(opacity)`,
  `.allowsHitTesting(false)`, `.accessibilityHidden(true)` (BackgroundImageStore.swift:176–188).
- Opacity comes from `BackgroundFade.opacity(for:)` = `1 - percent/100`, clamped 0…90 fade %
  (BackgroundFade.swift:24–26; default fade 50% ⇒ opacity 0.5, BackgroundFade.swift:11).
  No animation modifiers exist on the layer — opacity is applied statically per render.
- `Color.systemBackground` maps to `UIColor.systemBackground` on iOS/watchOS,
  `NSColor.windowBackgroundColor` on macOS (Color+CrossPlatform.swift:11–19). On iOS dark mode
  this resolves to near-black; in light mode near-white — never blue.
- The only blue in the codebase's bottom bar is the **mic button itself**
  (`.background(.blue, in: Circle())`, ContentView.swift:496) plus the system default control
  tint (blue) used by any control without an explicit `.tint`. There is no explicit blue
  background modifier anywhere; a perceived "blue behind controls" can only come from the
  default accent/tint rendering of unlabeled controls or the mic button's own blue fill.

## Q5: iOS Complete and Skip action buttons

### Findings
- Constructed iOS-only in ContentView.swift:
  - `completeButton` (:450–462): `Label("Complete", systemImage: "checkmark.circle.fill")`,
    `.labelStyle(.iconOnly)`, `.frame(width: 44, height: 44)`, `.contentShape(Circle())`,
    `.tint(.green)`, labels "Complete reminder"/`.isButton`.
  - `skipButton` (:464–476): `Label("Skip", systemImage: "circle.slash")`, iconOnly, 44×44,
    `.contentShape(Circle())`, `.tint(.orange)`.
  - `actionCluster` (:478–483): `HStack(alignment: .center, spacing: 16)` ordering
    complete → mic → skip (mic sits between them, still the 56×56 blue bubble).
- Visibility conditions: `showsActionButtons` = `enableActionButtons` @AppStorage (default
  **false**, ContentView.swift:337–340) AND `store.visibleReminders.first != nil`
  (ContentView.swift:69–72). Shown only when `canDictate && showMicrophoneButton` also hold;
  otherwise plain `micButton` (bottomBar, ContentView.swift:435–443).
- Actions: Complete → `store.completeCurrentReminder()` async; Skip → `store.skipCurrentReminder()`
  synchronous (ContentView.swift:451, 465). macOS has its own separate `actionButtons` variant
  with Delete added (ContentView.swift:246–289) — not used on iOS.

## Q6: Watch app Complete/Skip styling (the stated reference)

### Findings
- `actionButtons` in SingleThreadWatch/WatchReminderView.swift:87–109: plain `HStack` of two
  `Button`s using **default borderless watch button style** (no custom buttonStyle/background):
  - Complete: `Label("Complete", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)`,
    `.tint(.green)`, labels "Complete reminder"/`.isButton` (WatchReminderView.swift:92–97).
  - Skip: `Label("Skip", systemImage: "circle.slash").labelStyle(.iconOnly)`, `.tint(.orange)`
    (WatchReminderView.swift:102–107).
- Placement: below the scrollable reminder details inside the padded VStack of
  `reminderCard(_:)` (WatchReminderView.swift:145–161). Icons inherit the tint color; no frames,
  shadows, fills, or scheme-dependent colors are applied.

## Q7: UI test coverage and deterministic seams

### Findings
- Launch seams built in `SingleThreadApp.makeStore(arguments:)` (SingleThreadApp.swift:100–134):
  - `--seed '<json>'`: parses `UITestingSeed.fromLaunchArguments` (UITestingSeed.swift:27–38),
    calls `resetPersistedState()` (clears App Group + standard defaults keys,
    UITestingSeed.swift:41–47), backs store with `InMemoryEventStore` — supports write flows
    without EventKit/TCC.
  - `--ui-testing` (iOS): builds a single "Buy groceries" reminder store with
    `authorizationStatus: .fullAccess`, `loadsReminders: false`, **and sets
    `enableActionButtons = true` in UserDefaults.standard** so the cluster renders
    (SingleThreadApp.swift:114–127).
  - `--no-reminders`: suppresses load only (SingleThreadApp.swift:128–130).
- `ActionButtonsUITests` (SingleThreadUITests/ActionButtonsUITests.swift): launches with
  `["--ui-testing"]`; finds buttons by accessibility labels `Complete reminder` /
  `Skip reminder`; taps Skip then asserts the "All Done" static text appears (:25–43);
  runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion,
  .sufficientElementDescription, .trait])` scoped to the action-button state (:56–63).
- App-wide audit `testAccessibilityAudit` (SingleThreadUITests/SingleThreadUITests.swift:30–64):
  also `--ui-testing`; on CI narrows audit to `[.sufficientElementDescription, .trait]`
  (runner-hang carve-out, SingleThreadUITests.swift:52–57).
- Flow tests use the seed seam: `SingleThreadUITestsFlows.launchApp(seedJSON:)` builds
  `launchArguments = ["--seed", json]` (SingleThreadUITestsFlows.swift:21–29); relaunch tests
  must use `--ui-testing` because seeding wipes persisted state (:158–162, 174–179).
- Appearance launch tests use `--no-reminders` and drive the Settings appearance picker by the
  label "Appearance" (SingleThreadUITestsAppearanceLaunchTests.swift:35, 62–74).
- No existing UI test asserts on visual style (colors/fills/shadows) of the bottom bar — only
  existence, tap behavior, and a11y audits.

## Cross-Cutting Observations
- Two distinct icon-bubble idioms coexist: 56×56 shadowed circles (mic/recording/feedback,
  ContentView.swift:489–523) vs. 44×44 flat tinted icon buttons (Complete/Skip,
  ContentView.swift:450–476) vs. the unadorned 44×44 gear glyph (ContentView.swift:99–106).
- Fixed colors everywhere except ReminderCardView's plate: green/orange/red/blue tints do not
  respond to `colorScheme`; the only scheme-adaptive pattern is the showsOverPhoto plate
  (ReminderCardView.swift:66–69).
- Appearance is forced at the UIWindow level, so all SwiftUI `.secondary`/semantic colors follow
  the override automatically; nothing re-renders manually.
- The photo layer is purely decorative: hit-testing disabled, a11y hidden, opacity from
  BackgroundFade (BackgroundImageStore.swift:181–187); content above it never changes color
  except the card plate path gated by `backgroundDisplayed` (ContentView.swift:76–78, 352–353).
- Test determinism flows exclusively through launch arguments (`--seed`, `--ui-testing`,
  `--no-reminders`); there is no screenshot/style assertion infrastructure today.

## Open Areas
- Where exactly a user-visible "blue background" originates cannot be pinned to an explicit
  modifier; the only blue source found is the mic button fill (ContentView.swift:496) and
  SwiftUI's default tint on untinted controls. Reproduction context (device/screenshot) would
  resolve this definitively.
- No unit/UI test covers `recordingIndicator` or `creationFeedbackView` visuals; their behavior
  is covered indirectly via dictation unit tests only.
