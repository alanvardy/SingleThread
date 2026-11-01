# Design Discussion

## Current State

Sentry issue 7821993169 is reported as `Fatal App Hang Fully Blocked`, culprit
`SingleThreadApp.$main`, on 1.4+21 / iOS 27.2. The raw event (provided during
grilling, Q2) resolves the question the research left open: the blocked main
thread is **entirely inside system code**, and the only app frames are the app
entry points.

Blocked chain (top of stack is the block itself, read bottom-up):

```
SingleThreadApp.$main → App.main → GSEventRunModal → __CFRunLoopRun
  → _dispatch_main_queue_drain → __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
  → _UIScreenBacklightLevelDidChangeCallback
  → +[UIScreen _currentSystemResolvedBrightnessForScreen:]
  → BKSDisplayBrightnessGetCurrent → _BKSServerPortHelper
  → bootstrap_look_up → _xpc_interface_routine → _xpc_pipe_routine
```

UIKit's own backlight-level-change notification handler performs a synchronous
XPC Mach-port lookup to BackBoardServices; that call stalls, the main thread
blocks, and Sentry's hang tracker fires. Breadcrumbs corroborate: `started`
13:29:37.98, `device.orientation` 13:29:38.05, a 5m07s gap, `device.event`
13:34:45.08, hang 13:34:45.45. `SingleThreadApp.$main` is merely the topmost
*app* frame — which is why the report claimed "no app frames on the hung
thread". **No app-code change can prevent this stall.**

Supporting facts, source-verified:

- Pinned sentry-cocoa **9.29.2** (`SingleThread.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:7`).
- Hang events are built in `SentryHangTrackingIntegration.swift:96-115`:
  `mechanism.type == "AppHang"` (`:109`), `exceptions[0].stacktrace =
  threads[0].stacktrace` (the main thread, `snapshot = true`, `:111-112`),
  and `event.threads` populated with every thread (`:115`) with
  `threads[0].isMain == true` (`:113`, `SentryDefaultThreadInspector.swift:98`).
- The human-readable type strings (`"Fatal App Hang Fully Blocked"`, …) live in
  `SentryAppHangTypeMapper.swift:8-14`, which is `@_spi(Private)` — **not**
  importable via plain `import Sentry`. `"AppHang"` is the stable public marker.
- `beforeSend` runs for **both** the in-process hang and the next-launch fatal
  flush, and returning `nil` drops the event
  (`SentryClient.m:1156-1161`, `:394-402`).
- iOS/tvOS/visionOS in 9.29.2 use `SentryANRTrackerV2` unconditionally and the
  integration already gates on `applicationState == .active`
  (`SentryHangTrackingIntegration.swift:93-95`) and excludes background time, so
  "the app was backgrounded" is **not** an available explanation.
  `enableAppHangTrackingV2` does not exist in 9.29.2 (DOC-ONLY: removed in 9.x).
- `appHangTimeoutInterval` defaults to 2.0 s (`Options.swift:646-660`);
  `enableReportNonFullyBlockingAppHangs` is **deprecated** (`Options.swift:448-452`).
- Current wiring: `SentryBootstrap.swift:26,38-39` sets
  `enableAppHangTracking = true` and `beforeSend = { SentryScrubber.scrub($0) }`.
  `SentryScrubber.scrub(_ event: Event) -> Event?` is pure and already returns an
  optional, but **never returns `nil` today** (`SentryScrubber.swift:13-25`).
- Latent, unrelated main-thread defects found en route: `BackgroundImageStore`
  does synchronous `Data(contentsOf:)`/`FileManager` work on the MainActor
  (`BackgroundImageStore.swift:150,152,188,229,251`); `EKEventStore()` is
  constructed at launch (`ReminderStore.swift:24`) and
  `refreshSourcesIfNecessary()` runs synchronously on the MainActor
  (`ReminderStore.swift:525`).
- There are **no** `DispatchSemaphore`/`.sync`/`NSLock`/`Thread.sleep`/`RunLoop`/
  `while true`/`NSFileCoordinator`/`fatalError` in production source, and the
  rechecker (`StaleReminderRechecker.swift:102-138`) and AI coordinator
  (`AIReminderRanking.swift:108-165`) are cooperative and coalesced.

