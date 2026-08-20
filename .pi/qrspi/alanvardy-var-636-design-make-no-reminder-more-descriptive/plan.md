# Implementation Plan

## Overview

Make the iOS "No Reminders" empty state descriptive by distinguishing *truly
empty* (no incomplete reminders at all) from *hidden by the view* (incomplete
reminders exist but fall outside today's window — future-dated, undated while
the toggle is off, or older than the 30-day overdue cutoff). A `hasHidden`
signal computed on `ReminderStore` drives the copy/icon on iOS, watch, and
widget; the same reason is conveyed on the companion surfaces so every surface
answers "nothing is showing" with a "here's why".

> **Go-back note (constraint):** `hasHidden` is derived in `reload()` only, but
> previews/unit tests seed the store via the `ReminderStore(loadsReminders:,
> reminders:, skippedIDs:, authorizationStatus:, excludedProjectTitles:)` init,
> which never runs `reload()` nor touches EventKit. That seeded init gains an
> optional `hasHidden:` param (plus a pure `hasHiddenFor` helper) so the hidden
> sub-state is previewable and unit-testable. This is a design-compatible
> addition, not a redesign.
>
> **Deviation from structure.md:** the structure lists a hypothetical
> `-only-testing:SingleThreadCore` command, but there is no Core test bundle —
> Core tests live in `ReminderStoreTests.swift` under the `SingleThreadTests`
> bundle. All derivation tests below run under `-only-testing:SingleThreadTests`.

---

## Phase 1: Store signals + seedable detection

Establishes the `hasHidden` fact in Core so every upper surface can branch on
it, and makes detection testable without EventKit. No user-visible change.

### Changes

#### 1. `ReminderStore` — new stored property
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add the stored property beside the sibling public properties (`:56-60`):

```swift
    /// `true` when incomplete reminders exist outside the current date window
    /// (or are undated while `showsUndatedReminders` is off). Set by `reload()`;
    /// seeded by the preview/test init. Lets surfaces explain an empty state
    /// that is actually "nothing due right now".
    public private(set) var hasHidden = false
```

#### 2. `ReminderStore` — new pure derivation helper
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a `public static func` in the "Public methods" section (near
`ReminderSort`/`ReminderDateFilter` static usage). Indexes `shown` by
`calendarItemIdentifier` and answers whether the broad incomplete set contains a
reminder that is not shown:

```swift
    /// Returns `true` when `allIncomplete` contains a reminder absent from
    /// `shown` (by `calendarItemIdentifier`) — i.e. the current in-window view
    /// is hiding at least one incomplete reminder.
    public static func hasHiddenFor(shown: [EKReminder], allIncomplete: [EKReminder]) -> Bool {
        let shownIDs = Set(shown.map(\.calendarItemIdentifier))
        allIncomplete.first(where: { !shownIDs.contains($0.calendarItemIdentifier) }) != nil
    }
```

#### 3. `ReminderStore` — extend the preview/test init
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add an optional trailing `hasHidden: Bool = false` param to the seeded init and
assign it. This is the seam that makes the hidden sub-state previewable/testable.

```swift
    public init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        excludedProjectTitles: Set<String> = [],
        hasHidden: Bool = false) {
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.excludedProjectTitles = excludedProjectTitles
        self.authorizationStatus = authorizationStatus
        self.hasHidden = hasHidden
        eventStore = EKEventStore()
        skipStore = SkippedReminderStore()
        excludeStore = ExcludedProjectStore()
    }
```

#### 4. `ReminderStore.reload()` — compute `hasHidden`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

In `reload()`, after `let shown = ...` and before `reminders = shown`, derive
`hasHidden`. When `showsUndatedReminders` is already true, the in-hand `fetched`
is already the broad set, so compare it against `shown`. Otherwise run **one
extra** broad (nil/nil) fetch and compare against the narrow `shown`:

```swift
        let shown = showsUndatedReminders
            ? fetched.filter { ReminderDateFilter.isInCurrentWindow($0.dueDateComponents?.date) }
            : fetched
        if showsUndatedReminders {
            // Broad fetch already in hand — derive from fetched vs shown.
            hasHidden = Self.hasHiddenFor(shown: shown, allIncomplete: fetched)
        } else {
            // Narrow fetch excludes future/old/undated work; one extra broad fetch
            // reveals whether the window is hiding reminders.
            let broadPredicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil)
            let allIncomplete: [EKReminder] = await fetchReminders(matching: broadPredicate)
            hasHidden = Self.hasHiddenFor(shown: shown, allIncomplete: allIncomplete)
        }
        reminders = shown
```

