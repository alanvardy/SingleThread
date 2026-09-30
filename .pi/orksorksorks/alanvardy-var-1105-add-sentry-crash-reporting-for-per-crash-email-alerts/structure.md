# Structure Outline

## Approach

Link `sentry-cocoa` (9.26.x) to the `SingleThread` target only; steer it through a pure,
Sentry-free `SentryConfiguration` value type made real by a thin `SentryBootstrap` adapter, and
start it from a new `SingleThreadApp.init()`. Every slice cuts app-launch → config → scrub →
capture → disclosure/upload, so the tree stays green and each slice is independently demoable.

> The one non-vertical element — the remote SPM `packageReferences` + product-dependency wiring —
> is folded into Slice 1 because no slice can build without it; it is not split into a layer phase.

---

## Phase 1: Walking skeleton — a real crash reaches Sentry, end to end

Add the repo's first remote SPM package, start the SDK at launch behind a testable factory, and
prove one deliberately triggered crash lands as an event in the Sentry dashboard. DSN is empty by
default, so this skeleton cannot leak from normal builds; it is not production-shippable by
construction.

**Files**: `SingleThread.xcodeproj/project.pbxproj`, `SingleThread/SentryConfiguration.swift`,
`SingleThread/SentryBootstrap.swift`, `SingleThread/SingleThreadApp.swift`,
`SingleThread/Info.plist` (or generated-plist build-setting seam), `SingleThreadTests/SentryConfigurationTests.swift`

**Key changes**:
- `struct SentryConfiguration: Equatable, Sendable { let dsn: String; let environment: String; let maxBreadcrumbs: Int; let sendDefaultPii: Bool; let tracesSampleRate: Double }`
- `static func SentryConfiguration.make(dsn: String?, environment: String) -> SentryConfiguration?` — `nil` when DSN is nil/empty/whitespace ⇒ no `SentrySDK.start`
- `enum SentryBootstrap { static func startIfEnabled() }` — reads DSN from the `SENTRY_DSN` Info.plist key, maps to `SentryOptions`, calls `SentrySDK.start` once on the main thread
- `SingleThreadApp.init()` calls `SentryBootstrap.startIfEnabled()` before `@State viewModel`

**Contract**: `SentryConfiguration.make` is pure and imports no Sentry; `SentryBootstrap.startIfEnabled()`/`stop()` are the only SDK entry points. `SENTRY_DSN` (build setting → Info.plist) is the DSN source of truth.

**Tests**: `SentryConfigurationTests` — empty/whitespace DSN ⇒ `nil`; `sendDefaultPii == false`; `tracesSampleRate == 0`; environment maps debug vs release. Happy path + one sad path (no DSN ⇒ no start).
**Verify**: `scripts/test-one.sh SingleThreadTests/SentryConfigurationTests`; manual — Debug simulator build with `SENTRY_DSN` set, trigger a deliberate test crash, confirm the event appears in the dashboard.

---

## Phase 2: Privacy scrubber — no reminder content can leave the device

Wire the allow-list `beforeSend`/`beforeBreadcrumb` scrub and prove a constructed event carrying a
reminder title, note, or list name comes out with none of it — the release gate for enabling capture.

**Files**: `SingleThread/SentryScrubber.swift`, `SingleThread/SentryBootstrap.swift`, `SingleThread.xcodeproj/project.pbxproj` (link Sentry to `SingleThreadTests`), `SingleThreadTests/SentryScrubberTests.swift`

**Key changes**:
- `enum SentryScrubber { nonisolated static func scrub(_ event: Event) -> Event?; nonisolated static func scrub(_ breadcrumb: Breadcrumb) -> Breadcrumb? }` — `user = nil`, allow-list-only `extra`/`request`/`modules`/`tags`, breadcrumb keeps category/level/timestamp and drops message/data
- `SentryBootstrap`: `options.beforeSend`/`beforeBreadcrumb` delegate to `SentryScrubber`, returning `nil` to drop

