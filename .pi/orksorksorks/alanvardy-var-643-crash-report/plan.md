# Implementation Plan — VAR-643: MainActor executor assert on `requestAuthorization`

## Overview

Fix the Swift 6 MainActor crash where callback-bridged async paths resume their
checked continuation **inline** (no `@MainActor` hop) from a framework-owned
completion queue, so Apple can deliver the completion off the main dispatch queue
without aborting the process. Adopt the extract-then-hop-then-resume shape already
proven by `awaitFinalResult`: extract Sendable values off-actor, then
`Task { @MainActor in … }` before `continuation.resume`, guarded by a single-resume
`ResumptionGate`. Apply it to the two inline no-hop resume sites
(`ReminderDictation.requestAuthorization`, `ReminderStore.fetchReminders`) and
consolidate into one shared helper via a regression gate.

Files touched, by phase (all under repo root):

```
SingleThread/AuthorizationRequiring.swift             (new, P1)
SingleThread/ReminderDictation.swift                 (P1 product, P3 dedupe)
SingleThreadTests/ReminderDictationTests.swift       (P1 red/green, P3)
SingleThreadCore/Sources/SingleThreadCore/ResumptionGate.swift  (new, P3)
SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift   (P2, P3)
SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift (P2 off-main seam)
SingleThreadTests/ReminderStoreTests.swift           (P2 red/green)
```

---

## Phase 1: Fix the `requestAuthorization` crash (root cause)

### Changes

#### 1. New seam protocol — `SingleThread/AuthorizationRequiring.swift`

**File**: `SingleThread/AuthorizationRequiring.swift`
**Action**: create

A fakeable bridge matching `Pattern E` (`@Sendable` completion) so the real
authorization continuation path can be driven test-side from an off-main context.
`SFSpeechRecognizerAuthorizationStatus` is a `Sendable` enum, so the closure and
its value cross the hop safely.

```swift
@preconcurrency import Speech

/// Test seam: abstracts `SFSpeechRecognizer.requestAuthorization`'s callback API
/// so tests can deliver the completion from an off-main (`Task.detached`) context
/// and reproduce the queue mismatch the runtime asserts on. The production impl
/// wraps the real framework call; a fake drives the off-main delivery.
@MainActor
protocol AuthorizationRequiring: AnyObject {
    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) async
}

/// Production impl: forwards to the real `SFSpeechRecognizer.requestAuthorization`.
@MainActor
final class SpeechAuthorizationRequiring: AuthorizationRequiring {
    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) async {
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            completion(status)
        }
    }
}
```

> The `@Sendable` closure carries only Sendable values (`status` is a Sendable
> enum) so the framework may invoke it from any queue without a concurrency fault.

#### 2. Rewire `ReminderDictation.requestAuthorization` to the seam — `SingleThread/ReminderDictation.swift`

**File**: `SingleThread/ReminderDictation.swift`
**Action**: modify — `init`, add private stored seam, rewrite `requestAuthorization`.

Add the seam as a stored dependency (defaulted, mirroring `speechTranscriber`
wiring in `ContentView`):

```swift
init(locale: Locale = .current,
     authorizationSource: any AuthorizationRequiring = SpeechAuthorizationRequiring()) {
    self.locale = locale
    self.authorizationSource = authorizationSource
    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
}

@ObservationIgnored private let authorizationSource: any AuthorizationRequiring
```

Rewrite `requestAuthorization` to extract Sendable off-actor inside the `@Sendable`
completion, then hop to main before resuming, guarded by a single-resume gate:

```swift
func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    final class ResumptionGate: @unchecked Sendable {
        var hasResumed = false
    }
    let gate = ResumptionGate()

    let status = await withCheckedContinuation { continuation in
        authorizationSource.requestAuthorization { @Sendable receivedStatus in
            // Sendable-derived status extracted here; hop to main before resuming.
            Task { @MainActor in
                guard !gate.hasResumed else { return }
                gate.hasResumed = true
                continuation.resume(returning: receivedStatus)
            }
        }
    }
    authorizationStatus = status
    return status
}
```

