# Structure Outline

## Approach
A compiler-driven mechanical rename of "project" → "list" across all layers,
staged so that **Swift symbols move first** (zero behavior change, easy eye
review) and **raw string literals move second** (all copies of each key in one
atomic step, per the design's lockstep rule). Two small behavior fixes follow:
context-clobbering and dead watch push wiring. Final phase runs the full CI
gate.

---

## Phase 1: Symbol & File Rename (no string changes)

Renames every Swift symbol and file from project → list terminology while
leaving all string literals (`"excludedProjectTitles"`, `"excludedProjects"`,
`"--ui-testing-excluded"`, `"Excluded Projects"`) untouched. Behavior is
byte-for-byte identical afterward; the diff is pure naming and easy to review
by eye (the design's stated mitigation for grep-completeness risk).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift` (→ `ExcludedListStore.swift`), `ReminderStore.swift`, `SkippedReminderSyncService.swift`, `UITestingSeed.swift`, `SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`, `SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`, `ContentView.swift` previews; tests: `ExcludedProjectStoreTests.swift` (→ `ExcludedListStoreTests.swift`), `ReminderStoreTests.swift`, `SkippedReminderSyncServiceTests.swift`, `UITestingSeedTests.swift`, `SettingsViewTests.swift`, `SingleThreadWatchUITestsFlows.swift`

**Key changes**:
- `struct ExcludedListStore` — file renamed; init params unchanged
- `ReminderStore.excludedListTitles: Set<String>` — renamed property
- `setExcludedListTitles(_:)` / `refreshExcludedListTitles(_:)` — renamed pair, semantics preserved
- `onExcludedListsChanged: ((Set<String>) -> Void)?` — renamed hook
- `availableLists: [String]` — renamed computed property
- `PayloadKey.excludedListTitles` — renamed enum case, raw value still `"excludedProjectTitles"`
- `ExcludedListsView`, `excludedListsBinding`, seed field `excludedProjectTitles` → `excludedLists` (property name only), `inProjectReminder` → list naming

**Verify**: `./scripts/test.sh` passes with no test-logic edits beyond renames; `rg -i 'excludedProject|availableProjects|inProject' --type swift` returns nothing outside string literals; spot-check `git diff` contains no changed quoted strings.

---

## Phase 2: Persisted + Wire Key Literal Rename

Moves the App Group UserDefaults key and WatchConnectivity payload key to
`"excludedListTitles"` in one atomic step — the design flags these raw-literal
copies (store default param, `PayloadKey`, `UITestingSeed.persistedKeys`,
unit-test string assertions) as must-move-together.

**Files**: `ExcludedListStore.swift`, `SkippedReminderSyncService.swift`, `UITestingSeed.swift`, `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `ExcludedListStore.init(defaults:key: String = "excludedListTitles")` — literal change
- `PayloadKey.excludedListTitles: String = "excludedListTitles"` — raw value change
- `UITestingSeed.persistedKeys` — `"excludedProjectTitles"` → `"excludedListTitles"` in reset list
- Test assertions at `SkippedReminderSyncServiceTests.swift:58,319` pin the new dictionary key

**Verify**: `./scripts/test.sh` unit portion passes (string-pinning tests prove alignment); manual: launch in Simulator, toggle an exclusion in Settings, relaunch app, confirm it stays toggled (plist round-trip under new key).

---

## Phase 3: Seed Seam + User-Facing Copy

Renames the test-only seed surface and all user-visible strings to "Excluded
Lists". Zero device impact; completes the user-facing half of the rename.

**Files**: `UITestingSeed.swift`, `SingleThreadApp.swift`, `SingleThreadWatchApp.swift`, `SingleThread/SettingsView.swift`; tests: `SingleThreadTests/UITestingSeedTests.swift`, `SettingsViewTests.swift`, `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`

**Key changes**:
- Seed JSON key `"excludedProjects"` → `"excludedLists"` (CodingKeys / property from Phase 1)
- Launch arg `--ui-testing-excluded` → `--ui-testing-excluded-list` (consumed in `SingleThreadWatchApp.swift:74-89`)
- `"Excluded Projects"` → `"Excluded Lists"` (Label :183, navigationTitle :34); footer → `"Excluded lists are hidden from the reminder list."`
- Watch UI test launches with `["--ui-testing", "--ui-testing-excluded-list", "Work"]`

**Verify**: `./scripts/test.sh` passes including the watchOS exclusion UI flow; manual: run the app, confirm Settings row reads "Excluded Lists" with new footer.

---

## Phase 4: Fix Application-Context Clobbering

`pushExcludedListTitles` currently sends a single-key context that wipes other
context keys (skips, sort, date). It now re-carries `skippedReminderIdentifiers`,
mirroring `pushSortOption`'s shape (:118-128).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `func pushExcludedListTitles(_ titles: Set<String>)` — context becomes `[skippedReminderIdentifiers: …, excludedListTitles: titles]`
- Updated assertion in `pushExcludedListTitlesUpdatesApplicationContext()` pins **both** keys present

**Verify**: `xcodebuild test -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests …` passes; manual: pair phone + watch simulators, change an exclusion, confirm skips still render filtered on watch after re-activation.

---

## Phase 5: Remove Dead Watch Push Wiring

Deletes the unreachable push-hook wiring in `SingleThreadWatchApp.swift:48`;
adds a comment documenting that exclusion sync is phone→watch only. Receive
path stays intact.

**Files**: `SingleThreadWatch/SingleThreadWatchApp.swift`

**Key changes**:
- Removed: `service.onExcludedListsChanged` wiring on watch (no watch caller of `setExcludedListTitles` exists)
- Added explanatory comment at the removal site

**Verify**: build succeeds; `make periphery` clean (confirms nothing else referenced the removed closure assignment); watch UI tests pass.

---

## Testing Checkpoints
- **After Phase 1**: full gate green; diff contains no changed string literals — safe rollback point if rename review finds collateral damage.
- **After Phase 2**: persisted/wire literals aligned everywhere; string-pinning unit tests green; manual plist persistence check done.
- **After Phase 3**: user-facing copy and seed/launch-arg surface fully renamed; watch exclusion UI flow green.
- **After Phase 4**: exclusion pushes carry skips + exclusions; sync suite green.
- **After Phase 5**: no dead watch wiring; Periphery clean; final `./scripts/test.sh` gate green before PR.

## Notes on Slicing Limits
The Phase 1 rename cannot be split further vertically: Swift symbols are
coupled by compilation across app/core/test targets, so partial renames yield
non-compiling intermediates. Phases 2–4 are genuinely independent — if Phase 4
slips, Phases 1–3 still deliver the complete rename as a shippable unit.
