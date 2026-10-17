# Done

- **What was built**: The Settings > Reminders row now uses the `checklist` SF Symbol instead of `bell.badge`, so it is visually distinct from the Notifications row (which remains `bell.badge`). The matching `SettingsCaptionTests` fixture was updated.
- **Commit SHA(s)**: `f762d298`
- **Verification**: `make format` and `make lint` clean (0 violations); `make build` → `** TEST BUILD SUCCEEDED **`; focused `SingleThreadTests/SettingsCaptionTests` suite → 3/3 cases passed.
- **Reviewer findings**: No blockers. One nit: the working-tree `DELETEME` deletion is unrelated and was left out of this commit.
- **Remaining manual items**: Confirm the `DELETEME` removal is committed before merge (branch hygiene); visual check of the new icon on device/simulator if desired.
