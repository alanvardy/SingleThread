# Implementation Summary

Implemented all 4 phases of `plan.md` for VAR-1168 (iCloud sync for excluded
lists). Each phase was implemented by a dedicated one-phase subagent and
committed separately; the parent committed Phase 1 after that lane's 30-minute
run cap fired mid-verification (all Phase 1 code was complete; the parent
re-ran the full Phase 1 verification before committing).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `6fac0180` | walking skeleton — exclude locally, persist to iCloud, rehydrate at launch |
| 2 | `7db19a60` | live propagation — iCloud change applies without a relaunch |
| 3 | `68724087` | clear propagates — absent vs empty precedence |
| 4 | `ec301806` | hardening — degraded mode, macOS parity |

All commits are pushed to `origin/alanvardy-var-1168-sync-excluded-lists`
(`git rev-list --left-right --count` = `0 0`).

## Files added / changed (matches plan's file list)

- **New** `SingleThreadCore/Sources/SingleThreadCore/UbiquitousKeyValueStoring.swift`
- **New** `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`
- **Modified** `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
- **Modified** `SingleThread/AppViewModel.swift`
- **New** `SingleThread/App.entitlements`
- **Modified** `SingleThread/SingleThread.entitlements`
- **Modified** `SingleThread.xcodeproj/project.pbxproj` (2 iOS entries → `App.entitlements`; macosx\* + widget entries untouched)
- **Modified** `SingleThreadTests/TestFixtures.swift` (`InMemoryUbiquitousStore`)
- **New** `SingleThreadTests/ExcludedListCloudStoreTests.swift`
- **New** `SingleThreadTests/ExcludedListCloudSyncTests.swift`
- **Modified** `SingleThreadTests/ReminderStoreTests.swift`
- `SingleThread/AppGroup.entitlements` — unchanged, as planned

## Automated Checks

- [x] `make format` (clean)
- [x] `make lint` (SwiftLint --strict: 0 violations, 237 files)
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests` (7 cases)
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudSyncTests` (5 cases)
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListObserverWiringTests` / `ExcludedListCloudObserverWiringTests` (1 case)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` (39 cases)
- [x] `scripts/test-one.sh SingleThreadTests/AppViewModelSyncWiringTests` (2 cases, still green)
- [x] `make build` (TEST BUILD SUCCEEDED)
- [x] `plutil -lint SingleThread/App.entitlements SingleThread/SingleThread.entitlements`
- [x] `make mac-build` (BUILD SUCCEEDED, macOS entitlement)
- [~] `rm -rf DerivedData && make periphery` — ran; only pre-existing findings remained (see Notes)
- [~] `make mac-test` — only pre-existing failures/flakes observed (see Notes)
- [ ] Full CI-identical gate (`./scripts/test.sh`, both iPhone + iPad legs) — **deferred to the review/run-gate step** by design; left unchecked in `plan.md`.

## Deviations from `plan.md` (all necessary, scope-preserving)

1. **`AppViewModel.swift` file-length disable.** Adding the iCloud wiring pushed
   the file to 679 lines, over SwiftLint's `file_length` (650) limit, so a
   `// swiftlint:disable file_length` header was added with a rationale comment —
   the same convention `ReminderStore.swift` already uses. No logic impact.
2. **Argument order (Phase 1).** The plan's production snippet
   `ReminderStore(loadsReminders: loads, cloudStore: …)` does not compile — Swift
   requires `cloudStore:` to precede `loadsReminders:` per the declaration. The
   committed order is `cloudStore:…, loadsReminders:…`.
3. **`@MainActor` on `ExcludedListCloudSyncTests` (Phase 2).** The plan's snippet
   omitted it; `ReminderStore` is `@MainActor`, so the suite must be too.
4. **Empty-collection literals (Phases 2–3).** Plan assertions like `== []` fail
   SwiftLint `--strict` (`empty_collection_literal`); the equivalent
   `?.isEmpty == true` / `.isEmpty` forms are used.
