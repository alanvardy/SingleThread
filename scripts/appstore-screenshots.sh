#!/usr/bin/env bash
#
# App Store Connect screenshots — iPhone 6.3" and iPad 13" display classes.
#
# Per language, per display class, this captures:
#
#   main-light.png         main reminder card, light appearance
#   options-light.png      root Settings sheet, light appearance
#   main-dark.png          main reminder card, dark appearance
#   empty-dark.png         "All Done" empty state, dark appearance
#   no-reminders-dark.png  "No Reminders" empty state, dark appearance
#
# The watch class captures a third, separate set — the watch app has no
# wallpaper, no settings screen, and no `--seed`, so its demo copy comes from the
# watch's own seams in `WatchDemoReminder`:
#
#   main.png          reminder card
#   more.png          three-action menu — Skip / Reschedule / Delete
#   all-done.png      "All Done" (`--ui-testing-excluded-list`)
#   no-reminders.png  "No Reminders" (`--ui-testing-empty`)
#
# The menu and the empty states exist only behind seams: the menu needs a tap on
# the Skip button (`--ui-testing-open-action-menu` presents it at launch), and
# `--ui-testing` always seeds a card, so nothing else reaches the empty store.
#
# watchOS follows the *device* language rather than an in-app preference, so
# each language pass writes AppleLanguages/AppleLocale into the watch simulator
# and reboots it — a relaunch alone does not pick the change up. The watch boots
# unpaired; pairing only routes the app through a phone clone.
#
# The options screen is presented by the `--ui-testing-open-settings` launch
# seam (`LaunchArgument.openSettings`), which replays the gear button's action
# at launch — the sheet has no URL scheme or menu command, and `simctl` cannot
# tap, so no other route reaches it. Capturing options therefore needs an app
# build that carries the seam; the script rebuilds by default rather than
# reusing a possibly stale .app (pass --no-build to skip).
#
# The main card shows one localized demo reminder — "Teach the cat how to do my
# taxes" and its five translations, in `demo_reminder_seed` below. It travels in
# a --seed payload rather than the app's string catalog: reminder text is user
# content, and cataloging marketing copy would ship it inside the binary and
# put it in front of translators. Two consequences:
#
#   * `-showSwipePrompt NO` is required. A seeded launch resets the first-launch
#     swipe guide back on (UITestingSeed.persistedKeys) and it draws over the
#     card; the argument domain sits above the persistent one, so the flag wins.
#   * The app language is primed by a throwaway --ui-testing launch per language
#     before the seeded captures, because --ui-testing-app-language is read only
#     on the --ui-testing path.
#
# Output: build/appstore-screenshots/<lang>/<class>/<name>.png
#
# Folders are language-major, so every localization of one device sits in a
# single directory, and each language directory carries the App Store's own
# ordering as a numeric prefix (`language_folder` below): 1-en, 2-zh-Hans,
# 3-fr, 4-de, 5-ja, 6-es. The output tree is cleared at the start of every
# run, so a stale layout can never linger beside the new one.
#
# The captures are the simulator's native pixels — 1206 x 2622 (6.3") and
# 2064 x 2752 (13") — which are App Store Connect's accepted pairs for those
# slots, so no resize or pad is needed. `--mask ignored` drops the rounded
# device mask that the store does not want.
#
# Language: `--ui-testing-app-language <raw>` persists the app-language
# preference into the App Group, and `AppLocaleState` reads it on the next cold
# launch. Launching with the flag per language (rather than only once) is what
# makes every later capture in that language follow — the preference is not
# cleared by the `--seed` reset (`appLanguage` is absent from
# `UITestingSeed.persistedKeys`).
#
# ── Wallpaper ────────────────────────────────────────────────────────────────
#
# The background photo is not bundled. `backgroundEnabled` defaults to true at a
# 50% fade, and `BackgroundImageStore` shows whatever photo sits at
#
#   <app data container>/Library/Application Support/SingleThread/background.jpg
#
# with a `background.json` sidecar (`photographer`, `fetchedAt`). A `fetchedAt`
# inside 24h makes `refreshIfNeeded()` return early, so a staged photo is never
# overwritten — that is how wallpapers are pinned here.
#
# Wallpapers are keyed by "slot" = <device class>-<screen>, NOT by language, so
# each device/screen pair keeps one fixed photo across all six languages:
#
#   iphone-6.3-main-light    ipad-13-main-light      (own photo: the light
#   iphone-6.3-main-dark     ipad-13-main-dark        appearance composites the
#                                                     photo over white, not black)
#   iphone-6.3-options       ipad-13-options
#   iphone-6.3-empty         ipad-13-empty           ("All Done")
#   iphone-6.3-no-reminders  ipad-13-no-reminders
#
# The set is COMMITTED — scripts/fixtures/appstore-wallpapers/ holds the ten
# photos and manifest.json — so a clone captures the same wallpapers with no
# network and nothing to draw. Override the directory with WALLPAPER_DIR to use
# your own art (the slot file names and manifest shape are all that matter).
#
# To change the set, draw new photos from the API
# (https://vardy.cc/unsplash/random), which keeps any slot already on disk:
#
#   scripts/appstore-screenshots.sh --fetch-wallpapers          # random
#   scripts/appstore-screenshots.sh --wallpaper-url <url>       # one URL, all slots
#   scripts/appstore-screenshots.sh --wallpaper-url ipad-13-main=<url>
#
# Rotate deliberately with --refetch-wallpapers; re-runs are byte-identical
# otherwise. A missing manifest is a hard error, not a cue to fetch: silently
# drawing fresh photos would change the capture set, and the old fallback —
# letting the app download its own single photo — gave every screen the same
# wallpaper while each `stage_slot` threw a FileNotFoundError at the reader.
#
# These are Unsplash photos (the licence permits redistribution; the manifest
# carries each photographer's attribution). Replace them with your own art for a
# permanent store listing.
#
# Options: --fetch-wallpapers, --refetch-wallpapers, --wallpaper-url, and
# --no-build / --no-install to reuse an already-built .app and an app already
# installed on the simulator. REPO_ROOT overrides the root captures land under.
#
# Usage: scripts/appstore-screenshots.sh [options] [class ...]
#        class: iphone-6.3 | ipad-13 | watch-series11-46mm
#        (default: the two iOS classes)