**Contract**: scrubber is pure, `nonisolated`, `Sendable`-safe, and returns `nil` for anything not allow-listed. Later slices must not add event/breadcrumb fields outside the allow-list.

**Tests**: `SentryScrubberTests` — reminder title/note/list name placed in `extra`, `user`, and breadcrumb message/data never survive; benign allow-listed fields do survive.
**Verify**: `scripts/test-one.sh SingleThreadTests/SentryScrubberTests`; manual — repeat the Phase 1 test crash and confirm no reminder text in the dashboard event.

---

## Phase 3: Consent toggle — the user can turn crash reporting off and back on

Add `CrashReportingPreference` (default on), a Settings "Share crash reports" toggle with caption,
and start/close wiring, so opting out stops the SDK and opting back in restarts it.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/CrashReportingPreference.swift`, `SingleThread/SettingsBindings.swift`, `SingleThread/SettingsView.swift`, `SingleThread/SentryBootstrap.swift`, `SingleThread/SingleThreadApp.swift`, `SingleThreadTests/CrashReportingPreferenceTests.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `struct CrashReportingPreference { init(defaults: UserDefaults = .standard); var isEnabled: Bool { get set } }` — absent key ⇒ `true`; `UserDefaults.standard` (not App Group — device-local, not watch-synced)
- `SentryBootstrap.setEnabled(_ enabled: Bool)` — `SentrySDK.close()` when off, `startIfEnabled()` when on; `startIfEnabled()` now consults the preference
- `SettingsBindings` gains the crash-reporting binding; `SettingsView` gains the toggle + `SettingsCaption` + `.accessibilityIdentifier`

**Contract**: `CrashReportingPreference` is the single consent source; `SentryBootstrap.setEnabled(_:)` is the only toggle-driven SDK control.

**Tests**: `CrashReportingPreferenceTests` — absent key ⇒ enabled, set/toggle round-trip, injected defaults; `SettingsViewTests` — toggle reflects and persists through the binding.
**Verify**: `scripts/test-one.sh SingleThreadTests/CrashReportingPreferenceTests` (+ `SettingsViewTests`); manual — toggle off, trigger crash, no event; toggle on, crash, event returns.

---

## Phase 4: Truthful disclosures — manifest, in-app copy, App Store label

Ship `PrivacyInfo.xcprivacy`, add the 5th `crashReports` privacy section, reword the "only network
request" absolute, and update the ASC label to Diagnostics → Crash Data, so disclosure matches
behavior.

**Files**: `SingleThread/PrivacyInfo.xcprivacy` (new), `SingleThread.xcodeproj/project.pbxproj` (resource inclusion, if the synchronized group misses it), `SingleThread/PrivacySettingsContent.swift`, `SingleThread/Resources/Localizable.xcstrings` (all 6 languages), `SingleThreadTests/PrivacySettingsContentTests.swift`; ASC label (dashboard, not code)

**Key changes**:
- `PrivacyGuideContent.sections(in:)` returns 5, adding a `crashReports` section naming Sentry, the toggle condition, and "never reminder content"
- `background` section: drop "This is the app's only network request"; `closingLine` and the `reminders` "never sent to a third party" phrasing stay (still true)
- `PrivacyInfo.xcprivacy`: Crash Data (`linked=false`, `tracking=false`, purpose AppFunctionality) + Sentry reason codes `CA92.1`/`1C8F.1`/`35F9.1`/`C617.1`; `NSPrivacyTracking = false`

**Contract**: 5 sections with stable id `crashReports`; manifest declared on the app target. No code outside the app target consumes these.

**Tests**: `PrivacySettingsContentTests` (updated) — 5 sections, crash section names Sentry, all six languages resolve, non-English values differ from English, no-analytics closing line still holds.
**Verify**: `scripts/test-one.sh SingleThreadTests/PrivacySettingsContentTests`; manual — archive and inspect the Privacy Report to confirm the manifest merges under SPM/static linking.

---

## Phase 5: Symbolicated per-crash alert — dSYM upload + triage docs

Xcode Cloud uploads archive dSYMs via `sentry-cli`, a Sentry alert rule emails per crash, and
`docs/CrashReporting.md` documents triage.

