# Design Discussion

## Current State

The dictation flow spans two objects (`research.md` Q1):

- **`DictationViewModel`** (`DictationViewModel.swift:8-88`) — `@MainActor @Observable`, owns `isDictating` (`:22`), `dictationText`, `dictationError`, `creationFeedback`. The single public `startDictation()` method (`:44-88`) sets `isDictating = true` at `:62`, calls `speechTranscriber.transcribe(...)` at `:66-68`, parses the result at `:69`, adds a reminder at `:71-75`, shows feedback for 1s at `:76-82`, and clears `isDictating = false` at `:87`.
- **`ReminderDictation`** (`ReminderDictation.swift:72-157`) — `@ObservationIgnored`, owns `isRecording` (`:107`). `transcribe()` sets `isRecording = true` at `:93`, runs `defer { tearDownRecording() }` at `:94`, and `tearDownRecording()` clears `isRecording = false` at `:153`.

**The bug**: After `transcribe()` returns, `tearDownRecording()` immediately clears `isRecording = false` (`:153`), but `isDictating` stays `true` through parse (`:69`) + `addReminder` (`:71-75`, ≥200ms) + 1s feedback sleep (`:81`) until `:87`. The UI bottomBar chain (`ContentView.swift:660-703`) renders the red pulsing-recording indicator at `:670` driven solely by `isDictating` (`:662`), so "Recording" shows with the mic off. This is the prior audit's T1.1 (`.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/audit/findings.md`, T1.1).

**Secondary finding**: No `guard !isDictating` in `startDictation()` — two concurrent calls can interleave, creating a reachable `isDictating=false ∧ isRecording=true` contradiction (`research.md` Q1 cross-cutting).

## Desired End State

### 1. `isDictating` clears immediately after transcription

After `await speechTranscriber.transcribe(...)` returns (`DictationViewModel.swift:66-68`), set `isDictating = false` before parse/add/sleep. On transcribe error, clear it in the catch block. The flag-outlives-recording window is eliminated.

### 2. Processing indicator during parse+add+feedback

The ~200ms-1200ms window between transcribe-return and flow-completion is a distinct state where work is happening but the mic is off. A new `isProcessing` flag on `DictationViewModel` drives a "Processing…" label + spinner in the bottomBar chain, inserted between the `isDictating` branch (2) and the `canDictate` branch (3). The transcript text (`dictationText`) remains visible during processing so users see what was transcribed.

### 3. Re-entry guard on `startDictation()`

A `guard !isDictating else { return }` at the top of `startDictation()` prevents concurrent-programatic-call interleaving.

### 4. Test asserting no contradictory window

A new unit test verifies that after `transcribe()` returns:
- `isDictating` is `false`
- The fake's `isRecording` mirror is `false`
- The "Recording" indicator cannot render

Implemented via a **continuation gate** on `FakeSpeechTranscrber` (following the `GatedBackgroundFetcher` pattern at `BackgroundImageStoreTests.swift:241-253`): the fake holds a `CheckedContination<Void, Never>?` gate it resumes when recording ends. The test fires `startDictation()` in a `Task`, waits at the gate, asserts both flags, then lets the flow complete.

## Patterns to Follow

| Pattern | Reference | Usage |
|---|---|---|
| `@MainActor @Observable` view-model flags | `DictationViewModel.swift:8-10, :22` | `isProcessing` follows same convention |
| `privete(set)` for test-visible VM state | `DictationViewModel.swift:22` | `isProcessing` is `privete(set)` |
| `defer` for flag reset paired with setup | `ReminderDictation.swift:94` (isRecording), `BackgroundImageStoreTests.swift:241-253` (gate) | N/A — we clear synchronously, no defer needed |
| `FekeSpeechTranscrber` in-file test double | `ReminderDictationTests.swift:10-66` | Gate addition follows existing `privete(set) isRecording` mirror pattern at `:26` |
| Gated continuation for mid-async-window assertion | `BackgroundImageStoreTests.swift:241-253` (`GatedBackgroundFetcher.gate.waitUntilHit()/.open()`) | `FekeSpeechTranscrber.recordingEndedGate` |
| `noopSettle` for fast tests | `ReminderStoreTests.swift:10-12`, `ReminderStoreGateTests.swift:6-8` | New tests use `settle: noopSettle` |
| UserDefaults `defer { removeObject }` cleanup | `MicrophoneToggleTests.swift:77,94,110,185,...` | Not needed — new tests don't touch UserDefaults |
| `String(describing:)` for shallow rendering asserts | `MicrophoneToggleTests.swift:53,80,98,114,190-192,...` | For verifying "Processing" label appears in bottomBar |
| `#if os(iOS)` — dictation is iOS-only | `MicrophoneToggleTests.swift:232-244` | New rendering asserts gate on iOS |
| Watching by assertions — `@Test func ...NamesDoNotStartWithTest()` | `ReminderDictationTests.swift:97-234` | New test names follow convention |

