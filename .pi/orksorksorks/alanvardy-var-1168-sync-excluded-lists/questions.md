# Research Questions

## Context

Focus on the shared persistence and synchronization layers of the SingleThread
repo: the App Group `UserDefaults` stores for skipped-reminder identifiers and
excluded list titles, the `ReminderStore` state and mutation flow that owns
them, the WatchConnectivity sync service and its phone/watch wiring, the
project/entitlement configuration of the app targets, and the test conventions
around persistence and sync. Also survey how refreshes, pruning, conflict
handling, and observer notifications currently behave.

## Questions

1. How are the skipped-reminder and excluded-list stores implemented (types,
   keys, load/save shape, defaulting/injection), and where are all of their
   read and write call sites?
2. How does the WatchConnectivity sync service build, push, and apply its
   payloads, and how are the phone and watch sides wired to it?
3. How does `ReminderStore` hold, filter, mutate, and persist skip/excluded
   state, and how does it notify observers when that state changes?
4. What app and extension targets exist, which entitlements and capabilities
   files do they declare, and how is that configuration represented in the
   Xcode project?
5. How are refresh, pruning, conflict resolution, and change notification
   currently handled across the App Group + WatchConnectivity path (ordering,
   last-wins, remote-apply vs local-save split)?
6. What test patterns and seams exist for persistence and sync (UserDefaults
   injection, fakes, launch-arg seams, existing suites and what they cover)?
