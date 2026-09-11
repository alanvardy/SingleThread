# Research Questions

## Context

This is a Swift 6 iOS/watchOS app where a shared domain package
(`SingleThreadCore`) owns persistence and sync. Persisted values flow through
Apple App Group `UserDefaults` containers: a `suiteName`-scoped group suite, or
the platform-standard container. The iOS and watch apps share sync values over a
WatchConnectivity session. Focus areas: the App Group / `UserDefaults`
infrastructure, the sync service used by both apps, the watch app's launch-time
test seams, simulator tooling for iOS+watch topologies, and the project's
test-target build wiring (pbxproj, schemes, scripts, CI).

## Questions

1. **App Group suite registration mechanics** — Trace `AppGroup.swift`:
   when does `UserDefaults(suiteName:)` return nil and fall back to
   `UserDefaults.standard`, on iOS vs watchOS vs each simulator? What registers
   or would register the group suite (OS-level entitlement, build configuration,
   launch arguments, device identity)? Is there evidence — code, docs, or Apple
   platform documentation — that a watchOS target or watchOS simulator can hold
   a non-standard `UserDefaults` suite at all?

2. **Cross-container read/write paths per sync value** — For every value
   shared between the iOS and watch apps (`completionCount`, `skipCounts`,
   `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`,
   `sortOption`, `enableActionButtons`), trace each read and each write in the
   sync pipeline: which `UserDefaults` container does it use, on which platform,
   for both production paths and seed/launch-argument paths? Where does the
   `enableActionButtons` `.standard`→group migration run, and on what trigger?

3. **Launch seams and state isolation for tests** — What launch-argument seams
   exist on the watch app (`--ui-testing*` family) and the iOS app (`--seed`)?
   How do existing watch unit tests (`SingleThreadWatchTests`) and watch UI
   tests (`SingleThreadWatchUITests`) inject and isolate state — fake sessions,
   launch arguments, in-memory stores — and what machinery clears persisted
   state (e.g. `UITestingSeed.resetPersistedState`), including on which
   containers?

4. **Simulator topologies for iOS + watch interaction** — What devices are
   available for testing (`xcrun simctl list`), how does simulator pairing work
   (`simctl pair`), how does CI provision watch simulators, and is there any
   existing test that combines a phone simulator and a watch simulator in one
   process or session? What contention constraints apply (single xcodebuild
   test process, sim shutdown, orphan cleanup)?

5. **Test-target build wiring** — For a watch test target (unit and UI-test
   variants that exist today): which pbxproj objects (native targets, build
   configurations, configuration lists, scheme `TestAction` entries), which
   `-only-testing` entries in `scripts/test.sh` (including the
   `EXPECTED_TARGET_LITERALS` guard), Makefile targets, and CI matrix/cache-key
   entries reference each target — and what does adding a new target require in
   each of those places?