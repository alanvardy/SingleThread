# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `5d99584e` | drop captured BackBoardServices stall in beforeSend |
| 2 | `739d7eea` | fail-open guarantee for AppHang signature |
| 3 | `1c5f6bc2` | move BackgroundImageStore disk I/O off the MainActor |

All three commits pushed to `origin/alanvardy-var-1165-sentry-error`.

## Automated Checks

- [x] Phase 1 — `make build` succeeded (`** TEST BUILD SUCCEEDED **`).
- [x] Phase 1 — `scripts/test-one.sh SingleThreadTests/SentryScrubberTests`: `ok: 9 case(s) ran`, exit 0, no zero-match.
- [x] Phase 2 — `make build` succeeded.
- [x] Phase 2 — `scripts/test-one.sh SingleThreadTests/SentryScrubberTests`: `ok: 15 case(s) ran`, exit 0, no zero-match.
- [x] Phase 2 — `swiftformat --lint` and `swiftlint lint --strict` clean on the touched files.
- [x] Phase 3 — `make build` succeeded.
- [x] Phase 3 — `scripts/test-one.sh SingleThreadTests/BackgroundImageStoreTests`: `ok: 21 case(s) ran` (19 pre-existing + 2 new), exit 0, no zero-match.
- [x] Phase 3 — `swiftformat --lint` and `swiftlint lint --strict` clean on the touched files.

## Manual Verification Items (from the plan)

Phase 1:
- [ ] Confirm `dropsCapturedBacklightSystemStall` succeeds, i.e. `scrub` returns `nil` for the real captured client-side frame list.
- [ ] Confirm `keepsHangWithAppFrameInBlockedChain` and `keepsNonHangBacklightEvent` both return non-`nil`.

Phase 2:
- [ ] Confirm every new assertion is `scrub(event) != nil` (the event survives).
- [ ] Confirm no force-unwrap was introduced (SwiftLint bans it outside tests).

Phase 3:
- [ ] `diskWorkRunsOffMainActor` asserts `false` (the work runs off the MainActor).
- [ ] No public surface changed: grep for `refreshIfNeeded(`/`forceRefresh(` call sites (`ContentViewModel:156`, `BackgroundSettingsView:57`) and confirm they still compile unchanged.

## Deviations from plan snippets (intent preserved)

- **Phase 1**: `Stacktrace(frames:)` from the plan is not the sentry-cocoa 9.29.2 Swift name — used `SentryStacktrace(frames:registers:)`. Added a `legacy_objc_type` SwiftLint disable for the SDK-mandated `NSNumber` `Frame.inApp`, matching the existing `SentryBootstrap.swift` pattern. SwiftFormat removed trailing commas the plan's snippets contained.
- **Phase 3**: `BackgroundMetadata` and `LoadedImage` are declared `nonisolated` structs so their `Codable`/`Sendable` conformances work across the `@concurrent` executor under the default MainActor isolation. `LoadedImage.photographerURL` is `String?` (the plan's snippet declared `URL?` but passed a `String?`), converted on assignment via `.flatMap(URL.init)`. `fetchWallpaper` now calls `Self.isDecodableImage(data)`.

## Notes

- No new files, no pbxproj change (synchronized file groups), no schema migration, no new test target, no `Makefile`/`scripts/test.sh` filter entries.
- The full CI-identical gate (`./scripts/test.sh`) was intentionally not run by phase workers; it belongs to the review step.
- `DELETEME` remains an unstaged deletion in the worktree (pre-existing, must be removed before merge). Plan artifacts under `.pi/orksorksorks/` remain untracked.
