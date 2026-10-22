<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 07: ownership-analysis

Subsystem: `foreign/idr/lib/Analysis/Ownership/` (Borrows, Captures,
Exclusivity, ExclusivityAnalyses, ExclusivityGraph, Reuses, Uses, Values),
`foreign/idr/include/idr/Analysis/Ownership.h`,
`foreign/idr/include/idr/Analysis/Ownership/ExclusivityDetail.h`.

Status: complete (2026-10-21), at e96bb991.

## 1. Reading notes

Notes written while reading, in reading order. "→" marks what it means
for this subsystem.

**Skill (`.claude/skills/representation-first/SKILL.md`).** Map onto
MLIR's grain: `DataFlowSolver` for dataflow, `AnalysisManager` for
cached analyses, effects declared in ODS (a hand `getEffects` is a
declaration not yet made), shared shape is an interface not an `isa`
ladder or a C++ concept. "A switch on a tag is a polymorphism not yet
named"; "parse at the boundary, once"; delete what the representation
makes dead in the same change; the limit (Brooks): essential cases stay
distinct. → Every finding below is a state made unrepresentable, a check
moved to a boundary, a branch deleted, or an essential case named.

**AGENTS.md.** Acceptance is a property of the program; "two of
constructs outside the language's memory model, each on a total
analysis: a reference knot counting could never free, and a library's
in-place promise exclusivity cannot meet". Every refusal's rule carries
its category in ODS. Budgets never reject. A linear binder does not
imply unique heap ownership. No fact in a discardable attribute.
→ Exclusivity's refusal (`InPlace`) must stay total on admitted
programs; the analysis is load-bearing for a refusal, so its precision
under any redesign (per-function summaries) is a correctness question,
not only a speed one.

**§2 (brief).** `Ownership/Borrows` is listed "still on upstream's
dataflow framework". Exclusivity is "three files: the solve, the
analyses, the graph". Counting is `idr-rc-cells`, `idr-rc-stack`,
`idr-rc-grades`, `idr-rc-exclusive` (lane 08).

**§3 (walls).** ffa91113: exclusivity on `DataFlowSolver`, 627 GB ("a
lattice per value, an `Executable` per program point, a predecessor
state per function, nested maps, uniqued program points"). e96bb991:
building exclusivity's own graph did not finish ("an interface query
per pair of terminator and region successor, quadratic in a match's
case count"). b8301ebe: rc-stack, a candidate bit vector per value
copied along every edge (lane 08's, but its marking design is shared
with exclusivity). Conjecture there: framework failed on state model.

**§5.1 mlir-analysis.**
- A1/A2/A4: per-anchor inner `DenseMap` + per-state `SetVector`
  dependents, both 64-bucket minimum; ~2.9 KB per one-bit state at the
  pin; P1 (SmallDenseMap/SetVector small mode) ~0.2 KB; P2 flat map +
  typed arenas ~0.15 KB; our own BitVector bit 0.13 B. → measures what
  exclusivity's framework version cost (H2: 627 GB ≈ 200 M states).
- A3/A6: one knob (`interprocedural`); per-function scope is supported
  (top = function; calls go to `visitExternalCall`), nothing between
  function and module; no summaries. → Borrows can be a per-function
  solve; exclusivity's interprocedural part (Calls, Crossings) needs a
  summary layer.
- A7: `DeadCodeAnalysis` + `SparseConstantPropagation` must load beside
  every sparse analysis (`loadBaselineAnalyses`). → Borrows pays the
  baseline (check).
- C1/C2/C4: per-edge interface methods O(1); `getPredecessors`,
  `getSuccessorOperandInputMapping()` (no source), `isRepetitiveRegion`,
  `insideMutuallyExclusiveRegions` O(N) per call; enumerate edges once
  per op. → e96bb991 is this lesson; check every interface query in
  ExclusivityGraph/Borrows/Reuses.
- C3: the framework's region-branch join is a recomputation over all N
  terminators per visit; O(N²) worst case per op.
- G3: ownership-based deallocation fixes a function-boundary ABI instead
  of solving across calls; per-block state; residual runtime checks.
  → model for a per-function exclusivity with a boundary contract.
- H2: patched framework cuts fixed cost ~15×, leaves the lattices' own
  contents (set-valued dense lattice per point is the essential cost).
- 5.1.2 item 2: `Ownership/Borrows` should be a per-function sparse
  solve reading summaries via `visitExternalCall`/`visitCallableOperation`.
  Item 3: "what stays ours, honestly": exclusivity's graph, rc-stack's
  inference, frames, the label solve, SCC summaries.
- Design 1 (patched framework, per function, our summary layer),
  Design 3 (solver layer: dense per-function numbering, BitVector,
  edge table once per op, concept-constrained lattices, actions).
  Rejected 4: a general framework of our own.
- Owner questions QA1 (U1 first; P1 or P2), QA2 (per-function +
  summaries vs whole program), QA3 (remove-dead-values), QA4 (one state
  representation for all our solvers). Wave-2 questions W1 (V, B, P, F),
  W2 (each analysis's lattice, interprocedural, summaries, Design 1 or
  3), W3 (every O(N) interface query), W4 (`RecursiveMemoryEffects`),
  W5 (attributes created on hot paths), W6 (function anchoring),
  W7 (backward callee resolution in a non-interprocedural solve).

**§5.2 mlir-ods.**
- A9: the transform dialect models consumption as `Read` + `Free` on
  `TransformMappingResource` attached to the `OpOperand`; production as
  `Allocate` + `Write` on the result; `transform-check-uses` reads those
  effects; `InferEffects` writes a per-argument consumed/read-only
  summary that the call op's `getEffects` reads by symbol lookup.
  → this is exactly what Uses.cpp's "consumed / borrowed" classification
  and Borrows' read-only-argument summary compute by hand.
- A5: an op's effects are all ODS or all hand.
- A6: `wouldOpBeTriviallyDead` deletes an unused op whose effects are
  all `Read`; `Free` keeps it. → a consuming op (drop) stays; a borrow
  is deletable.
- M2: `Lin` and consumption match A9 exactly; effect derived from the
  type by one trait (row 3). Row 2: `Idr_Consumed<T>` = `Arg<T,
  "consumed", [MemRead<Heap>, MemFree<Heap>]>`, `Idr_Borrowed<T>` =
  `[MemRead<Heap>]`.
- Q2 (effects that follow from types: a trait vs op splits).

**§5.3 llvm.**
- B3/I3: a `get_if`/`holds_alternative` chain is the ladder; one
  exhaustive `std::visit` (or `makeVisitor`) compiles-errors on a missed
  case. B4/I4: a sum over handles is a `PointerUnion` (8 bytes, keeps
  `isa`). → `Ownership.h` holds several variants (check each).
- B5/I5: a hot callback is a template; cold traversal keeps
  `function_ref`. → Uses.cpp/Borrows.cpp callbacks (check).
- B7/I7: `DenseMap`/`DenseSet` allocates ≥64 buckets on first insert;
  per-node maps are the wall; state in a vector indexed by a dense
  number. MLIR numbers blocks (`Block::getBlockID`) but not ops or
  values. → every per-node map in this subsystem is a finding.
- B8/I6: write `GraphTraits`, get `scc_iterator`, `post_order`, dom
  trees. → exclusivity's graph should specialise `GraphTraits`.
- C2/C7: SCCP stores no dependents, reads users off use lists, one flat
  map; MemorySSA is a representation, not a solve. M7: "Exclusivity
  marks the program graph … dependents read off a graph's edges, a mark
  per node, the answer a value" = SCCP's shape found by hand; S1 makes
  it one generic mechanism (`Graph` CSR, `Solution<A>`, `mark(graph,
  seeds)` BitVector BFS: "Exclusivity's and idr-rc-stack's markings
  become calls").
- S0: before S1 is given an analysis, ask whether the dialect could
  carry the answer (a type, a token, an op) so no pass solves for it.
  → grades in types (`!idr.q`) are S0 for linearity; exclusivity's
  "exclusive" answer could be an `excl` permission in the type (check
  how `idr-rc-exclusive` consumes it, lane 08).
- M9/Q-llvm-2: an analysis a refusal rests on has no budget (finite
  height or widening). → Exclusivity's refusal: check for caps.
- Q-llvm-3: dense numbering as an invariant (per solve, cached
  analysis, or an upstream patch numbering ops/values).
- Wave-2 asks: every worklist, per-node DenseMap, function_ref,
  variant; "Exclusivity's graph, idr-rc-stack's flow graph and the
  label solve's graph: their node and edge representations, and whether
  one CSR `Graph` type with `GraphTraits` serves all three".

**§5.4 modular.**
- F2/1: Modular runs no `DataFlowSolver`; keeps upstream lattice values,
  folders, effects interface; per-problem engines.
- F6/Design 3: IPDF's `RegionState`, rows only at writing ops, shared
  pointers; "Counting, stack-cell inference and exclusivity keep state
  per program point; this representation is a candidate for all three"
  (incl. borrows).
- F7/Design 4: `CFGAnalysis`: successors per terminator, predecessors
  inverted in one pass; "one query per terminator, never a query per
  pair of terminator and successor" → e96bb991's fix, check whether
  ExclusivityGraph now does exactly this.
- F15: Mojo's `CheckLifetimes` (borrow checker, destructor insertion):
  three-tier state (whole-program immutable, per-thread cache,
  per-function numbered values with bit ranges per field), driver
  `failableParallelForEach`; loops converge on a lattice whose bits only
  fall ("a measure, not a count"). → the closest industrial analogue of
  Borrows + Exclusivity as a per-function solve.
- Design 1 (`SCCGraph` port, callees-first/callers-first, concept
  `SummaryProblem`), Design 2 (per-function three-tier driver).
- Wave-2: "Where state is copied per region or per edge (the b8301ebe
  shape), and which per-point solvers design 3 fits"; "How predecessors
  of region successors are computed today in each client of
  `RegionBranchOpInterface`".

**§5.5 cxx26.**
- D1 (the boundary rule): over ops, dispatch is MLIR's (interface,
  trait, rooted pattern); below the dispatch, typed code; over our own
  C++ types, closed sums and templates. A concept may *read* ODS
  (`OpT::hasTrait<>()` is constexpr) but never list ops.
- D2: `std::variant` + one fold `match`; `holds_alternative`/`get_if`
  banned outside `match`. Finding 12: `std::visit` cliff above 11
  alternatives.
- D3: `Id<Tag>` minted only by the graph, `IndexVector<IdT, T>` with
  `operator[](uint32_t) = delete("index by the graph's Id")`; concept
  `Lattice` (`join` → `mlir::ChangeResult`), `FlowGraph`; `solveForward`
  with a template transfer; one `extern template` per solver. The sketch
  names `ExclGraph` and `Excl` explicitly as an instantiation.
- D4c: a product of facts joins field by field with a structured
  binding pack.
