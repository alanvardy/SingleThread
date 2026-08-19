# Implementation Plan

## Overview

Add a "Show Date" toggle (default **on**) that hides the due-date row —
`Text(due, style: .date)` + `.font(.caption)` + `.foregroundStyle(.secondary)` —
from the reminder card on iPhone/Mac, the watch card, and the widget. One shared
key `"showDate"` (stored in the App Group) is written by the phone, read directly
by the widget, and pushed to the watch over the existing WatchConnectivity
service. Sorting, the fetch window, and layout are untouched.

Each phase is a vertical slice (persistence → service → UI) with its own
verification checkpoint. Implement in order; do not reorganize.

---

## Phase 1: Phone/Mac — toggle + card gate + shared preference

Delivers the core feature end-to-end on iPhone/macOS: a settings row writing one
shared key, and the card hiding/showing its date row. Publishes the
`ShowDatePreference` core type + App Group key that Phases 2–3 build on.

### Changes

#### 1. New core preference type
**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowDatePreference.swift`
**Action**: create

New SPM source file (auto-discovered, no pbxproj edits). Mirrors
`SkippedReminderStore` but with a **nil→true** default (avoids `bool(forKey:)`,
which would hide dates by default on a missing key). Must be `public` (referenced
from the widget, watch, app, and tests).

```swift
import Foundation

/// Persists the user's "show due date" preference in UserDefaults.
///
/// Unlike `SkippedReminderStore`, an absent key resolves to `true` (today's
/// behavior) rather than `false` — `bool(forKey:)` would hide dates on first
/// launch. `nil` (missing key) therefore maps to `true`.
public struct ShowDatePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showDate") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether the due date is shown. `nil` (missing key) → `true`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Card gate + shared `@AppStorage` + settings sheet plumbing
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Three edits:

**(a)** Add the shared `@AppStorage` beside `showMicrophoneButton` (after
`ContentView.swift:127`):

```swift
    @AppStorage("showMicrophoneButton")
    private var showMicrophoneButton = true

    @AppStorage("showDate", store: AppGroup.defaults)
    private var showDate = true
```

**(b)** Gate the date row — extracted into a dedicated card view so the gate is
observable in string-snapshot tests. *Deviation:* the card `VStack` (title,
date, notes) moved from `ContentView` into a new `ReminderCardView`
(`SingleThread/ReminderCardView.swift`) — `List` type-erases `if` conditionals
to a stable `Optional<Text>`, making `String(describing: ContentView.body)`
byte-identical whether the date is shown or not. The card now renders as
`ReminderCardView(reminder: reminder, showDate: showDate)` with the gate inside
it (`if showDate, let due = ...`), and `ContentView`'s now-unused
`priorityColor` moved into the extracted view.

**(c)** Pass `showDate: $showDate` in **both** `.sheet` branches
(`ContentView.swift:67-79`):

```swift
            #if os(iOS)
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    allowsLandscape: $allowsLandscape,
                    showMicrophoneButton: $showMicrophoneButton,
                    showDate: $showDate)
            #else
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    showMicrophoneButton: $showMicrophoneButton,
                    showDate: $showDate)
            #endif
```

#### 3. Toggle row + binding plumbing
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

**(a)** Add `showDate: Binding<Bool>` to **both** initializers (last parameter)
and store it. iOS init (`SettingsView.swift:10-20`):

```swift
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            allowsLandscape: Binding<Bool>,
            showMicrophoneButton: Binding<Bool>,
            showDate: Binding<Bool>) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _allowsLandscape = allowsLandscape
            _showMicrophoneButton = showMicrophoneButton
            _showDate = showDate
        }
```

`#else` init (`SettingsView.swift:21-29`) — same, minus `allowsLandscape`.

**(b)** Add the stored binding next to `showMicrophoneButton`
(`SettingsView.swift:77`):

```swift
    @Binding private var showMicrophoneButton: Bool
    @Binding private var showDate: Bool
```

**(c)** Add the row after the "Show Microphone" toggle
(`SettingsView.swift:57-59`):

