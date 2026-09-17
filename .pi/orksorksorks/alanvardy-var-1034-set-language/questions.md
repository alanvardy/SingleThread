# Research Questions

## Context

The SingleThread iOS app lives at /Users/vardy/dev/alanvardy-var-1034-set-language
with an SPM package (SingleThreadCore), a watchOS app, a widget, and unit/UI
test targets. Relevant areas: the settings UI stack (SettingsView.swift,
InterfaceSettingsView.swift, SettingsBindings.swift, SettingsViewModel), the
core preference-store types, the localized-string infrastructure (four
.xcstrings catalogs + SharedStrings accessors), App Group persistence
(AppGroup.swift), phone-watch sync (SkippedReminderSyncService.swift,
WatchAppViewModel.swift), and the existing unit/localization test suites.

## Questions

1. Trace the end-to-end flow of an existing Interface preference (e.g.
   appearanceMode or textSize): from the Picker binding in
   InterfaceSettingsView, through SettingsBindings/SettingsViewModel and
   ContentView, into the core store type and AppGroup.defaults persistence.
   How is the macOS target handled (platform gating, any separate macOS
   surface)?

2. How is localization structured: the four .xcstrings catalogs (which
   languages, how each target registers its catalog), every String(localized:)
   call site per target, the SharedStrings typed-accessor layer, and how do
   LocalizationTests/LocalizationTestHelpers force a specific locale in tests
   (including which Foundation API parameters they pass)?

3. How do shared preferences cross the phone-watch boundary: walk one shared
   preference (e.g. enableActionButtons, showDate, sortOption) from phone UI
   to AppGroup.defaults, into the WatchConnectivity payload (PayloadKey,
   SkipSyncSession, relay), and to the watch UI (WatchAppViewModel,
   ShowDateState); note any generic mirroring mechanism and which preferences
   are synced over the wire vs. read directly from the shared suite.

4. Enumerate every locale-sensitive rendering site currently in the codebase:
   all SwiftUI Text(date, style:) usages, DateFormatter/NumberFormatter or
   date-calculation code, and any user-facing strings that bypass the
   localized catalogs (hardcoded literals in views) — across app, core,
   widget, and watch.

5. How are the settings, preference-store, and localization unit tests
   structured: SettingsViewTests, LocalizationTests, LocalizationTestHelpers,
   how store types are tested for persistence round-trips, how views receive
   injected bindings, and what platform gating or UI-test seams (--seed,
   --ui-testing launch args) exist.