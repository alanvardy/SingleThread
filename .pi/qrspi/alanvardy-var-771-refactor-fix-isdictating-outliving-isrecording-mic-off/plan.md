# Implementation Plan

## Overview

Eliminate the `isDictating`-outlives-`isRecording` window by clearing
`isDictating` immediately after `transcribe()` returns, introducing an
`isProcessing` flag for the post-transcribe tail, and adding a re-entry guard
on `startDictation()`. The bottomBar chain gets a new "Processing…" indicator
branch so the mic-off state never shows a false recording indicator.

---

## Phase 1: Test Seam — Continuation Gate on `FakeSpeechTranscriber`

### Changes

#### 1. Add `recordingEndedGate` property to `FakeSpeechTranscriber`
**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify — add property and resume point inside the `FakeSpeechTranscriber` class (lines 10–66)

Add the property after `transcriptionError` (~line 33):

```swift
var recordingEndedGate: CheckedContinuation<Void, Never>?
```

In `transcribe()`, resume the gate after `isRecording = false` (~line 60) and before the error throw/return (currently `:61-62`).Replace lines 59–63:

```swift
// Before:
        isRecording = false
        if let error = transcriptionError {
            throw error
        }
        return transcriptionResult ?? ""

// After:
        isRecording = false
        recordingEndedGate?.resume()
        recordingEndedGate = nil
        if let error = transcriptionError {
            throw error
        }
        return transcriptionResult ?? ""
```

####2. Add gate test `gateResumesAfterRecordingEnds`
**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify — add new test inside `ReminderDictationTests` struct, after `fakeTranscribeDeliversPartialResults` (~line 155)

```swift
@Test
func gateResumesAfterRecordingEnds() async {
    let fake = FakeSpeechTranscriber(transcriptionResult: "Hello")
    #expect(!fake.isRecording)
    await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
        fake.recordingEndedGate = gate
        Task {
            _ = try? await fake.transcribe { _ in }
        }
    }
    #expect(!fake.isRecording)
}
```

**How this works**: `withCheckedContinuation` suspends the test until `transcribe()` calls `gate.resume()`. The resume happens inside `transcribe()` after `isRecording = false`. Since `transcribe()` continues synchronously (error check, return), then returns to `startDictation()` which executes `isDictating = false` (also synchronous on `@MainActor`), the test's continuation body runs at the first suspension point after all that work — so `!isRecording` holds.

### Verification
#### Automated
- [x] Full `ReminderDictationTests` suite passes (existing tests + new gate test):
  ```fish
  set SIM (xcrun simctl list devices available | grep -m1 'iPhone 17 (' | string match -r '([A-F0-9-]{36})' | head -1)
  xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,id=$SIM" -configuration Debug test -only-testing:SingleThreadTests/ReminderDictationTests
  ```

#### Manual
- [ ] `grep recordingEndedGate SingleThreadTests/ReminderDictationTests.swift` → property at ~line 35, resume at ~line 61, test reference at ~line 165

---

## Phase 2: ViewModel State — `isProcessing`, `isDictating` Move, and Re-entry Guard

### Changes

#### 1. Add `isProcessing` property to `DictationViewModel`
**File**: `SingleThread/DictationViewModel.swift`
**Action**: modify

After `private(set) var isDictating = false` (line 22), add:

```swift
var isProcessing = false
```

Note: `private(set)` is intentionally omitted — unlike `isDictating` (which tests never set directly), `isProcessing` needs to be settable from` MicrophoneToggleTests` for rendering assertions, matching the existing `dictationError` property pattern (no `private(set)`). The framework sets it in `startDictation()`; tests set it directly for shallow rendering checks.

#### 2. Add re-entry guard at the top of `startDictation()`
**File**: `SingleThread/DictationViewModel.swift`
**Action**: modify

After `func startDictation() async {` (line 44), insert:

```swift
guard !isDictating else { return }
```

#### 3. Move `isDictating = false` and set `isProcessing`
**File**: `SingleThread/DictationViewModel.swift`
**Action**: modify — replace lines 65–87

Before:

```swift
        do {
            let result = try await speechTranscriber.transcribe { [weak self] text in
                self?.dictationText = text
             }
            let parsed = ReminderDictationParser.parse(result)
             if !parsed.title.isEmpty {
                 let saved = await store.addReminder(
                     title: parsed.title,
                     notes: nil,
                     dueDate: parsed.dueDateComponents,
                     recurrenceRule: parsed.recurrenceRule)
                 if saved {
                     creationFeedback = .success
                 } else {
                     creationFeedback = .failure
                 }
                 try? await Task.sleep(nanoseconds: 1_000_000_000)
                 creationFeedback = nil
             }
         } catch {
            dictationError = error.localizedDescription
        }
         isDictating = false
```

