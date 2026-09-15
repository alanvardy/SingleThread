# Research Questions

## Context

This repo declares minimum-OS floors in two places: the SPM package manifest
for the shared model package, and per-target deployment-target build settings
in the Xcode project file. Certain language/library features used across the
iOS, watchOS, and macOS source trees (`@Observable` macro, EventKit
authorization APIs) are only available on recent OS versions, and the project
enables compiler warnings for unguarded calls to newer APIs. The build/test
infrastructure pins simulators and caches build indexes (DerivedData,
Periphery) that can go stale when version settings change. Distribution
metadata (release notes, store listing, docs) may state OS requirements.

Answer each question about what EXISTS and how it works today. Do not suggest
improvements or propose solutions.

## Questions

1. [project.pbxproj deployment targets] Enumerate every
   `IPHONEOS_DEPLOYMENT_TARGET`, `WATCHOS_DEPLOYMENT_TARGET`, and
   `MACOSX_DEPLOYMENT_TARGET` setting in the Xcode project file: exact value
   of each occurrence, which target (project, app, test, watch, widget) and
   which build configuration (Debug/Release) it belongs to, and the line
   number. Then look for OTHER build settings in the same file that imply or
   constrain a minimum OS version (e.g. `SDKROOT`, supported-platforms
   settings, version literals inside `CLANG_WARN_UNGUARDED_AVAILABILITY`
   regions, `#available`-related flags, or any setting that embeds an OS
   version number) and report those too.

2. [SPM package platform declarations] Describe the `platforms` block(s) in
   every Swift Package Manager manifest in the repo (at minimum
   `SingleThreadCore/Package.swift`; check for others, e.g. watch or widget
   packages): which platform each package declares, the exact minimum
   versions, and how the versions are grouped/structured. Also report how the
   consuming app targets' deployment-target settings relate to the package's
   declared platform versions (i.e. what the build would do if an app target's
   minimum were lower than a dependency package's declared minimum).

3. [@Observable macro floor] Trace the `@Observable` macro: which library or
   framework provides it (the import/module name), where that dependency is
   declared (package manifest, system framework, toolchain), and its declared
   minimum platform support if visible in the repo or local toolchain files.
   Then list every `@Observable` use site across the four source trees
   (SingleThread/, SingleThreadCore/, SingleThreadWatch/, SingleThreadWidget/)
   with file:line references, and note which source files also use other
   macros/attributes from the same library (e.g. `@Observable`-adjacent
   symbols) that could share the same floor.

4. [EventKit authorization APIs] Trace the EventKit authorization flow:
   where `requestFullAccessToReminders()` and
   `EKAuthorizationStatus.fullAccess` are defined and used (file:line for
   `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
   `EventKitStoring.swift`, `InMemoryEventStore.swift`, and the app-side
   consumers in SingleThread/). Identify which framework provides these
   symbols (EventKit? a system framework?), how the code conditions on
   authorization status, and whether the local SDK/toolchain headers (look
   under the installed platforms/SDK if feasible within budget) annotate the
   availability or minimum-OS-introduction of `requestFullAccessToReminders`.

5. [OS-version-dependent code patterns] Survey the code for patterns that
   handle OS-version capability differences: uses of the
   `CLANG_WARN_UNGUARDED_AVAILABILITY` project setting; any `#available`,
   runtime version checks, `if #available` guards, Swift-level feature or
   library-version conditionals; any code paths (UI, animations, backgrounds,
   overlays) that touch recent OS visual/effect features; and any comments or
   constants naming OS versions. Report file:line references for each pattern
   found and summarize which parts of the codebase would compile or behave
   differently across OS versions the compiler can see.

6. [Distribution metadata and CI/test infrastructure] Find where the project
   states OS requirements for distribution: release notes or changelog, docs
   (docs/), store metadata or export options, any "requires"/"minimum"
   phrasing outside the build config. Then describe the CI/test
   infrastructure that would touch or be affected by version-setting changes:
   the CI runner and simulator-runtime pinning in .github/workflows/ci.yml,
   the simulator destination pinning mechanics (SIM= / .simulator_id), the
   Makefile/scripts/test.sh handling of DerivedData and the Periphery index,
   and any documented gotchas about stale build indexes after branch or
   setting changes.