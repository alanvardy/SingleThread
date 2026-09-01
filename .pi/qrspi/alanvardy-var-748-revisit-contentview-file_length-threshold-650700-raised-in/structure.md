# Structure Outline

## Approach

Pure code-movement decomposition: move three self-contained regions out of
`SingleThread/ContentView.swift` into sibling `extension ContentView` files
(previews, iOS notifications, settings-bag plumbing), then restore the
`file_length` warning to 650 and delete both `swiftlint:disable` directives. No
behavior change, no new View types, no new tests (per design — this is movement,
not logic).

"Layers" here are **dependency-ordered extraction stages**, bottom-up. Each
stage compiles, passes the existing regression suite, and keeps `swiftlint lint
--strict` at 0 before the next begins. The disables stay in place until the
final stage, so every intermediate stage lands green on its own.

Measurements (HEAD, research-verified): ContentView.swift is **817 raw / 815
measured / 563 struct-body** lines. Extraction totals ~205 lines → ~610 file
lines (under 650) and ~488 body lines (under 500).

---

## Stage 1: Previews → `ContentView+Previews.swift`

Moves the preview fixtures and `#Preview` blocks out of the struct's file. This
is the lowest-risk split: it touches nothing the app or tests execute, proves
the sibling-file + extension pattern compiles, and shrinks the file by ~78
lines. It depends on nothing below it.

**Files**: `SingleThread/ContentView.swift` (delete 739–817), `SingleThread/ContentView+Previews.swift` (new)

**Key changes** (moved verbatim, file-private fixtures stay `private`):
- `private let mockPreviewEventStore = EKEventStore()`
- `private let mockReminder: EKReminder`
- `private let mockReminderInList: EKReminder`
- 6 × `#Preview(...)` blocks (all call existing internal `ContentView` inits)
- New file needs `import EventKit`, `import SingleThreadCore`, `import SwiftUI` (the preview fixtures reference `EKEventStore`/`EKReminder`/`EKCalendar`).

No access-control changes — `#Preview` and the fixtures touch no `private`
ContentView member.

**Tests**: existing regression suite stays green; no new tests (design
[design.md](../design.md) §"No new tests required"). The two suites that
instantiate `ContentView` directly are the guard: `SingleThreadTests.swift:15,26`
and `MicrophoneToggleTests.swift:39,66,83,99` must still compile and pass.

**Verify**: `make build && ./scripts/test.sh --unit-only && make lint` → all green; `wc -l SingleThread/ContentView.swift` ≈ 739.

---

## Stage 2: iOS notifications extension → `ContentView+iOS.swift`

Moves the existing file-scope `private extension ContentView` (686–737) into its
own sibling file. Depends on Stage 1 only for the established pattern; the
extension is already separate from the struct body, so this reduces `file_length`
by ~52 lines. This is the first stage that widens access control.

**Files**: `SingleThread/ContentView.swift` (delete 686–737), `SingleThread/ContentView+iOS.swift` (new)

