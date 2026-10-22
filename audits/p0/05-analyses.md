<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane analyses: the analyses, the solver layer's inventory, the rederivation chains

*Written (2026-10-21), at e96bb991 plus the working tree's uncommitted
proposal. Scope: `foreign/idr/lib/Analysis/{BindingTimes,CallCycles,
Constants,Effects,Identities,IdentitiesRebuilds,IdentitiesRecord,Inline,
Ranges,Recursion}.cpp`, `include/idr/Analysis/` (all but Ownership and
Labels), `lib/Support/Scc.cpp`; every `DataFlowSolver`/`dataflow::` user;
every `getAnalysis`, `getCachedAnalysis`, `markAnalysesPreserved` and
`AnalysisManager` use; the inventory of every analysis in the tree; the
cross-cutting rederivation chains.*

## 1. Reading notes

### §1-§4

- §1: "If we really need our own solvers ... be honest, and refactor it
  out into its own code where we can better understand how they compose
  and are threaded." The solver layer is this lane's inventory target.
- §2 brief: `lib/Analysis` 3,564 lines; tokens `getAnalysis<`,
  `getCachedAnalysis`, `AnalysisManager` 105; `dataflow::` or
  `DataFlowSolver` 44; `worklist` 87; `DenseMap<`/`DenseSet<` 212. The
  list of ours: BindingTimes, CallCycles, Constants, Effects, Identities
  (3 files), Inline, Labels/LabelSites, Ranges, Recursion; Ownership/*;
  more inside passes (Stack's lifetime inference, Tail/Frames' plan,
  Optimize's demand); `Support/Scc.cpp`. Still on the framework:
  `Analysis/Constants`, `Analysis/Ranges`, `Ownership/Borrows`,
  `Narrow/{Lanes,Copy}`, `Tail/Returned`, `Effects/Constants`.
- §3 walls bearing on analyses: ffa91113 (exclusivity on the framework,
  627 GB), 16005000 (upstream `remove-dead-values` 52 GB; also
  "pipeline no longer solves liveness over the whole program"),
  e96bb991 (interface query per pair of terminator and successor),
  b8301ebe (rc-stack bit vector per value copied per edge). Conjecture:
  the framework failed on its state model, not its algorithm.
- §4: order of preference upstream, upstream patched, solver layer with
  a header naming what upstream lacks plus the measurement; "a fact
  recomputed is cached (`AnalysisManager`) or carried in a type";
  "Threaded by construction ... every analysis and solver states what it
  reads, what it writes, and what may run beside it".

### §5.1 mlir-analysis (the lane this document applies most)

- A1-A2 (read): solver = FIFO worklist + pending set, a `StorageUniquer`
  for program points, `DenseMap<LatticeAnchor, DenseMap<TypeID,
  unique_ptr<AnalysisState>>>`, equivalence classes per state type; no
  per-scope arena; `eraseState` per anchor.
- A3: `DataFlowConfig` has only `interprocedural`; silently off unless
  top is a `SymbolTable`.
- A4 (measured): fixed cost per state about 2.9 KB (two 64-bucket
  tables); P1 (`SmallDenseMap<TypeID,...,2>`, `SetVector<...,4>`) cuts
  to about 0.2 KB; P2 flat map + bump allocator 148 B; ours one bit in a
  `BitVector` 0.13 B per value.
- A5: uniquer runs threaded in a single-threaded solver
  (`disableMultithreading` is one line).
- A6: the one supported scope is per function (top = a function, not a
  symbol table): calls go to `visitExternalCall`, summaries through
  `visitExternalCall`/`visitCallableOperation` overrides reading a
  client table. No per-SCC solve, no summary notion.
- A7: `DeadCodeAnalysis` + `SparseConstantPropagation` must load
  beside every analysis (`loadBaselineAnalyses`); SCCP simulates `fold`
  and uniques property dictionaries in the context per op (W5 hazard).
- B1: forward analyses resolve callees by linear scan unless
  `upstream/05`; B2 liveness one `bool` per value; B3
  `remove-dead-values` interprocedural only for private-function dead
  args/results; B5 `IntegerRangeAnalysis` has a widening budget (an
  upstream precedent for a budget that loses precision, never fails).
- C1-C4: per-edge interface methods O(1); `getPredecessors`,
  `getPredecessorValues`, `getSuccessorOperandInputMapping()` (no
  source), `isRepetitiveRegion`, `insideMutuallyExclusiveRegions` are
  O(N) per call; C3 a sparse forward visit of a region-branch result
  rejoins all N terminators (no incremental join). Remedy: enumerate an
  op's edges once per op; our match ops override `getPredecessors`,
  `getPredecessorValues`, `getSuccessorRegions(Region&)`,
  `isRepetitiveRegion` with O(1)/O(answer).
- D2 table: who reads effects upstream (CSE, DCE, LICM, sink, inliner,
  SCCP cleanup, liveness, alias analysis, bufferization); stage and
  full-region unread. D3: `RecursiveMemoryEffects` = whole-body walk per
  query.
- E1: `CallGraph` 150-700 B per function, `eraseNode` O(nodes); SCCs
  via `scc_iterator` bottom-up; inliner parallel only within an SCC.
  E2: `SymbolTableCollection` 2 MB at 70k; `SymbolUserMap` 64-bucket
  `SetVector` per used symbol (about 40 MB, conjecture).
- F1 (threading contract): compute whole-program facts in a
  module-level pass/analysis; nested parallel passes read them
  read-only via `getCachedParentAnalysis`; child maps created serially
  before the parallel loop. F2: the pass manager parallelizes over
  immediate children; functions reached by module -> `idr.program` ->
  function, must be `IsolatedFromAbove`. F3: attribute/type creation on
  hot paths grows the context and takes its locks.
- G1 non-dataflow `Liveness` per block; G2 actions + debug counters for
  a solver's units; G3 ownership-based deallocation: per function,
  function-boundary ABI, residual runtime checks.
- H1-H3: arithmetic; H3 large match N² per round if queried per region.
- 5.1.2 #2 (conjecture): per-value sparse problems go back on the
  framework per function: Constants, Ranges, Borrows, Narrow
  Lanes/Copy, Tail Returned, Effects/Constants, and "any analysis of
  ours whose lattice is per value and whose interprocedural part is a
  summary (`Recursion`, `BindingTimes`, `Ranges`' return ranges)".
  #3: ours honestly: per-point set-valued problems (exclusivity's
  graph, rc-stack lifetimes, Frames' plan), the label solve, every
  interprocedural summary over call-graph SCCs. #4: `remove-dead-values`
  split. #5: match ops answer per op. #7: threading contract; a
  wavefront over the SCC DAG is the solver layer's to provide.
- Design 1 (recommended): U1 state storage patch; U2 backward callee
  resolution in a scoped solve (`SparseAnalysis.cpp:521-540`, W7); U3
  quadratic helpers; U4 baseline coupling (#193112); match-op
  overrides; one module-level summary analysis over SCCs bottom-up with
  a wavefront, iterated in a recursive SCC up to a budget that only
  loses precision; function passes read summaries via
  `getCachedParentAnalysis` in `visitExternalCall` /
  `visitCallableOperation`.
- Design 2: whole program on the patched framework (baseline only).
  Design 3: the solver layer: one directory, header per solver naming
  A4/C3/A6; dense per-function numbering, `BitVector`, edge table read
  once per op, lattices and transfers as concept-constrained template
  parameters, SCCs from upstream `CallGraph` + `scc_iterator`, results
  in `AnalysisManager`, units as actions. Design 4 rejected: a general
  framework of ours.
- Owner questions QA1-QA4 (mine to evidence). W1-W7 for wave 2: W2
  (every analysis: lattice, interprocedural?, summaries, Design 1 or 3)
  and W7 (any analysis relying on backward callee resolution in a
  non-interprocedural solve) fall squarely here; W3 (edge tables per
  query) and W6 (anchoring) partly.

### §5.2 mlir-ods (what bears on analyses)

- A6: upstream reads effect kind, resource (identity, parents,
  addressable), value/symbol; never stage, full-region, parameters.
  A7: divergence/trap as speculation leaves a dead op deletable.
  A8: `isa<IOResource>` over effect instances is hierarchy-aware, so
  "does IO" is one query: bears on `Analysis/Effects`.
  A9: transform dialect `InferEffects` stores a per-argument summary on
  function arguments that the call's hand `getEffects` reads; lookup
  via `lookupNearestSymbolFrom` linear: our effect summaries must not
  be read that way.
- H3: a module pass re-verifies all functions unless it preserved all
  analyses; M11/W9: passes that change nothing should
  `markAllAnalysesPreserved()` (the verifier is then skipped). This is
  the analysis-manager use this lane owns.
- E3: walk driver terminates by construction (AGENTS.md shape for
  optimization).
- M2/Q1: Divergence and Crash as speculation vs resources (bears on
  `Analysis/Effects` and `Analysis/Recursion`, which compute "may
  loop").

### §5.3 llvm (S1 and the idiom catalog)

- B7 (read): `DenseMap` minimum 64 buckets; dense numbering is LLVM's
  newest move (`Block::getBlockID`, `Region::getMaxBlockID` at our
  pin). B8: `scc_iterator` is iterative Tarjan; "`lib/Support/Scc.cpp`
  is, by its name, a hand-rolled `scc_iterator`".
- C1 Attributor (known/assumed states, REQUIRED deps, 32-round cap to
  pessimistic); C2 SCCP (no stored dependents, use lists, one product
  lattice); C3 LVI memo; C4 MemorySSA representation; C5 clang (CRTP
  over type-erased core, vector of block states, RPO worklist, cap is an
  error: not ours); C7 table.
- D1: `llvm::parallelFor` inside an MLIR pass is a second pool; use
  `mlir::parallelForEach`. D2 lld ICF double-buffered; D3 BOLT.
- M3: hot callbacks become templates; cold traversal callbacks keep
  `function_ref`. M4: our worklists and `Scc.cpp` are `scc_iterator`,
  `post_order`, RPO + `BitVector`. M5: per-node `DenseMap`s are the
  shape of the walls. M7: "Our recent fixes are the SCCP shape, found by
  hand" (exclusivity marks, rc-stack marks, "a component's answer is
  data"); S1 makes it one mechanism. M9: budgets: Attributor/MemorySSA
  model fits AGENTS.md, clang's error model does not. M12: walks that
  re-find the same ops (walk once, index by kind).
- **S0** (read this most carefully): "Before S1 is given an analysis,
  wave 2 asks of it: could the dialect carry this answer (a type, a
  token, an op) so that no pass solves for it?"
- **S1**: `idr::solve`: `Node` dense index; frozen CSR `Graph` with
  `GraphTraits` (getNumber/getMaxNumber); `Forward`/`Backward` types;
  `Lattice` and `Analysis` concepts; `Solution<A>` frozen vector cached
  in `AnalysisManager`; `solve` instantiated once per analysis in its
  TU; `mark(graph, seeds)` for two-point lattices. Schedule: SCCs via
  `scc_iterator`, RPO priority worklist inside an SCC. Composition:
  `const Solution<B>&` in constructor (a dependency is a parameter,
  cycles cannot be written); mutually dependent analyses are one
  `Product<A,B>`. Threading: per-function solves in function passes;
  whole-program solves SCC level by level with `mlir::parallelForEach`.
  Memory about 8(N+E) + N*state. Budgets: none for refusal analyses,
  pessimistic for optimization-only. Deletes (conjecture): hand SCC
  utility, per-analysis worklists and graph types, per-node containers,
  framework users that solve over the whole program.
- S2: upstream `DataFlowSolver` scoped per function + footprint patch
  for local analyses (ranges in a function, lanes, copies). S3
  Attributor/DFX ranked below S1. S4 LVI memo for sparse queries.
- I1-I8 idiom rules (I5 hot callback template, I6 worklist is a
  schedule, I7 per-node state is a vector indexed by a dense number).
- Owner questions mine to evidence: Q-llvm-1 (monomorphized vs
  type-erased core, one instantiation per analysis), Q-llvm-2 (budgets),
  Q-llvm-3 (dense numbering as invariant: per solve, cached analysis,
  or upstream op/value numbers), Q-llvm-7 (giant SCC).
- Wave-2 questions: every worklist (order, dedup, identity, which
  algorithm); every `DenseMap` per solve or per node; every
  `function_ref`; `Scc.cpp` vs `scc_iterator`; every mutex/atomic and
  `parallelFor*`; "the seven files on `DataFlowSolver`: which solve
  within one function (S2) and which over the whole program (S1)?";
  whether one CSR `Graph` serves exclusivity, rc-stack, label solve.

### §5.4 modular (SCCGraph)

- F2: Modular uses no `DataFlowSolver`; own SCCP, IPDF, DAE etc.
- F3: `CallGraphUtils.h` (CRTP `CallGraphBase`, built with
  `parallelForEach` under per-node `SmartRWMutex`) + `SCCUtils.h`
  (`SCCGraph<DerivedT, NodeT, BottomUpRewrite>`: `llvm::scc_begin`, a
  dependency count per SCC, leaf SCCs first fork-join,
  `doAnalysis(node)->bool` iterated within an SCC, `doRewrite`). Its
  in-SCC fixpoint asserts a count (`SCCUtils.h:76-77`).
- F5: Mojo SCCP copies the whole map per nested region (our b8301ebe
  shape); loop threshold 5 then Unknown (budget that weakens).
  F6 IPDF: persistent row-per-writing-op state. F7: `CFGAnalysis`
  built once per function, one query per terminator, predecessors
  inverted from successors. F8: DAE per argument/result (LLVM's
  algorithm); `InferFunctionAttrs` an `SCCGraph` client in about 100
  lines. F9: `SymbolTableAnalysis` cached, `isInvalidated` false.
  F15: three-tier threading contract (whole-program immutable,
  per-worker cache, per-function state); `failableParallelForEach`
  with per-worker cache + consolidate. F17: Mojo writes facts to
  discardable attributes (`ipdf`, `convergent`): forbidden for us.
- 5.4.2 #2: "Our call-graph analyses (`CallCycles`, `Recursion`,
  `Effects`, `Inline`, the label solve's interprocedural part,
  `optimize`'s bottom-up inline-and-specialize, the deduplicator) are
  each 'a summary per function, callees first'"; SCCGraph lacks a
  top-down direction (caller to callee, for constants and binding times
  at call sites). #6: DAE per argument/result, not per value.
- Design 1 (modular): `SummaryProblem` concept, `solve<P, Direction>`
  with `calleesFirst`/`callersFirst`, dense `CallGraph` (FunctionId,
  CSR), an SCC enqueued when its last neighbour finishes; deletes
  `Scc.cpp`, `CallCycles`, `Recursion`'s own SCC order, the
  deduplicator's waves, `optimize`'s bottom-up scheduling.
- Design 2 (modular): per-function solvers on one parallel driver with
  the three-tier contract.
- Design 3 (modular): dense per-point state as rows shared until written
  (IPDF) for stack cells, exclusivity, borrows. Design 4: region control
  flow as a table built once (successors per terminator, predecessors
  inverted, cached per function). Design 6: dead arguments/results as a
  summary problem (bit per arg/result). Design 7: answers that carry
  what was learned (`Changed` enum, `TriResult`).
- Q-M1 (mine to evidence): adopt the SCCGraph-shaped schedule, port or
  fresh. Wave-2 list: "Which analyses are summaries over the call graph,
  in which direction, and does each compute its own SCC order?
  (`CallCycles`, `Recursion`, `Effects`, `Inline`, `Identities`,
  `BindingTimes`, `LabelSites`, `optimize`, the deduplicator.)"; where
  state is copied per region/edge; how predecessors of region
  successors are computed in each client.

### §5.5 cxx26 (what bears on analyses)

- Finding 9: MLIR erases walk callbacks on purpose (`function_ref`).
  Finding 12: `std::visit` cliff above 11 alternatives. Finding 13:
  a template callback costs 2-3x a `function_ref` to compile.
- D1 boundary rule: dispatch over ops by interface/trait/pattern; never
  a concept listing ops; typed code below the dispatch; our own types
  are closed sums.
- D2: `std::variant` + one `match`; `holds_alternative`/`get_if`
  banned outside `match`. Example lattice `Bottom | Exact | Range |
  Top` (the shape our Constants/Ranges lattices would take).
- D3: solver C++ shape: `Id<Tag>` minted by the graph,
  `IndexVector<IdT, T>` with raw-integer indexing deleted; `Lattice`
  concept with `mlir::ChangeResult`; `FlowGraph` concept; transfer as a
  template parameter; `extern template` one instantiation per solver.
  "Deletes `DenseMap<Value, L>` as solver state, `function_ref`
  transfer callbacks, any virtual 'analysis' base of our own."
- D4c: product of facts joined field by field with structured-binding
  packs (bears on `Effects`' summary record).

### §5.6 ecosystem

- A1-A4 CIRCT: IMConstProp own sparse SCCP (`FieldRef` keys, 8-byte
  lattice, users precomputed, sequential solve, parallel rewrite);
  IMDCE a set of live elements; `InstanceGraph` held in the
  `AnalysisManager`, kept up to date by passes that change it,
  preserved by name in 15 files. B5: Arc off the framework 130 s ->
  200 ms (nodes only for interesting ops).
- C2-C4 IREE DFX: lazy, type-filtered, arena; C3 IREE turns the budget
  into errors (forbidden). D1 IPO `FuncAnalysis` bit vectors per arg/
  result. D2 `FixedPointIteratorPass` (attribute + round count that
  refuses: forbidden). D3 upstream solver per function under
  `FunctionLikeNest`. D4 IREE recomputes DFX analyses per pass (14 and
  9 rebuilds): "the rederivation chain §1 asks us to kill, at
  whole-program scale". D6: whole-program answer written into types
  once (lifetime in `!stream.resource`), regretting the lossy mapping.
- E3 Flang: opt-in pass-scoped cache of recursive effect summaries.
- G1 Enzyme summary-based: per-function solver, summaries as
  discardable attributes (forbidden for us); G2 Triton
  `CallGraph<T>` template, summaries as discardable attributes.
- 5.6.2 #1: a solver's domain is the values whose type leaves its
  question open, read off the type (Design 2, W-E2). #2: one call graph,
  cached and kept up to date (CIRCT `InstanceGraph`); "§2 lists
  `CallCycles`, `Recursion`, `Inline`, `LabelSites` and
  `Support/Scc.cpp`, each of which may derive call-graph facts on its
  own". #3: summaries over the SCC DAG in a typed table, never in
  attributes; recursion is essential; terminates by finite lattice.
  #5: a budget degrades a site, never fails a pass. #6: extract, solve,
  write back. #8: structured walk linear only without copying state at
  branches (per-case deltas). #9: queries on a big region op answered
  once per op.
- Design 1 (ecosystem): `lib/Solver/`; `ProgramGraph` (an
  `AnalysisManager` analysis on `idr.program`, dense `FunctionId`, CSR
  callees/callers, SCCs bottom-up, `replaceCall` kept up to date by
  defunctionalize, contify, inline, specialize, symbol DCE, preserved
  by name); Shape S summaries over SCC DAG (`Summary` concept,
  `SummaryTable<S>`, `solveBottomUp`); Shape L local solves per function
  reading shape S in `visitExternalCall`; Shape G extract-solve-write
  back. Design 2: lazy, type-filtered state (filter = `ValueFacts` type
  interface). Design 3: upstream per function, patched, for Constants,
  Ranges, Borrows, Narrow, Tail/Returned, Effects/Constants.
- Q-E1 (mine to evidence: ProgramGraph + three shapes), Q-E5 (upstream
  RFCs: maintained call graph with SCCs; per-SCC scope in the
  framework). W-E1 (who derives call-graph/SCC facts on its own; which
  passes change calls without telling anyone), W-E3 (analyses computed
  by more than one pass; which could preserve), W-E4 (facts in
  discardable attributes), W-E5 (every budget), W-E7 (`DenseMap<Value,
  ...>` per function), W-E9 (state copied per edge/branch): mine.

### §5.7 library (L1, L2 read most carefully)

- B3 (read): MLIR has no whole-module use-def chains; every
  interprocedural fact (who calls whom, which closures flow where,
  what a callee does to its arguments) must be built as a structure of
  its own: the reference graph (calls plus closure and constant
  references).
- C1-C3: sparse vs dense; PLV criterion (product of per-variable
  lattices with per-variable transfers); SSI; backward analyses sparse
  only under static single use; SSA DCE has SSI. C4: liveness under
  strict SSA needs no fixpoint (liveness check). C5: in region IR,
  dominance and scope are the region tree.
- D4 Flix: composition by union of rules; IFDS/IDE summaries. D5
  Steensgaard/union-find over subsets. F1 LVars freeze; F4 build
  systems: `AnalysisManager` is a dirty-bit rebuilder with no early
  cutoff (conjecture). F6 stratification: read a complement only after
  what it complements is complete.
- H3 (read): two-level type theory makes binding times types: "what a
  binding-time analysis would infer is instead stated, and checked by
  typing" (bears on `Analysis/BindingTimes`).
- M2: the 52 GB liveness wall is a one-bit problem per value; dead
  args/results across calls are a bit per argument/result in a
  per-function summary. M3: e96bb991 = validation repeated where a
  parse belongs; parse the interface once per op into a CSR edge
  array. M4: rc-stack's per-value candidate vectors = independent
  sparse problems encoded densely. M7: two compositions: product
  lattice for mutual dependence; frozen read for one-way dependence;
  interprocedural = summaries over SCCs of the reference graph. M8
  threading = phase concurrency over scopes. M9: dense numbering per
  scope; pre-order intervals give enclosure in two compares. M10:
  monomorphized C++ is Soufflé's practice.
- **L1**: SSI by representation: every ownership change defines a new
  value; case regions bind refined scrutinees; quantity 1 is static
  single use. Then every ownership fact is per value; no per-point
  state. Essential: relational facts (aliasing) stay relations.
- **L2**: one scoped sparse solver core: `Scope` (ops in pre-order,
  `end` intervals, values in walk order, `uses` CSR, `flow` CSR from
  one interface query per op, callees); `SparseAnalysis` concept;
  `solve<As...>` over the product lattice, one worklist of op ids, no
  program points; frozen callee summaries; SCCs of the reference
  graph in bottom-up waves; summary a small fixed record per function
  in one array by function id. Upstream first for intraprocedural
  facts upstream computes per function (`int-range-optimizations`
  3 s vs 30 s nested per function, `notes/compile-pipeline/
  upstream-mlir-llvm.md` §4). Deletes (conjecture): whole-program
  framework uses in ownership, hand worklists, per-analysis
  `DenseMap`s, exclusivity's own graph, `Scc.cpp`.
- L3 build-then-freeze interned program tables (data types, effect
  summaries, reference graph). L4 whole-program relations as sorted
  flat arrays with union-find (label flow, reference graph, effect
  propagation). L5 clones as keys (specialization, frames). L6
  analyses maintained by rewriter listeners.
- QL1 (mine to evidence: a scoped array view of the IR built per solve
  vs `Value`-keyed hash maps), QL3 (rules over relations vs transfer
  functions over one engine). Wave-2: per analysis PLV / PVP /
  relational, forward/backward, per-point facts; which analyses could
  share one product-lattice solve; which only read another's frozen
  answer; stage-1 counts.

### §5.8 dialect-design (what bears on analyses)

- Table "who needs the fact -> carrier": a type (every use, every
  pass); an inherent attribute (one op's meaning); a declared effect;
  a trait/interface (classification); an analysis or pass-checked
  invariant (a property of a whole function). "A fact in a lower row
  than its readers need is rederived (the rederivation chains of §1)."
  This is the frame for every chain in §5 of this document.
- T6 (read): a function type carries conventions and effects; "A
  call's effects are then read off the callee's type, once, instead of
  being re-inferred (§2's `Analysis/Effects`)". B9: a parallel function
  pass may not read a sibling (the callee); DS2.1: either the call
  carries the callee's effect set as an inherent property verified by
  `verifySymbolUses`, or effects are an analysis cached in the
  `AnalysisManager`.
- T7: `ValueFacts` the home of "contains a linear field", "contains a
  reference", "is trivially copyable", "has a runtime form", computed
  at construction, not per query (bears on Identities/Effects reading
  type facts).
- EF1/DD-Q2: divergence kept or deletable (bears on `Recursion`'s
  may-loop facts). DS2: world vs effects (bears on `Effects`' "does
  IO" derivation). DS3: data types table (bears on every analysis that
  reads `data` bodies). DS4: `check.may_loop`, `Divergence` resource.
- Wave-2 questions mostly ods lanes; for this lane: where `MayCrash`,
  `PerformsIO`, `ObservableIO`, world operands are read (the Effects
  analysis is one reader).

### §5.9 mlton (analyze.fun read most carefully)

- B1-B2: property lists: per-pass state on the node, typed, freed with
  the pass (`destroy`). B3 (read): `ssa/analyze.fun` is one generic
  abstract interpreter parameterized by a value domain (`coerce`,
  `conApp`, `filter`, `primApp`, `select`, `tuple`, `const`,
  `fromType`), visits each reachable block once, emits one constraint
  per binding/argument/return/case arm; the fixpoint lives in the
  abstract values (mutable cells propagating their own changes); the
  type checker is the instance whose `coerce` is equality; `useless`
  and constant propagation are instances. B4: cells are union-find
  nodes with handler lists (two-point rises once, handlers run once:
  O(constraints), no worklist, no iteration count). B5: abstract value
  shape is the type's shape; constructor field facts once per `Con`;
  first-order types share one abstract value (state sized by types and
  constructors).
- D1: monomorphise by thunks forced in reverse (no worklist). D2: 0CFA
  as one traversal with handlers, hash-consed lambda sets, sending
  differences. E1: contify one whole-program graph + one dominator
  tree. E2-E3: the shrinker is the normal form called by every pass.
  F1: inline decision computed once from the call graph SCCs
  leaves-first, size counts inlined callees, budget only leaves code
  uninlined. F2: removeUnused: demand-driven two-point cells per name;
  liveness, reachability, dead constructors/fields/args/returns as one
  analysis. F7: liveness per function, per variable (bit-vector
  liveness "infeasible for MLton"). G2.7: "Nothing is carried between
  passes except the program; every analysis is recomputed by the pass
  that needs it, and that is affordable because each is linear". G2.9:
  lazily cached CFG/dominator tree that cannot go stale.
- H table: each §3 wall mapped to MLton's mechanism (all "no").
- M2: "Three of §3's eight walls are a per-value or per-program-point
  state model ... the three fixes already made ... are each a step
  towards MLton's model, taken one analysis at a time. P0's solver
  layer can take the model whole (Design 1)." M8: the inliner is
  already MLton-shaped.
- **Design 1 (mlton)**: one constraint-generating abstract interpreter
  templated on a domain concept + one library of cells (two-point,
  flat, set) in per-pass arenas found through dense indices; state
  sized by types; the type checker is a domain; composition = product
  domain or reading the first's answer written into the IR. Deletes (if
  confirmed): Ownership solvers, Labels/LabelSites, `Effects`,
  `Constants`, `Ranges` "where they are whole-program", whole-program
  framework users, every per-analysis worklist. Design 3: a fact is
  written into a type by the pass that proves it; everything else is
  recomputed by the pass that needs it (linear), cached only within a
  preserving pipeline. Design 4: liveness per function per variable.
  Design 6: footprint per pass as a Tracy report.
- Q-O2 (mine to evidence): constraint-generating abstract interpreter
  (flow-insensitive per SSA value, cells with handlers) as *the* solver
  layer, `DataFlowSolver` only for intraprocedural analyses where its
  state fits. Q-W2: per analysis, state per value / point / pair / type
  / constructor; flow-sensitive by need or by framework; could it be a
  domain of Design 1.

### §5.10 rc (what bears on analyses outside ownership)

- M1: every counting algorithm in the field is per function and reads
  other functions only through signatures; Lean runs its impure
  pipeline one SCC at a time (`Main.lean:200-215`) with saved
  signatures. M2: liveness should be the insertion walk's state, not
  an analysis read by another component ("a rederivation chain in §0's
  sense"). M5: quantity 1 decides the parameter is owned by type.
  M6: exclusivity, locality, borrowing as monotone two-point markings
  (one honest solver for three markings). R1: signatures in types; one
  interprocedural solver; per-function passes nested on `idr.func`.
- These are lane 07/08's subjects; I record only the cross-cutting
  claims: signatures read off types (a chain that ends in a type), and
  the "three markings, one solver" shape that S1's `mark` provides.

### §5.11 oom (what bears on analyses)

- A1: "Memory is a stated property of each solver's representation":
  each solver's header states its state size in program units; "a
  state sized by a product of two program quantities is a wall waiting
  to be met". A4: budgets in program units only (ops, rewrites,
  clones), never bytes or seconds (C7: determinism; stage 2 =
  stage 3). Wave-2 #7: "Every solver and pass whose state is sized by
  a product of two program quantities (A1): the next walls, for §6's
  solvers lane." #8: attributes passes create per function or per
  value (`TransientScope`).

### §6-§9

- §6: twenty lanes; the Idris side in scope, within the two-host
  subset. §7 not written. §9 decisions D1-D4: D2 "Our own solvers are
  allowed where upstream cannot do the job, named honestly and
  refactored into code of their own, where how they compose and are
  threaded is clear."
- §8.4 groups "QA4, Q-O2, QL1 and Q-llvm-3 [as] four sides of one
  choice, the shared state representation". My questions: QA1, QA2,
  QA3, QA4, Q-O2, QL1, QL3, Q-M1, Q-E1, Q-E5, Q-llvm-1, Q-llvm-2,
  Q-llvm-3, Q-llvm-7 (with Q-E3 and oom-2 as companions of Q-llvm-2).

### proposals/0003-facts-once.md (items that are rederivation chains in my scope)

- §1 rule: **keep** a fact when deriving it again is a guess, can
  refuse or hang, or is super-linear; **derive** it when it is a total,
  cheap function of a smaller one-source representation (the stored
  copy then goes). One fact, one source.
- Defunc lane items: "Analyses dropped and rebuilt": `Effects.cpp`
  preserves only `SymbolTable` though it writes only effects, so
  Contify rebuilds `CallCycles`; `Defunctionalize/Pass.cpp` builds a
  `TypeGraph` outside the manager for a statistic, Knots builds it
  again; `TypeGraph(op)` built directly by `Layouts`, `layout::fit`
  and the program verifier after every pass; `verify::recycles` builds
  a whole `Layouts`. `givesBack` solved twice (idr-optimize summaries
  vs `Tail/Returned.cpp`). The optimizer rescans each wave and restamps
  every call's effects each round. Ranges discarded (`Narrow.cpp`) and
  re-solved; `Lanes.cpp` finds a bound by search behind a guard.
- Ownership lane items: exclusivity solved twice; "Exclusivity is no
  analysis" (handed by constructor to `createRcCommit`); static
  lifetime searched along the definition chain (`isStatic`).
- Control lane items: what an enclosing match says about a value three
  ways; `knownNonEmpty` re-walks; `closureLabels` walks every value's
  type though sums are `TypeGraph::declarations()`.
- Leftovers: MoveOut classifies effects a second way beside
  `idr::classify`; resources read as effect bits by hand
  (`Expect/Placement.cpp`, `StructureLoops/Forms.cpp`); crash-site count
  vs crash effect disagree; Identities' parallel `arguments`, `slots`,
  `types` and the `Drop` pair; `holdsLabels(Value)` repeating
  `carriesLabels(Type)`; target lane: `effects` and `total` reach no
  LLVM attribute.

## 2. What the subsystem is

### 2.1 Files and sizes

*Measured*: `wc -l` over the files at e96bb991.

| file | lines | what it is |
| --- | ---: | --- |
| `lib/Analysis/CallCycles.cpp` + `.h` | 58 + 63 | the partition into call-graph SCCs, cached; reads upstream `CallGraph` |
| `lib/Analysis/Recursion.cpp` + `.h` | 50 + 35 | which functions may have more than one frame live |
| `lib/Analysis/Effects.cpp` + `.h` | 96 + 64 | the `effects` summary driver over CallCycles; the observable-run reach |
| `lib/Analysis/BindingTimes.cpp` + `.h` | 179 + 41 | fixed/varies per parameter inside one SCC (abstract interpretation) |
| `lib/Analysis/Identities{,Record,Rebuilds}.cpp` + `.h` | 129 + 321 + 282 + 195 | which argument a function gives back: one walk into a record, a greatest fixpoint per SCC |
| `lib/Analysis/Inline.cpp` + `.h` | 34 + 64 | MLton's inline rule and the caller cap |
| `lib/Analysis/Constants.cpp` + `.h` | 43 + 59 | SCCP with summaries at calls; returned constants read off the body |
| `lib/Analysis/Ranges.cpp` + `.h` | 94 + 75 | upstream `IntegerRangeAnalysis`, seeded by types, whole program, interprocedural |
| `lib/Support/Scc.cpp`, `include/idr/Support/Scc.h` | 53 + 56 | SCCs of index graphs through `llvm::scc_iterator` |
| `include/idr/Support/Worklist.h` | 157 | `OnceWorklist`, `MonotoneWorklist`, two concepts |
| framework users outside `lib/Analysis` | 209 + 194 + 149 + 159 + 249 + 315 | `Transforms/Effects/Constants.cpp` (idr-constants), `Tail/Returned.cpp`, `Tail/ReturnedArguments.cpp`, `Narrow/Copy.cpp`, `Narrow/Lanes.cpp`, `Analysis/Ownership/Borrows.cpp` |

`lib/Analysis` in all is 3,564 lines (*measured*:
`cat lib/Analysis/*.cpp lib/Analysis/Ownership/*.cpp | wc -l`), matching §2.

### 2.2 Each analysis of this lane: fact, state, scope, readers, builds

*Read* unless marked.

- **CallCycles** (`CallCycles.cpp:16-46`). Fact: the call graph's SCCs,
  callees first, every function in one, body-less functions alone and
  first. State: upstream's `CallGraph` (cached itself; §5.1 E1:
  `MapVector<Region*, unique_ptr<CallGraphNode>>`, a `SetVector` of edges
  per node), then three copies of the partition: `SmallVector<Component>`,
  `DenseMap<Operation*, unsigned> indices`, `DenseSet<Operation*>
  selfCalling` (`CallCycles.h:55-58`). Scope: whole program (or module
  after lowering). An extra pre-order walk finds body-less callables
  (`CallCycles.cpp:28-33`). Exposes no callers and no callees.
  Readers (9 `getAnalysis` sites, *measured*: `grep -rn
  'getAnalysis<\(idr::\)\?CallCycles>' lib | wc -l`): idr-effects
  (`Transforms/Effects/Effects.cpp:31`), idr-contify (`Contify.cpp:128`),
  idr-optimize (`Optimize.cpp:85`), idr-binding-times
  (`Specialize/Report.cpp:29`), idr-frames (`Frames.cpp:349`), idr-rc-stack
  (`Stack.cpp:289`, and through Recursion, `Recursion.cpp:17`), idr-rc-grades
  through Borrows (`Borrows.cpp:299`), idr-tail-calls
  (`TailCalls.cpp:139`). Builds per pipeline: **up to seven** in the
  compile pipeline (effects, contify, optimize, frames, rc-stack,
  rc-grades, tail-calls), one per reading pass whenever a pass between
  changed the program, since no pass preserves it or `CallGraph` by name
  (*measured*: `grep -rn 'markAnalysesPreserved<.*\(CallCycles\|CallGraph\|Recursion\)' lib`
  finds 0) and every pass between those changes something. Scale at 70,000
  functions: 10-50 MB for upstream's graph (§5.1 E1, *conjecture*) plus
  about 60 B per function for our copies (*conjecture*, from the
  containers), each build two walks of every op (§5.1 E1) plus ours.
- **Recursion** (`Recursion.cpp:16-44`). Fact: may a function have two
  frames live (on a multi-member SCC, or calling itself not in tail
  position). State: `DenseSet<Operation*> onCycle`. Reads CallCycles,
  walks each self-calling singleton's body in parallel
  (`Recursion.cpp:30-40`, `mlir::parallelFor`, the context's pool). One
  reader: idr-rc-stack's frame budget (`Stack.cpp:288, 310-311`). One build.
- **Effects summary** (`Effects.cpp:36-47` over `IR/Func/Func.cpp:189-221`).
  Fact: the `Effect` bits (io, crash, diverge) of each function, the union
  of its own part (`bodyEffect`) and its out-of-SCC callees'. A Shape-S
  summary (§5.6) solved in one pass per SCC (a union needs no iteration).
  The answer is **carried in the IR**: an inherent property `effects` on
  `idr.func` and on every `idr.call` (`IdrOps.td:143-163, 198-220`),
  checked by `CallOp::verifySymbolUses` (`Call.cpp:52-57`) and by the
  program verifier's `effectsCovered` after every pass
  (`Verify/Program.cpp:53-71`). To write calls it builds a
  `SymbolTableCollection` and a whole-program `SymbolUserMap`
  (`Effects.cpp:37-39`). Readers: every pass that reads a call's memory
  effects (`Call.cpp:65-72`: upstream CSE, DCE), Identities
  (`IdentitiesRecord.cpp:160`), idr-optimize's summaries. Computed:
  idr-effects once; idr-optimize again per component as it finishes
  (`Component.cpp:215`, bodies changed: essential); re-derived as a check
  after every pass (`Verify/Program.cpp:61-71`).
- **observableRuns** (`Effects.cpp:49-96`). Fact: which functions may,
  through calls and label runs, perform an `ObservableIO` op (before
  defunctionalization's conversion). State: a per-function slot
  (`Runs{bool, SmallVector<FuncOp>}`), a `positions` map
  (`DenseMap<Operation*, unsigned>`, `:52-54`), a reverse adjacency
  (`:79-82`) and a backward reach on `OnceWorklist<unsigned>` (`:85-94`).
  Its label edges come through a `function_ref` the caller fills from
  `Labels` (`Effects.h:51-52`; `Defunctionalize/Pass.cpp:110-115`). One
  reader, one build (idr-defunctionalize).
- **BindingTimes** (`BindingTimes.cpp:90-177`). Fact: per parameter of a
  function, fixed or varies over the calls of its SCC. Abstract
  interpretation of each member reached with each tuple of abstract
  arguments; tuples keyed in a `std::map<SmallVector<unsigned>, Tuple>`
  (`:110`), reaches in a `OnceWorklist<pair<Operation*, Tuple>>`
  (`:115`), members by name (`:47, 173-175`). Called once **per member**
  (`Component.cpp:245`; `Report.cpp:34`), each call re-interpreting every
  member it reaches. Intraprocedural within one SCC; reads nothing
  outside it. Readers: idr-optimize's summary (`Waves.cpp:287`), the
  specializer's keys; the report pass. Scale: per SCC, O(members ×
  reach) (*conjecture* from the loop structure).
- **Identities** (`Identities.cpp:38-127`, `IdentitiesRecord.cpp`,
  `IdentitiesRebuilds.cpp`). Fact: which argument each function of an SCC
  gives back. Extract-solve: one walk per member into a `Record` of
  dense-numbered nodes (`std::vector<Build>`, a 10-alternative variant,
  `Identities.h:141-185`) via a `DenseMap<Value, Id>`
  (`IdentitiesRecord.cpp:97`); then a greatest fixpoint dropping
  assumptions on `OnceWorklist<Drop>` (`Identities.cpp:96-120`), callees
  outside the SCC frozen through an `Outside` callback (`Identities.h:45`).
  Each check builds a fresh `Reading` with its own memo and interned parts
  (`IdentitiesRebuilds.cpp:89-128, 269-280`). Readers: idr-optimize's
  summary and idr-identity (`Component.cpp:238-242`). Built per component
  of the ready set. Its answer dies with idr-optimize; Tail/Returned
  re-solves the same fact on lowered code (§5 chain R5).
- **Inline facts** (`Inline.cpp:14-34`). Fact: a function's op count and
  MLton's verdict. Two walks per ask (`:16`, `:25-28`). Readers:
  idr-optimize's summary (`Component.cpp:219-220`); `inlineSize` also
  from `Inline/Inline.cpp:124, 144`, `Optimize.cpp:110`,
  `Expect/Sizes.cpp:25`.
- **Constants** (`Constants.cpp`; the solve in
  `Transforms/Effects/Constants.cpp:171-201`). Fact: constants of every
  value of one function given its final callees' returned constants. A
  per-function upstream solve (`DataFlowConfig().setInterprocedural(false)`,
  `DeadCodeAnalysis` + our `SparseConstantPropagation` subclass whose
  `visitExternalCall` reads summaries, `Constants.cpp:37-43`): exactly
  §5.1 A6's supported scope and Design 1's shape, already in the tree. The
  solve's result is written into the body as constant ops, and
  `returnedConstants` reads the summary back off the body
  (`Constants.cpp:16-30`): the body is the one copy (0003 §1, *derive*).
  Built once per round of each function's inner pipeline (`Optimize.cpp:51-77`).
- **Ranges** (`Ranges.cpp:65-92`). Fact: an integer range for every value
  of the program. One whole-program **interprocedural** solve on upstream's
  `DataFlowSolver` (`Ranges.cpp:67`), baseline analyses loaded
  (`:74`, dead code + SCCP), our `NaturalRanges` subclass seeding by type
  (`:30-33`) and special-casing `ub.poison` (`:39-44`) and a literal
  match's default region (`:51-60`). State: §5.1 A4's model: per value a
  `Lattice<ConstantValue>` and an `IntegerValueRangeLattice`, an
  `Executable` per block, a `PredecessorState` per callable and call, all
  live while `Ranges::Solved` holds the solver (`Ranges.h:40-53`) through
  the nested idr-narrow-words run. Readers: idr-narrow and
  idr-narrow-words (`Narrow.cpp:74-75, 144`; `Narrow/Facts.cpp:59`).
  Builds: one, plus a second whole-program solve whenever a loop was
  versioned (`Narrow.cpp:154-165`). The pipeline has never reached
  idr-narrow on the stage-1 module (0001's record ends in counting), so
  this solve's footprint there is **unmeasured**.
- **Scc** (`Scc.cpp:32-53`, `Scc.h:31-52`). Not a hand-rolled Tarjan:
  a `GraphTraits` adapter that copies an index graph into a
  `std::vector<Vertex>` (one `SmallVector` of successor pointers each,
  plus a root vertex) and runs `llvm::scc_iterator`. `stronglyConnected`
  adds a `DenseMap<Node, unsigned>` numbering and takes successors through
  a `function_ref` returning a `SmallVector` by value per node. Ten users,
  each building its own adjacency first (*measured*, `grep -rn
  'idr::components(\|stronglyConnected<\|= components(edges)' lib`):
  `Labels.cpp:261`, `TypeGraph.cpp:110, 185`, `ValueFacts.cpp:266`,
  `Layout/Components.cpp:167`, `DataRemap.cpp:257`, `Target/Partition.cpp:234`,
  `Deduplicate/EliminateDuplicateFunctions.cpp:126`, `Expect/Cycles.cpp:34`.
- **Worklist.h**. `OnceWorklist` (a `SetVector` plus a cursor) is used in
  30 files (*measured*: `grep -rln 'OnceWorklist<' lib include tools | wc -l`).
  `MonotoneWorklist` and the `FiniteLattice` concept it alone uses have
  **no user** (*measured*: 0 hits outside `Worklist.h`).

### 2.3 The framework users (all seven files)

Seven files, five solves: `Analysis/Constants.cpp` is the subclass
idr-constants loads, and `Narrow/Lanes.cpp` drives `Copy`'s solver.

*Read.* "Shape" is §5.1/§5.6's vocabulary.

| file:line | analyses loaded | top op | interprocedural | anchors | shape today | reached on stage 1 |
| --- | --- | --- | --- | --- | --- | --- |
| `Transforms/Effects/Constants.cpp:188-191` | DeadCode, `SummarizedConstantPropagation` | one `idr.func` | no (summaries in `visitExternalCall`) | every value and block of one function | per function (A6) | yes (idr-optimize finished, 0001) |
| `Analysis/Ranges.cpp:67-77` | baseline (DeadCode, SCCP), `NaturalRanges` | `idr.program` | yes | every value, block, callable of the program | whole program (Design 2) | no |
| `Tail/Returned.cpp:152-159` | baseline, `ReturnedAnalysis` | lowered module | yes (`PredecessorState`, `:108-124`) | every value of the module | whole module (Design 2) | no |
| `Narrow/Copy.cpp:66-76` | baseline, `IntegerRangeAnalysis` | a scratch module of one loop | no | one loop's values | per loop, up to 6 trials (`Lanes.cpp:81-83, 135-158`) | no |
| `Analysis/Ownership/Borrows.cpp:297-304` | custom `DataFlowAnalysis` (no sparse base) | `idr.program` | by hand (states read after calls) | parameters and read values only; points after calls only | whole program, sparse anchors (a marking) | yes (*conjecture*: idr-rc-grades reads Borrows before it rewrites, `Grades.cpp:45-47`, and ran far enough to fail verification, 9db9813d) |

Every analysis loaded here is forward or custom: there is no
`SparseBackwardDataFlowAnalysis` and no `LivenessAnalysis` in the tree
(*measured*: `grep -rn 'Backward\|LivenessAnalysis' lib include` finds
none), which answers W7 (§3).

### 2.4 The analysis manager as the tree uses it

*Read*, from the full grep of `getAnalysis<`, `getCachedParentAnalysis`,
`markAnalysesPreserved`, `markAllAnalysesPreserved` (21 sites) and
`markAnalysesPreserved<...>` (13 sites, *measured*).

- Cached analyses: upstream `CallGraph`, `SymbolTable`,
  `DataLayoutAnalysis` (`Lower.cpp:254`); ours `CallCycles`, `Recursion`,
  `Labels` (`Labels.h:285-289`), `Reuses`, `Borrows` (`Ownership.h:229,
  248`), `Ranges`, `Returned` (`Tail.h:294`), `TypeGraph`, `Layouts`
  (`TypeGraph.h:48`, `Layout.h:262`).
- Not analyses though computed whole-program and read by others:
  `Exclusivity` (handed by constructor, `Exclusive.cpp:39-52`; 0003's
  "Exclusivity is no analysis", lane 07), the optimizer's `ReadySet` and
  `Summary` table (`Optimize.cpp:85`, `Waves.cpp:283-295`, lane 09),
  `TypeGraph` built outside the manager by defunctionalize, `layout::fit`,
  `Layouts` and the verifier (`Defunctionalize/Pass.cpp:152`,
  `Layout/Fit.cpp:25`, `Layouts.cpp:67`, `Verify/Program.cpp:104, 266`;
  0003, lane 01).
- Parent-cache reads by nested parallel passes (F1's contract): idr-narrow-words
  (`Narrow.cpp:74-75`), idr-returned-arguments-drop
  (`ReturnedArguments.cpp:108`); idr-optimize nests every function's
  manager before its tasks (`Optimize.cpp:93-94`, `Waves.cpp:270`).
- Preservation gaps: idr-effects writes only properties yet preserves only
  `SymbolTable` (`Transforms/Effects/Effects.cpp:39`), dropping `CallGraph`,
  `CallCycles`, `Recursion`, `TypeGraph` and `Layouts` (0003); idr-contify
  knows exactly how the call graph changes (one member folded into its
  only caller on the same cycle, `Contify.cpp:24-33`) yet invalidates it;
  idr-narrow invalidates everything but three analyses to re-solve ranges
  after versioning (`Narrow.cpp:158-162`).
- A private manager per checked pass in the contract instrumentation
  (`Contracts.cpp:327-328`, test only, lane 19).

### 2.5 Threading

*Read.* `Recursion.cpp:30` and `Effects.cpp:63` use `mlir::parallelFor`
on the context's pool (§5.3 D1's right pool). Every other analysis of
this lane is serial on the pass thread. idr-optimize's waves run
components in parallel (`Waves.cpp:337`, `failableParallelForEach`) and
read and write the summaries of disjoint components; a component's own
members run serially in one turn (`Component.cpp:257-269`).

### 2.6 The inventory of every analysis in the tree (W-E1, W-E3, W2, Q-W2)

*Read* for the facts and lines; scale is *conjecture* from the containers
unless marked. "Builds" counts per compile pipeline. "Home" is where P0's
evidence points; for another lane's analysis it is that lane's to decide.
S = summary over call-graph SCCs (Shape S, §5.6), L = upstream per
function (Shape L), G = extract, solve, write back (Shape G), T = a fact
carried in a type or property (S0, §5.3), U = upstream as it is or patched.

| # | analysis (entry) | lane | fact | state model | scope | readers | builds | home |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `CallGraph` (upstream, via CallCycles) | 05 | call edges | node per function + `SetVector` of edges | program | CallCycles | ≤7 | one maintained `ProgramGraph` (T5.1) |
| 2 | `CallCycles` (`CallCycles.cpp:16`) | 05 | SCCs callees first | 3 copies of the partition | program | 9 sites (§2.2) | ≤7 | `ProgramGraph` (T5.1) |
| 3 | `Recursion` (`Recursion.cpp:16`) | 05 | >1 frame may live | `DenseSet<Op*>` | program | rc-stack budget | 1 | a bit of `ProgramGraph`; delete the class |
| 4 | effects summary (`Effects.cpp:36`, `Func.cpp:189-221`) | 05 (classifier 02) | io/crash/diverge per function | property on func and call | program, per SCC | CSE/DCE via call effects; Identities; optimize | 2 solves + a check per verify | S over `ProgramGraph`; result stays T (property) |
| 5 | `observableRuns` (`Effects.cpp:49`) | 05 (reader 06) | runs an observable op | slots + reverse adjacency + reach | program | defunctionalize | 1 | G: `mark` on a runs graph, beside `Labels` (lane 06) |
| 6 | BindingTimes (`BindingTimes.cpp:172`) | 05 (reader 09) | fixed/varies per parameter | tuples per reach, `std::map` | one SCC, per member | optimize summary, keys | per member of every component | S intra-SCC over one extraction per component (T5.4) |
| 7 | Identities (`Identities.cpp:38`) | 05 (reader 09) | argument given back | record per function, greatest fixpoint | one SCC | idr-identity, optimize summary | per component | S; result carried to lowering as T (T5.5) |
| 8 | inline facts (`Inline.cpp:20`) | 05 (reader 09) | size, verdict | walks per ask | function | optimize, inline step | per ask | entry of the summary table; size maintained |
| 9 | constants (`Transforms/Effects/Constants.cpp:171`) | 05/09 | SCCP per function | upstream states per value of one function | function | the body; `returnedConstants` | per round per function | L as is; U: export SCCP's rewrite (T5.6) |
| 10 | `Ranges` (`Ranges.cpp:69`) | 05 (reader 11) | integer ranges | upstream states per value of the program | program, interprocedural | narrow, narrow-words | 1 or 2 | L per function + S for return/argument ranges, or U whole program after U1 (QA2) |
| 11 | `Returned` (`Tail/Returned.cpp:152`) | 10 | result is argument i | upstream states per value of the module | module, interprocedural | returned-arguments | 1 | deleted by carrying #7 (T5.5), else S |
| 12 | `Copy::analyse` (`Narrow/Copy.cpp:66`) | 11 | ranges of a loop copy | upstream, one loop | scratch module | lanes | ≤6 per loop | U as is |
| 13 | `Borrows` (`Borrows.cpp:297`) | 07 | borrowed/owned per parameter | `HoldingState` per parameter and read value | program | rc-grades | 1 | G marking in the solver layer (lane 07) |
| 14 | `Reuses` (`Reuses.cpp:272`) | 07 | reset/reuse sites | `DenseMap<FuncOp, SmallVector<Site>>` | per function | rc-grades, Borrows | 1 | per function (lane 07) |
| 15 | `Exclusivity::solve` (`Exclusivity.cpp:66`) | 07 | exclusive or shared per value | items graph, `DenseMap<Value, Sharing>`, `dependents` per value (`ExclusivityDetail.h:155`) | program, rounds until labels settle | rc-exclusive, commit, demand | 2 (grade copies) | G marking + a cached analysis (lane 07; 0003) |
| 16 | `whereDies`, `usedAfter` (`Uses.cpp`) | 07 | where a value dies | per query walks | block | Reuses, placement | per query | Perceus' walk state (§5.10 M2, lane 07/08) |
| 17 | `tracked`/`isStatic` (`Values.cpp`, `Verify/Uses.cpp`) | 07 | holds references, static | definition-chain search per query | value | many | per query | T: static in the grade (0003; lane 01/07) |
| 18 | `Labels` + `LabelSites` (`Labels.cpp:371`) | 06 | closure label sets | interned sets, condensed inclusion graph | program | defunctionalize, expect | 1 (+expect) | G, honest solver (lane 06) |
| 19 | deduplicate heights (`EliminateDuplicateFunctions.cpp:95-136`) | 06 | equivalence classes by height | symbol-use graph, own SCCs, waves | program, pre-defunc | itself | 1 | G on the reference graph (lane 06) |
| 20 | `ReadySet` + `Scheduler` (`ReadySet.cpp:27`, `Waves.cpp`) | 09 | dynamic SCC schedule, per-function `Summary` | nodes by name, `Scc` with counts, merges | program, graph grows | optimize | 1 | the dynamic client of S (T5.3, lane 09) |
| 21 | specialization order and keys (`Specialize/Order.cpp`, `Requests.cpp`) | 09 | homeomorphic embedding per owner | keys by owner | program | redirect | per request | lane 09 (L5 of §5.7) |
| 22 | contify's single use (`Contify.cpp:88-104`) | 09 | one call from the same SCC | `SymbolUserMap` | program | itself | 1 | `ProgramGraph` callers |
| 23 | stack inference (`Stack.cpp:116-269`) | 08 | escapes, fills, frame values | per-node `SmallVector<unsigned,2>` graph, `DenseMap<Value, unsigned>`, `BitVector` markings | program | rc-stack | 1 | G on the shared `Graph` (lane 08) |
| 24 | classes and placement (`Transforms/Ownership/Classes.cpp`, `Placement.cpp`) | 08 | placement per value | `DenseMap<Value, Class>` per function (`Transforms/Ownership.h:152`) | function | rc-grades | 1 | lane 08 |
| 25 | demand (`Demand.cpp`) | 08 | in-place promise kept | reads exclusivity's grades | program | refusal | 1 | lane 08 |
| 26 | frames plan (`FramesPlan.cpp`, `Frames.cpp:349-358`) + `closureLabels` | 10 | frames per component | per component; `Members` by name | per SCC | frames | 1 | lane 10 |
| 27 | accumulator plan, TRMC `contextAt`, tail position (`AccumulatorPlan.cpp`, `IR/Tail.cpp`) | 10 | tail shapes | per query | block | accumulate, trmc, tail-loops, Borrows, Stack, Recursion, Lifetimes | per query | T on the call (T5.8, lane 10/03) |
| 28 | `TailCallPlan` + `TailPaths` (`Conversion/TailCallPlan.cpp:69`, `TailPosition.cpp:258-283`) | 10/12 | tail calls on LLVM | `DenseMap<Value, Known>` per function; `SymbolUserMap` | module | tail-calls | 1 | reads the carried tail fact (T5.8) |
| 29 | narrow facts, versions, widths, carried (`Narrow/*.cpp`) | 11 | word candidates | per function | function | narrow-words | 1 | lane 11 |
| 30 | One-Shot module analysis (`Bufferize/Bufferize.cpp`) | 11 | in-place buffers | upstream's own callee-first order | program | bufferize | 1 | U as is (lane 11) |
| 31 | `TypeGraph`, `Layouts`, ValueFacts sealing (`IR/TypeGraph.cpp:57`, `Layouts.cpp:41`, `ValueFacts.cpp:266`) | 01 | type containment, layouts | SCCs over types | program | knots, layouts, verifier | many (outside the manager) | cached once (0003, lane 01) |
| 32 | program verifier (`Verify/Program.cpp`) | 01/13 | effects covered, recycles, knots | rebuilds `Layouts`, `TypeGraph`, `bodyEffect` | program | after every pass | per verify | lane 01/13 |
| 33 | flow edges, carriers (`IR/Flow.cpp:76-87`) | 02 | how values move | per op, per query | op | Labels, Lifetimes, Borrows, verifier | per query | lane 02 |
| 34 | canon helpers (`Canon/Feeds.cpp`, `Sink.cpp`, `Crashes.cpp:20`, `MoveOut.cpp`) | 04 | feeds, sinkable, non-empty | per query walks | op | canonicalize | per query | lane 04 |
| 35 | lifetimes edges (`IR/Lifetimes.cpp:68-129`) | 08 | frame rules | per op | op | Stack, verifier | per query | lane 08; W3 item below |
| 36 | partition (`Target/Partition.cpp:234`) | 13 | bins of the reference graph | own SCCs on LLVM IR | module | codegen | 1 | lane 13 |
| 37 | expect properties (`Transforms/Expect/*`) | 19 | test properties | recompute analyses | module | tests | per test | lane 19 |
| 38 | frontend `Recursion.idr` (Tarjan over size-change graphs) | 15/16 | `terminating`, hence `total` | `SortedMap Address Nat` search | pre-defunc definitions | `total` property, read by `bodyEffect` (`Func.cpp:190`) | 1 | Idris side (lane 15/16): a different graph, essential |

Three observations stand out (*read*, and *measured* where counted):
- **Every honest solver of ours has its own graph type and its own
  worklist**: Labels (interned sets), Exclusivity (items), Stack (per-node
  `SmallVector<unsigned,2>`), Identities (record of `Id`s), observableRuns
  (index adjacency), BindingTimes (tuples), the ready set (`Scc` structs),
  deduplicate (index adjacency plus heights), plus the ten `Scc` users'
  index adjacencies. Dense numbering is already used, ad hoc, in at least
  six of them, each with its own `DenseMap<..., unsigned>` to mint it.
- **The optimizer is already a summary layer.** "One summary per function
  holds its effects, identities, binding times, constants and inline
  facts, computed when its component is ready and published when it is
  final" (`Passes.td:268-271`; `Waves.cpp:287-288`): five of this lane's
  analyses are its transfer functions, scheduled over a dynamic SCC
  wavefront (`Waves.cpp:323-347`) whose graph grows (specialization nodes,
  `Waves.cpp:259-275`) and whose components merge (`Waves.cpp:142-192`).
- **No analysis fact is kept in a discardable attribute** (W-E4,
  *measured*: the one `setAttr` with a string name in `lib`,
  `ContentNames.cpp:116`, is a printing vehicle). Facts that cross passes
  are properties (`effects`, `total`, `no_inline`) or types (grades).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs that touch this lane

- **§2's list "still on upstream's dataflow framework"**: holds (*measured*,
  §2.3). Note that two of the seven are already per-function solves
  (idr-constants per function; Copy per loop).
- **§2 / §5.3 B8: "`lib/Support/Scc.cpp` is, by its name, a hand-rolled
  `scc_iterator`"**: refuted. It runs `llvm::scc_iterator` over a
  `GraphTraits` specialization (`Scc.cpp:24-30, 45`). What holds is
  §5.3 M4's point in another form: the graph is copied three times per
  call (the caller's adjacency, the `Vertex` copy, the output;
  `Scc.cpp:37-51`, `Scc.h:35-51`), and every user builds its own
  adjacency.
- **§5.1 A6 (per-function scope with summaries through
  `visitExternalCall`)**: holds, and is already built: idr-constants
  (`Transforms/Effects/Constants.cpp:186-191`, `Constants.cpp:37-43`). It
  ran on the stage-1 module inside idr-optimize (0001's record reaches
  passes after idr-optimize). This is the one in-tree measurement that
  §5.1 Design 1's per-function shape scales.
- **§5.1 5.1.2 #2 (what goes back on the framework per function)**:
  holds in part. Constants already is. Narrow's Copy already is (per
  loop). Ranges and Returned are whole-program solves today and are the
  cases the item is about. Borrows is not a per-value sparse problem: it
  is a two-point marking over parameters and read values whose states
  live only at points after calls (`Borrows.cpp:180-193, 225-246`), so it
  belongs to §5.3 S1's `mark` or §5.9 Design 1's two-point cells, not to a
  sparse framework analysis (lane 07 decides). "`Recursion`,
  `BindingTimes` ... per-value lattices with summaries": refuted for both:
  Recursion holds no lattice (a bit per function off CallCycles plus a
  body walk, `Recursion.cpp:16-44`), and BindingTimes is relational (a
  tuple of abstract arguments per reach, `BindingTimes.cpp:83-116`), not
  per value. "`Ranges`' return ranges": holds.
- **§5.1 A7 (baseline coupling)**: holds, with a cost in this lane:
  Ranges, Returned and Copy load `DeadCodeAnalysis` and SCCP only to have
  executable blocks (`Ranges.cpp:72-74`, `Returned.cpp:154`,
  `Copy.cpp:71`), so each pays a second per-value lattice (SCCP's) on every
  anchor. Returned's lattice reads no constant at all.
- **§5.1 B4/B3 (`remove-dead-values`)**: already out of the pipeline
  (16005000; `Pipeline.cpp:95-105`): dead parameters are decided by the
  optimizer's specialization holes, and counting drops the rest. No
  signature solver exists to split it into (QA3 evidence, §6).
- **§5.1 C2, W3 (quadratic interface helpers)**: holds for one site, new
  here: `IR/Lifetimes.cpp:50-54` asks `isRepetitiveRegion` of a match's
  parent once per terminator, from idr-rc-stack's graph build
  (`Lifetimes.cpp:85`, called per op from `Stack.cpp:133`); upstream's
  `traverseRegionGraph` allocates and clears a `SmallVector<bool>` of the
  op's region count on every call
  (`.toolchain/llvm-project/mlir/lib/Interfaces/ControlFlowInterfaces.cpp:234-241`),
  so a match of N cases costs N allocations of N bytes: O(N²) bytes zeroed
  per match (*read*; the time is *conjecture*: about a second at N =
  30,000). The other sites ask once per op or are guarded
  (`Linearity.cpp:126` only for non-exclusive branches;
  `ExclusivityGraph.cpp:65-95, 191-221` once per point after e96bb991;
  `Uses.cpp:101`, `Flow.cpp:44-62` once per op or terminator, O(1) per
  match terminator since `IdrMatchOps.td:63-71` answers a terminator with
  the parent alone). `Bufferize/Releases.cpp:111` calls
  `insideMutuallyExclusiveRegions` per pair (O(N·depth) each, §5.1 C2) and
  `Releases.cpp:44` `isRepetitiveRegion` per region (lane 11).
- **§5.1 D3, W4 (`RecursiveMemoryEffects` on a match)**: holds
  (`IdrMatchOps.td:26`). Lane 02 owns the declaration; for this lane it
  means every `wouldOpBeTriviallyDead` in idr-constants' rewrite
  (`Transforms/Effects/Constants.cpp:149`) walks a match's body.
- **§5.1 E1, §5.4 Design 1, §5.6 item 7 ("a wavefront over the SCC DAG ...
  has no precedent; it is ours to design")**: refuted in part: idr-optimize
  already runs one (`Waves.cpp:323-347`: every component whose callees are
  final, in parallel, `failableParallelForEach`), dynamic besides. What it
  lacks: `enable` rescans every component after each wave
  (`Waves.cpp:64-83`, O(waves × components), 0003), and a giant
  component's members run serially (`Component.cpp:257-269`).
- **§5.1 E2 (`SymbolUserMap` cost)**: holds; seven constructions in
  `lib`, four in the compile pipeline and three in test instrumentation
  (*measured*: `Effects.cpp:39`, `Contify.cpp:89`,
  `Contracts.cpp:200, 244`, `Returned.cpp:163`, `Expect/Continuations.cpp:26`,
  `TailCallPlan.cpp:77`), each to recover callers that the call graph
  analysis does not expose.
- **§5.1 F1 (threading contract)**: holds (§2.4).
- **§5.2 A8 (hierarchy-aware resources make "does IO" one query)**: bears
  on `observableRuns`, which reads the `ObservableIO` trait
  (`Effects.cpp:66`) and on `bodyEffect`'s classifier (`Func.cpp:189-201`),
  which reads `MayCrashOpInterface`, `WorldNewOp`, `RunsLabelsOpInterface`
  and world-typed arguments beside MLIR's effects (the comment admits it,
  `Func.h:32-34`). The effects model is lane 02's; the summary over it is
  this lane's.
- **§5.3 M7 ("our recent fixes are the SCCP shape, found by hand")**:
  holds, and extends to this lane: Identities is extract (`Record`) then
  solve (greatest fixpoint), observableRuns is a backward marking,
  idr-effects is a union summary; each with its own graph.
- **§5.3 S1 deletes ("the hand-rolled SCC utility, per-analysis worklists
  and graph types ...")**: holds in part. `Scc.cpp` stays as an
  `scc_iterator` call but loses its copies; the per-analysis graph types
  and the dead `MonotoneWorklist` go; `OnceWorklist` stays for its honest
  uses (a set of things to visit once that is not a graph's marking).
- **§5.4 5.4.2 #2 ("CallCycles, Recursion, Effects, Inline, the label
  solve, optimize, the deduplicator ... each a summary per function,
  callees first")**: holds in part. CallCycles is the order, not a
  summary. Effects and the inline facts are callees-first summaries.
  Identities is a greatest fixpoint per SCC with callees frozen. Recursion
  is a per-function bit. BindingTimes is intra-SCC only (no callee is
  read). The label solve is not over the call graph (it runs before the
  program is first-order, over flow points). The deduplicator is
  callees-first over its own symbol-use graph.
- **§5.4 Design 1 ("deletes `lib/Support/Scc.cpp`, `CallCycles`,
  `Recursion`'s own SCC order, the deduplicator's waves, `optimize`'s own
  bottom-up scheduling")**: holds in part. Recursion has no SCC order of
  its own (it reads CallCycles). The optimizer's scheduling cannot be a
  static `SCCGraph`: its graph gains nodes during the solve and merges
  components when waits close a cycle (`Waves.cpp:142-192, 259-275`). That
  is essential (specialization makes functions while summaries are being
  computed), so the shared spine must offer insertion and merge, or the
  optimizer stays the one dynamic client of the same summary types.
- **§5.6 item 2 / D4 (one call graph, cached and kept up to date; IREE's
  14 rebuilds are the chain to kill)**: holds: up to seven `CallCycles` builds
  per pipeline (§2.2) plus the independent derivations of chain R1 (§5).
- **§5.6 item 3 (summaries in a typed table, never in attributes)**:
  holds, with a twist: the one summary every pass reads (effects) is
  already in the IR as a verified property, which is §5.8 DS2.1's first
  option and Q-E2's "IR" side. The others live in the optimizer's
  `Summary` record (`Waves.cpp:287`) and die with the pass.
- **§5.6 item 5 / Q-E3 (a budget degrades a site)**: holds for every
  budget in this lane (W-E5 below).
- **§5.7 B3 (no whole-module use-def chains; the reference graph is the
  layer's to build)**: holds; built twice today, differently: the
  deduplicator's symbol-use graph (`EliminateDuplicateFunctions.cpp:95-120`,
  calls and closure references, before defunctionalization) and
  `Target/Partition.cpp` (after LLVM). After defunctionalization the call
  graph is the reference graph's call part.
- **§5.7 L2 (one scoped sparse core)**: holds in part; Identities' `Record`
  is already a scoped, read-only, dense-numbered view of one function
  (`IdentitiesRecord.cpp:84-122`), freed after its component (QL1 evidence).
- **§5.8 T6 / DS2.1 (a call's effects read off the callee's type or an
  inherent property verified by `verifySymbolUses`)**: holds and is built:
  `Call.cpp:29-58`.
- **§5.9 B3 (`analyze.fun`)**: holds for Exclusivity, Stack, Labels,
  observableRuns and effects (constraints on cells, handlers or a marking,
  no program points). Identities is the dual (cells start assumed and only
  drop: a greatest fixpoint over two points). BindingTimes is relational,
  which a per-value cell cannot hold without the tuple.
- **§5.11 A1 (memory a stated property of each solver)**: no header of
  this lane states its state's size; Ranges and Returned would state
  "per value of the program, at A4's cost", which is the shape of the
  walls (§8).
- **0003 items in this lane**: "Analyses dropped and rebuilt" holds
  (`Transforms/Effects/Effects.cpp:39`); "`givesBack` solved twice" holds
  (`Component.cpp:238-239` and `Returned.cpp:152-191`); "Ranges discarded
  ... and re-solved" holds (`Narrow.cpp:154-165`); "Identities' parallel
  `arguments`, `slots` and `types` and the `Drop` pair" holds
  (`Identities.h:182-184`, `Identities.cpp:96`).

### 3.2 Wave-2 questions answered

- **W1** (§5.1: V, B, P, F at each solve point). Not measurable here: no
  built compiler and no stage-1 module in this checkout. The one recorded
  fact is §5.1 H1's inference (V ≈ 10 million at `remove-dead-values`).
  Needed: a statistic pass counting values, blocks, ops and functions, run
  on the stage-1 module before idr-narrow and before
  idr-returned-arguments, the two whole-program solves not yet reached.
- **W2** (each analysis: lattice, interprocedural, summaries, Design 1 or
  3). §2.6's table; in short: Constants per value, per function, summary
  of returns: Design 1, built. Ranges per value, whole program today: needs
  return and argument summaries for Design 1 (§5, T5.7). Returned per
  value, whole module: a per-result bit summary suffices (Design 3/S).
  Borrows per parameter: a marking (Design 3). Recursion, effects, inline
  facts, identities, binding times: per function or per parameter, solved
  per SCC: the summary layer (Design 3 / Shape S).
- **W3** (per-query edge tables): §3.1 above: `Lifetimes.cpp:50-54` is the
  one quadratic site; `Releases.cpp:44, 111` are lane 11's per-region and
  per-pair queries.
- **W4** (who carries `RecursiveMemoryEffects`): the match ops
  (`IdrMatchOps.td:26`); lane 02 counts the rest.
- **W5** (attributes created on a hot path): in this lane, the label sets
  `Labels::labelsOf` returns are uniqued `ArrayAttr`s (`Labels.h:290-295`,
  lane 06); SCCP's `getPropertiesAsAttribute` (§5.1 A7) runs in
  idr-constants (every function, every round), Ranges and Returned; Copy
  creates a scratch `ModuleOp` and an `IntegerAttr` per bound per trial
  (`Copy.cpp:30-63`).
- **W6** (passes anchored on functions): every analysis pass of this lane
  is a program pass (effects, contify, optimize, narrow) or module pass
  (returned-arguments, tail-calls); per-function work is nested by hand
  (idr-narrow-words, idr-returned-arguments-drop, the optimizer's inner
  pipeline through `runPipeline`). Lane 13 owns the pipeline.
- **W7** (reliance on backward callee resolution in a non-interprocedural
  solve): none: no backward sparse analysis exists in the tree (§2.3).
- **§5.3's wave-2 list**: worklists in this lane: `OnceWorklist` FIFO
  over pointers or indices (BindingTimes, Identities, observableRuns),
  `MonotoneWorklist` dead; `DenseMap`s per solve except
  `Identities.cpp:86-90` (`DenseMap<StringAttr, SetVector<unsigned>>`, a
  `SetVector` per callee, a per-node container); `function_ref`s
  `Effects.h:51` (`LabelsRun`), `Constants.h:39` (`ConstantsOf`),
  `Identities.h:45` (`Outside`), `Scc.h:34` (successors) and
  `Inline/Inline.cpp:117` (callee): each callee's static type is known
  (one caller each), so each is a template parameter or a
  `const SummaryTable&` (I5); variants `BindingTimes.cpp:57`
  (`Abstract`), `Identities.h:141, 152, 169` (`Build`, `Fact`, `Arm`),
  `Tail.h:238-262` (`Known`): each visited by `llvm::makeVisitor` except
  `IdentitiesRebuilds.cpp:222` and `Tail.h:246, 253-255` (`get_if` and
  `holds_alternative` validators); `Scc.cpp` against `scc_iterator`:
  answered above; mutexes and `parallelFor` in this lane: §2.5. "The seven
  files on `DataFlowSolver`: which solve within one function (S2) and which
  over the whole program (S1)": §2.3.
- **§5.4's wave-2 list**: "which analyses are summaries over the call
  graph, in which direction, and does each compute its own SCC order":
  §3.1 (5.4.2 #2) and chain R1 (§5.13). "How predecessors of region
  successors are computed today in each client": Exclusivity after
  e96bb991 inverts successors once per point
  (`ExclusivityGraph.cpp:186-221`); Flow asks per op and per terminator
  (`Flow.cpp:44-62`); the framework users get them from upstream's
  `PredecessorState`. "Whether our call op can implement upstream's
  `CallOpInterface`": it does already (`CallCycles.cpp:7-8` builds on it;
  `CallGraph` resolves `idr.call`).
- **§5.6 W-E1** (who derives call-graph or SCC facts on its own; which
  passes change calls without telling anyone): chain R1 (§5.13) lists the
  derivations. Passes that change calls: idr-defunctionalize
  (makes them), idr-contify, idr-optimize (inline, specialize, redirect,
  identity), symbol DCE, idr-frames, idr-accumulate, idr-trmc, idr-rc-exclusive
  (grade copies and redirects, `Exclusive.cpp:40-46`), idr-tail-loops,
  the lowering. None updates a call-graph analysis; all rely on
  invalidation, which is correct and rebuilds it up to seven times.
- **W-E2** (state only for values whose type leaves the question open):
  in this lane, Ranges keeps states for every value (types without an
  integer storage width are skipped only by readers, `Copy.cpp:88`); the
  seed already reads the type (`Ranges.cpp:30-33`). Identities keeps
  records only for functions whose result type matches an argument's
  (`Identities.cpp:24-36`): already type-filtered.
- **W-E3** (analyses computed by more than one pass, and which could be
  preserved): `CallCycles`/`CallGraph` (up to seven builds; idr-effects
  and every pass that does not change calls could preserve it, as
  idr-frames already does when it performs nothing; contify could update
  it in place); effects (idr-effects,
  idr-optimize, the verifier); gives-back (idr-optimize, idr-returned-arguments);
  constants (idr-constants and three SCCP baselines); ranges (two
  whole-program solves and the lane solves); `TypeGraph` and `Layouts`
  (lane 01).
- **W-E4**: none (§2.6).
- **W-E5** (every budget, and whether one fails): this lane's:
  `Inline.h:23-30` (`kLeafSize` 40, `kSmall` 60, `kProduct` 320,
  `kCallerCap` 10,000): each leaves a call a call (`Inline/Inline.cpp:148-151`);
  upstream's range widening after 128 merges (`Ranges.h:25-33`): loses
  precision only; the narrowing search over exponents 8 to 31
  (`Lanes.cpp:81-83`): a fixed search; upstream's greedy default of ten
  rounds in `Copy.cpp:128`, result ignored. Others, for completeness:
  `Stack.cpp:78-80` (cell 256, frame 1,024, recursive frame 64: a cell
  stays on the heap), `Canon/Sink.cpp:54` (64), `Target/Schedules.cpp:76`
  (10 rounds). Exclusivity's outer loop (`Exclusivity.cpp:73-120`) ends by a
  measure (labels only go), not a count. None becomes a failure or a
  refusal (*read*).
- **W-E6** (queries that enumerate a match's regions per query): the
  `isRepetitiveRegion` site above; `RecursiveMemoryEffects` walks (lane 02).
- **W-E7** (`DenseMap<Value, ...>` a dense number would replace): 21 maps
  and 4 sets in `lib`/`include` (*measured*: `grep -rn
  'DenseMap<\(mlir::\)\?Value' lib include | wc -l`); in this lane
  `IdentitiesRecord.cpp:97` (per function); whole-program ones elsewhere:
  `Stack.cpp:265`, `ExclusivityAnalyses.cpp:316`, `ExclusivityDetail.h:155`,
  `Defunctionalize.h:105-106, 210`. Numbering cost: one walk per scope,
  already paid by each of them separately.
- **W-E8** (single-block regions after defunctionalization): a match's
  regions are `SingleBlock` (`IdrMatchOps.td:26`); a function's body is
  one block except transiently in contify and inlining
  (`Contify.cpp:33-41`, `Inline/Inline.cpp:160-164`); `cf` only after
  lowering (`Pipeline.cpp:186`).
- **W-E9** (state copied per edge or branch): none in this lane; the one
  copy per visit is BindingTimes' tuple copy (`BindingTimes.cpp:128`).
- **§5.7's wave-2 list**: PLV, PVP or relational: Constants and Ranges
  PLV (per value), Returned PLV, Borrows a per-parameter PVP marking,
  BindingTimes relational (tuples), Identities per function with
  per-argument facts (PVP across arguments, `IdentitiesRebuilds.cpp:99-106`).
  Which share a scope and could be one product solve: the five optimizer
  summaries are already computed together per component
  (`Component.cpp:212-250`), each by its own walks (per member: at least
  one for `bindingTimesOf`, three for Identities, two for the inline
  facts, one for `componentEffects`, three for the call-effects writes;
  `returnedConstants` reads only the terminator); which read another's frozen
  answer: Recursion reads CallCycles; Borrows reads Reuses and CallCycles;
  Identities reads the effects property; idr-constants reads the
  summaries.
- **§5.9 Q-W2**: §2.6's state column; flow-sensitive by need: Constants
  and Ranges inside a function only through SCCP's executability; none of
  this lane's analyses keeps a fact per program point.
- **§5.10 W1** (dup/drop and liveness components): lane 07/08.

## 4. Issues

Every row is *read* at the line given unless it says otherwise. The
disposition names the T-item of §5 that carries it. Rows owned by
another lane are marked with that lane and are listed because they are a
framework use, an analysis-manager use or a rederivation chain, which
this lane inventories.

### 4.1 CallCycles, Recursion, the SCC utility, the worklists

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| CC1 | `CallCycles.cpp:28-33` | state | an extra pre-order walk of the whole program for body-less callables, beside the call graph's own two walks | `ProgramGraph` built in one walk (T5.1) |
| CC2 | `CallCycles.h:55-58`, `CallCycles.cpp:18-23, 41-44` | state | three copies of one partition (`all`, `indices`, `selfCalling`) on top of upstream's graph | one dense `FunctionId` table: `sccOf[id]`, SCCs as ranges (T5.1) |
| CC3 | `CallCycles.cpp:48-50` | rederivation | invalidated by every pass that does not preserve it by name, and none does (*measured*: 0 sites): up to seven builds per pipeline | preserved by name where calls do not change; updated in place by contify (T5.1, T5.10) |
| CC4 | `CallCycles.h:39-52` | rederivation | exposes components only, no callers or callees, so seven sites build a `SymbolUserMap` (four in the pipeline) and nine keep name maps to recover them (chains R1, R9) | callers, callees and call sites in the graph (T5.1) |
| CC5 | `CallCycles.h:52`, `CallCycles.cpp:43-44` | rederivation | `callsItself` exists, yet `Inline.cpp:25-28`, `Waves.cpp:228-234`, `Recursion.cpp:33-36` re-walk bodies for a self call (chain R2) | one self-edge bit in the graph; the walks go (T5.1) |
| CC6 | `CallCycles.cpp:34` | upstream | depends on upstream `CallGraph`, rebuilt from scratch each time (§5.1 E1; `eraseNode` O(nodes)) | ours built on `CallOpInterface`; an upstream RFC for a maintained graph (Q-E5) |
| RC1 | `Recursion.h:19-31`, `Recursion.cpp:16-44` | dead (as a class) | an analysis class for one bit per function, read by one budget (`Stack.cpp:310`) | `ProgramGraph::recursive(id)`; class and header deleted (T5.1) |
| RC2 | `Recursion.cpp:33-36` | rederivation | self call by name compare and `tail::inTailPosition` per call, beside `tail::isSelfCall` (`Tail.cpp:50-53`) and `lifetimes::loopsInFrame` (`Lifetimes.cpp:59-66`) and Stack's own walk (`Stack.cpp:250-258`): three formulations of "loops in its frame" (chain R3) | one per-call tail fact (T5.8) read by the graph build |
| RC3 | `Recursion.h:30` | state | `DenseSet<Operation*>` for a bit per function | a `BitVector` over `FunctionId` (T5.1) |
| SC1 | `Scc.cpp:17-30, 37-43` | state | the caller's adjacency copied into `std::vector<Vertex>` with a `SmallVector` per vertex and a root vertex | `Graph` (CSR) is itself the `GraphTraits` (with `getNumber`); `scc_iterator` walks it without a copy (T5.2) |
| SC2 | `Scc.h:31-52` | cpp | `function_ref<SmallVector<Node>(Node)>` returns a heap vector per node, plus a `DenseMap<Node, unsigned>` numbering per call | callers hand a `Graph` whose ids they minted once; the template and its map go (T5.2) |
| SC3 | `Labels.cpp:261`, `TypeGraph.cpp:110, 185`, `ValueFacts.cpp:266`, `Layout/Components.cpp:167`, `DataRemap.cpp:257`, `Partition.cpp:234`, `EliminateDuplicateFunctions.cpp:126`, `Expect/Cycles.cpp:34` | list | ten users each build `SmallVector<SmallVector<unsigned>>` by hand | each builds one `Graph` (lanes 01, 06, 13, 19 own the users) (T5.2) |
| WL1 | `Worklist.h:96-153` | dead | `MonotoneWorklist`: no user (*measured*) | deleted (T5.12) |
| WL2 | `Worklist.h:52-63` | dead | `FiniteLattice`, read only by `MonotoneWorklist` | deleted with it; the solver layer's `Summary`/`Lattice` concept replaces it where one is needed (T5.2) |
| WL3 | `Worklist.h:65-94` and 30 files | state | `OnceWorklist` (a `SetVector` plus a cursor) used both as a set of things to visit and as a graph marking (`Effects.cpp:85-94`, `Waves.cpp:128-139, 152-161`, `TailCallPlan.cpp:52`, `Exclusivity.cpp:94`) | markings become `mark(graph, seeds)` on a `BitVector`; `OnceWorklist` stays for the rest (T5.2) |

### 4.2 Effects and observableRuns

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| EF1 | `Effects.cpp:36-47` | upstream (layer) | a Shape-S summary written by hand over CallCycles | `solveBottomUp<Effect>` in the solver layer, `bodyEffect` its transfer (T5.3) |
| EF2 | `Effects.cpp:37-39` | rederivation | a `SymbolTableCollection` and a whole-program `SymbolUserMap` per solve to find each function's calls (chain R1; §5.1 E2's 64-bucket `SetVector` per symbol) | call sites from `ProgramGraph` (T5.1) |
| EF3 | `Effects.cpp:49-54` | rederivation | `positions` (`DenseMap<Operation*, unsigned>`) mints a dense function number again (chain R9) | `FunctionId` (T5.1) |
| EF4 | `Effects.h:51-52`, `Effects.cpp:70-71` | cpp | `LabelsRun` is a `function_ref` whose one caller (`Defunctionalize/Pass.cpp:110-115`) holds `Labels` statically | take `const Labels &`, or move the reach beside the label solve (lane 06) (T5.3) |
| EF5 | `Effects.cpp:66` | ods (lane 02) | "observes" read off the `ObservableIO` trait, one of the "does IO" representations (§2) | a query over effect instances on the resource tree (§5.2 A8), lane 02 |
| EF6 | `Effects.cpp:68-71` | ladder | `dyn_cast<CallOp>` then `dyn_cast<RunsLabelsOpInterface>` to find what an op runs | one question to the graph builder: call edges and label-run edges (T5.3) |
| EF7 | `Effects.cpp:79-94` | state | a hand reverse adjacency and a `OnceWorklist` backward reach | `mark(graph, seeds, Backward)` (T5.2) |
| EF8 | `Func.cpp:189-201` | ods (lane 02) | `bodyEffect`: an `isa` ladder (`MayCrashOpInterface`, `WorldNewOp`, `RunsLabelsOpInterface`) plus world-typed arguments, a second effects model beside MLIR's (`Func.h:32-34`) | lane 02's one effects model; the summary's transfer reads it |
| EF9 | `Func.cpp:225-230` | rederivation | `writeEffects` needs a `SymbolUserMap` (callers) | callers from `ProgramGraph` (T5.1) |
| EF10 | `Verify/Program.cpp:53-71` | rederivation (lane 01/13) | after every pass the verifier recomputes `bodyEffect` of every function and joins its calls': a whole-program walk per verification for a fact the call's `verifySymbolUses` and a local check already bound | keep the check (AGENTS.md verifies after every pass); make it per function and parallel (§5.2 M11); lane 13 measures |
| EF11 | `Component.cpp:73-81`, `:213-214`, `Waves.cpp:291-292` (lane 09) | rederivation | `writeCallEffects` walks a member's body at each turn, at finish and at finalize (three walks per function) | call sites listed once per function in the summary layer (T5.3) |
| EF12 | `Transforms/Effects/Effects.cpp:39` | rederivation | preserves only `SymbolTable` though it writes properties alone (0003) | `markAnalysesPreserved<ProgramGraph, CallGraph, TypeGraph, Layouts, SymbolTable>()` (T5.10) |
| EF13 | `Transforms/Expect/CrashSites.cpp` (counts `NoReturn`) vs `Func.cpp:194-195` (`MayCrashOpInterface`) | rederivation (lanes 02, 19) | "may crash" counted two ways (0003) | lane 02 |

### 4.3 BindingTimes

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| BT1 | `BindingTimes.cpp:34-42`, `BindingTimes.h:27-28` | list | `nameOf` switch, a stringify for the report pass only | a `constexpr` table indexed by the enum (§5.5 D4b), or the report reads the summary's own printer (T5.4) |
| BT2 | `BindingTimes.cpp:47, 173-175` | rederivation | `Members`, a `DenseMap<StringAttr, FuncOp>` of the component rebuilt per call (chain R9) | `FunctionId` and the SCC's id range (T5.1) |
| BT3 | `BindingTimes.cpp:51-64` | cpp | a two-alternative variant `Abstract` plus `code()` re-encoding it as an integer: two representations of one value | the code is the representation (0 = anything, k+1 = parameter k) in a typed `enum class AbstractCode : unsigned`; the variant goes (T5.4) |
| BT4 | `BindingTimes.cpp:69-81` | rederivation | `eval` recurses through `sourceOf` for every operand on every visit (chain R12) | each call's argument-to-parameter map extracted once per function, as Identities' `Record` does (T5.4) |
| BT5 | `BindingTimes.cpp:110-111` | state | `std::map<SmallVector<unsigned>, Tuple>` (ordered, keys allocate) to intern tuples | interned tuple ids in one hash table, or no tuples (T5.4) |
| BT6 | `BindingTimes.cpp:118-131, 172-177`; `Component.cpp:245`; `Report.cpp:34` | rederivation | one full interpretation per member of a component, each re-reaching every member and re-walking its body: O(members × reach) per component | the extraction shared by all members (T5.4); merging the interpretations is *conjecture* (polyvariance) |
| BT7 | `BindingTimes.cpp:143-151` | rederivation | a reached function is walked again for each tuple it is reached with (`fn.walk` per visit) | the call list extracted once per function (T5.4) |
| BT8 | `BindingTimes.cpp:145` | cpp | callee by name lookup per call per visit | callee `FunctionId` on the extracted edge (T5.4) |
| BT9 | `BindingTimes.cpp:128` | state | the tuple copied per visit ("a push while the body is read may grow the tuples") | stable ids into an arena (T5.4) |

### 4.4 Identities

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| ID1 | `Identities.h:45`, `Component.cpp:236-237` | cpp | `Outside`, a `function_ref` whose one caller is the ready set | read the frozen `SummaryTable` (T5.5) |
| ID2 | `Identities.h:54-58`, `Identities.cpp:39-41, 45-62` | rederivation | `Members` and `Assumed` keyed by `StringAttr` (chain R9) | `FunctionId`-indexed vectors (T5.5) |
| ID3 | `Identities.h:180-184`, `IdentitiesRecord.cpp:104-108` | list | `arguments`, `slots` (a `DenseMap<unsigned, unsigned>`) and `types`: three lists matched by position (0003) | one `SmallVector<Candidate{arg, type}>`; a slot is its index (T5.5) |
| ID4 | `Identities.cpp:96` | cpp | `Drop = std::pair<unsigned, unsigned>` (0003) | a named struct `{slot, argument}` (T5.5) |
| ID5 | `Identities.cpp:55-62, 79-83`; `IdentitiesRecord.cpp:112` | rederivation | three walks of each member (outside callees, member callees, the record) | the record's walk lists the calls; the other two walks go (T5.5) |
| ID6 | `Identities.cpp:86-90` | state | `DenseMap<StringAttr, SetVector<unsigned>> callers`: a reverse call graph rebuilt per component with a `SetVector` (a 64-bucket `DenseSet` once it holds anything, §5.3 B7) per callee | callers from `ProgramGraph` restricted to the SCC (T5.1, T5.5) |
| ID7 | `IdentitiesRecord.cpp:97` | state | `DenseMap<Value, Id>` per walked function | walk-order numbering in the scope view (§5.7 L2) (T5.2) |
| ID8 | `IdentitiesRecord.cpp:58-72, 248-268` | rederivation | `remaining(match)` and `framesAt`: what the enclosing matches say about a value, a fourth copy beside 0003's three (chain R8) | one `knownConstructor(Value, at)` (lane 04's), or case regions that bind the refined scrutinee (§5.7 L1, lane 03) |
| ID9 | `IdentitiesRecord.cpp:47-51, 228-235` | ods (lane 03) | the successor of a natural recognized as `BigAddOp` with a constant one, beside a `BigPredOp` op for the predecessor | a `nat.succ` op mirroring `pred` would make `S k` a fact; lane 03 decides |
| ID10 | `IdentitiesRecord.cpp:209-243` | ladder | `internResult`: `MatchOpInterface`, `CallOp`, `BigPredOp`, `ConOp`, `BigAddOp`, constants, as `if (dyn_cast)` | one `TypeSwitch` with `Default` inside the pass (§5.3 I2) (T5.5) |
| ID11 | `IdentitiesRecord.cpp:292-297` | ladder | `isa<YieldOp, ub::UnreachableOp>` for the terminators a region may end in | `RegionBranchTerminatorOpInterface` and the match verifier's own rule (lane 03) |
| ID12 | `IdentitiesRebuilds.cpp:89-95, 269-272` | state | a fresh `Reading` (memo vector and interned parts per slot) per check of a requeued member | keep the reading per member across checks, invalidated by the drops it read (*conjecture* on gain) (T5.5) |
| ID13 | `IdentitiesRebuilds.cpp:222` | cpp | `std::get_if<KnownTag>` validator on a `Fact` | one exhaustive `match` (§5.5 D2) |
| ID14 | `Component.cpp:238-239` vs `Tail/Returned.cpp:152-191` | rederivation | the answer dies with idr-optimize and is re-solved after lowering (chain R5; 0003) | carried as a function fact to lowering (T5.5) |

### 4.5 Inline facts

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| IN1 | `Inline.cpp:14-18`, `:21`; `Inline/Inline.cpp:124, 144`; `Optimize.cpp:110`; `Expect/Sizes.cpp:25` | rederivation | `inlineSize` walks the whole body per ask (chain R10) | the size kept on the node and updated by each inline (`size += calleeSize - 1` already, `Inline/Inline.cpp:156`) and by each pipeline run's statistics (T5.6) |
| IN2 | `Inline.cpp:21-28` | rederivation | a second walk right after `inlineSize`'s for leaf and self call; self call is CallCycles' (chain R2) | one walk; self call from the graph (T5.1) |
| IN3 | `Inline.h:23-30` | budget | `kLeafSize`, `kSmall`, `kProduct`, `kCallerCap`: optimization budgets in ops that leave a call a call; never a refusal | keep; state them in the layer's header as program-unit budgets (Q-llvm-2, oom A4) |
| IN4 | `Inline.h:34-39` | cpp | `Facts{size, bool inlines}`: a flag where a sum `Keep | Inline{size}` carries what is read (`Inline/Inline.cpp:136-140` reads size only when inlining) | the sum (§5.4 Design 7) (T5.6) |
| IN5 | `Inline/Inline.cpp:117` (lane 09) | cpp | the callee answer through `function_ref<optimize::Callee(StringAttr)>` whose one caller holds the ready set | `const ReadySet &` or the summary table (lane 09) |

### 4.6 Constants (the analysis and idr-constants)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| CO1 | `Transforms/Effects/Constants.cpp:73-169` | upstream | `replaceWithConstant` and `rewrite` are upstream SCCP's file-static functions (`.toolchain/llvm-project/mlir/lib/Transforms/SCCP.cpp:41-112`) re-written with actions and a `changed` flag | `upstream/<bug>/`: export SCCP's rewrite with a listener (actions wrap it), then delete ours (T5.6) |
| CO2 | `Constants.h:39`, `Transforms/Effects/Constants.cpp:180-185` | cpp | `ConstantsOf`, a `function_ref` whose one caller is the ready set | read the summary table (T5.6) |
| CO3 | `Transforms/Effects/Constants.cpp:188-191` | upstream | a per-function solve loads `DeadCodeAnalysis` and SCCP (correct, §5.1 A7), paying A4's fixed cost per value of the function per round | keep; U1 (§5.1) shrinks it; the scope is already the right one |
| CO4 | `Transforms/Effects/Constants.cpp` (file place) | list | the inner step of idr-optimize lives under `Transforms/Effects/` and is created as `idr::optimize::createConstants` (`:205`) | moved beside the optimizer or the layer's per-function solves (lane 09) |
| CO5 | `Constants.cpp:16-30` | — | `returnedConstants` reads the final body: the body is the one copy (0003 §1, derive) | keep (it is right) |

### 4.7 Ranges and the narrowing solves

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| RA1 | `Ranges.cpp:67-79` | state | one whole-program interprocedural solve: two per-value lattices (SCCP's and ranges') plus `Executable`s and `PredecessorState`s, about 2 × 2.9 KB per value at the pin (§5.1 A4) | per-function solves with summaries in both directions, or the whole-program solve after U1 if measured (T5.7, QA2) |
| RA2 | `Ranges.h:40-53` | state | `Ranges::Solved` keeps the whole solver (all states of the program) alive through the nested idr-narrow-words run | per-function solves freed per function; only the summaries cross functions (T5.7) |
| RA3 | `Narrow.cpp:154-165` (lane 11) | rederivation | after versioning, everything but three analyses is invalidated and the whole program re-solved (0003) | re-solve the versioned functions only (T5.7) |
| RA4 | `Ranges.cpp:39-44`, `Tail/Returned.cpp:74-75` | upstream | `ub.poison` special-cased by hand in two analyses as "any value" | an upstream patch making `IntegerRangeAnalysis` and the sparse framework treat a poison constant as bottom (*conjecture* on the form; a report first) (T5.7) |
| RA5 | `Ranges.cpp:51-60` | ods (lane 03) | `visitNonControlFlowArguments` override for `MatchLitOp`'s default region, which binds the scrutinee without forwarding it | the default region's argument as a forwarded entry operand (`getEntrySuccessorOperands`), so upstream joins it; the override goes (lane 03) |
| RA6 | `Ranges.cpp:72-74` | upstream | baseline loaded for executability alone (§5.1 A7) | U4 when it lands (#193112) |
| RA7 | `Ranges.h:24-33` | budget | upstream's widening after 128 merges: precision only | keep (an upstream budget of the allowed kind, §5.1 B5) |
| NL1 | `Narrow/Copy.cpp:116-125` (lane 11) | upstream | a `RewriterBase::Listener` erasing solver states, which upstream writes twice, file-local (`IntRangeOptimizations.cpp:117`, `UnsignedWhenEquivalent.cpp:67`) | `upstream/<bug>/`: export one `DataFlowListener`; ours goes |
| NL2 | `Narrow/Copy.cpp:66-76`, `Lanes.cpp:135-158` (lane 11) | — | up to six scoped solves per loop on a scratch module | keep (S2; the scope is right) |

### 4.8 Returned, Borrows (framework parts)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| RT1 | `Tail/Returned.cpp:152-159` (lane 10) | state | a whole-module interprocedural solve with the baseline loaded: per value a `KnownLattice` and SCCP's lattice | deleted by the carried gives-back fact (T5.5), else a per-result summary (T5.3) |
| RT2 | `Tail/Returned.cpp:162-169` (lane 10) | rederivation | a `SymbolUserMap` for eligibility (chain R1) | callers from the lowered module's graph |
| RT3 | `Tail.h:252-258` (lane 10) | cpp | `Known::join` by `holds_alternative` | one `match` (§5.5 D2) |
| BO1 | `Ownership/Borrows.cpp:162-304` (lane 07) | state | a two-point marking run on `DataFlowSolver` as a subscription worklist: A4's fixed cost per `HoldingState` | the solver layer's marking (lane 07) |
| BO2 | `Ownership/Borrows.cpp:233-246` (lane 07) | rederivation | each revisit of a call recomputes `cycles.together`, `inTailPosition` and `inTailPositionModuloContext` (a block scan and a walk, `Tail.cpp:282-289`) (chain R3) | per-call facts computed once (T5.8) |

### 4.9 Analysis-manager uses and interface queries

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| AM1 | `Contify.cpp:88-89, 128-133` (lane 09) | rederivation | a `SymbolUserMap` for single use; invalidates the call graph though it knows its one edit | `ProgramGraph::eraseInto(fn, caller)` keeps it (T5.10) |
| AM2 | `Optimize.cpp:85, 114-116` (lane 09) | rederivation | the ready set is a maintained call graph built from CallCycles plus its own callee walk (`ReadySet.cpp:34-42`), discarded at the pass's end | built on `ProgramGraph` and leaving it current (T5.3, lane 09) |
| AM3 | `Frames.cpp:349, 371-373`; `Stack.cpp:288-290, 381`; `TailCalls.cpp:139` | rederivation | each rebuilds the call graph after passes that did not change calls (rc-cells, between rc-stack and rc-grades) | preservation by name (T5.10) |
| AM4 | `Narrow.cpp:159-161` (lane 11) | rederivation | a hand `invalidate(kept)` to force a re-solve | per-function re-solve (T5.7) |
| AM5 | `Exclusive.cpp:39-52` (lane 07) | state | `Exclusivity` is no analysis (0003) | a cached analysis (lane 07) |
| AM6 | `Defunctionalize/Pass.cpp:152`, `Layout/Fit.cpp:25`, `Layouts.cpp:67`, `Verify/Program.cpp:104, 266` (lane 01) | rederivation | `TypeGraph` and `Layouts` built outside the manager (0003) | lane 01 |
| IQ1 | `IR/Lifetimes.cpp:50-54` (lane 08), from `Stack.cpp:133` | upstream | `isRepetitiveRegion` per terminator: O(N) allocation per call on a match, O(N²) per match | ask once per parent op (a per-build cache), or an upstream patch making `isRepetitiveRegion` an overridable interface method so a match answers in O(1) (T5.11) |
| IQ2 | `Bufferize/Releases.cpp:44, 111` (lane 11) | upstream | `isRepetitiveRegion` per region and `insideMutuallyExclusiveRegions` per pair | §5.1 U3's patches; lane 11 |

### 4.10 Rederivation chains (cross-cutting; detail in §5.13)

| ID | first known | computed again | category | disposition |
| --- | --- | --- | --- | --- |
| R1 | the call graph: written by idr-defunctionalize | CallCycles up to ×7; `ReadySet.cpp:34-74`; `EliminateDuplicateFunctions.cpp:95-136` (pre-defunc); `Exclusivity.cpp:84-103` and `ExclusivityGraph.cpp:17-60`; seven `SymbolUserMap`s; `Ranges`/`Returned` `PredecessorState`s; `TailCallPlan.cpp:69-87`; `Effects.cpp:79-82`; `Identities.cpp:86-90`; `Partition.cpp:234` | rederivation | `ProgramGraph` (T5.1) |
| R2 | self call: `CallCycles.cpp:43-44` | `Inline.cpp:25-28`; `Waves.cpp:228-234`; `Recursion.cpp:33-36`; `Tail.cpp:50-53`; `TailCallPlan.cpp:84` | rederivation | graph self-edge (T5.1) |
| R3 | tail position: the IR's shape | `Tail.cpp:31-35, 282-289` per query from Borrows (per visit), Lifetimes (per call), Stack, Recursion, FramesPlan, AccumulatorPlan; again on LLVM by `TailPosition.cpp:258-283` | rederivation | a per-call fact (T5.8) |
| R4 | effects: idr-effects | idr-optimize per component (essential); verifier after every pass; not lowered to LLVM attributes (0003) | rederivation | T5.3; lowering's attributes lane 12 |
| R5 | gives back: Identities in idr-optimize | `Tail/Returned.cpp` on lowered code | rederivation | T5.5 |
| R6 | constants: idr-constants writes them into bodies | SCCP baselines in Ranges, Returned, Copy; canonicalize | rederivation | baseline coupling U4; T5.6 |
| R7 | ranges: Ranges | re-solve after versioning; per-loop solves after lowering; `RuntimeCalls.cpp:37-50` | rederivation | T5.7 |
| R8 | what an enclosing match says | `IdentitiesRecord.cpp:58-72, 248-268`; 0003's three; `Grades.cpp:210-216` | rederivation | lane 04 / L1 |
| R9 | function membership and numbering | `BindingTimes.cpp:47`; `Identities.h:55-58`; `Tail.h:135` (Frames); `ReadySet.cpp:59`; `ExclusivityGraph.cpp:19`; `TailCallPlan.cpp:28`; `Effects.cpp:52-54`; `CallCycles.h:56`; `Tail.h:306` | rederivation | `FunctionId` (T5.1) |
| R10 | function size: the body | `inlineSize` per ask, five callers | rederivation | T5.6 |
| R11 | which code runs | `DeadCodeAnalysis` in four solves; `Exclusivity.cpp:84-103` (`liveBlocksOf`, `reached`); symbol DCE; unreachable-block erasure | rederivation | lane 07 for exclusivity; U4 |
| R12 | "the same value" (`sourceOf`) | `definitionChain` walks per query in BindingTimes, Identities, Borrows, Captures, Reuses, Verify, Classes, Demand, ResetsUnshared (24 call sites, *measured*: `grep -rn 'sourceOf(\|definitionChain(' lib include | wc -l`) | rederivation | §5.7 L1 and §5.8's forwarding interface (lanes 03, 07) |
| R13 | a match has no repeating region | `Lifetimes.cpp:50-54` per terminator | rederivation | T5.11 |
| R14 | the recursion structure the frontend found (`Recursion.idr`, `total`) | the C++ call graph after defunctionalization | — | essential: a different graph (closures are calls only after defunctionalization); `total` is carried as a property and read (`Func.cpp:190`) |

## 5. Target design

What follows applies §5.1 Design 1, §5.3 S0/S1, §5.4 Design 1, §5.6
Design 1, §5.7 L2 and §5.9 Design 1 to this lane's code, as far as the
evidence of §2-§4 carries them. Where the owner's questions are open
(QA1-QA4, Q-O2, QL1, QL3, Q-M1, Q-E1, Q-llvm-1/2/3/7) the design says
which answer it assumes and what changes under the other; it decides
nothing. Every item gives its one line (the skill's rule).

### T5.0 The S0 question, asked of each analysis first

§5.3 S0: could the dialect carry the answer so no pass solves for it?
- **Effects**: already carried (the `effects` property on functions and
  calls, verified by `verifySymbolUses`). Kept; the solve stays only to
  compute it where bodies change.
- **Tail position** (chain R3): yes. A call knows at construction whether
  its results go straight to its function's return; MLton puts it on the
  call (`Return.t = Dead | NonTail | Tail`, §5.9 C3). Candidate for lane
  03/10: a call property set where a tail is made and verified locally
  (the next op is the terminator and passes exactly its results), read by
  every client instead of `inTailPosition`'s recursion up the matches.
- **Gives back** (chain R5): yes. A function fact, `gives_back = i`, as
  an inherent property beside `effects`, verified at calls the way effects
  are (lane 03 decides the form). It is what LLVM's `returned` attribute
  says (0003), so lowering writes the attribute from it.
- **Recursion**: no: a property of the call graph, an analysis (§5.8's
  table: "a property of a whole function: an analysis").
- **Binding times, inline facts, constants of returns**: transient to the
  optimizer, or already in the body (constants). No IR change.
- **Ranges**: partly: a value whose range a pass proved can carry it as
  a check or range op (0003 "emit ranges as `range` facts"; lane 11).

### T5.1 One program call graph, maintained (`ProgramGraph`)

- *Representation.* An `AnalysisManager` analysis on `idr.program` (and
  one on the lowered module), replacing `CallCycles` and `Recursion`:
  `FunctionId` dense in program order (`enum class FunctionId :
  std::uint32_t`, minted only by the graph, §5.5 D3's `Id<Tag>`); callees
  and callers as CSR rows; the call sites per function in walk order;
  SCCs bottom-up as id ranges; `sccOf`, `callsItself` (self edge),
  `recursive` (multi-member SCC, or a non-tail self call: Recursion's bit),
  `id(FuncOp)` and `op(FunctionId)`. Built in one parallel walk per
  function (callees) and one serial link, through `CallOpInterface` and
  `CallableOpInterface` (§5.6 Design 1; CIRCT's `InstanceGraph` shape).
  Edits for the passes that know their edits: `erase(fn)`,
  `eraseInto(fn, caller)` (contify), `insert(fn)` (the optimizer's made
  nodes), `mergeSccs` (the optimizer's waits).
- *Deletes.* `CallCycles.{h,cpp}`, `Recursion.{h,cpp}`; every
  `SymbolUserMap` built for callers (seven sites, four in the pipeline); `Members` maps by name in
  BindingTimes, Identities, Frames; `ByName` in TailCallPlan; `positions`
  in observableRuns; the self-call walks of `Inline.cpp:25-28`,
  `Waves.cpp:228-234`, `Recursion.cpp:30-40`; the reverse map of
  `Identities.cpp:86-90`.
- *One line.* The fact "who calls whom, in which SCC" has one source,
  minted once per stage, so a function's membership, its callers and its
  self call can no longer be asked of a second, drifting copy (chain R1,
  R2, R9 deleted).
- *Cost.* About 8 bytes per edge in two CSR directions plus per-function
  vectors: a few MB at 70,000 functions and ten calls each (*conjecture*,
  §5.4 Design 1's arithmetic), against up to seven rebuilds of upstream's
  graph and four `SymbolUserMap`s per compile today.
- *Upstream.* Whether to build it on upstream's `CallGraph` (rebuilt, no
  update API worth using: `eraseNode` is O(nodes), §5.1 E1) or on the
  interfaces directly is the owner's (Q-E5): the evidence is that every
  client here wants dense ids and callers, which upstream's graph does not
  give.

### T5.2 The solver layer's shared pieces (`lib/Solver/`, `include/idr/Solver/`)

- *Representation* (§5.3 S1, §5.5 D3): `Graph` (CSR forward and
  reverse over a typed dense id, frozen after build) with a
  `GraphTraits` specialization carrying `getNumber`/`getMaxNumber`, so
  `llvm::scc_iterator`, `post_order` and `GenericDomTree` take it with no
  copy; `components(const Graph &)`; `mark(const Graph &, seeds,
  Direction)` returning a `BitVector`; `IndexVector<Id, T>` whose raw
  integer index is `= delete`d; the concepts `Summary` (join returns an
  `enum class Changed`) and `Transfer`. One header per solver states what
  upstream lacks and its state's size in program units (§4, §5.11 A1).
- *Deletes.* `Scc.cpp`'s `Vertex` copy and `stronglyConnected`'s map and
  callback (SC1, SC2); the dead `MonotoneWorklist` and `FiniteLattice`
  (WL1, WL2); the hand markings of observableRuns (EF7) and, in their
  lanes, Stack's per-node `SmallVector` graph, the ready set's
  `reaches`/`merge` markings, Exclusivity's item graph if lane 07 takes it.
- *One line.* A graph is built once into one representation that the
  algorithms read directly, so a per-call copy, a per-node container and a
  raw index into the wrong table are unrepresentable.
- *Order.* First (T5.1 and every later item use it).

### T5.3 Summaries over the SCCs (Shape S), static and dynamic

- *Representation.* `SummaryTable<S>` = `IndexVector<FunctionId, S>`;
  `solveBottomUp<S>(const ProgramGraph &, Transfer)` (callees first;
  inside an SCC, members re-run until no summary changes, which a finite
  lattice ends: effects needs one pass, being a union), and
  `solveTopDown<S>` (callers first) for facts that flow from call sites
  (argument ranges, T5.7). Sequential first; a wavefront of ready SCCs on
  `mlir::parallelForEach` where measured to pay.
- *Clients.* Effects (`bodyEffect` the transfer, the result written into
  the `effects` property, which stays the carrier); Returned's per-result
  bit if T5.5's carried fact is not taken; Ranges' return and argument
  summaries (T5.7). The optimizer is the **dynamic** client: its ready set
  adds nodes and merges SCCs during the solve (`Waves.cpp:142-192,
  259-275`), which is essential (specialization makes functions while
  their callers' summaries are pending), so it keeps its own schedule but
  over `ProgramGraph`'s ids and the same `Summary` record and transfers;
  its `enable` rescan (`Waves.cpp:64-83`) becomes a ready queue fed by
  `unfinishedCallees` reaching zero (lane 09).
- *Deletes.* `solveEffects`' SymbolUserMap (EF2), `writeCallEffects`'
  three walks per function (EF11, by a call-site list per function), the
  ready set's own callee walk (`ReadySet.cpp:34-42`, AM2).
- *One line.* One schedule and one table type serve every summary, so
  each summary states only its lattice and transfer; the per-analysis
  driver, its order and its maps are deleted.
- *Under the other answers.* If Q-M1 takes a port of Modular's
  `SCCGraph`, it needs insertion and merge for the optimizer, which it
  lacks (§3.1).

### T5.4 BindingTimes: extract once per component, interpret over the extract

- *Representation.* Per component, one extraction (Identities' `Record`
  shape): for each call between members, the callee's `FunctionId` and,
  per argument, the caller parameter it is the same value as, or nothing
  (`sourceOf` asked once per operand, at extraction). The interpretation
  then runs over these edges, not over the IR: a reach is (member,
  interned tuple id), and visiting it reads the member's extracted edges.
  Whether the per-member interpretations can be merged into one solve
  per component is *conjecture*: today's analysis is polyvariant (a
  member reached with two tuples is read twice, `BindingTimes.cpp:134-141`),
  and a merged solve over (member, parameter) nodes with a flat lattice
  would be monovariant, possibly less precise; the existing
  `idr-binding-times` remarks are the test that decides.
- *Deletes.* The per-visit body walks and callee name lookups (BT7, BT8),
  the per-operand `sourceOf` recursion (BT4), the `std::map` of vector
  keys (BT5), the `Abstract` variant beside its `code()` (BT3), `Members`
  (BT2), `nameOf`'s switch for a table (BT1).
- *One line.* Each call's argument-to-parameter relation is read off the
  IR once per component, so the re-walk of a body per tuple and the second
  encoding of an abstract value are unrepresentable; the per-member cost
  (Q-llvm-7) stays until a merged solve is shown to keep today's answers.

### T5.5 Identities: dense ids, one walk, a carried answer

- *Representation.* Members and assumptions as `IndexVector`s over the
  SCC's ids (ID2); the record's walk lists the calls (ID5) and a candidate
  is one struct (ID3); callers from `ProgramGraph` (ID6); the walk's
  numbering from the scope (ID7). The answer is published as the
  function fact of T5.0 (`gives_back`), which every later pass keeps and
  lowering turns into LLVM's `returned` attribute.
- *Deletes.* The `StringAttr` maps, the two extra walks, the parallel
  lists, the `Drop` pair; in lane 10, `Tail/Returned.cpp`'s whole-module
  solve, replaced by reading the attribute (or, if lowering splits values
  into components that the fact cannot follow, a per-result summary over
  the lowered graph, T5.3, seeded by it: 0003's "seed the lowered solve").
- *One line.* What a function gives back is decided once and carried, so
  the whole-module per-value re-solve after lowering (chain R5) is
  deleted.
- *Depends on.* Lane 03 (the property and its verifier), lane 10
  (Returned), lane 12 (the attribute in lowering).

### T5.6 Constants and inline facts: upstream's rewrite, the size kept

- Constants: idr-constants keeps its per-function upstream solve (the
  scope §5.1 A6 recommends, already built and already run at stage-1
  scale). Upstream patch: export SCCP's `rewrite` with a listener hook
  (`upstream/<bug>/` with report, reproducer, test and plan), so the copy
  at `Transforms/Effects/Constants.cpp:73-169` goes; our actions wrap the
  listener. `ConstantsOf` becomes a read of the summary table (CO2).
  *One line:* a second copy of upstream's rewrite is deleted.
- Inline facts: the size lives on the ready set's node, updated by each
  inline (`Inline/Inline.cpp:156` already) and recomputed only after the
  inner pipeline ran on the body (it changed); `Facts` becomes the sum
  `Keep | Inline{size}` (IN4). *One line:* the per-ask walks (chain R10)
  go, and a size read for a callee that is kept is unrepresentable.

### T5.7 Ranges: per function with summaries, or whole program after U1

- *Assumed answer (QA2 = Design 1).* idr-narrow-words already runs per
  function; it would solve its own function with upstream's
  `IntegerRangeAnalysis` (`top` = the function, interprocedural off), a
  call's results from the callee's **return-range summary**
  (`visitExternalCall`, as idr-constants does) and the function's
  arguments seeded from its **argument-range summary** (the join over its
  call sites' operand ranges, a callers-first `solveTopDown`). Inside a
  recursive SCC the summaries iterate until upstream's widening rule
  stops them (precision only). Versioning re-solves only the versioned
  functions (RA3, AM4).
- *Other answer (QA2 = Design 2).* Keep the whole-program solve after
  U1, measured on the stage-1 module first: at the pin it costs about
  2 × 2.9 KB per value plus blocks and callables (§5.1 A4, H1), which at
  §5.1 H1's V ≈ 10 million is tens of GB (*conjecture*).
- *Either way.* The poison and literal-default special cases move to
  upstream and lane 03 (RA4, RA5); the baseline coupling follows U4 (RA6).
- *One line.* Range facts cross functions only as summaries, so a
  per-value state of the whole program alive through a nested pass (RA1,
  RA2) is unrepresentable; the re-solve after versioning shrinks to the
  functions it changed.

### T5.8 Tail position as a per-call fact

- *Representation.* T5.0's candidate: a call's tail kind (`not tail`,
  `tail`, `tail modulo a context`), set where the IR is built or
  rewritten and checked locally, or, if lane 03 keeps it out of the IR, a
  per-function cached analysis computed once (one walk) and read by every
  client.
- *Deletes.* The per-query recursion of `inTailPosition`
  (`Tail.cpp:31-35`) and the block scan of `inTailPositionModuloContext`
  (`Tail.cpp:282-289`) in Borrows' per-visit path (BO2), Lifetimes,
  Stack, Recursion; and, after lowering, `TailPosition.cpp`'s recomputation
  if the fact survives lowering (lane 12).
- *One line.* Whether a call is a tail call is decided once per call, so
  three formulations of "loops in its frame" (RC2) collapse into one read.

### T5.9 The per-value and per-point state that stays upstream

- idr-constants (per function), Copy (per loop), and under Design 1
  Ranges (per function): upstream's framework, with U1 (§5.1) for the
  fixed cost per state and U4 for the baseline. Nothing of ours keeps a
  per-program-point state in this lane (§3.2, Q-W2).
- *One line.* The framework is used only at the scope it supports (A6),
  so no whole-program per-value solve of ours remains.

### T5.10 Analysis-manager hygiene

- Passes preserve by name what they do not change: idr-effects keeps
  `ProgramGraph`, `CallGraph`, `TypeGraph`, `Layouts`, `SymbolTable`
  (EF12); every pass that changes no call keeps `ProgramGraph`; contify
  and the optimizer update it in place (AM1, AM2); passes that change
  nothing keep calling `markAllAnalysesPreserved()` (21 sites already),
  which also skips the verifier (§5.2 H3).
- *One line.* An analysis is rebuilt only when what it reads changed,
  so up to seven call-graph builds become one per stage (chain R1).

### T5.11 Interface queries once per op

- `Lifetimes.cpp:50-54` asks `isRepetitiveRegion` once per parent op
  per graph build (a cache in the builder), or, better, upstream makes
  `isRepetitiveRegion` an overridable interface method with today's body
  as its default (the shape of `BufferizableOpInterface::isRepetitiveRegion`,
  §5.1 C2) and the match answers "no region repeats" in O(1); `upstream/`
  entry with report and test (U3's family).
- *One line.* A per-op fact is no longer recomputed per terminator, so
  the O(N²) bytes per match (IQ1, chain R13) go.

### T5.12 Deletions with no replacement

- `MonotoneWorklist` and `FiniteLattice`: dead, nothing replaces them
  (*measured*: no user). Everything else this lane deletes is replaced
  by a T-item above (§7).
- *One line.* Code that nothing reaches is not kept beside the solver
  layer's own concepts.

### T5.13 The rederivation chains, traced

For each fact: where it is first known, every place it is computed
again, and where it should live. *Read* unless marked.

- **R1, the call graph.** First written by idr-defunctionalize, which
  makes every closure call a direct call (`Pipeline.cpp:67-71`). Computed
  again: `CallGraph` + `CallCycles` up to seven times (§2.2); the ready set's
  callee walk and its call counts (`ReadySet.cpp:34-42`); exclusivity's
  `Calls`, its reach over functions and its callers table
  (`ExclusivityGraph.cpp:17-60`, `Exclusivity.cpp:84-103`); the callers
  of the `SymbolUserMap`s (seven sites); the `PredecessorState`s of Ranges and
  Returned; TailCallPlan's internal set (`TailCallPlan.cpp:69-87`);
  observableRuns' runners (`Effects.cpp:79-82`); Identities' callers
  (`Identities.cpp:86-90`); upstream One-Shot bufferization's own callee
  order (`Bufferize/Bufferize.cpp:4-9`). Different graphs, honestly so:
  the deduplicator's symbol-use graph before defunctionalization
  (`EliminateDuplicateFunctions.cpp:95-136`, references and calls) and
  the partition's reference graph after LLVM (`Partition.cpp:234`).
  Home: T5.1 per stage; the reference graph before defunctionalization
  stays the deduplicator's (lane 06).
- **R2, a self call.** First: the call graph's self edge
  (`CallCycles.cpp:43-44`). Again: `Inline.cpp:25-28`,
  `Waves.cpp:228-234`, `Recursion.cpp:33-36`, `Tail.cpp:50-53`,
  `TailCallPlan.cpp:84`, `Stack.cpp:250-258` with `Lifetimes.cpp:59-66`.
  Home: T5.1 (self edge) and T5.8 (tail kind).
- **R3, tail position.** First: the IR's shape when a pass builds it.
  Again: per query, from the call up through the enclosing matches
  (`Tail.cpp:23-35`) and, modulo a context, a block scan and a walk
  (`Tail.cpp:270-289`), asked by Borrows on every revisit of a call
  (`Borrows.cpp:236-237`), Lifetimes per call (`Lifetimes.cpp:65`), Stack
  (`Stack.cpp:233`), Recursion (`Recursion.cpp:35`), FramesPlan
  (`FramesPlan.cpp:61, 90`), AccumulatorPlan (`AccumulatorPlan.cpp:125,
  130`); after lowering, `TailPosition.cpp:258-283` for TailCallPlan.
  Home: T5.8.
- **R4, effects.** First: idr-effects. Again: idr-optimize per
  component once its bodies are final (essential: the bodies changed);
  as a check after every pass (`Verify/Program.cpp:61-71`) and per call
  in `verifySymbolUses` (`Call.cpp:54`); not lowered, so LLVM infers
  weaker ones (0003). Home: T5.3 for the solve, the property for the
  carrier, lowering's attributes for LLVM (lane 12).
- **R5, gives back.** First: Identities inside idr-optimize. Lost at the
  pass's end. Again: `Tail/Returned.cpp` on lowered code. Home: T5.5.
- **R6, constants.** First: idr-constants, written into the body.
  Again: three SCCP baselines loaded for executability (Ranges, Returned,
  Copy); every canonicalize folds again (cheap, local, right). Home: the
  body; U4 removes the baseline's second lattice.
- **R7, ranges.** First: Ranges. Again: after versioning; per loop after
  lowering (on the copy, at a bound: a different question); the stated
  ranges of runtime calls (`RuntimeCalls.cpp:37-50`, lane 12). Home: T5.7
  and 0003's `range` facts (lane 11).
- **R8, what an enclosing match says.** First: the match. Again:
  Identities (`IdentitiesRecord.cpp:58-72, 248-268`), the three of 0003,
  `sourceOf` for a case region's arguments (`Grades.cpp:210-216`). Home:
  lane 04's one `knownConstructor`, or §5.7 L1 (lane 03).
- **R9, function membership and number.** Nine maps (§4.10). Home: T5.1.
- **R10, function size.** `inlineSize` per ask. Home: T5.6.
- **R11, which code runs.** `DeadCodeAnalysis` in four solves,
  exclusivity's live blocks and reach, symbol DCE, unreachable-block
  erasure. Home: U4 for the baselines; exclusivity's is lane 07's.
- **R12, the same value.** `sourceOf` is the one rule (`Grades.cpp:197-217`),
  but each of 24 sites walks a definition chain per query. Home: §5.7 L1
  and §5.8's forwarding interface (lanes 03, 07); in this lane, T5.4 and
  T5.5 ask once per operand at extraction.
- **R13, no region of a match repeats.** Home: T5.11.
- **R14, the frontend's recursion.** `Recursion.idr` finds SCCs of
  Idris's size-change graphs to state `terminating`, carried as `total`
  and read by `bodyEffect` (`Func.cpp:190`): one fact, carried. The C++
  call graph after defunctionalization is another graph (closure calls
  exist only then): essential, kept.

### T5.14 Order inside the subsystem, and dependencies

1. T5.2 (`Graph`, `mark`, `components`, `IndexVector`), T5.12 deletions.
2. T5.1 (`ProgramGraph`), cutting over every `CallCycles` and
   `Recursion` reader and every caller-only `SymbolUserMap` in one change.
3. T5.10 (preservation) with T5.1.
4. T5.3 (summary table and `solveBottomUp`); effects onto it.
5. T5.4, T5.5, T5.6 with lane 09's ready set (it holds their summaries).
6. T5.8 with lanes 03 and 10; T5.11 with lane 08.
7. T5.7 with lane 11, after QA2.
8. T5.5's deletion of `Returned` with lanes 03, 10 and 12.

Dependencies on other lanes: 02 (the effects model `bodyEffect` reads),
03 (`gives_back` and tail properties; the literal match's default
forwarding; a `succ` op if wanted), 06 (observableRuns beside the label
solve; the label solve's graph on T5.2), 07 (Borrows and Exclusivity on
T5.2; exclusivity's callers and live blocks), 08 (Stack's graph on T5.2;
Lifetimes' query), 09 (the ready set on `ProgramGraph`), 10 (Returned,
FramesPlan's `Members`), 11 (Narrow under T5.7), 12 (lowering the carried
facts to LLVM attributes), 13 (verification's per-function cost, the
pipeline's nesting).

### T5.15 The Idris side

No Idris file is in this lane. The one Idris-side fact this lane reads is
`total` (from `Recursion.idr`'s `terminating`, `Emit/Declarations.idr:56`)
and `no_inline` (`:57`), both inherent properties: carried, not
re-derived (R14). Lane 15/16 owns `Recursion.idr`'s own search
(`SortedMap Address Nat` numbering, `Recursion.idr:40-50`).

## 6. Evidence for the owner's questions

What our code says, by ID; no answers.

- **QA1** (patch the state storage first; P1 or P2). The framework users
  that pay A4's fixed cost on whole-program anchors are Ranges, Returned
  and Borrows (§2.3); idr-constants and Copy pay it per function and per
  loop and free it after. Of the three whole-program ones only Borrows has
  run on the stage-1 module (sparse anchors: parameters and read values,
  points after calls); Ranges and Returned anchor every value and have not
  been reached (0001's record ends in counting). So U1 changes the
  measured outcome only for solves not yet run. P2's per-type freeing has
  no client here: every solve of ours drops its whole solver at once
  (`Constants.cpp:188` is a local; `Returned.cpp:153` a local;
  `Ranges::Solved` one object).
- **QA2** (per-function with summaries, or whole program after U1).
  idr-constants is the per-function design already, and it ran at stage-1
  scale. Ranges is the case that decides: its readers are per function
  (idr-narrow-words, `Narrow.cpp:67-133`), but its precision on a
  natural's argument comes from interprocedural joins over callers today
  (`Ranges.cpp:67`), which a per-function design must rebuild as a
  callers-first argument summary (T5.7). Inside a recursive SCC, today's
  solve already gives up precision on loop-carried values after 128
  merges (`Ranges.h:25-33`). Returned needs only one bit per (result,
  argument) across calls (`Tail.h:238-262`): its whole-module per-value
  state is far more than its question.
- **QA3** (`remove-dead-values`). Already out of the pipeline (16005000,
  `Pipeline.cpp:95-105`): dead parameters are the optimizer's
  specialization holes, dead results counting's drops. No signature
  solver exists. No backward analysis exists either, so U2 matters only if
  a per-function `remove-dead-values` returns (W7).
- **QA4** (one state representation for all our solvers). Each of our
  solvers built its own (§2.6, "three observations"): Labels' interned
  sets and condensed graph, Exclusivity's items, Stack's per-node
  `SmallVector<unsigned,2>` with `BitVector` markings, Identities'
  `Id`-numbered record, BindingTimes' tuple map, observableRuns' index
  adjacency, the deduplicator's and the ten `Scc` users' index
  adjacencies; dense numbering minted separately in at least six of them,
  each with its own hash map. No two share a graph type.
- **Q-O2** (MLton's constraint-generating interpreter as *the* layer).
  Fits as is: Exclusivity and Stack (markings, ffa91113, b8301ebe),
  observableRuns (a backward marking), effects (a union per SCC), Labels
  (0CFA with sets). Fits as a dual: Identities (cells start assumed and
  only drop, `Identities.cpp:92-120`). Does not fit a per-value cell:
  BindingTimes (relational: which caller parameter a value equals, carried
  as a tuple, `BindingTimes.cpp:83-116`), and the per-function SCCP and
  range solves, which are upstream's and flow-sensitive only through
  executability.
- **QL1** (a scoped array view built per solve). One exists:
  Identities' `Record` (nodes numbered in walk order in a vector, a
  `DenseMap<Value, Id>` only during the walk, `IdentitiesRecord.cpp:84-122`),
  freed with its component; Stack's node numbering (`Stack.cpp:181-190`)
  and exclusivity's items are two more, whole-program. None is shared.
- **QL3** (rules over relations, or transfers over one engine). Today's
  composition is one-way reads of frozen answers through constructor
  arguments (`Borrows.cpp:299`, `Recursion.cpp:17`,
  `Exclusivity::solve(program, copies)`), and one product computed per
  component without a shared engine: the optimizer's five summaries,
  each by its own walk (`Component.cpp:212-250`). No rule engine, no
  mutual dependence between two of this lane's analyses.
- **Q-M1** (one call-graph schedule, port or fresh). The tree has three
  schedules: CallCycles' static order (read by effects, frames,
  rc-stack, rc-grades, tail-calls), the optimizer's dynamic wavefront
  with insertion and merge (`Waves.cpp:59-192, 259-347`), and the
  deduplicator's static waves by height with a barrier per height
  (`EliminateDuplicateFunctions.cpp:121-185`). Modular's `SCCGraph` has
  neither insertion nor merge; the optimizer needs both.
- **Q-E1** (one maintained graph, three shapes). Shape S: effects,
  Identities, BindingTimes (intra-SCC), inline facts, Recursion, Returned
  as a summary, Borrows per parameter. Shape L: idr-constants, Copy,
  Ranges per function. Shape G: Labels, Exclusivity, Stack, Identities'
  record, observableRuns. Not fitting any as stated: the optimizer's
  schedule (a Shape S whose graph grows during the solve), and
  exclusivity's outer rounds (the whole solve re-run until the labels it
  reads settle, `Exclusivity.cpp:73-120`).
- **Q-E5** (upstream RFCs: a maintained call graph; a scope between
  function and module). The call graph is rebuilt up to seven times per
  pipeline (*read*: no pass preserves it by name, §2.2), and two
  passes know their edits exactly (contify, the optimizer). No solve of
  ours wants a per-SCC framework scope today: the per-SCC solves are
  ours (Identities, BindingTimes) and are not per value.
- **Q-llvm-1** (monomorphized, or a type-erased core). This lane's
  analyses are free functions and plain classes with no virtual dispatch
  of their own; virtuals appear only where upstream's framework requires
  them (`SummarizedConstantPropagation`, `NaturalRanges`,
  `ReturnedAnalysis`, Borrows' `Inference`). Callbacks where templates
  belong: five `function_ref`s, each with one caller (§3.2).
- **Q-llvm-2** (budgets). This lane's budgets are optimization budgets in
  program units that leave code as it was (`Inline.h:23-30`), and one
  upstream widening that loses precision (`Ranges.h:25-33`). No analysis
  of this lane is one a refusal rests on; none has a budget that fails
  (W-E5).
- **Q-llvm-3** (numbering: per solve, cached, or upstream). Per solve
  today, at least six times over (§2.6); none cached; MLIR's block
  numbers unused (*measured*: 0 hits for `getBlockID`/`getMaxBlockID` in
  `lib`, `include`). `FunctionId` (T5.1) would be the first numbering
  cached across passes.
- **Q-llvm-7** (the giant SCC). Serial today wherever it occurs: a
  component's members run in one turn of the optimizer
  (`Component.cpp:257-269`); BindingTimes interprets once per member
  (O(members × reach), `Component.cpp:245`); Identities rechecks callers
  per drop; effects is one pass. The size distribution of the stage-1
  call graph's SCCs is not recorded anywhere in the tree.

**New questions for the owner.**
- **Q-AN1.** May "a call is a tail call" and "a function gives back
  argument i" become function and call facts carried in the IR and
  verified (T5.0, T5.5, T5.8), as `effects` already is, so that their
  re-derivations (seven tail-position readers, the whole-module Returned
  solve) are deleted? Answer with Q-O3 and Q-E2.
- **Q-AN2.** Is the optimizer's dynamic schedule (nodes inserted and SCCs
  merged during the solve) the shared spine's job, or is the optimizer
  the one dynamic client of a static spine (T5.3)?
- **Q-AN3.** Ranges: per function with callers-first argument summaries
  (T5.7), or a measured whole-program solve after U1? It is the one
  analysis of this lane where QA2's answer changes the code.

## 7. Deletion list

By file and symbol; each with the T-item that replaces it.

- `include/idr/Analysis/CallCycles.h`, `lib/Analysis/CallCycles.cpp`:
  the file (T5.1).
- `include/idr/Analysis/Recursion.h`, `lib/Analysis/Recursion.cpp`: the
  file (T5.1).
- `include/idr/Support/Scc.h`: `stronglyConnected`; `lib/Support/Scc.cpp`:
  `Vertex`, its `GraphTraits`, the copying `components` (T5.2).
- `include/idr/Support/Worklist.h`: `MonotoneWorklist`, `FiniteLattice`
  (T5.12).
- `lib/Analysis/Effects.cpp`: the `SymbolTableCollection`/`SymbolUserMap`
  in `solveEffects`; `positions`, `runners` and the `OnceWorklist` reach in
  `observableRuns`; `include/idr/Analysis/Effects.h`: `LabelsRun` (T5.3).
- `lib/IR/Func/Func.cpp`: `writeEffects`' `SymbolUserMap` parameter (T5.1).
- `lib/Analysis/BindingTimes.cpp`: `Members`, `abstract::Anything`,
  `abstract::Same`, `Abstract` beside `code` (one encoding stays), `eval`
  (replaced by the extraction), the `std::map` of tuples; `nameOf`'s
  switch (T5.4). `Interpreter` stays, over the extract, unless a merged
  solve is shown to keep today's answers.
- `include/idr/Analysis/Identities.h`: `Outside`, `Members`, `Assumed`
  (as `StringAttr` maps), `Record::arguments`/`slots`/`types` as three
  lists; `lib/Analysis/Identities.cpp`: the two extra walks, `callers`,
  `Drop` (T5.5).
- `lib/Analysis/Inline.cpp`: the second walk in `factsOf`;
  `include/idr/Analysis/Inline.h`: `Facts::inlines` as a flag (T5.6).
- `include/idr/Analysis/Constants.h`: `ConstantsOf`;
  `lib/Transforms/Effects/Constants.cpp`: `replaceWithConstant`, `Rewrite`,
  `rewrite` once upstream exports its own (T5.6).
- `include/idr/Analysis/Ranges.h`: `Ranges::Solved` holding a
  whole-program solver; `lib/Analysis/Ranges.cpp`: the interprocedural
  configuration, the poison special case (upstream), the literal
  default's override (lane 03) (T5.7; under QA2 = Design 1).
- `lib/Transforms/Tail/Returned.cpp`: `ReturnedAnalysis`, `KnownLattice`,
  the whole-module solve, its `SymbolUserMap` (T5.5; lane 10's file).
- `lib/Transforms/Narrow/Copy.cpp`: the local `Listener` once upstream
  exports its `DataFlowListener` (lane 11's file).
- `lib/Transforms/Optimize/Waves.cpp`: `stepOfRecursion`'s self-call
  walk; `lib/Transforms/Optimize/ReadySet.cpp`: the callee walk and the
  `calls` count (lane 09's files; T5.1, T5.3).
- `lib/Transforms/Optimize/Contify.cpp`, `lib/Conversion/TailCallPlan.cpp`,
  `lib/Transforms/Contracts/Contracts.cpp`,
  `lib/Transforms/Expect/Continuations.cpp`: their caller-only
  `SymbolUserMap`s (their lanes; T5.1).
- `include/idr/Transforms/Tail.h`: `Members` (lane 10; T5.1).
- Per-query tail position in its readers once T5.8 lands (lanes 07, 08,
  10).

## 8. Risks, unknowns, measurements needed

- **The next wall may be Ranges or Returned** (*conjecture*, from §5.1
  A4 and H1). Both are whole-program per-value solves on the framework at
  the pin, and the stage-1 pipeline has not yet reached either: Ranges
  anchors every value of the program with two lattices, Returned every
  value of the lowered module. At §5.1 H1's V ≈ 10 million this is tens
  of GB. Measure before the cutover: count V at idr-narrow and at
  idr-returned-arguments (W1), and run each solve alone on the stage-1
  module with peak footprint recorded (§5.11 A2's measure).
- **The SCC size distribution is unknown** (Q-llvm-7). BindingTimes is
  quadratic in a component's size today, and every per-SCC solve is
  serial in a component. Measure: SCC sizes of the stage-1 program after
  idr-effects (a statistic in idr-effects, or a remark like
  idr-binding-times').
- **A maintained `ProgramGraph` is a new invariant** every call-changing
  pass must keep (CIRCT's discipline, §5.6 A4). A pass that forgets is a
  silent wrong answer, not a crash. Mitigation: the verifier (or a
  contract under `--idr-contracts`) rebuilds the graph and compares in
  test builds; release relies on preservation.
- **Lowering changes function identity** (idr.func to func.func to
  llvm.func), so a `FunctionId` table does not survive it; the lowered
  module gets its own graph (one build, T5.1). Whether the gives-back and
  tail facts survive lowering (T5.5, T5.8) depends on lane 12 mapping
  them, and on whether component splitting of results (`Returned.cpp:5-13`)
  defeats a per-result fact: unknown.
- **BindingTimes' merge** (T5.4) is *conjecture*: a single solve per
  component would be monovariant where today's interpretation is
  polyvariant, so it must reproduce today's fixed/varies answers, which
  a test over the existing `idr-binding-times` remarks can check; until
  then the per-member cost stays.
- **Upstream patches proposed here** (SCCP's rewrite exported; one
  `DataFlowListener`; poison as bottom in range and sparse analyses;
  `isRepetitiveRegion` overridable) each need a report, a reproducer, a
  test and a plan (AGENTS.md); their reception is unknown.
- **Measurements needed**: V, B, P, F at each solve (W1); SCC sizes; peak
  footprint of Ranges and Returned on stage 1; the time of
  `Lifetimes.cpp`'s per-terminator `isRepetitiveRegion` on the 30,000-case
  match (IQ1); how often the optimizer's `enable` rescan runs and costs
  (waves × components); the cost of the `CallCycles` builds and the
  `SymbolUserMap`s on stage 1.

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole, lines 1-11141, in chunks);
  `proposals/0003-facts-once.md` (whole); `audits/p0/README.md`;
  `proposals/0001-self-host.md:60-120, 180-195`.
- This lane's files, in full: `foreign/idr/lib/Analysis/{BindingTimes,
  CallCycles,Constants,Effects,Identities,IdentitiesRebuilds,
  IdentitiesRecord,Inline,Ranges,Recursion}.cpp`;
  `include/idr/Analysis/{BindingTimes,CallCycles,Constants,Effects,
  Identities,Inline,Ranges,Recursion}.h`; `lib/Support/Scc.cpp`,
  `include/idr/Support/{Scc,Worklist}.h`.
- Framework users, in full: `lib/Transforms/Effects/{Constants,Effects}.cpp`,
  `lib/Transforms/Tail/{Returned,ReturnedArguments}.cpp`,
  `lib/Transforms/Narrow/{Narrow,Copy,Lanes}.cpp`,
  `include/idr/Transforms/Narrow.h`; `lib/Analysis/Ownership/Borrows.cpp`
  (lines 1-80, 150-315); `include/idr/Transforms/Tail.h:223-312`.
- Readers and analysis-manager uses: `lib/Transforms/Optimize/{Optimize,
  ReadySet,Component,Waves,Contify}.cpp` (whole);
  `lib/Transforms/Specialize/Report.cpp`; `lib/Transforms/Inline/Inline.cpp:110-168`;
  `lib/Transforms/Stack/Stack.cpp:1-60, 100-300`;
  `lib/Transforms/Tail/Frames.cpp:340-378`, `FramesPlan.cpp:1-60`;
  `lib/Conversion/TailCallPlan.cpp` (whole);
  `lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp:1-25, 95-190`;
  `lib/Transforms/Defunctionalize/Pass.cpp:100-162`;
  `lib/Transforms/Ownership/Exclusive.cpp:20-60`;
  `lib/Analysis/Ownership/Exclusivity.cpp:60-140`;
  `include/idr/Analysis/Ownership.h` (whole); `include/idr/Analysis/Labels.h:1-40, 270-325`;
  `lib/Analysis/Labels.cpp:240-275`, `LabelSites.cpp:1-30`;
  `lib/Transforms/Pipeline.cpp` (whole);
  `lib/Transforms/Contracts/Contracts.cpp:190-250, 315-340`;
  `lib/Transforms/Expect/SolvedEffects.cpp`;
  `include/idr/Transforms/Passes.td:33-61, 255-300` and the pass list.
- Shared IR helpers: `include/idr/IR/Func.h`, `lib/IR/Func/Func.cpp:150-287`,
  `lib/IR/Func/Call.cpp`; `include/idr/IR/IdrOps.td` (effects
  declarations); `include/idr/IR/IdrMatchOps.td:20-110`;
  `include/idr/IR/Tail.h:1-86`, `lib/IR/Tail.cpp:1-60, 270-291`;
  `include/idr/IR/Grades.h:120-200`, `lib/IR/Grades.cpp:197-240`;
  `lib/IR/Effects.cpp:1-60`; `lib/IR/Flow.cpp:30-110`;
  `lib/IR/Lifetimes.cpp:40-131`; `lib/IR/Verify/Program.cpp:40-110`;
  `lib/IR/Verify/Linearity.cpp:115-135`;
  `lib/Transforms/Bufferize/Releases.cpp:35-50, 95-120`;
  `lib/IR/ContentNames.cpp:95-134`; file headers of
  `lib/Analysis/Ownership/{Uses,Values,Captures,Reuses,ExclusivityGraph}.cpp`,
  `lib/Transforms/Ownership/Classes.cpp`, `lib/Transforms/Demand/Demand.cpp`,
  `lib/Transforms/Specialize/{Order,Requests}.cpp`,
  `lib/Transforms/Narrow/Versions.cpp`,
  `lib/Transforms/Tail/{AccumulatorPlan,Trmc,TailLoops}.cpp`,
  `lib/Target/Partition.cpp`, `lib/IR/{TypeGraph,ValueFacts,Crashes}.cpp`,
  `lib/Conversion/TailPosition.cpp`,
  `lib/Transforms/{Bufferize/Bufferize,Columns/Columns}.cpp`.
- Idris side: `compiler/src/IdrisMLIR/Frontend/Translate/Recursion.idr:1-60`;
  `compiler/src/IdrisMLIR/Emit/Declarations.idr:50-60` (by grep).
- Pinned upstream: `.toolchain/llvm-project/mlir/lib/Transforms/SCCP.cpp:1-140`;
  `mlir/lib/Interfaces/ControlFlowInterfaces.cpp:225-320, 390-405`;
  `mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:117`,
  `UnsignedWhenEquivalent.cpp:67` (by grep); `mlir/lib/Dialect/UB/IR/UBOps.cpp`
  (by grep).
- History: `git log --oneline` of this lane's paths (42 commits over
  `lib/Analysis`, `include/idr/Analysis`, `lib/Support`,
  `include/idr/Support`); `git show` of 0a884489, 16005000, ffa91113,
  e96bb991, b8301ebe, 9db9813d (messages and stats).
- Measurements (commands in the text): `wc -l` of the files; grep counts
  of `getAnalysis<CallCycles>` (9), preservation of CallCycles/CallGraph
  (0), `markAllAnalysesPreserved` (21), `markAnalysesPreserved<` (13),
  `OnceWorklist` files (30), `MonotoneWorklist` users (0),
  `DenseMap<Value` (21) and `DenseSet<Value` (4), `DenseMap<StringAttr`
  (27), SCC-utility users (10), `SymbolUserMap` constructions (7),
  `sourceOf`/`definitionChain` sites (24), `getBlockID` uses (0),
  backward analyses (0).