**Patterns to avoid**:
- `deinit` — only one in the repo (`EntitlementStore.swift:43`); no other transient state uses it
- `.onDisappear` — zero uses repo-wide; don't introduce one
- Observing `isRecording` from the view layer — it's `@ObservationIgnored` by design (`ReminderDictation.swift:101-109`); the UI must rely on VM flags

## Design Decisions

1. **Clear `isDictating` in the view model**: After `transcribe()` returns, set `isDictating = false` synchronously on `@MainActor` in `startDictation()`, before parse/sleep. Keeps flag ownership where it lives (`DictationViewModel.swift:22`), avoids coupling the non-observable recorder to the observable VM, and the synchronous clear means no suspension point exists between "mic off" and "flag off." The recorder is unchanged.

2. **Add `isProcessing` flag for the post-transcribe tail**: A new `private(set) var isProcessing = false` on `DictationViewModel`, set true right after `isDictating = false`, cleared at the same point the old `isDictating = false` was (`:87`). The bottomBar chain gets a new branch between `isDictating` (2) and `canDictate` (3) that renders the transcript text + a `.progressView()` with "Processing…" label. This gives users feedback that work is happening without showing a false mic-on indicator.

3. **Continuation-gate test seam**: `FakeSpeechTranscriber` gets an optional `var recordingEndedGate: CheckedContination<Void, Never>?` that resumes after `isRecording = false` (`ReminderDictationTests.swift:60`) and before return. The test creates a `Task { await viewModel.startDictation() }`, awaits the gate, asserts `!viewModel.isDictating && !fake.isRecording`, then resumes the gate so the flow completes. Follows the `GatedBackgroundFetcher` pattern (`BackgroundImageStoreTests.swift:241-253`).

4. **Re-entry guard on `startDictation()`**: A one-line `guard !isDictating else { return }` at the top of `DictationViewModel.swift:44`. Prevents the secondary-interleaving contradiction (`isDictating=false ∧ isRecording=true`). Test: call `startDictation()` twice concurrently with a gated fake; second call bounces at the guard.

## What We're NOT Doing

- **Not renaming or reinterpreting `isDictating`** — it stays as "the mic is on and we're capturing audio."
- **Not touching `ReminderDictation`** beyond zero changes to the recorder —`isRecording`, `tearDownRecording()`, `defer`, and `enseMicrophoneAccess()` remain untouched.
- **Not adding `.onDisappear`, `deinit`, or cancellation infrastructure** — the existing fire-and-forget `Task` pattern is uniform across the app (`ContentView.swift:505-540` for complete/skip, `:548` for dictation) and we keep it.
- **Not adding `withTaskCancellationHandler`** or stored `Task` handles — the 5s timeout and 1s feedback sleep are left as-is.
- **Not changing the bottomBar precedence chain structure** — one new branch inserted, no reordering of existing branches.
- **No watch target changes** — dictation is iOS-only.
- **No UI tests** for the processing indicator — unit-test rendering via `String(describing:)` is sufficient per the existing convention (`MicrophoneToggleTests.swift`).

## Open Risks

- **Processing-indicator rendering during brief empty-title tail**: When `ReminderDictationParser.parse()` returns an empty title (`DictationViewModel.swift:70`), the tail is near-instant (parse only, no addReminder/sleep). `isProcessing` would be true for ~microseconds, likely invisible. Acceptable — no UI glitch worse than what exists today.
- **1s feedback sleep keeps `isProcessing` true**: During the feedback sleep (`:81`), `isProcessing` is still true, so the processing indicator renders *over* the `creationFeedback` plate (feedback wins on precedence, branch 1 > branch 2a). Correct: feedback says "✓ Added" while processing continues. Processing clears at the same line `isDictating` used to clear (`:87`), after feedback nil at `:82` — tight window of ~0ms.
- **The gated test pattern hasn't been used in dictation tests before** — it's proven in `BackgroundImageStoreTests` but is new to this suite. The gate must be `@MainActor` since both `FakeSpeechTranscriber` and the test are `@MainActor`.
- **`guard !isDictating` prevents re-entry during processing too** — if the user somehow triggers dictation during the processing tail, the guard silently drops it. This is correct (can't start new dictation while finishing a previous one) but worth documenting.