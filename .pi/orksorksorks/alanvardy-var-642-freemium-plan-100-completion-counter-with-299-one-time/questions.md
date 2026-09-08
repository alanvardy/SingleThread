# Research Questions

## Context

This codebase is a Reminders client shipped as an iOS app, a watchOS app, and
a widget, sharing a domain-layer Swift package (`SingleThreadCore`). Research
focuses on how reminder mutations (complete/skip/delete) flow through the
shared store and each surface, how cross-surface state is persisted and
propagated, how the Xcode project configures targets/schemes/entitlements, and
how features are tested. Read the source and cite `file:line` references;
describe what exists — this is a documentation task, never propose changes.

## Questions

1. **Completion funnel.** Trace every code path that completes a reminder:
   iPhone swipe, context menu, action cluster, macOS buttons, watch buttons,
   watch relay, widget intent. Where does the EventKit save occur, what does
   the API return on success vs. failure, how do the platform branches
   (watchOS relay vs. iOS direct save) converge, and which observable hooks
   fire after a mutation on each surface?

2. **Shared persistence seam.** How does the App Group `UserDefaults`
   seam (`AppGroup.defaults`) work, and what is the store-struct convention
   (key naming, storage types, missing-key fallback) used by
   `SkippedReminderStore`, `ExcludedListStore`, `SortOptionStore`, and the
   `Show*Preference` structs? Enumerate the current keys, who reads/writes
   each (phone `@AppStorage`, watch, widget, sync service), and how the
   `--seed` UI-testing reset list keeps these keys in sync.

3. **UI action wiring and gating precedents.** How are Complete/Skip/Delete
   actions wired in `ContentView` (buttons, swipe actions, context menu), and
   what precedents exist for disabling or conditionally rendering actions
   (e.g. `showsActionButtons`, watch refresh button)? How are confirmation
   dialogs handled, where is the Settings sheet presented, and how does the
   SettingsView list group its rows?

4. **End-to-end settings propagation.** What is the full path a persisted
   preference takes from its Core store-struct → phone `@AppStorage` /
   `SettingsBindings` bag / `makeSettingsBag` / sheet write-back → watch sync
   service push payload (`PayloadKey`) → watch `Show*State` holders → widget
   reads? Which preferences are device-only (`.standard`) vs. shared
   (`AppGroup.defaults`)?

5. **StoreKit and project configuration terrain.** Does any StoreKit code,
   entitlement, or `.storekit` file exist anywhere? How are entitlements
   wired per target (app, watch, widget, macOS) in the Xcode project, how are
   Debug scheme `LaunchAction`s configured (any config-file injection or
   launch-arg precedent), and what are the deployment floors in file?

6. **Watch + widget mutation constraints.** How do the watch app and widget
   perform reminder mutations, and what per-surface constraints exist (EventKit
   read-only on watch, fresh `ReminderStore` per widget intent process)? What
   payload keys and hooks does `SkippedReminderSyncService` define for the
   complete/delete relay, and how do the phone's receive handlers in
   `AppViewModel` invoke the shared store?

7. **Test infrastructure.** How are unit tests (Swift Testing) structured for
   store logic and preference persistence (suite isolation, injected defaults,
   `@MainActor` conventions), how does the `--seed` launch-arg seam work with
   `InMemoryEventStore`, when is `--seed` used vs. the `--ui-testing` family,
   and does any StoreKit test utility (`SKTestSession`) already exist?