# Research Findings

Source context: repo root `SingleThread/` (git). Questions target the watchOS view layer
(`SingleThreadWatch/`), the SwiftUI view-descriptor DSL, build/test/CI for the watch app, and
accessibility/lint conventions. Line references reflect the current working tree.

---

## Q1: watchOS SwiftUI interaction & modal APIs and their usage

### Findings

- **`Button`** is the sole "tap" control used in the DSL. A tap is expressed as a real
  `Button`, not as a gesture. There is **no `onTapGesture`** anywhere in `SingleThreadWatch/`
  or `SingleThread/` (verified by grep). Buttons across the codebase:
  - `SingleThreadWatch/WatchReminderView.swift:85` — `Button` "Complete" (icon-only `Label`),
    async `Task { await store.completeCurrentReminder() }`.
  - `SingleThreadWatch/WatchReminderView.swift:93` — `Button` "Skip" (icon-only `Label`),
    synchronous `store.skipCurrentReminder()`.
  - `SingleThreadWatch/WatchReminderView.swift:120` — `Button("Refresh")` (`refreshButton`),
    `.disabled(isRefreshing)`.
  - `SingleThreadWatch/WatchReminderView.swift:136` — `Button("Refresh")` inside the
    `confirmationDialog`.
  - `SingleThread/ContentView.swift:50` — settings gear `Button` overlay (sets
    `isShowingSettings = true`).
  - `SingleThread/ContentView.swift:193`, `:205` — macOS `actionButtons` Complete/Skip
    (keyboard shortcuts "c"/"s").
  - `SingleThread/ContentView.swift:278` — "View in Reminders" inside `contextMenu`.
  - `SingleThread/ContentView.swift:290`, `:298` — Complete/Skip inside `swipeActions`.
  - `SingleThread/ContentView.swift:352` — `micButton` (dictation).
  - `SingleThread/SettingsView.swift:162` — `Button("Done")` (confirmationAction) → `dismiss()`;
    `:151` `NavigationLink` pushes `ExcludedProjectsView`.

- **`onLongPressGesture`** — the only long-press gesture in the repo, watch-only:
  `SingleThreadWatch/WatchReminderView.swift:132`. It is attached to the reminder `ScrollView`
  and only flips `@State isShowingRefreshConfirmation = true` (does not act directly).

- **`confirmationDialog`** — the only confirmation dialog in the codebase:
  `SingleThreadWatch/WatchReminderView.swift:135` — `.confirmationDialog("Reminder",
  isPresented: $isShowingRefreshConfirmation)` with a single `Button("Refresh")` action.
- **`contextMenu`** — present only in iOS:
  `SingleThread/ContentView.swift:277` — deep-link "View in Reminders" on the reminder card.
- **`.sheet(isPresented:)`** — present only:
  `SingleThread/ContentView.swift:83` — presents `SettingsView` (iOS/macOS variants).
- **`swipeActions(edge:)`** — iOS-only list-row gestures: `ContentView.swift:289`
  (`.leading` Complete), `:297` (`.trailing` Skip).
- **`refreshable`** — pull-to-refresh `ScrollView`/`List` states:
  `ContentView.swift:249`, `:262`, `:308`.
- **Unused APIs** (absent repo-wide in scope): `onTapGesture`, `fullScreenCover`,
  `popover`, `alert`. `SingleThread/ReminderCardView.swift`, `SingleThread/SingleThreadApp.swift`,
  and `SingleThreadWatch/SingleThreadWatchApp.swift` expose no interaction/modal APIs (scene
  setup only).
- `SingleThreadWidget/NextThingWidget.swift` (outside stated scope) also uses `Button(intent:)`
  at `:127`, `:135`.

---

## Q2: How `WatchReminderView.swift` composes the reminder view

### Findings
- File is 252 lines. `WatchReminderView` is a `struct` conforming to `View` (`:5`) with one
  injected `ReminderStore` (`private let store`, `:57`) and two initializers (`:9-11`, `:14-24`).
- **Body / authorization gate** (`:28-43`): wraps in a `Group`, switches on
  `store.authorizationStatus` — `.notDetermined` → `ProgressView("Requesting access…")` (`:32`);
  `.fullAccess` → `reminderContent` (`:33-34`); `default` (denied/restricted) →
  `Text("Enable Reminders access in Settings")` (`:35-37`). `.task` (`:40-42`) calls
  `await store.start()` on appear.