After:

```swift
        do {
            let result = try await speechTranscriber.transcribe { [weak self] text in
                self?.dictationText = text
             }
            isDictating = false
            isProcessing = true
            let parsed = ReminderDictationParser.parse(result)
             if !parsed.title.isEmpty {
                 let saved = await store.addReminder(
                     title: parsed.title,
                     notes: nil,
                     dueDate: parsed.dueDateComponents,
                    recurrenceRule: parsed.recurrenceRule)
                 if saved {
                    creationFeedback = .success
                 } else {
                     creationFeedback = .failure
                 }
                 try? await Task.sleep(nanoseconds: 1_000_000_000)
                 creationFeedback = nil
             }
         } catch {
             dictationError = error.localizedDescription
            isDictating = false
            isProcessing = true
        }
        isProcessing = false
```

Key behaviors:
- Success path: `isDictating = false; isProcessing = true` after `transcribe()` returns, before parse/add/sleep. `isProcessing = false` at the old `isDictating = false` location (now the final line of the function).
- Catch path: also sets `isDictating = false; isProcessing = true`. `isProcessing = false` at the final line (shared exit).
- Paths A/B (permission denied/restricted at entry) never set `isDictating = true`, so they never set `isProcessing = true` either — the guard returns before the do/catch.
- The re-entry guard `guard !isDictating else { return }` prevents concurrent calls from interleaving. Note: it also blocks re-entry during the processing tail (when `isDictating` is false but `isProcessing` is true), which is correct — a new dictation shouldn't start while finishing a previous one.

#### 4. Add new tests in `ReminderDictationTests.swift`
**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify — add after `startDictationAddsReminderAndFlowsText` (~line 207)

```swift
@Test
func isDictatingClearsAfterTranscribeBeforeParseAddAndSleep() async {
    let fake = FakeSpeechTranscriber(transcriptionResult: "Buy milk")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(), loadsReminders: false)
    let viewModel = DictationViewModel(speechTranscriber: fake, store: store)

    // The gate fires inside transcribe() after isRecording = false.
    // After transcribe() returns, startDictation() synchronously sets
    // isDictating = false on @MainActor before any suspension point (parse
    // is sync; the first await is addReminder). The test's continuation
    // resumes at that first suspension point, so isDictating is already
    // false.
    await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
        fake.recordingEndedGate = gate
        Task {
            await viewModel.startDictation()
        }
    }
    #expect(!viewModel.isDictating)
    #expect(!fake.isRecording)
    #expect(viewModel.isProcessing)
}

@Test
func isProcessingSetDuringPostTranscribeTail() async {
    let fake = FakeSpeechTranscriber(transcriptionResult: "Buy milk")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(), loadsReminders: false)
    let viewModel = DictationViewModel(speechTranscriber: fake, store: store)

    await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
        fake.recordingEndedGate = gate
        Task {
            await viewModel.startDictation()
        }
    }
    #expect(viewModel.isProcessing)
    #expect(!viewModel.isDictating)

    // Let the flow complete (production settle is 200ms).
    // Poll for isProcessing to clear.
    for _ in 0..<50 {
        if !viewModel.isProcessing { break }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(!viewModel.isProcessing)
}

@Test
func reentryGuardBlocksConcurrentCalls() async {
    let fake = FakeSpeechTranscriber(transcriptionResult: "First")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(), loadsReminders: false)
    let viewModel = DictationViewModel(speechTranscriber: fake, store: store)

    // Hold the first call at the gate so isDictating stays true.
    let task1 = Task { await viewModel.startDictation() }
    // Give task1 time to set isDictating = true and enter transcribe().
    try? await Task.sleep(nanoseconds: 100_000_000)
    #expect(viewModel.isDictating)

    // Second call should bounce at the guard — isDictating is still true.
    let task2 = Task { await viewModel.startDictation() }
    try? await Task.sleep(nanoseconds: 100_000_000)
    #expect(viewModel.isDictating) // still true; task2 bounced

    // Let task1 complete, then task2.
    // (no gate set, so transcribe runs normally)
    // task1 completes normally with production settle (200ms)
    await task1.value
    await task2.value

    #expect(!viewModel.isDictating)
    #expect(fake.transcribeCallCount == 1) // only task1 called transcribe
}
```

