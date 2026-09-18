# Design Discussion — VAR-1044: run-devices.sh covers all devices

## Current State

`scripts/run-devices.sh` is a single sequential bash flow with three legs:

- **Discovery** (`run-devices.sh:39-93`): `xcrun devicectl list devices -j "$DEVICES_JSON"`
  (`:41`), then an inline python filter (`:55-88`) that keeps
  `hardwareProperties.platform=="iOS"` (`:66`) **and** `deviceType in
  (iPhone,iPad)` (`:68`) with `developerModeStatus=="enabled"` (`:71`), and
  classifies a device unreachable when `transportType is None` or
  `connection.state=="unavailable"` or `tunnelState=="unavailable"` (`:80-82`).
  Qualifying entries are printed `identifier|name` (`:86`) into `DEVICES`.
- **Build + install/launch** (`run-devices.sh:115-147`): one
  `xcodebuild -scheme SingleThread -destination 'generic/platform=iOS'
  -configuration Debug -derivedDataPath DerivedData build` (`:118-122`),
  producing `DerivedData/Build/Products/Debug-iphoneos/SingleThread.app`
  (`:34`); then per device `devicectl device install app` (`:136`) and
  `devicectl device process launch --terminate-existing --activate` (`:143`).
- **macOS host leg** (`run-devices.sh:151-172`): `-destination 'platform=macOS'`
  plus `CODE_SIGNING_ALLOWED=NO` (`:158`), then `open "$MAC_APP_PATH"` (`:167`).

Failure accounting: unreachable devices are logged (`:83-84`) and seeded into
`failures` (`:109-112`); each install/launch failure increments it
(`:137-139,144-145`); the summary prints ✅ only when `failures == 0`, else
`❌ … step(s) failed` and exit 1 (`:174-182`). Env overrides are
`SCHEME / BUNDLE_ID / CONFIGURATION / DERIVED_DATA / RUN_MAC` (`:25-29`).

The watch target exists and is well-formed but **has never been built for a
real device anywhere in the repo** (conventions.md §Build gotchas; research Q5).
`SingleThreadWatch` is `com.apple.product-type.application`
(`project.pbxproj:334`) with `SDKROOT=watchos`,
`SUPPORTED_PLATFORMS="watchos watchsimulator"`,
`PRODUCT_BUNDLE_IDENTIFIER=app.alanvardy.SingleThread.watchkitapp`,
`WKCompanionAppBundleIdentifier=app.alanvardy.SingleThread`, `SKIP_INSTALL=YES`,
`CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM=6NWX2DHB9Q`
(`project.pbxproj:941-993`). Its shared scheme builds/launches the watch app
(`SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch.xcscheme`).
Every existing watch leg (Makefile `watch-build`/`watch-test`/`watch-ui-test`
`Makefile:40-41,107-120`; CI `ci.yml:234-241,247-317`) is **simulator-only**
with no signing flags.

Live devicectl probe (2026-09-17, research Q4): a real **Apple Watch Ultra** is
paired with Developer Mode enabled — `platform:"watchOS"`,
`deviceType:"appleWatch"`, `reality:"physical"`, identifier
`6EF5C1CD-A890-559B-98D5-8F7F5A5A699A`, udid `00008301-209B793C010BC02E` — but
`connectionProperties.tunnelState:"disconnected"` and
`properties.connection.state:"disconnected"`. WatchOS sims also appear in the
same list with `reality:"simulated"`. `--device` accepts
UUID/ECID/serial/UDID/name/DNS; `--activate`, `--terminate-existing`,
`--display` are documented "not supported on all platforms".

## Desired End State

`./scripts/run-devices.sh` covers **iPhone, iPad, macOS, and Apple Watch** in
one run, with the same contract it has today: discover → build → install →
launch → summary, unreachable devices reported with their real cause, exit
non-zero when any step failed.

Concretely, a run with the watch reachable should:

1. Discover physical watches alongside iOS devices and report a watch that is
   paired but tunnel-down as *unreachable*, naming the cause (paired iPhone
   connectivity) rather than emitting a raw devicectl 4016.
2. Build `SingleThreadWatch` once for `generic/platform=watchOS` into the shared
   `DerivedData`, landing at
   `DerivedData/Build/Products/Debug-watchos/SingleThreadWatch.app`.
