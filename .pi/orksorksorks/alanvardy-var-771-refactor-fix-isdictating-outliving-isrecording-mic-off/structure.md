# Structure Outline

## Approach

Fix the `isDictating`-flag-outlives-`isRecording` bug by moving the
`isDictating = false` clear to immediately after `transcribe()` returns
(before parse/add/sleep), adding a new `isProcessing` flag for the
post-transcribe tail, and adding a re-entry guard on `startDictation()`.
Each layer is fully tested before the next begins — bottom-up from test seam
through ViewModel state to View rendering.

---

## Stage 1: Test Seam — Continuation Gate on `FakeSpeechTranscriber`

**What**: Add an optional `recordingEndedGate: CheckedContinuation<Void, Never>?`
to the existing `FakeSpeechTranscrber` test double, following the
`GatedBackgroundFetcher` pattern (`BackgroundImageStoreTests.swift:241-253`).
The gate resumes after `isRecording = false` (line 60) and before return,
giving tests a rendezvous point to observe the in-window state after the
recorder tears down but before the ViewModel finishes the flow.

**Files**:
- `SingleThreadTests/ReminderDictationTests.swift` (FakeSpeechTranscriber:10-66)

**Key changes**:
- `var recordingEndedGate: CheckedContinuation<Void, Never>?` — new property on `FakeSpeechTranscriber`
- Resume the gate inside `transcribe()`, after `isRecording = false` (`:60`) and before the error throw (`:61-62`) / return

**Tests**: New test `gateResumesAfterRecordingEnds` in `ReminderDictationTests.swift`:
- Creates a `FakeSpeechTranscriber` with a non-nil `recordingEndedGate`
- Calls `transcribe()` from a `Task`, awaits the gate
- Asserts `fake.isRecording == false` after the gate resumes
- Resumes the continuation and awaits task completion

**Verify**: `make test` passes for `ReminderDictationTests` only:
```fish
set SIM (xcrun simctl list devices available | grep -m1 'iPhone 17 (' | string match -r '([A-F0-9-]{36})' | head -1)
xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,id=$SIM" -configuration Debug build-for-testing
xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,id=$SIM" -configuration Debug test -only-testing:SingleThreadTests/ReminderDictationTests
```

---

## Stage 2: ViewModel State — `isProcessing`, `isDictating` Move, and Re-entry Guard

**What**: Three coordinated changes to `DictationViewModel.startDictation()`:
1. Add `private(set) var isProcessing = false` property (follows the
   `isDictating` convention at `:22`)
2. Move `isDictating = false` from `:87` to immediately after `transcribe()`
   returns (`:68`), and also clear it in the catch block (`:85`)
3. Add `guard !isDictating else { return }` at the top of `startDictation()`
   (`:44`)
4. Set `isProcessing = true` right after the `isDictating = false` clear
   (both the success and catch paths), and clear `isProcessing = false` at
   `:87` (replacing the old `isDictating = false`)

**Files**:
- `SingleThread/DictationViewModel.swift` (lines 22, 44, 62-68, 84-87)
- `SingleThreadTests/ReminderDictationTests.swift` (new tests)

**Key changes**:
- `DictationViewModel`:
  - `private(set) var isProcessing = false` — new property
  - `guard !isDictating else { return }` — re-entry guard at `:44`
  - After `:68` (`transcribe` return): `isDictating = false; isProcessing = true`
  - In catch at `:85`: `isDictating = false` (also added)
  - At `:87`: `isProcessing = false` (replaces old `isDictating = false`)

**Tests** (all in `ReminderDictationTests.swift`, using the gate from Stage 1):
- `isDictatingClearsBeforeParseAddAndSleep` — gate test: `Task { startDictation() }`, await gate, assert `!viewModel.isDictating && !fake.isRecording`, resume gate, await task completion
- `isProcessingSetDuringPostTranscribeTail` — gate test: await gate, assert `viewModel.isProcessing && !viewModel.isDictating`, resume gate, await completion, assert `!viewModel.isProcessing`
- `reentryGuardBlocksConcurrentCalls` — two concurrent `Task { startDictation() }` with gated fake; second call's `isDictating` stays false (bounced at guard), first completes normally
- Existing tests (`startDictationAddsReminderAndFlowsText` `:191-207`, others) still pass — `isDictating` clears earlier but `isProcessing` holds through parse/add/sleep, so functional behavior is preserved

