# Q1: SwiftData Persistence Layer End-to-End

## Files Retrieved
1. `SingleThread/Item.swift` (lines 8-22) - the single `@Model` definition.
2. `SingleThread/SingleThreadApp.swift` (lines 10-32) - app entry point and `ModelContainer` setup.
3. `SingleThread/ContentView.swift` (lines 8-85) - main view reading/displaying records via `@Query`.

## Key Code

### `SingleThread/Item.swift` — the `@Model`
- `import Foundation` (line 7), `import SwiftData` (line 8)
- `@Model` macro applied to the class at line 11.
- `final class Item` (line 12).
- Initializer `init(timestamp: Date)` (lines 15-17), assigns `self.timestamp = timestamp` (line 16).
- Single persisted property: `var timestamp: Date` (line 22).

```swift
@Model
final class Item {
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
    var timestamp: Date
}
```

### `SingleThread/SingleThreadApp.swift` — container setup
- `import SwiftData` (line 7), `import SwiftUI` (line 8).
- `@main struct SingleThreadApp: App` (lines 10-11).
- `sharedModelContainer` property (line 13):
  - `let schema = Schema([Item.self])` (lines 14-16).
  - `ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)` (line 17) — on-disk persistence.
  - `try ModelContainer(for: schema, configurations: [modelConfiguration])` (line 20).
  - `catch { fatalError("Could not create ModelContainer: \(error)") }` (lines 21-22).
- Injected into the scene graph via `.modelContainer(sharedModelContainer)` on `WindowGroup` (line 30).

```swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema([Item.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
```

### `SingleThread/ContentView.swift` — reading/displaying via `@Query`
- `import SwiftData` (line 7), `import SwiftUI` (line 8).
- `@Environment(\.modelContext) private var modelContext` (line 46) — gives write/delete access.
- `@Query private var items: [Item]` (line 47) — auto-populated fetch of all `Item` records (no sort/filter predicate; default ordering).
- Display: `List { ForEach(items) { item in ... } }` (lines 16-20); each row is a `NavigationLink` showing `item.timestamp` formatted via `Date.FormatStyle(date: .numeric, time: .standard)` (lines 17-20).
- `.onDelete(perform: deleteItems)` (line 22) wires swipe-to-delete.
- Writes:
  - `addItem()` (lines 49-54): creates `Item(timestamp: Date())` (line 51) and `modelContext.insert(newItem)` (line 52), wrapped in `withAnimation`.
  - `deleteItems(offsets:)` (lines 56-62): iterates offsets and `modelContext.delete(items[index])` (line 59), wrapped in `withAnimation`.
- `#Preview` uses `.modelContainer(for: Item.self, inMemory: true)` (lines 82-84).

## Architecture

Single-direction data flow, standard SwiftData:

1. **Schema definition** — `Item` (`@Model`, `final`) declares one persisted `Date` property `timestamp`.
2. **Container construction** — `SingleThreadApp` builds a `Schema` from `Item.self` and a non-memory `ModelConfiguration`, then creates a `ModelContainer` (on-disk). It is stored as a stored property and attached to the root `WindowGroup` via `.modelContainer(_:)`.
3. **Model context propagation** — the `.modelContainer` modifier injects a `ModelContext` into the environment; `ContentView` retrieves it via `@Environment(\.modelContext)`.
4. **Read path** — `@Query private var items: [Item]` drives the `List`; the query automatically reflects insertions/deletions with no manual save (SwiftData autosaves the main-actor context).
5. **Write path** — `addItem` inserts via `modelContext.insert`; `deleteItems` removes via `modelContext.delete`.

Cross-platform note: `ContentView` uses `NavigationViewWrapper` (lines 65-80) — `NavigationSplitView` on macOS, passthrough otherwise. Toolbar is conditional on `#if os(iOS)` for `EditButton` (lines 25-29).

## Start Here

Open `SingleThread/SingleThreadApp.swift` first — it is the single place where the schema and container are wired, and it links `Item.swift` (schema) to `ContentView.swift` (query/display).

## Constraints / Notes

- Only one `@Model` (`Item`) and one `@Query` exist in the entire `SingleThread/` source tree (confirmed by grep).
- No unit/UI test file references `@Model`, `@Query`, or `modelContainer` (grep returned no matches in `SingleThreadTests/` and `SingleThreadUITests/`).
- The `@Query` has no `SortDescriptor` or `#Predicate`; ordering is the store's default.