- D8: `std::expected<T, Reason>` when the failure is data the caller
  branches on (a refusal's category generated from ODS).

**§5.6 ecosystem.**
- B5: CIRCT moved Arc's `LegalizeStateUpdate` off `DataFlowSolver`
  (130 s → <200 ms): nodes only for interesting ops, two node kinds in
  arenas, propagation up the region tree, callables re-queued when
  argument accesses change. "It is the move our ffa91113 made for
  exclusivity."
- Item 1 / Design 2 / W-E2: "a solver's domain is the values whose
  *type leaves its question open*, read off the type … an `excl` value
  is exclusive"; the filter is a type interface method (`ValueFacts`).
  → check whether exclusivity's graph excludes values whose grade
  already answers (lin, excl, scalars).
- Item 3: summaries over the SCC DAG in a typed table, never in
  attributes; recursion is essential, terminates by finite lattices.
- Item 5: an analysis a refusal rests on (knots, the in-place promise)
  has no budget. → exclusivity carries the in-place refusal.
- Item 6 / Shape G: extract, solve, write back; extractor per function
  in parallel, writer in the same order (no Value→node map). "The
  problems that are not per-value dataflow (… exclusivity's program
  graph …) fit this form."
- Item 8 / W-E8 / W-E9: structured walk with per-case deltas (undo log,
  `ScopedHashTable`) instead of copying per branch.
- D5: IREE's `TiedOpInterface` declares in-place results by interface
  over one attribute; "rather than hardcoded op names". → reuse/update
  ops (`Update` interface, §2).
- D6: IREE writes the analysis answer into the type (resource
  lifetime); regrets the lossy mapping: the type should hold the
  answer's own bits.
- W-E1…W-E9 for wave 2 (W-E2, W-E4, W-E5, W-E6, W-E7, W-E9 bear here).

**§5.7 library.**
- C2: PLV problems; SSI (Split, Info, Link, Version); σ-functions and
  parallel copies split live ranges so the fact becomes per-name;
  relational facts are not PLV. C3: backward analysis is an equation
  system only under static single use. C4: liveness under strict SSA
  needs no fixpoint (liveness check). C5: in nested regions, dominance
  is the region tree.
- M1: "The 627 GB wall is a dense formulation of a sparse problem … the
  facts that change at such points ('after here v is consumed', 'after
  here v is shared') are exactly the ones a representation can turn into
  definitions … Then exclusivity, borrows, stack lifetimes and reuse
  become per-value lattices"; quantity 1 gives SSU for linear values.
- M3: e96bb991 is "validation repeated where a parse belongs"; query the
  interface once per op, keep the CSR.
- M7: compose by product lattice (mutual) or frozen read (one-way); a
  non-monotone question ("unique everywhere") is the complement of a
  monotone one ("shared somewhere") read after the freeze. → exactly
  exclusivity's shape (marking "shared" and reading the complement).
- M9: number a scope's values in walk order; pre-order intervals give
  "a encloses b" in two compares.
- **L1** (SSI by representation): "an op that changes what may be done
  with a reference (consume, share, borrow, give, take, enter a linear
  scope) defines a new SSA value for the new state … a match's case
  region binds the refined scrutinee as a block argument … Then each
  analysis's fact is a lattice per value, and no analysis keeps a fact
  per program point." Deletes "program-point state in exclusivity,
  borrows and stack lifetimes; any analysis that recovers 'consumed
  here' by scanning forward from a point." Essential, kept distinct:
  relational facts (may alias) stay relations (L4).
- L2: one scoped sparse solver core: `Scope` (ops in pre-order, `end[]`,
  values in walk order, `uses` CSR, `flow` CSR one query per op,
  callees); `SparseAnalysis` concept; `solve<As...>` over a product;
  summaries per function, waves of SCCs. Deletes "the whole-program
  `DataFlowSolver` uses in ownership analyses … exclusivity's own graph".
- QL1 (scoped array view as solver input), QL2 (SSI as a dialect rule),
  QL3 (rules vs transfer functions), QL4 (byte-identical output).
- Wave-2: for every analysis: PLV, PVP or relational; forward or
  backward; which keep a fact per program point and whether that point
  is an ownership change the IR could make a definition; which share a
  product solve.
- Notes for rc: "Borrow inference per parameter is a
  partitioned-variable problem whose interprocedural form is a
  per-function summary (D4)."

**§5.8 dialect-design.**
- T1: the type is the only per-value carrier every pass keeps. T2: a
  qualifier is an attribute with an interface (`mayDuplicate`,
  `mayDiscard`, `isUnique`, `join`, `canRegradeTo`). T4: illegal grade
  pairs unrepresentable. T5: "Lifetimes are regions first … A borrow
  whose scope is a region needs no lifetime in its type: a local
  verifier on the region's terminator stops it escaping". T6: a
  function type carries conventions and effects.
- O3: "A regrade is a cast whose result type is computed … Forwarding is
  a category: an op that carries an operand into a result declares
  which, once, in an interface; projections forward only non-consuming
  grades; consuming an aggregate is one destructuring op." → Values.cpp
  and Uses.cpp's forwarding knowledge.
- EF3: consumption is `Read` + `Free` on the operand; "consumed exactly
  once on every path" is a pass, not an op verifier (B10).
- C4: `FunctionalStyleTransformOpTrait` declares "consumes every
  operand" once; a consuming op is never trivially dead.
- D1/D2 (SIL OSSA): ownership kind per value (`None`, `Owned`,
  `Guaranteed`, `Unowned`); each operand a kind constraint + a
  lifetime-ending bit; forwarding is a category; "owned values can never
  be partially consumed"; `begin_cow_mutation` makes a new SSA value.
- DS1.1 graded type `!idr.g<T, #grade>`; DS4 mapping rows: `lin.enter,
  lin.use, own.adopt, own.give, share, borrow` → one regrade cast,
  `borrow` as a region op if T5 holds; `take, unpack` → one consuming
  destructure; `SameValue, TakesReference, BuildsValue, CarriesOperand,
  ResultCarriesOperand` → "one forwarding interface declared in ODS";
  `ConsumesOperands, ConsumesOnly, Lin` → `MemFree<Idr_Linear>`.
- DD-Q1 (grades on trivially copyable types), DD-Q6 (borrows: regions or
  lifetimes in types; bears on rc-Q1), DD-Q7 (own function op).
- Wave-2: "Which (quantity, permission) pairs occur, what the lifetime
  parameter holds, and who reads each"; "How the grade verifier runs
  … whether it follows def-use chains"; "Where … `ConsumesOperands` …
  are read, mapped to the effect queries that would replace them".

**§5.9 mlton.**
- B3: one generic abstract interpreter per domain, each reachable block
  visited once, one constraint per binding/argument/return/case arm; the
  fixpoint lives in the abstract values.
- B4: two-point cells are union-find nodes with handler lists; each cell
  rises once, each handler runs once; O(constraints), no worklist, no
  count.
- B5: abstract value's shape is the type's; field facts per constructor;
  first-order values share one cell per type. "The analysis state is
  sized by the program's *types and constructors*, plus one cell per
  variable of a type that can carry what is being tracked."
- F7: liveness per function, one variable at a time; bit-vector
  liveness "infeasible".
- G2: state on the node, typed, dies with the pass; one fact per name,
  never per program point; facts written into types.
- H table: ffa91113 → "no: there is no program-point object … ffa91113's
  'marks the program graph' is MLton's model"; e96bb991 → MLton's case
  is a vector of labels.
- M2: "The three fixes already made (ffa91113 'marks the program graph',
  b8301ebe …, 16005000 …) are each a step towards MLton's model, taken
  one analysis at a time."
- Design 1 (constraint-generating abstract interpreter, cells in arenas
  indexed densely, state sized by types; "Deletes (if wave 2 confirms):
  the separate solvers in `Analysis/Ownership` (Exclusivity's solve,
  Uses, Values, Captures, Reuses)"). Design 2 (case as terminator after
  defunc). Design 4 (liveness per variable).
- Q-O1, Q-O2 (the model: constraint-generating abstract interpreter as
  *the* solver layer), Q-O3 (facts into types). Q-W2 for every analysis
  in `lib/Analysis/Ownership`: "is its state per value, per program
  point, per (terminator, successor), per type or per constructor; is
  it flow-sensitive because it must be, or because the framework made
  it so; could it be a domain of Design 1". Q-W6 (counting's liveness).

**§5.10 rc.**
- A1/A2: Perceus is three syntax-directed per-function passes, no
  solver; Parc walks in reverse with the live set as state.
- A4/A5: drop-guided reuse runs *after* Parc (size-keyed token map,
  intersected at joins), frame-limited; algorithm K (reuse at branch
  head while live) and D (Lean's reset past last use) are fragile or not
  frame-limited.
- A6: Koka's borrow inference flag is dead; borrowing declared.
- B2: Lean's borrow inference: monotone per SCC; thirteen `OwnReason`s,
  split forced (correctness) vs heuristic; terminates by monotonicity.
- B3: "derived borrows" (a value projected from a borrowed value is
  borrowed) = OSSA's guaranteed projection.
- C1: OSSA ownership kinds; lifetime-ending bit per operand.
- G1/G2: linearity restricts the future, uniqueness guarantees the
  past; Idris quantity 1 is the future promise only.
- M2: "If `Uses` and `Values` compute liveness or use counts that
  `idr-rc-cells` then reads, that is a rederivation chain."
- M3: grades are OSSA kinds; consuming traits are the lifetime-ending
  bit.
- M4/M5: exclusivity is "a forward property from allocation sites,
  killed by the first `dup` or ω binding: a two-point lattice per node,
  which only ever goes from exclusive to shared".
- M6: "`idr-rc-exclusive` linear by construction, if its graph has one
  node per parameter, result and value-flow edge, and each node is
  marked at most once … Three markings, one honest solver layer."
- M7: `Reuses` before or after dup/drop insertion? M8: "`Captures` may
  vanish under defunctionalization".
- R1: per-function Perceus, signatures in types, one solver for the
  three markings, `is_unique` folding on an exclusive type. Would
  delete "`Uses` and `Values` as inputs to insertion; `Reuses` as an
  analysis (it becomes the rewrite); possibly `Captures`; `Borrows` off
  `DataFlowSolver` into the solver layer or out entirely (Q1)".
- rc-Q1 (borrow inference), rc-Q2 (how much exclusivity is static).
  Wave-2 W1 (who inserts dup/drop; Uses/Values as inputs), W2 (Reuses
  before or after; by constructor or size; token across a call), W4
  (exclusive graph after e96bb991: nodes per value or per parameter,
  marked once, peak), W7 (each ownership op against the field's).

**§5.11 oom.** A1: each solver's header states its state's size in
program units; "a state sized by a product of two program quantities
is a wall waiting to be met". "The passes acceptance rests on … cannot
be budgeted at all: their memory must be bounded by construction" →
exclusivity (in-place refusal) is one. Wave-2 item 7: every solver
whose state is a product of two program quantities.

**§8 (owner questions bearing here).** QA1–QA4, Q-llvm-3, QL1, Q-O2
(§8.4, "four sides of one choice, the shared state representation");
QL2 (§8.3, SSI); rc-Q1, rc-Q2 (§8.5); also DD-Q6, Q-E2, Q-O3,
Q-llvm-2/Q-E3 (budgets). §9: D2 (own solvers allowed, named honestly).

**proposals/0003-facts-once.md** (items in this subsystem, to confirm
against the code at e96bb991):
- §1 rules: *keep* a fact when re-deriving it is a guess, can refuse a
  valid program, or costs more than linear; *derive* when it is a total,
  cheap function of a smaller one-source representation.
- "The dialect: ownership": a token without its cell (`!idr.token` has
  no parameters; four walks back to `idr.take`, one in
  `ReusesEveryCell.cpp`); "Exclusivity solved twice" (`Exclusive.cpp`
  re-solves the whole program when grade copies exist) and
  `ownsParameter` answering from the signature or the grade depending on
  whether a table was passed.
- "The static lifetime in the grade": `ownership::isStatic` searched
  along the definition chain; readers include
  `Analysis/Ownership/Values.cpp` (`tracked`) and
  `Analysis/Ownership/Reuses.cpp`; owed: `static` in `Idr_Lifetime`,
  written once at the op that makes the value; delete `isStatic` and
  callers' static branches.
- "Types that could carry the fact": `Exclusivity::targets` keyed by
  `Operation *` where only calls are stored (`Ownership.h`);
  `Reuses::sites` dereferencing a `find` without a check.
- "Exclusivity is no analysis": the final solve handed to
  `createRcCommit` by constructor (`Ownership/Exclusive.cpp`), so nothing
  reads it cached and it has no timing row; owed: a cached program
  analysis read by idr-rc-commit with `getCachedParentAnalysis`.

**audits/p0/README.md.** Nine-section layout; categories upstream, ods,
rederivation, ladder, list, attribute, state, budget, per-target, cpp,
idris, dead; lanes to cite: 02 (effects, `getEffects`, flow interface),
03 (ops), 05 (analyses outside ownership, SCC utility, dataflow uses,
cross-cutting rederivation chains), 06 (label solve), 08 (counting:
`Transforms/Ownership` cells, grades, exclusive, knots, reuse, take,
stack cells, demand), 13 (pipeline, threading), 01 (types, grades,
verifier).

## 2. What the subsystem is

All at e96bb991 (the working tree's `HEAD`); *read* unless marked.

### 2.1 Files and sizes

*Measured*: `wc -l foreign/idr/lib/Analysis/Ownership/* foreign/idr/include/idr/Analysis/Ownership.h foreign/idr/include/idr/Analysis/Ownership/*`.

| file | lines | what it is |
| --- | ---: | --- |
| `include/idr/Analysis/Ownership.h` | 323 | the shared vocabulary (points, uses, deaths, fields, value classes, `Copies`) and the three results: `Reuses`, `Borrows`, `Exclusivity` |
| `include/idr/Analysis/Ownership/ExclusivityDetail.h` | 170 | exclusivity's private types: `Calls`, `Captures`, `Item`, `SuccessorSources`, `Graph`, `solveOnce`, `liveBlocksOf` |
| `lib/Analysis/Ownership/Uses.cpp` | 207 | where a value is used and dies: `heldIn`, `usersIn`, `decides`, `usedAfter`, `whereDies`, `fieldsOf`, `onlyReads` |
| `lib/Analysis/Ownership/Values.cpp` | 42 | `followed`, `tracked`, `isMemoCell`, `isCountedElement` |
| `lib/Analysis/Ownership/Reuses.cpp` | 283 | reset/reuse decisions, per function, in parallel |
| `lib/Analysis/Ownership/Borrows.cpp` | 315 | borrow inference, whole program, on `DataFlowSolver` |
| `lib/Analysis/Ownership/Captures.cpp` | 74 | memo labels' captures, a pre-pass of exclusivity |
| `lib/Analysis/Ownership/Exclusivity.cpp` | 197 | the solve's driver and its answer tables, `proves` |
| `lib/Analysis/Ownership/ExclusivityGraph.cpp` | 226 | `Calls`, `liveBlocksOf`, the graph build |
| `lib/Analysis/Ownership/ExclusivityAnalyses.cpp` | 326 | the marking |
| **total** | **2,163** | |

Pattern counts over the same ten files (*measured*: `bash -c 'cat <files> | grep -c -E "<pattern>"'`, run from `foreign/idr`):

| pattern | count | | pattern | count |
| --- | ---: | --- | --- | ---: |
| `isa<` | 11 | | `DenseMap<` | 23 |
| of which multi-type `isa<A, B…>` | 2 | | `DenseSet<` | 11 |
| `dyn_cast` | 25 | | `MapVector<` | 1 |
| `std::variant<` | 4 | | `std::vector<` | 3 |
| `std::visit` | 6 | | `function_ref<` | 10 (5 declarations, each in `.h` and `.cpp`) |
| `std::get_if` | 10 | | `switch (` | 3 |
| `std::holds_alternative` | 2 | | `template <` | 4 (all `DenseMapInfo` or a local helper) |
| `std::get<` | 2 | | `requires`/`concept` | 0 |
| `DataFlowSolver`/`AnalysisState`/`DataFlowAnalysis` | 6 (all Borrows) | | `parallelForEach` | 1 (Reuses) |
| interface edge queries (`getSuccessorRegions/Operands/Inputs/NonSuccessorInputs`) | 8 | | `.walk(` | 5 |

No per-target case: `grep -n -i -E "x86|arm64|aarch|darwin|apple|linux|elf|glibc|page"` over the files finds only prose (*measured*).
No unit test exercises any of the three analyses directly
(`ls foreign/idr/unittests`: Constants, Cycles, Flow, Hooks, Identities,
Labels, Ranges, Sources, Verify, Words; *measured*); they are exercised
through `tests/rc-*` (21 directories, `ls tests | grep rc-`), 76 tests
that run `idr-rc`, 9 that mention an `excl` grade, 1 expecting
`unsupported (uniqueness)` (*measured*, `grep -rl` over `tests/`).

### 2.2 The facts it derives, and who reads them

| result | fact | state, keyed by | built by | read by |
| --- | --- | --- | --- | --- |
| `Reuses` | per function, the take sites (`Site`: box, data type, tag, point, bound fields, the `cell.new`s that recycle its cell) | `DenseMap<FuncOp, SmallVector<Site>>` (`Ownership.h:236`); per function while deciding: `DenseSet<Operation*> claimed`, `DenseMap<OpOperand*, TakenField> moved`, `DenseMap<TakenField, Virtual> virtuals`, `DenseMap<Point, SmallVector<unsigned>> takesAt` (`Reuses.cpp:258-265`) | `Reuses(program, am)`, a program analysis that runs `Decider` per function in `parallelForEach` on the context's pool (`Reuses.cpp:272-281`) | `Borrows` (a taken param is owned, `Borrows.cpp:179-181`); idr-rc-grades' `reuseAt` (`Transforms/Ownership/Grades.cpp:56-60`, `Reuse.cpp:37`) |
| `Borrows` | per parameter: `Untracked`, `Borrowed` or `Owned` | `DenseMap<FuncOp, SmallVector<Param>>` (`Ownership.h:256`); during the solve, one `HoldingState` (an `AnalysisState`) per parameter (every one, `Borrows.cpp:173-177`) and per readThrough-chain value it touches, and a uniqued `ProgramPoint` after every call (`:233`) | `Borrows(program, am)`: one `DataFlowSolver`, one custom `DataFlowAnalysis`, over the whole program, single-threaded (`Borrows.cpp:297-313`) | `writeOwnedGrades` (`Transforms/Ownership/Signatures.cpp:22-47`), then every later pass reads the grades from the types |
| `Exclusivity` | per value `Unknown`/`Exclusive`/`Shared`; live blocks; call targets under grade copies; callers and returns per function | `DenseMap<Value, Sharing>`, `DenseSet<Block*>`, `DenseMap<Operation*, FuncOp>` (calls only), `DenseMap<FuncOp, SmallVector<CallOp>>`, `DenseMap<FuncOp, SmallVector<ReturnOp>>` (`Ownership.h:304-308`) | `Exclusivity::solve(program, copies)`, a static function, not an analysis (`Ownership.h:27-31, 280`); called once or twice per idr-rc-exclusive (`Transforms/Ownership/Exclusive.cpp:39, 44`) | `specializeOnGrade`, `redirectCalls` (`Specialize.cpp:52-141`), `writeExclusiveGrades` (`Signatures.cpp:49-75`, into signatures), `createRcCommit` by constructor (`Exclusive.cpp:52`, `Commit.cpp:35-179`, reading `proves` and `live` from parallel function passes); idr-demand reads the grades the commit wrote and refuses `unsupported (uniqueness)` (`Passes.td:612-624`) |
| the vocabulary | where a value is used (`usersIn`, `heldIn`), whether used after an op (`usedAfter`), where it dies (`whereDies`), whether an op's regions are alternatives (`decides`), the fields a take gives (`fieldsOf`), a box only read (`onlyReads`), value classes (`followed`, `tracked`, `isMemoCell`, `isCountedElement`) | none: every query walks the IR | free functions (`Uses.cpp`, `Values.cpp`) | Reuses, Borrows, Exclusivity; lane 08's `Placement.cpp` (`usersIn`, `decides`, `pointBefore`, `definedAt`, `blockOf`, `firstAt`), `Reshape.cpp` (`whereDies`, `onlyReads`, `usedAfter`, `usersIn`, `isMemoCell`), `Classes.cpp` (`usedAfter`, `isCountedElement`), `Take.cpp` (`heldIn`, `fieldsOf`), `Reuse.cpp` (`blockOf`, `firstAt`), `Share.cpp` and `Specialize.cpp` (`followed`); `IR/Canon/MoveOut.cpp` has its own local `usedAfter` (*measured*, `grep -rn` of each name outside the subsystem) |

### 2.3 Each analysis's state model and cost

All sizes are *conjecture* from the field types on a 64-bit target and
LLVM's container rules (§5.1 A4, §5.3 B7: a `DenseMap`/`DenseSet` has at
least 64 buckets once it holds anything; a bucket is the key and value
padded; the load factor is at most 3/4).

**Exclusivity** (the marking). One solve builds, for the whole program:
- `std::vector<Item> items`: one per op with results, per call, per
  successor of each region branch op (its results and each non-empty
  region), per non-entry block with arguments, and per non-region-branch
  region op with entry arguments (`ExclusivityGraph.cpp:122-164, 170-224`).
  `Item` is a kind byte, four pointers and an index: 48 B.
- `std::vector<SuccessorSources>`: one per region successor, about 168 B
  each (a `ValueRange`, a `SmallVector<Value>` of six inline, a
  `SmallVector<pair<Block*, OperandRange>, 2>`, a `SmallVector<Block*, 1>`),
  so about 5 MB for one match of 30,000 cases.
- `DenseMap<Value, SmallVector<unsigned, 2>> dependents`: an entry for
  **every operand value of every op that has results** and every value
  a successor or a call reads (`ExclusivityGraph.cpp:110-120, 155-158`),
  followed by exclusivity or not; a 32 B bucket, about 43 to 85 B per key.
- `DenseMap<FuncOp, SmallVector<unsigned>> itemsOf`.
- During the marking: `DenseMap<Value, Sharing> sharing` (16 B buckets,
  about 21 to 43 B per key), `std::vector<char> queued` (1 B per item:
  dense), `std::deque<unsigned> work`, and `DenseMap<FuncOp,
  DenseSet<Block*>> liveOf`: one 64-bucket set per function that runs,
  at least 1 KB each (`ExclusivityAnalyses.cpp:313-316`), so about 70 MB
  at 70,000 functions before any block is in it.
- After the marking, `Exclusivity::solve` copies every reached value of a
  live block from `solved` into `out.sharing` (`Exclusivity.cpp:125-133`):
  a second per-value map alive at the peak.

So about 100 to 170 B per value that some op reads, plus 48 B per op:
a seventeenth to a thirtieth of the framework's 2.9 KB per one-bit state
at the pin, a little below one state under the patch P1 (182 to 198 B,
§5.1 A4), where the removed solve needed two lattices per value (§3.1
row 2); against a `BitVector` by dense value number (0.13 B a value,
§5.1 A4) it is nearly three orders of magnitude. The lattice itself is two bits of information
(`Unknown` only ever means "in no live block", `Exclusivity.cpp:83-87`,
`ExclusivityAnalyses.cpp:57-62`).

Work: each item re-executes whenever any value it reads rises (at most
twice per value: `Unknown` to `Exclusive` to `Shared`). An op successor
item re-joins **every** predecessor's operands on each run
(`ExclusivityAnalyses.cpp:244-251`), so a match of N cases costs up to
O(N) per run and O(N) runs: §5.1 C3's O(N²) shape is still there, inside
our own marking. e96bb991 measured a generated 20,000-case match at
1.3 s of IdrRcExclusive in a debug build; no stage-1 run has passed
idr-rc-exclusive since (`proposals/0001-self-host.md:93-100`: "The run
after that has not been made"; e96bb991's message: the previous run's
graph build "did not finish").

The whole solve repeats while a memo label is found unmade
(`Exclusivity.cpp:73-122`, `Captures::keepMadeIn`), and each repetition
rebuilds the graph (`ExclusivityAnalyses.cpp:33-35`) though the graph
does not depend on the captures; idr-rc-exclusive runs one or two
solves (`Exclusive.cpp:39, 44`), each building `Calls`, `Captures` (a
program walk) and the graph again. About six whole-program walks per
solve iteration (*read*: `Captures.cpp:20`, `ExclusivityGraph.cpp:98-101`,
`liveBlocksOf` per running function twice, `Exclusivity.cpp:105, 125`).

**Borrows** (on `DataFlowSolver`). One `HoldingState` per parameter of
every function, holding references or not (`Borrows.cpp:173-177`), and
per readThrough-chain value `own` or `holds` touches (`:253-288`); one
uniqued `ProgramPoint` after every call (`:233`), never freed (§5.1 A5);
each state subscribed from an after-call point carries a dependents
`SetVector`. At the pin that is about 1.5 KB per state with no
dependent and 2.9 KB with one (§5.1 A4 table). The analysis is a raw
`DataFlowAnalysis` with its own `visit`: no `DeadCodeAnalysis`, no
sparse or dense base, no lattice per program point; the framework
supplies only state storage and a FIFO of program points as
subscription keys (`:187-191, 239, 258, 261`). Each revisit of a call
redoes a symbol lookup, `getParentOfType`, `CallCycles::together` and
two tail-position walks (`:232-237`), and walks the argument's
definition chain calling `tracked`, whose `isStatic` walks a chain
again (`:253-267`; `Values.cpp:30`; `IR/Ownership.h:51-53`): quadratic
in chain length per argument per revisit.

**Reuses** (per function, parallel). Per function: the matches in walk
order, then a second walk for read boxes (`Reuses.cpp:71-120`); per
match a `usedAfter` (an ancestor walk times `usersIn`, itself a walk of
every use with `findAncestorOpInBlock`, a sort and a unique,
`Uses.cpp:30-39, 75-82, 113-128`); per death point a forward scan
(`fits`) through the rest of the block and every region of every op
that decides (`Reuses.cpp:208-228`), calling `decides` (O(regions):
`Uses.cpp:96-104`, `IR/Verify/Linearity.cpp:27-33`) on every op it
passes. The per-function maps are one per scope (fine by §5.3 B7). It
keeps a **shadow of the rewrite it has not made**: a box is a `Value`
or a `TakenField` (`Reuses.cpp:59`), every taken field carries its type
and the uses it will move (`Virtual`, `:62-65`), and every later query
filters the uses already moved (`:142-151, 183-191`). The type of each
virtual field is built with `fieldType` (`:244`; `IR/Grades.cpp:253-260`,
which makes graded types through the context's uniquer) from the
worker threads.

**The vocabulary** keeps no state: every query walks the IR. The costs
per query: `heldIn` O(depth) per use; `usersIn` O(uses·depth + uses·log
uses); `usedAfter` O(depth · (uses·depth)); `decides` O(regions) (two
interface walks over every region of the op); `onlyReads` two `usersIn`
plus an ancestor walk per use (*read*, the lines above).

### 2.4 Threading

- Reuses: `mlir::parallelForEach` over the program's functions inside the
  analysis constructor, one output slot per function (owner computes);
  it reads `Layouts` (frozen) and its own function; it creates graded
  types from the workers (`Reuses.cpp:244, 276`), which takes the
  context uniquer's shard locks (§5.1 F3).
- Borrows: single-threaded, whole program, inside the program pass
  idr-rc-grades (`Grades.cpp:47`).
- Exclusivity: single-threaded, whole program, inside the program pass
  idr-rc-exclusive; the answer is then read by a nested, parallel
  function pipeline (`Exclusive.cpp:50-54`) through `proves` and `live`,
  which only read the frozen tables and the IR's flow edges.
- None states its threading contract in its header beyond "read-only once
  built" (`Ownership.h:30-31`).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs, one by one

| # | proposal claim | verdict | what our code shows |
| --- | --- | --- | --- |
| 1 | §2: `Ownership/Borrows` is "still on upstream's dataflow framework" | holds in part | It is on `DataFlowSolver` (`Borrows.cpp:54, 161, 298`), but as a raw `DataFlowAnalysis` with its own `visit` and one custom `AnalysisState`: no sparse or dense base, no dead-code analysis, program points used only as subscription keys after calls (`:187-191, 233, 239`). §5.1 item 2's "each is a `SparseForward/BackwardDataFlowAnalysis` solved with `top` = one function" does not describe it: the framework adds storage and a worklist, no algorithm. |
| 2 | §3 row ffa91113: exclusivity on the framework, 627 GB, "a lattice per value, an `Executable` per program point, a predecessor state per function" | holds | The removed code (`git show ffa91113 -- …/ExclusivityAnalyses.cpp`) loaded `DeadCodeAnalysis`, `NoConstants` (a `Lattice<ConstantValue>` per value, set to unknown everywhere only so the dead-code analysis would not prune regions on constants), `Running` (a `Runs` state per function entry) and `ExclusiveAnalysis` (a `CellsLattice` per value): two sparse lattices per value, an `Executable` per block, a `PredecessorState` per callable and region point. |
| 3 | §5.1 H2: "627 GB … some 200 million states"; a patched framework "would cut the fixed part about fifteenfold and leave the lattices' own contents" | holds in part | The lattices' contents were one byte (`Sharing`) and an unused constant: the fixed part was nearly everything. Besides memory, the framework cost two correctness rounds the removed comments record: a copy's regions never reached their results because the dead-code baseline consulted constants (4108916a, "NoConstants gives a parameter and a call's result the unknown constant too"), and every closure's function had unknown callers because the dead-code analysis counts a label's name as an unknown use (e8e38bd7), the fact of `upstream/29`. A return to the framework re-imports that coupling (§5.1 A7) unless U4 lands. |
| 4 | §3 row e96bb991: "an interface query per pair of terminator and region successor" | holds, with two residues | `scanBranch` now asks each point once (`ExclusivityGraph.cpp:191-216`). Residue 1: `unknownFrom` is appended to every successor (`:222`), O(successors × unknown blocks). Residue 2: the marking re-joins all N predecessors each time the op successor runs (`ExclusivityAnalyses.cpp:244-251`): §5.1 C3 inside our code. |
| 5 | §5.1 item 3: exclusivity's graph "stays ours, honestly" | holds | The problem is whole-program in both directions (a parameter from every caller, `execCall` `:221-222`; a call result from the callee's returns, `:223-225`) and context-sensitive (a call of a grade key goes to the copy while every followed argument is exclusive, `ExclusivityGraph.cpp:50-61`). Neither a per-function solve nor a one-direction summary schedule states it without an IFDS-style summary (result sharing as a function of parameter sharing). |
| 6 | §5.1 C4 / item 5: "every client of ours builds an op's edge table once" | holds for exclusivity, refuted for the vocabulary | `decides()` asks `getSuccessorRegions(parent)` and, through `verify::alternatives`, `getSuccessorRegions(region)` for every region, on **every call** (`Uses.cpp:96-104`, `IR/Verify/Linearity.cpp:27-33`): O(regions) per query, called per scanned op in Reuses' `fits` (`Reuses.cpp:219`) and per user in lane 08's placement (`Placement.cpp:193, 247`). `execBlockArgs` re-asks `BranchOpInterface` per run (`ExclusivityAnalyses.cpp:281-297`). |
| 7 | §2 trait layer (recalled): "the `Decides` trait, declared in ODS, with a `verifyTrait`" | refuted | `grep -rn Decides foreign/idr/include foreign/idr/lib` finds only a comment in `IR/Symbols.h:197` (*measured*). "Decides" is the C++ function `ownership::decides` (`Uses.cpp:96`), re-derived per query. |
| 8 | §5.3 M7: "Exclusivity marks the program graph … dependents read off a graph's edges, a mark per node, the answer a value" (SCCP's shape) | holds in part | Dependents by edge: yes (`Graph::dependents`). A mark per node: a `Sharing` per value, but in a `DenseMap<Value, …>`, not a dense vector. The answer a value: yes, but not cached in the `AnalysisManager` and copied once more after the solve (`Exclusivity.cpp:125-133`). Unlike SCCP, a change re-runs the whole writer item, not one edge. |
| 9 | §5.3 S1: "`mark(graph, seeds)` … Exclusivity's and idr-rc-stack's markings become calls" | holds in part | Exclusivity is a three-valued join (`ExclusivityAnalyses.cpp:64-77`) whose edges are **gated** (an edge writes only from a live block, `:86-89, 236-251`), whose call edges **switch target** once (`:219`), and whose memo captures need a made label (`:263-266`) decided in an outer descending loop (`Exclusivity.cpp:73-122`). A plain BFS from seeds does not express gates or switches; MLton's cells with handler lists (§5.9 B4) do. |
| 10 | §5.4 F7 / Design 4: successors per terminator, predecessors inverted once | holds after e96bb991 | `scanBranch` is exactly that (`ExclusivityGraph.cpp:191-216`), kept per branch op in `SuccessorSources`. Its `byRegion` map (`:178`) re-derives `Region::getRegionNumber`, which is pointer subtraction (§5.1 C1). |
| 11 | §5.6 item 1, Design 2, W-E2: a solver's domain is the values whose type leaves the question open | refuted for exclusivity today | `followed` is that filter (`Values.cpp:22-26`), applied in `execOp` (`ExclusivityAnalyses.cpp:156`), `intoPart` (`:139`), `fillCaptures` (`:201`) and `Calls::target` (`ExclusivityGraph.cpp:56`). But the graph holds an item for every op with results and a dependent entry for every operand (`ExclusivityGraph.cpp:155-158, 110-115`), and `joinValue(…, Shared)` writes state for values exclusivity does not follow: every parameter of a root (`ExclusivityAnalyses.cpp:97-100`), every unforwarded input (`:269`), every entry argument of a non-branch region op (`:301-308`), every input after an unknown terminator (`:236-243`). |
| 12 | §5.6 item 6 / Shape G: extract, solve, write back; "exclusivity's program graph" fits | holds in part | The graph is an extraction (`ExclusivityGraph.cpp`) and the answer goes back into types (`writeExclusiveGrades`, `Signatures.cpp:49-75`). But nodes are IR pointers (`Value`, `Block*`, `Operation*`) in hash maps, not dense ids, and the extraction is redone per solve iteration. |
| 13 | §5.7 M1: "The 627 GB wall is a dense formulation of a sparse problem" | refuted in part | The removed solve was already sparse: `SparseForwardDataFlowAnalysis<CellsLattice>`, a lattice per SSA value (ffa91113's removed code). The owned stage already has SSI for exclusivity: "a reference is duplicated only by idr.dup, so exclusivity is provenance" (`Exclusivity.cpp:11-13`); dup, share, take, recycle and give each define a value. What was dense was the dead-code baseline (`Executable` per block, `PredecessorState`) and A4's containers. |
| 14 | §5.7 L1: SSI by representation deletes "program-point state in exclusivity, borrows and stack lifetimes" | refuted for exclusivity and borrows, holds for reuse in a different form | Exclusivity keeps one bit per block (reach) and nothing per point; Borrows keeps nothing per point (its after-call program points are subscription keys, not facts). The facts at points in this subsystem are deaths (`whereDies`, `usedAfter`), which are liveness, a query under SSA (§5.7 C4), not a fact an SSI rewrite moves onto a name. |
| 15 | §5.9 H, M2: ffa91113's "marks the program graph" is MLton's model | holds in part | One fact per name: yes. On the node and dense: no (hashed by `Value`). Constraint handlers: no (writer items re-run). State sized by types and constructors: no, except memo captures, which `Captures` keys by (data type, tag, field) (`ExclusivityDetail.h:95-99`): MLton's per-constructor fact (§5.9 B5) found by hand for one case, and the same anchor `FlowAnchor::Field` the label solve uses (`IR/FlowEdges.h:88-93`). |
| 16 | §5.9 Design 1 deletes "the separate solvers in `Analysis/Ownership` (Exclusivity's solve, Uses, Values, Captures, Reuses)" | holds for Exclusivity, Captures, Values; refuted for Uses and Reuses | Uses is a set of per-function liveness queries, not a whole-program fact; it becomes a per-function scope (L2), not a domain. Reuses is a placement decision at points, not a fact per name. |
| 17 | §5.10 M2: "If `Uses` and `Values` compute liveness or use counts that `idr-rc-cells` then reads, that is a rederivation chain" | holds in part | No liveness table is stored and read later. The chain is elsewhere: the same decision, "take an owned box apart where it dies", is made twice with the same helpers, by Reuses before the rewrite (`Reuses.cpp:71-201`) and by lane 08's Reshape after it (`Transforms/Ownership/Reshape.cpp:69-109, 260-282`), with different filters (`isStatic` against `Classes`) and different `takesOver` rules. |
| 18 | §5.10 M5: exclusivity is "a forward property from allocation sites, killed by the first `dup` or ω binding" | holds | `Exclusivity.cpp:11-36`: fresh cells, takes, recycles, inits of exclusive fields; dups, constants, stack cells, shares and unseen callers share. |
| 19 | §5.10 M6: linear "if its graph has one node per parameter, result and value-flow edge, and each node is marked at most once" | holds in part | Nodes are writer items; values rise at most twice; items re-run per rise of any input (row 4's residue 2). |
| 20 | §5.10 M7: reuse before or after insertion | answered: before (Lean's order) | Reuses runs before borrow inference and before placement, in idr-rc-grades (`Grades.cpp:45-66`), with "any call may take its arguments over" (`Reuses.cpp:193-195`); it matches by size (`:192, 213`); its token may be held across calls (§3.2, rc-W2). |
| 21 | §5.10 M8: "`Captures` may vanish under defunctionalization" | refuted | `Captures` is not about closures: it tracks the fields of memo labels that `idr.cell.init` writes and `idr.memo.run` moves out (`ExclusivityDetail.h:65-77`), which defunctionalization creates. It could become anchor nodes of the one graph (row 15). |
| 22 | §5.10 R1.1: signatures in types | holds | Borrows' answer is written into every signature (`writeOwnedGrades`, `Signatures.cpp:22-47`) and exclusivity's too (`writeExclusiveGrades`, `:49-75`); later passes read types (S0, Q-O3's form already). |
| 23 | 0003 "Types that could carry the fact": `Exclusivity::targets` keyed by `Operation *`, `Reuses::sites` dereferencing a `find` | holds, and a third | `Ownership.h:306` (only `CallOp`s are stored, `Exclusivity.cpp:112`), `Ownership.h:233`; also `Borrows::params` (`Ownership.h:251`). |
| 24 | 0003 "Exclusivity is no analysis"; "Exclusivity solved twice" | holds | `Ownership.h:27-31`; `Exclusive.cpp:39, 44, 52`. |
| 25 | 0003 "The static lifetime in the grade": readers in `Values.cpp` and `Reuses.cpp` | holds | `Values.cpp:30` (`tracked`), `Reuses.cpp:164-165` (`reusable`, a chain of `isStatic`, each a chain walk). `Values.cpp:28-29` says "the type answers … asking again costs nothing", which is false of its `!isStatic(value)` half. |
| 26 | §5.2 A9 / §5.8 EF3: consumption as `Read` + `Free` on the operand | holds in the IR, not in this subsystem's reading | `consumedEffects` already declares `Free` on `ReferenceResource` per taken operand (`IR/Effects.cpp:96-105`), but Reuses asks `consumes(use)` (`Reuses.cpp:195`; `IR/Effects.cpp:86-90`, the same `eachTaken` walk), and Borrows asks an `isa` ladder plus `storedBy` and `forwardedValues` (`Borrows.cpp:194-219`). |
| 27 | §5.10 M6 "three markings, one honest solver layer"; §5.3 S1's `mark` | holds, and the tree already has two engines | b8301ebe made idr-rc-stack's inference (lane 08) a graph with **dense node ids** (`DenseMap<Value, unsigned> ids` once at the build), adjacency `SmallVector<SmallVector<unsigned, 2>> out, in`, and a `BitVector` breadth-first `mark(seeds, backward)` (`Transforms/Stack/Stack.cpp:197-208, 262-268`): S1's primitive, written by hand. Exclusivity's marking, written the same day (ffa91113), keeps a different state model (writer items, `DenseMap<Value, Sharing>`). One fact (a monotone marking over a program graph), two representations. |

### 3.2 Wave-2 questions of §5 answered

*§5.1 mlir-analysis.*
- **W1** (V, B, P, F): not measurable here (no built compiler). What this
  subsystem's state scales with: exclusivity, every operand of every op
  with results (dependents), every reached value (twice), every op
  (items), every running function (a block set each); Borrows, every
  parameter of the program plus chain values plus a program point per
  call. Measurement in §8.
- **W2**, for this subsystem:

  | analysis | lattice | where | interprocedural | summaries it would need | fits |
  | --- | --- | --- | --- | --- | --- |
  | Exclusivity | `Sharing`, 2 bits of information per value; a reach bit per block; a run bit per function | per value (sparse) | yes, both directions, and context through grade copies | parameter sharing from callers (top-down) and result sharing from returns (bottom-up), mutually dependent | Design 3 / S1 (one honest marking) |
  | Borrows | two-point per parameter (`Borrowed` to `Owned`) with fixed cases | per parameter and chain value | yes, callee to caller (an owned callee parameter owns the argument) and, inside a cycle of calls, caller to callee (tail calls) | a parameter vector per function, iterated inside an SCC | Design 1's summary layer (per SCC, as Lean's, §5.10 B2) or the same marking as exclusivity |
  | Reuses | none: a decision per match and per read box | per point (death), per function | no (pessimistic about calls) | none | a per-function rewrite (§5 D4) |
  | Captures | per (memo, tag, field): shared or not; per label: made | per constructor field | yes (whole program) | none | part of exclusivity's graph |
  | Uses | none: queries | per value per block | no | none | a per-function scope (§5.7 L2) |

- **W3**: per-query interface calls: `decides` (`Uses.cpp:100-101`) and
  `verify::alternatives` (`IR/Verify/Linearity.cpp:29-30`), O(regions)
  each; `execBlockArgs`' `getSuccessorOperands` per run
  (`ExclusivityAnalyses.cpp:290`). Per op (fine): `liveBlocksOf`
  (`ExclusivityGraph.cpp:75, 92-94`), `scanBranch` (`:193, 202, 220-221`).
  None calls `getPredecessors`, `getPredecessorValues`,
  `getSuccessorOperandInputMapping`, `isRepetitiveRegion` or
  `insideMutuallyExclusiveRegions` (*measured*, `grep`).
- **W4**: the match ops carry `RecursiveMemoryEffects`
  (`IdrMatchOps.td:26`); this subsystem queries no effect, so it pays
  none of D3's walk (Placement's `writes`, lane 08, does).
- **W5**: `Reuses::record` builds graded types with `fieldType` on the
  worker threads (`Reuses.cpp:244`, `IR/Grades.cpp:253-260`), only to
  type a field that does not exist yet. Nothing else here creates an
  attribute or a type.
- **W6**: none of the three is function-anchored. Reuses is per function
  but runs inside a program-level analysis with its own
  `parallelForEach` (`Reuses.cpp:276`); Borrows and Exclusivity are whole
  program by nature (rows 1, 5).
- **W7**: no. Borrows resolves callees itself through the `SymbolTable`
  analysis (`Borrows.cpp:234`); nothing here uses a backward sparse
  analysis.

*§5.3 llvm.*
- Worklists: exclusivity's FIFO `std::deque<unsigned>` over dense item
  ids with a `std::vector<char>` of queued flags (dedup by flag:
  `ExclusivityAnalyses.cpp:41-49, 79-84`); `OnceWorklist<FuncOp>` for
  reached functions (`Exclusivity.cpp:94-117`); a LIFO `SmallVector`
  stack in `liveBlocksOf` with the `DenseSet` as the seen set
  (`ExclusivityGraph.cpp:64-95`); Borrows uses the solver's FIFO. None
  needs an SCC order of its own; Borrows reads `CallCycles` (lane 05).
- Per-node containers: `liveOf` (a `DenseSet` per running function),
  Reuses' and Borrows' and Exclusivity's `DenseMap<FuncOp, SmallVector<…>>`
  (fine: one map, inline vectors), Borrows' framework states (two
  64-bucket tables per state, §5.1 A4). The per-value maps are one per
  solve but keyed by pointer.
- `function_ref`: `whereDies`' `takesOver` and `at` (`Ownership.h:116-121`):
  `at` is an output threaded as a callback (return the points instead);
  `takesOver` is a policy with two callers (Reuses, Reshape), cold
  enough for `function_ref` but gone with §5 D4. `Calls::target`'s
  `isExclusive` (`ExclusivityDetail.h:50`): two callers, each a lambda
  over the solve's own state.
- Variants: `Point` (2 alternatives, visited exhaustively,
  `Uses.cpp:55-61`); `Held`/`Site::box` (2, read by `get_if` chains,
  `Reuses.cpp:136-166, 187`); `Calls::Callee` (2, visited by
  `makeVisitor`, but tested once by `holds_alternative`,
  `Exclusivity.cpp:111`); `FlowEdges::Edge::move` (8, visited
  exhaustively, `ExclusivityAnalyses.cpp:172-185`; probed by `get_if` in
  `proves`, `Exclusivity.cpp:171-174`).
- The seven framework files: Borrows solves over the whole program (S1
  material, not S2).
- One CSR graph type for exclusivity's graph, idr-rc-stack's flow graph
  and the label solve's graph: for exclusivity, yes if the graph type
  carries gates (an edge waits on its function's run bit, a capture edge
  on its label's made bit, a call's edges on its target; block reach is
  static per function, D2) and node classes (value, function, label,
  capture anchor, key call);
  idr-rc-stack (lane 08) and Borrows are plain two-point markings that
  need neither.

*§5.4 modular.*
- State copied per region or edge: none here. Per-point state: Reuses'
  death points only.
- Predecessors of region successors: computed once per branch op by
  inverting each point's successors (`ExclusivityGraph.cpp:191-216`).
- A hand `getEffects` or `verify` because an attribute changes an op:
  none in this subsystem.

*§5.6 ecosystem.*
- **W-E2**: row 11 of §3.1; the counts need a stage-1 run (§8).
- **W-E4**: no discardable attribute here; both interprocedural answers
  go into types.
- **W-E5**: no budget, cap or round count. One loop that states its end
  by a measure: the solve repeats while a memo label stops being made,
  and labels only go (`Exclusivity.cpp:69-74`; c4d38e9b's message,
  "a loop that states its end"). It cannot fail.
- **W-E6**: `decides`/`alternatives` (row 6); `scanBranch` reads each
  branch op's edges once; `liveBlocksOf` once per op.
- **W-E7**: exclusivity's `sharing`, `dependents` and `out.sharing`
  (`DenseMap<Value, …>`); Reuses' `moved` (`DenseMap<OpOperand*, …>`) and
  `takesAt` (`DenseMap<Point, …>`); Borrows' framework states. A
  per-function pre-order numbering already exists in the verifier
  (`IR/Verify/Linearity.cpp:41-58`, `Numbering`).
- **W-E9**: no copy per edge; Reuses' state per point is essential
  (where a value dies).

*§5.7 library* (for every analysis: PLV, PVP or relational; direction;
per-point facts; product solves):
- Exclusivity: PLV (a value's sharing is a function of its writers'),
  forward, no per-point fact but block reach, which it already computes
  in the same solve (a product of reach and sharing). The call-target
  switch makes it non-distributive but monotone.
- Borrows: PLV per parameter, backward (a use owns its definition, up
  the readThrough chain) with one forward rule inside a cycle; reads
  Reuses' finished answer (composition by frozen read, M7 (ii)).
- Reuses: not a lattice problem; a decision at death points.
- Captures: PLV per constructor field; folded into exclusivity's product.
- The vocabulary: liveness queries (C4).

*§5.8 dialect-design.* The reads of consumption:
`Reuses.cpp:195` (`consumes`), `Borrows.cpp:207-218` (`OwnGiveOp`,
`storedBy`, `forwardedValues`); each maps onto a `Free` on the operand
(already declared, row 26) or a `FlowEdges::Flow` into a part.

*§5.9 mlton.*
- **Q-W2**: exclusivity, per value, flow-insensitive by construction
  (SSA), Design 1's domain with handlers instead of writer items;
  Borrows, per parameter, Design 1's two-point domain; Captures, per
  constructor field (B5); Reuses and the vocabulary are not domains.
- **Q-W6** (counting's liveness): the vocabulary answers it per query
  (`usedAfter`, `whereDies`), never as a stored fact; lane 08's Placement
  walks each value's uses per block (`Placement.cpp:183-235`).

*§5.10 rc.*
- **W1**: lane 08's `place` inserts `idr.dup`/`idr.drop`
  (`Grades.cpp:63`); Uses is its query helper, not an input computed
  beforehand.
- **W2**: before insertion; by size; a token may be held across calls:
  `fits` scans forward with no stop at a call or at any op that does
  not decide (`Reuses.cpp:208-228`); the takes themselves avoid Lean's
  example B by refusing a take after a consuming last use
  (`Reuses.cpp:193-195`, `Uses.cpp:141-143`).
- **W4**: one item per writer (op, call, region successor, block with
  arguments, region op with entry arguments); a value is marked at most
  twice; peak memory and time on stage 1 unmeasured (§8).
- **W7** (ownership ops): seen from here, `idr.take` and
  `idr.cell.recycle` are a token pair Reuses decides but does not
  create (`Ownership.h:212-217`); 0003's typed token
  (`!idr.token<!idr.box<T>, @C>`) would let Reuses' sites live in the IR.

*§5.11 oom.* Item 7, states sized by a product of two program
quantities: `unknownFrom` copied per successor (successors × unknown
blocks, `ExclusivityGraph.cpp:222`); `fillCaptures`' `find_if` per
capture (inits × forces × fields², `ExclusivityAnalyses.cpp:199-209`);
the outer re-solve (labels dropped × program, `Exclusivity.cpp:73-122`);
`fits` (death points × path length, `Reuses.cpp:208-228`); `decides` per
query (queries × regions).

## 4. Issues

Every claim *read* at the cited lines unless marked. "→ D*n*" points to
the change in §5 that disposes of it.

### 4.1 `include/idr/Analysis/Ownership.h`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| O-01 | `Ownership.h:27-31, 280` | upstream | Exclusivity "is a value its solve returns, as it is solved twice": a static `solve`, not an `AnalysisManager` analysis; handed to the commit by constructor (`Exclusive.cpp:52`). 0003's "Exclusivity is no analysis". | a cached program analysis keyed by its copies, read with `getCachedParentAnalysis` → D2 |
| O-02 | `Ownership.h:56-68, 177-193` | state | `Point = variant<BlockStart, After>` with two `DenseMapInfo` specializations, a hashed pair for a position between ops | an integer coordinate of the per-function scope (the pre-order index of the op before, the block's start a sentinel) → D5 |
| O-03 | `Ownership.h:70-77` | state | `blockOf`, `firstAt`, `pointBefore`, `definedAt` translate `Point` to iterators and back | arithmetic on the coordinate → D5 |
| O-04 | `Ownership.h:82` | rederivation | `heldIn`: `findAncestorOpInBlock` per use per query (`Uses.cpp:75-82`) | two compares on pre-order intervals → D5 |
| O-05 | `Ownership.h:87-90` | rederivation | `usersIn` ×2: walk every use, ancestor-find, sort by `isBeforeInBlock`, unique, per query (`Uses.cpp:30-39`) | uses sorted once by pre-order index; a range query → D5 |
| O-06 | `Ownership.h:99` | ods, rederivation | `decides`: O(regions) interface calls per query (`Uses.cpp:96-104`, `IR/Verify/Linearity.cpp:27-33`); §2's recalled `Decides` trait does not exist | one bit per op computed once at the scope's boundary; or an ODS-declared fact (lanes 02/03) → D5 |
| O-07 | `Ownership.h:107` | rederivation | `usedAfter`: ancestors × `usersIn` per query (`Uses.cpp:113-128`), O(depth²·uses) | a liveness check on the scope (§5.7 C4) → D5 |
| O-08 | `Ownership.h:116-121` | cpp | `whereDies` threads its output through a `function_ref` (`at`) and its policy through another (`takesOver`) | return the points; `takesOver` goes with the second decider → D4, D5 |
| O-09 | `Ownership.h:124-133` | — | `Field`, `fieldsOf`: bound arguments then field reads, by index (`Uses.cpp:162-170`) | keep (one reader, `Take.cpp:38, 73`) |
| O-10 | `Ownership.h:140-141` | rederivation | `onlyReads` ×2: two `usersIn` per query and an ancestor walk per use (`Uses.cpp:196-203`) | one range compare on the scope → D5 |
| O-11 | `Ownership.h:147` | ods (type) | `followed`: `isa<CellType>` or owned and `isa<BoxType, DataType, TokenType>` (`Values.cpp:24-25`): a classification of types restated as a C++ ladder | a `ValueFacts` type-interface method (lane 01) → D6 |
| O-12 | `Ownership.h:151` | rederivation | `tracked = holdsReferences && !isStatic`; `isStatic` walks the definition chain (`IR/Ownership.h:51-53`); the comment at `Values.cpp:28-29` claims a type answer "made once" | the static lifetime in the grade (0003; lanes 01, 08); then a type fact → D6 |
| O-13 | `Ownership.h:158` | — | `isMemoCell`: a type predicate (`Values.cpp:32-35`) | keep as a type fact beside O-11 → D6 |
| O-14 | `Ownership.h:165` | ladder | `isCountedElement`: `memref::LoadOp` by name (`Values.cpp:37-40`); 0003's "owned stage reads upstream's buffer ops by name" | the crossing as an op of its own (0003; lanes 08, 03) → D6 |
| O-15 | `Ownership.h:171-173` | — | `Copies`, a `MapVector<FuncOp, FuncOp>` in a struct: the solve's context | becomes the second analysis's input → D2 |
| O-16 | `Ownership.h:233, 236` | state | `Reuses::sites(fn)` is `sitesOf.find(fn)->second` with no check (0003); a `DenseMap<FuncOp, …>` | gone with Reuses → D4 (or a vector by function id) |
| O-17 | `Ownership.h:206-210, 219, 314-321` | state | `TakenField`, `Site::box = variant<Value, TakenField>`, `DenseMapInfo<TakenField>`: the shadow of a rewrite not yet made | deleted: decide and rewrite in one walk → D4 |
| O-18 | `Ownership.h:218-225` | state | `Site` carries `bound` and `cells` as side data the rewrite then makes (`Reuse.cpp:37-60`) | the take and recycle ops themselves → D4 |
| O-19 | `Ownership.h:244` with `Borrows.cpp:73, 88-100` | cpp | two enums for one fact (`Param` public, `Holding` inside) and a switch between them | one sum: fixed (owned or view) or inferred (a bit) → D3 |
| O-20 | `Ownership.h:251, 256` | state | `Borrows::params(fn)` dereferences `find` unchecked; `DenseMap<FuncOp, …>` | a vector by function id, or the signature itself (the grades are written there anyway) → D3 |
| O-21 | `Ownership.h:270` | state | `Sharing {Unknown, Exclusive, Shared}`: `Unknown` is "in no live block" folded into the value's lattice (`Exclusivity.cpp:83-87`) | a shared bit per value and a reach bit per block → D2 |
| O-22 | `Ownership.h:286`; `Exclusivity.cpp:163-181` | rederivation | `proves` re-reads the defining op's flow edges per query and recurses through quantity changes, from the parallel commit (`Commit.cpp:86, 93`) and `writeExclusiveGrades` | the quantity-change edge is in the graph already; answer is a bit; a value made after the solve is graded by the op that makes it (lane 08) → D2 |
| O-23 | `Ownership.h:304` | state | `DenseMap<Value, Sharing>`: a hash bucket per reached value | a bit vector by dense value id → D2 |
| O-24 | `Ownership.h:305` | state | `DenseSet<Block*> liveBlocks` | a bit vector by dense block id → D2 |
| O-25 | `Ownership.h:306` | state | `targets` keyed by `Operation *` though only calls are stored (0003) | `DenseMap<CallOp, FuncOp>` or a slot per call id → D2 |
| O-26 | `Ownership.h:307-308` | state | `callersOf`, `returnsOf`: `DenseMap<FuncOp, SmallVector<…>>`; `returns(fn)` is `.at(fn)` | vectors by function id (or the program graph's, lane 05) → D2 |
| O-27 | `Ownership.h:38` | dead | `#include "mlir/IR/SymbolTable.h"`: nothing in the header names `SymbolTable` (*measured*, `grep -n SymbolTable`) | delete |

### 4.2 `include/idr/Analysis/Ownership/ExclusivityDetail.h`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| X-01 | `ExclusivityDetail.h:34-63`; `ExclusivityGraph.cpp:39-41` | rederivation | `Calls::calleeOf` hashes the callee's name per call per run (`callees.at(attr)`) | resolve once into the call's edges at the build → D2 |
| X-02 | `ExclusivityDetail.h:40` | cpp | `Callee = variant<FuncOp, Pair>`; visited exhaustively twice, asked once with `holds_alternative` (`Exclusivity.cpp:111`) | one visit; the target switch as a gated call edge → D2 |
| X-03 | `ExclusivityDetail.h:50` | cpp | `target(call, function_ref<bool(Value)>)`: a callback where the caller's state is known | a member of the marking reading its own bits → D2 |
| X-04 | `ExclusivityDetail.h:58` | — | `showsEveryCall = !fn.isRoot()`: the closed-program invariant (e8e38bd7) | keep: it is the program's one root |
| X-05 | `ExclusivityDetail.h:78-100`; `Captures.cpp` | state | `Captures`: forces, makers and shared fields keyed by (data, tag[, field]) pairs, a per-constructor-field fact kept beside the graph | anchor nodes (`FlowAnchor::Field`) of the one graph → D2 |
| X-06 | `ExclusivityDetail.h:107-108` | state | `solveOnce` returns `DenseMap<Value, Sharing>` by value | the frozen solution → D2 |
| X-07 | `ExclusivityDetail.h:114`; `ExclusivityAnalyses.cpp:95`; `Exclusivity.cpp:104` | rederivation | `liveBlocksOf` run twice per running function per solve iteration: in the marking and again after it | reach is one of the marking's bits → D2 |
| X-08 | `ExclusivityDetail.h:124-132` | state, cpp | `Item`: a kind plus fields only some kinds use (`op` null for block arguments; `region`, `source` only for successors) | edges in a CSR table; the kinds become edge classes that carry only their data → D2 |
| X-09 | `ExclusivityDetail.h:139-144`; `ExclusivityGraph.cpp:208-216, 222` | state, budget | `SuccessorSources::unknownFrom` holds every block of the op's regions whose terminator is not a region-branch terminator, copied into every successor: O(successors × such blocks) | deleted with the predecessor that never transfers control → D1 |
| X-10 | `ExclusivityDetail.h:149-166` | state | `Graph`: `DenseMap<Value, SmallVector<unsigned, 2>> dependents` keyed by pointer, for every operand; `DenseMap<FuncOp, SmallVector<unsigned>> itemsOf` | CSR over dense ids, only followed values → D2 |

### 4.3 `lib/Analysis/Ownership/ExclusivityGraph.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| G-01 | `ExclusivityGraph.cpp:24-37` | — | `Calls` reads a function's one return off its single block's terminator | keep (the single-block invariant) |
| G-02 | `ExclusivityGraph.cpp:63-96` | state | `liveBlocksOf`: a `DenseSet<Block*>` filled per function | reach bits → D2 |
| G-03 | `ExclusivityGraph.cpp:155-158` | state | an `Op` item for every op with results, followed or not | an edge only where a followed value is written → D2 |
| G-04 | `ExclusivityGraph.cpp:110-115` | state | `reads` adds a dependent for every operand value, followed or not | the domain filter at the boundary → D2, D6 |
| G-05 | `ExclusivityGraph.cpp:124-132` | — | a `BlockArgs` item per non-entry block with arguments (CFG blocks inside our structured IR) | keep as block-argument edges; count them at stage 1 (§8) |
| G-06 | `ExclusivityGraph.cpp:127-131` with `ExclusivityAnalyses.cpp:281-297` | rederivation | `BranchOpInterface` asked at the build and again at every run | edges carry their operands, as successor sources already do → D2 |
| G-07 | `ExclusivityGraph.cpp:141-164` | ladder | `dyn_cast<RegionBranchOpInterface>` / `dyn_cast<CallOp>` / else, and `isa<RegionBranchOpInterface, CallableOpInterface>` (`:159`): an interface-based classification, acceptable, but a chain | one `TypeSwitch` with `DefaultUnreachable` over the classes the graph knows (§5.3 I2) → D2 |
| G-08 | `ExclusivityGraph.cpp:178, 184, 197-200` | upstream, rederivation | `DenseMap<Region*, unsigned> byRegion` per branch op re-derives `Region::getRegionNumber` (pointer subtraction, §5.1 C1) | index by `getRegionNumber()` → D2 |
| G-09 | `ExclusivityGraph.cpp:208-216, 222`; `ExclusivityAnalyses.cpp:236-243` | rederivation (precision bug, *conjecture* on its effect, *read* on its path) | a case region ending in `ub.unreachable` (a `Terminator` with no `RegionBranchTerminatorOpInterface`, `UBOps.td:73`; how every crash case ends, `IR/OpsMatch.cpp:32`, `IdrCheckOps.td:21`) counts as "a way out whose operands no interface says"; when its block is live, **every input of every successor of the match is shared**: its results and every region's arguments. Every memo force dispatch has such a case (`tests/rc-capture-unmade/rc-capture-unmade.mlir`, `case @running() { idr.crash …; ub.unreachable }`), as does every non-covering function. The same rule stood before e96bb991 (its diff). | a terminator that is neither a region-branch terminator nor a branch leaves the op nowhere: no predecessor, no `unknownFrom` → D1 |
| G-10 | `ExclusivityGraph.cpp:219-221` | — | `getSuccessorInputs`, `getNonSuccessorInputs` per successor, O(1) each | keep in the build → D2 |

### 4.4 `lib/Analysis/Ownership/ExclusivityAnalyses.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| A-01 | `ExclusivityAnalyses.cpp:33-35` | rederivation | `Solve` builds the graph in its constructor, so every repetition of the outer loop (`Exclusivity.cpp:73-122`) rebuilds a graph that does not depend on the captures | built once → D2 |
| A-02 | `ExclusivityAnalyses.cpp:41-49, 79-84, 313-314` | — | a FIFO `deque` of dense item ids with a `vector<char>` of queued flags | keep the dense flags; the order becomes edge propagation → D2 |
| A-03 | `ExclusivityAnalyses.cpp:52-62` | state | `get` and `held`: a hash lookup per read | a bit read → D2 |
| A-04 | `ExclusivityAnalyses.cpp:64-77` | state | `joinValue`: `try_emplace` then `dependents.find` per propagation | set a bit, walk a CSR row → D2 |
| A-05 | `ExclusivityAnalyses.cpp:86-89` | state | `live(item)`: two hash lookups (function, then block) per run | a bit read → D2 |
| A-06 | `ExclusivityAnalyses.cpp:91-103` | state | `startRun` shares every parameter of a root, followed or not | seeds only on followed values → D2 |
| A-07 | `ExclusivityAnalyses.cpp:105-118` | ladder (cpp) | `switch (item.kind)` over five kinds of our own closed sum | gone with items (X-08); if kinds stay, a `match` (§5.5 D2) → D2 |
| A-08 | `ExclusivityAnalyses.cpp:125-142` | — | `wholeFrom`, `intoPart`: the rules for a flow into a value whole and into a part | keep as the edge rule at the build → D2 |
| A-09 | `ExclusivityAnalyses.cpp:148-190` | state, ladder | `execOp` reruns every op item, though most results are not followed (`:156`); `dyn_cast<CellInitOp>` special-cases memo captures (`:188`) inside the generic transfer | edges from flow edges once, at the build; init-to-capture as anchor edges → D2 |
| A-10 | `ExclusivityAnalyses.cpp:195-210` | budget (product) | `fillCaptures`: per force of the label, per capture, a `find_if` over the init's operands: inits × forces × fields² | one edge per (init operand, anchor) and one per (anchor, capture): inits·fields + forces·fields → D2 |
| A-11 | `ExclusivityAnalyses.cpp:215-226` | rederivation | `execCall` re-decides the target (with a callback) and re-hashes `startRun` per run | the call edge switches once, as a handler → D2 |
| A-12 | `ExclusivityAnalyses.cpp:244-251` | state (C3) | the op successor re-joins every live predecessor's operands on every run: O(N) per run, O(N²) per wide match | per-edge propagation: a rise of one operand writes its one input → D2 |
| A-13 | `ExclusivityAnalyses.cpp:259-269` | ladder | `dyn_cast<MemoRunOp>` special case for captures inside the generic successor transfer | captures as anchor nodes (X-05) → D2 |
| A-14 | `ExclusivityAnalyses.cpp:273-299` | rederivation | `execBlockArgs` re-asks `BranchOpInterface` per predecessor per run (G-06) | → D2 |
| A-15 | `ExclusivityAnalyses.cpp:301-308` | state | `execEntryArgs` shares every entry argument of a non-branch region op, followed or not | seeds on followed values only → D2 |
| A-16 | `ExclusivityAnalyses.cpp:315` | state | `DenseMap<FuncOp, DenseSet<Block*>> liveOf`: a 64-bucket set per running function (≥1 KB each, §5.3 B7) | one reach bit vector → D2 |
| A-17 | `ExclusivityAnalyses.cpp:316` | state | `DenseMap<Value, Sharing> sharing` | → D2 (O-23) |

### 4.5 `lib/Analysis/Ownership/Exclusivity.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| E-01 | `Exclusivity.cpp:69-122` | budget (a measure, cannot fail) | the whole program is solved again while a memo label stops being made (labels only go): labels dropped × program, each time with a new graph (A-01) | made-ness as nodes of the same marking, read after a first quiescence (stratified, §5.7 F6) → D2 |
| E-02 | `Exclusivity.cpp:77-87, 125-133` | rederivation, state | the solve's map is copied into a second per-value map restricted to live blocks | the frozen solution is the solve's own bits → D2 |
| E-03 | `Exclusivity.cpp:88-117` | rederivation, in part essential | which functions run, their live blocks and every call's target are computed again after the solve. The run set is essential: the marking's run bits only rise, so a copy a call later left still has its bit (`:88-93`). The live blocks are not: they depend only on each function's IR. The targets are the solve's own | a BFS over the frozen call edges under the final targets; block reach static per function → D2 |
| E-04 | `Exclusivity.cpp:111` | cpp | `std::holds_alternative<Pair>` to decide whether to record a target | the call's edge class → D2 |
| E-05 | `Exclusivity.cpp:134-144` | state | callers and returns per function into `DenseMap<FuncOp, …>` | vectors by function id → D2 |
| E-06 | `Exclusivity.cpp:147` | dead | `llvm_unreachable("a settled solve returns")` after a loop whose every exit returns | gone with the loop → D2 |
| E-07 | `Exclusivity.cpp:150-153` | state | `of()` hashes | a bit read → D2 |
| E-08 | `Exclusivity.cpp:163-181` | rederivation | `proves` (O-22): `getFlowEdges` per query, `get_if` probes, recursion | → D2 |
| E-09 | `Exclusivity.cpp:183-195` | — | `target`, `callers`: optionals for "not a call of a key" and "callers not all seen" | keep the second (essential: the root's callers are outside); the first by the call's class → D2 |

### 4.6 `lib/Analysis/Ownership/Captures.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-01 | `Captures.cpp:15-53` | rederivation | one whole-program walk per `Exclusivity::solve`, so twice per idr-rc-exclusive, though captures do not depend on the copies | once, in the graph build → D2 |
| C-02 | `Captures.cpp:16-19` | cpp | `std::get_if<role::Label>` on a constructor's role, a question whose answer is thrown away | the data type's typed view (0003's `Body` per kind, lane 01) |
| C-03 | `Captures.cpp:26-34` | — | walks every constant's attribute tree for static memo cells | keep, once (C-01) → D2 |
| C-04 | `Captures.cpp:37-51` | rederivation | `sourceOf` for every result and every region argument of the program, to find used views of memo fields | an anchor query the graph answers (a field read is an edge out of the anchor) → D2 |
| C-05 | `Captures.cpp:60-68` | budget (measure) | `keepMadeIn` drives E-01's outer loop | → D2 |

### 4.7 `lib/Analysis/Ownership/Values.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| V-01 | `Values.cpp:22-26` | ods (type), ladder | `followed` (O-11) | → D6 |
| V-02 | `Values.cpp:28-30` | rederivation | `tracked` and its false comment (O-12) | → D6 |
| V-03 | `Values.cpp:32-35` | — | `isMemoCell` (O-13) | → D6 |
| V-04 | `Values.cpp:37-40` | ladder | `isCountedElement` (O-14) | → D6 |

### 4.8 `lib/Analysis/Ownership/Uses.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| U-01 | `Uses.cpp:30-39` | rederivation | `holders`: sort by `isBeforeInBlock` and unique per query (O-05) | → D5 |
| U-02 | `Uses.cpp:42-45` | rederivation | `usedWithin`: every use × `isProperAncestor` per query | an interval test → D5 |
| U-03 | `Uses.cpp:47-61` | — | one overload per `Point` alternative and `std::visit`: exhaustive, as the skill asks | gone with `Point` → D5 |
| U-04 | `Uses.cpp:75-82` | rederivation | `heldIn` (O-04) | → D5 |
| U-05 | `Uses.cpp:96-104` | ods, rederivation | `decides` (O-06) | → D5 |
| U-06 | `Uses.cpp:113-128` | rederivation | `usedAfter` (O-07) | → D5 |
| U-07 | `Uses.cpp:133-154` | cpp | `whereDies` (O-08); recursion into the regions of a deciding last user | returns points → D5 |
| U-08 | `Uses.cpp:141` | — | `hasTrait<OpTrait::IsTerminator>()`: a trait, as it should be | keep |
| U-09 | `Uses.cpp:172-205` | rederivation | `onlyReads` (O-10) | → D5 |

### 4.9 `lib/Analysis/Ownership/Borrows.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| B-01 | `Borrows.cpp:29-41, 54, 107-153, 161-293, 297-313` | upstream (as used), state | the inference on `DataFlowSolver` as a raw `DataFlowAnalysis`: per-anchor heap states at about 1.5 to 2.9 KB each at the pin (§5.1 A4), uniqued after-call program points never freed (§5.1 A5); the framework contributes storage and a FIFO, no algorithm (§3.1 row 1) | a two-point marking per parameter in the solver layer (D3); or §5.1 Design 1's per-function framework solve with summaries (owner's QA1, QA2) |
| B-02 | `Borrows.cpp:131-149` | — | `HoldingState::print`, a switch the framework's pure virtual requires | goes with B-01 |
| B-03 | `Borrows.cpp:173-177` | state | a state for every parameter of every function, those that hold no reference (`Untracked`) included | no node for a value whose type answers → D3 |
| B-04 | `Borrows.cpp:179-181` | — | reads Reuses' finished sites (`get_if<Value>`): a frozen read, the right composition (§5.7 M7 (ii)) | reads `idr.take` ops in the IR once D4 makes them → D3, D4 |
| B-05 | `Borrows.cpp:182` | — | one walk per function at initialization | keep, as the graph build → D3 |
| B-06 | `Borrows.cpp:194-219` | ladder, rederivation | `dyn_cast<CallOp>`, `<ConOp>`, `<CellInitOp>`, `<OwnGiveOp>`, `isa<ReturnOp>`, `storedBy`, `forwardedValues`: "stored, given to memory, returned, forwarded" restated per op, where `FlowOpInterface` declares the same moves and Exclusivity reads them (`ExclusivityAnalyses.cpp:162-186`) | seeds from the flow edges (a flow into a part, a release to memory, a return, a region forward), one reading of op semantics for both analyses (lane 02 owns the interface) → D3 |
| B-07 | `Borrows.cpp:232-237` | rederivation | per revisit of a call: `symbols.lookup`, `getParentOfType<FuncOp>`, `cycles.together`, `tail::inTailPosition` and `inTailPositionModuloContext` | computed once per call at the build (an edge's class) → D3 |
| B-08 | `Borrows.cpp:233, 239, 258, 261` | state | `getOrCreateFor<HoldingState>(after, …)`: a uniqued program point per call and a dependents set per subscribed state | edges in a CSR graph → D3 |
| B-09 | `Borrows.cpp:253-267` | rederivation | `holds`: `definitionChain` and `tracked` (an `isStatic` chain walk per element) per argument per revisit: O(chain²) | chain edges at the build; static from the grade (D6) → D3 |
| B-10 | `Borrows.cpp:272-288` | state | `own` recurses up the readThrough chain creating a state per chain value | chain values as nodes (or collapsed to the parameter each reaches) → D3 |
| B-11 | `Borrows.cpp:73-103` | cpp, state | `Holding` mixes fixed cases (`Fixed` for the root and quantity 1, `View` for memo cells) with the lattice (`Borrowed` to `Owned`) | a sum whose fixed alternatives carry no bit → D3 |
| B-12 | `Borrows.cpp:301-304` | — | `assert(succeeded(ran))`: the solve cannot fail | goes with B-01 |
| B-13 | `Borrows.cpp:297-313` | state | the result copied into a `DenseMap<FuncOp, SmallVector<Param>>`, then written into signatures by `writeOwnedGrades` | the signature is the one copy (a summary in the type, Q-E2) → D3 |

### 4.10 `lib/Analysis/Ownership/Reuses.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-01 | `Reuses.cpp:27-32, 59-65, 136-151, 232-265` | state | the shadow IR: `Held = variant<Value, TakenField>`, `Virtual {type, uses}`, `moved`, `virtuals`, `takesAt`, `claimed`, kept so later decisions see takes not yet made | decide and rewrite in one walk (D4 (a)), or drop-guided reuse after placement (D4 (b), owner's NQ1) |
| R-02 | `Reuses.cpp:183-191` | rederivation | 9db9813d's guard: erase every use an earlier site moved; it exists because of R-01 (1088 verifier errors on stage 1 without it, 9db9813d's message) | deleted with R-01 → D4 |
| R-03 | `Reuses.cpp:71-86` | rederivation | per match, `usedAfter(box, match)` (U-06) | → D4, D5 |
| R-04 | `Reuses.cpp:94-120` | state, cpp | a second walk for read boxes; `takesAt.lookup` copies a `SmallVector` per op (`:106, 116`) | gone with R-01 → D4 |
| R-05 | `Reuses.cpp:136-151, 160-162, 187` | cpp | `get_if`/`std::get` chains over `Held` | gone with R-01; else one `match` → D4 |
| R-06 | `Reuses.cpp:157-166` | rederivation | `reusable`: `definitionChain` × `isStatic` (each a chain walk), O(chain²) | the static lifetime in the grade (0003) → D6 |
| R-07 | `Reuses.cpp:193-195` | ladder, rederivation | `takesOver = isa<CallOp> || consumes(use)`: a pre-borrow guess that every call takes its arguments over, read through the `consumes` predicate rather than the declared `Free` (`IR/Effects.cpp:86-105`) | with D4 (b) placement's drops say where a box dies; with D4 (a) the guess stays (essential to Lean's order) but reads the declared effect |
| R-08 | `Reuses.cpp:192, 212-213` | — | match by cell size, not by constructor (Koka's rule, §5.10 A4) | keep (essential) |
| R-09 | `Reuses.cpp:208-228` | budget (product), space | `fits`: a forward scan per death point through the block and the regions of every deciding op, with no stop at a call: a token may be held across calls (not frame-limited, §5.10 A5) | with D4 (b), a forward walk with a size-keyed map intersected at joins (§5.10 A4); the stop rule is the owner's (rc-Q3) |
| R-10 | `Reuses.cpp:219` | rederivation | `decides(&op)` per scanned op: O(regions) each (U-05) | → D5 |
| R-11 | `Reuses.cpp:244` | state (W5) | `fieldType` builds graded types on worker threads, through the context uniquer's locks, to type a virtual field | gone with R-01 → D4 |
| R-12 | `Reuses.cpp:272-281` | upstream | per-function work run by our own `parallelForEach` inside a program analysis built from a program pass (`Grades.cpp:45`) | a function pass the pass manager parallelizes (with D4 (a), the decide-and-rewrite pass) → D4 |
| R-13 | `Reuses.cpp:71-201` with `Transforms/Ownership/Reshape.cpp:69-109, 260-282` | rederivation (cross-lane) | the "take apart where it dies" decision made twice, before and after the rewrite, with different filters and rules | one decider of takes (with lane 08) → D4 |

### 4.11 Outside the files, read for this subsystem (other lanes' to fix)

| ID | file:line | category | what | owner |
| --- | --- | --- | --- | --- |
| Z-01 | `Transforms/Ownership/Exclusive.cpp:39, 44` | rederivation | exclusivity solved twice per pass, each solve building `Calls`, `Captures` and a graph | lane 08, with D2 |
| Z-02 | `IR/Verify/Linearity.cpp:27-33` | rederivation | `verify::alternatives`: O(regions) per call, read by `decides` | lanes 01/03, with D5 |
| Z-03 | `IR/Verify/Linearity.cpp:41-58` | state | a per-function pre-order numbering already exists, private to the verifier | lane 05 (Q-llvm-3), shared with D5 |
| Z-04 | `IR/Grades.cpp:253-260` | state | `fieldType` makes types; harmless where it builds real IR, not from analyses (R-11) | lane 01 |

## 5. Target design

What the subsystem becomes, applying the proposal. *Conjecture* as design;
every "today" is *read* (§4's lines). No Idris code is in this subsystem;
nothing here changes the Idris side (category *idris*: none).

### D1. A dead-end terminator is no predecessor (fix first, alone)

- **Representation.** In the graph build, a block of a branch op's region
  whose terminator is neither a `RegionBranchTerminatorOpInterface` nor a
  `BranchOpInterface` (in our IR exactly `ub.unreachable`, the end of every
  crash case: `IR/OpsMatch.cpp:32` admits only `idr.yield` or
  `ub.unreachable` as a case region's end) transfers control nowhere, so
  it contributes no predecessor. `SuccessorSources::unknownFrom`, its
  copy into every successor (`ExclusivityGraph.cpp:208-216, 222`) and the
  share in `execSuccessor` (`ExclusivityAnalyses.cpp:236-243`) go.
- **Why first.** Today a live crash case shares the results of its match
  and every case's arguments (G-09): every memo force and every
  non-covering function. The rule predates e96bb991 (its diff shows the
  same branch). It is a precision loss in the analysis the in-place
  refusal rests on (idr-demand reads the grades it writes,
  `Passes.td:612-624`), so it may refuse programs and add count tests;
  fixing it can only grade more values exclusive, never fewer (a dead end
  gives nothing), which is sound. It is also e96bb991's last product of
  two quantities (successors × crash blocks).
- **Test, before the fix** (testing-by-search, behaviour only): a match
  with one crash case and one case yielding a fresh cell, whose result
  flows to an in-place consumer; expect `!idr.excl` on the result and no
  count test in the lowered take; and the same through a memo force. The
  fixture fails today if the conjecture holds.
- **The line.** State made unrepresentable: a terminator that never
  returns standing as a predecessor whose operands are unknown; branch
  deleted: `unknownFrom` and its share.

### D2. Exclusivity: one honest marking in the solver layer

- **Representation.**
  - *Nodes*, numbered densely at the build, by an extractor run per
    function in parallel with a prefix sum of each function's base
    (§5.6 Shape G, §5.7 L2): a node per **followed** value only (the
    type filter of D6: a value whose type answers the question has no
    node; §5.6 Design 2), per function (run), per memo label (made), per
    memo label field (an anchor, `FlowAnchor::Field`, as the label solve
    already keys its sets, `IR/FlowEdges.h:88-93`; §5.9 B5), and per call
    of a grade key (its target).
  - *Block reach is static.* `liveBlocksOf` depends only on the
    function's IR (`ExclusivityGraph.cpp:63-96`: every region an op may
    enter, every block a terminator names), so a block's reach is a
    per-function constant computed once at the build; the only dynamic
    liveness is a function's run bit. A writer in a statically
    unreachable block gets no edge.
  - *Edges*, in compressed rows, read once from the IR: from each op's
    flow edges (a flow whole or into a part, a fresh value, a constant,
    with `wholeFrom`/`intoPart`'s rules, `ExclusivityAnalyses.cpp:125-142`,
    decided at the build), from each branch op's successor table
    (e96bb991's, kept: an edge per forwarded operand and input), from
    calls (argument to parameter, return operand to result; a key's call
    has one edge set per target), from inits to anchors and anchors to
    force captures. Each edge's gate is its function's run bit, and an
    anchor-to-capture edge also its label's made bit.
  - *Bits*: shared per value node, run per function, made per label, and
    a target per key call that flips from the copy to the original at
    most once (`ExclusivityAnalyses.cpp:7-8` already argues this).
  - *Propagation* as cells with handlers (§5.9 B4) or SCCP's edges
    (§5.3 C2): a node that rises walks its row once; a gated edge whose
    gate is down waits on the gate. Each bit rises once, each edge fires
    at most once per rise: O(V_followed + E). The op successor's re-join
    of all N predecessors (A-12) cannot be written: an input is joined by
    the one edge whose operand rose.
  - *Made labels as a stratum* (§5.7 F6, M7: a complement read after
    what it complements is complete). First the marking with captures of
    labels not yet made left unseeded and made bits rising as a maker's
    block comes to run; at quiescence, every label still unmade seeds its
    captures shared, and the marking continues. Sharing only rises, so
    continuing from the first state reaches the second stratum's least
    fixpoint. Precision as today's: a label dropped stays dropped
    ("each solve keeps the labels the one before found made … Labels only
    ever go", `Exclusivity.cpp:69-72`), as a call sent off a copy stays
    off it ("may be less precise than one solved afresh, never unsound",
    `:41-43`). One graph, no outer re-solve (E-01, A-01).
  - *What runs, finally.* Run bits only rise, so a copy a call left
    still has its bit (today's reason for E-03's second pass,
    `Exclusivity.cpp:88-93`). That pass stays, essential, as a
    reachability over the frozen call edges under the final targets: a
    BFS over function ids, no IR walk and no `liveBlocksOf`.
  - *The answer* is a frozen solution: the shared bits, the final run
    bits, a target per key call, callers and returns per function id;
    cached in the `AnalysisManager` on the program, one instance before
    the copies and one with them (the copies as an analysis input that
    specialization produces), and read by the commit as its own pass
    with `getCachedParentAnalysis` (0003's "Exclusivity is no
    analysis"). `proves` reads a bit; the quantity-change rule is the
    whole-flow edge the graph already has, and a value the commit makes
    after the solve is graded by the op that makes it (lane 08).
- **Where.** The solver layer (§5.1 Design 3, §5.3 S1, D2's ruling),
  with a header stating what upstream lacks: a whole-program two-point
  marking with gated edges and switching call targets, across both
  directions of the call graph; and the measurement: 627 GB on the
  framework (ffa91113), today's hash-map marking about 100 to 170 B per
  read value (§2.3, *conjecture*), the target about one bit per followed
  value and 4 B per edge.
- **Deletes.** `Item` and its kinds and switch; `Graph::dependents`,
  `itemsOf`; `Solve` and its `sharing`, `liveOf`, deque; `solveOnce`;
  `SuccessorSources::from` as data re-joined per run (it becomes edges);
  `Captures` (folded into anchors) and `fillCaptures`' `find_if`;
  `liveBlocksOf` as a per-solve walk; `Sharing::Unknown`; the five maps of
  `Exclusivity`; the outer loop and its unreachable; `Calls::target`'s
  callback; the `holds_alternative`.
- **The line.** State made unrepresentable: a fact for a value whose
  type already answers; a second copy of the answer; a re-join of an
  input over every predecessor; a graph rebuilt per stratum. Branch
  deleted: the item-kind switch and every per-run interface query.
  Essential, kept: the two directions, the target switch and the made
  stratum, which the problem has.

### D3. Borrows: a two-point marking per parameter

- **Representation.** Nodes: each parameter whose type holds references
  and whose case is inferred (not the root's, not quantity 1, not a memo
  cell: those are constants of the sum, no node), and each tracked value
  on a readThrough chain that a rule touches. Edges: from a chain value
  to what it was read from (`own` recurses that way, `Borrows.cpp:272-288`);
  from a callee's parameter to each caller's argument chain (`:239-240`);
  inside a cycle of calls, from each chain element of a tail call's
  argument up to its first decisive element to the callee's parameter
  (`holds`, `:253-267`, is a monotone disjunction over that prefix).
  Seeds: the local reasons, read from the op's flow edges (a flow into a
  part: stored in a constructor or a cell; a release into memory: a give
  or a store; a return; a region forward), the same declaration
  exclusivity reads, and the reuse takes. Tail position and cycle
  membership are computed once per call at the build. The marking is
  D2's template without gates.
- **Upstream first, honestly.** The framework adds nothing here today
  (§3.1 row 1): no sparse or dense base, program points only as
  subscription keys. The upstream form §5.1 proposes would be a
  per-function sparse backward analysis reading callees' parameter
  summaries in `visitExternalCall`, with our summary layer iterating each
  SCC (Lean's, §5.10 B2): the owner's QA1/QA2. The evidence (§6) favours
  the marking for its size (a bit per parameter), but both remove
  today's per-anchor states and per-call program points.
- **The answer** is the signatures: `writeOwnedGrades` already writes
  it there (`Signatures.cpp:22-47`), so the `paramsOf` map is a second
  copy read once (B-13); the marking writes the grades and keeps
  `numBorrowed` as the statistic.
- **Deletes.** `HoldingState`, `Inference`, `DataFlowSolver` in this
  subsystem; `Holding` and its switch to `Param`; the op ladder (B-06);
  the per-revisit lookups (B-07); the chain walks per revisit (B-09).
- **The line.** State made unrepresentable: a solver state for a
  parameter that holds no reference, a program point per call. Branch
  deleted: the op ladder restating the flow edges. Essential, kept: the
  cycle rule (a tail call within a cycle must not be followed by a drop)
  and the fixed cases (root, quantity 1, memo cell).

### D4. Reuses: no shadow IR

Two forms; the choice is the owner's (NQ1, §6).
- **(a) Decide and rewrite in one walk (keeps Lean's order).** A
  function pass, before borrow inference, decides each site in today's
  order and makes its `idr.take` and the `idr.cell.recycle` at once,
  with 0003's typed token (`!idr.token<!idr.box<T>, @C>`), so every later
  decision reads real fields and real uses, and Borrows reads takes from
  the IR (a take of a parameter's chain owns it, as today). The
  `takesOver` guess (any call takes its arguments over, `Reuses.cpp:193-195`)
  stays: it is essential to deciding reuse before borrows. It needs the
  stage machinery to admit a take before grading (lanes 01, 08).
- **(b) Drop-guided reuse after placement (Koka's order).** Reuse is a
  forward walk per function after placement, turning a drop of a
  deconstructed box into a token and a same-size `cell.new` into a
  `cell.recycle`, the available tokens intersected at joins (§5.10 A4);
  frame-limited if tokens do not cross calls. Reuses as an analysis is
  deleted; borrow inference no longer reads reuse, so a parameter taken
  apart only for its cell stays borrowed unless a forced rule owns it
  (a precision trade: today a take wins over a borrow).
- Either way, one decider of "take apart where it dies" (R-13), shared
  with lane 08's Reshape.
- **Deletes.** (a): `Held`, `TakenField`, `Virtual`, `moved`, `virtuals`,
  `takesAt`, `claimed`, `Site`, the `Reuses` class and its
  `DenseMapInfo<TakenField>`, 9db9813d's guard, the `fieldType` calls
  from workers, the analysis's own `parallelForEach`. (b): all of that,
  plus `Decider`, `fits` and `whereDies`' `takesOver`.
- **The line.** (a) state made unrepresentable: a decision kept beside
  the IR that later decisions must reconcile; check deleted: the
  moved-use filter. (b) also: the analysis itself, which becomes the
  rewrite, and the guess that every call takes its arguments over.

### D5. The vocabulary on a per-function scope

- **Representation.** One scope per function, built once (§5.7 L2's
  `Scope`; the verifier's `Numbering`, `IR/Verify/Linearity.cpp:41-58`,
  is the same idea and should be the same structure, Q-llvm-3): every op
  and every **block start** in pre-order (a block start is its own entry:
  a sentinel, so "the start of a block" and "after an op" are one kind of
  coordinate, and `Point`'s two alternatives become one integer, EWD831's
  half-open range from a position on); `end[i]` closing each op's
  subtree; each value's uses as sorted positions; a `decides` bit per op,
  computed once from the interfaces at the boundary (or declared in ODS:
  lanes 02 and 03; §2's recalled `Decides` trait does not exist).
- **Queries.** `heldIn`, `usersIn`, `usedWithin`, `usedAfter`,
  `onlyReads` become range tests and binary searches on positions;
  `whereDies` returns its points; `decides` reads a bit. A function
  analysis in the `AnalysisManager`, valid while a pass plans before it
  rewrites (lane 08's placement does: 4108916a, "plans every value on
  the function as it came").
- **Deletes.** `BlockStart`, `After`, `Point`'s variant and both
  `DenseMapInfo`s; `holders`' sort and unique per query; every ancestor
  walk per query; `decides`' interface calls per query (and with them
  the O(regions) term in Reuses' scan and in placement).
- **The line.** Branch deleted: per-query ancestor walks and interface
  calls. Check moved to a boundary: the order of uses and `decides`,
  once per function. Special case removed: a block's start beside an
  op's end (a sentinel per block makes them one coordinate).

### D6. Value classes as type facts

- `followed`, `isMemoCell` and `holdsReferences` as methods of the type
  interface `ValueFacts`, computed when the type is built (§5.8 T7;
  lane 01). `tracked` becomes `holdsReferences(type) && lifetime(type) !=
  static` once the static lifetime is in the grade (0003; lanes 01, 08),
  so neither Borrows nor Reuses walks a chain. `isCountedElement` becomes
  the crossing op of 0003 ("the owned stage reads upstream's buffer ops
  by name"; lanes 08, 03). `Values.cpp` is deleted.
- **The line.** State made unrepresentable: one value classed two ways
  by two readers. Branch deleted: the type ladder and every chain walk
  for "static".

### D7. The C++ shape (cross-cutting)

- One marking template over a graph concept (§5.5 D3, §5.3 S1),
  instantiated for exclusivity (gated), borrows (plain) and lane 08's
  idr-rc-stack markings (plain): §5.10 M6's "three markings, one honest
  solver layer". idr-rc-stack's hand-written engine since b8301ebe (dense
  ids, adjacency rows, a `BitVector` mark, `Stack.cpp:197-208, 262-268`)
  is the nearer starting point; exclusivity's adds gates and the target
  switch to it. Each instantiation explicit, in its own unit (Q-llvm-1).
- Dense typed ids (`Id<Tag>`, an index vector refusing a raw integer,
  §5.5 D3) for values, functions, labels and calls; the edge classes are
  data in the rows, so no `switch` on a kind and no `Item` with
  half-used fields.
- No `get_if` chain survives: `Held` goes with D4; `Callee` becomes the
  call's edge class; `FlowEdges` is visited once, exhaustively, at the
  build.

### Order and dependencies

1. **D1** alone, with its test: no dependency.
2. **D6**: lane 01 (`ValueFacts`, the static lifetime of 0003); lane 08
   (the crossing op).
3. **D5**: lane 05 and §8.4 (numbering: Q-llvm-3, QL1); lane 08
   (placement reads it).
4. **D2**: the solver layer's skeleton and its marking template (lanes
   05, 13); D6 for the domain; lane 02 (the flow edges as the one
   declaration of moves); lane 08 (the commit as a pass; grade copies as
   the second analysis's input).
5. **D3**: D2's template; lane 05's program graph (cycles of calls);
   lane 02 (flow edges for the seeds).
6. **D4**: lane 08 (pipeline order, Reshape's takes, the take before
   grading); the owner's NQ1.

## 6. Evidence for the owner's questions

What our code says; no answer. All *read* unless marked.

**rc-Q1 (borrow inference).**
- We infer borrows over the whole program today: every parameter that
  holds references starts borrowed except the root's (owned: its caller
  is outside), quantity 1 (owned: Idris proved one use) and memo cells
  (a view, never owned) (`Borrows.cpp:22-27, 76-86`); it becomes owned
  when it or a field read from it is taken apart, passed to an owned
  parameter, stored, returned or forwarded, or passed owned by a tail
  call from its own cycle of calls (`:7-21`). These are Lean's forced and
  heuristic reasons mixed: the tail-call rule and the reuse-target rule
  are correctness (Lean's "forced", §5.10 B2); there is no user
  annotation and no frame-limited restriction (Koka's concern, §5.10 A5).
- The order makes a take win over a borrow: reuse is decided first and
  every parameter a site takes apart is owned (`Borrows.cpp:43-44,
  179-181`; `Grades.cpp:45-48`).
- Cost: one framework state per parameter of the program and per chain
  value, a program point per call (B-01, B-03, B-08). The statistic
  `numBorrowed` exists (`Grades.cpp:48`); no stage-1 value is recorded.
- shareTainted's one-level taint across calls (`Transforms/Ownership/Share.cpp:27-47`)
  relies on a borrowed parameter never being dup'd in its own function,
  which Borrows' rules guarantee (`Borrows.cpp:3-5`: "a parameter the
  function never needs a reference of its own for is borrowed")
  (*conjecture* on the reliance): restricting or dropping inference
  changes what Share must do.

**rc-Q2 (how much exclusivity is static).**
- R1's run-time fallback exists: a take of a value not graded exclusive
  tests the count, a recycle tests the token (`Exclusivity.cpp:3-5`;
  `audits/bugs.md:45-50`: `idris_rt_is_unique` per take).
- R2 exists in a narrow form, inside counting and not in the optimizer:
  `specializeOnGrade` makes one copy per key function, taking every
  followed parameter exclusive, when some live call gives exclusive
  values while another shares (`Transforms/Ownership/Specialize.cpp:52-131`),
  and the second solve sends each call to the copy or the original
  (`ExclusivityGraph.cpp:50-61`). Copies are bounded by functions (one
  key per function, `copyName`, `Specialize.cpp:72-83`); no budget.
- Static exclusivity bears on acceptance: idr-demand refuses
  `unsupported (uniqueness)` where a call passes a shared value to a
  parameter its function rebuilds in place (`Passes.td:612-624`). So the
  analysis's precision is part of which programs are accepted; G-09 (a
  crash case shares a match's results) is a precision loss on exactly
  that path (*conjecture* on its reach at stage 1). An open entry
  records a lost exclusive copy (`audits/bugs.md:56-66`,
  `@Gen.reverseOnto.spec.*.excl.*`), cause not found.

**QA1 (patch U1 first; P1 or P2).**
- Borrows is this subsystem's one framework user; its state is per
  parameter and per chain value plus a program point per call, about
  1.5 to 2.9 KB each at the pin (§5.1 A4). U1 would cut it about
  fifteenfold; the framework still adds no algorithm here (§3.1 row 1).
- Exclusivity left the framework at ffa91113. Its removed form needed
  the dead-code baseline and a constant analysis rigged to know nothing
  (`NoConstants`), and that coupling caused two bugs before memory did
  (4108916a, e8e38bd7; §3.1 row 3). U1 removes the memory wall, not the
  coupling (U4 is upstream's, open).

**QA2 (per-function with summaries, or whole program).**
- Exclusivity is two-directional (parameters from callers, results from
  returns) and context-sensitive (a key's calls switch target on their
  arguments' sharing); a per-function form needs IFDS-style summaries
  (result sharing as a function of parameter sharing) or loses precision
  at every call (§3.1 row 5).
- Borrows is bottom-up (an owned callee parameter owns the caller's
  argument) with one rule inside a cycle of calls (tail calls): Lean's
  per-SCC shape fits it exactly (§5.10 B2).
- Reuses is per function already (`Reuses.cpp:272-281`); the vocabulary
  is per function.

**QA3 (`remove-dead-values`).** No evidence in this subsystem.

**QA4 (one state representation for all our solvers).**
- Today's states here: `DenseMap<Value, …>` (exclusivity, twice),
  `DenseMap<FuncOp, …>` (all three results), a `DenseSet<Block*>` per
  running function, `DenseMap<Point, …>` and `DenseMap<OpOperand*, …>`
  (Reuses), framework states (Borrows), and one dense structure, the
  item vector with its `vector<char>` of queued flags
  (`ExclusivityAnalyses.cpp:313`). Every one of them maps onto dense
  per-function numbering plus vectors by function id; the verifier
  already numbers each function's ops in pre-order
  (`IR/Verify/Linearity.cpp:41-58`).
- The two markings (exclusivity, borrows) and lane 08's idr-rc-stack
  share one algorithm (a monotone two-point marking, §5.10 M6);
  exclusivity alone needs gates.

**QL1 (a scoped array view as the solver's input).**
- Uses' queries are what such a view answers by integer compares
  (D5); exclusivity's graph is already an extraction built once per
  solve (`ExclusivityGraph.cpp`), but over IR pointers. Placement (lane
  08) plans before it rewrites (4108916a), so a scope built at plan time
  stays valid for its queries.

**QL2 (SSI as a dialect rule).**
- The owned stage already gives exclusivity SSI: every reference
  duplicated by `idr.dup` (`Exclusivity.cpp:11-13`), every forgotten
  exclusivity an `idr.share` that defines a new value (shareTainted
  inserts one at each consuming use of a tainted value,
  `Share.cpp:48-60`), every take, recycle and give a new value. Neither
  exclusivity nor Borrows keeps a fact per program point (§3.1 rows 13,
  14). The per-point facts here are deaths (liveness), which SSI does
  not turn into names.
- The rule's case-region half holds already: a match's case region binds
  the fields as block arguments, and the solve shares them as part reads
  (`ExclusivityAnalyses.cpp:254-270`).

**Q-llvm-3 (numbering).**
- Exclusivity numbers its items densely (`unsigned` ids into
  `std::vector<Item>`) but keys values, blocks and functions by pointer;
  Reuses numbers sites by position (`TakenField::site`); the verifier
  numbers ops in pre-order per function (`IR/Verify/Linearity.cpp:41-58`).
  Three numberings, none shared. D5 and D2 both need one per function
  (values, ops, block starts) and one per program (functions).

**Q-O2 (the model: a constraint-generating abstract interpreter).**
- Exclusivity and Borrows are monotone facts per name: MLton's cells fit
  them. Exclusivity's current marking is between the two models: one
  fact per name, but writer items re-run instead of handlers firing per
  edge (A-12). Reuses and the vocabulary are not cell domains (a
  decision at points; liveness queries).

**Related questions the code bears on.**
- **Q-E2 / Q-O3 (summaries in types):** both interprocedural answers
  of this subsystem are written into function types already
  (`Signatures.cpp:22-75`), checked after every pass by the owned
  verifier; the tables (`paramsOf`, `Exclusivity`'s maps) are second
  copies read once.
- **Q-llvm-2 / Q-E3 (budgets):** no budget here; the one loop states its
  end by a measure and cannot fail (§3.2, W-E5). The analysis a refusal
  rests on (exclusivity) has no cap.
- **rc-Q3 (a space guarantee):** reuse runs before insertion (Lean's
  order) and a token may be held across calls (`Reuses.cpp:208-228`);
  takes refuse a consuming last use (`Uses.cpp:141-143`), which removes
  Lean's example B; unrestricted borrowing (above). Neither
  garbage-free nor frame-limited is a property today.
- **DD-Q6 (borrows as regions or lifetimes in types):** a borrowed
  parameter is a view grade whose lifetime is the call
  (`Ownership.h:17-24`); `idr.borrow` gives a view of an owned value for
  as long as it lives; nothing in this subsystem reads a lifetime
  parameter except "the frame's" (`Exclusivity.cpp:163-165`,
  `Reuses.cpp:158`).

**New questions for the owner.**
- **NQ1. Reuse before or after counting.** Keep Lean's order (reuse
  decided before borrow inference and placement, so a take wins over a
  borrow and every call is guessed to take its arguments over), with the
  decision made as IR at once (D4 (a)); or take Koka's (drop-guided
  reuse after placement, so a borrow wins, reuse becomes the rewrite and
  can be frame-limited) (D4 (b))? Evidence: `Reuses.cpp:193-195`,
  `Borrows.cpp:179-181`, `Grades.cpp:45-66`, 9db9813d.
- **NQ2. What specifies the uniqueness refusal.** idr-demand refuses on
  the grades exclusivity writes; a precision fix (D1) or a redesign
  (D2) changes which programs pass. Is `unsupported (uniqueness)`
  defined by the analysis's answer, so that a more precise analysis
  admits more programs (AGENTS.md's "on a total analysis"), or by a
  declarative rule the analysis must decide exactly, with a test of that
  rule's boundary?
- **NQ3. Grade copies' home.** Grade specialization (one copy per key,
  inside idr-rc-exclusive) and the optimizer's specialization (each
  function once, bottom-up) are two specializers. Should the grade be a
  key of the one specializer (§5.10 R2's form), or stay where exclusivity
  is solved, after optimization?

## 7. Deletion list

By file and symbol, with the change that deletes it.

- `include/idr/Analysis/Ownership.h`
  - `BlockStart`, `After`, `Point`, their `DenseMapInfo`s; `blockOf`,
    `firstAt`, `pointBefore`, `definedAt` as point translators (D5).
  - `heldIn`, `usersIn` ×2, `decides`, `usedAfter`, `whereDies` ×2,
    `onlyReads` ×2 as IR walks (D5: they become queries of the scope).
  - `followed`, `tracked`, `isMemoCell`, `isCountedElement` (D6).
  - `Copies` as a struct passed by hand (D2: an analysis input).
  - `Reuses`, `Reuses::TakenField`, `Reuses::Site`,
    `DenseMapInfo<Reuses::TakenField>` (D4).
  - `Borrows::Param`, `Borrows::paramsOf`, `Borrows::params` (D3: the
    signatures hold the answer).
  - `Exclusivity::Sharing::Unknown`; `Exclusivity`'s `sharing`,
    `liveBlocks`, `targets`, `callersOf`, `returnsOf`; the static `solve`
    (D2).
  - `#include "mlir/IR/SymbolTable.h"` (O-27).
- `include/idr/Analysis/Ownership/ExclusivityDetail.h`: the whole header
  (D2): `Calls` (its callee table becomes call edges), `Captures`,
  `solveOnce`, `liveBlocksOf`, `Item`, `SuccessorSources`, `Graph`.
- `lib/Analysis/Ownership/ExclusivityAnalyses.cpp`: the whole file (D2):
  `Solve`, its kinds' `exec*`, `fillCaptures`.
- `lib/Analysis/Ownership/ExclusivityGraph.cpp`: the whole file (D2):
  `Calls`, `liveBlocksOf`, `Graph::scan*`; `scanBranch`'s successor
  table survives as the extractor's handling of branch ops, without
  `unknownFrom` (D1) or `byRegion` (G-08).
- `lib/Analysis/Ownership/Exclusivity.cpp`: the outer loop, `record`, the
  post-solve walks, `of`, `proves`'s recursion, `target`, `callers`; the
  unreachable (D2).
- `lib/Analysis/Ownership/Captures.cpp`: the whole file (D2: anchors).
- `lib/Analysis/Ownership/Values.cpp`: the whole file (D6).
- `lib/Analysis/Ownership/Uses.cpp`: `holders`, `usedWithin`, the
  `Point` overloads, and every function's walk (D5).
- `lib/Analysis/Ownership/Borrows.cpp`: `HoldingState`, `Inference`,
  `Holding`, `startOf`, `paramOf`, `ownsItself`, `isParameter`, the
  `DataFlowSolver` (D3).
- `lib/Analysis/Ownership/Reuses.cpp`: `Held`, `Virtual`, `Decider`'s
  shadow state (`claimed`, `moved`, `virtuals`, `takesAt`, `boxes`), 9db9813d's
  guard, `typeOf`, `usesOf`, the `fieldType` calls, the
  `parallelForEach` constructor (D4 (a)); and `Decider` and `fits` as
  well (D4 (b)).
- In the solve's readers (lane 08, with D2/D4): the solve twice
  (`Exclusive.cpp:39, 44`), `createRcCommit`'s constructor argument
  (`Commit.cpp:156-179`), `reuseAt`'s reading of `Site`s (`Reuse.cpp:37-60`).

## 8. Risks, unknowns, measurements needed

**Risks.**
- *Acceptance moves.* Exclusivity is the analysis `unsupported
  (uniqueness)` rests on. D1 and D2 change its precision, hence the set
  of accepted programs, and the counts tests expect. D1 can only accept
  more and count less (a dead end gives nothing); D2's stratified made
  labels and gated edges are meant to compute today's answer, which needs
  a test that compares the two on the corpus before the old one goes
  (there is no oracle: the committed expectations are the spec). NQ2.
- *Soundness of D1's rule* rests on every terminator of our region ops
  being one of: a region-branch terminator, a branch, or a dead end.
  `IR/OpsMatch.cpp:32` holds it for matches; scf and linalg terminators
  implement the interface. A future op with a terminator that returns to
  its parent without the interface would be read as a dead end; the
  build should refuse such an op loudly (an internal error naming it)
  rather than guess.
- *Run bits only rise.* D2 must keep today's second pass over the final
  targets (E-03's essential half), or a copy every call left would be
  graded as if it ran.
- *Values made after the solve.* `proves` recurses today because the
  commit asks about values it made (O-22); D2 assumes lane 08 grades
  those at creation. If not, the bit lookup needs the recursion back.
- *Borrows and Share move together.* shareTainted's one-level taint
  across calls (`Share.cpp:27-47`) leans on Borrows' rule that a borrowed
  parameter is never dup'd in its own function (*conjecture*, §6 rc-Q1);
  D3 and any answer to rc-Q1 must keep that invariant or widen the taint.
- *D4 (a) needs a take before grading.* Today a take exists only in the
  graded stage (`Borrows.cpp:43-44`: "not ops yet"); whether the stage
  verifier admits it earlier is lanes 01 and 08's.
- *C3's quadratic is unmeasured at stage 1.* The op successor re-join
  (A-12) may or may not bite on the real module; e96bb991's 1.3 s for a
  generated 20,000-case match is the one number.

**Unknowns.**
- Whether G-09 changes any committed expectation (the 9 tests that name
  an `excl` grade; `tests/rc-capture-unmade` has a crash case but checks
  only a capture of an unmade label).
- How many values are followed against how many have state today
  (W-E2), how many items and edges the graph holds, how many blocks with
  arguments exist inside our structured IR (G-05), how many functions
  run, how many memo labels and makers there are.
- Borrows' state count (parameters, chain values, calls) and time.

**Measurements needed** (a release `idris-mlir` on the stage-1 module;
none can be run in this checkout):
- Time and peak footprint of idr-rc-grades and idr-rc-exclusive:
  `idris-mlir … --mlir-timing --profile-actions-to=<file>` (the action
  profiler of 0001's method) and the process's `phys_footprint` (§5.11
  A2) around each pass.
- The graph's size: a statistic per solve for items, successor sources,
  dependents' entries, `sharing` entries and the number of outer-loop
  repetitions; and per Borrows run, its states and program points. These
  are one `Statistic` each in the passes (`Passes.td` holds
  `numExclusive`, `numBorrowed`, `numTakes`, `numReuses` already).
- The followed fraction: values whose type `followed` accepts, over all
  values with state.
- The widest matches: case counts and crash cases per match, the number
  of item runs of their op successors (the C3 term).
- The effect of D1: `numExclusive` and the count of `idris_rt_is_unique`
  calls in the lowered module before and after.

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (all of it, the
  verbatim source document included); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole, lines 1-11141, in chunks: §0-§4,
  §5.1-§5.11 every lane, §6-§9); `proposals/0003-facts-once.md` (whole);
  `audits/p0/README.md`.
- The subsystem, every line: `foreign/idr/include/idr/Analysis/Ownership.h`,
  `foreign/idr/include/idr/Analysis/Ownership/ExclusivityDetail.h`,
  `foreign/idr/lib/Analysis/Ownership/{Borrows,Captures,Exclusivity,ExclusivityAnalyses,ExclusivityGraph,Reuses,Uses,Values}.cpp`.
- Its readers and neighbours, in the parts cited:
  `foreign/idr/lib/Transforms/Ownership/{Exclusive,Grades,Signatures,Specialize,Share,Reshape,Placement,Commit,Reuse,Take,Classes}.cpp`
  (the call sites), `foreign/idr/lib/Transforms/Pipeline.cpp:30-60`,
  `foreign/idr/include/idr/Transforms/Passes.td:530-626`,
  `foreign/idr/include/idr/IR/{Ownership,Flow,FlowEdges,Grades}.h`,
  `foreign/idr/include/idr/IR/{IdrMatchOps,IdrCheckOps}.td` (match and
  crash), `foreign/idr/lib/IR/{FlowOps,Effects,Grades,OpsMatch}.cpp` (the
  cited functions), `foreign/idr/lib/IR/Verify/{Linearity,Uses}.cpp`
  (`alternatives`, `Numbering`, `viewRoot`),
  `foreign/idr/include/idr/IR/Layout.h` (`Layouts`),
  `foreign/idr/unittests/` (listing), `tests/rc-capture-unmade/rc-capture-unmade.mlir`,
  `tests/` (listing and greps), `audits/bugs.md:40-75`,
  `proposals/0001-self-host.md:60-110`.
- Pinned upstream: `.toolchain/llvm-project/mlir/include/mlir/Dialect/UB/IR/UBOps.td:73-87`
  (`ub.unreachable`: `Terminator` only).
- History: `git log --oneline` over the subsystem's paths (20 commits);
  `git show` of e96bb991 (message and full diff of the three files),
  ffa91113 (message, stats, and the removed `ExclusivityAnalyses.cpp`
  in full), 9db9813d (message and the `Reuses.cpp` hunk), e8e38bd7,
  c4d38e9b, d40d3c32, 4108916a (messages and stats).
- Commands for every count are given where the count is.