set -euo pipefail

cd "${REPO_ROOT:-$(dirname "$0")/..}"

BUNDLE=app.alanvardy.SingleThread
APP=DerivedData/Build/Products/Debug-iphonesimulator/SingleThread.app
DESTINATION='generic/platform=iOS Simulator'
WATCH_BUNDLE=app.alanvardy.SingleThread.watchkitapp
WATCH_APP=DerivedData/Build/Products/Debug-watchsimulator/SingleThreadWatch.app
WATCH_DESTINATION='generic/platform=watchOS Simulator'
# App Store Connect's only Apple Watch class this app can fill: 416 x 496 is
# Series 11 on watchOS 11+, and the deployment target is watchOS 11.0. One size
# serves every localization — the Watch section has no size fallback.
WATCH_CLASS=watch-series11-46mm
WATCH_DEVICE_TYPE='Apple Watch Series 11 \(46mm\)'
OUT=build/appstore-screenshots
# Committed, not under build/: a clone gets the same ten photos and re-runs are
# reproducible with no network.
WALLPAPER_DIR=${WALLPAPER_DIR:-scripts/fixtures/appstore-wallpapers}
WALLPAPER_API=${WALLPAPER_API:-https://vardy.cc/unsplash/random}
SETTLE=${SETTLE:-6}


# Optional path to one local photo to stage into every slot. Overrides the
# manifest; useful for a marketing photo you hold the rights to.
BACKGROUND_IMAGE=${BACKGROUND_IMAGE:-}

# "All Done" is `listContent == .allDone` — reminders loaded but every one
# filtered out, which an excluded list reaches deterministically.
ALL_DONE_SEED='{"reminders":[{"title":"Buy groceries","notes":"milk","priority":5}],"calendars":["Errands"],"excludedLists":["Errands"]}'

demo_reminder_title () { # $1 = language → localized demo reminder title
  case "$1" in
    en) echo "Teach the cat how to do my taxes" ;;
    de) echo "Der Katze beibringen, meine Steuererklärung zu machen" ;;
    es) echo "Enseñarle al gato a hacer mi declaración de la renta" ;;
    fr) echo "Apprendre au chat à faire ma déclaration d'impôts" ;;
    ja) echo "猫に確定申告のやり方を教える" ;;
    zh-Hans) echo "教猫帮我报税" ;;
    *)
      echo "!! no demo reminder for language '$1'" >&2
      return 1
      ;;
  esac
}

