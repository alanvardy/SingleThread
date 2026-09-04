# Task — iPhone Lock Screen widget + Control Center controls

Surface SingleThread's next reminder and quick actions where the user already is: add a
WidgetKit Lock Screen widget (accessoryInline / accessoryRectangular / accessoryCircular
variants showing the "next thing") and Control Center controls (`ControlWidgetButton` for
one-tap Complete / Skip) to the existing `SingleThreadWidget` bundle. The controls reuse the
existing `CompleteReminderIntent` / `SkipReminderIntent`, write through the same App Group
paths the existing widget intents use, and ideally expose a stateful "has next / all done"
status. Deployment target (iOS 18.7) supports both. Ships with unit tests for any new
presentation state and, where automatable, UI tests driven through the `--seed` in-memory
store seam; Control Center is known to be hard to drive from XCUITest, so intent-level unit
coverage is an acceptable fallback if stated in the PR.