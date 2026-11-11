# Research Findings

Scope: `scripts/appstore-screenshots.sh` capture pipeline, app-side display
layout detection (incl. other branches), launch-argument / persisted-defaults
seams, wallpaper slot/manifest system, shell-script test infra, and the
physical-device (devicectl) tooling. Every claim cites `file:line` or a
commit/branch.

---

## Q1: How does `scripts/appstore-screenshots.sh` work end to end?

### Findings
- 730-line bash script; `set -euo pipefail` @131, `cd "${REPO_ROOT:-$(dirname "$0")/..}"` @133. The doc block is lines 1–128 and is what `--help` prints (via `sed`, @285).
- **Capture set** (`SCREENS` @234–242): `<wallpaper slot>:<output stem>`:
  `main-dark:1-main-dark`, `empty:2-empty-dark`, `options:3-options-light`,
  `options:4-options-reminder-dark`, `main-light:5-main-light`,
  `no-reminders:6-no-reminders-dark`. `options` appears twice on purpose (the
  reminder subscreen shares the sheet photo) @231–233.
- **Device classes** (`DEVICE_TYPES` @244–250): `iphone-6.3:iPhone 17$`
  (anchored to avoid Pro/Pro Max/17e @245–247) and
  `ipad-13:iPad Pro 13-inch \(M5\)`. Only two entries today.
- **Languages** @212: `(en zh-Hans fr de ja es)`; mapped to folders
  `1-en`…`6-es` by `language_folder` @200–210. `class_folder` @218–228 maps
  class label → `1-iphone`/`2-ipad`/`3-watch`.
- `resolve_udid()` @305–321: `simctl list devices available --json` piped to
  `python3`, filters by runtime family + device-name regex, picks highest OS
  version, prints UDID or empty.
- Output tree: `$OUT/<language_folder>/<class_folder>/<stem>.png` (`OUT=build/appstore-screenshots` @147); `dir=` built @561; `rm -rf "$OUT"` @664.
- **Capture flow** — `capture_class()` @535–595:
  `resolve_udid` @540 → skip if none @541–543 → `simctl boot` + `bootstatus -b`
  @548–549 → optional `simctl install` @550–552 → `prepare_wallpaper` @553.
  Then per language @555–591: `demo_seed` @559–560, `prime_language` @561
  (`simctl terminate` + `launch … --ui-testing --ui-testing-noop-settle
  --ui-testing-app-language "$1"`, sleep 2 @517–522), then six shots.
- **Per-shot appearance**: `simctl ui "$UDID" appearance dark|light` @564, 572,
  578, 584, 589. Each shot: `stage_slot "$label" <screen>` then `shoot`
  @565–591. `shoot()` @524–533 = terminate, sleep 1, `launch "$UDID" "$BUNDLE"
  "$@"`, sleep `SETTLE` (6) @152, `simctl io … screenshot --mask ignored "$out"`.
- **Orientation: not handled anywhere.** No `landscape`/`portrait`/`rotate`/
  `orientation` invocation exists in the script. (The string `Rotate` @114 is
  wallpaper rotation, not device rotation.) `--mask ignored` @531, 619 is the
  only display-related option.
- **Watch path** @597–653: `capture_watch` @623, `watch_set_language` @599–610
  uses `simctl spawn … defaults write -g AppleLanguages/AppleLocale` + a
  shutdown/boot reboot cycle; `watch_shot` @612–621.
- **Run section** @655–730: default classes @657–659 `(iphone-6.3 ipad-13
  watch-series11-46mm)`; clears `$OUT` @664–665; `--fetch-wallpapers` gate
  @667–670; iOS build @683–687 (`DESTINATION='generic/platform=iOS Simulator'`
  @138), watch build @689–693; class loop @694–702; watch loop @704–708;
  dimension verification @710–730.
- **Dimension verification** @710–730: globs `"$OUT"/*/*/*.png` @713; reads
  `sips -g pixelWidth -g pixelHeight` @715; accepts only
  `1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496` @716; any other
  size sets `fail=1` and exits 1 @723–726. (Two accepted sizes —
  1179×2556, 1320×2868 — are not produced by the current device table.)
- Tools invoked: `xcrun simctl` (list/boot/bootstatus/install/launch/terminate/
  io/ui/spawn/get_app_container/shutdown), `xcodebuild` @684, 690, `python3`
  @178/306/341/451/469/504, `sips` @715, coreutils.

---

## Q2: Where does the app detect the Duo outer display / fail safe?

