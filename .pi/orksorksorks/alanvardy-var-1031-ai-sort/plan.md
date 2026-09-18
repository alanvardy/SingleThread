# Implementation Plan

## Overview

Add `.ai` as a fourth `SortOption` and wire a store-backed rule text box →
`AISortCoordinator` (core, fake-rankable) → `AISortRulesStore` (App Group) →
`ReminderStore.aiRanking` rank cache consulted by `visibleReminders`. The
`FoundationModels` adapter lives in one gated file in the iOS/macOS app target;
every other layer is core and testable without Apple Intelligence. Where the
model is unavailable (CI, iOS 17–25, Apple Intelligence off) `.ai` stays
selectable and orders by the `.priority` chain, with a footer explaining why.

---

## Preflight — SDK / toolchain probe (run BEFORE Phase 1 code)

Structure requires the gated-import probe to be green before the adapter is
written. **This was executed during planning under the local toolchain and is
green** (Xcode 27.0, `xcodebuild -version` → `Xcode 27.0 / 27A266a`):

- [x] iOS floor probe (`#if canImport(FoundationModels)` + `#available(iOS 26.0, macOS 26.0, *)` + `@Generable` + `@Guide` + `session.respond(to:generating:)`) type-checks at the repo's **iOS 17.0 floor**:
      `xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -swift-version 6 -default-isolation MainActor -typecheck <probe>` → exit 0
- [x] macOS probe at the app target's floor: `xcrun --sdk macosx swiftc -target arm64-apple-macos26.5 -swift-version 6 -default-isolation MainActor -typecheck <probe>` → exit 0
- [x] `nonisolated struct` + `nonisolated` members satisfying a **core (nonisolated) Sendable protocol** compiles under `-default-isolation MainActor` (the app target's setting) → exit 0
- [x] watchOS note: `canImport(FoundationModels)` is *true* on watchOS 27 SDKs, so `#if canImport(...)` alone is not a platform gate — the adapter stays out of the watch target, and `#available(iOS 26.0, macOS 26.0, *)` is always paired with it.

CI ships Xcode 26.6, which is not installed locally, so the CI-toolchain check
is the CI build itself. Fallback if CI rejects the gated import (design Open
Risk 1): move the adapter file behind a file-level `#if os(iOS) || os(macOS)`
guard plus a thin `@available` wrapper; raising the deployment floor is out of
scope and requires a re-decision with the user.

---

## Phase 1: Walking skeleton — AI reorders the list end to end

### Changes

#### 1. `SortOption` gains `.ai`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift`
**Action**: modify

```swift
public enum SortOption: String, CaseIterable, Sendable {
    /// Today's compound order: priority rank → due date → title.
    case priority
    /// Due date soonest-first (dated before undated) → title.
    case dueDate
    /// Case-insensitive title A→Z → due date.
    case title
    /// On-device AI ranking against the user's freeform rules, falling back to
    /// the `.priority` chain when no ranking is available.
    case ai

    // MARK: Public

    /// Single shared key used by `SortOptionStore`, the app's `@AppStorage`,
    /// and nowhere else as a raw literal.
    public static let defaultsKey = "sortOption"
}
```

#### 2. `AISortRulesStore` (new)
**File**: `SingleThreadCore/Sources/SingleThreadCore/AISortRulesStore.swift`
**Action**: create — mirrors `SortOptionStore`; App-Group only (conventions §3).

```swift
import Foundation

/// Persists the user's freeform AI-sort rules in the App Group, mirroring
/// ``SortOptionStore``. The text is opaque: it is handed to the ranking
/// implementation as-is and never parsed here.
public struct AISortRulesStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = AISortRulesStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key, also wiped by `UITestingSeed.resetPersistedState`.
    public static let defaultsKey = "aiSortRules"

    /// The stored rules, or `""` when nothing has been saved yet.
    public func load() -> String {
        defaults.string(forKey: key) ?? ""
    }

    public func save(_ rules: String) {
        defaults.set(rules, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 3. `AIReminderCandidate` + `AIReminderRanking` + `AIRankingError` + `AISortCoordinator` (new)
**File**: `SingleThreadCore/Sources/SingleThreadCore/AIReminderRanking.swift`
**Action**: create.

Phase-1 (thin) coordinator — no debounce, no dedupe, previous order simply
replaced. Phase 3 replaces `update`'s body with the full version.

```swift
import Foundation

/// One reminder, flattened to the value data the ranker needs. `Sendable` so it
/// can cross into the ranking task; `Equatable` for the Phase-3 input digest.
public struct AIReminderCandidate: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        identifier: String,
        title: String,
        notes: String?,
        priority: Int,
        dueDate: Date?,
        listTitle: String?) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.listTitle = listTitle
    }

    // MARK: Public

    public let identifier: String
    public let title: String
    public let notes: String?
    public let priority: Int
    public let dueDate: Date?
    public let listTitle: String?
}

/// Injectable ranking capability. Production is the app target's
/// FoundationModels adapter; tests use fakes.
public protocol AIReminderRanking: Sendable {
    /// Returns reminder identifiers best-first. The implementation must be
    /// treated as untrusted (Phase 3 reconciles the result).
    func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String]
}

/// Errors the ranking layer can surface. The coordinator treats every error as
/// "keep the previous ranking".
public enum AIRankingError: Error, Equatable {
    case unavailable
}

/// Owns the in-flight ranking task and hands a validated identifier→rank map
/// back to the store. `@MainActor` is explicit — `SingleThreadCore` does not
/// enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (conventions §6).
@MainActor
public final class AISortCoordinator {
    // MARK: Lifecycle

