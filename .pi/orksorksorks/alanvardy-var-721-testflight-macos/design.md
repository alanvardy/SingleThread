# Design Discussion — Testflight macOS (VAR-721)

## Current State

The macOS build path is already wired and alive — just never launched or shipped.
`SingleThread` is one physical app target spanning three SDKs
(`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `SDKROOT = auto`,
`project.pbxproj:772,770`); a `-destination platform=macOS` build produces a **native,
non-Catalyst** Mac app (`com.apple.product-type.application` :264; no `maccatalyst`
string anywhere in the project). macOS-only wiring is already in place:

- **Build settings**: `MACOSX_DEPLOYMENT_TARGET = 26.5` (:765, Release :815);
  `ENABLE_APP_SANDBOX` + `ENABLE_HARDENED_RUNTIME` (:744-745);
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = SingleThread/SingleThread.entitlements` (:739);
  `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"` (:740);
  `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = @executable_path/../Frameworks` (:763-764).
- **Entitlements**: `SingleThread/SingleThread.entitlements` adds app-sandbox,
  `device.audio-input`, `personal-information.calendars` + the shared app group
  `group.app.alanvardy.SingleThread` (vs the iOS-only `AppGroup.entitlements` with just
  the group). **No `com.apple.developer.in-app-purchases` anywhere repo-wide.**
- **Companions dropped per platform**: watch app + widget both carry
  `platformFilter = ios` on their embed + target dependencies (`project.pbxproj:15,591,597`),
  so a macOS build/archive excludes both. The widget target *declares* `macosx`
  (:1016) but has no `MACOSX_DEPLOYMENT_TARGET` and is never built for macOS.
- **Runtime surface** (research Q3): `SingleThreadApp` is a bare
  `WindowGroup { ContentView }` (`SingleThreadApp.swift:19-23`) with a macOS
  `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` (:32-34) that only bridges
  appearance (`AppDelegate.swift:62-89`). Store construction → `ReminderStore` with a
  real `EKEventStore` → `.fullAccess` auth via `requestFullAccessToReminders()` is
  platform-neutral (`AppViewModel.swift:273-278`, `ReminderStore.swift:428-440`). The
  reminder flow (view/complete/skip/delete) already works on macOS via the `actionButtons`
  cluster + `c`/`s` shortcuts (`ContentView.swift:294-334`). Absent on macOS: MenuBarExtra,
  `.commands`, notifications (100% `#if os(iOS)`, `AppViewModel.swift:4-9`), background
  photo, and the iOS `--ui-testing` seam (`AppViewModel.swift:231-272` — compiles out).
- **Verification today**: `make mac-build`/`make mac-test` (`Makefile:23-27`) and CI
  `mac-tests` (`ci.yml:294-313`) run build + `-only-testing:SingleThreadTests` unit tests;
  **every** macOS step forces `CODE_SIGNING_ALLOWED=NO` (`Makefile:24,27`,
  `scripts/test.sh:269`, `ci.yml:299`), so nothing has ever signed or launched the product.
  `scripts/test.sh`'s macOS step is **build-only** (`test.sh:267-277`); macOS UI tests are
  never selected.
- **Distribution**: zero tooling. No `xcodebuild archive`/`-exportArchive`,
  `exportOptions.plist`, fastlane/Gemfile, altool/notarytool, or ASC key anywhere
  (research Q5/Q6). `ArchiveAction = Release` + `revealArchiveInOrganizer` exists on the
  scheme only (`SingleThread.xcscheme:113-117`).

Local feasibility confirmed: this Mac runs **macOS 27.0 / Xcode 26.6**, above the 26.5
deployment target.

## Desired End State

A macOS app that (a) builds, signs, and **launches locally**, and (b) has a documented,
repeatable path to a **TestFlight-for-macOS** upload. Concretely:

1. **`make mac-run`** signs (Automatic, "Apple Development") and launches the app on this
   Mac: Reminders TCC prompt appears, reminders render, and complete / skip / delete / the
   freemium unlock all work. `make mac-build`/`mac-test` stay unsigned (fast CI gate).
2. **In-app purchase is enabled on macOS**: `in-app-purchases` capability added to
   `SingleThread/SingleThread.entitlements`; `Products.storekit`/`unlockProductID` unchanged
   (single source of truth, `EntitlementStore.swift:42`).
3. **`scripts/distribute-macos.sh` + `make mac-distribute`** runs
   `xcodebuild archive` → `-exportArchive` with a checked-in `exportOptions.plist`
   (`method = app-store-connect`, automatic signing), producing an uploadable `.pkg`.
4. **`docs/TestFlight-macOS.md`** documents the human steps (create the macOS app record on
   `app.alanvardy.SingleThread`, add the `unlimited` non-consumable product, mint an ASC API
   key, upload the `.pkg`) — the portal/secret actions an agent cannot perform.
5. **macOS unit tests enter the local full gate**: `scripts/test.sh`'s macOS step runs
   `-only-testing:SingleThreadTests` instead of build-only; the deployment-target guard
   (:119-188) keeps enforcing 26.5.

## Patterns to Follow

- **One-target-per-SDK, `#if os(...)`-gated divergence** — no separate macOS sources.
  `MacAppDelegate` lives inside `AppDelegate.swift:62-89` under `#if os(macOS)`; the
  appearance mapping is `AppearanceMode.swift:34-42`. Any new macOS code follows this
  in-place, `#if os(macOS)` pattern rather than a parallel `*Mac*` file tree.
- **Per-SDK build settings, not target forks**: entitlements/identity/runpath are
  `[sdk=macosx*]` clauses in the app target (`project.pbxproj:739-740,763-764`), never a
  second target. Adding the IAP capability edits `SingleThread.entitlements`, not a new
  entitlements file.
- **Uniform persistence across iOS+macOS**: all Core prefs land in `AppGroup.defaults`
  (`AppGroup.swift:8`); `.standard` holds device-local cosmetics
  (`AppearanceMode.swift:79-85`, `ContentView.swift:72-92`). macOS adds nothing new to the
  tiers — it just omits the iOS-gated `.standard` keys (`ContentView.swift:79-112`).
- **EventKit neutrality**: the write path, `.fullAccess` auth, and skip/excluded logic are
  already ungated (`ReminderStore.swift:147-238`); macOS differs only in entitlements/prompt.
  Keep using it as-is — no `#if os(macOS)` needed for the core flow.
- **Single source of truth for the purchase**: `EntitlementStore.unlockProductID` — never
  hard-code the id; the capability addition is an *entitlement*, not a new ID.
- **StoreKit `testingWithEntitled:` seam** for tests (`EntitlementStore.swift:34-38`) — the
  project-wide convention for driving entitlement state without a real purchase.

### Patterns NOT to follow

- Do **not** add fastlane/Gemfile — the repo has no Ruby tooling; a plain `xcodebuild`
  script matches the existing Makefile idiom (`Makefile:23-27`).
- Do **not** re-enable `UserNotifications`/UIKit on macOS for now — notifications are
  package-gated 100% iOS (`AppViewModel.swift:4-9`, `ContentView+iOS.swift:5-27`); that work
  is deferred to VAR-760.
- Do **not** add a macOS `--ui-testing` seam — the seed JSON path (`--seed`) is already
  platform-neutral (`AppViewModel.swift:231-272` vs the platform-neutral `UITestingSeed`).
- Do **not** attempt macOS UI tests in this ticket — `SingleThreadUITests` is iOS-file-gated
  and its macOS viability is unknown (research Q5); unit tests + manual smoke is the bar.

## Design Decisions

1. **Signing model**: Automatic signing (team `6NWX2DHB9Q`, unchanged). Local run drops
   `CODE_SIGNING_ALLOWED=NO`; distribution ships `exportOptions.plist`
   (`method = app-store-connect`). Rationale: least churn against the current per-SDK
   automatic configuration (`project.pbxproj:649,741`). *(Q1-A)*
2. **Distribution tooling**: `scripts/distribute-macos.sh` (archive → export) + a
   `make mac-distribute` target; upload is a documented human checklist, not a CI job.
   Rationale: no fastlane precedent; ASC app-record + API key are portal secrets the repo
   can't provision. *(Q2-A)*
3. **In-App Purchase capability**: add `com.apple.developer.in-app-purchases` to
   `SingleThread/SingleThread.entitlements`. Rationale: the freemium unlock surface
   (`PurchaseSettingsView.swift`, gate `ReminderStore.swift:144-145`) already ships on
   macOS; without the capability real purchases fail in a TestFlight build. *(Q3-A)*
4. **macOS runtime scope — minimum viable**: launch, auth prompt, reminders render,
   complete/skip/delete + unlock work; no new macOS affordances. First-class menu/`commands`/
   notifications are **deferred to VAR-760** (created as a child of VAR-721). *(Q4-A)*
5. **Verification gate**: wire `-only-testing:SingleThreadTests` into `scripts/test.sh`'s
   macOS step; keep `make mac-test`; add a manual launch smoke checklist to
   `docs/TestFlight-macOS.md`. Honest "launched by a human" bar. *(Q5-A)*
6. **Widget platform scope**: remove `macosx` from the widget target's
   `SUPPORTED_PLATFORMS` (`project.pbxproj:1016/:1047`). Rationale: macOS widget delivery is
   unverified and already excluded via `platformFilter = ios` (:591/:597); dropping `macosx`
   makes the iOS-only intent unambiguous and removes a stray macOS-widget build risk from the
   archive. *(follows Q4-A)*

## What We're NOT Doing

- **No macOS-only UX surface** — no MenuBarExtra, `.commands`/`CommandMenu`, app-menu Quit,
  or notifications (tracked in VAR-760).
- **No macOS notifications or UIKit/UIApplication usage** — stays 100% iOS-gated.
- **No macOS UI tests** — the suite is iOS-gated and unverified on a Mac destination.
- **No CI upload job / ASC API key provisioning** — upload is a documented manual step; no
  CI secret, no `xcrun altool`/notarytool in automation.
- **No fastlane / Ruby tooling** — plain `xcodebuild` scripts only.
- **No widget macOS delivery** — widget becomes iOS-only; no `MACOSX_DEPLOYMENT_TARGET` ever
  set on it.
- **No StoreKit product/ID changes** — `unlockProductID` and `Products.storekit` are
  untouched; only the macOS *capability* is added.
- **No persistence-model changes** — App Group + `.standard` split is unchanged on macOS.
- **No signing-identity change** — `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`
  stays for local dev; distribution re-signs at export via the exportOptions method.

## Open Risks

- **First signed launch is untested** — no macOS build has ever been signed/launched; the
  automatic "Apple Development" identity requires the `6NWX2DHB9Q` team's certs on this Mac
  (likely present, but unverified). If signing fails, the run-path falls back to a logged
  Xcode-managed scheme run.
- **StoreKit `.storekit` on macOS** — the launch-time StoreKit config is wired to the
  (shared) scheme `LaunchAction` (`SingleThread.xcscheme:88-92`), but its macOS resolution
  is unverified; purchase dev-testing may need a manual scheme tweak before external flight.
- **EventKit macOS prompt path** — auth uses the same code as iOS; the macOS TCC surface
  (System Settings vs in-app) differs and is not observable from the repo. The
  `personal-information.calendars` sandbox entitlement must align with the
  `NSReminders*` usage strings, else auth silently fails.
- **Archive/export is entirely novel** — no archive has ever run on this project
  (0 hits); Release config differences (+51-line siblings) and the watch/widget build
  phases (`SingleThread.xcscheme` builds the watch for Archiving) may surface first-archive
  breakage despite the `platformFilter = ios` exclusion.
- **`EXPECTED_*_LITERALS` dead constants** — `scripts/test.sh:116-117` defines but never
  references the deployment-target literal counts; the guard (:119-188) is still effective,
  but count-drift is silently ignored. Clean up or delete while touching `test.sh`.
- **macOS 26.5 target vs 27.0 local** — this Mac is ahead of the deployment target; a
  framework feature available on 27.0 might not exist on 26.5. The deployment-target guard
  keeps the floor honest, but manual smoke should run on the target OS if possible.