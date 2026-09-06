# Design Discussion — macOS first-class UX affordances (VAR-760)

## Current State

SingleThread is a single multiplatform app target (`SDKROOT = auto`,
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, project.pbxproj:773/775)
whose macOS surface is a bare `WindowGroup`:

- **One scene, no chrome.** `SingleThreadApp.@main` body is a single
  `WindowGroup { ContentView }` (`SingleThreadApp.swift:9-10, 19-24`) with no
  `.commands`, `MenuBarExtra`, `buildMenu`, `windowStyle`, or `defaultSize`
  anywhere. macOS gets only SwiftUI's default Application/File/Edit/View/
  Window/Help menus.
- **Delegate adaptors are the only platform divergence in the App struct**:
  iOS `@UIApplicationDelegateAdaptor` (`:31-34`) vs macOS
  `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` (`:35-38`);
  `AppViewModel()` is constructed eagerly in `init()` (`:13-16`).
- **`MacAppDelegate` bridges only appearance.** `applyAppearance(_:)` sets
  `NSWindow.appearance` per window (`AppDelegate.swift:67, 72-75`) at
  launch (`:77-79`, `:87-90`) and on become-active (`:81-83`). No menus, no
  window management, no notifications.
- **All shortcuts are SwiftUI `.keyboardShortcut`s**, no `NSMenu`/
  `NSMenuItem`/`onCommand` anywhere. Complete `"c"` (`ContentView+ActionMenu.swift:105`),
  Delete `.delete` (`:122`), Skip `"s"` (`:129`, `:144`). These are
  card-scoped, not app-scoped.
- **Action surface & state.** State lives in `@MainActor @Observable`
  `ReminderStore` (`ReminderStore.swift:50-51`; `reminders :71`, `visibleReminders :147-154`);
  `ContentViewModel` (`ContentViewModel.swift:8-10`) adds UI concerns (glow
  `:145`, undo). macOS bottom-bar `actionButtons` render only when
  `visibleReminders.first != nil` (`ContentView.swift:631-635`,
  `ContentView+ActionMenu.swift:75-86`). `guard canMutate` (freemium cap 100)
  is the authoritative gate on every store action (`ReminderStore.swift:176-179`).
- **Notifications are 100% iOS-gated.** Only `import UserNotifications` is at
  `AppViewModel.swift:6` inside `#if os(iOS)` (`:4-8`); all scheduling/permission/
  cancel logic is iOS-only (`:52-146`, `:410-427`), triggered by iOS scenePhase
  hooks (`.background`→schedule, `.active`→cancel, `ContentView.swift:604-625`).
- **Appearance** uses `@AppStorage("appearanceMode")` in **standard**
  `UserDefaults` (`ContentView.swift:72-73`), not the App Group; `AppearanceMode`
  has an `appKitAppearance: NSAppearance?` mapping (`AppearanceMode.swift:34-42`)
  and `load(from:)` (`:76-85`). Written from `InterfaceSettingsView` via the
  `SettingsBindings` bag (`ContentView+Settings.swift:19`).

## Desired End State

A macOS build that feels native from the menu bar outward:

1. **`CommandMenu`** (app menu bar) exposing Complete (⌘-effective) and Skip
   for the current reminder, plus a System/Light/Dark appearance switch — wired
   to the same store actions and `appearanceMode` key as the in-window UI.
2. **App-menu polish**: a proper **About** entry (reusing the existing About
   modal from var-651) and a proper **Quit** entry, via
   `CommandGroup(replacing: .appInfo)` / `(.appTermination)`.
3. **`MenuBarExtra`** — a `.menu`-style live "next reminder" dropdown: shows
   the next due reminder (title + due info), Complete/Skip items operating on
   it, and an "Open SingleThread" item; **hidden entirely when nothing is
   due**.
4. **macOS local notifications** for due reminders via a shared, platform-
   agnostic `NotificationScheduler` in `SingleThreadCore`, replacing the
   iOS-only inline logic in `AppViewModel`; permission request + scheduling
   behave on macOS (`.alert` + `.sound`, no `.badge`).

**Verification** (from conventions): `make mac-build` / `make mac-test` plus new
unit tests for the scheduler and any new logic; the full `./scripts/test.sh`
gate passes once (macOS unit run `-only-testing:SingleThreadTests`,
`scripts/test.sh:286-292`). No macOS UI tests — verified by hand / `make mac-run`.

## Patterns to Follow

- **Inline `#if os(...)` is the norm** for UI divergence (macOS bottoms:
  `ContentView.swift:210-215` refresh overlay, `:631-635` action buttons,
  `AppDelegate.swift:62-90`); `+`-suffixed files are extension splitters, not
  platform files (`ContentView+ActionMenu.swift` internal-splits iOS/macOS,
  `:5-10`). New macOS-gated surface should follow this: a `#if os(macOS)`
  block in the App/ContentView or one small macOS-gated file.
- **Model stays platform-agnostic; UI diverges inline** (Q6 consensus). A
  `NotificationScheduler` in `SingleThreadCore` with only the import gated is
  exactly the established shape (cf. `AppearanceMode`'s per-platform mappings
  `AppearanceMode.swift:22-42`, `Color+CrossPlatform`, `SortOption+Presentation`).