**Key changes**:
- New file wraps the members in `#if os(iOS)` with an **internal** extension: `extension ContentView { ... }` (not `private`) — the call sites live in `ContentView.swift` (`body`'s `.onChange(of: scenePhase)`, `.onChange(of: notificationsEnabled)`, and the `isNotificationsUITesting` overlay check), so the members must be visible across files.
- `var isNotificationsUITesting: Bool` — computed, internal (was private-to-extension)
- `var notificationStatusOverlay: some View` — computed, internal
- `func handleScenePhaseChange(_ phase: ScenePhase)` — internal
- `func handleNotificationsEnabledChange(_ newValue: Bool)` — internal
- Access widening in `ContentView.swift`: `private let appViewModel: AppViewModel?` → `let appViewModel: AppViewModel?` (the moved members read `appViewModel?.pendingSummary` / `lastScheduleSummary`).

**Tests**: existing suites green. The notification seams (`pendingStatus` /
`lastScheduleStatus` under `--ui-testing-notifications`) must keep rendering —
UI test `NotificationSchedulingUITests`/`NotificationsUITests` cover the flow.

**Verify**: `make build && ./scripts/test.sh --unit-only && make lint` green; optional `./scripts/test.sh --ui-only` to confirm the notification UI seams.

---

## Stage 3: Settings-bag plumbing → `ContentView+Settings.swift`

Moves `settingsSheetWritebacks` (587–622) and `makeSettingsBag` (640–678) out of
the struct body. This is the only stage that reduces **both** counters — it
drops the struct body 563 → ~488 (under the 500 `type_body_length` warning) and
the file to ~610. Highest-risk split: the widest access-control widening and the
`#if os(iOS)` branches must be preserved inside both functions.

**Files**: `SingleThread/ContentView.swift` (delete 587–622 and 640–678), `SingleThread/ContentView+Settings.swift` (new)

**Key changes**:
- `@MainActor func makeSettingsBag() -> SettingsBindings` — internal (was `private`); keeps both the iOS (19-value) and non-iOS (13-value) `SettingsBindings(...)` variants under `#if os(iOS)`.
- `func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View` — internal (was `private`); keeps the staged `withAppearance` → `withIOSPreferences` → `return` write-back chain verbatim.
- Both land in an internal `extension ContentView` (call sites are `settingsSheetContent` and `body`'s gear-button action, in `ContentView.swift`).
- Access widening in `ContentView.swift` (the moved funcs read these directly, per design decision 2):
  - 19 `@AppStorage` properties `private var` → `var`: `appearanceMode`, `textSize`, `allowsLandscape`, `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours`, `showUndatedReminders`, `sortOption`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`
  - `private let viewModel: ContentViewModel` → `let viewModel: ContentViewModel`
  - `private var excludedListsBinding: Binding<Set<String>>` → `var excludedListsBinding`

No behavior change — the `backgroundPinned` missing write-back stays as-is (out
of scope, design "What We're NOT Doing").

**Tests**: existing suites green (no new tests). `SettingsViewTests` renders
`SettingsView` directly and is unaffected; `SingleThreadTests` /
`MicrophoneToggleTests` still compile against the re-homed internal members.

**Verify**: `make build && ./scripts/test.sh --unit-only && make lint` green; confirm `wc -l` ≈ 610 and struct body < 500 (directive-stripped `swiftlint lint` shows no `type_body_length` even with the disable removed).

---

## Stage 4: Restore threshold + remove disables

The acceptance layer. Only safe after Stages 1–3 land, because it converts the
measurement from "silenced" to "enforced": with the disables gone and the
threshold at 650, the ~610-line / ~488-body file must pass on its own. If this
stage is red, Stages 1–3 (code **and** their green tests) remain independently
valuable and can land first.

**Files**: `.swiftlint.yml` (line 33), `SingleThread/ContentView.swift` (header 1–4, directive 5, comment 10–12, directive 13)

**Key changes**:
- `.swiftlint.yml`: `file_length.warning: 700` → `warning: 650` (`error: 800` unchanged).
- `ContentView.swift`: remove `// swiftlint:disable file_length` (line 5) and `// swiftlint:disable:next type_body_length` (line 13) + the now-obsolete explanatory comments (10–12).
- Rewrite the stale header comment (1–4) — it currently claims the file sits *above* 650/500 to justify the disables; after this stage it should say the single-screen view is decomposed across sibling extensions so it stays *under* both thresholds.

**Tests**: the permanent assertion becomes `swiftlint lint --strict` → 0
violations across all 136 files **without** any size disables on ContentView.

**Verify**: `make lint` → 0; then full CI-identical gate `./scripts/test.sh` → green (format, lint, build, Periphery, unit + UI tests).

---

## Testing Checkpoints

Resume points if context resets — each line is the gate that must be green before the next stage:

- **After Stage 1**: `make build && ./scripts/test.sh --unit-only && make lint` green; ContentView.swift ≈ 739 lines.
- **After Stage 2**: same three commands green; ContentView.swift ≈ 687 lines.
- **After Stage 3**: same three commands green; ContentView.swift ≈ 610 lines, struct body < 500.
- **After Stage 4**: `make lint` = 0 at 650 with no disables; full `./scripts/test.sh` green.

**Cross-cutting note (access control)**: the only non-layered concern is
`private` → `internal` widening on the `@AppStorage` properties, `viewModel`,
`excludedListsBinding`, and `appViewModel`. It is not unit-testable on its own,
but it is behavior-neutral and is caught at compile time at each stage — the
stages that introduce it (2 and 3) carry it as an explicit listed change, so
it never silently rides along with the file split.
