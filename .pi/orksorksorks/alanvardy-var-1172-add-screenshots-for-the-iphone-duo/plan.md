# Implementation Plan

## Overview

Extend `scripts/appstore-screenshots.sh` with an **opt-in** `iphone-duo` device
class that resolves the Duo simulator, captures each integrated display with
`simctl io … screenshot --display <id>`, and adds the four spec pixel pairs to
the hard `sips` size allowlist. Two opt-in app launch-arg seams
(`--ui-testing-force-duo-outer`, `--ui-testing-orientation landscape`) let the
screenshot harness fire the Duo outer layout and force outer landscape geometry
on the sim, without touching the production `DuoOuterPortrait` detection or its
fail-safe.

All phases are vertical slices: each ends with a runnable script that produces a
new folder of real PNGs accepted by the runtime size gate.

## Ground truth (verified this session)

- `xcrun simctl list devicetypes` has `iPhone Duo`
  (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`); the bootable device is in
  runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4` →
  `iPhone Duo 0B7A8FD4-5A93-468F-A7A1-CBBE7E76B8B5`.
- `resolve_udid "iPhone Duo$" iOS` matches it (`pattern.match` anchors the start;
  the per-worktree clone `sim-…-iphone-duo` is excluded by the `$`).
- `DuoDisplay.swift`, `DuoOuterPortrait.swift`, `ChecklistLayout.swift`,
  `DuoOuterPortraitTests.swift`, `LaunchArgumentTests.swift` are all present on
  this branch (`git ls-files` verified).
- `scripts/fixtures/appstore-wallpapers/` holds **5 unique slots per class**
  (`main-dark`, `empty`, `options`, `main-light`, `no-reminders`) = 10 `.jpg`
  today. The `SCREENS` array lists `options` twice, so a new class adds **5**
  jpgs, not 6.

## Conventions (from `conventions.md`)

- Shell: the agent command tool runs fish — write compound bodies with the
  `write` tool and run `bash /tmp/x.sh`, or one-liners via `bash -c '…'`.
- `scripts/appstore-screenshots.sh` is bash (`set -euo pipefail`); macOS ships
  **bash 3.2**, so an empty array expansion under `set -u` must use the existing
  `"${arr[@]+"${arr[@]}"}"` guard pattern (as `WALLPAPER_URLS` does).
- Unit tests: Swift Testing, `@Test`, names must not start with `test`/`testing`.
- Single test: `scripts/test-one.sh <Target/Suite>`. Lint/format: `make lint` /
  `make format`. Full gate once at the end via the `run-gate` skill.
- `scripts/appstore-screenshots.sh` has **no gate-wired test**; its only
  self-check is the runtime `sips` allowlist. The Swift seam suites are the only
  CI-visible coverage.

---

## Phase 1: Walking skeleton — folded outer portrait, end to end

Goal: `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo` boots
the Duo sim, launches with the force seam, and writes seven
`4-duo-outer-portrait/` shot sets at exactly 1398 × 2034 with the widened card.
Reuses one wallpaper slot set for all variants.

### Changes

#### 1. Add the force-outer launch argument
**File**: `SingleThread/LaunchArgument.swift`
**Action**: modify — add one case (the `isPresent(_:in:)` helper already exists).

```swift
    /// Forces the Duo outer-portrait checklist layout under the screenshot/UI
    /// harness. Production launches never pass it, so the `uname`-based
    /// detection and its fail-safe to `.standard` are untouched.
    case forceDuoOuter = "--ui-testing-force-duo-outer"
```

#### 2. Make the Duo layout forceable through the pure seam
**File**: `SingleThread/DuoOuterPortrait.swift`
**Action**: modify — add a defaulted `forceDuoOuter` parameter to the test seam
and pass the live argv check from the size-class overload.

```swift
    /// Test/launch seam: inject the machine identifier and optionally force the
    /// Duo outer context, overriding the machine + size-class predicate.
    nonisolated static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        machine: String,
        forceDuoOuter: Bool = false) -> ChecklistLayout.Context {
        ChecklistLayout.Context(
            isDuoOuterPortrait: forceDuoOuter
                || DuoDisplay.isOuterPortrait(
                    machine: machine,
                    isCompactWidth: horizontal == .compact,
                    isRegularHeight: vertical == .regular))
    }

    static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?) -> ChecklistLayout.Context {
        context(
            horizontal: horizontal,
            vertical: vertical,
            machine: machineIdentifier,
            forceDuoOuter: LaunchArgument.isPresent(.forceDuoOuter))
    }
```

`ChecklistLayout.swift` and `ContentView.swift` need **no** change — `ContentView`
already calls `DuoOuterPortrait.context(horizontal:vertical:)`.

#### 3. Cover the seam decision
**File**: `SingleThreadTests/DuoOuterPortraitTests.swift`
**Action**: modify — append one happy-path test. (`@MainActor` struct already
imports `SwiftUI`; the existing `duoMachineInCompactRegularIsDuoOuter`,
`duoMachineInRegularRegularIsStandard`, `nonDuoMachineInCompactRegularIsStandard`
and `emptyMachineIsStandard` cases remain and prove the seam stays opt-in.)

```swift
    /// Happy: the screenshot/test seam forces the Duo outer context even where
    /// `uname` reports the host arch and the size class is regular/regular.
    @Test
    func forceFlagReturnsDuoContext() {
        let context = DuoOuterPortrait.context(
            horizontal: .regular, vertical: .regular, machine: "arm64", forceDuoOuter: true)
        #expect(context == .init(isDuoOuterPortrait: true))
    }
```

#### 4. Extend the screenshot script
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify — new global, CLI case, device-type entry, `--display`
selector in `shoot`, pose helpers, a `duo_six_shots` capture helper, and a
`capture_duo` entry point dispatched from `capture_class`; allowlist gains one
pair.

**4a. Global** — next to `SETTLE` (~`:157`):

```bash
# The iPhone Duo's hinge posture. Set it in DeviceHub.app *before* the run, then
# pass the matching --duo-pose: no headless hinge API exists. One pose change
# covers all seven languages. `folded` shoots the outer panel (display 1),
# `book`/`open` the inner panel (display 3).
DUO_POSE=${DUO_POSE:-}
```

**4b. Device table** — append to `DEVICE_TYPES` (~`:250`):

```bash
  # The Duo's two integrated displays are pixel-identical to four App Store
  # spec pairs, but the Duo slot is not live in App Store Connect yet, so this
  # class is opt-in only (absent from the default class list). `$` keeps the
  # pattern off the per-worktree `sim-…-iphone-duo` clones.
  "iphone-duo:iPhone Duo$"
```

**4c. CLI** — add a `--duo-pose` case to the `while [ $# -gt 0 ]` block
(~`:291`, before `-*`):

```bash
    --duo-pose)
      DUO_POSE=$2
      case "$DUO_POSE" in
        folded | book | open) ;;
        *)
          echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
```

**4d. Pose helpers** — beside `class_folder` (~`:228`):

```bash
# iPhone Duo pose → simctl screenID and numbered output directory. The inner
# panel is regular/regular, so it renders the standard layout with no app seam.
# The four variants reuse the same six screens; `folded` emits two folders
# (portrait and forced-landscape), which is why this is not `class_folder`.
duo_display_for_pose () { # $DUO_POSE → simctl --display id
  case "$DUO_POSE" in
    folded) echo 1 ;;
    *)
      echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2
      return 1
      ;;
  esac
}

duo_folder_for_pose () { # $DUO_POSE → numbered output directory
  case "$DUO_POSE" in
    folded) echo "4-duo-outer-portrait" ;;
    *)
      echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2
      return 1
      ;;
  esac
}
```

**4e. `shoot` gains an optional leading `--display <id>`** (~`:524`):

```bash
shoot () { # $1 = output path, then optional `--display <id>`, rest = launch arguments
  local out=$1
  shift
  local display=()
  if [ "${1:-}" = "--display" ]; then
    display=(--display "$2")
    shift 2
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored \
    "${display[@]+"${display[@]}"}" "$out" >/dev/null
  echo "    $(basename "$(dirname "$out")")/$(basename "$out")"
}
```

Existing call sites in `capture_class` pass no `--display`, so they are
unaffected. The `"${display[@]+…}"` guard is required: macOS bash 3.2 + `set -u`
errors on a bare empty-array expansion.

**4f. `duo_six_shots`** — new helper in the capture section, after `shoot`.
`$language`/`$demo_seed` are set by `capture_duo` and visible via bash dynamic
scope (same pattern `capture_class` uses with `shoot`):

```bash
duo_six_shots () { # $1 = output dir, $2 = display id, rest = extra launch args
  local dir=$1
  local display=$2
  shift 2
  local extra=("$@")
  mkdir -p "$dir"

  xcrun simctl ui "$UDID" appearance dark
  stage_slot iphone-duo main-dark
  shoot "$dir/1-main-dark.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --seed "$demo_seed" --ui-testing-noop-settle -showSwipePrompt NO

  stage_slot iphone-duo empty
  shoot "$dir/2-empty-dark.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --seed "$ALL_DONE_SEED"

  xcrun simctl ui "$UDID" appearance light
  stage_slot iphone-duo options
  shoot "$dir/3-options-light.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --ui-testing --ui-testing-noop-settle --ui-testing-app-language "$language" \
    --ui-testing-open-settings

  xcrun simctl ui "$UDID" appearance dark
  stage_slot iphone-duo options
  shoot "$dir/4-options-reminder-dark.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --ui-testing --ui-testing-noop-settle --ui-testing-app-language "$language" \
    --ui-testing-open-settings-reminder

  xcrun simctl ui "$UDID" appearance light
  stage_slot iphone-duo main-light
  shoot "$dir/5-main-light.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --seed "$demo_seed" --ui-testing-noop-settle -showSwipePrompt NO

  xcrun simctl ui "$UDID" appearance dark
  stage_slot iphone-duo no-reminders
  shoot "$dir/6-no-reminders-dark.png" --display "$display" "${extra[@]+"${extra[@]}"}" \
    --no-reminders
}
```

**4g. `capture_duo`** — new entry point, after `capture_class`:

```bash
capture_duo () { # $1 = device type regex; pose taken from $DUO_POSE
  local pattern=$1
  local udid display folder
  udid=$(resolve_udid "$pattern" iOS)
  if [ -z "$udid" ]; then
    echo "!! no available simulator for '$pattern' — skipping iphone-duo" >&2
    return 1
  fi
  display=$(duo_display_for_pose)
  folder=$(duo_folder_for_pose)

  echo "==> iphone-duo ($pattern, pose '$DUO_POSE', display $display)"
  UDID=$udid
  LABEL=iphone-duo
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  if [ "$INSTALL" -eq 1 ]; then
    xcrun simctl install "$UDID" "$APP"
  fi
  prepare_wallpaper

  # The force seam is for the outer panel only; the inner panel is
  # regular/regular and must keep the standard layout.
  local force_args=()
  if [ "$DUO_POSE" = folded ]; then
    force_args=(--ui-testing-force-duo-outer)
  fi

  for language in "${LANGUAGES[@]}"; do
    echo "  -> $language"
    demo_seed=$(demo_reminder_seed "$language")
    prime_language "$language"
    duo_six_shots "$OUT/$(language_folder "$language")/$folder" "$display" \
      "${force_args[@]+"${force_args[@]}"}"
  done

  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
```

**4h. Dispatch** — at the top of `capture_class` (~`:535`):

```bash
capture_class () { # $1 = class label, $2 = device type regex
  local label=$1
  local pattern=$2
  if [ "$label" = iphone-duo ]; then
    capture_duo "$pattern"
    return
  fi
  local udid dir
  …
```

**4i. Size allowlist** — extend the `case` (~`:716`):

```bash
    1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496 | 1398x2034) ;;
```

#### 5. Fetch and commit the Duo wallpaper slots
**Files**: `scripts/fixtures/appstore-wallpapers/iphone-duo-*.jpg` (5 new) +
`scripts/fixtures/appstore-wallpapers/manifest.json`
**Action**: create/modify — the Duo class reuses the same five slot names, so
five new photos and five manifest entries are required or `prepare_wallpaper`
for `iphone-duo` fails.

Run once (needs network; keeps the ten existing photos):

```bash
bash scripts/appstore-screenshots.sh --fetch-wallpapers --duo-pose folded iphone-duo
```

Expected new files: `iphone-duo-main-dark.jpg`, `iphone-duo-empty.jpg`,
`iphone-duo-options.jpg`, `iphone-duo-main-light.jpg`,
`iphone-duo-no-reminders.jpg`. Verify all five resolve:

```bash
python3 -c "import json;m=json.load(open('scripts/fixtures/appstore-wallpapers/manifest.json'));print(sorted(k for k in m if k.startswith('iphone-duo')))"
```

If the API is unreachable, fall back to
`bash scripts/appstore-screenshots.sh --fetch-wallpapers --wallpaper-url iphone-duo-main-dark=<url> …`
per slot, or copy existing photos to the new slot names and add manifest entries
by hand (shape: `{file, source, photographer, photographerURL, fetchedAt}`).

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` passes
      (includes the new `forceFlagReturnsDuoContext`).
- [x] `bash -n scripts/appstore-screenshots.sh` exits 0.
- [x] `make format && make lint` clean (SwiftFormat may reorder the new
      `LaunchArgument` case — copy `organizeDeclarations` output).
#### Manual
- [ ] In Device Hub, set the Duo to **folded**, then run
      `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo`.
- [ ] The run reports `7×6 screenshots, every size accepted` and every file
      under `build/appstore-screenshots/*/4-duo-outer-portrait/` is 1398 × 2034
      (`for f in build/appstore-screenshots/*/4-duo-outer-portrait/*.png; do sips -g pixelWidth -g pixelHeight "$f"; done`).
- [ ] `1-main-dark.png` shows the **widened** Duo card (gutter 20, cap
      `min(340, w*0.8)`), not the standard 40-inset card.
- [ ] `git status` shows exactly the 5 new `iphone-duo-*.jpg` + modified
      `manifest.json` under `scripts/fixtures/appstore-wallpapers/`.

---

## Phase 2: Folded outer landscape, end to end

Goal: the same `--duo-pose folded` run also emits
`5-duo-outer-landscape/` at 2034 × 1398, by launching the app with
`--ui-testing-orientation landscape` and shooting display 1 again.

### Changes

#### 1. Add the orientation launch argument + parser
**File**: `SingleThread/LaunchArgument.swift`
**Action**: modify — one new case and one parser.

```swift
    /// Forces the device orientation for the screenshot harness. The value is
    /// the next argv token: `portrait` or `landscape`. Production launches never
    /// pass it, so shipping orientation follows `allowsLandscape` alone.
    case orientation = "--ui-testing-orientation"

    /// The value following ``orientation``, or `nil` when the flag is absent or
    /// has no following token.
    static func orientationValue(
        in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: orientation.rawValue),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
```

#### 2. Apply the forced orientation at launch
**File**: `SingleThread/AppDelegate.swift`
**Action**: modify — add a static helper and call it from
`applicationDidBecomeActive` (the scene/window exists by then; a
`didFinishLaunching` call would have no scene to update).

```swift
        /// Forces landscape when the screenshot harness passes
        /// `--ui-testing-orientation landscape`. A no-op for every production
        /// launch. Uses an explicit `.landscape` mask: ``applyLock`` uses
        /// `.allButUpsideDown`, which does not force a rotation.
        static func applyForcedOrientationIfNeeded() {
            guard LaunchArgument.orientationValue() == "landscape" else { return }
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let controller = scene.keyWindow?.rootViewController
            else { return }

            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                print("Forced orientation request failed: \(error.localizedDescription)")
            }
        }
```

Change the existing delegate method:

```swift
        func applicationDidBecomeActive(_: UIApplication) {
            print("SimVerify: app active")
            Self.applyAppearance(AppearanceMode.load())
            Self.applyForcedOrientationIfNeeded()
        }
```

(`supportedInterfaceOrientationsFor` still returns `.allButUpsideDown` because
`allowsLandscape` defaults to `true` and the `--seed` reset leaves the key
absent — landscape rotations are permitted.)

#### 3. Parser tests
**File**: `SingleThreadTests/LaunchArgumentTests.swift`
**Action**: modify — append happy + sad cases to the `@MainActor @Suite(.serialized)`
struct (names must not start with `test`).

```swift
    @Test
    func orientationValueParsesLandscape() {
        #expect(
            LaunchArgument.orientationValue(
                in: ["--ui-testing", "--ui-testing-orientation", "landscape"])
                == "landscape")
    }

    @Test
    func orientationValueAbsentIsNil() {
        #expect(LaunchArgument.orientationValue(in: []) == nil)
        #expect(LaunchArgument.orientationValue(in: ["--ui-testing-orientation"]) == nil)
        #expect(LaunchArgument.orientationValue(in: ["--ui-testing"]) == nil)
    }
```

#### 4. Script — extend the folded branch and allowlist
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify.

Add the landscape pass inside `capture_duo`'s language loop (after the
`duo_six_shots … "$folder"` call):

```bash
    # Outer landscape: same six screens, app-forced landscape geometry.
    if [ "$DUO_POSE" = folded ]; then
      duo_six_shots "$OUT/$(language_folder "$language")/5-duo-outer-landscape" 1 \
        --ui-testing-force-duo-outer --ui-testing-orientation landscape
    fi
```

Extend the allowlist:

```bash
    1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496 | 1398x2034 | 2034x1398) ;;
```

### Verification
#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/LaunchArgumentTests` passes
      (`orientationValueParsesLandscape`, `orientationValueAbsentIsNil`).
- [x] `bash -n scripts/appstore-screenshots.sh` exits 0.
- [x] `make format && make lint` clean.
#### Manual
- [ ] Device Hub pose **folded**;
      `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo`
      reports every size accepted.
- [ ] `build/appstore-screenshots/en/4-duo-outer-portrait/` is 1398 × 2034 and
      `build/appstore-screenshots/en/5-duo-outer-landscape/` is 2034 × 1398.
- [ ] Spot-check `5-duo-outer-landscape/1-main-dark.png`: content is rotated
      landscape (not a letterboxed portrait), card still widened.
- [ ] Stop and re-open the design's orientation decision if
      `requestGeometryUpdate` proves flaky on the Duo runtime.

---

## Phase 3: Inner display, both poses, end to end

Goal: `--duo-pose book` yields `6-duo-inner-portrait/` (2007 × 2853) and
`--duo-pose open` yields `7-duo-inner-landscape/` (2853 × 2007), both from
display id 3. The inner panel is regular/regular, so the standard layout is
correct — no app seam, no `--ui-testing-orientation`.

### Changes

#### 1. Extend the pose helpers
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify `duo_display_for_pose` and `duo_folder_for_pose`.

```bash
duo_display_for_pose () { # $DUO_POSE → simctl --display id
  case "$DUO_POSE" in
    folded) echo 1 ;;
    book | open) echo 3 ;;
    *)
      echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2
      return 1
      ;;
  esac
}

duo_folder_for_pose () { # $DUO_POSE → numbered output directory
  case "$DUO_POSE" in
    folded) echo "4-duo-outer-portrait" ;;
    book) echo "6-duo-inner-portrait" ;;
    open) echo "7-duo-inner-landscape" ;;
    *)
      echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2
      return 1
      ;;
  esac
}
```

No change to `capture_duo`: `force_args` is already empty for non-`folded`
poses, the landscape branch already gates on `folded`, and `display` comes from
`duo_display_for_pose`.

#### 2. Extend the allowlist
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify.

```bash
    1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496 | 1398x2034 | 2034x1398 | 2007x2853 | 2853x2007) ;;
```

### Verification
#### Automated
- [x] `bash -n scripts/appstore-screenshots.sh` exits 0.
- [x] `make format && make lint` clean (no Swift changes this phase; still run
      to confirm nothing regressed).
#### Manual
- [ ] Device Hub pose **book**;
      `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose book iphone-duo`
      reports every size accepted; `6-duo-inner-portrait/` files are
      2007 × 2853.
- [ ] Device Hub pose **open**;
      `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose open iphone-duo`
      reports every size accepted; `7-duo-inner-landscape/` files are
      2853 × 2007.
- [ ] Inner shots render the **standard** 40-inset layout (not the widened Duo
      card) — confirms `isOuterPortrait` correctly excludes regular/regular.

---

## Phase 4: Hardening & documentation

Goal: a missing Duo runtime fails loudly, the doc block describes the whole Duo
workflow, and `iphone-duo` stays out of the default class list.

### Changes

#### 1. Fail loudly when the Duo runtime/device type is absent
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify — replace the Phase 1 `capture_duo` skip block with an
explicit non-zero exit and diagnostic.

```bash
  udid=$(resolve_udid "$pattern" iOS)
  if [ -z "$udid" ]; then
    echo "!! no iPhone Duo simulator found matching '$pattern'." >&2
    echo "   The Duo device type needs the iPhone19,4 runtime. Check:" >&2
    echo "     xcrun simctl list runtimes | grep iPhone19,4" >&2
    echo "     xcrun simctl list devicetypes | grep 'iPhone Duo'" >&2
    exit 1
  fi
```

This is the only class that exits instead of skipping: the Duo class is
explicitly requested, and a silent skip would produce a "successful" run with
zero Duo folders.

#### 2. Confirm the class stays out of the defaults
**File**: `scripts/appstore-screenshots.sh`
**Action**: verify (no edit expected) — the default remains:

```bash
  CLASSES=(iphone-6.3 ipad-13 watch-series11-46mm)
```

#### 3. Rewrite the doc block for the Duo workflow
**File**: `scripts/appstore-screenshots.sh`, doc block (`:1–128`)
**Action**: modify — add:

- The four variants and their folders/pixels:

  | variant | `--duo-pose` | folder | pixels |
  |---|---|---|---|
  | outer portrait | `folded` | `4-duo-outer-portrait` | 1398 × 2034 |
  | outer landscape | `folded` (same run) | `5-duo-outer-landscape` | 2034 × 1398 |
  | inner portrait | `book` | `6-duo-inner-portrait` | 2007 × 2853 |
  | inner landscape | `open` | `7-duo-inner-landscape` | 2853 × 2007 |

- The three invocations (folded / book / open) and the Device Hub pose step,
  with observed panel sizes in points (**outer 466 × 678**, **inner 669 × 951**),
  noting one pose change covers all seven languages.
- The pose → `--display` id table: `folded` → 1, `book`/`open` → 3.
- The launch-arg seams (`--ui-testing-force-duo-outer`,
  `--ui-testing-orientation landscape`) and that the first is **outer-only**.
- The `iphone-duo` class is opt-in and **not** in the default class list, because
  the App Store Connect Duo upload slot is not live yet — local assets only, and
  uploads will be rejected until Apple opens it.
- Two implementation notes: the inner display ignores supported orientations so
  orientation is pose-driven; and `iphone-duo` reuses five shared wallpaper slots
  (`iphone-duo-<screen>`), fetched once with `--fetch-wallpapers`.

Update the `Usage:` line's class list to include `iphone-duo`.

#### 4. Keep `--help`'s `sed` range aligned
**File**: `scripts/appstore-screenshots.sh`, the `-h | --help` case
**Action**: modify — the help text is `sed -n '2,128p' "$0"`. If the doc block
no longer ends at line 128, set the range's end to the last doc-block line:

```bash
      sed -n '2,<last-doc-line>p' "$0" | sed 's/^# \{0,1\}//'
```

Find the value with:

```bash
grep -n '^set -euo pipefail' scripts/appstore-screenshots.sh
```

The range end is that line number minus 1 (the block is `#`-prefixed through the
blank line before `set`).

### Verification
#### Automated
- [x] `bash -n scripts/appstore-screenshots.sh` exits 0.
- [x] `shellcheck -S warning scripts/appstore-screenshots.sh` is clean or every
      finding is pre-existing (not gate-wired; run by hand per `conventions.md`).
- [x] `bash scripts/appstore-screenshots.sh --help` prints the full doc block
      through the new usage line (no truncation).
- [x] `make test` (unit) — the two seam suites are green; no other unit changes.
- [x] `make format && make lint` clean.
#### Manual
- [ ] Simulating a missing runtime (e.g. temporarily point the pattern at a
      bogus name or rename the check) exits non-zero with the runtime hint rather
      than a silent skip. **Restore before committing.**
- [ ] Full three-invocation sweep across all seven languages:
      `… --duo-pose folded iphone-duo`, `… --duo-pose book iphone-duo`,
      `… --duo-pose open iphone-duo`; all four class folders are present with
      every size accepted.
- [ ] `--fetch-wallpapers` resolves all five `iphone-duo-*` slots.
- [ ] Full CI-identical gate runs once via the `run-gate` skill
      (`./scripts/test.sh`).

---

## Testing Checkpoints (from structure.md)

- **After Phase 1**: `DuoOuterPortraitTests` green; folded run accepted; save the
  resolved Duo UDID — later slices reuse it via `resolve_udid`.
- **After Phase 2**: `LaunchArgumentTests` green; folded run yields both outer
  folders. If `requestGeometryUpdate` is flaky on the Duo runtime, stop and
  re-open the design's orientation decision before Phase 3.
- **After Phase 3**: all four folders produced across the three pose runs.
- **After Phase 4**: `make test` (units) + `bash -n` + full manual sweep green;
  run the full gate once via the `run-gate` skill.

No new test target, no `scripts/test.sh`/CI rewiring, no child tickets — all
work on this branch.

## Deviations from `structure.md` (and why)

1. **`class_folder` cannot serve the Duo.** `class_folder` is one label → one
   folder, but `--duo-pose folded` emits **two** folders (`4-` and `5-`) in one
   run, and the folder depends on the pose. Replaced with
   `duo_folder_for_pose` + `duo_display_for_pose` + a `duo_six_shots` helper;
   `class_folder` is left unchanged (no `iphone-duo` entry, since it is unused
   for this class).
2. **Five wallpaper slots, not six.** `SCREENS` lists `options` twice, so each
   class has five unique slots (verified: the committed set is 10 jpgs for two
   classes). The Duo adds five jpgs + five manifest entries.
3. **`applyForcedOrientationIfNeeded` uses a dedicated `.landscape` mask.**
   `applyLock` uses `.allButUpsideDown`, which permits but does not force
   landscape; forcing needs `.iOS(interfaceOrientations: .landscape)` via the
   same `requestGeometryUpdate` call. Applied from `applicationDidBecomeActive`
   because the scene/window is not guaranteed to exist at
   `didFinishLaunching`.
4. **Phase 4 must fix the `--help` `sed` range.** The doc block is printed by
   `sed -n '2,128p'`; growing the block without updating the range would truncate
   `--help`. Called out explicitly as a Phase 4 step.
