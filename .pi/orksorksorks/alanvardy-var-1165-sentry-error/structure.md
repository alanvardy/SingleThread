# Structure Outline

## Approach

Contain, don't fix: the reported hang is a system-only stall
(`BKSDisplayBrightnessGetCurrent` → `bootstrap_look_up`) with no app frame, so
the shippable increment is a narrow `beforeSend` filter that drops exactly that
event class and leaves every other hang/crash untouched. The decision lives in a
pure predicate over plain values (repo test-seam style), with a thin `Event`
adapter; a single bundled hardening slice moves `BackgroundImageStore`'s
synchronous disk I/O off the MainActor.

All work lands on the main ticket branch — no child tickets.

**Pre-phase validation (plan step, not a slice):** confirm the open risk from
`design.md` — that the fatal-flush persisted event still carries
`event.exceptions[0].stacktrace` / `event.threads` at `beforeSend` time — before
relying on the filter for the next-launch flush. If it does not hold, the slice
still contains the in-process hang and Phase 1's contract is unchanged.

---

## Phase 1: Walking skeleton — drop the captured BackBoardServices stall in `beforeSend`

**Outcome**: the exact captured "Fatal App Hang Fully Blocked" event (system-only
blocked stack matching the backlight denylist) is dropped instead of reported,
end to end from the real captured signature through the pure predicate to
`SentryScrubber.scrub(_:)` returning `nil`; a hang carrying any app frame is
reported unchanged. Green tests prove both directions.

**Files**: `SingleThread/SentryScrubber.swift`,
`SingleThreadTests/SentryScrubberTests.swift` (app-target logic + its suite).

**Key changes**:
- `nonisolated static let systemStallSignatureFrames: Set<String>` — denylist
  `["BKSDisplayBrightnessGetCurrent", "bootstrap_look_up"]`.
- `nonisolated static func isSystemStall(mechanismType: String?, frameSignatures: [String], hasAppFrames: Bool) -> Bool`
  — pure three-condition conjunction: `mechanismType == "AppHang"` (public,
  stable marker) ∧ `!hasAppFrames` ∧ denylist ∩ signatures non-empty.
- `nonisolated static func appHangStack(in event: Event) -> (mechanismType: String, frameSignatures: [String], hasAppFrames: Bool)?`
  — thin adapter selecting the `"AppHang"` exception and reading its
  `stacktrace.frames` (`inApp == true` **or** `package == "SingleThread"` ⇒ app
  frame); returns `nil` for any shape it does not recognize (fail-open).
- `nonisolated static func scrub(_ event: Event) -> Event?` — when
  `appHangStack` is non-nil **and** `isSystemStall` is true, return `nil`;
  otherwise run the existing PII-scrub branch order unchanged.
- Doc comment on the predicate naming issue `7821993169`, the captured chain,
  and why a system-only stack is intentionally filtered (design Decision 6).

**Contract**: `isSystemStall(mechanismType:frameSignatures:hasAppFrames:)` and
`scrub(_:)`'s nil-on-match behaviour. Later slices/tests depend only on these,
never on the adapter internals. No `SentryBootstrap` change — `beforeSend`
already routes through `scrub` (`SentryBootstrap.swift:38`).

**Tests**: `dropsCapturedBacklightSystemStall` (fixture = captured frame list
verbatim; happy path), `keepsHangWithAppFrame` (sad path — one `inApp` frame),
`keepsNonHangBacklightEvent` (sad path — same system frames, no `"AppHang"`
mechanism ⇒ PII still scrubbed, not dropped).
**Verify**: `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes;
`make build`; manual check = the two assertions above demonstrate drop vs report.

---

## Phase 2: Fail-open guarantee — SDK churn or odd shapes never lose signal

**Outcome**: every deviation from the exact filtered shape still reports the
event, so a sentry-cocoa rename or a missing/empty stack surfaces as noise, never
as silent loss. This is the correctness hardening of Phase 1's predicate.

**Files**: `SingleThread/SentryScrubber.swift` (explicit `false`/`nil` guards),
`SingleThreadTests/SentryScrubberTests.swift`.

**Key changes**: clamp `isSystemStall` to `false` and `appHangStack` to `nil`
for every under-specified input; treat a frame as app-owned if either
`inApp == true` or `package == "SingleThread"` (belt-and-braces per
`SentryFrame.h`).

**Contract**: unchanged from Phase 1 — only more negative cases are pinned.

**Tests**: `keepsEventWhenMechanismRenamed`, `keepsEventWhenStacktraceMissing`,
`keepsEventWhenFrameListEmpty`, `keepsEventWhenDenylistPartiallyMatches`,
`keepsEventWhenAnyFrameIsInApp` (all sad paths; assertions are `scrub != nil`).
**Verify**: `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes.

---

## Phase 3: `BackgroundImageStore` disk I/O off the MainActor

**Outcome**: the wallpaper store's synchronous `Data(contentsOf:)` /
`FileManager` reads and writes no longer execute on the MainActor, removing a
real main-thread stall source independent of the Sentry filter.

**Files**: `SingleThread/BackgroundImageStore.swift`,
`SingleThreadTests/BackgroundImageStoreTests.swift`.

**Key changes**:
- `loadStoredImage()`, `isFresh(maxAge:)`, `persist(imageData:metadata:)` move
  their filesystem work into `nonisolated` helpers awaited from the existing
  `async` callers; observable state is assigned back on the MainActor after the
  disk work returns (disk-before-state ordering preserved).
- Public surface unchanged: `refreshIfNeeded(maxAge:)` / `forceRefresh()`
  signatures and `imageData`/`photographer`/`photographerURL` semantics stay as
  today; `BackgroundImageFetching` fakes unaffected.

**Contract**: `refreshIfNeeded`/`forceRefresh` behaviour and the observable
properties — existing callers (`ContentViewModel:156`,
`BackgroundSettingsView:57`) need no change.

**Tests**: existing `BackgroundImageStoreTests` must remain green; add
`diskWorkRunsOffMainActor` (sad path = the sync-read regression) plus a
behavior-parity case that a stored image still loads and a fresh sidecar still
short-circuits the network.
**Verify**: `scripts/test-one.sh SingleThreadTests/BackgroundImageStoreTests`
passes; `make build`.

---

## Testing Checkpoints

- After Phase 1: `SingleThreadTests/SentryScrubberTests` green (captured stack
  dropped, app-frame hang kept) before Phase 2 starts.
- After Phase 2: same suite green with the fail-open negatives added.
- After Phase 3: `SingleThreadTests/BackgroundImageStoreTests` green
  (off-main assertion + parity) before the gate.
- Once all three phases commit: run `make format` + `make lint` inline, then the
  full CI gate **once** via the `run-gate` skill (never `nohup`); no UI test is
  added (design decision — a UI test cannot trigger a BackBoardServices stall).