```swift
                Toggle(isOn: $showMicrophoneButton) {
                    Label("Show Microphone", systemImage: "microphone")
                }
                Toggle(isOn: $showDate) {
                    Label("Show Date", systemImage: "calendar")
                }
```

**(d)** Update the three `#Preview`s at the bottom of the file to pass
`showDate: .constant(true)` (and `.constant(false)` in the "Dark + Extra Large"
iOS preview) so the file compiles.

#### 4. Preference unit tests
**File**: `SingleThreadTests/ShowDatePreferenceTests.swift`
**Action**: create

Imports `SingleThreadCore` **non-`@testable`** (keeps the type Periphery-clean).

```swift
import SingleThreadCore
import Testing

struct ShowDatePreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }

    @Test
    func missingKeyIsNotFalse() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        // A missing key must never read as false (which would hide dates by
        // default). Distinguishes the nil→true default from bool(forKey:).
        #expect(preference.isEnabled != false)
    }
}
```

#### 5. ShowDateTests — snapshot the extracted card view
**File**: `SingleThreadTests/ShowDateTests.swift`
**Action**: create

Mirrors `MicrophoneToggleTests`. The date row is the only `Text(_, style: .date)`
on the card; SwiftUI describes it as a `FormatStyleStorage`, whereas the
title/notes rows are `LocalizedTextStorage` (verified: the date string is also
locale-dependent, so assert on the storage kind, which is stable).

*Deviation:* snapshots `ReminderCardView.body` (not `ContentView.body`) — `List`
erases the conditional, but the standalone card view reflects it
(`Optional(...FormatStyleStorage...)` present when shown, `nil` when hidden).

```swift
@testable import SingleThread
import EventKit
import SwiftUI
import Testing

@MainActor
struct ShowDateTests {
    @Test
    func dateRowHiddenWhenShowDateDisabled() {
        let description = String(describing: makeCard(showDate: false).body)
        // The date row is the only `Text(_, style: .date)`; hiding it removes
        // the FormatStyleStorage. Title/notes are LocalizedTextStorage.
        #expect(!description.contains("FormatStyleStorage"))
    }

    @Test
    func dateRowShownWhenShowDateEnabled() {
        let description = String(describing: makeCard(showDate: true).body)
        #expect(description.contains("FormatStyleStorage"))
    }

    // MARK: Private

    private func makeCard(showDate: Bool) -> ReminderCardView {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Buy groceries"
        reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15)
        return ReminderCardView(reminder: reminder, showDate: showDate)
    }
}
```

#### 6. Settings smoke test gains the new row
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add `showDate: .constant(true)` to both `SettingsView(...)` constructions (iOS
and `#else` branches), then add the assertion:

```swift
        #expect(bodyDescription.contains("Show Date"))
        #expect(bodyDescription.contains("Microphone"))
```

### Verification

#### Automated
- [x] `make test` passes (new `ShowDatePreferenceTests` + `ShowDateTests`; existing `SettingsViewTests` still green)
- [x] `make build` passes (iPhone sim build, warnings-as-errors on)
- [x] `make mac-build` passes (macOS variant compiles) — *environment note:* bare
  `make mac-build` fails on this machine for provisioning reasons (pre-existing,
  reproduced on the base commit). Verified with the CI-equivalent
  `CODE_SIGNING_ALLOWED=NO` build, which passes.
- [x] `make periphery` passes — `ShowDatePreference` is referenced by app + widget + sync service, so it is not flagged dead

#### Manual
- [ ] iPhone/Mac: gear → Settings shows a "Show Date" toggle (calendar icon), on by default
- [ ] Turn "Show Date" off → the date row disappears from the card (title + notes remain)
- [ ] Toggle back on → date row returns
- [ ] Quit and relaunch → the persisted choice sticks (key survives restart)

---

## Phase 2: Widget — read the shared key, gate the date row

The widget reads the same App Group key; the phone toggle now prompts an
immediate timeline reload.

### Changes

#### 1. Entry carries the flag; provider reads the pref
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

**(a)** Add the stored property to `NextThingEntry`:

```swift
struct NextThingEntry: TimelineEntry {
    enum State {
        case noAccess
        case empty
        case allDone
        case reminder(ReminderDisplay)
    }

    let date: Date
    let state: State
    let showsDate: Bool
}
```