## Desired End State

1. A "Fatal App Hang Fully Blocked" event whose blocked stack is system-only and
   matches the BackBoardServices/backlight signature is **dropped in `beforeSend`**
   instead of being reported; every hang that has an app frame is still reported
   unchanged.
2. The drop rule is a pure, unit-tested predicate whose fixture is the **real
   captured stack from this ticket** — the reproducible regression artifact the
   repo's bug-fix policy requires.
3. `BackgroundImageStore`'s synchronous disk I/O no longer runs on the MainActor.
4. The rationale for the filter is recorded **in code** (Q6, revised), so a future
   reader cannot mistake it for a swallowed error.

**Verification:** `make format` + `make lint` clean;
`scripts/test-one.sh SingleThreadTests/SentryScrubberTests` and a new
`BackgroundImageStoreTests` case pass; then the full gate via the `run-gate`
skill. Manual confirmation: a unit-test assertion that the captured frame list is
dropped and an app-frame stack is not.

## Patterns to Follow

- **Pure static predicate in an `enum` namespace** — mirrors
  `SentryScrubber` (`SentryScrubber.swift:11,13,31`): `enum` + `nonisolated static func`,
  no state, directly unit-testable. Extend this type rather than adding a new
  service object.
- **Test style for Sentry types** — `SingleThreadTests/SentryScrubberTests.swift`
  uses Swift Testing, `import Sentry` (`:1-3`), and constructs SDK objects
  directly (`Event()` `:9`, `Exception(value:type:)` `:55-57`). Test names do not
  start with `test` (SwiftFormat strips the prefix).
- **Prefer a pure layer over SDK-object construction** — the repo's
  injectable-seam habit (`ReminderStoreSettle` `ReminderStore.swift:12,48-50`;
  `StaleReminderRechecker.Sleep` `StaleReminderRechecker.swift:27,34,46`) applies
  here: put the decision logic in a function over plain values, keep the SDK
  adapter thin.
- **MainActor isolation defaults** — the app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `SingleThreadCore` does not, so
  annotate explicitly there (`AGENTS.md` → Concurrency Model). `SentryScrubber`
  is already `nonisolated`.
