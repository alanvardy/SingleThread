# Q6: Unit Tests & SwiftUI Previews Structure

## Testing Frameworks

- **Unit tests** use **Swift Testing** (`import Testing`, `@Test`), not XCTest.
  - `SingleThreadTests/SingleThreadTests.swift:8` — `import Testing`
  - `SingleThreadTests/SingleThreadTests.swift:10-15` — `struct SingleThreadTests { @Test func example() { ... } }` (single placeholder test, empty body).
- **UI tests** use **XCTest** (`import XCTest`, `XCTestCase`).
  - `SingleThreadUITests/SingleThreadUITests.swift:8` — `import XCTest`
  - `SingleThreadUITests/SingleThreadUITests.swift:10` — `final class SingleThreadUITests: XCTestCase`
  - `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift:8` — `import XCTest`
  - `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift:10` — `final class SingleThreadUITestsLaunchTests: XCTestCase`

This split (Swift Testing for unit, XCTest for UI) matches `AGENTS.md`: "Unit tests use Swift Testing ... UI tests still use XCTest."

## SwiftData Model Container Provisioning

### In tests
- **Unit tests** (`SingleThreadTests/SingleThreadTests.swift`) do **not** currently instantiate or provide any `ModelContainer`. The single `example()` test is empty (no `@Model` setup, no `.modelContainer(...)` call).
- `AGENTS.md` states the intended convention: "Previews and tests that need a container use `.modelContainer(for: Item.self, inMemory: true)`." — no actual test currently exercises it.
- **UI tests** do not set up a model container; they launch the full app (`XCUIApplication().launch()`), which uses the app's real `sharedModelContainer`:
  - `SingleThreadUITests/SingleThreadUITests.swift:27-31` — `testExample()` launches app.
  - `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift:27-31` — `testLaunch()` launches app.

### In previews
- The single `#Preview` block is in `SingleThread/ContentView.swift:81-83`:
  ```swift
  #Preview {
      ContentView()
          .modelContainer(for: Item.self, inMemory: true)
  }
  ```
  It provides an in-memory SwiftData container via `.modelContainer(for: Item.self, inMemory: true)`.

### In the app (for contrast)
- `SingleThread/SingleThreadApp.swift:10-21` builds the real (on-disk) `sharedModelContainer`:
  ```swift
  var sharedModelContainer: ModelContainer = {
      let schema = Schema([Item.self])
      let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
      do { return try ModelContainer(for: schema, configurations: [modelConfiguration]) }
      catch { fatalError("Could not create ModelContainer: \(error)") }
  }()
  ```
- `SingleThread/SingleThreadApp.swift:26-30` injects it via `.modelContainer(sharedModelContainer)` on the `WindowGroup`.
- `SingleThread/Item.swift:10-21` defines the `@Model final class Item` (single `timestamp: Date` property).

## Test Invocation / Wiring

- `Makefile:8-9` — `test` target runs `xcodebuild test ... -only-testing:SingleThreadTests` (unit tests only; UI tests not run by `make test`).
- `scripts/test.sh:23-26` — CI runs unit tests via `xcodebuild test ... -only-testing:SingleThreadTests`, after formatting, lint, and build.

## Files Retrieved
1. `SingleThreadTests/SingleThreadTests.swift` (lines 1-16) — Swift Testing framework, empty placeholder test, no container.
2. `SingleThreadUITests/SingleThreadUITests.swift` (lines 1-42) — XCTest framework, launches app.
3. `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift` (lines 1-37) — XCTest launch/screenshot test.
4. `SingleThread/ContentView.swift` (lines 81-83) — only `#Preview`, provides in-memory container.
5. `SingleThread/SingleThreadApp.swift` (lines 10-30) — real `ModelContainer` and injection.
6. `SingleThread/Item.swift` (lines 10-21) — `@Model` type.
7. `Makefile` (lines 8-9) — `test` target (unit only).
8. `scripts/test.sh` (lines 23-26) — CI unit test invocation.