Note: the `reentryGuardBlocksConcurrentCalls` test does NOT set a gate — it relies on timing. The fake's `transcribe()` takes ~50ms minimum (the partial sleep). Since `isDictating` is set true BEFORE `transcribe()` is called (`startDictation()` line 62), `task2` will find `isDictating == true` and bounce at the guard. The timing window is wide (~50ms+) so this is reliable.

The sleep-based approach (100ms waits) is consistent with patterns used elsewhere in the test suite (e.g. `CompletionGlowTests` polls ≤100×20ms).

#### 5. Update existing `startDictationAddsReminderAndFlowsText` test
**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify — add one assertion at ~line 203

After `#expect(!viewModel.isDictating)`, add:

```swift
        #expect(!viewModel.isProcessing)
```

#### 6. `noopSettle` not needed
The new tests use the default `ReminderStore` init (with the production 200ms `settle` sleep). This provides the suspension point needed for `isDictatingClearsAfterTranscribeBeforeParseAddAndSleep` to observe `isDictating == false` after the gate fires. For `isProcessingSetDuringPostTranscribeTail`, the polling loop waits for the flow to complete.

### Verification
#### Automated
- [x] Full `ReminderDictationTests` suite passes:
  ```fish
  xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,id=$SIM" -configuration Debug test -only-testing:SingleThreadTests/ReminderDictationTests
  ```
- [x] New tests pass individually:
  - [x] `isDictatingClearsAfterTranscribeBeforeParseAddAndSleep`
  - [x] `isProcessingSetDuringPostTranscribeTail`
  - [x] `reentryGuardBlocksConcurrentCalls`
  - [x] `startDictationAddsReminderAndFlowsText` (updated assertion)

#### Manual
- [ ] `grep 'isProcessing' SingleThread/DictationViewModel.swift` → property at ~line 23, set `true` at ~lines 69 + 86, set `false` at ~line 88
- [ ] `grep 'isDictating = false' SingleThread/DictationViewModel.swift` → two hits: post-transcribe (~line 68) and catch block (~line 85)
- [ ] `grep 'guard !isDictating' SingleThread/DictationViewModel.swift` → one hit at ~line 45

---

## Phase 3: View Rendering — Processing Indicator in `bottomBar`

### Changes

#### 1. Insert processing branch in the bottomBar if/else-if chain
**File**: `SingleThread/ContentView.swift`
**Action**: modify — insert after line 670 (closing `}` of `isDictating` block)

Insert a new `else if` branch between the `isDictating` branch and the `canDictate` branch:

```swift
            } else if viewModel.dictation.isProcessing {
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
```

The resulting chain order (first match wins):
1. `creationFeedback != nil` → feedback plate (unchanged)
2. `isDictating` → transcript + recording indicator (unchanged)
3. **`isProcessing`** → transcript (if non-empty) + "Processing…" spinner **(new)**
4. `canDictate && showMicrophoneButton` → mic/actions/upgrade (unchanged)
5. `!canDictate && …` → "Speech recognition is unavailable." (unchanged)

The `dictationError` standalone `if` at lines 653–659 is unchanged — it coexists above the chain.

#### 2. Add rendering tests in `MicrophoneToggleTests.swift`
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify — add tests inside `MicrophoneToggleTests` struct, before the closing `}` (~line 284)

```swift
#if os(iOS)
    @Test
    func processingIndicatorRendersWhenIsProcessingIsTrue() {
        let fake = MicToggleFakeTranscriber()
        let contentViewModel = makeContentViewModel(fake)
        contentViewModel.dictation.isProcessing = true
        let view = ContentView(viewModel: contentViewModel)

        let bodyDescription = String(describing: view.bottomBar)
        #expect(bodyDescription.contains("Processing…"))
        #expect(!bodyDescription.contains("Recording"))
        #expect(!bodyDescription.contains("mic.fill"))
    }

    @Test
    func processingIndicatorNotRenderedWhenIsProcessingIsFalse() {
        let fake = MicToggleFakeTranscriber()
        let contentViewModel = makeContentViewModel(fake)
        // isProcessing defaults to false
        let view = ContentView(viewModel: contentViewModel)

        let bodyDescription = String(describing: view.bottomBar)
        #expect(!bodyDescription.contains("Processing…"))
    }

    @Test
    func recordingIndicatorNotRenderedWithProcessingTrue() {
        let fake = MicToggleFakeTranscriber()
        let contentViewModel = makeContentViewModel(fake)
        contentViewModel.dictation.isProcessing = true
        contentViewModel.dictation.dictationText = "Hello"
        let view = ContentView(viewModel: contentViewModel)

        let bodyDescription = String(describing: view.bottomBar)
        #expect(bodyDescription.contains("Hello"))
        #expect(!bodyDescription.contains("Recording"))
    }
#endif
```

