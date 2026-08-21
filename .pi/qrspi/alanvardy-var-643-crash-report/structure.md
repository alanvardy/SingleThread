# Structure Outline

## Approach

Fix the off-main continuation resume that trips the Swift 6 MainActor assert at `ReminderDictation.requestAuthorization()` (`ReminderDictation.swift:40-41`), then the identical inline no-hop resume in `ReminderStore.fetchReminders` (`ReminderStore.swift:371-374`). Adopt the extract-then-hop-then-resume shape already proven in `awaitFinalResult` (`:152-158`): extract Sendable values off-actor, `Task { @MainActor in … }` before resuming, guarded by a `ResumptionGate` single-resume. Consolidate this into one shared helper once all three sites are fixed. This is iOS/SwiftUI, so the "layers" are the framework-completion bridge, the seam/protocol surface, and the Swift Testing suites — each phase crosses all three.

---

## Phase 1: Fix the `requestAuthorization` crash (root cause)

Delivers the actual reported fix end-to-end: an off-main completion no longer aborts the process. Introduces a fakeable `AuthorizationRequiring` seam so the **real** continuation path can be unit-driven from an off-main (`Task.detached`) context — red before the fix, green after.

**Files**: `SingleThread/ReminderDictation.swift`; new `SingleThread/AuthorizationRequiring.swift`; `SingleThreadTests/ReminderDictationTests.swift`.

**Key changes**:
- New seam type: `@MainActor protocol AuthorizationRequiring: AnyObject { func requestAuthorization(completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) async }` — production impl wraps `SFSpeechRecognizer.requestAuthorization`.
- `ReminderDictation.requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus` — modified: request via the seam; in the `@Sendable` completion extract `status`, then `Task { @MainActor in … }` before `continuation.resume(returning: status)`. Failures impossible (no propagate on one-shot resume). `authorizationStatus` write + return unchanged (`:44-45`).
- `ResumptionGate { var hasResumed = false }` — single-resume guard where the callback is the only resume source (request required), matching the `awaitFinal` shape.

**Verify**: `make test` (unit-only). New `@Test func requestAuthorizationResumesOnMainActorFromOffQueue()` red before the hop, green after. `ContentView.startDictation()` `.notDetermined → .authorized` path (`ContentView.swift:501-511`) unchanged; existing `ReminderDictationTests` + `MicrophoneToggleTests` all green.

---

## Phase 2: Mirror the fix into `ReminderStore.fetchReminders`

Delivers the same crash-class fix at the one other inline no-hop resume site, so no remaining dictation/EventKit completion resumes off-main. `EKReminder` already crosses the continuation boundary Sendable, so extraction is safe.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`; `SingleThreadTests/ReminderStoreTests.swift`.

**Key changes**:
- `private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder]` — modified: same shape, `completion: @escaping @Sendable ([EKReminder]?) -> Void` extraction off-actor, then `Task { @MainActor in … }` before `continuation.resume(returning: reminders ?? [])`.
- No `EventKitStoring` protocol change — the completion closure becomes `@Sendable`; `EKReminder` already Sendable (`ReminderDateFilter.swift:23`).

**Tests**: add off-main delivery to the seam behavior specified by the plan (completion invoked via `Task.detached`); new fetch test turns red on current code, green post-hop. Existing `ReminderStoreTests.visibleReminders…`/hasHidden coverage must stay green (no `loadsReminders` behavioral change).

---

## Phase 3: Consolidate the shared bridge helper + regression

Extract the duplicated extract-then-hop shape into one private helper used by `requestAuthorization`, `fetchReminders`, and `awaitFinalTranscript`. Removes the paste-three-times debt; **no behavior change** — this is a pure dedup with a regression gate (the riskiest piece is preserving `awaitTranscript`’s timeout/double-resume interplay).

**Files**: `SingleThread/ReminderDictation.swift`; `SingleThreadCore/…/ReminderStore.swift`; `SingleThreadTests/ReminderDictationTests.swift`.

**Key changes**:
- New private helper shape (illustrative): `nonisolated func resumeOnMainActor<Return>(gate: ResumptionGate, continuation: CheckedContinuation<Return, Never>, value: Return)` — runs `Task { @MainActor in }`, guards `!gate.hasResumed`, marks the gate, resumes.
- `ReminderStore.fetchReminders` + `requestAuthorization` route the success resume through it; `awaitFinalTranscript` routes the final-result resume through it while keeping its error unwind + 5s timeout branches on their own `Task { @MainActor [weak self] in … }` defenses.
- `ResumptionGate` promoted to a shared declaration (either file) so all three sites name one type, not three nested finals.

**Tests: full** `./scripts/test.sh` (format, lint, build, Periphery, unit, UI + a11y) green. Confirm the added hop’s scheduling delay doesn’t break existing dictation timing (all `FakeSpeechTranscriber`-driven tests + bar mic gating in `MicrophoneToggleTests`).

---

## Testing Checkpoints

- **After Phase 1**: `ReminderDictationTests` includes a real-continuation authorization test that drives the completion from `Task.detached`; red pre-fix, green post-fix. Reported crash path is closed.
- **After Phase 2**: ReminderStore off-main fetch test green; all `ReminderStoreTests` green. No dictation-script behavior changed.
- **After Phase 3**: helper exposed by full `./scripts/test.sh` — unit + UI + a11y + Periphery + lint clean — confirming the dedup and the timeout/double-resume semantics survived.
- **Not sliced vertically** (by design): authorization is not UI-drivable today (the `--seed` seam doesn’t surface `ReminderDictation`), AGENTS.md permits unit-only for speech — no UI test slice exists (explicit design decision).
- **Proof relies on + seam + review**: the real device off-main queue can’t be observed in CI (`research.md` Q2 area); correctness rests on the pattern precedent + deterministic seam test.