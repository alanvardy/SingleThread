# Phase 3 Report: Phone → watch → widget propagation

Branch: `alanvardy-var-1034-set-language` · Commit: `1e32d5e7` ("Phase 3: language sync to watch and widget") · Pushed: f346a101..1e32d5e7 (fast-forward)

## What was implemented (per plan.md lines 657–865)

### SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift
- `PayloadKey.appLanguage = "appLanguage"` added (after `sortOption`).
- Stored props `appLanguageStore: AppLanguagePreference` and `sendsAppLanguage: Bool`; init params
  `appLanguageStore: AppLanguagePreference = AppLanguagePreference()` and `sendsAppLanguage: Bool = false`
  (mirrors the `sendsShowDate` pattern); both assigned in `init`.
- `pushAll()`: after the `sortOption` entry, `if sendsAppLanguage { context[PayloadKey.appLanguage] = appLanguageStore.load().rawValue }`.
- New write-once hook `public nonisolated(unsafe) var onAppLanguageReceived: ((AppLanguage) -> Void)?` with the
  same doc-comment rationale as `onShowDateReceived`.
- `apply(context:)` decodes the key with the plan's exact snippet (persist → snapshot → fire hook,
  `AppLanguage(rawValue: rawValue) ?? .system`); absent key ⇒ no-op.

**Adaptation (adheres to strict lint):** SwiftLint `--strict` rejected the plan's placement of the decode
inside `apply(context:)` (function body grew to 52 lines vs the 50-line limit — the reason `applyRemaining`
exists per its own doc comment). The decode was moved, verbatim, into the file's established overflow method
`applyRemaining` (right after the `enableActionButtons` decode; that method's doc comment was updated to
list app language). Functional behavior is identical: decode → persist → notify, same ordering, same hook.
This is the repo's own documented mechanism for this exact limit, not a redesign.

### SingleThread/AppViewModel.swift (phone)
- `SkippedReminderSyncService` built with `sendsAppLanguage: true` (setupSyncService).
- `handlePreferencesChanged()` (App-Group `UserDefaults.didChangeNotification` diff): added
  `let currentAppLanguage = AppLanguagePreference().load()`, extended the change condition with
  `|| currentAppLanguage != lastAppLanguage`, and in the branch:
  `AppLocaleState.current.set(currentAppLanguage)` (idempotent; covers writers that only touch the App-Group
  key) plus `lastAppLanguage = currentAppLanguage`, alongside the existing `syncService?.pushAll()`.
- New `private var lastAppLanguage = AppLanguagePreference().load()` next to the other last-seen values.
  (All inside the existing `#if os(iOS)` block — macOS unaffected.)

### SingleThread/InterfaceSettingsView.swift
- Language Picker now has `.onChange(of: appLanguage) { _, _ in viewModel.showPreferenceChanged() }`
  gated `#if os(iOS) || os(macOS)`, matching the neighbouring pickers' pattern
  (ReminderSettingsView toggles / SettingsViewModel.showPreferenceChanged gate). This fires the existing
  `WidgetCenter.shared.reloadAllTimelines()` chokepoint.

### SingleThreadWatch/WatchAppViewModel.swift
- `makeSyncService()` passes `appLanguageStore: AppLanguagePreference(defaults: .standard)` and
  `sendsAppLanguage: false` (declaration-order: `sendsShowDate: false, sendsAppLanguage: false, …` —
  the Swift compiler requires named args in declaration order, caught on the first build attempt).
- `wireStateReceiveHooks(_:)` adds `service.onAppLanguageReceived = { value in
  Task { @MainActor in AppLocaleState.current.set(value) } }` (mirrors the show-* hooks).

### SingleThreadWatch/SingleThreadWatchApp.swift
- `WindowGroup { WatchReminderView(...) .environment(\.locale, AppLocaleState.current.effectiveLocale) }`.
- Needed `import SingleThreadCore` (compiler error on first build attempt).

### SingleThreadWatch/Resources/Localizable.xcstrings
- Of the four plan-targeted literals (WatchReminderView.swift:55, 167, 303, 319), **two were already keyed**
  ("Enable Reminders access in Settings" and "Upgrade on\nyour iPhone" — present in the catalog from an
  earlier phase). Added the two missing keys with all six languages (en, zh-Hans, es, ja, de, fr):
  "Couldn't reschedule. Try again with your iPhone nearby." and "Your reminder wasn't updated."
  Code in `WatchReminderView.swift` unchanged (they already defer via `LocalizedStringKey`).

