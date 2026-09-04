# Implementation Plan

## Overview

Extract the widget's nested `NextThingEntry.State` into one shared
`public enum ListContent` in `SingleThreadCore`, add a single post-auth resolver
`ReminderStore.listContent`, and replace the three targets' divergent `if/else`
branch chains with exhaustive no-`default` switches. Pure refactor: widget
behavior is byte-for-byte unchanged; iOS/watch empty/all-done copy stays
identical.

Layered bottom-up: **Core type + resolver first** (fully unit-tested), then each
of the three consumers in sequence (widget, iOS, watch). Verify each stage before
committing; the full `make check` gate runs ONCE, by the parent, after all stages
commit.

---

## Stage 1: Core — `ListContent` enum + `ReminderStore.listContent` resolver

### Changes

#### 1. New shared enum

**File**: `SingleThreadCore/Sources/SingleThreadCore/ListContent.swift`
**Action**: create (auto-discovered by SwiftPM — no `Package.swift` change)

```swift
/// What a "list content" surface should render, resolved once by
/// `ReminderStore.listContent` instead of re-derived per target.
///
/// Pure Core logic, no SwiftUI — presentation lives in each app target.
public enum ListContent: Equatable, Sendable {
    case noAccess
    /// `hasHidden` is true when reminders exist but are out-of-window (or are
    /// undated while `showsUndatedReminders` is off).
    case empty(hasHidden: Bool)
    case allDone
    case reminder(ReminderDisplay)
}
```

Conformance notes (design decisions 1 & 6): plain `public enum` (data enum, mirroring
`SortOption.swift:6`, NOT the `public nonisolated enum` of the casing/logic enums);
`Equatable` for the ordering/equality asserts; `Sendable` because it threads through
the widget `TimelineEntry` under Swift 6. `ReminderDisplay` is already
`Equatable, Sendable` (`ReminderDisplay.swift:6`), so the transitivity holds. No
`Hashable`/`Codable`/`CaseIterable`.

#### 2. Resolver computed property

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify — insert after the `allSkipped` property (~`:136-140`), before
`canMutate`.

```swift
    /// Single post-auth resolution of what a list surface should show, in
    /// canonical order `allDone → reminder → empty`. Never returns `.noAccess`
    /// (auth is a target-local concern).
    public var listContent: ListContent {
        if allSkipped { return .allDone }
        if let first = visibleReminders.first { return .reminder(ReminderDisplay(reminder: first)) }
        return .empty(hasHidden: hasHidden)
    }
```