- **The store is the gatekeeper** — view-level gates only choose surfaces
  (`ActionMenuGate.swift:7-11` on macOS `ContentView+ActionMenu.swift:89-93`).
  Menu commands must call `ReminderStore` methods and let `guard canMutate`
  enforce the cap; do not re-implement gating.
- **Reuse the existing action plumbing** rather than inventing parallel flows:
  Complete/Skip/Delete/Reschedule all already route through store methods
  (`ReminderStore.swift:260-263, 380-405, 296, 356`), which is what the macOS
  bottom bar calls today (`ContentView+ActionMenu.swift:96-167`).
- **Persistence discipline**: `appearanceMode` legitimately stays in `.standard`
  (`ContentView.swift:72-73`) — appearance is deliberately app-local and not
  read by widget/watch (Q5). Do **not** migrate it to `AppGroup.defaults`.
- **Testing**: unit (Swift Testing, headless `String(describing:)` assertions),
  no new test targets needed (new `.swift` files auto-discovered; `objectVersion = 77`).
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on the app target but **not**
  on `SingleThreadCore` — annotate `@MainActor` explicitly in the scheduler.
- **Pattern NOT to follow**: the current iOS-only notification blob inside
  `AppViewModel` (a ~100-line `#if os(iOS)` region mixing import, keys, and
  logic) is the anti-pattern this ticket extracts away from.

## Design Decisions

1. **MenuBarExtra style & interactivity**: `.menu`-style interactive dropdown
   (complete/skip/open items), not a `.window` strip — native look, actions in
   reach, no custom hit-target/a11y surface that can't be UI-tested on macOS.
   Hidden when `visibleReminders` is empty (no "Nothing due" item — minimal
   chrome).

2. **Action routing**: menu commands call `ReminderStore` directly via
   `AppViewModel` (not `ContentViewModel` wrappers). App-level chrome doesn't
   need `ContentViewModel`'s glow/animation concerns. Requires exposing the
   store from `AppViewModel` into the `App` scene for both `CommandMenu` and
   `MenuBarExtra`.

3. **Notification code extraction**: new `NotificationScheduler` in
   `SingleThreadCore` — platform-agnostic body (only `import UserNotifications`
   gated), owning `scheduleNotificationIfNeeded`, `cancelNotifications`,
   `requestNotificationPermissionIfNeeded`, and the `idleReminderIdentifier`
   constant. `AppViewModel` becomes a thin hook. macOS requests
   `[.alert, .sound]`; iOS keeps `.alert, .badge`.

4. **macOS scheduling trigger**: schedule on data-change + launch, cancel when
   nothing is due — hooking the existing reminder reload path (store
   reload/settle, `ReminderStore.swift:393-399`) and app launch, instead of a
   repeating timer. No iOS-style `.background` scenePhase exists on macOS.

5. **App-menu polish**: reuse the existing About modal from var-651; add
   `CommandGroup(replacing: .appInfo)` (About) and `.appTermination` (Quit).
   Appearance is a `Picker` inside `CommandMenu` bound to
   `@AppStorage("appearanceMode")`, reusing `AppearanceMode` + the existing
   `handleAppearanceMode` write path (`ContentViewModel.swift:130-135`).

6. **No new Info.plist usage strings**: `UNUserNotificationCenter` requires no
   `INFOPLIST_KEY_*` description; existing usage strings
   (`INFOPLIST_KEY_NSMicrophoneUsageDescription` / `NSRemindersUsageDescription`
   / `NSpeechRecognitionUsageDescription`, `project.pbxproj:752-754`) are
   already unqualified and land in the macOS Info.plist (Q5) — nothing to add.

## What We're NOT Doing

- **Not** investigating WidgetKit macOS viability (explicitly out of scope).
- **No macOS UI tests** — confirmed decision (var-788); macOS verified by unit
  run + `make mac-run`.
- **No `.window`-style custom strip** and no embedded strip buttons.
- **No appearance sync** to widget/watch — appearance stays `.standard`/
  app-local.
- **No new persistence keys** for menu state; reuse `appearanceMode` and the
  shared `visibleReminders` computation.
- **No repeating background timer** for notification scheduling.
- **No behavior change** to the iOS notification path — extract and rewire,
  don't alter scheduling semantics or the `--ui-testing-notifications` seam.

## Open Risks

- **Store ownership at app level** (research verbatim): the exact owner of the
  shared `ReminderStore` instance above `ContentView` (does `AppViewModel` hold
  it, and is it already exposed?) wasn't pinned by research — exposing it for
  menu access may need a small wiring change; confirm during planning.
- **macOS notification delivery under sandbox + hardened runtime**
  (`project.pbxproj:747-748`): dev/adhoc builds must be signed with the proper
  bundle identity for notifications to display reliably; local notifications
  can silently no-op from an unsigned/odd-path launch location.
- **Foreground/presentation behavior**: iOS sets no
  `UNUserNotificationCenterDelegate` today; macOS foreground presentation
  options (`.banner`/`.list`/`.sound`) may need handling to surface a
  notification while the app is active — untested ground.
- **MenuBarExtra lifetime**: the extra is a scene that can outlive the main
  window; it must observe the same `@MainActor` store instance or the strip
  will go stale.
- **⌘ shortcut collisions**: the app-menu Complete/Skip commands must not
  shadow existing card-scoped `"c"`/`"s"` shortcuts (`ContentView+ActionMenu.swift:105, 129, 144`).