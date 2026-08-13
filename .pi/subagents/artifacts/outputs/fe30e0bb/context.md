# Q5: Dates & Timestamps — Code Context

## Files Retrieved
1. `SingleThread/Item.swift` (lines 7-21) — defines the `Item` `@Model` with its single `Date` property and initializer.
2. `SingleThread/ContentView.swift` (lines 18-22, 47-52) — all timestamp display and creation logic.
3. `SingleThread/SingleThreadApp.swift` (lines 11-21) — SwiftData model container wiring (no date logic).
4. `SingleThreadTests/SingleThreadTests.swift` (lines 1-14) — empty placeholder test; no date assertions.

## Key Code

`SingleThread/Item.swift`:
```swift
@Model
final class Item {
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
    var timestamp: Date
}
```
- Line 9: `@Model` macro (SwiftData).
- Line 15-17: initializer takes and stores a `Date`.
- Line 21: single stored property `var timestamp: Date`.

`SingleThread/ContentView.swift`:
```swift
Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))   // line 21
...
let newItem = Item(timestamp: Date())   // line 51
```
- Line 19: detail screen `Text` formats the same timestamp.
- Line 21: list row label formats the timestamp.

## Architecture / Data Flow

- **Storage**: The timestamp is persisted via SwiftData as a `Date` property on `Item` (`Item.swift:21`). The model container is configured `isStoredInMemoryOnly: false` (`SingleThreadApp.swift:13`), so the `Date` is stored on disk in the default SwiftData store.
- **Creation**: `ContentView.addItem()` (`ContentView.swift:47-53`) constructs `Item(timestamp: Date())` at line 51 — capturing the current wall-clock instant at the moment of creation — then inserts it into `modelContext`.
- **Formatting/Display**: The timestamp is rendered in two places using SwiftUI's `Text(_:format:)` initializer with `Date.FormatStyle(date: .numeric, time: .standard)`:
  - Navigation detail: `ContentView.swift:19`
  - List row label: `ContentView.swift:21`
  Both use `.numeric` date + `.standard` time. No locale/timezone is specified, so formatting inherits the device/process default locale and time zone.
- **Sorting/ordering**: There is NO explicit `@Query` sort descriptor. `@Query private var items: [Item]` (`ContentView.swift:46`) uses default ordering, so items are not sorted by `timestamp`.

## Date/Time API Usage Inventory

| API | Location | Purpose |
| --- | --- | --- |
| `Date` (stored property) | `Item.swift:21` | persist timestamp |
| `Date()` (init) | `ContentView.swift:51` | capture creation time |
| `Date.FormatStyle(date: .numeric, time: .standard)` | `ContentView.swift:19`, `ContentView.swift:21` | display formatting |

**Not present anywhere in the app source:**
- No `DateFormatter` usage.
- No `Calendar` / `Calendar.current` usage.
- No `TimeInterval`, `DateComponents`, or relative-date logic (`RelativeDateTimeFormatter`, `Text(..., style: .relative)`, etc.).
- No date comparison, filtering, scheduling, or time-based logic.
- No time-zone or locale overrides.
- No timestamp references in tests (`SingleThreadTests.swift` is an empty placeholder).

## Start Here
Open `SingleThread/ContentView.swift` (lines 18-22 and 47-53) first — it contains the only functional date logic (creation + display). Then `SingleThread/Item.swift` (lines 7-21) for the persisted `Date` property.

## Open Questions / Notes
- The `@Query` (`ContentView.swift:46`) has no sort, so the timestamp currently has no behavioral role other than being stored and displayed.
- The timestamp display is locale/timezone-dependent (default device settings) since no explicit locale/timezone is passed to `Date.FormatStyle`.