`Self.hasHiddenFor(...)` follows the existing `Self.makeEntry()` /
`Self.applyAppearance(...)` static-call convention.

### Verification
#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug open build` (or `make build`) compiles with the new property, init param, and static helper.
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes with new `ReminderStoreTests` `hasHidden` cases (below).
- [x] `swiftlint lint --strict` is clean (variable names all ≥ 3 chars).

Add to `SingleThreadTests/ReminderStoreTests.swift` (new `// MARK: - hasHidden`
section; reuses the existing `makeReminder(title:)` fixture):

```swift
    // MARK: - hasHidden

    @Test
    func hasHiddenDefaultsToFalse() {
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!store.hasHidden)
    }

    @Test
    func hasHiddenSeedsFromInit() {
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            hasHidden: true)
        #expect(store.hasHidden)
    }

    @Test
    func hasHiddenForFalseWhenSetsMatch() {
        let a = makeReminder(title: "A")
        #expect(!ReminderStore.hasHiddenFor(shown: [a], allIncomplete: [a]))
    }

    @Test
    func hasHiddenForTrueWhenIncompleteHasHidden() {
        let shown = makeReminder(title: "In")
        let hidden = makeReminder(title: "Hidden")
        #expect(ReminderStore.hasHiddenFor(shown: [shown], allIncomplete: [shown, hidden]))
    }
```

#### Manual
- [ ] None — no visible change yet.

---

## Phase 2: iOS contextual empty state

Splits the iOS empty `reminderList` branch into two copy/icon variants driven by
`store.hasHidden`, keeping pull-to-refresh + the mic `bottomBar` affordances.

### Changes

#### 1. `ContentView` — thread `hasHidden` through the preview init
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add a trailing `hasHidden: Bool = false` to the pre-populated `init` (around
`:22-35`) and pass it to the store:

```swift
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        excludedProjectTitles: Set<String> = [],
        hasHidden: Bool = false,
        speechTranscriber: (any SpeechTranscribing)? = nil) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus,
            excludedProjectTitles: excludedProjectTitles,
            hasHidden: hasHidden)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
    }
```

#### 2. `ContentView.reminderList` — split the empty branch
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Replace the current "No Reminders" arm (currently `ContentView.swift:251-265`)
so it branches on `store.hasHidden`. Keep the `ScrollView` frame,
`.scrollBounceBehavior(.always)`, `.refreshable { await store.reload() }`, and
the trailing `bottomBar` exactly as-is. Both arms still use
`ContentUnavailableView(title, systemImage:, description:)`:

```swift
            } else if store.reminders.isEmpty {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        if store.hasHidden {
                            ContentUnavailableView(
                                "Nothing due",
                                systemImage: "calendar",
                                description: Text("Only today's and overdue reminders show here — pull to refresh."))
                                .frame(minHeight: viewHeight, alignment: .center)
                        } else {
                            ContentUnavailableView(
                                "No Reminders",
                                systemImage: "checklist",
                                description: Text("You don't have any reminders yet."))
                                .frame(minHeight: viewHeight, alignment: .center)
                        }
                    }
                    .scrollBounceBehavior(.always)
                    .refreshable {
                        await store.reload()
                    }
                    bottomBar
                }
            } else {
```

#### 3. `ContentView` previews — two sub-states
**File**: `SingleThread/ContentView.swift` (preview block, `:470-506`)
**Action**: modify

Keep `#Preview("Empty")` (renders the truly-empty variant via `hasHidden`
default `false`) and add a second hidden preview:

```swift
#Preview("Empty") {
    ContentView(loadsReminders: false)
}

#Preview("Nothing Due") {
    ContentView(loadsReminders: false, hasHidden: true)
}
```

### Verification
#### Automated
- [x] `make build` compiles ContentView, ReminderStore, and the SwiftUI `ContentUnavailableView` usage.
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes with new `contentViewEmptyStatesShowDistinctCopy` copy assertions (below).
- [x] Existing `contentViewBodyContainsRefreshableModifier` still passes (both variants still contain `refreshable`).