demo_reminder_seed () { # $1 = language → seed JSON holding the localized demo reminder
  # python rather than printf: the French copy carries an apostrophe and every
  # language carries non-ASCII, so the JSON needs real escaping.
  python3 -c 'import json, sys
print(json.dumps({"reminders": [{"title": sys.argv[1], "priority": 5}], "calendars": ["Errands"]}, ensure_ascii=False))' "$(demo_reminder_title "$1")"
}

watch_locale () { # $1 = language → "<AppleLanguages value> <AppleLocale>"
  case "$1" in
    en) echo "en en_US" ;;
    de) echo "de de_DE" ;;
    es) echo "es es_ES" ;;
    fr) echo "fr fr_FR" ;;
    ja) echo "ja ja_JP" ;;
    zh-Hans) echo "zh-Hans zh_CN" ;;
    *) return 1 ;;
  esac
}

# App Store Connect's localization order, with the folder label each language
# writes into: language-major output, ordered exactly as the store lists them.
# `es` ships as "6-es", matching the raw-code style of the other five.
language_folder () { # $1 = language → numbered output directory name
  case "$1" in
    en) echo "1-en" ;;
    zh-Hans) echo "2-zh-Hans" ;;
    fr) echo "3-fr" ;;
    de) echo "4-de" ;;
    ja) echo "5-ja" ;;
    es) echo "6-es" ;;
    *) return 1 ;;
  esac
}

LANGUAGES=(en zh-Hans fr de ja es)

# Wallpaper slots per device class, in capture order. Slot names match the
# captured file names so a staged photo maps 1:1 onto an output PNG.
SCREENS=(main-light options main-dark empty no-reminders)

# class:simctl devicetype name regex
DEVICE_TYPES=(
  # `iPhone 17` is 6.3" (1206 x 2622) — an accepted App Store iPhone slot. The
  # `$` keeps the pattern off `iPhone 17 Pro` / `iPhone 17 Pro Max` / `iPhone 17e`.
  "iphone-6.3:iPhone 17$"
  "ipad-13:iPad Pro 13-inch \\(M5\\)"
)

# ── CLI ──────────────────────────────────────────────────────────────────────

FETCH_WALLPAPERS=0
REFETCH_WALLPAPERS=0
BUILD=1
INSTALL=1
WALLPAPER_URLS=()
CLASSES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch-wallpapers)
      FETCH_WALLPAPERS=1
      shift
      ;;
    --refetch-wallpapers)
      FETCH_WALLPAPERS=1
      REFETCH_WALLPAPERS=1
      shift
      ;;
    --wallpaper-url)
      FETCH_WALLPAPERS=1
      WALLPAPER_URLS+=("$2")
      shift 2
      ;;
    --wallpaper-dir)
      WALLPAPER_DIR=$2
      shift 2
      ;;
    --no-build)
      BUILD=0
      shift
      ;;
    --no-install)
      INSTALL=0
      shift
      ;;
    -h | --help)
      sed -n '2,120p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "!! unknown option: $1" >&2
      exit 2
      ;;
    *)
      CLASSES+=("$1")
      shift
      ;;
  esac
done

MANIFEST=$WALLPAPER_DIR/manifest.json

resolve_udid () { # $1 = device type name regex, $2 = runtime family; newest runtime wins
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys

pattern = re.compile(sys.argv[1])
family = sys.argv[2]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if family not in runtime:
        continue
    version = tuple(int(n) for n in re.findall(r"[0-9]+", runtime.rsplit(".", 1)[-1]))
    for device in devices:
        if pattern.match(device["name"]) and (best is None or version > best[0]):
            best = (version, device["udid"])
print(best[1] if best else "")
' "$1" "$2"
}

# ── Wallpapers ───────────────────────────────────────────────────────────────

wallpaper_dir () { # app-private cache directory for the background photo
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  echo "$container/Library/Application Support/SingleThread"
}