### SingleThreadWidget/NextThingWidget.swift
- `NextThingWidgetView(entry: entry).environment(\.locale, AppLanguagePreference().load().locale)
  .containerBackground(.fill.tertiary, for: .widget)`.

## Tests added

### SingleThreadTests/AppLanguageSyncTests.swift (NEW, mirrors EnableActionButtonsSyncTests)
`#if os(iOS) || os(watchOS)`, `@MainActor @Suite(.serialized)`, uses the shared `FakeSession` from
`TestFixtures.swift` and isolated `.standard` keys with UUID suffixes. Three tests (plan's exact bodies):
- `pushPayloadCarriesLanguageWhenSet` — pushes `"de"` for `sendsAppLanguage: true`.
- `pushPayloadOmitsLanguageWhenNeverSet` — `sendsAppLanguage` default false ⇒ key absent.
- `applyContextPersistsLanguageAndFiresHook` — persists to the injected store, fires the hook with
  `.japanese`, and an absent key is a no-op (with `removeObject` defer).

### SingleThreadWatchTests/WatchSyncPipelineTests.swift (NEW suite in existing file)
- `@MainActor @Suite(.serialized)` (the hook persists through the real `.standard` "appLanguage" key):
  `WatchAppLanguageSyncTests/watchAppLanguageReceiveUpdatesLocaleState` — constructs the service with an
  isolated `.standard` preference, delivers `["appLanguage": "ja"]` via `session(_:didReceiveApplicationContext:)`,
  asserts `pref.load() == .japanese` (persisted) and `state.language == .japanese` (locale state updated).
  Uses the existing `WatchFakeSession` (SingleThreadWatchTests/TestFixtures.swift). Name free of a `test` prefix.

## Verification (automated, all green on the final committed source)

| Command | Result | Evidence |
|---|---|---|
| `scripts/test-one.sh SingleThreadTests/AppLanguageSyncTests` | PASS | `ok: 3 case(s) ran` |
| `make watch-test` | PASS (exit 0) | 53/53 cases passed; `WatchAppLanguageSyncTests/watchAppLanguageReceiveUpdatesLocaleState() passed` |
| `make watch-build` | PASS (exit 0) | `** BUILD SUCCEEDED **` |
| `make format && make lint` | PASS (both exit 0) | `Found 0 violations, 0 serious in 193 files` |

Extra compile evidence: the iOS test run compiled the full iOS scheme (app + unit + UI test targets +
widget) — `SingleThreadWidget.appex` product re-stamped after the NextThingWidget edit; watch-test/watch-build
were re-run after the final line-wrap adjustment (`sendsShowDate` line split for line_length 120) and stayed green.

## plan.md
Automated checkboxes (lines 851–854) flipped `- [ ]` → `- [x]`. Manual items, prior phases, and the
Testing-checkpoint table untouched.

## Observations / adaptations
1. Decode placement moved to `applyRemaining` (strict-lint 50-line body limit) — semantics unchanged.
2. Only 2 of the 4 watch literals needed catalog additions (2 already present).
3. Two build iterations were needed before green: `import SingleThreadCore` in SingleThreadWatchApp.swift and
   named-arg declaration order in `makeSyncService()`.
4. **Pre-existing, not Phase 3:** `make mac-build` fails at HEAD and on origin/main (macOS compile of
   `SingleThread/AppViewModel.swift:22` — `SkipSyncSession` in `session:` init param, iOS/watchOS-only,
   since commit 0bcce49f — plus `SingleThread/SingleThreadApp.swift:19` `\.locale` inference from Phase 1).
   The `./scripts/test.sh` gate does not build macOS, so this does not block Phase 3; the CI `mac-tests`
   job will be red for any main push until addressed. Phase 3's macOS-relevant code (InterfaceSettingsView
   `.onChange`, AppViewModel changes — iOS-gated) compiled cleanly in the macOS batch (no error for those files).
5. Manual items (watch-pair UI flip, widget live refresh, relaunch persistence) intentionally not run —
   outside the phase's automated contract.

## Residual risks
- macOS compilation of the app is broken at HEAD/`origin/main` (pre-existing, see above) — needs a decision on
  follow-up; does not affect the iOS/watch gate.
- Widget live-relabel behavior (`.environment(\.locale)` inside `StaticConfiguration`) is compile-verified but
  functionally unverified off-device (manual item).
- The full `./scripts/test.sh` gate has not run (by design — runs once post-Phase 6 via run-gate).