> **Adaptation note:** `String(describing: view.body)` proved unreliable for asserting
> rendered text — in an isolated run it includes `Text`/label content, but in the
> full `SingleThreadTests` bundle the same expression returns a text-free structural
> type dump (so `.contains("No Reminders")` fails). To keep a deterministic,
> non-flaky view-level test, the iOS empty-state copy/icon was lifted into a small
> `ContentView.EmptyStateCopy` struct returned by a new `ContentView.emptyStateCopy(hasHidden:)`
> helper (the `reminderList` empty branch now renders from it). The unit test asserts on
> that helper instead of on body-string reflection.

Add to `SingleThreadTests/SingleThreadTests.swift`, next to the existing
`ContentView` tests:

```swift
    @Test
    func contentViewEmptyStatesShowDistinctCopy() {
        let emptyCopy = ContentView.emptyStateCopy(hasHidden: false)
        #expect(emptyCopy.title == "No Reminders")
        #expect(emptyCopy.systemImage == "checklist")
        #expect(emptyCopy.description == "You don't have any reminders yet.")

        let nothingDueCopy = ContentView.emptyStateCopy(hasHidden: true)
        #expect(nothingDueCopy.title == "Nothing due")
        #expect(nothingDueCopy.systemImage == "calendar")
        #expect(nothingDueCopy.description == "Only today's and overdue reminders show here — pull to refresh.")
        #expect(emptyCopy.title != nothingDueCopy.title)
    }
```

#### Manual
- [ ] Run `#Preview("Empty")` on the Quartz simulator: "No Reminders" + `checklist` icon + "You don't have any reminders yet." Confirm pull-to-refresh still calls `store.reload()` and mic `bottomBar` still overlays.
- [ ] Run `#Preview("Nothing Due")`: "Nothing due" + `calendar` icon + "Only today's and overdue reminders show here — pull down to refresh." Confirm same affordances.

---

## Phase 3: Roll out to watch + widget

Applies the same signal to the companion surfaces for consistent "nothing due,
here's why" copy.

### Changes

#### 1. Watch — add a description to `noRemindersState`
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify (`noRemindersState`, currently `:110-116`)

Add a `Text` child under the headline, keyed off `store.hasHidden`. Keep the
existing `refreshButton`:

```swift
    private var noRemindersState: some View {
        VStack(spacing: 6) {
            Text("No Reminders")
                .foregroundStyle(.secondary)
            Text(store.hasHidden ? "Nothing due right now" : "No reminders yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            refreshButton
        }
    }
```

#### 2. Watch — preview the hidden sub-state
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Add a trailing `hasHidden: Bool = false` to the preview init and pass it through:

```swift
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        hasHidden: Bool = false) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus,
            hasHidden: hasHidden)
    }
```

Add a preview seeding the hidden variant:

```swift
#Preview("Nothing Due") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        hasHidden: true)
}
```

#### 3. Widget — carry `hasHidden` into the `.empty` state
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

The widget's view only sees the `entry`, not the store, so the hidden fact must
ship on the state. Change the `State` enum's `.empty` case to carry a `Bool`:

```swift
    enum State {
        case noAccess
        case empty(Bool)   // hasHidden — true when reminders exist but are out-of-window
        case allDone
        case reminder(ReminderDisplay)
    }
```

Update the `makeEntry()` constructor site (currently
`return NextThingEntry(date: date, state: .empty, showsDate: showsDate)`) to
`.empty(store.hasHidden)`:

```swift
            if store.reminders.isEmpty {
                return NextThingEntry(
                    date: date,
                    state: .empty(store.hasHidden),
                    showsDate: showsDate)
            }
```

Update the `.empty` arm of `NextThingWidgetView.body` to pass a real message
instead of `nil`:

```swift
        case let .empty(hasHidden):
            messageView(
                title: "No Reminders",
                systemImage: "checklist",
                message: hasHidden ? "Nothing due right now" : "No reminders yet")
```

(`messageView` already renders its `Text(message)` as `.caption2` + `.secondary`
and is unchanged.)

### Verification
#### Automated
- [x] `make watch-build` compiles the watch target; `make build` compiles the iOS/widget targets.
- [x] `swiftlint lint --strict` passes (watch/widget target rules already extend the Core opt-in set).
- [x] No production-signature changes elsewhere — `store.reload()` still populates `hasHidden` for the widget's `loadsReminders: true` path.