slot_names () { # every slot for the device classes in play, as <class>-<screen>
  local entry label screen
  for entry in "${DEVICE_TYPES[@]}"; do
    label=${entry%%:*}
    for screen in "${SCREENS[@]}"; do
      echo "$label-$screen"
    done
  done
}

fetch_wallpapers () { # one photo per slot, kept once fetched
  local slots=()
  local slot
  while IFS= read -r slot; do slots+=("$slot"); done < <(slot_names)
  mkdir -p "$WALLPAPER_DIR"
  [ -f "$MANIFEST" ] || echo '{}' >"$MANIFEST"
  python3 - "$MANIFEST" "$WALLPAPER_API" "$REFETCH_WALLPAPERS" "${WALLPAPER_URLS[@]+"${WALLPAPER_URLS[@]}"}" "${slots[@]}" <<'PY'
import datetime, hashlib, json, os, sys, urllib.request

manifest_path, api, refetch, *rest = sys.argv[1:]
slots = [item for item in rest if "=" not in item]
overrides = dict(item.split("=", 1) for item in rest if "=" in item)
directory = os.path.dirname(manifest_path)
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}

# One photo per slot is the whole point, and the random endpoint does repeat
# itself (it served the same John Lee photo to two slots on the first run), so
# every draw is checked against the photos already in play.
REDRAWS = 5


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "appstore-screenshots"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def draw(url):
    """One photo: the default endpoint is JSON describing it, while an
    explicit --wallpaper-url may already be the image itself."""
    payload = download(url)
    photographer, photographer_url = "SingleThread", None
    try:
        described = json.loads(payload)
        photographer = described.get("photographer", "Unknown")
        photographer_url = described.get("photographer_url")
        payload = download(described["url"])
    except (ValueError, KeyError, TypeError):
        pass
    return payload, photographer, photographer_url


in_play = {}
for other, entry in manifest.items():
    path = os.path.join(directory, entry["file"])
    if os.path.isfile(path):
        in_play[digest(open(path, "rb").read())] = other

for slot in slots:
    target = os.path.join(directory, slot + ".jpg")
    if os.path.exists(target) and slot in manifest and not int(refetch):
        print("    kept {} ({})".format(slot, manifest[slot]["photographer"]))
        continue
    url = overrides.get(slot, overrides.get("*", api))
    pinned = slot in overrides or "*" in overrides
    payload, photographer, photographer_url = draw(url)
    redraws = 0
    while not pinned and in_play.get(digest(payload), slot) != slot and redraws < REDRAWS:
        redraws += 1
        payload, photographer, photographer_url = draw(url)
    clash = in_play.get(digest(payload))
    if clash and clash != slot:
        print("    !! {} still duplicates {} after {} redraws".format(slot, clash, redraws))
    with open(target, "wb") as handle:
        handle.write(payload)
    in_play[digest(payload)] = slot
    if redraws:
        print("    redrew {} {}x to avoid a duplicate".format(slot, redraws))
    manifest[slot] = {
        "file": os.path.basename(target),
        "source": url,
        "photographer": photographer,
        "photographerURL": photographer_url,
        "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
    }
    print("    fetched {} -> {} ({} bytes)".format(slot, photographer, len(payload)))

json.dump(manifest, open(manifest_path, "w"), indent=2, sort_keys=True)
PY
  echo "    manifest: $MANIFEST"
}

stage_slot () { # $1 = class, $2 = screen — pin that slot's photo into the app
  local slot="$1-$2" dir
  # Guarded in bash: the python below opens the manifest directly, so a missing
  # one surfaces as a FileNotFoundError traceback instead of a useful message.
  if [ ! -f "$MANIFEST" ]; then
    echo "!! no wallpaper manifest at $MANIFEST — every screen would keep one photo" >&2
    return 1
  fi
  dir=$(wallpaper_dir)
  mkdir -p "$dir"
  python3 - "$MANIFEST" "$slot" "$dir" <<'PY'
import datetime, json, os, shutil, sys

manifest_path, slot, target_dir = sys.argv[1:4]
entry = json.load(open(manifest_path)).get(slot)
if not entry:
    sys.exit(3)
source = os.path.join(os.path.dirname(manifest_path), entry["file"])
if not os.path.isfile(source):
    sys.exit(4)
shutil.copyfile(source, os.path.join(target_dir, "background.jpg"))
metadata = {
    "photographer": entry["photographer"],
    "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    ),
}
if entry.get("photographerURL"):
    metadata["photographerURL"] = entry["photographerURL"]
json.dump(metadata, open(os.path.join(target_dir, "background.json"), "w"))
PY
  echo "    wallpaper: $slot"
}