`authorizationStatus` write + return (`:44-45`) are unchanged. `ContentView`'s
`.notDetermined → .authorized` path (`ContentView.swift:501-511`) and the
`SpeechTranscribing` protocol surface are untouched.

#### 3. Red/green regression test — `SingleThreadTests/ReminderDictationTests.swift`

**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify — add mixed seams + a test driving the real continuation.

Add a fake that delivers the completion off a genuinely non-main `Task.detached`:

```swift
// MARK: - Off-main authorization seam

@MainActor
private final class DetachedAuthorizationRequiring: AuthorizationRequiring {
    private let status: SFSpeechRecognizerAuthorizationStatus

    init(status: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.status = status
    }

    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) async {
        // Dispatch the completion from an off-main queue, reproducing the real
        // framework delivery that tripped the MainActor assert.
        Task.detached { completion(status) }
    }
}
```

Add under the existing `// MARK: - Authorization` section:

```swift
@MainActor
struct ReminderDictationTests {
    // ...
    @Test
    func requestAuthorizationResumesOnMainActorFromOffMainQueue() async {
        let requester = DetachedAuthorizationRequiring(status: .authorized)
        let dictation = ReminderDictation(authorizationSource: requester)
        let status = await dictation.requestAuthorization()
        #expect(status == .authorized)
        #expect(dictation.authorizationStatus == .authorized)
    }
}
```

### Verification

#### Automated
- [x] Write the test **before** the fix; run `make test` and observe RED (the
      off-main resume trips the MainActor/`dispatch_assert` trap on current code).
- [x] Apply the hop; run `make test` and confirm GREEN.
- [x] `make lint` (SwiftFormat + SwiftLint `--strict`) passes.
- [x] Existing `ReminderDictationTests.fakeRecordsAuthorizationCall` /
      `DictationErrorTests.*` stay green.

#### Manual
- [ ] On the real device/simulator, launch the app with a dictation-capable
      entitlement; confirm no `EXC_BREAKPOINT`/trap within the first seconds.
      (Authorization-UI flow is unchanged.)

> Note: the off-main CE delivery is only deterministic in tests via the seam; the
> real device queue cannot be observed in CI (see `.pi/qrspi/…/research.md` Q2).

---

## Phase 2: Mirror the fix into `ReminderStore.fetchReminders`

### Changes

#### 1. Off-main completion seam — `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`

**File**: `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`
**Action**: modify — add init flag + off-main delivery in `fetchReminders`.

`InMemoryEventStore` currently completes `fetchReminders` synchronously on the
main actor. Add an opt-in flag so a test can deliver the completion from a
detached (non-main) context. The protocol signature is **unchanged** (the
`EventKitStoring` completion stays `@escaping ([EKReminder]?) -> Void`); the
off-main bridge uses a `nonisolated(unsafe)` label, matching the codebase's
queue-bridge precedent (`SkippedReminderSyncService.swift`).

```swift
public init(
    reminders: [EKReminder] = [],
    calendars: [EKCalendar] = [],
    deliverCompletionOffMain: Bool = false) {
    allReminders = reminders
    self.calendars = calendars
    self.deliverCompletionOffMain = deliverCompletionOffMain
}

private let deliverCompletionOffMain: Bool
```

```swift
@discardableResult
public func fetchReminders(
    matching _: NSPredicate,
    completion: @escaping ([EKReminder]?) -> Void) -> Any {
    let result = allReminders.filter { !$0.isCompleted }
    if deliverCompletionOffMain {
        nonisolated(unsafe) Task.detached { completion(result) }
    } else {
        completion(result)
    }
    return ()
}
```

> Safety note: this test-only off-main delivery mirrors how real EventKit hands
> freshly-built `EKReminder`s to the `@Sendable` continuation closure off-queue;
> the values are then hoisted back to `@MainActor` inside the ReminderStore hop
> and never re-read off-main thereafter. It does not change default behavior.

#### 2. Apply the hop — `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify — `fetchReminders` completion closure + hop + gate.

Rewrite `fetchReminders` so the completion closure is `@Sendable` and resumes only
after hopping to main with a single-resume gate:

```swift
private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
    final class ResumptionGate: @unchecked Sendable {
        var hasResumed = false
    }
    let gate = ResumptionGate()
    await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
        eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
            let value = reminders ?? []
            Task { @MainActor in
                guard !gate.hasResumed else { return }
                gate.hasResumed = true
                continuation.resume(returning: value)
            }
        }
    }
}
```

`await` on `continuation` already yields the array (last expression), so the
`return` is implicit — unchanged behavior. No `EventKitStoring` protocol change;
`EKReminder` is already `@Sendable` (`ReminderDateFilter.swift:23`) and the call-
site closure only captures Sendable values (`value`, `continuation`, `gate`).

Using `reload()` (not the private `fetchReminders`) in the test below keeps the
method private and exercises the whole narrow+broad fetch path.

#### 3. Red — green regression test — `SingleThreadTests/ReminderStoreTests.swift`

**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify — add a Store test using the off-main `InMemoryEventStore`.

```swift
@Test
func reloadResumesOnMainActorWhenFetchCompletesOffMain() async {
    let reminder = makeReminder(title: "A")
    let fake = InMemoryEventStore(reminders: [reminder], deliverCompletionOffMain: true)
    let store = ReminderStore(eventStore: fake, loadsReminders: true)
    await store.reload()
    #expect(store.reminders.map(\.title) == ["A"])
}
```

### Verification

#### Automated
- [x] Write the test **before** the fix; run `make test` and observe RED (the
      inline `continuation.resume` trips the MainActor/`dispatch_assert` trap when
      the off-main completion arrives).
- [x] Apply the hop; run `make test` and confirm GREEN.
- [x] `make test` keeps existing `ReminderStoreTests.visibleReminders…` /
      `hasHidden…` green (no `loadsReminders` behavior change).
- [x] `make lint` clean.

#### Manual
- [ ] On-sim ./ plain `ReminderStore` reload (`start()` → `reload()`) completes
      without a MainActor/assert crash when EventKit delivers off-main.

---

## Phase 3: Consolidate the shared bridge helper + regression

No behavior change — pure dedup. The riskiest piece is preserving
`awaitFinalResult`'s timeout/double-resume interplay.

### Changes

#### 1. Shared `ResumptionGate` + helper — new `SingleThreadCore/Sources/SingleThreadCore/ResumptionGate.swift`

**File**: `SingleThreadCore/Sources/SingleThreadCore/ResumptionGate.swift`
type**: new

`ReminderStore` lives in the `SingleThreadCore` crate (imported by the iOS app);
`ReminderSource`'s `ReminderDictation.swift` `import SingleThreadCore`, so the
shared declaration + helper must live in the **core**, not in either iOS file.
Expose the gate as a `public` type and a free `resumeOnMainActor` function both
sites name.

```swift
import Foundation

/// Guards a one-shot `Checked*Continuation` resume so competing resume sources
/// (a framework callback and a timeout, or two deliveries) never double-resume.
public final class ResumptionGate: @unchecked Sendable {
    public var hasResumed = false
}

/// Hops onto the MainActor and calls `resume`, which performs the actual
/// `continuation.resume`. Routes the success/return resume through this one
/// route. Must be `nonisolated` so it can be invoked from an off-main completion
/// queue; it only schedules a `Task` that returns to main and never touches
/// isolated state.
nonisolated func resumeOnMainActor(gate: ResumptionGate, _ resume: () -> Void) {
    Task { @MainActor in
        guard !gate.hasResumed else { return }
        gate.hasResumed = true
        resume()
    }
}
```

> The closure parameter (`() -> Void`) is deliberately continuation-type-free so
> it serves both the non-throwing `withCheckedContinuation` sites
> (`requestAuthorization`, `fetchReminders`) and the `withCheckedThrowingContinuation`
> success path in `awaitFinalResult`. `Task { @MainActor in … }` is exactly how the
> codebase already hoists completion-queue captures (`ReminderDictation.swift:158`).

#### 2. Route all three sites through the helper — `SingleThread/ReminderDictation.swift`, `SingleThreadCore/…/ReminderStore.swift`

**File**: `SingleThread/ReminderDictation.swift`
**Action**: modify

- Remove the local `final class ResumptionGate` inside `requestAuthorization` and
  `awaitFinalResult`; use the imported `ResumptionGate`.
