# Implementation Summary

Ticket: `alanvardy-var-769` — Collapse 6 × `Show*Preference` into a generic `BoolPreferenceStore`
Branch: `alanvardy-var-769-refactor-collapse-6-×-showpreference-into-a-generic`

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `25effdb` | BoolPreferenceKey — key constants + tests |
| 2     | `66f0b36` | BoolPreferenceStore — generic store + tests |
| 3     | `877a967` | Replace Show*Preference call sites with BoolPreferenceStore + remove old code |

## Automated Checks

- [x] `BoolPreferenceKeyTests` — 6 parameterized rawValue checks + exhaustive + Sendable-cast suite passes (run via UDID-pinned `xcodebuild`; plan's `make test SIM=iPhne 17,OS=26.1` command was typo'd and OS=26.1 doesn't exist on this machine)
- [x] `BoolPreferenceStoreTests` — absent-fallback, round-trip, overwrite, defaults-injection suites pass
- [x] `make format` (SwiftFormat + SwiftLint --fix)
- [x] `make lint` (SwiftFormat --lint + SwiftLint lint --strict) — 0 violations
- [x] `./scripts/test.sh` full CI gate: format, lint, iOS build-for-testing, watch build, Periphery ("No unused code detected"), iOS unit tests, iOS UI tests, watch UI tests, watch unit tests, macOS unit tests — all green
- [x] Periphery confirms zero dead code / lingering references to the six removed structs

## Plan Deviations (resolved during implementation)

1. **Sendable dropped** (Phase 2, supervisor-approved): `UserDefaults` does not conform to `Sendable` under Xcode 26.5 / Swift 6 — the plan's design premise was factually wrong. `BoolPreferenceStore` is a plain `public struct` exactly like the old `Show*Preference` structs and `SortOptionStore`; the `isSendable()` store test was dropped. The `BoolPreferenceKey` enum keeps its `Sendable` conformance (String-backed, tests include the cast check).
2. **Plan bug — showList fallback**: plan's Stage 3a.1 "After" block showed `showListStore fallback: true`; the old `ShowListPreference` uses `?? false`, and the plan's own Stage 1 spec + Stage 3c.1 say `false`. Used `fallback: false` everywhere (AppViewModel read/cache, widget, watch states/tests, sync-service tests).
3. **Stale file shapes**: `AppViewModel` wires 4 stores (no list/undated) and has no `showCompletionGlowStore` field; `ReminderStore.showsUndatedReminders` is already a plain `Bool` with `didSet` (not store-backed); `ContentViewModelTests.swift` never injects glow preference; `CompletionGlowViewModelTests.swift` doesn't exist (real file: `CompletionGlowTests.swift`). All adapted without behavior change; `ReminderStore.swift` and `ContentViewModelTests.swift` untouched.
4. **Verification commands**: plan's `make test SIM=… ,OS=26.1` invocations were typo'd/mismatched with installed runtimes (iOS 26.5/27.0 only); replaced with UDID-pinned `xcodebuild -only-testing:` runs. plan.md checkbox text kept verbatim.
5. **Lint adaptations**: `AppViewModel` gained a small documented static `showPreferenceStore(_:fallback:)` helper (init was already at the `function_body_length` limit); `SkippedReminderSyncServiceTests.swift` gained `// swiftlint:disable file_length` at the top (4 lines over the 650 limit, mirroring the `ReminderStoreTests.swift` precedent). No functional impact.
6. **`BoolPreferenceStore.init` lint directive**: `// swiftlint:disable:next function_default_parameter_at_end` keeps the plan's `(defaults:key:fallback:)` argument order (required to preserve the plan's call-site syntax; reordering breaks every `defaults:key:fallback:` call site).

## Manual Verification Items (from the plan — not yet done)

- [ ] Run app once with `--seed` launch arg to confirm seeded prefs round-trip
- [ ] Run app once with `--reset-glow-preference` to confirm the `.standard` vs App-Group glow-seam mismatch still works
- [ ] Toggle each of the six preferences in Settings → confirm they persist across app restart
- [ ] Confirm watch app receives preference changes from phone

## Notes for Review

- Two suppression comments were required to satisfy `--strict` lint (see deviations 5–6) — both scoped and documented; flag for a second opinion in review if desired.
- The Phase 1 subagent force-pushed after a clean rebase of the 8 pre-existing commits (their 2 remote-only commits were patch-equivalent duplicates); local and remote are in sync.
- Untracked QRSPI planning artifacts (`.research/`, `conventions.md`, `design.md`, `research.md`, `structure.md`) were intentionally left untracked; consider committing them if they should live with the branch.