Gate with `#if os(iOS)` matching the existing convention at `MicrophoneToggleTests.swift:232-244` — dictation is iOS-only.

### Verification
#### Automated
- [ ] Both suites pass together:
  ```fish
  xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,id=$SIM" -configuration Debug test \
    -only-testing:SingleThreadTests/ReminderDictationTests \
    -only-testing:SingleThreadTests/MicrophoneToggleTests
  ```
- [ ] New `MicrophoneToggleTests` pass individually:
  - [ ] `processingIndicatorRendersWhenIsProcessingIsTrue`
  - [ ] `processingIndicatorNotRenderedWhenIsProcessingIsFalse`
  - [ ] `recordingIndicatorNotRenderedWithProcessingTrue`

#### Manual
- [ ] `grep 'isProcessing' SingleThread/ContentView.swift` → one hit: the `else if viewModel.dictation.isProcessing` branch
- [ ] `grep 'Processing…' SingleThread/ContentView.swift` → one hit in the processing branch label
- [ ] BottomBar chain order: feedback → isDictating → isProcessing → canDictate → unavailable (verify by reading lines 660–710)

---

## Phase 4: Full Gate Verification

### Changes
None — verification only.

### Verification
#### Automated
- [ ] `./scripts/test.sh` passes — full CI-identical gate:
  - [ ] `swiftformat --lint` + `swiftlint lint --strict` clean
  - [ ] iOS build-for-testing succeeds
  - [ ] watch build succeeds
  - [ ] `periphery scan --strict` clean (no new dead code:`isProcessing` is read in `ContentView.swift` and` ReminderDictationTests.swift`)
  - [ ] iOS unit tests pass (62 suites)
  - [ ] iOS UI tests pass
  - [ ] watch unit tests pass
  - [ ] watch UI tests pass
  - [ ] macOS unit tests pass

#### Manual
- [ ] Build and run on iPhone 17 simulator: tap mic, speak, verify:
  1. Recording indicator (red pulsing mic) shows during capture
  2. "Processing…" spinner shows after speech ends (no red mic)
  3. Feedback "✓ Added" appears
  4. Normal mic button returns

---

## Summary of All Files Touched

| File | Phase | Action |
|------|-------|--------|
| `SingleThreadTests/ReminderDictationTests.swift` | 1, 2 | Add `recordingEndedGate` property + resume in `transcribe()`; add 4 new tests; update 1 existing test |
| `SingleThread/DictationViewModel.swift` | 2 | Add `isProcessing` property; add re-entry guard; move `isDictating = false` + set `isProcessing` |
| `SingleThread/ContentView.swift` | 3 | Insert `isProcessing` branch in bottomBar if/else-if chain |
| `SingleThreadTests/MicrophoneToggleTests.swift` | 3 | Add 3 rendering tests gated on `#if os(iOS)` |

Total: 4 files, ~15 net new lines of production code, ~80 net new lines of test code.

## Testing Summary

| Test Name | Suite | Phase | What it verifies |
|-----------|-------|-------|------------------|
| `gateResumesAfterRecordingEnds` | ReminderDictationTests | 1 | Gate seam works: resumes after `isRecording = false` |
| `isDictatingClearsAfterTranscribeBeforeParseAddAndSleep` | ReminderDictationTests | 2 | `isDictating` clears immediately after transcribe, before parse/sleep |
| `isProcessingSetDuringPostTranscribeTail` | ReminderDictationTests | 2 | `isProcessing` is true during parse+add, false after completion |
| `reentryGuardBlocksConcurrentCalls` | ReminderDictationTests | 2 | Two concurrent `startDictation()` calls don't interleave |
| `processingIndicatorRendersWhenIsProcessingIsTrue` | MicrophoneToggleTests | 3 | bottomBar shows "Processing…" when `isProcessing` is true |
| `processingIndicatorNotRenderedWhenIsProcessingIsFalse` | MicrophoneToggleTests | 3 | bottomBar does NOT show "Processing…" when `isProcessing` is false |
| `recordingIndicatorNotRenderedWithProcessingTrue` | MicrophoneToggleTests | 3 | "Recording" indicator does not render when `isProcessing` is true |
| `startDictationAddsReminderAndFlowsText` (updated) | ReminderDictationTests | 2 | Existing flow test still passes; now also asserts `!isProcessing` |