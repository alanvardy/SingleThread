# Design Discussion

## Current State

The Apple Watch reminder card is built in `SingleThreadWatch/WatchReminderView.swift`.
The reminder's options menu — today only a "Refresh" action — is reachable only
through a long-press on the card's `ScrollView`:

- `WatchReminderView.swift:131-134` attaches `.onLongPressGesture { isShowingRefreshConfirmation = true }`
  to the `ScrollView` that wraps `reminderDetails`.
- `WatchReminderView.swift:135-138` presents the repo's **only** `confirmationDialog`,
  titled `"Reminder"`, holding a single `Button("Refresh") { refresh() }`.
- `@State isShowingRefreshConfirmation` (`:52`) is the driving state bool.
- A separate text `refreshButton` `Button("Refresh")` (`:119-123`) already exists for the
  empty states.
- The card's action row `actionButtons` (`:83-101`) has two icon-only `Button`s — Complete
  (`:85-91`, async) and Skip (`:93-99`, sync) — with **no** `.accessibilityLabel` /
  `.accessibilityAddTraits`, unlike their iOS/macOS equivalents
  (`ContentView.swift:202-203`, `:214-215`).

Interaction vocabulary available on watchOS SwiftUI: every tap in the codebase is a real
`Button` — **no `onTapGesture` is used anywhere** in `SingleThreadWatch/` or `SingleThread/`
(research Q1). The SDK **does** expose `onTapGesture(count:coordinateSpace:perform:)`
and `onLongPressGesture` (SwiftUI.swiftinterface:22093, 16254). Only `Button`,
`onLongPressGesture`, and `confirmationDialog` are used on watch; iOS adds
`contextMenu`/`swipeActions`/`refreshable`/`.sheet` (research Q1).

**Verification gap**: there is **no** watchOS unit/UI/interaction test target anywhere. The
watch app builds only in the full `./scripts/test.sh` pipeline and the CI `lint` job
(research Q3). The only exercisable representations are five `#Preview` blocks
(`WatchReminderView.swift:202-252`).

## Desired End State

The reminder card's options menu is revealed by a **plain tap** on the card instead of a
long-press, and the watch's interactive controls meet the same accessibility baseline as
iOS/macOS:

- The card reveals the `"Reminder"` confirmation dialog containing the "Refresh" action
  on a single tap, replacing `.onLongPressGesture` with `.onTapGesture`.
- The tap affordance is marked `.accessibilityAddTraits(.isButton)` (satisfies SwiftLint
  `accessibility_trait_for_button`).
- Icon-only Complete/Skip buttons are backfilled with `.accessibilityLabel` +
  `.accessibilityAddTraits(.isButton)` to match iOS/macOS.
- A new watch UI test target seeds interaction-level coverage: launching the watch app
  under `--ui-testing`, asserting a tap reveals the confirmation dialog, and running the
  accessibility audit.

**Verification**: the tap→dialog flow is compiler-verified (watch builds in `scripts/test.sh`
and CI lint job) and exercised by the new watch UI test target (run locally via a new
`make`/`scripts/test.sh` path, and in CI). SwiftLint `--strict` passes with no
accessibility violations.

## Patterns to Follow

- **Icon-only action buttons**: Complete/Skip use `Button { ... } label: { Label(...).labelStyle(.iconOnly) }.tint(...)`
  (`WatchReminderView.swift:85-99`); keep this shape, and replicate the iOS/macOS
  accessibility annotations (`ContentView.swift:202-203`, `:214-215`).
- **State-bool-gated dialog**: `isShowingRefreshConfirmation` + `.confirmationDialog("Reminder", isPresented:)`
  (`:135`) — keep, only change the trigger.
- **Guard + min-duration refresh**: `refresh()` (`:174-189`) stays as-is; dialog's Refresh
  button keeps deferring to it.
