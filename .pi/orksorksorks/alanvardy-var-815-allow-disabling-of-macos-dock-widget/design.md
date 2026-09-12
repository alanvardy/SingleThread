# Design Discussion

**Terminology correction (important):** the ticket says "macOS dock widget", but the surface that exists is the macOS
**menu bar extra** — the `MenuBarExtra` scene at `SingleThreadApp.swift:36-41`. Its content (`MenuBarExtraOptions`) is
what the user sees: reminder title + due date, Complete Reminder, Skip Reminder, Open SingleThread
(`MenuBarExtraOptions.swift:11-33`). There is no dock widget anywhere in the repo (research Q4), and macOS widgets
cannot live in the Dock — on macOS 26 they live on the desktop / Notification Center under *Desktop & Dock → Widgets*
([Apple support](http://support.apple.com/zh-cn/guide/mac-help-cn/mchl52be5da5/26/mac)). "Disable" therefore means
**remove the menu bar icon**. The PR description should call out the misnomer.

## Current State

- **The surface is unconditional.** `MenuBarExtra("SingleThread", systemImage: "checkmark.circle")` with
  `.menuBarExtraStyle(.menu)` (`SingleThreadApp.swift:37-41`) has no `isInserted:` argument, no stored preference, and
  no hide path exists anywhere in the tree (research Q4 / Open Areas).
- **The app is not menu-bar-only.** macOS gets a `WindowGroup` plus the extra (`SingleThreadApp.swift:15-42`) and no
  `LSUIElement` key exists in `project.pbxproj`, so the app keeps a Dock icon and a ⌘-Tab entry. Hiding the extra
  therefore cannot strand the app, and it will *not* quit it (Apple's "last extra quits menu-bar-only apps" rule does
  not apply to an app with a window scene).
- **Settings flow.** Gear button (`ContentView.swift:180-194`) → sheet (`:290-292`) → `settingsSheetWritebacks(_:)`
  builds `SettingsView` and attaches the `.onChange` write-backs (`ContentView+Settings.swift:8-39`) → bag built by
  `makeSettingsBag()` (`:45-66`; macOS branch `:57-66`). `SettingsBindings` (`SettingsBindings.swift:24`) holds plain
  in-memory values for standard-suite keys; each is written back to its `@AppStorage` property so it survives relaunch
  (comment `ContentView+Settings.swift:19-22`). App-Group keys are store-backed computed props and need no write-back.
- **Closest precedent — `enableActionButtons`:** declared with the App-Group store (`ContentView.swift:95-96`), filled
  into the macOS bag (`ContentView+Settings.swift:63`), written back **only** in the `#elseif os(macOS)` branch
  (`:26-28`), surfaced as a macOS `Toggle` (`InterfaceSettingsView.swift:85-94`) reached from the Interface row's
  `#elseif os(macOS)` case (`SettingsView.swift:50-55`).
- **Preference-type precedent:** `@AppStorage("appearanceMode")` in the App scene (`SingleThreadApp.swift:50-53`) plus
  `AppearanceMode.load(from: UserDefaults = .standard)` (`AppearanceMode.swift:77-80`).
- **Key-constant precedent:** `@AppStorage(NotificationPreference.enabledDefaultsKey)` — a non-literal `String` key is
  already accepted in this codebase (`ContentView.swift:114`).
- **Localization:** hand-maintained String Catalog `SingleThread/Resources/Localizable.xcstrings`
  (`"extractionState": "manual"`, six languages), e.g. `:4615-4633`.
- **Tests:** macOS bag + view-content suites in `SingleThreadTests/SettingsViewTests.swift:351-401`, constructing
  `InterfaceSettingsView(appearanceMode:textSize:showMicrophoneButton:enableActionButtons:viewModel:)` (5 args on
  macOS) and asserting on `String(describing: view.body)`.

## Desired End State

- macOS → Settings → Interface shows a **macOS-only** toggle **"Show in Menu Bar"** (caption
  "Show the next reminder in the menu bar."), default **on**. Toggling it off removes the menu bar item *immediately*;
  toggling it on restores it. No relaunch.
- The choice persists in `UserDefaults.standard` under `MenuBarExtraPreference.key` and is honoured on next launch.
- Because `isInserted:` is bidirectional, ⌘-dragging the icon off the menu bar writes `false` through the binding and
  persists; the Settings toggle then reads off (next time the sheet opens). Restoring requires the app window.
- **Correct when:** (a) unit tests pass for the bag default/round-trip and the macOS Interface content, (b) `make
  format` + `make lint` are clean, (c) manual macOS check: toggle off → icon disappears with no relaunch; relaunch →
  still gone; toggle on → returns; ⌘-drag off → reopened Settings shows the toggle off.

## Patterns to Follow

1. **macOS-only settings surface**: `#elseif os(macOS)` destination case (`SettingsView.swift:50-55`) and a
   `Toggle(isOn: $binding)` inside the existing `Form` (`InterfaceSettingsView.swift:85-94`). Every subscreen ends
   `.settingsSubscreenLayout()` (`SettingsView.swift:6-13`) — do not drop it.
2. **Standard-suite preference chain**: `@AppStorage(<key>)` property + plain bag value + `.onChange` write-back
   (`ContentView.swift:81-93`, `ContentView+Settings.swift:15-17`).
3. **App-scene read of a macOS preference** next to `appearanceMode` (`SingleThreadApp.swift:50-53`).
4. **Key constants over duplicated literals** (`NotificationPreference.enabledDefaultsKey`, `ContentView.swift:114`).
5. **Test style**: Swift Testing `@Test`, names **without** a `test` prefix, `#if os(macOS)` whole blocks, `.constant(…)`
   binds, `String(describing: view.body)` assertions, and **clean up the defaults key after mutating it**
   (`SettingsViewTests.swift:351-401`, cleanup `:373-374`) — unit tests share the app's defaults domain.
6. **Localization**: add both new strings to `SingleThread/Resources/Localizable.xcstrings` as `manual` entries with
   `en`, `de`, `es`, `fr`, `ja`, `zh-Hans`, mirroring `:4615-4633`.

**Do NOT follow:**

1. **`AppGroup.defaults` for this key.** The App-Group rule covers values shared with the watch (`AppGroup.swift:17-21`,
   root `AGENTS.md`); nothing else reads this flag, so App-Group storage would add silent-divergence risk (the suite
   always exists on simulator, so the two namespaces diverge undetectably) for zero consumers.
2. **Do not add the key to `SkippedReminderSyncService.PayloadKey` (`:530-…`) or `UITestingSeed.persistedKeys`
   (`:114`)** — there is no iOS/watch seam for a macOS-only preference; the watch never pushes preferences back
   (`WatchAppViewModel.swift:228-245`).
3. **Do not reach for `supportedFamilies([])` gallery hacks or a third-party `MenuBarExtraAccess` package.** `isInserted`
   is first-party; the repo adds no dependency for this, and the widget surface is out of scope.
4. **Do not switch the app to `.accessory`/`LSUIElement`** — the Dock icon is the recovery path (see What We're NOT Doing).
5. **Do not add a test-only helper** to the new preference type: Periphery runs `--strict` (`Makefile:126`,
   `scripts/test.sh:251`) and would flag a symbol no production path calls.

## Design Decisions

1. **Mechanism — `MenuBarExtra(_:systemImage:isInserted:content:)`.** First-party SwiftUI binding; `true` inserts the
   item, `false` removes it; the system also writes `false` when the user ⌘-drags it away. Live, App-Store safe, no
   private API, no new dependency ([Apple docs](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:isinserted:content:))).
2. **Storage — `UserDefaults.standard`, key `showMenuBarExtra`.** macOS-only surface, no watch/iPhone/extension
   consumer; matches `appearanceMode` (`SingleThreadApp.swift:52-53`) rather than `enableActionButtons` (App Group).
3. **Default — shown (opt-out, `defaultValue = true`).** Existing users see no change; the toggle is discoverable in
   Interface settings.
4. **Plumbing — two `@AppStorage` declarations for one key (chosen option 2A).** `SingleThreadApp` owns the reactive
   read used by `isInserted`; `ContentView` owns the settings read/write-back read, declared inside `#if os(macOS)`
   (mirroring the `#if os(iOS)`-gated declarations at `ContentView.swift:78-80, 99-110`, keeping it out of the iOS
   build so Periphery sees it used). The write-back line goes in the `#elseif os(macOS)` branch at
   `ContentView+Settings.swift:26-28` and the value into the macOS bag at `:57-66`.
5. **Toggle placement — a macOS-only `Toggle` inside `InterfaceSettingsView`**, adjacent to `showActionButtonsToggle`
   (`:85-94`), reached through the existing Interface row; no new row, no new subscreen.
6. **Key constant — `MenuBarExtraPreference`** (`key`, `defaultValue`) in a new macOS-only app-target file, consumed by
   both `@AppStorage` sites and the tests. Removes the typo/drift risk of two bare literals at the cost of ~8 lines;
   follows `NotificationPreference.enabledDefaultsKey` (`ContentView.swift:114`).
7. **Scope — menu bar item only.** `enableActionButtons`, `MenuBarExtraOptions` content, the window, activation policy,
   the widget target, and the watch are all untouched.

## What We're NOT Doing

- **Not** hiding the app's Dock icon, ⌘-Tab entry, or window (user chose 5A). That is a different feature
  (`NSApp.setActivationPolicy(.accessory)`) and would need its own recovery design — separate ticket.
- **Not** adding a "quit app" affordance, an "auto-hide when no reminder is due" rule, or any change to the extra's
  content when it *is* visible.
- **Not** adding an iOS/watch counterpart, a sync payload entry, or an App-Group migration.
- **Not** adding UI tests: there is no macOS UI-test target job in CI (`ci.yml` runs iOS UI smoke + watch UI); per the
  repo's testing policy UI tests are the exception, and the value here is unit-testable.
- **Not** touching `SingleThreadWidget` or its pbxproj wiring (`platformFilter = ios`, `SUPPORTED_PLATFORMS` without
  `macosx`).

## Open Risks

1. **Key drift** if Decision 6 is dropped in planning: the two `@AppStorage` sites in `SingleThreadApp.swift` and
   `ContentView.swift` must then keep identical literals in sync.
2. **Stale toggle inside an already-open sheet** if the icon is ⌘-dragged off while Settings is open: the bag snapshots
   the value when the sheet opens (`ContentView.swift:283-289`). Bounded and identical to existing keys' behaviour; no
   fix planned.
3. **`InterfaceSettingsView` has no defaulted initializer**, so the new binding touches its macOS preview
   (`InterfaceSettingsView.swift:129-147`) and the two macOS call sites in `SettingsViewTests.swift:383-401`.
   Compiler-enforced, so low risk — but it is real diff surface.
4. **Localization is hand-maintained**: skipping the catalog entries ships English text in the other five languages
   (acceptable fallback, but the plan should include the entries).
5. **Recovery assumes the Dock icon stays.** If a later ticket hides the Dock icon, a user with the extra off and the
   window closed has no UI path back — this design's assumption must be flagged in the PR.
6. **No automated test can prove the scene actually hides the icon** — that is framework behaviour of `isInserted`.
   Covered by the manual macOS checks in Desired End State; recorded here as `UNVALIDATED` for CI.
7. **⌘-drag persistence** relies on `@AppStorage` observing the same `UserDefaults.standard` key the binding writes. If
   planning picks a non-`@AppStorage` write path, re-verify this (it is the one behaviour this design gets "for free"
   from the framework).