**Files**: `ci_scripts/ci_post_clone.sh` (new, +x), `ci_scripts/ci_post_xcodebuild.sh` (new, +x), `docs/CrashReporting.md` (new); Sentry dashboard alert rule (not code)

**Key changes**:
- `ci_post_clone.sh` installs `sentry-cli` (guarded, `set -e`-safe)
- `ci_post_xcodebuild.sh` no-ops unless `CI_ARCHIVE_PATH` is set, then `sentry-cli debug-files upload --org "$SENTRY_ORG" --project "$SENTRY_PROJECT" "$CI_ARCHIVE_PATH"` with `SENTRY_AUTH_TOKEN` from Xcode Cloud env only
- `docs/CrashReporting.md` captures the alert rule, region/plan, and triage steps

**Contract**: none downstream (terminal slice). Scripts are non-zero-exit-safe and read credentials only from Xcode Cloud env.

**Tests**: no unit target (scripts only run on Xcode Cloud) — mitigate with `bash -n` on both scripts.
**Verify**: `bash -n ci_scripts/ci_post_clone.sh ci_scripts/ci_post_xcodebuild.sh`; manual — archive on Xcode Cloud, confirm dSYMs in Sentry, a Release test crash shows a symbolicated stack, and the alert email arrives.

---

## Phase 6: Hardening — sad paths, both platforms, toolchain noise

Cover the edge states and toolchain fallout the feature slices deferred: boot-time race, disconnect
paths, and SDK-side Periphery/warning noise.

**Files**: `SingleThread/SentryBootstrap.swift`, `SingleThread/SentryConfiguration.swift`, `scripts/xcodebuild-warnings.allow` (only if a genuine toolchain diagnostic needs a one-line rationale), `SingleThreadTests/SentryConfigurationTests.swift`, `SingleThreadTests/CrashReportingPreferenceTests.swift`, `SingleThreadTests/SentryScrubberTests.swift` (additions)

**Key changes**:
- Off→on→off toggle cycle and empty-DSN state covered as explicit sad paths; macOS uncaught-NSException behaviour decided and tested/documented
- Background-thread / app-hang / watchdog-termination capture verified; any scrubber or bootstrap concurrency fix made `nonisolated`/`Sendable`-correct under Swift 6 strict concurrency
- Periphery findings from the new SPM dependency triaged per the `periphery` skill (SDK-side findings expected, not "fixed")

**Contract**: no new interface — only additional tests/guards around the existing `SentryConfiguration`, `SentryBootstrap`, and `SentryScrubber` contracts.

**Tests**: added sad-path cases in the three existing suites.
**Verify**: `make lint`, `make periphery`, and `scripts/test-one.sh` for the three suites; manual — trigger crashes on both iOS and macOS to confirm capture and scrubbing.

---

## Testing Checkpoints

- After Phase 1: `SentryConfigurationTests` green + one dashboard event → proceed.
- After Phase 2: `SentryScrubberTests` green + no reminder text in the dashboard event → proceed.
- After Phase 3: `CrashReportingPreferenceTests` + `SettingsViewTests` green + toggle-off suppresses capture → proceed.
- After Phase 4: `PrivacySettingsContentTests` green + Privacy Report shows the manifest → proceed.
- After Phase 5: `bash -n` clean + symbolicated Release crash and alert email confirmed → proceed.
- After Phase 6: `make lint`, `make periphery`, targeted suites green → run the full `./scripts/test.sh` gate once via `run-gate`.

## Risks Carried Forward

- Exact `SentryOptions` spellings (session-tracking flag, hang/watchdog names, `beforeSend` signature) must be read off the resolved 9.26.x package, never memory — Phase 1/2.
- Whether `PrivacyInfo.xcprivacy` is picked up by the synchronized file group without a pbxproj resource edit — Phase 4.
- Xcode Cloud `ci_scripts` behaviour is invisible to the gate — Phase 5 manual archive is the only proof.
- US data region + free Developer plan is a stated reading, unconfirmed by the user.