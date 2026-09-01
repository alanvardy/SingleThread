# Design Discussion

## Current State

`SingleThread/ContentView.swift` is **817 raw / 815 measured lines** (SwiftLint
counts all physical lines; `.swiftlint.yml:33-35`). Two directives suppress
warnings: `// swiftlint:disable file_length` (line 5) and `// swiftlint:disable:next
type_body_length` (line 13; struct body measures 563). The `file_length` warning
threshold sits at **700** after a bump from 650 in `efa156e` (VAR-743 pin-wallpaper
work, 2026-08-30; commit comment `.pi/qrspi/.../implement.md:25`: "The plan bars
refactoring ContentView to shrink it, so the warning threshold was raised
instead. This is the one out-of-scope file change."). A follow-up commit
`e5b05d4` titled "Revisit ContentView file_length threshold" changed nothing.

The single-screen UI deliberately concentrates every view modifier in one struct
(file header comment, 1-4). This single decision drives all three constraints:
file length, type-body length, and the compiler's single-expression type-check
budget. Three extractions already work around the compiler (`setBackgroundPinned`,
633-635; `settingsSheetContent`, 578-582; `settingsSheetWritebacks`, 587-622),
and one iOS extension (686-737) was split out to stay inside `type_body_length`.

Three other repo files carry file-length disables (`ReminderStoreTests.swift:8`,
`SingleThreadUITestsFlows.swift:13`) — each with explanatory headers matching
ContentView's pattern. The codebase already uses file-scope extensions to move
members out of a struct body (ContentView's iOS extension, 686-737), and
separate View types are the dominant convention for new views (`ReminderCardView`,
`SettingsView`, every settings sub-screen). No view models reach views on iOS
beyond `ContentViewModel`/`SettingsViewModel` — everything else is plain values
and `Binding`s.

Tests that directly instantiate `ContentView`: `SingleThreadTests.swift:15,26`
(`init(viewModel:)`) and `MicrophoneToggleTests.swift:39,66,83,99`
(`init(loadsReminders:speechTranscriber:)`). UI tests depend only on
accessibility identifiers and launch-arg seams — never on type names.

## Desired End State

1. **`file_length` threshold restored to 650** in `.swiftlint.yml`, with the
   line-5 `file_length` disable removed from ContentView.
2. **`type_body_length` disable removed** (line 13) — the struct body falls
   under the 500 warning on its own.
3. **Zero new warnings** from `swiftlint lint --strict`.
4. **No behavioral changes** — every test passes; no UI, accessibility, or
   state-flow regressions.
5. **Threshold stays at 650 long-term** — the extracted files are small and
   single-concern, so future additions land in the right file naturally.

Verification: `./scripts/test.sh` green; `make lint` green; `swiftlint lint
--strict` reports 0 violations; 650 warning line in `.swiftlint.yml` is not
hit.

## Patterns to Follow

- **One View per file + companion extensions in same-dir sibling files.**
  `ReminderCardView.swift` (extracted from the original monolithic view),
  `SettingsView.swift`, `InterfaceSettingsView.swift`, etc. Precedent: every
  settings sub-screen is its own file (SingleThread/).

- **File-scope `extension ContentView` for non-view plumbing.** The existing iOS
  extension (686-737) is the exact pattern: `private extension ContentView`
  inside `#if os(iOS)` to house helpers and test seams that don't render views.
  We extend this pattern to settings bag plumbing.

- **Previews co-located with source, not inline.** The codebase has no
  established convention (every view keeps previews in-source), but SwiftUI
  tooling doesn't care about file boundaries — Xcode discovers `#Preview`
  blocks in any file under the target. `ContentView+Previews.swift` is a
  lightweight convention that matches the extension pattern.

- **Input style: `Binding`s and plain values, not view models.** Settings
  sub-views receive individual `@Binding`s sliced from the bag
  (`SettingsView.swift:54-91`). ReminderCardView receives `ReminderDisplay` +
  Bools + `Binding<Bool>` (`ContentView.swift:385-391`). No new ViewModel
  types on iOS.

- **`@AppStorage` stays at the View level.** The 19 `@AppStorage` properties
  (ContentView.swift:179-240) remain in `ContentView` — they're the single
  source of truth for persisted preferences. Extracted helpers access them
  through the `ContentView` instance (self), same as today.

### Patterns NOT to follow

- **Raising the threshold** (650→700 in `efa156e`) — the task explicitly
  prefers decomposition. No threshold bumps in this change.
- **Do NOT create a new View struct for settings plumbing.** `makeSettingsBag`
  and `settingsSheetWritebacks` are non-view code; creating a `SettingsBagBuilder`
  or similar type would add indirection with no benefit. File-scope extension
  is the right granularity.
- **Do NOT extract `reminderList` as a separate View type on this ticket.**
  That's scope creep. It would need its own binding/@AppStorage surface and
  test isolation work — a separate ticket if desired later.

## Design Decisions

1. **Ambition: moderate decomposition.** Extract previews (~80 lines), iOS
   extension (~52 lines), and settings-bag plumbing (~75 lines) into three
   files. This removes ~207 lines from ContentView.swift — landing at ~610
   raw lines, cleanly under the 650 warning. No new View types, no test
   behavioral changes, no binding/app-storage re-plumbing.

2. **Extraction pattern: file-scope extensions, not new View types.**
   `ContentView+Previews.swift`, `ContentView+iOS.swift`, and
   `ContentView+Settings.swift` — all `extension ContentView` at file scope.
   This gives direct access to `@AppStorage`/`@State`/`@Environment`
   properties without threading through initializers. Matches the existing iOS
   extension precedent (686-737).

3. **Remove both disables.** Extracting `makeSettingsBag` (640-678) and
   `settingsSheetWritebacks` (587-622) to an extension drops the struct body
   from 563 measured lines to ~488 — under the 500 warning. The line-13
   `type_body_length` disable and line-5 `file_length` disable both go away.

4. **Previews: separate file, keep all 6.** `ContentView+Previews.swift`
   holds all helper functions and `#Preview` blocks currently at 739-817. No
   previews are deleted — they're harmless and still useful when separated.

5. **Threshold: restore 650, keep error at 800.** `.swiftlint.yml` line 33
   changes `warning: 700` back to `warning: 650`. Error stays at 800.
   `type_body_length` stays at 500/600 — no config change needed there since
   the body falls under 500 naturally.

6. **No new tests required.** The extraction is pure code movement — no logic
   changes. Existing unit tests (SingleThreadTests.swift, MicrophoneToggleTests.swift)
   still compile and pass against the rehomed members (extensions on the same
   type are visible wherever the type is imported). UI tests are unaffected
   (identifier-based, not type-based). If anything, this is verified by the
   existing gate: `./scripts/test.sh` must stay green.

## What We're NOT Doing

- **Not refactoring the View hierarchy.** No new View structs, no breaking up
  `body`, no changes to modifier chains or type-check extraction.
- **Not touching `type_body_length` or `function_body_length` config values.**
  Both stay at their current thresholds. We're just removing the disable.
- **Not adding a "max extracted" precedent.** Future additions to ContentView
  that push it back over 650 should land in the appropriate extension file,
  not trigger another threshold discussion. But we're not codifying that as a
  rule — just establishing the pattern.
- **Not changing bag write-back behaviour.** `backgroundPinned`'s missing
  write-back (research Q5) is out of scope — it's a pre-existing bug, not
  related to file organization.

## Open Risks

- **Preview canvas breakage risk is low but nonzero.** Xcode's canvas
  discovers `#Preview` blocks across the target, not just the main file — but
  if it has a bug with extension files, previews stop working. Mitigation:
  this is a well-established pattern across the SwiftUI community; if it
  breaks, revert the preview move and extract more non-view code instead.
- **Import visibility for `EKEventStore` in the preview file.** The preview
  helpers use `EKEventStore`, which is imported via `EventKit` — already
  available in ContentView.swift. The preview file may need its own `import
  EventKit` if not transitively visible. Low risk, caught at compile time.
- **`private extension` access control.** `makeSettingsBag` and
  `settingsSheetWritebacks` are currently struct members (implicitly
  internal). Moving them to a `private extension ContentView` in a separate
  file should work (Swift allows `private` extensions on a type to access
  `private` members, and file-private members are visible to any extension in
  the same file — but extensions in *different* files need at least
  `internal` access). Mitigation: verify access control compiles; promote
  members from `private` if needed.