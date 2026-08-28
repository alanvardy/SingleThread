# Research Questions

## Context

Explore the watchOS companion app and the iPhone app that configures it. On
the watch, study the root reminder view, its existing overlay/dismiss
mechanisms, the state-holder objects that drive per-surface UI flags, and the
UI-testing launch-argument seam. On the iPhone and shared layer, study how
boolean user preferences are persisted, synced between phone and watch, and
surfaced in the Settings screen.

## Questions

1. How is the watch root view (`WatchReminderView`) composited — its `ZStack`
   layers, `.overlay` usage, and existing full-screen overlay (the completion
   glow)? How does that overlay handle touch passthrough (`allowsHitTesting`),
   accessibility, animation, and the Reduce Motion setting?

2. What is the pattern for a watch state-holder (`ShowXState`) + its persisted
   preference (`ShowXPreference` in `SingleThreadCore`)? Describe each file's
   structure, default/missing-key semantics, where preference keys and defaults
   are stored, and how a state-object is initialized inside `WatchAppViewModel`.

3. How does `AppGroup.defaults` resolve the backing `UserDefaults` store, and
   which flags/preferences are watch-local vs shared? Where are these writes
   and reads performed, and what is used when the App Group is unavailable?

4. How does the `SkippedReminderSyncService` propagate show-* preferences from
   phone to watch — the push/pull direction, which flags it sends vs leaves
   watch-local, and where the receive hooks are wired in `WatchAppViewModel`?

5. How is the iPhone Settings screen structured (`SettingsView`, the
   `SettingsBindings` bag, `SettingsViewModel`, and the `ReminderSettingsView`
   / `InterfaceSettingsView` sheets)? Where do preference bindings live, how is
   a new row/button added, and how does a phone-side preference reach the watch?

6. What does the watch UI-testing seam (`--ui-testing` and related launch
   arguments) seed, and how do existing watch unit/UI tests drive deterministic
   state and run the accessibility audit? Is there any existing pattern for
   resetting or forcing a first-launch condition between test runs?

7. What gestures and interactive elements does the reminder card support (tap,
   swipe, action buttons, confirmation dialogs)? How would an overlay describing
   "swipe right"/"swipe left" sit alongside the card's existing touch targets so
   it neither blocks nor is blocked by them?