3. `devicectl device install app --device <watch>` that bundle, then
   `devicectl device process launch` the watch bundle id.
4. Keep the existing iOS and macOS legs byte-for-byte in behaviour.
5. Honour a new `RUN_WATCH` switch, default `1`, symmetric with `RUN_MAC`.

Verification: a manual run on this Mac with the watch reachable shows the watch
in the discovery list, a successful `Debug-watchos` build, a successful install
and launch, and a ✅ summary. A run with the watch unreachable exits non-zero
and names the watch + cause; a run with `RUN_WATCH=0` skips the leg entirely.

## Patterns to Follow

**Follow:**

- **Leg symmetry.** Each platform leg is a guarded block that increments
  `failures` rather than aborting (`run-devices.sh:151-172` macOS; `:130-147`
  iOS). The watch leg is a third such block, placed between the iOS and macOS
  legs.
- **Env-override defaults block** (`run-devices.sh:25-29`) — add `RUN_WATCH`
  (and any watch-specific override) there, and document it in the header
  comment (`:9-23`), which is the script's user-facing contract.
- **Python-filter-emits-`identifier|name`** discovery shape
  (`run-devices.sh:47-88`) — stdout parseable, skips/errors to stderr, unreachable
  names appended to a log file that feeds the tally (`:83-84`, `:109-112`).
- **Loud, cause-naming failure messages** (`run-devices.sh:42-44,96-98,124-127`)
  — the watch leg must say "make sure the watch is on your wrist, its paired
  iPhone is nearby and unlocked" rather than surfacing a devicectl assertion.
- **DerivedData-relative product path const** (`run-devices.sh:34-35`) — add
  `WATCH_APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos/SingleThreadWatch.app"`.
- **`--device` with the CoreDevice `identifier`** (`run-devices.sh:136,143`) —
  keep using the same identifier field for the watch; do not switch to the UDID
  or name form.
- **Docs/test conventions** (conventions.md): `make format` then `make lint`
  before committing; the full `./scripts/test.sh` gate runs once via the
  `run-gate` skill; single tests via `scripts/test-one.sh`.

**Do NOT follow:**

- **`CODE_SIGNING_ALLOWED=NO`** (`run-devices.sh:158`, `Makefile:44`,
  `ci.yml:177,187`) — valid for the unsigned macOS host build, fatal for a
  device install. The watch leg must use Automatic signing.
- **Simulator-pinned watch destinations** (`Makefile:8,12-21`) — `WATCH_SIM`
  is `generic/platform=watchOS Simulator`; the real-device leg needs
  `generic/platform=watchOS` (no Simulator suffix).
- **The iOS unreachable predicate verbatim** (`run-devices.sh:80-82`) — it
  keys on `state=="unavailable"`, and the real watch reports
  `state=="disconnected"`. Watch reachability needs its own check.
- **`reality`-blind filtering** (`run-devices.sh:66,68`) — a `platform=="watchOS"`
  filter alone would match the four paired watch sims on this machine; the
  watch filter must also require `reality=="physical"`.

## Design Decisions

1. **Install target: direct to the watch.** `devicectl device install app
   --device <watch-identifier> WatchApp.app` is the watch leg's install — the
   ticket asks for the install *and* launch of the watch app, and a companion-
   relayed install gives the script no proof the watch received the new build.
   The paired-iPhone prerequisite is satisfied by the existing iOS leg; the
   script documents it rather than trying to detect it.
2. **Discovery filter: platform `watchOS` + deviceType `appleWatch` +**
   **`reality == "physical"`.** Same `list devices -j` call and same
   `identifier|name` contract; the `reality` clause is what keeps the four
   simulator watches out of a real-device run.
3. **Reachability: `connection.state != "connected"` is unreachable, and it
   counts as a failed step.** This keeps the script's existing contract
   ("unreachable is a real signal, not a silent skip" — `run-devices.sh:109-112`)
   consistent across iOS and watch, and it turns the live probe's
   `disconnected` state into a named diagnosis instead of a 4016 four steps later.
4. **Build leg: separate `SingleThreadWatch` build, `generic/platform=watchOS`,**
   **`-allowProvisioningUpdates`, shared `DERIVED_DATA`.** A separate invocation
   mirrors the macOS leg, and the provisioning flag removes the most likely
   first-run failure (`No profiles for 'app.alanvardy.SingleThread.watchkitapp'
   were found`) without touching the project's signing settings. The main
   `SingleThread` scheme does **not** build the watch for plain `build`
   (only `buildForTesting`, research Q2), so reuse is not available.