### Findings
- **This code is NOT on the current branch (`alanvardy-var-1172-…`) and NOT on
  `origin/main`.** It exists only on the unmerged sibling branch
  `alanvardy-var-1170-increase-width-on-outer-duo-screen` (local + origin; PR
  #247, OPEN) — commits `38da945d` ("Phase 1: Duo outer portrait widens the
  reminder card end-to-end") and `e1af721f` ("Phase 2: Empty states and the
  AI-sort banner follow the same policy"). `git branch -a --contains 38da945d`
  lists only that branch plus a stale gate ref; `git merge-base --is-ancestor
  38da945d origin/main` is false.
- **Files introducing it** (on that branch): `SingleThread/DuoDisplay.swift`,
  `SingleThread/DuoOuterPortrait.swift`, `SingleThread/ChecklistLayout.swift`,
  plus tests `SingleThreadTests/{DuoDisplayTests,DuoOuterPortraitTests,
  ChecklistLayoutTests}.swift`. On the current branch these paths do not exist
  (`git ls-tree -r HEAD | grep -i duo` returns only 1166 artifacts).
- **Detection predicate** — `SingleThread/DuoDisplay.swift:4–12` (at branch
  1170): `outerPortraitMachines = ["iPhone19,4"]`; `isOuterPortrait(machine:
  isCompactWidth:isRegularHeight:) = set.contains(machine) && isCompactWidth &&
  isRegularHeight`. Machine id alone is insufficient — outer vs inner/landscape
  differ only by size class (`DuoDisplay.swift:1–3`).
- **Machine identifier bridge** — `DuoOuterPortrait.swift:10–21`: on `os(iOS)`
  reads `uname(&info).machine`; `#else` returns `""` (macOS). `context(...)`
  test seam @24–33; live `context(horizontal:vertical:)` @35–39.
- **Fail-safe** — `DuoOuterPortrait.swift:4–7` doc: "Fails safe to `.standard`:
  macOS, the simulator, unknown machines and the Duo's inner/landscape displays
  all resolve to `.standard`." On simulator `uname` reports host arch
  (`arm64`), never `iPhone19,4`; on macOS `machine == ""`. Either way
  `contains` is false → `ChecklistLayout.Context.standard`
  (`ChecklistLayout.swift:8`, `isDuoOuterPortrait: false`).
- **Layout policy** — `ChecklistLayout.swift:21–23`: `horizontalInset =
  isDuoOuterPortrait ? 20 : 40`; `maxContentWidth` @27–34 guards Duo and
  otherwise delegates to the pre-existing `CardWidth.maxContentWidth` (cap
  `min(340, w*0.6)`); Duo path caps `min(340, viewportWidth*0.8)`.
- **Wiring** — `ContentView.swift` (branch 1170) `@Environment(\.horizontalSizeClass)`
  / `(\.verticalSizeClass)` @374–377; `layoutContext` computed @160–162 calls
  `DuoOuterPortrait.context(horizontal:vertical:)`; consumed @449, 466, 498,
  519; `ContentView+iOS.swift:176` also uses `horizontalInset`.
- **Tests** (branch 1170): `DuoOuterPortraitTests.emptyMachineIsStandard`
  @31–37, `nonDuoMachineInCompactRegularIsStandard` @22–28,
  `duoMachineInRegularRegularIsStandard` @14–20; `DuoDisplayTests` @33–47
  asserts exact match (no whitespace/case tolerance).
- **Implication for a simulator capture**: because the detection keys on
  `uname` machine plus size class, and the simulator never reports `iPhone19,4`,
  the Duo outer layout cannot fire on a simulator without a new forcing seam.
  (This is a factual consequence, not a proposal.)

---

## Q3: What launch-argument / persisted-defaults seams prime app state?

### Findings
- **`LaunchArgument.swift`** (app target only): only two cases —
  `openSettings = "--ui-testing-open-settings"` @18 and
  `openSettingsReminder = "--ui-testing-open-settings-reminder"` @27; helpers
  `opensSettings(in:)` @34–38, `isPresent(_:in:)` @41–44. No appearance/
  language/orientation case.
- **`--seed '<json>'`**: `UITestingSeed.fromLaunchArguments(_:)`
  (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:58–68`);
  schema `SeedPayload` @113–183 (`reminders`, `calendars`, `excludedLists`,
  `completionCount`, `skipCounts`, `isEntitled`, `hasHidden`,
  `entitlementUnresolved`, `completionDayMarker`, `completionTodayCount`).
  `resetPersistedState()` @71–77 clears `AppGroup.defaults` +
  `UserDefaults.standard` for `persistedKeys` @88–112 — which **includes**
  `allowsLandscape` @107, `appearanceMode` @108, `textSize` @106, but **not**
  `appLanguage`. Consumed in `AppViewModel.makeStore(arguments:)`
  (`SingleThread/AppViewModel.swift:245–249`); `seededStore` @322+ writes into
  `AppGroup.defaults`.
- **`--ui-testing` family** (`AppViewModel.swift:250–321`): `--ui-testing`
  seeds one InMemoryEventStore "Buy groceries" reminder @277–317;
  `--ui-testing-noop-settle` @246, 296; `--reset-glow-preference` @266–267;
  `--reset-swipe-preference` @268–269; sets `showSwipePrompt = false`
  (`UserDefaults.standard` @271) and `enableActionButtons = true`
  (`AppGroup.defaults` @273); `--no-reminders` @321–322.
  `--ui-testing-notifications` read in `NotificationScheduler.swift:31–33`.
- **App language**: `AppLanguagePreference` (`SingleThreadCore/.../
  AppLanguagePreference.swift`), key `"appLanguage"` @19 in
  `AppGroup.defaults` @22–28; `--ui-testing-app-language <raw>` handled
  `AppViewModel.swift:274–283`.
- **Orientation**: `OrientationPreference` (`SingleThreadCore/.../
  OrientationPreference.swift`) key `"allowsLandscape"` @21 in
  `UserDefaults.standard` (not App Group) @1–8, default `true` @24–26.
  `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`
  (`SingleThread/AppDelegate.swift:51–56`) returns `.allButUpsideDown` or
  `.portrait`; `applyLock(allowsLandscape:)` @32–47; `@AppStorage("allowsLandscape")`
  mirror `ContentView.swift:84–85`.
- **Explicit finding**: **no orientation-forcing and no display-context-forcing
  launch argument exists** in `LaunchArgument.swift`, `AppViewModel`,
  `UITestingSeed`, or `appstore-screenshots.sh`. The only orientation control
  is the persisted `allowsLandscape`; the only display-context handling is
  `simctl io … screenshot --mask ignored`.
- **Appearance**: primed only via `simctl ui … appearance` in the script
  (Q1); `AppDelegate.applyAppearance(_:)` @21–29 reads `AppearanceMode.load()`
  (resettable seed key `appearanceMode`), no `--appearance` arg.
- **`-showSwipePrompt NO`** on main-card shots (`appstore-screenshots.sh:567,
  587`): a `UserDefaults` argument-domain override (`-key value` argv form),
  not a `LaunchArgument` case; rationale @50–51.
- Script's seam use: `prime_language` @517–522; per-shot seeds/args in the
  language block @555–591 (`--seed "$demo_seed"` @567, 587; `--seed
  "$ALL_DONE_SEED"` @570; `--ui-testing-open-settings` @574; `-open-settings-reminder`
  @582; `--no-reminders` @591).

---

## Q4: How are wallpaper slots / manifest defined, fetched, staged, consumed?

### Findings
- **Slot = `<device class>-<screen>`**, not per-language (`appstore-screenshots.sh:86–107`).
  `slot_names()` @331–339 iterates `DEVICE_TYPES × SCREENS` emitting
  `"$label-${screen%%:*}"`.
- **Manifest**: `MANIFEST=$WALLPAPER_DIR/manifest.json` @299/303; default dir
  `scripts/fixtures/appstore-wallpapers` @150 (committed: 10 `.jpg` +
  `manifest.json`). Format = JSON object keyed by slot, each value
  `{file, source, photographer, photographerURL, fetchedAt}` (`manifest.json:2–8`),
  written `indent=2, sort_keys=True` @424.
- **Fetch** `fetch_wallpapers()` @341–427: inline Python; per slot keeps
  existing file unless `refetch` @395–398; URL from per-slot override, `*`, or
  `WALLPAPER_API` (default `https://vardy.cc/unsplash/random` @151) @401;
  `draw()` treats the default endpoint as JSON `{url,photographer,
  photographer_url}` @373–384; redraws up to `REDRAWS=5` to avoid duplicates
  @360, 403–407; writes `<slot>.jpg` + manifest @409–421. Flags
  `--fetch-wallpapers`, `--refetch-wallpapers`, `--wallpaper-url
  <url>|<slot>=<url>`, `--wallpaper-dir` @254–291; env `BACKGROUND_IMAGE`
  @156–157.
- **Staging target**: `wallpaper_dir()` @325–329 = `simctl get_app_container
  "$UDID" "$BUNDLE" data` + `/Library/Application Support/SingleThread`.
  `stage_slot(class, screen)` @429–461 copies the manifest file to
  `background.jpg` and writes `background.json` (photographer/fetchedAt/…);
  exits 3 if slot absent, 4 if source missing. `stage_single_wallpaper()`
  @463–475 handles `BACKGROUND_IMAGE`. `prepare_wallpaper()` @477–511 called
  once per class @553 before the language loop; each shot stages its slot
  immediately before `shoot` (@565, 569, 573, 579, 585, 590). Watch the path
  does no wallpaper staging.
- **Consumer**: `SingleThread/BackgroundImageStore.swift:55` reads
  `directory/background.jpg` @83–85 and `directory/background.json` @87–89;
  default dir `Application Support/SingleThread` @215–219 (matches simctl);
  `loadStoredImage()` @159–183; `defaultMaxAge = 86400` @205 with
  `refreshIfNeeded` @108–130 pinning a staged photo; `persist` @283–296.
  `BackgroundMetadata` @26–31. Rendering `BackgroundPhotoLayer` @300+; injected
  via `AppViewModel.swift:32,66`, `ContentViewModel.swift:20,52`,
  `BackgroundSettingsView.swift:16`.

---

## Q5: What shell-script syntax/lint/test infrastructure exists?

### Findings
- **Gate** `scripts/test.sh` sources `check-warnings.sh` @5; runs
  `verify_deployment_target` + `verify_xcodebuild_wrapped` @222–223 (the latter
  greps `test.sh` for bare `xcodebuild` and fails @110–121); full pipeline:
  swiftformat, `swiftlint lint --strict`, `bash scripts/tests/warning-check/run.sh`
  @237, iOS build, watch build, periphery, UI/watch-UI/watch-unit/macOS-unit.
  Mode flags `--unit-only` @305, `--ui-only` @320.
- `scripts/check-warnings.sh` defines `WARNING_PATTERN` + allowlist @22–23 and
  `run_xcodebuild`; no `bash -n`/shellcheck.
- `scripts/tests/warning-check/run.sh` — 16+ fixtures replaying the warning
  checker, wired at `test.sh:237` and CI `.github/workflows/ci.yml:261–263`.
- **`scripts/test-run-devices.sh`** is the only bash-script harness: `bash -n
  "$SCRIPT"` @33–35; `shellcheck -S warning --exclude=SC1111 "$SCRIPT"` @37–45
  (gated on availability); extracts the two inline Python filters via `awk`
  @54–69 and replays them against `scripts/fixtures/devicectl-devices.json`;
  replays bash control flow with stubs @115–236. **Not wired into
  `scripts/test.sh`, `Makefile`, or CI** — hand-run only.
- **`scripts/appstore-screenshots.sh` has no test of any kind** — no `bash -n`,
  no shellcheck, no fixture; the only self-check is the runtime `sips`
  dimension allowlist @710–730. No `.shellcheckrc`, no shell-lint CI job.
- Makefile targets: `test` @113–114 (`test.sh --unit-only`), `ui-test` @116–117
  (`--ui-only`), `check` @131–132 (full gate), `simverify` @119–120; none run
  shellcheck/bash -n or `test-run-devices.sh`.
- Platform gating: `test.sh` runs iOS + watch + macOS legs; `warning-check` is
  shell-only; `test-run-devices.sh` targets only the iOS/watch discovery legs
  (hardware install/launch explicitly out of scope, header @1–9).

---

## Q6: How does `run-devices.sh` drive physical devices via devicectl?

### Findings
- `scripts/run-devices.sh` @1: `set -euo pipefail`. Defaults @33–45
  (`SCHEME`, `BUNDLE_ID=app.alanvardy.SingleThread`, `CONFIGURATION=Debug`,
  `RUN_WATCH=1`, `RUN_MAC=1`, `DEVICES_JSON_IN=""`); temp paths + EXIT trap
  @45–49; product paths @51–53.
- **Inventory seam**: `DEVICES_JSON_IN` @44, 58 — when set, copies a saved
  `xcrun devicectl list devices -j` JSON @62 and validates it @66; live path
  @70–73.
- **iOS device filter** (embedded Python) @84–145: `platform == "iOS"` @100;
  `deviceType in ("iPhone","iPad")` @102; **excludes non-physical**
  `reality != "physical"` @104–107; `developerModeStatus != "enabled"` is only
  a stderr note, not a skip @126; unreachable check
  `transportType is None or connection.state == "unavailable" or
  tunnelState == "unavailable"` @118 → append to unreachable log + continue
  @119–122; emits `identifier|name` @136.
- **Watch filter** @148–207 (distinct): `platform == "watchOS"` @167,
  `deviceType == "appleWatch"` @169, physical-only @173, DevMode-disabled →
  skip @176, `pairingState != "paired"` → skip @181,
  `connection.state != "connected"` → unreachable @186.
- **Zero-device gate** @212–231.
- **Per-device build** @255–286: for each device
  `xcodebuild -scheme … -destination "id=$device_id" -configuration … -derivedDataPath
  … -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`
  @262–286. Rationale @260–265: building per destination auto-registers a new
  phone (avoids `0xe8008012`).
- **Install / launch** @296–297 `xcrun devicectl device install app --device
  "$device_id" "$APP_PATH"`; @303–304 `xcrun devicectl device process launch
  --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"`.
- Watch leg variants @317–390 (generic build for unreachable-only @317–333,
  per-device + registration @341–363, `4016` tunnel hint @374–379, launch
  retry without `--activate` @389–390). macOS leg @399–427 (`CODE_SIGNING_ALLOWED=NO`
  + `open`). Summary/exit @430–463.
- **Fixture** `scripts/fixtures/devicectl-devices.json`: 10 devices; iOS
  physical `Fixture iPhone` @199–205, `Fixture iPad DevMode Off` @230–238,
  **`Fixture iPhone Duo` @261–269**; iOS simulated excluded @292–300; watch
  physical @14–115; watch simulated @137–176.
- **Harness** `scripts/test-run-devices.sh` @1–217: `bash -n` @35, shellcheck
  @38–46, filter replay @68–69, iOS assertions @77–95 (Duo emitted even with
  DevMode off), watch assertions @97–106, control-flow replay @167–217
  (including `3/3 launched` against the real fixture @207–209).
- **Simulator-vs-physical distinctions encoded**: physical gate via
  `reality == "physical"` in both filters (@107, @173); sims excluded because
  they are not devicectl install targets; iOS unreachability keyed on
  transport/tunnel @118 vs watch on pairing/connection @181, 186;
  `DEVICES_JSON_IN` enables hardware-free replay @44, 58.

---

## Cross-Cutting Observations
- **The Duo display code the ticket describes is unmerged.** Current HEAD
  (`2e5f54cb`) lacks `DuoDisplay`/`DuoOuterPortrait`/`ChecklistLayout`; they live
  only on `alanvardy-var-1170-…` (PR #247, OPEN). Any capture change that needs
  the Duo layout depends on 1170 landing / being stacked on. (`large.md` line 12
  asserts the seam "already" exists; on this checkout it does not.)
- **No iPhone Duo simulator device type exists** (`xcrun simctl list devicetypes`
  has no Duo/fold entry). The screenshot pipeline is entirely simulator-based
  (Q1), while a physical-only path exists in `run-devices.sh` (Q6). The Duo is
  a physical device (`iPhone19,4`, `Fixture iPhone Duo`) with a working
  devicectl install/launch leg.
- **The script never sets orientation** (Q1) and **no forcing launch argument
  exists** (Q3). Landscape capture and Duo-display selection are both currently
  unrepresented in code.
- **Wallpaper slots are per class × screen** and must all resolve in
  `prepare_wallpaper` (Q4); a new class would need `DEVICE_TYPES`+`SCREENS`
  entries and matching manifest slots or `prepare_wallpaper` errors (@492–509).
- **Dimension gate is a hard allowlist** (@716) that must include any new pixel
  pair or the run exits 1.
- **Shell-script test infra is thin and currently unwired**: only
  `test-run-devices.sh` does `bash -n`/shellcheck, is hand-run, and does not
  cover `appstore-screenshots.sh` (Q5).

## Open Areas
- The exact behavior of the Duo branch's `e1af721f`/`38da945d` on the
  current 1172 base is not assessed (only that the code is absent from HEAD);
  whether 1172 branches from 1170 or main is a design/planning question.
- No simulator rotation mechanism was found in the script; whether `simctl` or
  AppleScript can rotate a simulator was **not** investigated (out of the
  question's codebase scope).
- Physical-device screenshot capture (devicectl has no screenshot verb in the
  research scope) was not investigated beyond install/launch.
- Two children briefly reported `questions.md` as missing (transient read race);
  Q1's reread succeeded, all children answered the numbered questions.