**(b)** Hardcode `true` in the placeholder and snapshot entries:

```swift
        NextThingEntry(
            date: Date(),
            state: .reminder(ReminderDisplay(title: "Next thing")),
            showsDate: true)
```

and `getSnapshot`:

```swift
            NextThingEntry(
                date: Date(),
                state: .reminder(ReminderDisplay(title: "Buy groceries")),
                showsDate: true)
```

**(c)** `makeEntry` (`NextThingWidget.swift:50`) reads the pref once and sets it
on all four return paths:

```swift
    @MainActor
    private static func makeEntry() async -> NextThingEntry {
        let date = Date()
        let showsDate = ShowDatePreference().isEnabled
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            let store = ReminderStore(loadsReminders: true)
            await store.reload()
            if store.reminders.isEmpty {
                return NextThingEntry(date: date, state: .empty, showsDate: showsDate)
            }
            guard let current = store.visibleReminders.first else {
                return NextThingEntry(date: date, state: .allDone, showsDate: showsDate)
            }
            return NextThingEntry(
                date: date,
                state: .reminder(ReminderDisplay(reminder: current)),
                showsDate: showsDate)
        default:
            return NextThingEntry(date: date, state: .noAccess, showsDate: showsDate)
        }
    }
```

**(d)** Gate the date row in `reminderView` (`NextThingWidget.swift:169`):

```swift
            if entry.showsDate, let dueDate = display.dueDate {
                Text(dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

**(e)** Update the three `#Preview` timeline entries at the bottom of the file to
add `showsDate: true` (the memberwise init has no default, so these must change
to keep the file compiling).

#### 2. Reload timelines on toggle change
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

**(a)** Add the WidgetKit import at the top (after `import SwiftUI`):

```swift
import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif
```

**(b)** Attach `.onChange` to the new toggle (mirrors `allowsLandscape`):

```swift
                Toggle(isOn: $showDate) {
                    Label("Show Date", systemImage: "calendar")
                }
                #if os(iOS) || os(macOS)
                    .onChange(of: showDate) { _, _ in
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                #endif
```

### Verification

#### Automated
- [x] `make build` passes — builds the app **and** the widget extension (the date gate + entry change compile under warnings-as-errors)
- [x] `make mac-build` passes (via CI-equivalent `CODE_SIGNING_ALLOWED=NO`)
- [x] `make test` still passes (no unit-test regressions)

#### Manual
- [ ] On device/simulator: toggle "Show Date" off on the phone → the widget drops its date row immediately (not after the 15-minute refresh)
- [ ] Toggle back on → widget restores the date row immediately
- [ ] Fresh install (no `showDate` key) → widget still shows dates (nil→true default)

---

## Phase 3: Watch — WatchConnectivity push + watch card gate

The watch mirrors the phone's choice: the sync service carries `showDate`
alongside the skip IDs, the watch writes it to `UserDefaults.standard`, and
`WatchReminderView` gates its date row.

### Changes

#### 1. Sync service payload + push/receive of `showDate`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**(a)** Add the payload key (`SkippedReminderSyncService.swift:118-120`):

```swift
        private enum PayloadKey {
            static let skippedReminderIdentifiers = "skippedReminderIdentifiers"
            static let completeReminderIdentifier = "completeReminderIdentifier"
            static let showDate = "showDate"
        }
```

**(b)** Init gains two defaulted params (keeps every existing call site
compiling):

```swift
        public init(
            session: any SkipSyncSession,
            skipStore: SkippedReminderStore,
            showDateStore: ShowDatePreference = ShowDatePreference(),
            sendsShowDate: Bool = true) {
            self.session = session
            self.skipStore = skipStore
            self.showDateStore = showDateStore
            self.sendsShowDate = sendsShowDate
            super.init()
        }
```

**(c)** `pushSkipIDs` sends both keys when `sendsShowDate` (whole-context
clobber guard, decision 7):

```swift
        public func pushSkipIDs(_ ids: [String]) {
            do {
                var context: [String: Any] = [PayloadKey.skippedReminderIdentifiers: ids]
                if sendsShowDate {
                    context[PayloadKey.showDate] = showDateStore.isEnabled
                }
                try session.updateApplicationContext(context)
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push skip IDs: \(description, privacy: .public)")
            }
        }
```