- `requestAuthorization` change resume to:

```swift
    let status = await withCheckedContinuation { continuation in
        authorizationSource.requestAuthorization { @Sendable receivedStatus in
            resumeOnMainActor(gate) { continuation.resume(returning: receivedStatus) }
        }
    }
```

- `awaitFinalResult`: keep the `@Sendable` extraction and error-unwind branch on its
  own `Task { @MainActor in … }` defense (with `gate.hasResumed` + `resume(throwing:…)`),
  but route the **final-result** resume through the helper, and keep the 5s-timeout
  `Task { @MainActor [weak /] in … }` branch intact — it fires `continuation`
  directly (no gate) as the competing source the gate protects against.

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify — replace the hops with the shared helper and use the core gate:

```swift
private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
    let gate = ResumptionGate()
    await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
        eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
            let value = reminders ?? []
            resumeOnMainActor(gate) { continuation.resume(returning: value) }
        }
    }
}
```

#### 3. Keep the off-main tests / existing timing tests green — `SingleThreadTests/ReminderDictationTests.swift`, `SingleThreadTests/ReminderStoreTests.swift`

**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: no new tests; the Phase 1 test now exercises the shared helper.

**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: no new tests; Phase 2 test now exercises the shared helper.

No change to `FakeSpeechTranscriber`, `MicToggleFakeTranscriber`, or
`ActionButtonFakeTranscriber`. Confirm the added hop's scheduling delay does not
break existing dictation timing (all `FakeSpeechTranscriber` tests + bar mic
gating in `MicrophoneToggleTests`).

### Verification

#### Automated
- [x] `make format` then `make lint` (SwiftFormat/SwiftLint --strict) clean.
- [x] `./scripts/test.sh` full pipeline green (format, lint, build, Periphery,
      unit + UI + accessory + a11y).
- [x] Periphery (`periphery scan --strict`) reports no unused declared symbols
      (the promoted `ResumptionGate`/`resumeOnMainActor` are used by all three sites).
- [x] `ReminderDictationTests.requestAuthorizationResumesOnMainActorFromOffMainQueue`
      and `ReminderStoreTests…OffMain…` still green post-dedicated.
- [x] `MicrophoneToggleTests` and all `FakeSpeechTranscriber`-driven dictation
      tests still green (hop timing preserved).

#### Manual
- [ ] Place a short dictation on the simulator/device; confirm partials stream,
      the transcription `isFinal` resumes on main (no trap), and the 5s timeout /
      error branches still behave (single-resume preserved).

---

## Notes / resolutions (vs. `structure.md`)

- **Helper signature**: `structure` sketched `resumeOnMainActor<Return>(gate, continuation: CheckedContinuation<Return,Never>, value)`, but `CheckThrowingContinuation` (used by `awaitFinalResult`) is **not** a `CheckedContinuation<_,Never>`, so a value-typed helper cannot serve all three sites. I used a closure-typed helper (`resume: () -> Void`) that works uniformly; the `structure`'s phrase "illustrative" authorizes this.
- **Where the shared gate/helper lives**: `structure` said "either file," but
  `ReminderStore` (SingleThreadCore package) and `ReminderDictation` (iOS app) are in
  different packages with a one-way dependency (app→core). The shared
  `ResumptionGate` + helper must live in `SingleThreadCore` so all three sites can
  name it.
- **Off-main store seam**: says "completion invoked via `Task.detached`";
  I keep the `EventKitStoring` completion type `@escaping ([EKReminder]?) -> Void`
  (so real `EKEventStore` conforms unchanged) and add the off-main delivery only on
  `InMemoryEventStore` via a `nonisolated(unsafe)` `Task.detached`, following the
  codebase's own queue-bridge precedent.
- **No UI test slice**: authorization is not UI-drivable today (no `--seed` seam for `ReminderDictation`) — unit-only coverage, per AGENTS.md speech guidance.
- **No protocol isolation config change**; no `@retroactive … Sendable` conformance changes; no `ContentView.startDictation()` behavior change; no `.ips`/crash artifact change.

## Open questions
None blocking — all resolved in the changes above.