5. **Launch: iOS-style flags first, minimal retry on failure.** Attempt
   `--terminate-existing --activate` with `app.alanvardy.SingleThread.watchkitapp`;
   if it exits non-zero, retry once with `--terminate-existing` and report
   which form succeeded. Research could not prove which flags watchOS accepts
   (`--activate` is "not supported on all platforms"), and this small fallback
   separates "unsupported flag" from "app won't launch" — a distinction the
   plan cannot get any other way.
6. **`RUN_WATCH`, default `1`.** Symmetric with `RUN_MAC` (`run-devices.sh:29`):
   default-on coverage, `RUN_WATCH=0` to skip. Zero watches found is a notice
   and a continue, **not** a failure — the same shape as "no iOS devices, but
   `RUN_MAC=1`" (`run-devices.sh:100-101`) — so a run without the watch on the
   wrist does not go red. A bare unpaired watch is also not a failure for the
   same reason.
7. **Watch bundle id derived from `BUNDLE_ID`.** Define
   `WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${BUNDLE_ID}.watchkitapp}"` next to the
   existing defaults, so a rebranded `BUNDLE_ID` keeps both legs coherent; the
   actual value matches `project.pbxproj:954` today.
8. **No structural refactor of the script.** The watch leg is added in place,
   in the same style; the existing iOS/macOS legs keep their line-for-line
   behaviour. This is a scope decision, not an aesthetic one — see below.

## What We're NOT Doing

- **Not** adding a `RUN_IOS` switch, not restructuring discovery into a shared
  function, not parallelising the legs.
- **Not** touching the Simulator-side watch flow (`Makefile` watch targets, CI
  watch jobs, `scripts/test.sh`) — those are green and out of scope.
- **Not** changing watch target signing settings, entitlements, bundle ids, or
  `WKCompanionAppBundleIdentifier` in `project.pbxproj`.
- **Not** handling the companion-relay install path (Option B in Q1) or
  detecting/installing the paired iPhone as a prerequisite.
- **Not** adding a unit-test target for a bash script. The verification in this
  ticket is a real run of `./scripts/run-devices.sh` against hardware, plus
  `make lint`-equivalent shell review. (If the plan finds a shellcheck-based
  seam already in the repo, it may be used; none was found in research.)
- **Not** attempting to make the watch leg work with the watch tunnel down —
  the failure is diagnosed, not worked around.

## Open Risks

- **Direct-to-watch install is unproven.** The single highest-uncertainty item
  (research "Open Areas"): the watch is paired but `state:"disconnected"`, so
  no install has ever been shown to succeed. If devicectl cannot install to a
  companion-embedded (`SKIP_INSTALL=YES`) watch bundle, Decision 1 has to be
  revisited — the plan must mark this step `UNVALIDATED` and make the manual
  hardware run a gate before merge.
- **Signing may still fail.** `-allowProvisioningUpdates` requires an
  authenticated Xcode account with a team profile for `…watchkitapp`; if the
  watch app needs its own profile and the account lacks one, first run fails at
  the build step. The failure message must be self-explanatory.
- **`Debug-watchos` product path is unverified** (research Open Areas) — the
  path const is derived by analogy with `Debug-watchsimulator`
  (`scripts/test.sh:315-317`) and `Debug-iphoneos` (`run-devices.sh:34`). If it
  differs, the leg must fail loudly rather than silently no-op, matching
  `run-devices.sh:124-127`.
- **Launch flag support on watchOS is unknown** — mitigated by Decision 5's
  single retry, but the retry's outcome is the real answer.
- **Shared `DerivedData` across three destinations** — the iOS and watch builds
  are separate invocations sharing one `-derivedDataPath`; the existing macOS
  leg already shares it (`:158`), so this is believed safe, but a watch build
  must not invalidate the iOS product used minutes earlier.
- **A watchOS 26.6 device against a `WATCHOS_DEPLOYMENT_TARGET=11.0` target** is
  a wide gap; the same gap already exists for simulator tests, so no new risk is
  expected, but it is untested on hardware.
