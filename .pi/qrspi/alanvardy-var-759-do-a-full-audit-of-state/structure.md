# Structure Outline

## Approach

A read-only state audit: the report is the work product and no app-code change
lands in this ticket (decision #1). The horizontal generalization of
schema→store→service→transport→UI is **fact base → inventory → cluster analysis →
enum advisory → severity ranking**. The bottom "schema" is a
citation-verified source index — every `file:line` the report cites is pinned to
its exact source text and machine-checked — and each layer's "test gate" is a
verifier/invariant checker over the audit artifacts, not `./scripts/test.sh`
(which stays green because nothing in the app changes). A later stage may cite
only what an earlier stage proved.

---

## Stage 1: Fact base — citation-verified source index (bottom layer)

Delivers the ground truth every other layer cites: one row per
declaration/read/write of every state value across all four targets, each pinned
to `file:line` + exact source text. Green when the verifier reproduces every
pinned line byte-for-byte.

**Files**: `.pi/qrspi/<branch>/audit/factbase.tsv`, `audit/verify-citations.sh`

**Key changes**:
```swift
enum Target { ios, watchOS, widget, core }
enum Role { declaration, read, write, dualRead, hook, seam, wcPayload }

struct FactEntry {
  id: String        // stable logical key, e.g. "sortOption", "completionCount"
  target: Target
  node: Role
  file: String      // repo-relative path
  line: Int
  lineText: String  // exact source text at that line — pinned for the verifier
}
// verify-citations.sh: for each row, `sed -n '<line>p' <file>` must equal lineText
```

**Tests** (`verify-citations.sh`):
- Every entry's pinned `lineText` matches the file at `line` (exit 0 = no drift).
- Triplet invariant: each `id` has ≥1 declaration + ≥1 read + ≥1 write; all 23
  production keys present (12 `.standard` + 11 App Group).
- Sad path: deliberately corrupt one `lineText`, confirm the verifier exits
  non-zero — proves the gate catches drift, not just passes trivially.

**Verify**: `bash audit/verify-citations.sh` exits 0 before any later stage
cites a fact.

---

## Stage 2: Inventory — key-centric and store-mirror cross-reference

Joins the fact base into per-key tables (default, encoding, read/write sites,
dual-read paths, targets) and a store-mirror table (which `@Observable` property
mirrors which persisted key; transient vs mirrored). This is the report's
"inventory" requirement.

**Files**: `audit/inventory.md`

**Key changes**:
```swift
enum Suite { standard, appGroup }
enum Encoding { rawString, rawBool, objectAsBool, int, stringArray, dict }

struct InventoryRow {
  key: String; suite: Suite
  encoding: Encoding
  default: String            // + how "absent" is encoded (registerDefaults vs
                             //   ?? fallback vs object(forKey:) as? Bool)
  decl: FactEntryRef; reads: [FactEntryRef]; writes: [FactEntryRef]
  targets: Set<Target>; dualReadPath: Bool
}

struct StoreMirror {
  store: String; property: String
  mirrorsKey: String?           // persisted key, or nil if transient
  kind: persisted | transient | computed
}
```

**Tests**:
- Completeness: 23 keys reproduced, split 12 `.standard` / 11 App Group.
- Every `file:line` in `inventory.md` is a subset of `factbase.tsv` (cite-check).
- Dual-read-path set equals research Q1's verified list
  (`enableActionButtons`, `notificationsEnabled`, `notificationIntervalHours`,
  `allowsLandscape`, `appearanceMode`, the 7 `show*` keys) — no more, no fewer.
- Store table matches Q2: no `ObservableObject` exists; every store is
  `@Observable final class` except `WatchAppViewModel`/`ResumptionGate` (plain
  classes) and the widget (no view model).

**Verify**: cite-check passes; `bash audit/verify-citations.sh` still 0.

---

## Stage 3: Combinatorial clusters + cross-target divergence analysis

For each of the four flag clusters (completion-transition, empty/all-done/first-card
branch ordering, entitlement gate, dictation) and the App Group-vs-`.standard`
divergence sites: a state-space table marking every combination
reachable / unreachable / contradiction, and what renders under each.

**Files**: `audit/clusters.md`

**Key changes**:
```swift
enum Reachability { reachable(path), unreachable(proven), undefined(openArea) }

struct ClusterMatrix {
  cluster: ClusterId   // completionTransition | branchOrder | entitlementGate | dictation
  rows: [{ vector: StateVector, reachability: Reachability, renders: String }]
}
struct DivergenceSite { site: FactEntryRef; which: String }  // 11 sites from Q5
```

**Tests**:
- Every `reachable` combo's `path` triple resolves in the fact base.
- Every `unreachable(proven)` claim: grep the fact base for any write that could
  set that vector → none (e.g. `allSkipped` requires non-empty `reminders`, so
  `empty ∧ allSkipped` is impossible).
- All four matrices + 11 divergence sites carry `file:line` from Stage 2.
- Open areas (group-registered watch untestable, second `EntitlementStore`,
  `--ui-testing-live-excluded` 5 s push, phone possibly receiving non-`pushAll`
  contexts) are marked `undefined`, never asserted.

**Verify**: every cell in every matrix is annotated and cited; contradictions
traceable to a real path (design's "correctness" clause).

---

## Stage 4: Enum assessment — advisory pointers + top-candidate sketches

Enumerate every bare-Bool/Int cluster, produce concrete enum sketches **only**
for the three top candidates (completion-transition, entitlement gate, branch
ordering), and label the rest advisory with `file:line` pointers (decision #3).

**Files**: `audit/enums.md`

**Key changes**:
```swift
struct EnumSketch {
  name: String
  cases: [String]                 // sketch, not full spec
  replaces: [FactEntryRef]        // bare fields this enum would subsume,
                                  // e.g. isShowingCompletionTransition +
                                  //      transitionReminder? → .completing(EKReminder)
  persistence: rawValueRoundTrip + fallback  // SortOption.swift:34-39 pattern
  presentation: onEnum | inExtension        // Core enum → extension, per Patterns
}
```

**Tests**:
- Each sketch's `replaces` fields resolve in the fact base (real fields only).
- Both patterns adhered to: `rawValue` round-trip with `else return .default`
  guard; presentation in an extension for Core-owned types, on the enum for
  app-target types.
- Scope discipline: sketches exist for exactly the three named clusters; the
  rest are advisory pointers, not full enums.

**Verify**: pointer-resolve check passes; sketch list is bounded to three.

---

## Stage 5: Severity ranking + prioritized action list (top layer)

Ranks every finding into the four tiers, assembles the prioritized action list
that `/5_plan` consumes, and links the layer files into the assembled report.

**Files**: `audit/findings.md`, `audit/index.md`

**Key changes**:
```swift
enum Tier { t1_reachableContradiction, t2_crossTargetDivergence,
            t3_dualReadPath, t4_hygiene }

struct Finding { id: String; tier: Tier; title: String;
                 evidence: [FactEntryRef]; action: String }
```

**Tests**:
- Ordering invariant: data-loss/divergence findings outrank hygiene — no tier-2
  item above a tier-1 item, etc.
- Every finding cites ≥1 fact-base entry; every Stage-3 cluster has a finding.
- Action list names the deferred tickets (constant for `100`, the two doc drifts
  at `AppGroup.swift:2-4` and `AppViewModel.swift:211`, the sync-contract spike,
  the group-registered-watch harness) — flagged as *future* tickets, not in-scope
  work (decision #1; "What We're NOT Doing").
- `index.md` links all four layer artifacts as the assembled report.

**Verify**: ordering check + citation check; `bash audit/verify-citations.sh`
still 0; the four verification clauses from the design's "Verification" line all hold.

---

## Testing Checkpoints

Resume short-circuits, one per stage — each gate must be green before advancing:

1. `bash audit/verify-citations.sh` → 0 (fact base pinned, no drift), self-test shows a corruption is caught.
2. Inventory cite-check: `inventory.md` ⊆ `factbase.tsv`; 23-key split and dual-read list exact.
3. Cluster matrices fully annotated (no bare `undefined` except listed open areas); divergences cited.
4. Three sketches only; `replaces` resolves; patterns adhered to.
5. Tier ordering (contradiction > divergence > dual-read > hygiene); action list maps to deferred tickets.

Note: `./scripts/test.sh` is *not* the gate here — the app is untouched by design;
the verifier above is the audit's test suite, and it (plus its self-test) lives
under `.pi/qrspi/<branch>/audit/`, not in `SingleThreadTests/`.