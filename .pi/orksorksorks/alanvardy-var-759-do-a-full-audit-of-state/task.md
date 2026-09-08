# Task

Perform a full audit of the state held by the SingleThread app across all its
targets (iOS app, watchOS app, widget extension, shared core package). The
audit must inventory every mutable and persisted variable, identify any
contradictory or erroneous state combinations the app can get into, and assess
where multi-way state could be modeled as enums so that invalid states are not
representable. The output informs a refactor aimed at making state
representations safer; the audit itself is the immediate work product.