stage_single_wallpaper () { # BACKGROUND_IMAGE into every slot
  local dir
  dir=$(wallpaper_dir)
  mkdir -p "$dir"
  cp "$BACKGROUND_IMAGE" "$dir/background.jpg"
  python3 - "$dir/background.json" <<'PY'
import datetime, json, sys

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump({"photographer": "SingleThread", "fetchedAt": now}, open(sys.argv[1], "w"))
PY
  echo "    staged $(basename "$BACKGROUND_IMAGE")"
}

prepare_wallpaper () { # never capture before a fresh photo is on disk
  local slot missing=0
  if [ -n "$BACKGROUND_IMAGE" ]; then
    stage_single_wallpaper
    return
  fi
  # The manifest is committed, so its absence means a broken checkout or a
  # WALLPAPER_DIR pointed somewhere else — never a cue to draw fresh photos,
  # which would silently change the capture set.
  if [ ! -f "$MANIFEST" ]; then
    echo "!! no wallpaper manifest at $MANIFEST" >&2
    echo "   restore it (git checkout -- $(dirname "$MANIFEST")) or draw a new set with --fetch-wallpapers" >&2
    return 1
  fi

  {
    for screen in "${SCREENS[@]}"; do
      slot="$LABEL-$screen"
      if ! python3 -c '
import json, os, sys

manifest_path, slot = sys.argv[1:3]
try:
    entry = json.load(open(manifest_path))[slot]
except Exception:
    sys.exit(1)
sys.exit(0 if os.path.isfile(os.path.join(os.path.dirname(manifest_path), entry["file"])) else 1)
' "$MANIFEST" "$slot"; then
        missing=1
      fi
    done
  }
  if [ "$missing" -eq 1 ]; then
    echo "!! some $LABEL wallpaper slots are missing — rerun --fetch-wallpapers" >&2
    return 1
  fi
}

# ── Capture ──────────────────────────────────────────────────────────────────

prime_language () { # $1 = language — --ui-testing-app-language lands only on the --ui-testing path
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" --ui-testing --ui-testing-noop-settle \
    --ui-testing-app-language "$1" >/dev/null
  sleep 2
}

shoot () { # $1 = output path, rest = launch arguments
  local out=$1
  shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    $(basename "$(dirname "$out")")/$(basename "$out")"
}