5. **Phase 4 test correction (`unavailableStoreLoadReturnsNil`).** The plan's
   assertion `#expect(!store.seedIfAbsent(from: ["Personal"]))` is impossible: an
   unavailable store reports the key absent, so `seedIfAbsent` attempts the write
   and returns `true` (the write is then dropped). Per supervisor approval the
   assertion is `#expect(store.seedIfAbsent(from: ["Personal"]))` with a
   clarifying comment; the backing store still holds `["Work"]`, proving the
   write was dropped. Phase 4 was explicitly "no behaviour change".
6. **Phase 2 wiring test lives in its own Swift Testing type**
   (`ExcludedListCloudObserverWiringTests`), so the plan's
   `test-one.sh SingleThreadTests/ExcludedListCloudSyncTests` matches only the 3
   outer cases; the wiring suite was run by its own name. The CI gate runs the
   whole `SingleThreadTests` target, so it is covered regardless.

## Notes / observations for the reviewer

- Neither `plan.md` nor any `.pi/orksorksorks/` artifact was committed by any
  phase — they remain untracked, as required.
- `DELETEME` is deleted in the working tree but **not committed** by this step
  (plan lists `git rm DELETEME` as a manual pre-merge item). It must be handled
  before the branch merges.
- Periphery: after cleaning the shared cache
  (`~/Library/Caches/com.github.peripheryapp/DerivedData-*`, not just the
  worktree-local `DerivedData/`), the only remaining finding is
  `SingleThread/ReminderCardView.swift:74 Unused property 'swipeOffset'` — the
  documented Xcode-27 local-only false positive (projection-only `@State`,
  CI-green, pre-existing from commit `a6936c33`). Not caused by this work.
- `make mac-test` did not reproduce the plan's exact three local-only
  `EntitlementStoreTests` failures this run: `hostStoreKitIsClean` was reported
  as an "Expected Failure"; `isEntitledSurvivesStoreRecreation` and
  `initialRefreshSettlesResolvedFlag` passed. One timing flake
  (`AISortCoordinatorTests/reRanksAfterSilentFallbackClearsTheDigest`) and one
  parallel-`UserDefaults.standard` interference
  (`SettingsViewTests/showMenuBarExtraRoundTripsThroughContentView`) appeared in
  the full parallel run but both pass in isolation — pre-existing, unrelated.

## Manual Verification Items (from the plan)

### Phase 1
- [ ] Archive the iOS app for a real device (`xcodebuild -scheme SingleThread -destination 'generic/platform=iOS' archive`) — signing must accept `com.apple.developer.ubiquity-kvstore-identifier`. If it fails with a provisioning error, enable iCloud → iCloud Documents/Key-value storage on the App ID `app.alanvardy.SingleThread` in the developer portal (design's provisioning open risk) before continuing.
- [ ] `make mac-build` succeeds with the macOS entitlement.
- [ ] Simulator launch with `--seed '{"reminders":[]}'` does **not** prompt or write iCloud (cloud store is nil under the seed seam).

### Phase 2
- [ ] Two simulators signed into the same (or no) iCloud account: an exclusion toggle in Settings → Excluded Lists reaches the App Group key and the widget timeline reloads.
- [ ] Watch simulator paired to the phone still receives the exclusion (WC path unchanged).

### Phase 3
- [ ] Manual two-device check (same iCloud account): exclude a list on device A → it disappears on device B (foreground both after the change). Then clear all exclusions on device A → the list reappears on device B. If the clear does not propagate, treat the absent-vs-empty assumption as failed (design open risk) and stop.

### Phase 4
- [ ] Sign out of iCloud (or run a build whose App ID lacks the capability) and confirm the app behaves exactly as today: no crash, no new UI, exclusions still persist locally and still reach the watch.
- [ ] `git rm DELETEME` is done before this branch merges (repo rule).
- [ ] PR description states why no UI test was added: the flow is data-layer; the value is fully captured by the unit suites, and a cross-device assertion is not reachable from XCUITest.

### Full gate
- [ ] Full CI-identical gate **once**, after all phases have committed, via the `run-gate` skill: `./scripts/test.sh` green on both iPhone and iPad legs.
