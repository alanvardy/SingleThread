# Structure Outline

## Approach

Work bottom-up through the reschedule chain's four real layers — WatchConnectivity
transport seam → shared `ReminderStore` relay → watch view-model → watch view — with a
diagnostic test layer underneath all of them. Make the transport seam
reachability-aware and queue-when-unreachable (uniformly for complete / delete /
reschedule), make the watch relay stop reporting unconditional `true`, then make the
watch view model surface the outcome and refresh on success. The iOS EventKit write and
the date-only wire semantics are never touched.

A repo-local `AGENTS.md` applies: shell is **fish** (`bash -c '…'` / `/tmp/x.sh` for
loops and `$( )`); test names in Swift Testing suites must not start with `test`/`testing`;
full gate runs once via the `run-gate` skill. New `.swift` files need no pbxproj edit
(synchronized groups).

---

## Stage 1: Test seams + hop-level diagnostic matrix

Make every unit-testable hop observable and record which hop drops the request. Adds the
reachability/queue surface all later stages assert against, plus the currently-missing
hop-1 and hop-6 coverage.

**Files**: `SingleThreadTests/TestFixtures.swift`, `SingleThreadWatchTests/TestFixtures.swift`,
`SingleThreadTests/SkippedReminderSyncServiceTests.swift`,
`SingleThreadTests/RescheduleSyncTests.swift`, new
`SingleThreadTests/AppViewModelSyncWiringTests.swift`, `SingleThread/AppViewModel.swift`

**Key changes**:
- `FakeSession` / `WatchFakeSession` (both conform to `SkipSyncSession`):
  `var isReachable = true`, `var queuedUserInfo: [[String: Any]] = []`,
  `var errorToThrow: (any Error)?` — `sendMessage` still records, but is now the only path
  a reachable session takes.
- `AppViewModel.init(arguments:session:)` — optional `(any SkipSyncSession)?` injection
  seam defaulting to `WCSession.default`; pure seam, no behaviour change.
- Hop-1 (sheet→store) is deliberately **not** extracted here — it is the Stage 4 fix and
  its red-first test lands there. Hop-4 (real `WCSession`) is covered by the paired-sim
  repro, not a unit test.

**Tests**: `receiveRescheduleReminderWritesStoreThroughWiring` (hop 6, new);
`requestRescheduleSendsMessage` / `requestRescheduleOmitsNilComponents` /
`receiveRescheduleReminderFiresHook` (existing, re-run); `rescheduleRelaysWhenPhoneUnreachable`
(new — expected **RED** against current code; that failure is the diagnosis artifact).
**Verify**: `scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests` and
`SingleThreadTests/AppViewModelSyncWiringTests` (destination pinned from `.simulator_id`);
all pre-existing cases green; the one new RED recorded in the plan/PR, then immediately
consumed by Stage 2. Paired-sim repro run here if the red points at hop 4 (see `simulator-pairing`).

---

## Stage 2: Sync transport — send-or-queue with reachability fallback

One delivery per attempt: `sendMessage` when `session.isReachable`, otherwise
`transferUserInfo` (auto-delivers on reconnect / relaunch). Applied to all three mutating
requests so complete / delete / reschedule share the fix.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThreadTests/TestFixtures.swift`, `SingleThreadWatchTests/TestFixtures.swift`,
`SingleThreadTests/RescheduleSyncTests.swift`, `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `SkipSyncSession` gains `var isReachable: Bool { get }` and
  `func queueUserInfo(_ userInfo: [String: Any])` — distinct name because `WCSession.transferUserInfo`
  returns `WCSessionUserInfoTransfer` and cannot witness a `Void` requirement.
- `extension WCSession { func queueUserInfo(_:) { _ = transferUserInfo($0) } }` (shim);
  `isReachable` is witnessed by the SDK property.
- `private func deliver(_ payload: [String: Any])` — the single send-or-queue chokepoint.
- `@discardableResult func requestRescheduleReminder(identifier: String, dueDateComponents: DateComponents) -> Bool`
  (+ `requestCompleteReminder` / `requestDeleteReminder`) return `true` when delivery was
  attempted; the payload and `PayloadKey` are unchanged.

**Tests**: `rescheduleQueuesWhenPhoneUnreachable`, `rescheduleSendsWhenPhoneReachable`,
`completeQueuesWhenPhoneUnreachable`, `deleteQueuesWhenPhoneUnreachable`,
`rescheduleQueuesExactlyOnceWhenUnreachable` (queue XOR send); existing payload/decode
cases untouched.
**Verify**: `scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests` and
`SingleThreadTests/RescheduleSyncTests` green; `make build` + `make watch-build` (protocol
conformance on both platforms, `SWIFT_TREAT_WARNINGS_AS_ERRORS`).

---

## Stage 3: Core store relay — truthful outcome

The watchOS relay branch stops returning unconditional `true`: it reports what the relay
actually did, so the view model can distinguish "queued/sent" from "nothing wired".

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadWatch/WatchAppViewModel.swift`, `SingleThreadTests/ReminderStoreTests.swift`,
`SingleThreadWatchTests/ReminderStoreWatchTests.swift`

**Key changes**:
- `public var onRescheduleReminder: ((String, DateComponents) -> Bool)?` — the relay hook
  returns acceptance (hook signature change; mirrors `onCompleteReminder`).
- watchOS branch: `let handler = onRescheduleReminder; return handler?(identifier, due) ?? false`.
- `WatchAppViewModel.wireStoreSyncHooks` closure returns
  `service.requestRescheduleReminder(identifier:dueDateComponents:)`.
- iOS/macOS `#else` branch, `canMutate` gate, and the EventKit write are byte-for-byte
  unchanged.