**(d)** New `pushShowDate` (sends both keys together):

```swift
        /// Push the current skip set **and** the show-date preference in one
        /// context. `updateApplicationContext` replaces the whole context, so
        /// both keys must travel together or one clobbers the other.
        public func pushShowDate(_ enabled: Bool) {
            do {
                try session.updateApplicationContext([
                    PayloadKey.skippedReminderIdentifiers: skipStore.load(),
                    PayloadKey.showDate: enabled,
                ])
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push show-date preference: \(description, privacy: .public)")
            }
        }
```

**(e)** `didReceiveApplicationContext` (`SkippedReminderSyncService.swift:79-92`)
adopts `showDate` only when the key is present (absent key → no-op, so a
skip-only push never clobbers the receiver):

```swift
        public func session(
            _: WCSession,
            didReceiveApplicationContext applicationContext: [String: Any]) {
            if let receivedIDs = applicationContext[PayloadKey.skippedReminderIdentifiers] as? [String] {
                // Latest-wins: `updateApplicationContext` transmits the sender's
                // full skip set, so the received array is authoritative.
                // ReminderStore.reload() prunes stale IDs on the next fetch.
                skipStore.save(receivedIDs)
            }
            // Absent key → no-op, so a skip-only push never clobbers the
            // receiver's show-date preference.
            if let showDate = applicationContext[PayloadKey.showDate] as? Bool {
                showDateStore.set(showDate)
            }
        }
```

**(f)** Add the two stored properties at the bottom (next to `session` /
`skipStore`):

```swift
        private let session: any SkipSyncSession
        private let skipStore: SkippedReminderStore
        private let showDateStore: ShowDatePreference
        private let sendsShowDate: Bool
```

#### 2. Phone wires the toggle to the service
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

**(a)** Retain the service as a (iOS-gated) property, next to `store`
(`SingleThreadApp.swift:88`):

```swift
    #if os(iOS)
        private var syncService: SkippedReminderSyncService?
    #endif

    private let store: ReminderStore
```

**(b)** Add the shared `@AppStorage` (next to `store`, outside the `#if`):

```swift
    @AppStorage("showDate", store: AppGroup.defaults)
    private var showDate = true

    private let store: ReminderStore
```

**(c)** In `init`, pass the store and retain the service
(`SingleThreadApp.swift:19-25`):

```swift
            if WCSession.isSupported() {
                let service = SkippedReminderSyncService(
                    session: WCSession.default,
                    skipStore: SkippedReminderStore(),
                    showDateStore: ShowDatePreference(),
                    sendsShowDate: true)
                ...
                service.activate()
                syncService = service
                store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }
                store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
            }
```

**(d)** In `body`, attach the push `.onChange`:

```swift
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                #if os(iOS)
                    .onChange(of: showDate) { _, newValue in
                        syncService?.pushShowDate(newValue)
                    }
                #endif
        }
    }
```

#### 3. Watch constructs the service receiver-side
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

```swift
        if WCSession.isSupported() {
            let service = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore(),
                showDateStore: ShowDatePreference(defaults: .standard),
                sendsShowDate: false)
            service.activate()
            store.onSkipSetChanged = { ids in service.pushSkipIDs(ids) }
            store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
        }
```

#### 4. Watch card gate
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

**(a)** Add the `@AppStorage` (watch sandbox → `UserDefaults.standard`), next to
the other stored state (`WatchReminderView.swift:49`):

```swift
    @State private var isRefreshing = false
    @State private var isShowingRefreshConfirmation = false

    @AppStorage("showDate")
    private var showDate = true

    private let store: ReminderStore
```

**(b)** Gate the date row (`WatchReminderView.swift:155`):

```swift
            if showDate, let due = reminder.dueDateComponents?.date {
                Text(due, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

#### 5. Sync service tests
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Append inside the existing `SkippedReminderSyncServiceTests` struct (all under
`#if os(iOS) || os(watchOS)`):