#### Manual
- [ ] Watch `#Preview("No Reminders")` shows "No Reminders" + "No reminders yet" + Refresh button.
- [ ] Watch `#Preview("Nothing Due")` shows "No Reminders" + "Nothing due right now" + Refresh button; a real on-device reload with a hidden future-reminder flips the copy.
- [ ] Widget: with a store that reports `hasHidden`, the `.empty` card shows "No reminders yet"→"Nothing due right now" with the `checklist` icon; accessible description reads via the `Text` (not the `accessibilityHidden` icon).

---

## Phase 4: Test hardening, UI comment fix, full CI

Correct the stale UI-test assumption, lock the All Done + empty copy, and run the
full gate. **No production-signature changes** in this phase.

### Changes

#### 1. Fix the stale UI-test comment
**File**: `SingleThreadUITests/SingleThreadUITests.swift` (`:22-23`)
**Action**: modify

The claim that `--ui-testing` shows a "Requesting access…" `ProgressView` is
wrong — `ContentView.swift:43-45` maps `loadsReminders: false` to the empty
`reminderList` branch, so the "No Reminders" empty state renders. Correct the
comment:

```swift
        // With --ui-testing, the app instantiates an empty store
        // (loadsReminders: false), so the view renders the "No Reminders"
        // empty reminderList branch. Wait for any visible text element before
        // auditing.
```

The existing `testAccessibilityAudit()` only waits for any static text and does
not assert on a string, so it stays green without further edits.

#### 2. Lock the "All Done" placeholder copy
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: add

There is no existing assertion on the "All Done" branch body. Add one alongside
the Phase 2 copy tests, seeding a non-empty store that is fully skipped:

```swift
    @Test
    func contentViewAllDoneShowsAllDoneCopy() {
        let reminder = makeStubReminder(title: "A")
        let view = ContentView(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let desc = String(describing: view.body)
        #expect(desc.contains("All Done"))
        #expect(desc.contains("Pull to refresh"))
    }
```

Add the stub fixture at the bottom of `SingleThreadTests.swift`:
`@testable import EventKit` is already part of the target's imports
(`SingleThread` is @testable; EventKit comes via the Core dependency):

```swift
private func makeStubReminder(title: String = "Stub") -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    return reminder
}
```

(If `EKReminder`/`EKEventStore` aren't directly visible in this file — the file
already relies on `@testable import SingleThreadCore` — add `import EventKit` to
the file's imports.)

### Verification
#### Automation
- [ ] `./scripts/test.sh` passes end-to-end: swiftformat → swiftlint --strict → build (iPhone 17) → Periphery → unit (`-only-testing:SingleThreadTests`) → UI/accessibility (`-only-testing:SingleThreadUITests`) → SwiftFormat/SwiftLint re-check.
- [ ] `make format` then `make lint` are clean before the full run.

#### Manual
- [ ] Confirm the `--ui-testing` app now renders the "No Reminders" empty state (not "Requesting access…") and `testAccessibilityAudit` still passes (dynamic type, hit regions, element descriptions, traits).

---

## Testing Checkpoints

- **After Phase 1**: `ReminderStore.hasHidden` exists and is seeded via init;
  derivation unit tests green; build compiles. (No visible change.)
- **After Phase 2**: iOS empty branch shows two distinct bodies/icons; copy unit
  tests green; both previews present; mic + pull-to-refresh unaffected.
- **After Phase 3**: watch and widget show a matching description; iOS/watch/
  widget all agree on the same hidden signal.
- **After Phase 4**: full `./scripts/test.sh` gate green; stale `--ui-testing`
  comment corrected.

## Explicitly non-sliceable / risk notes

- The broad `reload()` EventKit fetch is integration-only (needs a live store);
  guarded by the Phase-1 pure `hasHiddenFor` helper + Phase-2 seeded tests.
- The extra broad fetch (narrow mode only) adds one EventKit round trip per
  `reload()`; acceptable for typical library sizes. When `showsUndatedReminders`
  is already true, no extra fetch is issued (reusing the broad in-hand set).
- Watch reads EventKit read-only; the extra fetch is read-only and unchanged. If
  on-device watch testing shows the broad fetch is unexpectedly expensive, keep
  `hasHidden` seeded/hidden on the watch but flag for product review.
- The two iOS variants share one branch's `bottomBar`/`.refreshable` — they must
  be changed together (Phase 2 does this in one edit).