**Tests**: `rescheduleRelayReportsMissingHookAsFailure`, `rescheduleRelayPropagatesHookResult`
(replace/extend `rescheduleFiresRelayHookAndReturnsTrue`),
`rescheduleNoOpWhenGated` unchanged.
**Verify**: `scripts/test-one.sh SingleThreadWatchTests/ReminderStoreWatchTests` and
`SingleThreadTests/ReminderStoreTests` green; `make watch-build`.

**Decision to confirm in-plan**: the hook returns `Bool` because it is synchronous and
cannot see an async `sendMessage` failure — "acceptance" means *dispatched to the
transport*, and queued delivery counts as accepted. If a stricter signal is wanted, that
is a design change, not a structure tweak.

---

## Stage 4: Watch view-model — extracted confirm + outcome state

Move the confirm logic out of the SwiftUI closure into a testable view-model method that
refreshes on success and exposes failure.

**Files**: `SingleThreadWatch/WatchReminderViewModel.swift`,
`SingleThreadWatchTests/WatchReminderViewModelTests.swift`

**Key changes**:
- `func confirmReschedule() async` — reads `rescheduleDate`, builds date-only
  `DateComponents`, calls `store.rescheduleReminder`, then `await refresh()` on success.
- `var rescheduleFailure = false` (cleared at the start of each attempt) — the failure
  state the sheet renders.
- `isShowingRescheduleSheet` handling stays in the view (Stage 5) or moves here, whichever
  keeps the method under SwiftLint's cyclomatic/body limits.

**Tests**: `confirmRescheduleRefreshesVisibleRemindersOnSuccess`,
`confirmRescheduleSetsFailureWhenRelayRejected`, `confirmRescheduleNoopWithoutVisibleReminder`,
`confirmRescheduleSendsDateOnlyComponents` — driven by a relay-recording store
(`InMemoryEventStore`); new persisted values must use `AppGroup.defaults`, not the
`.standard` shortcut the older reschedule tests use.
**Verify**: `make watch-test` / `scripts/test-one.sh SingleThreadWatchTests/WatchReminderViewModelTests`
green; `make lint` (SwiftFormat strips `test` prefixes).

---

## Stage 5: Watch view — thin rendering of the outcome

Wire the sheet's Confirm button to `viewModel.confirmReschedule()` and render the failure
state; the view stays presentation-only.

**Files**: `SingleThreadWatch/WatchReminderView.swift`

**Key changes**:
- `actionMenuRescheduleSheet()` confirm Button → `Task { await viewModel.confirmReschedule() }`;
  no store call, no discarded `Bool` in the view.
- Failure surfaced inside the sheet (inline message + alert) while the sheet stays open;
  success closes it on the refreshed list.

**Tests**: no new unit test — the logic is already proven in Stage 4; the view is a
binding. Existing watch UI smoke + `testAccessibilityAudit` re-run.
**Verify**: `make watch-build` + `make lint`; watch UI smoke green.

---

## Stage 6: Regression + gate

Top layer: prove the phone path is untouched and the whole surface is green.

**Files**: none (verification only), plus PR notes.

**Tests**: `SingleThreadTests/EventKitStoringTests` (`reschedulePersistsDueDateAndReloads`,
`rescheduleUnknownIdentifierIsNoop`, `rescheduleFailureReturnsFalse`,
`reschedulePreservesRecurrenceRules`), `SingleThreadTests/RescheduleSyncTests`,
`SingleThreadTests/ReminderStoreTests` (`rescheduleResetsSkipCount`,
`reschedulePreservesRecurrenceOnRepeatingReminder`) — all unchanged and green.
**Verify**: full CI-identical `./scripts/test.sh` **once**, via the `run-gate` skill (async
gate subagent, managed worktree, multi-hour timeout). Known local-only macOS
`EntitlementStoreTests` failures are pre-existing — do not debug.

---

## Testing Checkpoints

- **After Stage 1**: pre-existing suites green; hop matrix complete; the
  `rescheduleRelaysWhenPhoneUnreachable` **RED** output captured as the diagnosis (the one
  sanctioned red→green handoff — Stage 2 must not start until that red is recorded).
- **After Stage 2**: `SkippedReminderSyncServiceTests` + `RescheduleSyncTests` green on both
  iOS and watch; the Stage-1 red is now green; queue XOR send proven.
- **After Stage 3**: `ReminderStoreWatchTests` + `ReminderStoreTests` green; watch relay
  returns `false` with no hook; iOS `#else` untouched.
- **After Stage 4**: `WatchReminderViewModelTests` green incl. sad paths; success refreshes,
  failure sets state.
- **After Stage 5**: watch build + lint green; view holds no business logic.
- **After Stage 6**: full gate green once.

**If context resets**: replay the checkpoint for the last committed stage; a stage whose
tests are not green is not done.

## Open Risks Carried Into Plan

- **Hop 4 is not unit-testable** — if the paired-sim repro implicates real `WCSession`
  transport, mark it `UNVALIDATED` and rely on the queued fallback + phone behaviour.
- **`transferUserInfo` double-apply** — enforced by the single `deliver` chokepoint
  (send XOR queue); the plan must verify no second path exists.
- **Hook signature change** (Stage 3) touches macOS compilation (`#else` branch) — verified
  by the `mac-tests` job, which is outside the local gate's watch focus.