# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | `e73a234` | fix: resolve pre-existing `launchApp(seedJSON:)` compile error (one-line, separate scoped commit — the base was red on `origin/main` at its own HEAD; required for every build gate) |
| 1     | `1d556ee` | Phase 1: build configuration foundation (IAP entitlement + widget iOS-only + `platformFilter = ios` on the widget embed build-file) |
| 2     | `10e7064` | Phase 2: macOS unit tests enter the local full gate (macOS `test -only-testing:SingleThreadTests` + literal-count drift checks, 20/3) |
| 3     | `65bab63` | Phase 3: local signed launch — `make mac-run` |
| 4     | `8f7c813` | Phase 4: distribution automation — `exportOptions.plist` + `scripts/distribute-macos.sh` + `make mac-distribute` |
| 5     | `3bf0b2c` | Phase 5: docs — `docs/TestFlight-macOS.md` runbook |
| —     | `8b26d8c` | ci: local-only `lib_TestingInterop` bundling for the watch UI test runner (env adaptation — see below) |
| —     | `77ffe17` | chore: check off completed automated boxes in plan.md |

## Automated Checks

- [x] Phase 1: `plutil -lint SingleThread.entitlements` OK; widget `SUPPORTED_PLATFORMS` iOS-only (app/tests/UI-tests unchanged); `make build` green; `make mac-build` green; `--unit-only` guard green
- [x] Phase 2: `bash -n scripts/test.sh` OK; `--unit-only` and `--ui-only` green with 20 + 3 literal checks; macOS step verified green
- [x] Phase 3: `make -n mac-run` echoes exactly the build + `open` commands (no `CODE_SIGNING_ALLOWED=NO`)
- [x] Phase 4: `bash -n scripts/distribute-macos.sh` OK; `plutil -lint exportOptions.plist` OK; unsigned archive **succeeds** (signed archive is blocked — see below)
- [x] Phase 5: `unlockProductID` symbol confirmed in `EntitlementStore.swift` (`app.alanvardy.SingleThread.unlimited`); all referenced `make` targets exist
- [x] **Full `./scripts/test.sh` passed end-to-end** on 2026-09-02 (`✅ All CI checks passed.`, exit 0): format → lint → build → watch build → Periphery → unit → UI → watch UI → watch unit → **macOS unit tests** (new step present)
- [x] E2E: `make format`/`make lint` green (in gate); `make build` + `make mac-build` green; `plutil -lint` both green; `bash -n` both green

## Local-Environment Adaptations (necessary, clearly-scoped)

1. **Pre-existing red base on `origin/main`**: `SingleThreadUITestsFlows.swift:675` called `launchApp(seedJSON:)` — no such label exists (`launchApp(arguments:)` / `launchSeeded(_:extra:)` are the real helpers). This is a compile error that broke `make build` and every CI-like gate *before any Phases-1–5 change*. Proven pre-existing (commit `076423d4` on main; `origin/main`'s own CI failed identically; zero diff vs main in that file). Fixed separately: `launchApp(seedJSON: seed)` → `launchSeeded(seed)`. The affected UI test (`testUnresolvedEntitlementRendersNoUpgradeButton`) passed in the full gate.

2. **`platformFilter = ios` on the widget embed build-file**: the plan asserted it already existed, but only the target-dependency carried it. Without it, the widget iOS-only change breaks `make mac-build` at a PlugIns copy step. Added (mirrors the watch embed pattern). Verified: `mac-build` green.

3. **Widget `SUPPORTED_PLATFORMS` = `"iphoneos iphonesimulator macosx"` in 6 blocks**: the plan's two line numbers (1016/1047) matched the widget configs exactly; edited only those two. App/tests/UI-tests keep `macosx` — confirmed.

4. **`lib_TestingInterop.dylib` missing from this machine's watchOS 26.5 simruntime** (`/usr/lib/swift`): the watch UI test runner crashes at launch (`Library not loaded: @rpath/lib_TestingInterop.dylib` → `Testing.framework`). CI's fresh watch sim runtime ships it (watch-ui-tests green on CI, e.g. run `33576337345`), so this is local-only. Fix: `scripts/test.sh` bundles the Xcode-side `WatchSimulator.platform` lib into the runner's Frameworks during the full gate — a no-op where the runtime already has it. The simruntime volume is read-only and passwordless sudo is unavailable, so patching the runtime itself wasn't possible.

## Deviations / Blockers

- **Stage 4 signed archive is blocked by a human/portal prerequisite (not a script bug)**: `xcodebuild archive` fails at `GatherProvisioningInputs` — *Entitlement com.apple.developer.in-app-purchases not found and could not be included in profile*. The installed Mac Team Provisioning Profile for `app.alanvardy.SingleThread` predates the Phase-1 IAP entitlement. Fix: enable **In-App Purchase** on the App ID in the developer portal, regenerate/redownload the profile (and register the team in Xcode + install a Distribution cert). This wall manifests one step earlier than the plan predicted (`archive`, not `exportArchive`) but is the same root cause. The unsigned archive succeeds, proving the script/build are sound.

## Manual Verification Items (from the plan — for the human)

- [ ] Step 1 manual: open pbxproj in Xcode — widget target has no macOS under Supported Platforms; app target still shows iPhone/iPad/Mac
- [ ] Stage 3 manual checklist (all four): run `make mac-run` and confirm (a) build/sign/open works; (b) `codesign -dv --entitlements -` shows app-sandbox, application-groups, device.audio-input, personal-information.calendars, **and** in-app-purchases; (c) first launch TCC prompt → grant → reminders load; (d) complete/skip/delete + `c`/`s` shortcuts + Settings → upgrade surface loads `Products.storekit` and unlock opens. Plus the run-macos.sh contingency only if the DerivedData path proves non-deterministic (not observed).
- [ ] Stage 4 manual: signed archive + `-exportArchive` → `build/SingleThread.pkg` (needs portal IAP capability + regenerated profile + Distribution cert first); the `.pkg` upload via Transporter/ASC is intentionally manual (ASC API key is a portal secret)
- [ ] Stage 5 manual: review `docs/TestFlight-macOS.md` — every referenced command committed/working; product id sourced from `EntitlementStore.unlockProductID`; smoke checklist maps 1:1 to Stage 3

## Notes / Observations

- No new Swift/domain code beyond the one-line pre-existing compile-error fix (`e73a234`) — that fix is a pure error repair touching a UI-test call site, and it is what makes ANY green gate possible (the branch was red before it).
- The Plan's `EXPECTED_TARGET_LITERALS=20` deviation from structure.md (16) was verified correct: 8 IPHONEOS + 6 MACOSX + 6 WATCHOS = 20.
- The Stage-4 signed-archive blocker is exactly what the Stage-5 doc's new "portal prerequisites" section now documents up front (with the observed error string), so a human isn't re-deriving it.
- PR #138 (draft) on this branch runs CI; prior phase pushes were fast-forwards, and the forced push only happened once after the initial rebase onto `origin/main`.