- **State-managed gesture handler** (state props `:49-55`): `@State isRefreshing`
  (`:51`), `@State isShowingRefreshConfirmation` (`:52`), `@AppStorage("showDate") showDate`
  (`:54-55`), `refreshMinimumDisplayDuration = 1` (`:49`). The gesture is on the card's
  `ScrollView`:
  `SingleThreadWatch/WatchReminderView.swift:132` `.onLongPressGesture {
  isShowingRefreshConfirmation = true }`; the dialog `:135` presents `Button("Refresh")`
  (`:136-138`). There is **no tap gesture** and no custom `@GestureState` — the long-press just
  flips the state-bool; Refresh is reached via the dialog.
- **Content region** (`reminderContent`, `:65-81`): a `ZStack` chooses among three states via
  `allSkipped` (`:59-61`) and `store.visibleReminders.first`: `allDoneState` (`:67-68`), else
  `reminderCard(reminder)` (`:69-70`), else `noRemindersState` (`:71-72`). Overlaid `.top`
  `ProgressView` when `isRefreshing` (`:75-79`).
- **Reminder card** (`reminderCard`, `:127-144`): `VStack(alignment: .leading, spacing: 6)`
  (`:128`) containing `ScrollView { reminderDetails(reminder) }` (`:129-131`, always scrollable
  so titles/notes never clipped — doc `:126` at) and `actionButtons` (`:141`); wrapped `.padding()`
  (`:143`). The long-press + confirmation dialog live on the `ScrollView` (`:132-139`).
- **Reminder details** (`reminderDetails`, `:146-170`): `VStack(.leading, 6)` with an
  `HStack(.firstTextBaseline, 3)` for priority marker + title (`:148-157`, marker
  `.accessibilityLabel("<level> priority")` `:153`), optional due date (`:158-162`,
  gated on `showDate`), optional notes via `ReminderNotesFormatter.format` (`:163-167`).
- **Action buttons** (`actionButtons`, `:83-101`): `HStack` with two icon-only `Button`s —
  Complete `.tint(.green)` async (`:85-91`), Skip `.tint(.orange)` sync (`:93-99`). No `VStack`
  for these; `VStack` is used only for the empty states (`:103-109`, `:111-117`).
- **Refresh flow** (`refresh()`, `:174-189`): `guard !isRefreshing` (`:175`), captures
  `clearSkipped = allSkipped` (`:176`), sets `isRefreshing = true` (`:177`) and `startedAt`
  (`:178`), spawns `Task` → `await store.reload(clearSkipped:)` (`:180`), enforces the 1-second
  min spinner via `MinimumDisplayDuration.remainingSleep(...)` (`:181-186`), clears
  `isRefreshing = false` (`:187`).
- **Previews** (`:202-252`): `mockWatchReminder` fixture (`:204-212`) + five `#Preview`s
  ("Requesting Access" `:214`, "Reminder" `:222`, "All Skipped" `:230`, "No Reminders" `:238`,
  "No Access" `:246`). These are the only exercise-able representations of the watch views.
- **Persistence / ownership**: the watch `store` is a shared `@MainActor @Observable`
  `ReminderStore` (owning `EKEventStore`) in `SingleThreadCore`; `completeCurrentReminder`,
  `skipCurrentReminder`, `reload` are the wired actions.

---

## Q3: Apple Watch app target — build, verify, and test coverage

### Findings
- **Native target**: `SingleThreadWatch` (object id `51AA3F220000000000000003`),
  `SingleThread.xcodeproj/project.pbxproj:267`. Product `SingleThreadWatch.app` (`:287`),
  `productType = "com.apple.product-type.application"` (`:288`) — standalone watchOS app, not an
  extension. Phases at `:270-274` (Sources `:271`, Frameworks `:272`, Resources `:273`); no
  dependencies (`:275-276`). Sources from synchronized folder `SingleThreadWatch`
  (`:279-281`; root group `:108`). Links local package `SingleThreadCore`
  (`:282-285`; package ref `:964-971`).
- **Build configs** (Debug `:785-811`, Release `:813-839`):
  `SDKROOT = watchos` (`:800`/`:828`), `SUPPORTED_PLATFORMS = "watchos watchsimulator"`
  (`:802`/`:830`), `WATCHOS_DEPLOYMENT_TARGET = 26.5` (`:809`/`:837`), `SWIFT_VERSION = 6.0`
  (`:806`/`:834`), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`:805`/`:833`),
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`:804`/`:832`),
  `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread.watchkitapp` (`:798`/`:826`).
  Companion app (not watch-only): `INFOPLIST_KEY_WKCompanionAppBundleIdentifier =
  app.alanvardy.SingleThread`, `INFOPLIST_KEY_WKWatchOnly = NO` (`:795-796`/`:823-824`).