**Verify**: Same targeted build + test as Stage 1, plus the new test names:

```fish
xcodebuild ... test -only-testing:SingleThreadTests/ReminderDictationTests
```

---

## Stage 3: View Rendering — Processing Indicator in `bottomBar`

**What**: Insert a new branch (2a) in the bottomBar if/else-if chain at
`ContentView.swift:660-703`, between the `isDictating` branch (2) and the
`canDictate` branch (3). The new branch renders when `isProcessing` is true:
the transcript text (if non-empty) + a `.progressView()` with "Processing…"
label. The `dictationError` standalone `if` (`:653-659`) is unchanged.

**Files**:
- `SingleThread/ContentView.swift` (bottomBar chain, lines 660-703)
- `SingleThreadTests/MicrophoneToggleTests.swift` (new rendering assertion)

**Key changes**:
- `ContentView.swift` — new `else if viewModel.dictation.isProcessing` branch in the chain at `:670`:
  ```swift
  else if viewModel.dictation.isProcessing {
      VStack(spacing: 6) {
          if !viewModel.dictation.dictationText.isEmpty {
              Text(viewModel.dictation.dictationText)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
          }
          HStack(spacing: 4) {
              ProgressView()
                  .scaleEffect(0.7)
              Text("Processing…")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
          }
          .accessibilityLabel("Processing")
      }
  }
  ```
- Re-number existing branches: old `isDictating` branch stays branch 2, new branch is 2a, old `canDictate` branch becomes 3, old "unavailable" branch becomes 4

**Tests** (in `MicrophoneToggleTests.swift`, following existing `String(describing:)` pattern):
- `processingIndicatorRendersWhenisProcessingIsTrue` — set `viewModel.dictation.isProcessing = true`, assert `String(describing: view.bottomBar)` contains `"Processing…"`, does NOT contain `"Recording"` or `"mic.fill"`
- `processingIndicatorNotRenderedWhenisProcessingIsFalse` — default state, assert bottomBar string does NOT contain `"Processing…"`
- `recordingIndicatorNotRenderedWithProcessingTrue` — `isProcessing = true ∧ dictationText = "Hello"`, assert "Hello" visible but no recording indicator
- Gate on `#if os(iOS)` (matching `MicrophoneToggleTests.swift:232-244` — dictation is iOS-only)

**Verify**: Targeted build + test for both dictation test suites:

```fish
xcodebuild ... test -only-testing:SingleThreadTests/ReminderDictationTests -only-testing:SingleThreadTests/MicrophoneToggleTests
```

---

## Stage 4: Full Gate Verification

**What**: Run the complete CI-identical gate to confirm no regressions across the full suite (62 iOS unit test files, UI tests, watch tests, macOS tests, lint, format, periphery).

**Files**: None (verification only)

**Verify**:
```fish
./scripts/test.sh
```

All stages pass: lint → format-check → build → periphery → unit tests → UI tests → watch tests → macOS tests.

---

## Testing Checkpoints

After each stage, the following must be green before advancing:

| Stage | Checkpoint |
|--------|-----------|
| 1     | `ReminderDictationTests` — gate test + all existing tests pass |
| 2     | `ReminderDictationTests` — new state tests + all existing tests pass |
| 3     | `ReminderDictationTests` + `MicrophoneToggleTests` — all pass |
| 4     | `./scripts/test.sh` — full gate green |

If context resets mid-implementation: resume at the next incomplete stage,
run its targeted test command, and confirm the prior stage's checkpoint still
holds before proceeding.

---

## What This Does NOT Touch

Per design decisions:
- **Zero changes to `ReminderDictation.swift`** — `isRecording`, `tearDownRecording()`, `defer`, `ensureMicrophoneAccess()`, and the entire engine half are untouched
- **No `.onDisappear`, `deinit`, or cancellation infrastructure**
- **No watch target changes** — dictation is iOS-only
- **No UI tests** for the processing indicator — unit-test rendering via `String(describing:)` per existing convention
- **No reordering** of existing bottomBar branches — one new branch inserted, precedence chain preserved
- **No changes to `SingleThreadCore`** package