> **Note (corrects design sketch):** `visibleReminders` yields `EKReminder`, not
> `ReminderDisplay`, so the `.reminder` arm must convert via
> `ReminderDisplay(reminder: first)` (same call the widget's `makeEntry` uses today).
> The design.md pseudocode's bare `.reminder(first)` is shorthand; do not copy it
> literally.

#### 3. Unit tests

**File**: `SingleThreadTests/ListContentTests.swift`
**Action**: create (auto-discovered by the synchronized file group)

```swift
import EventKit
@testable import SingleThreadCore
import Testing

@MainActor
private let sharedTestEventStore = EKEventStore()

@MainActor
@Suite(.serialized)
struct ListContentTests {
    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: sharedTestEventStore)
        reminder.title = title
        return reminder
    }

    @Test
    func listContentReturnsAllDoneWhenAllSkipped() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .allDone)
    }

    @Test
    func listContentReturnsReminderWhenVisible() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "A")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        guard case let .reminder(display) = store.listContent else {
            Issue.record("expected .reminder, got \(store.listContent)")
            return
        }
        #expect(display.title == "A")
    }

    @Test
    func listContentReturnsEmptyWithoutHidden() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .empty(hasHidden: false))
    }

    @Test
    func listContentReturnsEmptyWithHidden() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            hasHidden: true)
        #expect(store.listContent == .empty(hasHidden: true))
    }

    @Test
    func emptyStoreNeverReturnsAllDone() {
        // Pin the mutual-exclusivity invariant: `allSkipped` requires a non-empty
        // store (ReminderStore.swift:139), so an empty store must resolve `.empty`.
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .empty(hasHidden: false))
        #expect(store.listContent != .allDone)
    }

    @Test
    func emptyHasHiddenPayloadDiffers() {
        #expect(ListContent.empty(hasHidden: false) != ListContent.empty(hasHidden: true))
    }
}
```

The `makeReminder` helper mirrors the file-private fixtures in
`ReminderStoreTests.swift:887` / `ReminderDisplayTests.swift:6` (each test file
declares its own `sharedTestEventStore`). Seeding via `InMemoryEventStore` +
`loadsReminders: false` — no real `EKEventStore` and no TCC prompt.

### Verification

#### Automated
- [x] `make test` — new `ListContentTests` green + all existing `SingleThreadTests` pins green
- [x] `make build` — Core package + app scheme compile (enum/conformance errors surface here)
- [x] `make format && make lint` — clean before commit (SwiftFormat `organizeDeclarations` may reorder the new enum; commit the formatted result)

#### Manual
- [ ] Read the diff for `ReminderStore.swift`/`ListContent.swift` — confirm `listContent` sits next to the other derived state (`allSkipped`/`visibleReminders`)

---

## Stage 2: Widget — migrate `NextThingEntry` to `ListContent`

### Changes

#### 1. Replace nested `State` with `ListContent`

**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — delete the nested `enum State` (`:10-15`); change the stored
property type.

```swift
struct NextThingEntry: TimelineEntry {
    let date: Date
    let state: ListContent
    let showsDate: Bool
    let showsList: Bool
    let showsRecurrence: Bool
    let showsAlarms: Bool
}
```

(`SingleThreadCore` is already imported at `:3`.)

#### 2. `makeEntry()` — consume the resolver

**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — replace the `isEmpty` check + `guard let current` +
`.empty(store.hasHidden)` block (`:74-98`) inside `.fullAccess` with the single
resolver call; keep the outer auth switch and `default:` → `.noAccess` untouched.

```swift
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            let store = ReminderStore(loadsReminders: true)
            store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            return NextThingEntry(
                date: date,
                state: store.listContent,
                showsDate: showsDate,
                showsList: showsList,
                showsRecurrence: showsRecurrence,
                showsAlarms: showsAlarms)
        default:
            return NextThingEntry(
                date: date,
                state: .noAccess,
                showsDate: showsDate,
                showsList: showsList,
                showsRecurrence: showsRecurrence,
                showsAlarms: showsAlarms)
        }
```

#### 3. View switch — no textual change

**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify (type-only) — the `switch entry.state` at `:140-161` is already
exhaustive over the four identical case shapes; it compiles unchanged (`case let
.empty(hasHidden)` already matches). The only source-level delta is the now-shared
`ListContent` type. Do not add a `default` arm.

Widget behavior is unchanged by construction: `allSkipped` is mutually exclusive
with an empty list, so `store.listContent` returns `.allDone` in exactly the case
where the old `isEmpty → allDone(guard)` chain did. `.noAccess` still comes from
the `default:` auth branch.

### Verification

#### Automated
- [ ] `make build` — widget app-extension compiles; an exhaustive `ListContent` switch with a dropped/extra case fails here (`error: switch must be exhaustive`)
- [ ] `make format && make lint` — clean

#### Manual
- [ ] Exercise the widget previews (`:257/:274/:286` — `.reminder`/`.noAccess`/`.allDone`) in Xcode; confirm each renders as before
- [ ] Home-screen widget sanity pass (medium/large families) — unaffected
- [ ] Note in PR: no `.empty` preview exists (out of scope, design decision 8)

---

## Stage 3: iOS — replace `reminderList` `if/else` chain with switch

### Changes

#### 1. Replace the chain with an exhaustive `switch`

**File**: `SingleThread/ContentView.swift`
**Action**: modify — keep `authGatedContent` (`:337-346`) untouched. Inside
`reminderList`'s `GeometryReader` (`:351-387`), replace the
`if allSkipped → else if isEmpty → else` chain with `switch viewModel.store.listContent`.

```swift
        switch viewModel.store.listContent {
        case .allDone:
            let allDoneCopy = ContentViewModel.allDoneStateCopy()
            ScrollView {
                EmptyStateCard(
                    copy: allDoneCopy,
                    maxWidth: EmptyStateCard.maxContentWidth(viewportWidth: geometry.size.width))
                    .frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center)
            }
            .scrollBounceBehavior(.always)
            .refreshable {
                await viewModel.reload(clearSkipped: true)
            }
        case let .empty(hasHidden):
            let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: hasHidden)
            ZStack(alignment: .bottom) {
                ScrollView {
                    EmptyStateCard(
                        copy: emptyCopy,
                        maxWidth: EmptyStateCard.maxContentWidth(viewportWidth: geometry.size.width))
                        .frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await viewModel.reload()
                }
                bottomBar
            }
        case .reminder:
            // Keep the inner `if let` so the `EKReminder` identifier stays in scope
            // for the deep link below; the associated `ReminderDisplay` is unused
            // here (binding it would trip the unused-value warning→error).
            ZStack(alignment: .bottom) {
                List {
                    if let reminder = viewModel.store.visibleReminders.first {
                        ReminderCardView(
                            display: ReminderDisplay(reminder: reminder),
                            showDate: showDate,
                            showList: showList,
                            showRecurrence: showRecurrence,
                            showAlarms: showAlarms,
                            showSwipePrompt: swipePromptBinding)
                            .listRowBackground(viewModel.rowChromeBackground)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(minHeight: viewHeight, alignment: .center)
                            .listRowSeparator(.hidden)
                        #if os(iOS)
                            .contextMenu {
                                // ... unchanged "View in Reminders" / delete buttons
                                //     referencing `reminder.calendarItemIdentifier`
                            }
                        #endif
                            .swipeActions(edge: .leading) { /* unchanged complete */ }
                            .swipeActions(edge: .trailing) { /* unchanged skip */ }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .refreshable {
                    await viewModel.reload()
                }
                bottomBar
            }
        case .noAccess:
            // Unreachable: `authGatedContent` diverts non-.fullAccess before this
            // renders. Required only for exhaustiveness — if auth ever collapses
            // into the enum, this arm is the footgun to revisit.
            EmptyView()
        }
```

Rules followed (design decision 5):
- `.allDone` keeps **no bottomBar**, `.refreshable { reload(clearSkipped: true) }`.
- `.empty(hasHidden)` and `.reminder` keep `bottomBar`.
- `.noAccess` is a commented `EmptyView()`.
- The `.reminder` arm deliberately keeps the existing inner `if let` binding
  instead of binding the `.reminder(display)` payload: `ReminderCardView` takes the
  `ReminderDisplay`, but the "View in Reminders" deep link needs
  `reminder.calendarItemIdentifier` (an `EKReminder` only). Binding the payload and
  discarding it (`case let .reminder(display)` without use) is a warning that
  fails under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

`ContentViewModel.swift` copy builders (`emptyStateCopy(hasHidden:)`,
`allDoneStateCopy()`) are unchanged and consumed exactly as today.

### Verification

#### Automated
- [ ] `make build` — exhaustive-switch compile check for iOS
- [ ] `make test` — `contentViewEmptyStatesShowDistinctCopy` / `contentViewAllDoneShowsAllDoneCopy` (`SingleThreadTests.swift:32-56`) stay green
- [ ] `make ui-test` — `emptyStateTitle` assertions unchanged (`SingleThreadUITestsFlows.swift:34/:43/:87/:149/:167`, `ActionButtonsUITests.swift:40`)
- [ ] `make format && make lint` — clean

#### Manual
- [ ] Run in simulator: empty list → "No Reminders" card; skip-all → "All Done" (no bottom bar); a visible reminder → card with complete/skip + bottom bar
- [ ] Verify "View in Reminders" context-menu deep link still opens the right reminder

---

## Stage 4: Watch — replace `reminderContent` chain with switch

### Changes

#### 1. Replace the chain, keep ghost branch outside the switch

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — keep the auth gate (`:47-54`) and the completion-transition
ghost branch (`:79-81`) *outside* the switch; then `switch viewModel.store.listContent`.

```swift
    private var reminderContent: some View {
        ZStack {
            if viewModel.isShowingCompletionTransition,
               let reminder = viewModel.transitionReminder {
                reminderCard(reminder)
            } else {
                switch viewModel.store.listContent {
                case .noAccess:
                    // Unreachable: `body` diverts non-.fullAccess before this.
                    // Required for exhaustiveness (footgun note — see Stage 3).
                    EmptyView()
                case .allDone:
                    allDoneState
                case let .empty(hasHidden):
                    noRemindersState(hasHidden: hasHidden)
                case .reminder:
                    // `reminderCard` takes an `EKReminder`; don't bind the payload.
                    if let reminder = viewModel.store.visibleReminders.first {
                        reminderCard(reminder)
                    }
                }
            }

            if viewModel.isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
        .overlay {
            if viewModel.completionGlow.isActive {
                completionGlowOverlay
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
    }
```

#### 2. `noRemindersState` becomes a parameterized builder

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — change the no-param computed property (`:158-166`) into a
function taking the `hasHidden` value from the switch binding.

```swift
    private func noRemindersState(hasHidden: Bool) -> some View {
        VStack(spacing: 6) {
            Text(SharedStrings.noReminders)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("emptyStateTitle")
            Text(hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            refreshButton
        }
    }
```

Confirm before editing: `noRemindersState` has no other callers (grep; the structure
found only the chain at `:87`). `allDoneState` (`:149-156`) is unchanged.

The ghost branch stays view-local (design decision 7) — it is a completion-transition
animation overlay, not a content state, and `ShowCompletionGlowStateTests` pins it.

### Verification

#### Automated
- [ ] `make watch-build` — exhaustive-switch compile check for watchOS
- [ ] `make watch-test` — `ShowCompletionGlowStateTests` (transition ghost) and `WatchReminderViewRegressionTests` green
- [ ] `make watch-ui-test` — `emptyStateTitle` assertions unchanged (`SingleThreadWatchUITestsFlows.swift:39-195`)
- [ ] `make format && make lint` — clean

#### Manual
- [ ] Run watch sim: All Done vs No Reminders vs reminder card all render; completion glow then "No Reminders" still holds (`--ui-testing-glow` seam)

---

## Final Gate (parent only, after all stages commit)

- [ ] `make check` — i.e. `./scripts/test.sh`, identical to CI (iOS + watch matrix runs), green once
- [ ] Confirm `git log` shows each stage as a scoped commit; no orphaned `DELETEME` marker

## Cross-cutting notes

- **Widget has no test target** — its "unchanged" guarantee rests on Stage-1 Core unit tests + code review (design decision 8; do NOT add `SingleThreadWidgetTests` — it needs pbxproj IDs, scheme wiring, `-only-testing`, CI matrix).
- **Unreachable `.noAccess` arms** (Stages 3-4) are required for exhaustiveness but dead while the auth gate is separate; the inline comments flag them for any future "collapse auth into the enum" refactor.
- **`Sendable` transitivity** depends on `ReminderDisplay` being `Sendable` — confirmed (`ReminderDisplay.swift:6`). If a Scratch finding differs, drop `Sendable` from `ListContent` and re-verify `make build`.
- **SwiftFormat `organizeDeclarations`** reorders the new enum/functions — run `make format` before each commit to avoid phantom diffs.
- **One xcodebuild test process at a time** (simulator contention); pin destinations via Makefile defaults (`SIM ?= iPhone 17` resolves to UDID inside `scripts/test.sh`). On `Busy`/`RequestDenied`: prune `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`.