    public init(ranker: any AIReminderRanking) {
        self.ranker = ranker
    }

    // MARK: Public

    /// Set by `AppViewModel` to write the ranking into `ReminderStore`.
    public var onRankingUpdated: (([String: Int]) -> Void)?

    public func update(rules: String, candidates: [AIReminderCandidate]) {
        let trimmed = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pending?.cancel()
        pending = Task { [weak self, ranker] in
            do {
                let ranked = try await ranker.rank(candidates, rules: trimmed)
                guard let self else { return }
                self.pending = nil
                self.emit(Self.ranking(from: ranked))
            } catch {
                guard let self else { return }
                self.pending = nil
                // Retain the previous ranking.
            }
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    // MARK: Private

    private let ranker: any AIReminderRanking
    private var pending: Task<Void, Never>?

    /// First occurrence wins, so a duplicated identifier never overwrites an
    /// earlier (better) rank.
    private static func ranking(from identifiers: [String]) -> [String: Int] {
        var ranking: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() where ranking[identifier] == nil {
            ranking[identifier] = index
        }
        return ranking
    }

    private func emit(_ ranking: [String: Int]) {
        onRankingUpdated?(ranking)
    }
}
```

#### 4. `ReminderSort` `.ai` branch
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`
**Action**: modify — the switch is exhaustive, so `.ai` is a compile error until
this branch exists. `.ai` matches the `.priority` chain (the off-iOS case; the
real ranking is applied in `ReminderStore.visibleReminders`, which owns the
rank cache).

```swift
        switch option {
        case .priority, .ai:
            if let rank = comparePriorities(lhs, rhs) {
```

(Drop the old `case .priority:` line; the `.dueDate` and `.title` cases are
untouched.)

#### 5. `ReminderStore`: rank cache + candidate projection
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify — three additions next to the existing `sortOption`/
`visibleReminders` members.

```swift
    /// Identifier → rank for the `.ai` sort option. Empty means no ranking is
    /// available, so ordering falls through to the `.priority` chain.
    public private(set) var aiRanking: [String: Int] = [:]

    /// Assigns a new AI ranking. No hook is fired: `ReminderStore` is
    /// `@Observable`, so the mutation already invalidates every view that reads
    /// `visibleReminders`. Firing `onRemindersChanged` here would re-trigger the
    /// coordinator that produced the ranking.
    public func setAIRanking(_ ranking: [String: Int]) {
        guard ranking != aiRanking else { return }
        aiRanking = ranking
    }
```

Replace the existing `visibleReminders` with the rank-aware version plus the
extracted filter (the two filter lines move verbatim):

```swift
    /// The visible reminder set with no ordering applied — the base for
    /// `visibleReminders` and the input surface for `aiCandidates`.
    public var filteredReminders: [EKReminder] {
        reminders
            .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
            .filter { !excludedListTitles.contains($0.calendar?.title ?? "") }
    }

    public var visibleReminders: [EKReminder] {
        let filtered = filteredReminders
        guard sortOption == .ai, !aiRanking.isEmpty else {
            return filtered.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }
        }
        return filtered.sorted { lhs, rhs in
            let lhsRank = aiRanking[lhs.calendarItemIdentifier]
            let rhsRank = aiRanking[rhs.calendarItemIdentifier]
            switch (lhsRank, rhsRank) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return ReminderSort.areInIncreasingOrder(lhs, rhs, using: .priority)
            }
        }
    }

    /// The visible reminder set as ranker input, in a stable
    /// (ranking-independent) identifier order so re-ranking the same set never
    /// changes the Phase-3 input digest.
    public var aiCandidates: [AIReminderCandidate] {
        filteredReminders
            .map { reminder in
                AIReminderCandidate(
                    identifier: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    notes: reminder.notes,
                    priority: reminder.priority,
                    dueDate: reminder.dueDateComponents?.date,
                    listTitle: reminder.calendar?.title)
            }
            .sorted { $0.identifier < $1.identifier }
    }
```

#### 6. `SortOption` presentation
**File**: `SingleThread/SortOption+Presentation.swift`
**Action**: modify — both switches are exhaustive.

```swift
        case .title: String(localized: "Title", table: "Localizable", bundle: .main)
        case .ai: String(localized: "AI", table: "Localizable", bundle: .main)
        ...
        case .title: "textformat.abc"
        case .ai: "sparkles"
```

#### 7. Localization catalog entries
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — every existing key is `"extractionState": "manual"` with all
six languages, so new keys are added the same way. `LocalizationTests`
(`catalogsParseAndHaveNonEmptyEnglish`, `catalogsHaveAllSixLanguages`,
`nonEnglishValuesDifferFromEnglish`) fails on any key missing a locale.

Add four entries under `"strings"`:

```json
    "AI": {
      "extractionState": "manual",
      "localizations": {
        "en": { "stringUnit": { "state": "translated", "value": "AI" } },
        "de": { "stringUnit": { "state": "translated", "value": "KI" } },
        "es": { "stringUnit": { "state": "translated", "value": "IA" } },
        "fr": { "stringUnit": { "state": "translated", "value": "IA" } },
        "ja": { "stringUnit": { "state": "translated", "value": "AI" } },
        "zh-Hans": { "stringUnit": { "state": "translated", "value": "AI" } }
      }
    }
```

| Key | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `AI Sort Rules` | KI-Sortierregeln | Reglas de ordenación con IA | Règles de tri par IA | AI並べ替えルール | AI 排序规则 |
| `Describe how reminders should be ordered. On-device AI applies these rules.` | Beschreibe, wie Erinnerungen sortiert werden sollen. On-Device-KI wendet diese Regeln an. | Describe cómo deberían ordenarse los recordatorios. La IA en el dispositivo aplica estas reglas. | Décrivez comment les rappels doivent être triés. L'IA sur l'appareil applique ces règles. | リマインダーの並び順を説明します。オンデバイスのAIがこのルールを適用します。 | 描述提醒应如何排序，设备端 AI 会应用这些规则。 |
| `Describe how reminders should be ordered. This device can't run on-device AI, so reminders stay in priority order.` | Beschreibe, wie Erinnerungen sortiert werden sollen. Dieses Gerät kann keine On-Device-KI ausführen, daher bleibt die Prioritätsreihenfolge erhalten. | Describe cómo deberían ordenarse los recordatorios. Este dispositivo no puede ejecutar IA en el dispositivo, así que el orden por prioridad se mantiene. | Décrivez comment les rappels doivent être triés. Cet appareil ne peut pas exécuter l'IA sur l'appareil, les rappels restent donc classés par priorité. | リマインダーの並び順を説明します。このデバイスではオンデバイスAIを実行できないため、優先度順のままになります。 | 描述提醒应如何排序。此设备无法运行设备端 AI，因此提醒仍按优先级排序。 |

The fourth key is only consumed in Phase 2 — added here so the catalog is
touched once.

`"AI"` is byte-identical in `ja`/`zh-Hans` (standard acronym), so add an
exclusion in `LocalizationTests` (same treatment as `"System"`/`"Interface"`):
**File**: `SingleThreadTests/LocalizationTests.swift`

```swift
        // de/fr "Version" — same spelling in German and French
        ExclusionEntry(catalog: "Core", key: "Version %@"),
        // "AI" — standard computing acronym: ja/zh-Hans use "AI", de uses "KI"
        ExclusionEntry(catalog: "App", key: "AI")
```

#### 8. `FoundationModelsReminderRanker` (new, app target)
**File**: `SingleThread/FoundationModelsReminderRanker.swift`
**Action**: create. `nonisolated` because the app target defaults declarations to
`MainActor` while `AIReminderRanking` is a core (nonisolated) protocol — verified
by probe. Both the `#if canImport` and `#available` gates are required.

```swift
import Foundation
import SingleThreadCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// On-device ranking of reminders through Apple's Foundation Models framework.
/// The model exists only on iOS/macOS 26+, and only when Apple Intelligence is
/// enabled and ready; everywhere else `rank` throws and the store keeps the
/// deterministic `.priority` chain.
nonisolated struct FoundationModelsReminderRanker: AIReminderRanking {
    nonisolated func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, macOS 26.0, *),
                  SystemLanguageModel.default.availability == .available else {
                throw AIRankingError.unavailable
            }
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: Self.prompt(candidates: candidates, rules: rules),
                generating: RankedIdentifiers.self)
            return response.content.identifiers
        #else
            throw AIRankingError.unavailable
        #endif
    }

    /// Immutable identifier list + rule text; the model is never asked to
    /// re-read titles it can get wrong.
    nonisolated static func prompt(candidates: [AIReminderCandidate], rules: String) -> String {
        let list = candidates.map { candidate -> String in
            var parts = ["id: \(candidate.identifier)", "title: \(candidate.title)"]
            if let notes = candidate.notes, !notes.isEmpty { parts.append("notes: \(notes)") }
            if candidate.priority > 0 { parts.append("priority: \(candidate.priority)") }
            if let due = candidate.dueDate {
                parts.append("due: \(due.formatted(date: .abbreviated, time: .shortened))")
            }
            if let listTitle = candidate.listTitle { parts.append("list: \(listTitle)") }
            return "- " + parts.joined(separator: ", ")
        }.joined(separator: "\n")
        return """
        Sort these reminders. Rules: \(rules)
        Return every id exactly once, best first.

        \(list)
        """
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    nonisolated struct RankedIdentifiers {
        @Guide(description: "Reminder identifiers in ranked order, best first")
        var identifiers: [String]
    }
#endif
```

#### 9. `SettingsBindings.aiSortRules`
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify — computed store-backed property, exactly mirroring
`sortOption`; add the store beside `sortStore`.

```swift
    var aiSortRules: String {
        get {
            access(keyPath: \.aiSortRules)
            return aiRulesStore.load()
        }
        set {
            withMutation(keyPath: \.aiSortRules) {
                aiRulesStore.save(newValue)
            }
        }
    }
```

```swift
    private let sortStore = SortOptionStore()
    private let aiRulesStore = AISortRulesStore()
```

No `ContentView+Settings.swift` change: App-Group keys need no write-back
handler (unlike `@AppStorage` keys).

#### 10. `FilterSortSettingsView` rule box
**File**: `SingleThread/FilterSortSettingsView.swift`
**Action**: modify — new binding + conditional section. Kept to a
single controlled deviation from the "never hide a control" rule, scoped to the
`.ai` row (design decision 7).

```swift
struct FilterSortSettingsView: View {
    @Binding var sortOption: SortOption

    @Binding var aiSortRules: String

    @Binding var showUndatedReminders: Bool

    let availableLists: [String]

    @Binding var excludedLists: Set<String>

    var body: some View {
        Form {
            Picker(selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Sort By")
                    SettingsCaption(text: "Choose the order reminders appear in.")
                }
            }
            if sortOption == .ai {
                Section {
                    TextEditor(text: $aiSortRules)
                        .frame(minHeight: 88)
                        .accessibilityIdentifier("aiSortRulesEditor")
                } header: {
                    Text("AI Sort Rules")
                } footer: {
                    SettingsCaption(text: "Describe how reminders should be ordered. On-device AI applies these rules.")
                }
            }
            Toggle(isOn: $showUndatedReminders) { /* unchanged */ }
            Section { /* Excluded Lists — unchanged */ }
        }
        .navigationTitle("Filtering & Sorting")
        .settingsSubscreenLayout()
    }
}
```

Update the `#Preview` at the bottom of the file:
`aiSortRules: .constant("")` added after `sortOption:`.

#### 11. Pass the binding from the sheet
**File**: `SingleThread/SettingsView.swift`
**Action**: modify — `:96-100`.

```swift
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            aiSortRules: $bindings.aiSortRules,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            availableLists: availableLists,
                            excludedLists: $excludedLists)
```

#### 12. `AppViewModel` composition + triggers
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — the one place the real ranker is constructed and the
coordinator is hung off the existing change signals.

New stored properties:

```swift
    private let aiCoordinator: AISortCoordinator
    private var aiRulesObserver: NSObjectProtocol?
```

In `init`, immediately after `store.sortOption = SortOptionStore().load()`:

```swift
        aiCoordinator = AISortCoordinator(ranker: FoundationModelsReminderRanker())
        aiCoordinator.onRankingUpdated = { [weak store] ranking in
            store?.setAIRanking(ranking)
        }
```

Compose the AI refresh into the existing (iOS||macOS) reminder-changed hook —
`onRemindersChanged` fires on sort change, reload, skip (`applySkipSet`) and
excluded-list change, so it is the single re-rank trigger:

```swift
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = { [weak self] in
                WidgetCenter.shared.reloadAllTimelines()
                self?.refreshAIRanking()
                #if os(macOS)
                    Task { @MainActor in
                        await self?.scheduleNotificationsForMacOS()
                    }
                #endif
            }
        #endif
```

Rule-text edits must also trigger a re-rank. `AISortRulesStore` writes to the
App Group suite, which posts `UserDefaults.didChangeNotification` (the same
signal `PreferenceHolder` uses). Add unconditionally at the end of `init`:

```swift
        setupAIRankingObservation()
```

with:

```swift
    private func setupAIRankingObservation() {
        aiRulesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppGroup.defaults,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAIRanking()
                }
            }
    }

    /// Re-ranks the visible set whenever `.ai` is selected. Cheap to call on any
    /// App-Group write: the guard and the coordinator's input digest absorb the
    /// noise.
    private func refreshAIRanking() {
        guard store.sortOption == .ai else { return }
        aiCoordinator.update(rules: AISortRulesStore().load(), candidates: store.aiCandidates)
    }
```

No `deinit` change is needed — `NotificationCenter` drops the block observer when
the token is deallocated (same lifecycle as `syncDefaultsObserver`).

#### 13. SwiftLint: allow the `ai` identifier
**File**: `.swiftlint.yml`
**Action**: modify — `identifier_name` checks enum cases and the default minimum
is 3; `case ai` would be a strict-mode error. End state of the existing block:

```yaml
identifier_name:
  excluded:
    - id
    - e
    - d
    - rt
    - to
    - gvm
    - ai
```

#### 14. Tests
**Files**: `SingleThreadTests/AISortCoordinatorTests.swift` (create),
`SingleThreadTests/FoundationModelsReminderRankerTests.swift` (create),
`SingleThreadTests/AISortRulesStoreTests.swift` (create),
`SingleThreadTests/ReminderStoreTests.swift` (modify),
`SingleThreadTests/SortOptionTests.swift` (modify),
`SingleThreadTests/ReminderSkipTests.swift` (modify),
`SingleThreadTests/SettingsViewTests.swift` (modify).

`AISortCoordinatorTests.swift` — Swift Testing, `@MainActor struct`, fakes live
in the same file (no new test target):

```swift
/// Records calls and returns a canned order.
private final class CannedRanker: AIReminderRanking {
    func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] {
        Self.ranking
    }
}

private struct ThrowingRanker: AIReminderRanking {
    func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] {
        throw AIRankingError.unavailable
    }
}
```

- `ranksWithFakeRanker` — canned `["b", "a"]` over two candidates →
  `onRankingUpdated` receives `["b": 0, "a": 1]`.
- `retainsPreviousRankingWhenRankerThrows` — set a good ranking, then point the
  coordinator at `ThrowingRanker` (fresh coordinator with a mutable fake or a
  `SwitchableRanker`) and update: no second `onRankingUpdated` call.
- `skipsBlankRules` (added Phase 2), `fallsBackWhenRankerUnavailable` (Phase 2).

`FoundationModelsReminderRankerTests.swift`:
- `availabilityGateMatchesIsAvailable` —
  `#expect(FoundationModelsReminderRanker.isAvailable == (FoundationModelsReminderRanker.availability == .available))`.
  Deterministic under any host/CI (no model call).

`AISortRulesStoreTests.swift`:
- `loadsEmptyDefaultWhenMissing` — injected `UserDefaults.standard` + UUID key.
- `saveAndLoadRoundTrip` — `save("clients first")` → `load() == "clients first"`.
- `defaultsKeyIsAISortRules` — `AISortRulesStore.defaultsKey == "aiSortRules"`.

`ReminderStoreTests.swift` (harness:
`ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false, reminders:…, skippedIDs:…, excludedListTitles:…)`):
- `aiOptionUsesRankingThenPriorityChain` — three reminders with priorities
  1/5/9; `setSortOption(.ai)`; `setAIRanking(["low": 0, "high": 1])`; expect
  `["low", "high", "mid"]` (unranked `mid` falls through after ranked ones,
  then the `.priority` chain).
- `aiFallsBackToPriorityChainWithoutRanking` — `.ai` with empty `aiRanking`
  equals the `.priority` order (`setAIRanking([:])` leaves it empty).

`SortOptionTests.swift`:
- `rawValuesMatchPayloadKeys` add `#expect(SortOption.ai.rawValue == "ai")`.
- `allCasesCoverAllOptions` → `[.priority, .dueDate, .title, .ai]`.
- `presentationTitlesAreHumanReadable` add
  `#expect(SortOption.ai.title == String.en("AI", bundle: .main))`.
- `presentationSystemImagesAreValidSFSymbols` add
  `#expect(!SortOption.ai.systemImage.isEmpty)`.

`ReminderSkipTests.swift` (`struct ReminderSortTests`):
- `aiOptionMatchesPriorityChain` — for a priority/date/list fixture set,
  `ReminderSort.areInIncreasingOrder(l, r, using: .ai)` ordering equals
  `using: .priority` (reuse the helpers at `:268-278`).

`SettingsViewTests.swift`:
- Update the existing construction at `:191-196` with
  `aiSortRules: .constant("")`.
- `filterSortSettingsViewRendersAIRulesEditorWhenAISelected` —
  construct with `sortOption: .constant(.ai)`, `aiSortRules: .constant("clients first")`,
  and `#expect(bodyDescription.contains("AI Sort Rules"))`.

### Verification

#### Automated
- [x] `make format` (SwiftFormat may reorder the new declarations)
- [x] `xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -swift-version 6 -default-isolation MainActor -typecheck /tmp/fmprobe.swift` → exit 0 (re-run after the adapter lands)
- [x] `make build` — compiles the gated adapter for iOS and macOS
- [ ] `make mac-build` — compiles `SingleThread/` for macOS (the app target is shared) — **pre-existing local failure**: fails identically on `origin/main` (local Xcode 27 vs CI 26.6 divergence: entitlement profile error without flags, `SkipSyncSession` unresolved with Debug + `CODE_SIGNING_ALLOWED=NO`); CI mac-tests green — verified pre-existing, not caused by this phase
- [x] `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests` (iOS simulator)
- [x] `scripts/test-one.sh SingleThreadTests/FoundationModelsReminderRankerTests` (iOS simulator)
- [x] `scripts/test-one.sh SingleThreadTests/AISortRulesStoreTests` (iOS simulator)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` (iOS simulator; 36 cases)
- [x] `scripts/test-one.sh SingleThreadTests/SortOptionTests` (iOS simulator)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderSkipTests` — runs as `SingleThreadTests/ReminderSortTests` (the Swift Testing suite name inside `ReminderSkipTests.swift`; the filename selector matches zero cases) (iOS simulator; 12 cases)
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` (iOS simulator; 16 cases)
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` (iOS simulator; 5 cases)
- [x] `make lint` — clean (`defaultsKey`/`ai` cases included)

#### Manual
- [ ] Run the app on the current host (model `.available`); launch with
      `--seed '{"reminders":[{"title":"Client email","priority":1},{"title":"Buy milk","priority":9}]}'`;
      Settings → Filtering & Sorting → select **AI**; a rule box appears; type
      "clients first"; the list reorders on-device within a second.
- [ ] Switch to **Priority** → box hides; switch back to **AI** → the typed rule
      is still there; dismiss and reopen the sheet → still there.
- [ ] Relaunch the app → the rule text persists (App Group).

### Checkpoint
No later phase starts until the SDK integration compiles at the 17.0 floor and
the coordinator/ordering/store suites are green.

---

## Phase 2: Unsupported devices explain themselves and still work

### Changes

#### 1. Protocol-level availability + coordinator guards
**File**: `SingleThreadCore/Sources/SingleThreadCore/AIReminderRanking.swift`
**Action**: modify.

```swift
public extension AIReminderRanking {
    /// `false` when this device cannot rank at all. Defaults to `true` so fakes
    /// and other conformers need no change.
    var isAvailable: Bool { true }
}
```

Phase-2 `update` (replaces the Phase-1 body up to the task):

```swift
    public func update(rules: String, candidates: [AIReminderCandidate]) {
        let trimmed = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ranker.isAvailable else {
            // Blank rules or no ranking capability: clear any stale ranking so
            // the list settles on the `.priority` chain.
            pending?.cancel()
            pending = nil
            emit([:])
            return
        }
        pending?.cancel()
        pending = Task { [weak self, ranker] in /* unchanged from Phase 1 */ }
    }
```

#### 2. `FoundationModelsReminderRanker` availability surface
**File**: `SingleThread/FoundationModelsReminderRanker.swift`
**Action**: modify.

```swift
    enum Availability: Sendable, Equatable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    nonisolated static var availability: Availability {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return .available
                case let .unavailable(reason):
                    switch reason {
                    case .deviceNotEligible: return .deviceNotEligible
                    case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
                    case .modelNotReady: return .modelNotReady
                    @unknown default: return .modelNotReady
                    }
                @unknown default:
                    return .modelNotReady
                }
            }
            return .deviceNotEligible
        #else
            return .deviceNotEligible
        #endif
    }

    nonisolated static var isAvailable: Bool { availability == .available }

    nonisolated var isAvailable: Bool { Self.isAvailable }
```

`rank` keeps its own guard (defense in depth for a stale `isAvailable` read).

#### 3. Expose availability to the sheet
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify.

```swift
    /// `true` when this device can run the on-device ranker. Drives the
    /// Filter & Sort footer copy; not persisted.
    var isAIRankingAvailable: Bool {
        FoundationModelsReminderRanker.isAvailable
    }
```

#### 4. Conditional footer
**File**: `SingleThread/FilterSortSettingsView.swift`
**Action**: modify — new parameter + footer branch.

```swift
    let isAIRankingAvailable: Bool
    ...
                } footer: {
                    if isAIRankingAvailable {
                        SettingsCaption(text: "Describe how reminders should be ordered. On-device AI applies these rules.")
                    } else {
                        SettingsCaption(text: "Describe how reminders should be ordered. This device can't run on-device AI, so reminders stay in priority order.")
                    }
                }
```

Update the file's `#Preview` with `isAIRankingAvailable: false`.

#### 5. Pass through from the sheet
**File**: `SingleThread/SettingsView.swift`
**Action**: modify.

```swift
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            aiSortRules: $bindings.aiSortRules,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            isAIRankingAvailable: bindings.isAIRankingAvailable,
                            availableLists: availableLists,
                            excludedLists: $excludedLists)
```

#### 6. Tests
- `AISortCoordinatorTests` add:
  - `skipsBlankRules` — `update(rules: "   ", candidates: …)` emits `[:]` and
    never calls the ranker.
  - `fallsBackWhenRankerUnavailable` — an `UnavailableRanker` (`isAvailable`
    overridden to `false`, `rank` throws if called) emits `[:]`.
- `SettingsViewTests`:
  - Update the `:191-196` construction with `isAIRankingAvailable: false`.
  - `filterSortSettingsViewFooterExplainsUnavailableAI` — body description
    contains `"This device can't run on-device AI"`.
  - `filterSortSettingsViewHasNoAIEditorWhenAnotherOptionSelected` — with
    `.priority` selected, body description does **not** contain `"AI Sort Rules"`.
- `ReminderStoreTests.aiFallsBackToPriorityChainWithoutRanking` covers ordering
  fallback (already added in Phase 1).

### Verification

#### Automated
- [x] `make format`
- [ ] `make test` — macOS native, where the model is unavailable: exercises the
      exact CI path, including `FoundationModelsReminderRanker`'s macOS branch
      — **pre-existing local failure** (fails identically on `origin/main`,
      local Xcode 27 vs CI 26.6; see Phase 1 mac-build note); the macOS-only
      branch is covered by CI's mac-tests job, and the equivalent iOS-sim runs
      below compile and exercise the same core + adapter sources
- [x] `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests` (iOS simulator; 4 cases: incl. `skipsBlankRules`, `fallsBackWhenRankerUnavailable`)
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` (iOS simulator; 18 cases: incl. `filterSortSettingsViewFooterExplainsUnavailableAI`, `filterSortSettingsViewHasNoAIEditorWhenAnotherOptionSelected`)
- [x] `scripts/test-one.sh SingleThreadTests/FoundationModelsReminderRankerTests` (iOS simulator; `availabilityGateMatchesIsAvailable`)
- [x] `make lint`

> **Implementation note (deviation)**: the plan's extension-only `isAvailable`
> default cannot be overridden through the `any AIReminderRanking` the
> coordinator holds — Swift statically dispatches extension-only members and
> never sees a conformer's same-named member (the production adapter's override
> would be silently ignored too). Fixed by declaring `var isAvailable: Bool
> { get }` in the protocol as a required member with the extension supplying
> the `true` default (dynamic witness dispatch; fakes without the member still
> use the default). Verified with a standalone dispatch probe.

#### Manual
- [ ] Footer reads "This device can't run on-device AI…" whenever the host
      reports `availability != .available`; on the current host it reads the
      "On-device AI applies these rules." copy.
- [ ] With the model off, selecting **AI** leaves the list in priority order but
      the rule box still edits and persists.

---

## Phase 3: Async robustness — debounce, dedupe, retention, validation

### Changes

#### 1. Coordinator final shape
**File**: `SingleThreadCore/Sources/SingleThreadCore/AIReminderRanking.swift`
**Action**: modify — replace the class's stored properties and `update`; the
public initializer gains a debounce with a default so no call site changes.

```swift
    public init(ranker: any AIReminderRanking, debounce: Duration = .milliseconds(500)) {
        self.ranker = ranker
        self.debounce = debounce
    }
    ...
    public func update(rules: String, candidates: [AIReminderCandidate]) {
        let trimmed = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ranker.isAvailable else {
            pending?.cancel()
            pending = nil
            emit([:])
            return
        }
        let digest = Self.digest(rules: trimmed, candidates: candidates)
        if pending != nil, digest == lastDigest { return }
        lastDigest = digest
        generation += 1
        let requestedGeneration = generation
        let requestedCandidates = candidates
        let wait = debounce
        pending?.cancel()
        pending = Task { [weak self, ranker] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            do {
                let ranked = try await ranker.rank(requestedCandidates, rules: trimmed)
                guard let self, self.generation == requestedGeneration else { return }
                self.pending = nil
                self.emit(Self.reconcile(ranked, against: requestedCandidates))
            } catch {
                guard let self, self.generation == requestedGeneration else { return }
                self.pending = nil
                // Retain the previous ranking.
            }
        }
    }
    ...
    /// Drops invented identifiers, dedupes repeats, and appends omitted ones in
    /// the (identifier-sorted) candidate order. Exposed for direct unit testing.
    static func reconcile(
        _ ranked: [String],
        against candidates: [AIReminderCandidate]) -> [String: Int] {
        let known = Set(candidates.map(\.identifier))
        var ordered: [String] = []
        var seen: Set<String> = []
        for identifier in ranked where known.contains(identifier) && seen.insert(identifier).inserted {
            ordered.append(identifier)
        }
        for candidate in candidates where seen.insert(candidate.identifier).inserted {
            ordered.append(candidate.identifier)
        }
        var ranking: [String: Int] = [:]
        for (index, identifier) in ordered.enumerated() {
            ranking[identifier] = index
        }
        return ranking
    }

    /// In-memory-only fingerprint of the request inputs; stable because
    /// `aiCandidates` is identifier-sorted.
    static func digest(rules: String, candidates: [AIReminderCandidate]) -> Int {
        var hasher = Hasher()
        hasher.combine(rules)
        for candidate in candidates {
            hasher.combine(candidate.identifier)
        }
        return hasher.finalize()
    }
    ...
    private let ranker: any AIReminderRanking
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var lastDigest = 0
    private var generation = 0
```

`AIReminderCandidate`'s `Equatable` conformance (Phase 1) is currently only used
by `reconcile`'s candidate identity through `identifier`; keep it — it is part of
the public value type and used by tests.

Note: **no `ReminderStore` change is needed for this phase.** The re-rank trigger
is `onRemindersChanged`, which already fires from `setSortOption` (line 424),
`reload` (504), `setExcludedListTitles` (514), `refreshExcludedListTitles` (523),
and `applySkipSet` (634) — verified against the source; Phase 4 adds a test
locking that in for the `.ai` path.

#### 2. Tests
**File**: `SingleThreadTests/AISortCoordinatorTests.swift`
**Action**: modify — add fakes and cases.

```swift
/// Serves a canned order, counts calls, and can be switched to fail or block.
private actor RecordingRanker: AIReminderRanking {
    // rank returns `result` and increments `callCount`
}

/// Never returns until cancelled — proves debounce/dedupe without racing.
private struct NeverCompletingRanker: AIReminderRanking {
    func rank(_ candidates: [AIReminderCandidate], rules: String) async throws -> [String] {
        try await Task.sleep(for: .seconds(3600))
        return []
    }
}
```

Use `AISortCoordinator(ranker: ..., debounce: .milliseconds(20))` in tests that
exercise debounce; await a short `Task.sleep(for: .milliseconds(100))` before
asserting call counts (no polling helpers exist in this repo).

- `debouncesRapidEdits` — three `update` calls with different rules inside one
  debounce window produce exactly **one** ranker call.
- `skipsIdenticalInputs` — two synchronous identical `update` calls produce one
  ranker call.
- `retainsRankingOnError` — good ranking emitted; switch the fake to throwing;
  update with new rules; `onRankingUpdated` is not called again.
- `reconcilesUnknownAndMissingIds` — direct `reconcile` assertions: input
  `["ghost", "b", "b", "a"]` over candidates `[a, b, c]` → `["b": 0, "a": 1, "c": 2]`.
- `reranksWhenRemindersChange` — same rules, candidate set gains an id → a second
  ranker call (new digest) and the new ranking is emitted.
- `ignoresStaleGeneration` — a `NeverCompletingRanker` followed by a
  `CannedRanker` update: only the newer ranking is emitted (the cancelled task
  cannot overwrite it).

### Verification

#### Automated
- [x] `make format`
- [x] `scripts/test-one.sh SingleThreadTests/AISortCoordinatorTests` (iOS simulator; 11 cases: debounce, dedupe, error retention/recovery, reconcile, re-rank on change, stale-generation, cancel; `NeverCompletingRanker` used by `cancelsInFlightRequest` — the plan's intended dedupe-while-in-flight proof is covered by `skipsIdenticalInputs` with a counted fake, and stale-generation by a `BlockOnceRanker` that blocks only the first call, since the coordinator's ranker is a `let` and cannot be swapped mid-test)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` (iOS simulator; 36 cases)
- [x] `make lint`

#### Manual
- [ ] Type a long rule quickly: the list updates once, ~0.5 s after the last
      keystroke, and never flashes into an unordered state.
- [ ] Force a ranker failure (temporarily point `AppViewModel` at a throwing
      test ranker or disable the model): the list keeps its previous order.
- [ ] Skip a reminder and toggle an excluded list while **AI** is selected: the
      list re-ranks.

---

## Phase 4: Cross-surface parity, seams, and hardening

### Changes

#### 1. Seed reset covers the new key
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify — `persistedKeys` currently contains `"sortOption"`; add the
literal beside it (the array is literal-based, so a literal keeps the style).

```swift
        "showUndatedReminders",
        "sortOption",
        "aiSortRules",
        "completionCount",
```

#### 2. No production watch/widget source change
**Files**: `SingleThreadWatch/*`, `SingleThreadWidget/*`
**Action**: none — verify only. `.ai` arrives as `rawValue "ai"`; `ReminderSort`
handles it and no ranking exists off-iOS, so watch and widget order by the
`.priority` chain. `SkippedReminderSyncService` decodes via
`SortOption(rawValue:)`, which covers the new case without edit.

#### 3. Tests
**Files**: `SingleThreadTests/UITestingSeedTests.swift` (modify),
`SingleThreadTests/SkippedReminderSyncServiceTests.swift` (modify),
`SingleThreadWatchTests/WatchSyncPipelineTests.swift` (modify).

- `UITestingSeedTests.resetsAISortRules` — write `AISortRulesStore().save("x")`,
  call `UITestingSeed.resetPersistedState()`, expect `load() == ""` (and the
  same for `UserDefaults.standard` with an injected key).
- `SkippedReminderSyncServiceTests.sortOptionAITravelsAsRawValue` —
  `sortStore.save(.ai)`; `pushAll()`; `#expect(context["sortOption"] as? String == "ai")`.
  Receive side: `service.session(WCSession.default, didReceiveApplicationContext: ["sortOption": "ai"])`;
  `#expect(sortStore.load() == .ai)`.
- `WatchSyncPipelineTests.aiSortOptionOrdersByPriorityChain` — watch store
  seeded with two reminders; `store.setSortOption(.ai)`; assert `visibleReminders`
  order equals the `.priority` chain (mirrors the existing `:40` context test).

#### 4. Accessibility hardening
**File**: `SingleThread/FilterSortSettingsView.swift`
**Action**: modify only if the audit flags it. The editor already carries
`.accessibilityIdentifier("aiSortRulesEditor")`; if the local audit reports a
hit-region failure on the picker row, add `.padding` to the label as per the
AGENTS.md caption-padding rule, and `.accessibilityLabel("AI sort rules")` on
the editor.

**No new UI test is added.** Design decision 9 and AGENTS.md's UI-test policy:
CI cannot produce an AI ranking, the conditional row and persistence are
covered at the `SettingsViewTests` / `AISortRulesStore` level, and reaching the
settings sheet in the UI-test target would require a new end-to-end flow that
buys no coverage the unit suites lack. The PR must state this justification.

### Verification

#### Automated
- [x] `make format`
- [x] `make lint` (SkippedReminderSyncServiceTests needed `// swiftlint:disable file_length` + `// swiftlint:disable:this type_body_length` — same treatment as `ReminderStoreTests.swift`)
- [x] `scripts/test-one.sh SingleThreadTests/UITestingSeedTests` (iOS simulator; 21 cases incl. `resetsAISortRules`)
- [x] `scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests` (iOS simulator; 36 cases; the `.ai` round-trip case lives in the sibling suite `SingleThreadTests/AISortOptionTravelTests` — moving it out kept the main struct under the `type_body_length` bound; 1 case, verified separately)
- [x] `make watch-test` (watch simulator; 54 cases incl. `WatchSyncPipelineTests/aiSortOptionOrdersByPriorityChain`)
- [ ] Full CI-identical gate ONCE, via the `run-gate` skill (async gate
      subagent, managed worktree, multi-hour timeout) — never `nohup` it ad-hoc
      → **launched by the parent after the phases commit**
- [x] `git rm DELETEME` before merge (branch bootstrap marker) — removed in the
      session's setup commit (rebase prerequisite); no DELETEME remains

#### Manual
- [ ] Run a seeded UI session with `--seed` and select **AI**: the option
      persists, the editor accepts text, and the list orders by priority.
- [ ] Pair a watch (or run the watch simulator): selecting **AI** on the phone
      leaves the watch list in priority order and does not disturb the sync
      payload beyond `"sortOption": "ai"`.
- [ ] Accessibility Inspector pass over the Filter & Sort sheet: the editor has
      a label, the picker row keeps its trait, Dynamic Type at the largest
      setting does not clip the footer.

---

## Cross-phase notes

- **Order of edits inside Phase 1 matters for compilation**: `SortOption.ai`
  (step 1) breaks the two exhaustive switches until steps 4 and 6 land, and
  breaks every `FilterSortSettingsView(...)` call site until steps 10–11 and the
  test/preview call sites are updated. Do them in the listed order.
- **Deviations from `structure.md`**:
  1. Added a localization-catalog step (4 keys, six languages) plus an `"AI"`
     exclusion in `LocalizationTests` — `structure.md` did not mention it, but
     every app string is catalogued and `LocalizationTests` fails on a key with
     missing locales.
  2. Added `.swiftlint.yml` (`ai` added to `identifier_name.excluded`) — `case ai`
     is a strict-mode warning otherwise.
  3. Added `ReminderStore.filteredReminders` + `aiCandidates` (the ranker needs
     a stable, ranking-independent candidate list; `structure.md` only listed
     `setAIRanking`).
  4. Phase 3 lists `ReminderStore.swift` but needs **no** edit — the existing
     `onRemindersChanged` firings already cover skip/exclusion/sort/reload; the
     plan verifies rather than duplicating the trigger.
  5. Phase 4 drops the "a11y audit for the `.ai` sheet row" UI test in favour of
     unit coverage + a manual inspector pass, per design decision 9 and the
     AGENTS.md UI-test policy.
  6. Phase 3 lists `AppViewModel.swift` ("call `update` from every relevant
     hook") but needs **no** further edit: Phase 1 wires the single
     `onRemindersChanged` trigger plus the App-Group rules observer, which
     together cover sort change, reload, skip, excluded-list change, and rule
     edits. Phase 3 changes only the coordinator's internals.
- **Verification floor**: per AGENTS.md, phase subagents verify with a build plus
  targeted `-only-testing:` suites; the full `./scripts/test.sh` runs once after
  the phases commit, via the `run-gate` skill.