- **Embedding into iOS app**: "Embed Watch Content" copy-files phase at `:50-59`,
  `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"` (`:53`), embeds `SingleThreadWatch.app` (`:56`);
  PBXBuildFile embeds with `platformFilter = ios` (`:14`). iOS target depends on watch target
  (`PBXTargetDependency`, `:456-459`; proxy `remoteInfo = SingleThreadWatch` `:38`).
- **Xcode scheme** `xcshareddata/xcschemes/SingleThreadWatch.xcscheme`: `BuildAction` builds
  `SingleThreadWatch.app` (Blueprint `51AA3F220000000000000003`); `TestAction` (`:25-31`) is
  **empty** — `shouldAutocreateTestPlan = "YES"` but no testables; `LaunchAction`/`ProfileAction`/`ArchiveAction` use Release.
- **Makefile**:
  - `WATCH_SIM := generic/platform=watchOS Simulator` (`Makefile:2`).
  - `watch-build` target (`Makefile:15-16`): `xcodebuild -scheme SingleThreadWatch
    -destination '<WATCH_SIM>' -configuration Debug -derivedDataPath '<DERIVED_DATA>' build`.
  - `swiftformat`/`swiftformat --lint` include `SingleThreadWatch/` (`:75`, `:79`).
- **scripts/test.sh**: `WATCH_SIM="generic/platform=watchOS Simulator"` (`:6`),
  `WATCH_SCHEME="SingleThreadWatch"` (`:9`). Watch build runs **only in the full pipeline**,
  not in `--unit-only`/`--ui-only` (`:98-104`): `xcodebuild -scheme "$WATCH_SCHEME"
  -destination "$WATCH_SIM" -configuration Debug -derivedDataPath "$DERIVED_DATA" build`.
  SwiftFormat/SwiftLint include `SingleThreadWatch/` (`:78`, `:83`).
- **CI** (`.github/workflows/ci.yml`): no dedicated watch test job. The watch app is built once,
  in the `lint` job: "Watch build" step (`:212-218`, 15-min timeout): `xcodebuild -scheme
  SingleThreadWatch -destination "generic/platform=watchOS Simulator" -configuration Debug
  build -showBuildTimingSummary`; SwiftLint/Format include `SingleThreadWatch/` (`:206`); cache
  key hashes `SingleThreadWatch/**` (`:34`, `:95`). `unit-tests`, `ui-tests`, `mac-tests` jobs do
  **not** build the watch app.
- **Interaction-level test coverage of watch views**: **none.** No `SingleThreadWatchTests`
  directory/target/test files exist. `SingleThreadTests` and `SingleThreadUITests` contain no
  references to `WatchReminderView` or `SingleThreadWatchApp`. The only UI surface is the five
  `#Preview` blocks in `WatchReminderView.swift` (Q2). Shared core tests guard watchOS behavior
  with `#if` but don't exercise watch UI (`SingleThreadTests/ReminderStoreTests.swift:373`,
  `EventKitStoringTests.swift:87,120,211`, `SkippedReminderSyncServiceTests.swift:1`).

---

## Q4: Accessibility & lint conventions for interactive watch controls

### Findings
- **Active SwiftLint rules** (`.swiftlint.yml` `opt_in_rules`, warning severity; CI runs
  `--strict` so warnings are errors):
  - `accessibility_label_for_image` (`:40`): fires on SwiftUI `Image(...)` initializers (incl.
    `Image(systemName:)`, `Image(decorative:)`, `Image(uiImage:)`) without sibling
    `.accessibilityLabel` or `.accessibilityHidden(true)`.
  - `accessibility_trait_for_button` (`:41`): fires on `.onTapGesture` modifiers without
    `.accessibilityAddTraits(.isButton)` or `.isLink`. **Does not** fire on `Button`/`Link`
    (trait is default) and **does not** cover `.onLongPressGesture`.
- **Automated accessibility audit**: `SingleThreadUITests/SingleThreadUITests.swift:17-40`
  (`testAccessibilityAudit`) calls `app.performAccessibilityAudit(for:
  [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` (`:32-35`) — **iOS-only**
  (`#if os(iOS)` `:31`). There is **no watchOS UI test target or accessibility audit**.
