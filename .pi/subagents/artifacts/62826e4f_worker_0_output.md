# Q4: SwiftUI State & Observation

## Observed object

- `ReminderStore` is a `final class` annotated with `@Observable` and `@MainActor` — `ReminderStore.swift:37-39`. It uses the **Observation framework** (`import Observation`, `ReminderStore.swift:9`), not the older `ObservableObject`/`@Published` Combine pattern.
- Its observable state consists of two `private(set) var` properties: `accessStatus` (`ReminderStore.swift:44`) and `reminders: [EKReminder]` (`ReminderStore.swift:45`). Both are only mutated inside the class, which is what the Observation macro instruments.
- `eventStore` is an immutable `let EKEventStore()` (`ReminderStore.swift:42`), so it is not observation-tracked state.
- `accessStatus` is typed as the app's own `ReminderAccessStatus` enum (`ReminderStore.swift:16-35`), which wraps `EKAuthorizationStatus` (its `init(_:)` at `ReminderStore.swift:23-34`).

## Injection

- The app's single source of truth is owned by the `App` struct: `@State private var reminderStore = ReminderStore()` (`SingleThreadApp.swift:23`).
- It is injected into the environment at the `WindowGroup` level via `.environment(reminderStore)` (`SingleThreadApp.swift:18`).
- `ContentView` retrieves it with the Observation-style environment lookup: `@Environment(ReminderStore.self) private var reminderStore` (`ContentView.swift:32`).
- The SwiftUI `#Preview` independently injects a fresh instance the same way: `.environment(ReminderStore())` (`ContentView.swift:117`).

## What triggers re-render

- Because `ReminderStore` is `@Observable`, SwiftUI tracks which stored properties are read while `body` evaluates. Two reads establish the view's dependencies:
  - `reminderStore.accessStatus` in the `switch` (`ContentView.swift:55`)
  - `reminderStore.reminders` in the computed `visibleReminders` (`ContentView.swift:38`)
- When `load()` mutates those tracked properties — setting `accessStatus` (`ReminderStore.swift:57`) and `reminders` (`ReminderStore.swift:59` when denied, `ReminderStore.swift:67` when authorized) — the Observation machinery invalidates the dependent views, causing re-render.
- `visibleReminders` is a **computed** property (not stored state) derived fresh from `reminderStore.reminders` each render (`ContentView.swift:35-51`).
- The store's state changes are initiated from two lifecycle hooks on `ContentView`:
  - `.task { await reminderStore.load() }` on first appearance (`ContentView.swift:18-20`)
  - `.onChange(of: scenePhase)` re-loading when the app returns to `.active` (`ContentView.swift:21-27`)
- `ReminderStore` is `@MainActor` (`ReminderStore.swift:37`), so all its mutations occur on the main actor where SwiftUI rendering happens. (Project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` reinforces this default — `project.pbxproj:425,470`.)

## Patterns observed

- State/observation follows the modern `@Observable` + `@Environment(Type.self)` + `@State` ownership model, with the store instantiated once at the app root and passed down through the environment.
- The view derives its display list (`visibleReminders`) at render time rather than storing a filtered copy, so filtering/sorting recompute whenever the tracked `reminders` array changes.