capture_class () { # $1 = class label, $2 = device type regex
  local label=$1
  local pattern=$2
  local udid dir
  udid=$(resolve_udid "$pattern" iOS)
  if [ -z "$udid" ]; then
    echo "!! no available simulator for '$pattern' — skipping $label" >&2
    return 1
  fi

  echo "==> $label ($pattern)"
  UDID=$udid
  LABEL=$label
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  if [ "$INSTALL" -eq 1 ]; then
    xcrun simctl install "$UDID" "$APP"
  fi
  prepare_wallpaper

  for language in "${LANGUAGES[@]}"; do
    dir="$OUT/$(language_folder "$language")/$label"
    mkdir -p "$dir"
    echo "  -> $language"
    demo_seed=$(demo_reminder_seed "$language")
    prime_language "$language"
    stage_slot "$label" main-light
    xcrun simctl ui "$UDID" appearance light
    shoot "$dir/main-light.png" \
      --seed "$demo_seed" --ui-testing-noop-settle -showSwipePrompt NO
    stage_slot "$label" options
    shoot "$dir/options-light.png" \
      --ui-testing --ui-testing-noop-settle --ui-testing-app-language "$language" \
      --ui-testing-open-settings
    stage_slot "$label" main-dark
    xcrun simctl ui "$UDID" appearance dark
    shoot "$dir/main-dark.png" \
      --seed "$demo_seed" --ui-testing-noop-settle -showSwipePrompt NO
    stage_slot "$label" empty
    shoot "$dir/empty-dark.png" --seed "$ALL_DONE_SEED"
    stage_slot "$label" no-reminders
    shoot "$dir/no-reminders-dark.png" --no-reminders
  done

  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

# ── Watch ────────────────────────────────────────────────────────────────────

watch_set_language () { # watchOS reads the device language, so a reboot applies it
  local pair languages locale
  pair=$(watch_locale "$1")
  languages=${pair%% *}
  locale=${pair##* }
  xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$languages"
  xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$locale"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
}

watch_shot () { # $1 = output path, rest = watch launch arguments
  local out=$1
  shift
  xcrun simctl terminate "$UDID" "$WATCH_BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$WATCH_BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    $(basename "$(dirname "$out")")/$(basename "$out")"
}

capture_watch () { # $1 = device type regex
  local pattern=$1
  local udid dir language
  udid=$(resolve_udid "$pattern" watchOS)
  if [ -z "$udid" ]; then
    echo "!! no available simulator for '$pattern' — skipping $WATCH_CLASS" >&2
    return 1
  fi

  echo "==> $WATCH_CLASS ($pattern)"
  UDID=$udid
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl install "$UDID" "$WATCH_APP"

  for language in "${LANGUAGES[@]}"; do
    dir="$OUT/$(language_folder "$language")/$WATCH_CLASS"
    mkdir -p "$dir"
    echo "  -> $language"
    watch_set_language "$language"
    watch_shot "$dir/main.png" --ui-testing \
      --ui-testing-title "$(demo_reminder_title "$language")" --ui-testing-notes ""
    watch_shot "$dir/more.png" --ui-testing \
      --ui-testing-title "$(demo_reminder_title "$language")" --ui-testing-notes "" \
      --ui-testing-open-action-menu
    watch_shot "$dir/all-done.png" --ui-testing --ui-testing-excluded-list Errands
    watch_shot "$dir/no-reminders.png" --ui-testing --ui-testing-empty
  done

  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

# ── Run ──────────────────────────────────────────────────────────────────────

if [ ${#CLASSES[@]} -eq 0 ]; then
  CLASSES=(iphone-6.3 ipad-13)
fi

# Clear the output tree: the language-major layout replaced an older
# device-major one, and stale PNGs would otherwise sit beside (or be swept into
# the size check with) the fresh captures.
rm -rf "$OUT"
mkdir -p "$OUT"

if [ "$FETCH_WALLPAPERS" -eq 1 ]; then
  echo "==> wallpapers"
  fetch_wallpapers
fi

watch_requested () {
  local wanted
  for wanted in "${CLASSES[@]}"; do
    if [ "$wanted" = "$WATCH_CLASS" ]; then
      return 0
    fi
  done
  return 1
}

if [ "$BUILD" -eq 1 ] && [ "$INSTALL" -eq 1 ]; then
  echo "==> building $APP"
  xcodebuild -scheme SingleThread -configuration Debug \
    -destination "$DESTINATION" -derivedDataPath DerivedData build >/dev/null
fi

if [ "$BUILD" -eq 1 ] && watch_requested; then
  echo "==> building $WATCH_APP"
  xcodebuild -scheme SingleThreadWatch -configuration Debug \
    -destination "$WATCH_DESTINATION" -derivedDataPath DerivedData build >/dev/null
fi

for entry in "${DEVICE_TYPES[@]}"; do
  label=${entry%%:*}
  pattern=${entry#*:}
  for wanted in "${CLASSES[@]}"; do
    if [ "$wanted" = "$label" ]; then
      capture_class "$label" "$pattern"
    fi
  done
done

for wanted in "${CLASSES[@]}"; do
  if [ "$wanted" = "$WATCH_CLASS" ]; then
    capture_watch "$WATCH_DEVICE_TYPE"
  fi
done

echo "==> verifying sizes"
fail=0
count=0
for shot in "$OUT"/*/*/*.png; do
  count=$((count + 1))
  dims=$(sips -g pixelWidth -g pixelHeight "$shot" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  case "$dims" in
    1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496) ;;
    *)
      echo "!! ${shot} is ${dims}" >&2
      fail=1
      ;;
  esac
done
if [ "$fail" -ne 0 ]; then
  echo "!! some screenshots are not an App Store Connect-accepted size" >&2
  exit 1
fi
echo "    ${count} screenshots, every size accepted"

echo "==> done: $OUT"