- **Do NOT follow:** `enableReportNonFullyBlockingAppHangs` (deprecated →
  warning → gate failure under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`), any
  `@_spi(Private)` Sentry symbol, or raising `appHangTimeoutInterval` as a blunt
  instrument.

## Design Decisions

1. **Deliverable is containment, not a hang fix** — the stall is in
   `BKSDisplayBrightnessGetCurrent`/`bootstrap_look_up` via UIKit's own observer;
   no app frame participates, so app-code hardening cannot fix it. The ticket's
   testable artifact is therefore the event filter.
2. **Primary lever = signature-targeted `beforeSend` filter** (Q7=A) — it
   removes the false-alarm class without coarsening detection of real hangs.
   Options rejected: raising `appHangTimeoutInterval` (coarsens everything and
   still fails past the new threshold), disabling `enableAppHangTracking` (loses
   all ANR signal).
3. **Drop predicate = three-condition conjunction** (Q8=A), all of which must
   hold: (a) `exceptions` contains `mechanism.type == "AppHang"` (the public,
   stable marker; the descriptive strings are SPI), (b) the blocked stack has
   **zero app frames** (`frame.inApp != true` / `package != "SingleThread"`,
   both usable per `SentryFrame.h:41,94`), and (c) the signature contains the
   BackBoardServices/backlight denylist (`BKSDisplayBrightnessGetCurrent`,
   `bootstrap_look_up`). Narrowest predicate that still kills this class.
4. **Test surface = two layers** (Q9=A) — a pure
   `isSystemStall(frames:hasAppFrames:)`-style function over plain signature
   strings, plus a thin `Event → signature` adapter. The fixture is the captured
   frame list verbatim. This avoids depending on unverified public initializers
   for `Frame`/`Thread`/`Stacktrace` in the test target.
5. **Filter placement = extend `SentryScrubber`** — add the predicate and return
   `nil` from `scrub(_ event: Event)` when it matches. The signature already
   permits `nil` (`SentryScrubber.swift:13`), and `beforeSend` already routes
   through it (`SentryBootstrap.swift:38`), so no bootstrap plumbing changes.
   The existing PII-scrubbing branch order must be preserved for non-hang events.
6. **Rationale lives in code** (Q6, revised) — a doc comment on the predicate
   naming the issue id, the captured stack, and why it is system-only, plus the
   PR body. No `docs/CrashReporting.md` section, no Apple Feedback report.
7. **Bundled hardening = `BackgroundImageStore` only** (Q10=A) — move its
   synchronous `Data(contentsOf:)`/`FileManager` work off the MainActor. Bounded
   and low-risk; EventKit launch work is explicitly out of scope (see below).
8. **`"AppHang"` is matched as a literal, not via SPI** — `event.exceptions`
   is inspected directly; if a future SDK renames the mechanism string the filter
   stops matching and events are **reported** rather than lost (fail-open).

## What We're NOT Doing

- **Not moving EventKit off the main actor.** `EKEventStore()` construction
  (`ReminderStore.swift:24`) and `refreshSourcesIfNecessary()` (`:525`) stay as
  they are; relocating them requires changing `EventKitStoring`'s `@MainActor`
  isolation and the `ResumptionGate` contract (`ResumptionGate.swift:19-51`) — a
  separate ticket with its own tests.
- **Not adding Sentry breadcrumbs/instrumentation.** The Q1(A) "diagnose" half is
  unnecessary now that the stack is attributed; the cause is proven, not
  hypothesised.
- **Not touching `appHangTimeoutInterval`, `enableAppHangTracking`, or
  `enableReportNonFullyBlockingAppHangs`** (the last would break the gate).
- **Not using `@_spi(Private)`** (`SentryAppHangTypeMapper`, `SentryANRType`).
- **Not changing PII-scrubbing behaviour** for any event that isn't a matched
  system-stall hang.
- **Not touching the watch target** — the filter is iOS Sentry bootstrap only.
- **Not adding a UI test** — the change is a pure predicate; a UI test would be
  slow, flaky, and unable to trigger a BackBoardServices stall.
- **Not adding a docs page or an Apple Feedback report** (Q6, revised).

## Open Risks

- **Public initializers unverified.** The report confirmed `Frame.inApp`/
  `.package` exist but not public `Frame()`/`Thread()`/`Stacktrace(frames:)`
  initializers. Mitigated by Decision 4's pure-layer split; if the adapter cannot
  be unit-tested, the plan must say so and rely on the build for the adapter.
- **Fatal-flush retention inferred.** `beforeSend` provably runs on the fatal
  path (`SentryClient.m:394-402`), but that the *persisted* event still carries
  `event.threads`/`exceptions[0].stacktrace` at flush time was inferred, not
  proven. Verify during planning (plan-phase fact check), not at implementation.
- **Masking risk.** A genuine app hang whose stack happens to have zero app frames
  and passes through a backlight frame would be dropped. Bounded by the
  three-condition conjunction (Decision 3) and accepted.
- **Denylist coverage.** Only this one system signature is filtered; other
  system-stall signatures (CloudKit, StoreKit, cfprefsd) still report as noise.
  Adding signatures is a deliberate, reviewed act.
- **`BackgroundImageStore` timing change.** Moving its I/O off the MainActor may
  alter when the image is available and interacts with tests that inject
  `FakeBackgroundFetcher`/`SeededFetcher`; it needs its own test.
- **Audit-trail tension.** With Q6=C there is no external record; the only
  durable rationale is the code comment and PR body. A future maintainer may
  still delete the filter as "swallowed errors" — partially mitigated by
  Decision 6 and Decision 8's fail-open property.
- **SDK churn.** A sentry-cocoa bump may rename the `"AppHang"` mechanism; the
  failure mode is fail-open (noisy), never silent loss.