- **Interactive watch controls** (`SingleThreadWatch/WatchReminderView.swift`):
  - Complete `Button` (`:85-90`, icon-only `Label("Complete", systemImage:"checkmark.circle.fill")`) — **no accessibility annotation**.
  - Skip `Button` (`:93-98`, icon-only `Label("Skip", systemImage:"circle.slash")`) — **no annotation**.
  - Refresh buttons (`:119-123` all-done/no-reminders; `:136` in dialog) — text labels only, none needed.
  - Long-press gesture (`:131-134` on `ScrollView`) — no trait/label.
  - Only accessibility label in the whole watch app: `:153` — `.accessibilityLabel("<level>
    priority")` on the **priority marker `Text`** (non-interactive).
  - `SingleThreadWatch/` has **zero** `Image(...)`, `AsyncImage`, `.onTapGesture`,
    `.accessibilityAddTraits`, or `.accessibilityHidden` usages.
- **Do the watch action buttons satisfy the rules?** Both rules are **satisfied vacuously**:
  - `accessibility_label_for_image`: no `Image(...)` initializers exist in the watch target; the
    icon-only `Label`s use `systemImage:` string parameters which the rule does not match.
  - `accessibility_trait_for_button`: the only gesture is `.onLongPressGesture` (not covered);
    real `Button`s carry `.isButton` by default.
  So the watch app currently produces no violations under either rule.

### Convention gap (lint-clean but divergent from iOS/macOS)
- iOS/macOS explicitly annotates icon-only controls with **both** `.accessibilityLabel` and
  `.accessibilityAddTraits(.isButton)`:
  - `ContentView.swift:59-60` (settings gear), `:202-203` ("Complete reminder"),
    `:214-215` ("Skip reminder"), `:362-363` ("Dictate reminder").
- The watch `Complete`/`Skip` buttons use `.labelStyle(.iconOnly)` without an explicit
  `.accessibilityLabel`, unlike their iOS/macOS equivalents. Neither lint rule catches this
  (they don't cover `Label`/`.iconOnly`), and there is no watchOS audit — a residual risk around
  VoiceOver labeling.

---

## Cross-Cutting Observations
- **One relevant gesture** mentally anchors the change: `onLongPressGesture` exists **only** at
  `WatchReminderView.swift:132` and drives the repo's only `confirmationDialog`. No tap gesture
  exists; every tap is a `Button`. Changing long-press→tap therefore touches
  `WatchReminderView.swift` (remove `.onLongPressGesture`; a tap already exists implicitly at
  `Button("Refresh")`? — see Open Areas).
- **Watch UI is compile-only verified.** No watchOS unit/UI/interaction tests exist anywhere;
  watch build runs only in the full `./scripts/test.sh` pipeline and the CI `lint` job. Neither
  `make test` nor `make ui-test` (nor CI unit/ui/mac jobs) build the watch app.
- **Watch app borrows the iOS/macOS interaction vocabulary** but strips most of it: it uses
  `Button`, `onLongPressGesture`, `confirmationDialog` but not `contextMenu`/`swipeActions`/
  `refreshable`/`.sheet`.
- **Accessibility convention is platform-divergent**: iOS/macOS icon-only buttons get explicit
  `label + traits`; watch ones don't. Rules don't catch the gap; the iOS-only audit misses
  watchOS entirely.

## Open Areas
- **Gesture/substitute tap**: Q1/Q2 confirm there is no `onTapGesture` used today, so a
  single-tap equivalent of the long-press gesture (the ones the questions identify as
  "long-press") isn't demonstrated elsewhere in the watch code — how a plain tap should be
  expressed in the concern task is outside the observed codebase surface.
- **Label fallback**: Whether the watch icon-only `Label("Complete"/"Skip")` resolves to the
  visible text/title vs. nothing in VoiceOver is not determinable from source alone (runtime
  behavior).
- **Dialog dismissal**: The `confirmationDialog` (whether `isPresented` is rebound for auto
  dismissal after action) and `dismiss()` usage on iOS (`SettingsView.swift:162`) wasn't fully
  traced within scope.
- **Trailing detail**: The card's long-press drives the dialog with the Refresh button already
  duplicated at `:136`; the relationship between the empty-state `refreshButton` (`:120`) and
  dialog differing is existing state, not yet correlated with the intended change.