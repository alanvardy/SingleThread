## Review — Architecture, API design, maintainability, documentation

**Verdict: no blockers, no fix-now items.** The change is architecturally sound and consistent with existing patterns. Optional notes follow; nothing here should gate merge.

### (a) RescheduleSheet doc comment — accurate (no change needed)
`SingleThread/RescheduleSheet.swift:4-7` still describes the sheet correctly: both callers wrap it in a `NavigationStack` with a Cancel toolbar item (`SingleThread/ContentView+iOS.swift:60-74` nudge sheet; `SingleThread/ContentView+ActionMenu.swift:167-180` action-menu sheet), and it renders the nudge message, the tailored picker, and the confirm button. The layout/style changes (inline label, full-width prominent button) don't contradict any statement in the comment. **Optional:** line 7 could mention the confirm button renders full-width bordered-prominent, since that is now part of the sheet's contract, but the comment isn't wrong without it.

### (b) Static helper API — well-factored, no issues
- `hasDueTime(_ reminder: EKReminder?) -> Bool` (`RescheduleSheet.swift:59-61`) cleanly contains the nil-handling at the boundary (`guard let … else { return false }`), and `displayedComponents`/`dateComponentsMask` (`:63-68`) are pure pure-Bool→component mappings. The asymmetry (one takes the reminder, two take the derived Bool) is deliberate and correct: nil-safety lives in one place, the mappings are trivially testable. Tests cover all branches including nil (`RescheduleSheetTests.swift:30-50`).
- No stringly-typed API; both return typed component sets. The risk that `displayedComponents` and `dateComponentsMask` could drift (picker showing `hour` while write-back omits it) is already pinned by `writeBackMaskFollowsDueTime` and `timedReminderPicksDateAndTime` (`RescheduleSheetTests.swift:41-50`).
- The helpers are internal (no access modifier) and exercised from `SingleThreadTests` via the `@testable import SingleThread` seam — the repo-standard pattern; not a leak.

### (c) `.borderedProminent` vs the shared `SingleThreadButtonModifier` — intentional and consistent
The divergence is correct, not a drift:
- `SingleThreadButtonModifier.swift:4-8` explicitly scopes itself to **icon-only** chrome suppression (`.borderless` for `controlPlate` controls). The Reschedule confirm is a labeled primary action; routing it through `singleThreadButton()` would strip its plate.
- `.buttonStyle(.borderedProminent)` is already the established primary-action idiom in this codebase: `ReminderCardView.swift:164` (nudge banner), `:212` (Dismiss), `PurchaseSettingsView.swift:113` (purchase CTA). The RescheduleSheet change aligns with that pattern.
- The new test pins the invariant both ways (`RescheduleSheetTests.swift:94-99`), and its "stable token" claim checks out: `SwipePromptTests.swift:52`.
**Optional (report-only):** "prominent primary action" is now encoded ad hoc in four files (RescheduleSheet, ReminderCardView ×2, PurchaseSettingsView) with differing `.tint`/padding, so a shared modifier isn't warranted — no action.

### (d) `rescheduleConfirmButton` identifier vs the watch — no interaction
- The watch's copy at `SingleThreadWatch/WatchReminderView.swift:311` is in a separate binary; accessibility identifiers are process-local, so sharing the string is benign (and arguably good — consistent cross-platform test hooks).
- Verified no UI tests reference the identifier on either side: zero hits for `reschedule*` in `SingleThreadUITests/` or `SingleThreadWatchUITests/`, and the iOS identifier existed pre-change (the diff only relocated it). The renamed picker identifier `rescheduleDatePicker` (`RescheduleSheet.swift:33`) likewise has no referrers. Nothing to update.

### (e) Access control, force-unwraps, localization
- No force-unwraps in the diff; the only conditional is `guard let` (`RescheduleSheet.swift:60`). Module boundary respected — the change stays in the iOS app target; the separate watch `actionMenuRescheduleSheet` duplication is pre-existing and not touched by this PR.
- **No new user-facing strings.** "Reschedule to" and "Reschedule" both pre-existed in the source and in `SingleThread/Resources/Localizable.xcstrings` (`:2054` and `:2013`). The label was merely relocated from the `DatePicker` header into a sibling `Text` — extraction is unaffected. Nothing to localize.
- New test names follow the Swift Testing convention (no `test`/`testing` prefixes) and the repo's `describing:` string-snapshot style; **optional note:** `rescheduleSheetPutsLabelBesidePicker`'s `contains("HStack<")` token is coarse (it would match any HStack anywhere in the sheet), but combined with the `DatePicker<EmptyView` and literal-label assertions it discriminates the intended structure, and it pins the no-duplicate-label regression the comment calls out (`RescheduleSheetTests.swift:61`).

### Merge verdict: OK

No blockers, no fix-now findings from the architecture/API/maintainability/documentation angle.