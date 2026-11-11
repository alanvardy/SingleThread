# Research Questions

## Context
This survey covers the App Store screenshot capture pipeline under `scripts/`,
the app-side display-layout detection (including code that may live on other
branches), the launch-argument / persisted-defaults seams that drive app state
during automated runs, the wallpaper slot and manifest system, and the physical
device install/launch tooling. It also covers how shell scripts in this repo are
syntax-checked, linted, and tested.

## Questions
1. How does `scripts/appstore-screenshots.sh` currently work end to end: how are
   device classes, screen slots, appearance, languages, output-tree layout, and
   pixel-dimension verification defined and invoked? Trace the flow with
   `file:line` references.
2. Where does the app detect the foldable iPhone Duo outer display and adjust
   layout, and how does it fail safe on non-Duo hardware? Note whether that code
   is present on the current branch or only on other branches/refs, with
   `file:line` (or commit/branch) references.
3. What launch-argument and persisted-`UserDefaults` seams exist for priming app
   state during automated runs (content seeds, appearance, language, orientation,
   settings), and how does the screenshot script use them today?
4. How are wallpaper slots and the wallpaper manifest defined, fetched, staged
   into the app container, and referenced per class and per screen?
5. What shell-script syntax/lint/test infrastructure exists in the repo, and how
   are the screenshot script's dimension checks and other bash scripts validated?
6. How does `scripts/run-devices.sh` discover and drive physical iOS devices via
   `devicectl` (build destination, install, launch, fixtures/tests), and what
   simulator-vs-physical distinctions does it encode?
