# Code Context — ContentView List Interface (Q2)

## Files Retrieved
1. `SingleThread/ContentView.swift` (lines 1-84) — the entire list interface: body, NavigationViewWrapper, toolbar, row rendering, add/delete helpers.
2. `SingleThread/Item.swift` (lines 13-22) — the `@Model` type backing each row; single property `timestamp: Date`.
3. `SingleThread/SingleThreadApp.swift` (lines 12-27) — model container wiring (provides `Item` schema to `@Query`/`@Environment(\.modelContext)`).

## Key Code

### ContentView body — list construction (`SingleThread/ContentView.swift:14-42`)
```swift
var body: some View {
    NavigationViewWrapper {
        List {
            ForEach(items) { item in
                NavigationLink {
                    Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                } label: {
                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                }
            }
            .onDelete(perform: deleteItems)
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        #endif
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            #endif
            ToolbarItem {
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
    }
}
```

### NavigationViewWrapper abstraction (`SingleThread/ContentView.swift:65-79`)
```swift
private struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                content()
            } detail: {
                Text("Select an item")
            }
        #else
            content()
        #endif
    }
}
```

### Data model (`SingleThread/Item.swift:13-22`)
```swift
@Model
final class Item {
    init(timestamp: Date) {
        self.timestamp = timestamp
    }

    var timestamp: Date
}
```

### State / data sources (`SingleThread/ContentView.swift:44-63`)
```swift
@Environment(\.modelContext) private var modelContext
@Query private var items: [Item]

private func addItem() {
    withAnimation {
        let newItem = Item(timestamp: Date())
        modelContext.insert(newItem)
    }
}

private func deleteItems(offsets: IndexSet) {
    withAnimation {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}
```

## Architecture

- `ContentView` is a plain `struct` `View` (default `@MainActor` isolation per project settings).
- It draws its data via `@Query private var items: [Item]` (line 47), a SwiftData query over the `Item` model.
- The `body` wraps everything in `NavigationViewWrapper` (line 15), a cross-platform abstraction:
  - On **macOS** it produces a `NavigationSplitView` with the list in the sidebar and a static `Text("Select an item")` detail placeholder (lines 70-74).
  - On **iOS/visionOS** (`#else` branch) it returns `content()` unchanged (line 76), so the `List` is embedded directly in whatever navigation container hosts `ContentView` (there is no enclosing `NavigationStack`/`NavigationView` inside `ContentView` itself; `SingleThreadApp` hosts it via `WindowGroup` at `SingleThreadApp.swift:23-25`).
- Row rendering (lines 18-22): each item is a `NavigationLink`. Its label (and destination) both render the same string — `Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))`. The destination is a `Text` showing `"Item at <formatted timestamp>"`.
- **Information shown per row:** only the item's `timestamp`, formatted with numeric date + standard time. No title, notes, or other fields are displayed (the `Item` model has only `timestamp`, so there is nothing else to show).
- Toolbar (lines 29-40): on iOS only, an `EditButton` in `.navigationBarTrailing` placement (lines 30-34) enables the swipe-to-delete/`.onDelete` editing mode; on all platforms a plus `Label("Add Item", systemImage: "plus")` button (lines 35-39) calls `addItem`.
- macOS-specific layout: `.navigationSplitViewColumnWidth(min: 180, ideal: 200)` (lines 26-28).
- Add/delete mutate `modelContext` inside `withAnimation` (lines 49-62).

## Start Here
Open `SingleThread/ContentView.swift` first — it contains the entire list interface in a single file, including the `NavigationViewWrapper` abstraction, toolbar, and row rendering. `SingleThread/Item.swift` is the only data model and confirms the single `timestamp` field shown per row.
