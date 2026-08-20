# Task

Lower the iOS app's minimum compatible iPhone OS version from its current
deployment target (iOS 26.x, per the "26.5" Xcode 26 numbering everywhere in
the project) down to iOS 18.7, **without removing, gating, or degrading any
existing features**. The open question is whether this is achievable purely by
adjusting deployment-target configuration, or whether the codebase already
depends on iOS features unavailable below 18.7 that would force a feature
cut (or OS-version gating) to make the lower floor work.