```swift
        // MARK: - Show-date sync

        @Test
        func pushSkipIDsIncludesShowDate() throws {
            let fake = FakeSession()
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-sync-showdate-push")
            showDateStore.set(false)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-ids"),
                showDateStore: showDateStore,
                sendsShowDate: true)
            service.pushSkipIDs(["A"])
            let context = try #require(fake.lastContext)
            #expect((context["showDate"] as? Bool) == false)
            #expect(context["skippedReminderIdentifiers"] as? [String] == ["A"])
        }

        @Test
        func pushShowDateSendsBothKeys() throws {
            let fake = FakeSession()
            let skipStore = SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-both")
            skipStore.save(["X", "Y"])
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: skipStore,
                showDateStore: ShowDatePreference(defaults: .standard, key: "test-sync-showdate-both-pref"),
                sendsShowDate: true)
            service.pushShowDate(false)
            let context = try #require(fake.lastContext)
            #expect((context["showDate"] as? Bool) == false)
            #expect(context["skippedReminderIdentifiers"] as? [String] == ["X", "Y"])
        }

        @Test
        func receiveContextWritesShowDate() {
            let fake = FakeSession()
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-sync-showdate-receive")
            showDateStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-receive-ids"),
                showDateStore: showDateStore)
            service.session(
                WCSession.default,
                didReceiveApplicationContext: [
                    "skippedReminderIdentifiers": ["A"],
                    "showDate": false,
                ])
            #expect(showDateStore.isEnabled == false)
        }

        @Test
        func receiveContextMissingShowDateLeavesLocalUnchanged() {
            let fake = FakeSession()
            let showDateStore = ShowDatePreference(defaults: .standard, key: "test-sync-showdate-missing")
            showDateStore.set(true)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-missing-ids"),
                showDateStore: showDateStore)
            service.session(
                WCSession.default,
                didReceiveApplicationContext: ["skippedReminderIdentifiers": ["A"]])
            #expect(showDateStore.isEnabled) // unchanged
        }

        @Test
        func sendsShowDateFalseOmitsKey() throws {
            let fake = FakeSession()
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-sync-showdate-false"),
                showDateStore: ShowDatePreference(defaults: .standard, key: "test-sync-showdate-false-pref"),
                sendsShowDate: false)
            service.pushSkipIDs(["A"])
            let context = try #require(fake.lastContext)
            #expect(context["showDate"] == nil)
            #expect(context["skippedReminderIdentifiers"] as? [String] == ["A"])
        }
```

### Verification

#### Automated
- [x] `make test` passes (5 new sync tests + all prior suites)
- [x] `make watch-build` passes (watch target compiles with `ShowDatePreference`)
- [x] `./scripts/test.sh` passes — full pipeline: format, lint, iPhone build, watch build, Periphery, unit + UI tests, macOS build

  > *Note:* an earlier Periphery run flagged `SingleThreadApp.showDate` as unused
  > due to a stale index store (it is read via `.onChange(of: showDate)`). A fresh
  > `build-for-testing` + `--skip-build` scan reports it as referenced; the full
  > `test.sh` run passes cleanly with no ignore annotation needed.

#### Manual
- [ ] Pair a watch (or use two-simulator pairing), toggle "Show Date" on the phone → the watch drops the date row within the first sync
- [ ] Toggle back on → the watch restores it
- [ ] Skip a reminder on the watch → the phone's `showDate` value is **not** clobbered (watch never echoes `showDate`; phone stays authoritative)

---

## Noted deviations & risk notes (from design/structure)

- **Watch→phone echo** (decision 7 one-directional): `updateApplicationContext`
  replaces the whole context, and the watch also pushes skip IDs. `sendsShowDate:
  false` makes the phone authoritative for `showDate`; `didReceiveApplicationContext`
  only adopts the key when present.
- **First-launch staleness** (accepted in design): watch shows dates until the
  first context arrives; self-heals on connect. Unchanged.
- **`ShowDatePreference` is `public`** and referenced from `SingleThreadCore`
  (sync service), the phone app (`SingleThreadApp.swift`), and the widget
  (`NextThingWidget.makeEntry`) — plus non-`@testable` test imports — so Periphery
  (`retain_public: false`) will not flag it.