- **New test-target shape**: `SingleThreadUITests` shows the xctest pattern — productType
  `com.apple.product-type.bundle.ui-testing`, `TEST_TARGET_NAME`, `TEST_HOST` pointed at the
  app, a `PBXTargetDependency`, and an `#if os(iOS)` accessibility audit
  (`SingleThreadUITests/SingleThreadUITests.swift:17-40`); makefile `coverage-ui`/`ui-test`
  wire the SDK scheme + simulator. A `SingleThreadWatchUITests` target should mirror these
  (with `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = watchsimulator`, `TEST_TARGET_NAME =
  SingleThreadWatch`, and its own `#Preview`-driven launch).

## Patterns to AVOID

- **Do not** follow the watch's current silent divergence from iOS/macOS on icon-only
  accessibility (research Q4): icon-only `Label(...).labelStyle(.iconOnly)` buttons without
  `.accessibilityLabel`/traits. Neither active SwiftLint rule catches it
  (`accessibility_label_for_image` `.swiftlint.yml:40`, `accessibility_trait_for_button`
  `:41`), so it silently ships VoiceOver-unlabeled controls today — the change must backfill it.

## Design Decisions

1. **Tap affordance — plain `.onTapGesture` on the card ScrollView** (chosen 1a).
   Replace `.onLongPressGesture` (`WatchReminderView.swift:132`) with `.onTapGesture`, keeping
   the `confirmationDialog` and its single Refresh action. This is the smallest diff and
   directly delivers the concern. Requires `.accessibilityAddTraits(.isButton)` to satisfy
   `accessibility_trait_for_button`; the ScrollView container is the tap target, so the card
   reads as a button, but it is scrollable (crown-driven, so no crown/tap conflict).
2. **Dialog unchanged**: keep title `"Reminder"` and the single `Button("Refresh")`
   (chosen 2a). No widening of the menu in this change.
3. **Accessibility scope — align with iOS/macOS** (chosen 3b): add
   `.accessibilityAddTraits(.isButton)` to the new tap target, and backfill
   `.accessibilityLabel("Complete reminder")` / `.accessibilityLabel("Skip reminder")` +
   `.accessibilityAddTraits(.isButton)` on the icon-only Complete/Skip buttons, mirroring
   `ContentView.swift:202-203`, `:214-215`.
4. **Verification — seed a watch UI test target** (chosen 4b): add a `SingleThreadWatchUITests`
   XCTest bundle target that launches the watch app under `--ui-testing`, asserts a plain tap
   presents the confirmation dialog, and (where available) runs an accessibility audit.
   Thread it through `Makefile` (a `watch-ui-test` target), `scripts/test.sh` (a new step),
   and CI (a new job) so the flow is CI-guarded rather than compile-only.

## What We're NOT Doing

- Not adding `contextMenu`/`swipeActions`/`sheet`/`.refreshable` to the watch app.
- Not widening the menu beyond "Refresh" (no second items yet).
- Not touching the iOS/macOS apps or `SingleThreadCore` beyond the accessibility backfill
  (Complete/Skip live on watch side).
- Not converting watch Complete/Skip to text buttons or changing their tint/icons.
- Not running `xctrunner`-style device UI automation; the new test is simulator-level.

## Open Risks

- **`.onTapGesture` on a scrollable card**: a tap anywhere on the ScrollView surface
  (title, notes) reveals the dialog — behavior shape must be confirmed in simulator preview;
  if accidental reveals are an issue, fall back to a smaller tap region inside the card.
- **Watch UI test infra is net-new**: no existing watchOS xctest target/SD scheme wiring to
  copy wholesale; the CI watch-build step exists, but adding `SingleThreadWatchUITests`
  requires new pbxproj products, a scheme TestAction, and a new simulator-based job — the
  riskiest part of the change (CI job time, simulator availability, `--ui-testing`
  hook on the watch app).
- **`.onTapGesture` full-screen vs card hit-region** and its coordinate-space default
  `.local` (SwiftUI.swiftinterface:22093) — verify the tap target is the card HStack region,
  not the whole window.
- **Dialog not auto-dismissed**: neither trigger dismisses `confirmationDialog` after a
  refresh; kept as-is to match existing behavior.