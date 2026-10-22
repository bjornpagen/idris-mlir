<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 08: counting

Subsystem: `foreign/idr/lib/Transforms/Ownership/` (Buffers, Cells,
Classes, Commit, Exclusive, Grades, Knots, Placement, Reshape, Reuse,
Share, Signatures, Specialize, Take), `lib/Transforms/Stack/`,
`lib/Transforms/Demand/`, their headers under `include/idr/Transforms/`
(`Ownership.h`, `Stack.h`, `Demand.h`, their entries in `Passes.td`), and
`lib/Conversion/Counting.cpp` only for what the transforms hand to the
lowering (lane 12 owns it).

Marks: *read* (path:line, commit, proposal section), *measured* (a count,
with its command), *recalled*, *conjecture*.

## 1. Reading notes

Proposal sections are `§N`, finding IDs as the lane writes them. All
*read* from `proposals/0000-mlir-native.md` unless marked.

**§2, §3 (the brief).**
- §2: the counting stage is four passes in the pipeline,
  `idr-rc-cells`, `idr-rc-stack`, `idr-rc-grades`, `idr-rc-exclusive`,
  then `demand`; it runs after frames and before TRMC. Grades are
  `!idr.q<quantity, permission, T, lifetime>` with `lin`, `own`, `excl`
  as aliases; a verifier checks them after every pass.
- §2: "More live inside passes (`Transforms/Stack`'s lifetime inference,
  `Tail/Frames`'s plan, `Optimize`'s demand)": rc-stack is listed as an
  analysis living inside a pass.
- §3 row b8301ebe: `idr-rc-stack`, 47 GB, "a candidate bit vector per
  value, copied along every edge". Row ffa91113: exclusivity on
  `DataFlowSolver`, 627 GB. Row e96bb991: exclusivity's graph build,
  quadratic interface queries on a match.

**§5.1 mlir-analysis.**
- 5.1.1 G3: ownership-based buffer deallocation is the upstream design
  closest to counting: intraprocedural by construction, a **function
  boundary ABI** (arguments never owned, results pass ownership), one walk
  per function through the control-flow interfaces, an error on IR it
  cannot model, runtime conditions where static knowledge ends, removed
  later by a simplifier; linear per function, state per block.
- 5.1.2 item 3: what stays ours honestly: "problems whose state is per
  program point and set-valued (exclusivity's graph, `idr-rc-stack`'s
  lifetime inference, `Tail/Frames`' plan)". Their headers must name
  which of A4 / C3 / A6 they answer, with a measurement.
- 5.1.2 item 7, 5.1.3 Design 3: solver layer state is dense per-function
  numbering, arrays and bit vectors; results cached in `AnalysisManager`;
  each unit of work an action.
- 5.1.5: "rc, dialect-design: ownership-based deallocation (G3) fixes a
  function-boundary ownership ABI rather than solving across calls, and
  leaves residual runtime checks for a simplifier: a model for counting."
- QA4 (one state representation for all solvers). W2 (every analysis's
  lattice, per value or per point), W3 (every `getPredecessors` etc. and
  every edge table built per query), W6 (anchored on functions).

**§5.2 mlir-ods.**
- A9: the transform dialect is upstream's model of consumption: `Read`
  and `Free` on the consumed `OpOperand` (`TransformMappingResource`);
  `transform-check-uses` reads it; `InferEffects` infers a per-argument
  summary (consumed or read-only) and stores it on function arguments;
  the call's hand `getEffects` looks up the callee
  (`lookupNearestSymbolFrom`, linear: a wall at 70,000 functions).
- M2: `Lin` and consumption match the transform model: `Read`+`Free` on
  the consumed operand makes a consuming op never trivially dead (as
  `drop` must not be), leaves a borrow (`Read` only) deletable; effect
  derived from the type by one trait.
- Recipe row 2 (`class Idr_Consumed<T> : Arg<T, "consumed", [MemRead,
  MemFree]>`), row 3 (effects from operand types, one trait), row 15
  (grade as `EnumParameter`s).
- M9: grade well-formedness once per unique type; uses checked by
  `verifyTrait`/`verifyRegionTrait`, parallel per function.

**§5.3 llvm.**
- B7, M5, I7: per-node `DenseMap`/`DenseSet` costs at least 64 buckets;
  per-node state is a vector indexed by a dense number.
- M4: our graphs (exclusivity's, "`idr-rc-stack`'s flow graph", the
  label solve's) get `scc_iterator`, `post_order`, dominators by one
  `GraphTraits` specialization with `getNumber`/`getMaxNumber`.
- M7: "`idr-rc-stack`'s inference is the flow graph, marked" is the SCCP
  shape found by hand; S1 makes it one generic mechanism: build graph
  once, `mark(graph, seeds)` (a `BitVector` and a BFS), frozen
  `Solution`.
- S0: before a solver, ask whether the dialect could carry the answer (a
  type, a token, an op). S1 sketch: `Node` dense index, CSR `Graph`,
  `Forward`/`Backward` types, `Lattice`/`Analysis` concepts, `solve`
  instantiated once per analysis, `mark` for two-point lattices.
- I5 (hot callbacks are templates), I3 (one exhaustive visit), M9
  (budgets: refusal-bearing analyses have none).
- Wave-2 questions: every worklist, every `DenseMap` per node, every
  `function_ref`, every variant; "Exclusivity's graph, `idr-rc-stack`'s
  flow graph and the label solve's graph: their node and edge
  representations, and whether one CSR `Graph` type with `GraphTraits`
  serves all three."

**§5.4 modular.**
- F5: Mojo's SCCP copies its whole map into each nested region: "the
  copy-per-edge shape of our b8301ebe wall".
- F6 / Design 3: IPDF's `RegionState`, rows only at ops that write,
  shared with the previous row; candidate for "counting, stack-cell
  inference and exclusivity".
- F15: Mojo `CheckLifetimes` inserts destructor calls after last use,
  field-sensitive, bit range per tracked value, three-tier threading
  contract; loops converge on bits that only fall (a measure).
- 5.4.2 item 5; wave-2 question: "Where state is copied per region or per
  edge (the b8301ebe shape), and which per-point solvers design 3 fits."
- 5.4.5 rc note: Mojo linear types are types without `Deinitable`,
  consumed by `deinit`.

**§5.5 cxx26.**
- D1: dispatch once where the set is open (ops: interface/trait), then
  typed code; concepts may read ODS (`OpT::hasTrait<>()` constexpr), never
  list ops. D2: `std::variant` plus one `match`; `holds_alternative` and
  `get_if` outside `match` banned. D3: `Id<Tag>` minted by the graph,
  `IndexVector` with `operator[](uint32_t) = delete`, solver templates
  instantiated once, transfer a template parameter. D8: `std::expected`
  where failure is data.

**§5.6 ecosystem.**
- B5: CIRCT Arc moved off `DataFlowSolver` (130 s to 200 ms) by giving
  uninteresting ops no node: "the move our ffa91113 made".
- 5.6.2 item 1: "A state exists only for what the problem is about": the
  grade already answers many of counting's questions, so a solver's domain
  is the values whose type leaves its question open, read off the type.
  Design 2: lazy, type-filtered state; "Deletes: states for linear and
  exclusive values in counting and exclusivity, if wave 2 finds them".
- item 5: an analysis a refusal rests on (knots, the in-place promise) has
  no budget. item 6: shape G "extract, solve, write back" fits "counting's
  flow graph after b8301ebe". item 8: a structured walk copying state per
  branch is b8301ebe's wall; fix: per-case delta over the entry state.
- D6: IREE writes its analysis answer into types once (resource
  lifetimes); TODO: put the answer's own bits in the type, not a lossy
  summary.
- W-E2 (values with state vs values whose type leaves the question open),
  W-E4 (facts in discardable attributes), W-E5 (budgets), W-E7
  (`DenseMap<Value, ...>` per function), W-E8 (single-block regions after
  defunc), W-E9 (state copied per edge or per branch).
- 5.6.5 rc note: ClangIR `LiveObjectAnalysis::isLastUse` is a last-use
  analysis close to where Perceus places drops.

**§5.7 library.**
- M1: dense state is needed only for facts changing at non-definition
  points; an op that changes ownership should define a new value (SSI);
  a quantity-1 value is single-use, so backward analyses over linear values
  are sparse equation systems; region tree is dominance; liveness is a
  query.
- **M4: "`idr-rc-stack`'s 47 GB is a dense set per value copied per edge
  (b8301ebe). 'Can v's cell live on the stack' is a partitioned-variable
  problem ... The sparse form is one bit per value propagated on def-use
  edges, or a reachability query from v's uses to an escaping use."**
- L1 (SSI by representation), L2 (scoped sparse core, `Scope` with
  pre-order `end[]` for enclosure), M9 (dense numbering), M7 (composition:
  product lattice vs read a frozen answer; "unique everywhere" is the
  complement of "shared somewhere" read after the freeze).
- QL1 (scoped array view), **QL2 (SSI as a dialect rule)**.
- Wave-2: PLV / independent / relational per analysis; which keep a fact
  per point; which share a scope.

**§5.8 dialect-design.**
- Summary (3): consumption is `Read` + `Free` on the value (C4).
- C3/O2: `memref.alloc`/`alloca` are one class parameterized by the
  resource; sketch `Idr_CellAllocOp<mnemonic, Resource>` for `cell.new`,
  `cell.stack`.
- C7: ownership-based deallocation: ownership as an `i1`, per function,
  ABI, `uninitialized < unique(X) < unknown` lattice.
- D1-D4 (SIL/OSSA): ownership kinds on values; owned consumed exactly
  once on every path; forwarding a category; no partial consumption of
  owned aggregates (`destructure_struct`); counting staged:
  `strong_retain` lowered from `copy_value`/`destroy_value`;
  `begin_cow_mutation` returns a fresh value.
- F3: HLFIR `hlfir.destroy` marks last use, "the future will probably be to
  identify the last use points automatically in bufferization instead".
- T1 (type is the only per-value carrier), T2 (grade as an attribute with
  an interface), T4 (illegal pairs unrepresentable), T5 (lifetimes are
  regions first).
- O3: regrade is a cast with computed result type; an ownership event
  with a runtime cost is its own op with its own effect; SIL keeps
  `copy_value`/`destroy_value` apart from `begin_borrow`/`move_value`.
- EF3: `Arg<T, "", [MemRead<Idr_Linear>, MemFree<Idr_Linear>]>`; "consumed
  exactly once on every path" is a pass run by instrumentation, not an op
  verifier (B10).
- DS1: `!idr.g<T, #grade>`, grade attribute interface (`mayDuplicate`,
  `mayDiscard`, `isUnique`, `join`, `canRegradeTo`), unrestricted = `T`.
- DS4 rows that touch counting: `cell.new`/`cell.stack` one class;
  `cell.recycle`/`cell.init` -> `cell.reuse` (Free stage 0, Alloc stage 1)
  and `cell.init` (Write); `lin.enter`, `lin.use`, `own.adopt`,
  `own.give`, `share`, `borrow` -> one regrade cast; `dup`, `drop` kept as
  counting ops with effects; `take`, `unpack` -> one consuming destructure;
  `ConsumesOperands`, `ConsumesOnly`, `Lin` -> `MemFree<Idr_Linear>`.
- DD-Q1 (normalize `!idr.lin<i64>` to `i64`?), DD-Q6 (borrows as regions).

**§5.9 mlton.**
- B3, B4, G2.2-G2.4: one fact per SSA name, never per program point;
  cells are union-find nodes with handler lists, a two-point cell rises
  once; analysis state sized by types and constructors (B5: a value of a
  type that cannot carry the fact shares one cell).
- F4: KnownCase's scoped state (push on entry, pop on exit): live state is
  the walk's depth.
- F7: liveness per function, one variable at a time (Morgan), cost the
  size of the answer; "bit-vector liveness is infeasible for MLton".
- H table, b8301ebe row: "MLton refuses bit-vector liveness by name ... no
  per-value set is ever copied along an edge".
- M2: the three recent fixes (ffa91113, b8301ebe, 16005000) are steps to
  MLton's model one analysis at a time.
- M5 / Design 4: counting's liveness per function, one variable at a time;
  "Deletes: every bit vector per value in the counting passes".
- Design 2: `case` as a terminator after defunc; costs: "structured passes
  that want regions (... counting's lexical scopes)".
- Q-O1, Q-O2, Q-O3; **Q-W4** (which passes read match's region structure,
  "counting's scopes"), **Q-W6** ("What liveness or last-use facts do
  `idr-rc-cells`, `idr-rc-stack`, `idr-rc-grades`, `idr-rc-exclusive`,
  demand and frames compute, per what, and could each be Design 4's
  per-variable walk or a Design 1 domain?").

**§5.10 rc (read most carefully).**
- A1-A2: Perceus = one reverse walk per function, live set as state,
  owned set and borrowed table as environment; dups late, drops early
  (head of branch for vars live in some other branch); proved garbage-free.
- A3: drop specialization and dup/drop fusion at each branch head from a
  shape map built from the patterns (`specializeDrop`: unique arm drops
  children and frees; shared arm dups used children and decrefs).
- A4: reuse is **drop-guided**: after Parc, a `drop x` of a deconstructed
  `x` makes a token available by size; same-size allocation takes it;
  branches intersect; ICFP 2022: reuse before Perceus (algorithms K, D) is
  fragile or not frame-limited.
- A5: space classes: sound, garbage-free, frame-limited.
- A6: borrowing declared in the definition; Koka's inference flag is dead.
- A7: reuse specialization writes only changed fields (>= 1/4 saved).
- A8: FBIP check; A9-A10: runtime header (unique = 0), sticky band, fast
  paths, stackless free; A11: Koka's counting ops are untyped externals
  found by name (the counterexample).
- B1-B5 (Lean): counting per call-graph SCC, borrow inference monotone per
  SCC with forced vs heuristic reasons; explicit RC with derived borrows
  (projection of a borrowed value is borrowed; a reset target needs an
  exact count); reset/reuse with liveness in the same traversal,
  `classifyUse` treats an owned-argument pass as a live use; expanded
  reset splits hot/cold paths in IR; `coalesceRC`.
- C1-C4 (Swift): OSSA kinds and lifetime-ending bit; lexical vs precise
  lifetimes; `is_unique` ordering hazard.
- G1-G3: linearity restricts the future, uniqueness guarantees the past;
  Idris quantity 1 is the future promise only; FIP needs uniqueness.
- G5: ownership-based deallocation; transform consumption.
- M1: every counting algorithm is per function, reads others only through
  signatures; "None keeps per-value state for the whole program".
- M2: liveness should be the insertion walk's own state, not an analysis
  read by another component (rederivation chain if `Uses`/`Values` feed
  `idr-rc-cells`).
- M3: grades = OSSA kinds in types; consuming traits = lifetime-ending
  bit; grade verifier should be OSSA's rule, a linear walk.
- M4: `!idr.excl` is uniqueness; `idr-rc-exclusive` decides statically
  what Koka tests at run time.
- M5: quantity 1 binder: owned convention by type; uniqueness is a forward
  property from allocation, killed by the first `dup` or ω binding.
- M6: `idr-rc-exclusive` and `idr-rc-stack` are two-point markings
  (exclusive/shared, local/escaping); "Three markings, one honest solver
  layer."
- **M7: `cell.recycle` = `drop-reuse`/`reset`; `cell.init` =
  `alloc-at`/`reuse`. If `Reuses` pairs before dup/drop insertion it is
  algorithm K or D; drop-guided needs only a forward walk with a
  size-keyed token map.**
- M8: `Captures` may vanish under defunctionalization.
- M10: Koka runs TRMC before Perceus; we run counting before TRMC.
- R1 (recommended): signatures in types; one interprocedural solver of
  two-point markings; per-function passes nested on `idr.func`
  (insertion as a reverse walk, drop specialization and fusion, drop-guided
  reuse forward walk, reuse specialization); `is_unique` as an op whose
  folder returns true on an exclusive type; effects declared once (`dup`,
  `drop` write the count resource, `is_unique` reads it, consumption is
  `Read`+`Free`).
- R2 (grade specialization in `idr-optimize`), R3 (Koka as is, baseline),
  R4 (runtime header).
- Owner questions **rc-Q1** (borrow inference), **rc-Q2** (how much
  exclusivity is static; run-time test as fallback), **rc-Q3** (a space
  guarantee), **rc-Q4** (threads and shards), **rc-Q5** (drops at last
  use, everywhere).
- **Wave-2 W1-W9** (5.10.4): W1 who inserts dup/drop and whether liveness
  is the walk's state; W2 Reuses before/after insertion, by constructor
  or size, tokens across calls; W3 what `idr-rc-grades` writes, grades in
  function types; W4 rc-exclusive's graph; W5 the grade verifier; W6
  runtime header; W7 ownership ops vs the field; W8 counting on regions or
  CFG, TRMC after counting; W9 arrays freed by our code or by upstream
  deallocation.

**§5.11 oom.**
- 5.11.2 (A): "the passes acceptance rests on (defunctionalization, the
  label solve, counting, lowering) cannot be budgeted at all: their memory
  must be bounded by construction." A1: each solver's header states its
  state's size in program units; a state sized by a product of two program
  quantities is a wall waiting. Wave-2 item 7: every solver whose state is
  sized by a product of two program quantities.
- 5.11.5 rc note: "reuse lowers the peak, which is the only memory lever
  counting has."

**§8 owner questions this lane gives evidence for:** rc-Q1, rc-Q2, rc-Q3,
rc-Q4, rc-Q5 (§8.5, §8.7), QL2 (§8.3). Related: DD-Q1, DD-Q6, Q-O1, Q-O3,
Q-E2, QA4, Q-O2, QL1, Q-llvm-2, Q-E3, oom-2.

**§9:** D2 (own solvers allowed, named, refactored into code of their own),
D4 (no code until the plan is approved).

**proposals/0003-facts-once.md (items in this lane's files).**
- "A token without its cell": `!idr.token` has no parameters, so the
  verifier, `Conversion/Fields.cpp`, `Demand.cpp` and
  `ReusesEveryCell.cpp` each walk back to the `idr.take`; owed
  `!idr.token<!idr.box<T>, @C>` inferred by `TakeOp`.
- "Exclusivity solved twice (`Ownership/Exclusive.cpp` re-solves the whole
  program when grade copies exist), and `ownsParameter` answers from the
  signature or the grade depending on whether a table was passed."
- "The static lifetime in the grade": `ownership::isStatic` walks the
  definition chain; readers include `Transforms/Ownership/Classes.cpp`
  (`Class::Phantom`, `Class::Constant`, `Class::StaticRead`) and
  Placement's plan for each; owed `static` in `Idr_Lifetime`, written once
  by idr-rc; delete `isStatic`, the three classes and their plans.
- "Exclusivity is no analysis": the final solve handed to `createRcCommit`
  by constructor; owed: cached program analysis, idr-rc-commit a pass
  reading it with `getCachedParentAnalysis`.
- "Types that could carry the fact": `Exclusivity::targets` keyed by
  `Operation *` (`Ownership.h`); `Reuses::sites` dereferencing a `find`;
  Placement's `casesOf` variant beside the match interface.
- "The owned stage reads upstream's buffer ops by name": `Role::Carried`,
  `takesCarried`, `storedBy`, `idr.own.adopt`/`give`.

## 2. What the subsystem is

All *read* at e96bb991 unless marked. Paths are relative to
`foreign/idr/` unless they start with a top-level directory.

### 2.1 Files and sizes (*measured*: `wc -l`)

| file | lines | what |
| --- | ---: | --- |
| `lib/Transforms/Ownership/Cells.cpp` | 55 | idr-rc-cells (on `idr.func`): `idr.con` with a cell becomes `cell.new` + `cell.init` |
| `lib/Transforms/Stack/Stack.cpp` | 385 | idr-rc-stack (on `idr.program`): the frame lifetime, inferred by marking one whole-program graph |
| `lib/Transforms/Ownership/Grades.cpp` | 71 | idr-rc-grades (on `idr.program`): boundaries, Reuses, Borrows, owned grades, then each body (reuse, reshape, place) in `parallelForEach` |
| `lib/Transforms/Ownership/Buffers.cpp` | 51 | `boundaries`: `own.adopt` after each `memref.alloc`, `own.give` before each counted `memref.store` |
| `lib/Transforms/Ownership/Reuse.cpp` | 69 | `reuseAt`: the take and the recycles of each `Reuses::Site` |
| `lib/Transforms/Ownership/Reshape.cpp` | 341 | `reshape`: selects to matches, take-apart where a box dies, consumer sinking, fields owned at read |
| `lib/Transforms/Ownership/Classes.cpp` | 132 | `Class` and `Classes`: the placement class of each value, recomputed per step |
| `lib/Transforms/Ownership/Placement.cpp` | 381 | `place`: dups, drops, borrows, the grades of placed values; `rebindDefaults` |
| `lib/Transforms/Ownership/Take.cpp` | 80 | `takeAt`, `takeAtEntry`, `takeFields`, `keepsCountedField` |
| `lib/Transforms/Ownership/Signatures.cpp` | 78 | `writeOwnedGrades`, `writeExclusiveGrades` |
| `lib/Transforms/Ownership/Exclusive.cpp` | 60 | idr-rc-exclusive (on `idr.program`): share taint, solve, grade specialization, solve again, redirect, grades, nested commit |
| `lib/Transforms/Ownership/Share.cpp` | 65 | `shareTainted`: `idr.share` at the consuming uses of values a view of which was dup'd |
| `lib/Transforms/Ownership/Specialize.cpp` | 150 | `specializeOnGrade`, `redirectCalls` |
| `lib/Transforms/Ownership/Commit.cpp` | 184 | idr-rc-commit: a `PassWrapper` not in `Passes.td`, nested per function |
| `lib/Transforms/Ownership/Knots.cpp` | 29 | idr-knots: refuse a type graph where an array reaches itself (runs right after defunctionalization, not in idr-rc) |
| `lib/Transforms/Demand/Demand.cpp` | 147 | idr-demand: the in-place promise, checked on the grades |
| `include/idr/Transforms/Ownership.h` | 223 | the steps' shared vocabulary |
| `include/idr/Transforms/Stack.h`, `Demand.h` | 17 + 17 | pass declarations |
| `include/idr/Transforms/Passes.td` | 186-205, 480-627 | idr-knots, idr-rc-cells, -stack, -grades, -exclusive, idr-demand |
| total `.cpp` + headers | 2,535 | (*measured*: `cat` of the 19 files `| wc -l`) |

The subsystem leans on four files it does not own: `lib/Analysis/Ownership/`
(Reuses, Borrows, Exclusivity, Uses: lane 07,
`audits/p0/07-ownership-analysis.md`), `lib/IR/Effects.cpp` (`consumes`,
`consumedEffects`: lane 02), `include/idr/IR/{Ownership,Grades,Lifetimes,Flow}.h`
(lanes 01, 02, 05) and `lib/Conversion/{Counting,Cells,Fields}.cpp`
(lane 12).

### 2.2 The pipeline (*read*: `lib/Transforms/Pipeline.cpp:35-50, 125-131`)

`addRc` runs, inside the `idr.program` manager, after idr-accumulate and
idr-frames and before idr-demand, idr-trmc, idr-tail-loops:

1. `idr-rc-cells`, nested on each `idr.func` (stage First to First).
2. `idr-rc-stack`, on the program, role *optimization* (First to First).
3. `idr-rc-grades`, on the program (First to Graded): in order
   (`Grades.cpp:36-68`) `boundaries` and `rebindDefaults` per function in
   `parallelForEach`; `getAnalysis<Reuses>` (per function, in parallel,
   lane 07); `getAnalysis<Borrows>` (one whole-program solve on
   `DataFlowSolver`, `lib/Analysis/Ownership/Borrows.cpp:29-41`);
   `writeOwnedGrades` (every signature); then per function in
   `parallelForEach`: `reuseAt`, `reshape` (`rewriteSelects`, `takeApart`,
   `sinkConsumers`, `ownFields`), `place`.
4. `idr-rc-exclusive`, on the program (Graded to Owned)
   (`Exclusive.cpp:35-57`): `shareTainted`; `Exclusivity::solve` (no
   copies); `specializeOnGrade`; if any copy, `solve` again and
   `redirectCalls`; `writeExclusiveGrades`; a dynamic nested pipeline that
   runs `RcCommit` on each function in parallel.
5. upstream `symbol-dce` (copies and originals no call reaches).
6. `idr-demand` (check, Owned).

### 2.3 Facts the subsystem holds or derives

| fact | where derived | where held after | readers |
| --- | --- | --- | --- |
| a cell is allocated and initialized | Cells.cpp:33-50 | ops `cell.new`, `cell.init` | every later step, lowering |
| frame lifetime of every value a framed cell reaches | Stack.cpp:116-269 (marking) | the grade's lifetime in types and signatures (Stack.cpp:344-353) | verifier (`verify::lifetimes`), Reuses (frame boxes skipped), exclusivity (stack cells never excl), lowering (`LowerCellStack`) |
| which parameters are borrowed | Borrows (lane 07) | signatures (Signatures.cpp:22-44) | placement (Classes.cpp:77-84), shareTainted (Share.cpp:36-37) |
| where each dead box is taken and which cells recycle its cell | Reuses (lane 07), from `whereDies` | `idr.take` + `idr.cell.recycle` (Reuse.cpp:37-67) | lowering (Cells.cpp `LowerCellRecycle`, Fields.cpp), idr-demand (`rebuilt`) |
| the placement class of each value | Classes.cpp:39-122 | nothing: a `DenseMap<Value, Class>` per step, dropped | Reshape (5 constructions), Placement (1) |
| dups, drops, borrows, field ownership at read | Placement.cpp, Reshape.cpp:113-138 | ops | verifier (owned stage), lowering |
| which owned values are exclusive | Exclusivity (lane 07), solved once or twice | excl grades in values, signatures and call results (Signatures.cpp:49-76, Commit.cpp:84-98) | lowering (no count test, no null test), idr-demand |
| grade specialization's keys and copies | Specialize.cpp:92-135 | new functions named `contentName(sym, "excl", positions)` | symbol-dce, every later pass |
| dead paths the solve never reached | Exclusivity's live blocks | `ub.unreachable` (Commit.cpp:61-72) | everything after |
| the in-place promise of an `in_place` type | Demand.cpp:62-77, read off reuse's output | a refusal (`Rule::Uniqueness`, `IdrBase.td:226`) | the user |

### 2.4 State and data structures

- **idr-rc-stack** (*read*: Stack.cpp:260-268): `SmallVector<CellNewOp>
  cells`, `DenseMap<Operation *, unsigned> index`, `DenseMap<Value,
  unsigned> ids` (one entry per value any edge names, over the whole
  program), `SmallVector<Value> byNode`, `SmallVector<SmallVector<unsigned,
  2>> out, in` (one small vector per node per direction, heap-allocated
  past two edges), `SmallVector<unsigned> escapes`, `DenseMap<Operation *,
  bool> loops`; three markings plus a second `keepFills`, each one
  `BitVector` of all nodes (Stack.cpp:197-209); `DenseMap<Operation *,
  unsigned> left` for the frame budget (Stack.cpp:302).
- **idr-rc-grades**: `Reuses` (`DenseMap<FuncOp, SmallVector<Site>>`,
  `include/idr/Analysis/Ownership.h:236`), `Borrows` (`DenseMap<FuncOp,
  SmallVector<Param>>`, `:256`, plus the `DataFlowSolver`'s states during
  its solve, lane 07); per function, `Classes` (`DenseMap<Value, Class>`,
  Ownership.h:152) built up to five times by Reshape (Reshape.cpp:78 once
  *per match*, :117, :160 once *per block*, :232, :262) and once by
  Placement (Placement.cpp:80); Placement's `SmallVector<pair<Value,
  Type>> grades` and `MapVector<Operation *, Changes> changes`
  (Placement.cpp:356-358).
- **idr-rc-exclusive**: `shareTainted`'s `SetVector<Value>` and
  `DenseMap<Operation *, SmallVector<unsigned>>` (Share.cpp:28-29); two
  `Exclusivity` objects, each `DenseMap<Value, Sharing>`, `DenseSet<Block *>`,
  `DenseMap<Operation *, FuncOp>`, callers and returns maps
  (Ownership.h:304-308); `Copies` (`MapVector<FuncOp, FuncOp>`,
  Ownership.h:171-173); `OnceWorklist<FuncOp>` of keys (Specialize.cpp:96).
- **idr-demand**: `DenseMap<StringAttr, SmallVector<unsigned>>`
  (Demand.cpp:104), `SmallVector<Broken>`.

### 2.5 Threading (*read*)

- idr-rc-cells and idr-rc-commit run under MLIR's nested pass manager on
  each function (cells statically in `Pipeline.cpp:38`; commit in a
  pipeline built inside idr-rc-exclusive, `Exclusive.cpp:51-53`).
- idr-rc-grades runs function-local work in `mlir::parallelForEach` on the
  context's pool inside a program pass, twice (`Grades.cpp:41-44, 54-65`),
  because grading signatures and placing bodies must not be separated by
  a verifier (4c87dcc5's message). Reuses is computed per function in
  `parallelForEach` too (`lib/Analysis/Ownership/Reuses.cpp:272-282`).
  Borrows, idr-rc-stack, the exclusivity solves, `shareTainted`,
  specialization and idr-demand are serial.
- Placement and Reshape read callees' signatures through one shared
  `SymbolTable` from every thread (`Placement.cpp:146`,
  `Reshape.cpp:215`, via `lib/IR/Effects.cpp:32-37`): safe only because no
  thread writes a signature during that phase.
- `RcCommit` adds into a statistic owned by the parent from every thread
  (`Commit.cpp:169`).

### 2.6 Pattern counts in the subsystem (*measured*)

Command: `bash -c 'F=(lib/Transforms/Ownership/*.cpp lib/Transforms/Stack/Stack.cpp lib/Transforms/Demand/Demand.cpp include/idr/Transforms/{Ownership,Stack,Demand}.h); cat "${F[@]}" | grep -c -- PATTERN'`
from `foreign/idr`.

| pattern | count |
| --- | ---: |
| `isa<` | 11 |
| `isa_and_nonnull<` | 2 |
| `dyn_cast<` | 23 |
| `cast<` (includes the `dyn_cast<` above) | 42 |
| `std::visit` / `std::get_if` / `holds_alternative` | 3 |
| `switch (` | 4 (three over `Class`, one over `Borrows::Param`) |
| `DenseMap<` / `DenseSet<` | 7 |
| `MapVector<` / `SetVector<` | 6 |
| `.walk` | 26 (8 of them whole-program: Share.cpp:30, 40; Signatures.cpp:71; Stack.cpp:120, 132, 291, 359; Specialize.cpp:140) |
| `getAnalysis<` | 9 |
| `parallelForEach` | 2 |
| `hasTrait<` | 5 |
| `getEffects` | 2 |
| `symbols.lookup` | 7 |
| `Classes(fn)` / `Classes classes` | 6 |
| `function_ref<`, `template <`, `requires`/`concept` | 0, 0, 0 |
| `BitVector` | 11 |

Readers of "does this operand take over its reference" in the subsystem
(*read*), five rules for one fact: `consumes(op, &symbols)` (callee's
signature, Placement.cpp:146, Reshape.cpp:215); `consumes(op)` (the
operand's grade, Classes.cpp:51); `useOf` (the same, Share.cpp:54, via
`lib/IR/Verify/Uses.cpp:26-28`); Reuses' `isa<CallOp> || consumes`
(`lib/Analysis/Ownership/Reuses.cpp:195`); and the declared `Free` on
`ReferenceResource` (Reshape.cpp:291-306). Each `consumes` call rebuilds
the op's whole `FlowEdges` (`lib/IR/Effects.cpp:44-90`).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs, one by one

| proposal | claim | verdict | evidence (*read* unless marked) |
| --- | --- | --- | --- |
| §3, b8301ebe row | idr-rc-stack kept a candidate bit vector per value, copied along every edge | holds, as history; fixed | the commit replaced it by one graph and markings (`git show b8301ebe`, Stack.cpp:116-269) |
| §5.1 5.1.2 item 3 | rc-stack's inference is per-program-point, set-valued, and stays ours | holds in part | it stays ours, but it is no longer per point nor set-valued: one bit per node of a whole-program value graph (Stack.cpp:110-115, 197-209); what remains per value is the `DenseMap<Value, unsigned> ids` (Stack.cpp:265) |
| §5.1 G3, 5.1.5 | ownership-based deallocation's per-function ABI as a model | holds in part | placement reads only a callee's signature (Placement.cpp:39-41, 146), which is that ABI once grades are written; but the grades themselves are solved across calls (Borrows on `DataFlowSolver`; Exclusivity, twice; `shareTainted`, Share.cpp:27-63) |
| §5.1 W3 / §5.6 W-E6 | edge tables built per query on wide matches | holds, new instance | `decides(op)` (`lib/Analysis/Ownership/Uses.cpp:96-104`) calls `verify::alternatives` (`lib/IR/Verify/Linearity.cpp:27-33`, one `getSuccessorRegions` per region) and `getSuccessorRegions(parent)` on every call: Θ(N) for an N-case match, asked per user (Placement.cpp:193, 247), per ancestor level (`usedAfter`, Uses.cpp:124, reached from `Classes::aliveAt`, Classes.cpp:113), per last use (`whereDies`, Uses.cpp:147) and per op in Reuses' `fits` (Reuses.cpp:219). *Conjecture*: O(N²) per wide match from the field reads of its cases alone |
| §5.3 M5 | idr-rc-stack's per-node containers | holds in part | the bit vector per value is gone; per-node `SmallVector<unsigned, 2>` adjacency in both directions remains (Stack.cpp:267) |
| §5.3 M7, S1 `mark` | the recent fixes are the SCCP shape found by hand; `mark` should be one generic mechanism | holds | `Inference::mark` (Stack.cpp:197-209) is exactly S1's `mark`, private to the file, with the direction as a `bool` |
| §5.4 F5, Design 3 | state copied per region or edge; rows shared until written | refuted for counting today | no step of the subsystem keeps a per-program-point state: Placement keeps one grade per value and one change list per op (Placement.cpp:356-358); Stack one bit per node |
| §5.6 item 1, Design 2 | a solver's domain is the values whose type leaves its question open | holds in part | Stack's graph names only values that may be frame (`edgesOf` filters by `mayBeFrame`, `include/idr/IR/Lifetimes.h:88-93`); placement skips values whose type holds no reference (Classes.cpp:45, Placement.cpp:106-107); a linear value is placed like any other, as §5.10 M5 predicts it should be |
| §5.6 item 8 | structured walk copying state per branch | refuted for counting | nothing is copied per region; the cost on wide matches is in per-region queries instead (`usedIn`, Classes.cpp:124-128; `decides`, above) |
| §5.7 M4 | "can v's cell live on the stack" is a partitioned problem whose sparse form is one bit per value on def-use edges | holds | that is the current representation (Stack.cpp:110-115) |
| §5.7 L1, M1 | ownership changes should define values (SSI) | holds in part | `idr.borrow`, `idr.dup`, `idr.share`, `idr.take`, `idr.unpack`, `lin.enter`, `lin.use`, `own.adopt`, `own.give` each define a new value (`include/idr/IR/IdrOwnershipOps.td:62-424`); against it, `rebindDefaults` (Placement.cpp:364-375) and Reshape.cpp:103-105 *merge* a match's default binding back into the scrutinee |
| §5.9 M5, Design 4 | counting's liveness per function, one variable at a time, cost the size of the answer | holds in shape, not in cost | "Each value is placed on its own, along the ops of the block that defines it" (Placement.cpp:8-9): per variable, per function; but each placement re-walks all of the value's uses per block and per region (`usersIn`, Uses.cpp:30-40, 84-90; `usedIn` per region, Placement.cpp:199, 214, 245), so the cost is not the answer's size |
| §5.10 M1 | every counting algorithm is per function, reads others only through signatures; none keeps per-value state for the whole program | holds in part | per function: reuse rewrite, reshape, placement, commit; whole program: Stack (`DenseMap<Value, unsigned>` over every frame-able value, Stack.cpp:265), Borrows, Exclusivity (`DenseMap<Value, Sharing>`, Ownership.h:304), `shareTainted`, specialization |
| §5.10 M2 | liveness should be the insertion walk's state, not an analysis another component reads | holds in part | no liveness analysis feeds placement; but "where a value dies" is derived three times from one vocabulary with three different take-over rules: Reuses (any call takes over, `Reuses.cpp:195`), Reshape (callee grades, Reshape.cpp:95, 278), Placement (callee grades, Placement.cpp:184-236) |
| §5.10 M3 | consuming traits are OSSA's lifetime-ending bit | holds in part | consumption is derived from flow edges and the callee's grade (`lib/IR/Effects.cpp:44-90`) and declared as `Free` on `ReferenceResource` only for owned operands (`:96-105`); the subsystem reads it five ways (§2.6) |
| §5.10 M4 | an exclusive operand makes the uniqueness test constant | holds, in the lowering | `LowerTake` skips the test on an excl value (`lib/Conversion/Counting.cpp:91-92`), `LowerCellRecycle` the null test on an excl token (`lib/Conversion/Cells.cpp:123-127`) |
| §5.10 M5 | a quantity-1 parameter is owned by its type | holds | Borrows: "A parameter of quantity 1 is owned too" (`lib/Analysis/Ownership/Borrows.cpp:23-25`) |
| §5.10 M6 | exclusivity and stack are two-point markings; three markings, one solver layer | holds in part | Stack: marking (Stack.cpp:197-209); Exclusivity: marking (ffa91113, lane 07); borrow inference is a monotone solve on `DataFlowSolver` (Borrows.cpp:29-41), not a marking in the layer |
| §5.10 M7 | if Reuses pairs before insertion it is algorithm K or D; drop-guided needs only a forward walk | refuted in part | Reuses runs before placement (Grades.cpp:45, 57-62) and pairs **by size** (Reuses.cpp:192, 213) at the box's **predicted death point** (`whereDies` with "any call takes over", Reuses.cpp:192-200): not K (no reuse at a branch head while live), not D (no reset pushed past the last use); it is death-point-guided but predicted before the drops exist, then made true by `takeAt`. A token is held from the take to the first same-size `cell.new` on the same path, across calls (`fits` scans every op, Reuses.cpp:208-227). Same-constructor detection is the lowering's (`lib/Conversion/Fields.cpp:32-49`) |
| §5.10 M10 | counting before TRMC; Koka the reverse | holds | `Pipeline.cpp:128-131`; Borrows predicts idr-trmc's decision ("A self call whose result a tail position puts in a constructor counts as one", Borrows.cpp:16-19); Placement keeps self tail calls (Placement.cpp:32-34) |
| §5.10 R1.1 | parameter and result grades in function types | holds | owned/view (Signatures.cpp:22-44), excl (Signatures.cpp:49-76), frame (Stack.cpp:344-353) |
| §5.10 R1.3 | per-function passes nested on `idr.func` | refuted | the per-function work runs in `parallelForEach` inside program passes (Grades.cpp:41, 54); the commit in a pipeline the pass builds (Exclusive.cpp:51-53) |
| §5.10 R1.4 | uniqueness as an op whose folder decides | refuted | no such op; the static case is a C++ branch in two lowering patterns (Counting.cpp:91-107, Cells.cpp:123-127) |
| §5.10 R1.5 | `dup`/`drop` write the count resource, `is_unique` reads it | holds in part | `dup`: `MemRead, MemWrite` on the default resource; `drop`, `take`: `MemRead, MemWrite, MemFree` (IdrOwnershipOps.td:74, 89, 318); consumption elsewhere is `Free` on `ReferenceResource` (Effects.cpp:96-105): two resources for one count |
| §5.10 R2 | grade specialization, under idr-optimize | holds, elsewhere | built in idr-rc-exclusive after placement (Specialize.cpp:1-29, 92-148): one copy per function, key "every followed parameter exclusive", the key set closed over callees and fed calls |
| §5.11 A1, W item 7 | state sized by a product of two program quantities | holds (new instances, *conjecture* on size) | `usedIn` per region per value (regions × uses, Placement.cpp:193-217), `decides` per query (queries × regions), `Classes` rebuilt per block in `sinkConsumers` (blocks × class work, Reshape.cpp:154-160) |
| §5.8 DS4 `cell.new`/`cell.stack` | one class parameterized by the resource | holds in part | the effects already differ only by resource (`MemAlloc<DefaultResource>` / `MemAlloc<AutomaticAllocationScopeResource>`, IdrOwnershipOps.td:192, 211); two definitions (lane 03) |
| §5.8 DS4 `cell.recycle` | Free stage 0, Alloc stage 1 | holds already | `MemFreeAt<0, FullEffect>` on the token, `MemAlloc<DefaultResource, 1, FullEffect>` on the cell (IdrOwnershipOps.td:230-231) |
| §5.8 DS4 `take`, `unpack` | one consuming destructure | refuted (essential) | a take has a cell and gives a token, an unpack has none (Take.cpp:49-54: "S36: a cell or none"); different results, different effects |
| §5.8 O3 | a regrade is a cast up the grade order | holds | `idr.share` serves both "forget exclusivity" and "raise to the frame" (Commit.cpp:43, Stack.cpp:280-281): one cast up the order, one meaning |
| 0003 "a token without its cell" | Demand walks back to the take | holds | Demand.cpp:66 |
| 0003 "exclusivity solved twice" | | holds | Exclusive.cpp:39-46 |
| 0003 "static lifetime in the grade" | Classes' Phantom, Constant, StaticRead | holds | Classes.cpp:52-61, Placement.cpp:108-123, Ownership.h:105-128 |
| 0003 "exclusivity is no analysis" | | holds | Ownership.h:61-69, Commit.cpp:153-182 |
| 0003 "Placement's `casesOf`" | | not in this subsystem | `casesOf` is `lib/Transforms/Expect/Placement.cpp:35` (lane 19) |

### 3.2 Wave-2 questions in this subsystem, by ID

**§5.10 (rc).**
- **W1** (who inserts `dup` and `drop`; is liveness one component's,
  read by another). `place` in idr-rc-grades (Placement.cpp:377-379),
  after `reshape`, which itself inserts the dups of fields owned at read
  (Reshape.cpp:113-138). No liveness *analysis* feeds it: liveness is
  asked on demand through `usersIn`, `usedAfter`, `whereDies`
  (`lib/Analysis/Ownership/Uses.cpp`), and the classes (Classes.cpp)
  recompute "is the root alive at each use" per step. The rederivation is
  of death points, three times (§3.1, M2 row).
- **W2** (Reuses before or after insertion, by constructor or size,
  tokens across calls). Before (Grades.cpp:45 then 57, 62); by size
  (Reuses.cpp:213); a token may be held across a call to the first
  same-size `cell.new` on its path (Reuses.cpp:208-227; no op stops the
  scan). Borrows then keeps owned every parameter a reuse takes apart
  (Borrows.cpp:7-9, "the takes of reset/reuse are its decisions, not ops
  yet: each one owns its box", :43-44): Lean's order (§5.10 B2, B4).
- **W3** (what `idr-rc-grades` writes; grades in function types). It
  writes `own` on owned parameters and on every result that holds
  references, the view grade on borrowed parameters
  (Signatures.cpp:22-44), into `FunctionType` and the entry block; then
  each body's counts. Callers read a callee's grade from its signature
  through the program's `SymbolTable` during placement (Placement.cpp:146).
- **W4** (rc-exclusive's graph). The graph is lane 07's
  (`lib/Analysis/Ownership/ExclusivityGraph.cpp`); from this side: the
  pass solves once without copies and once with them (Exclusive.cpp:39-46),
  and holds both solves' tables for the duration of the pass. No
  measurement exists in this checkout.
- **W5** (the grade verifier). Not in this subsystem (`lib/IR/Verify/`,
  lanes 01 and 02). What counting relies on: the owned stage's rule that a
  terminator takes over what it passes (asserted again in C++,
  Placement.cpp:231-232) and verifySymbolUses for call operands
  (`lib/IR/Func/Call.cpp:29-59`).
- **W6** (runtime header). Lane 18. From the lowering's side: `unique`
  is count 1 and not a stack cell (`runtime/Rc/Counting.cpp:55-60`,
  Lean's encoding, §5.10 B6), counts saturate (`:3-5`), no atomics in
  `runtime/Rc/` (*measured*: `grep -rln atomic runtime` finds only
  `Alloc/Cells.cpp`, `Io/Output.cpp`, `Strings/Simd.cpp`); an exclusive
  take still loads its fields but reads no count (Counting.cpp:91-92).
- **W7** (each ownership op against the field's), for the ops this
  subsystem makes: `take` = FP²'s destructive match and Koka's unique arm
  of drop-special, with the shared arm in the lowering (Counting.cpp:93-107);
  `unpack` = a cell-less destructure, essential beside `take` (Take.cpp:49-54);
  `share` = uniqueness logic's one-way `P ⊢ P°`, also used to raise a
  lifetime (Stack.cpp:280); `borrow` = OSSA's guaranteed view, unscoped
  (Placement.cpp:254-256, 290-303: a view per read, no end op);
  `own.adopt`/`own.give` = the two directions of the buffer boundary
  (Buffers.cpp:21-48). `lin.enter`/`lin.use` are not made here.
- **W8** (regions or CFG; TRMC after counting). On `idr.match` regions
  and other region branches ("functional code, where a region's terminator
  is the join point", Placement.cpp:3-6; `decides`, Uses.cpp:96-104); TRMC
  and tail loops run after (Pipeline.cpp:128-132); counting keeps self
  tail calls by placing nothing after a consuming call (Placement.cpp:32-34)
  and Borrows predicts TRMC (Borrows.cpp:16-19). Whether TRMC keeps the
  reuse is lane 10's to read.
- **W9** (arrays freed by our code or upstream's deallocation). By ours:
  `boundaries` makes counting own each `memref.alloc` (`own.adopt`) and
  hand each counted store its value (`own.give`) (Buffers.cpp:27-49);
  `Classes` treats both as untracked by op name (Classes.cpp:45). Lane 11
  weighs ownership-based deallocation.

**§5.9 (mlton).**
- **Q-W4** (passes that read `match`'s region structure). All of counting:
  placement moves a value into each region of a deciding op
  (Placement.cpp:193-206), drops on region entry, reads a match's case
  arguments and default binding (Placement.cpp:333-348, 364-375); Reshape
  takes apart at case entry (Take.cpp:44-56, Reshape.cpp:81-99); Reuses
  searches each region (Reuses.cpp:219-225). A CFG `case` (Design 2) would
  need these rewritten over blocks or run before the lowering to it.
- **Q-W6** (liveness or last-use facts per rc pass). idr-rc-cells: none.
  idr-rc-stack: reachability on the value graph, no liveness. idr-rc-grades:
  last use per value per block (`usersIn`, `usedAfter`, `whereDies`),
  per variable, on demand. idr-rc-exclusive: none of liveness; block
  reachability from the solve (`Exclusivity::live`, Commit.cpp:48).
  demand: none. Each per-variable query fits Design 4; the whole step fits
  a reverse walk with the live set as state (§5 T3).

**§5.6 (ecosystem).**
- **W-E2.** Stack: nodes for every value an edge names (only frame-able
  types, Lifetimes.h:88-93), whether or not a candidate reaches it.
  Placement: every value whose type holds references (Classes.cpp:45).
  No count exists without a built compiler.
- **W-E4.** No discardable attribute carries a fact in this subsystem
  (*measured*: `grep -n "setAttr\|setDiscardableAttr\|removeAttr"
  lib/Transforms/Ownership/*.cpp lib/Transforms/Stack/Stack.cpp
  lib/Transforms/Demand/Demand.cpp` finds none; the `getAttr()` hits are
  `getCalleeAttr().getAttr()`, a symbol name). Facts go into types, ops and
  signatures.
- **W-E5.** Budgets: `stackCellLimit = 256`, `stackFrameLimit = 1024`,
  `recursiveStackFrameLimit = 64` bytes (Stack.cpp:78-80); each only
  leaves a cell on the heap, never fails. Grade specialization has no
  budget: at most one copy per function (Specialize.cpp:9-11). No round
  count in the subsystem; Exclusivity's own loop is lane 07's (c4d38e9b:
  "repeats while a label goes").
- **W-E7.** `DenseMap<Value, Class>` per function per step (Classes);
  `DenseMap<Value, unsigned>` for the whole program (Stack.cpp:265).
- **W-E8.** Counting assumes single-block regions for stack placement
  (`placeable`, Stack.cpp:92-103) and reads blocks through
  `Block::findAncestorOpInBlock` elsewhere; an `idr.func` body is one block
  (`include/idr/IR/Flow.h:10-11`).
- **W-E9.** No step copies state per edge or branch since b8301ebe.

**§5.3 (llvm), wave-2 bullets.**
- Worklists: `Inference::mark`'s `SmallVector<unsigned>` stack with a
  `BitVector` seen set (Stack.cpp:197-209); `OnceWorklist` for
  specialization keys (Specialize.cpp:96) and feeder chains
  (Reshape.cpp:311). Node identity: dense indices in Stack, `FuncOp` and
  `Operation *` elsewhere.
- `DenseMap`/`DenseSet` per node: none; one per solve or per function.
- `function_ref`: none in the subsystem; it passes lambdas into
  `whereDies` (function_ref, `include/idr/Analysis/Ownership.h:116-121`)
  and `edgesOf` (`Lifetimes.h:92-93`).
- Variants: `Reuses::Site::box` (`std::variant<Value, TakenField>`),
  visited once exhaustively (Reuse.cpp:42-48); `lifetimes::Edge`, visited
  exhaustively (Stack.cpp:212-245); `idr::Source` read by a `get_if`
  validator (Demand.cpp:43).
- rc-stack's graph: nodes are candidate cells first, then values in the
  order an edge first names them; edges carry, fill, pass; escapes are a
  sink list (Stack.cpp:105-115, 181-194). It fits one CSR `Graph` with
  `GraphTraits`.

**§5.1 (mlir-analysis).**
- **W2.** idr-rc-stack: per node (value or cell), one bit per marking,
  interprocedural through `Passes` edges to parameters, no summaries,
  Design 3. Classes: per value per function, recomputed. Placement: per
  value and per op, per function.
- **W3.** `decides` per query (above). No `getPredecessors`,
  `getSuccessorOperandInputMapping` or `isRepetitiveRegion` in the
  subsystem (*measured*: grep finds none).
- **W6.** Only idr-rc-cells is nested on functions by the pipeline
  (Pipeline.cpp:38). Grades and commit are function work run inside
  program passes (§2.5).

**§5.2 (mlir-ods).** W1: no hand `getEffects` in the subsystem; it reads
effects in two places (Placement.cpp:152-161, Reshape.cpp:291-306). W2: no
`MatchAnyOpTypeTag`. W3: no `verify()`. W9: idr-knots and idr-demand mark
all analyses preserved (Knots.cpp:25, Demand.cpp:141); idr-rc-stack does
when nothing moves to the frame (Stack.cpp:326-327); the others preserve
`SymbolTable`, `TypeGraph`, `Layouts` (Grades.cpp:67, Exclusive.cpp:56,
Stack.cpp:381).

**§5.4 (modular).** Copy per region or edge: none (above). Options that
select between implementations: none (*measured*: no `Option<` in the
pass records, Passes.td:487-627). Facts read from the mutable `!idr.data`
by many threads: Placement's `gradeViews` reads `getDataType().getCtor`
from every thread of `parallelForEach` (Placement.cpp:314, 339-341), as
Reshape does through `buildsCell` (Reshape.cpp:92); no lock on a read
path here.

**§5.5 (cxx26).** No template, concept, `function_ref` or `virtual`.
Variants above. `llvm::zip` where `zip_equal` belongs: Specialize.cpp:53,
Commit.cpp:103.

**§5.7 (library).** Stack's fact is independent per value (PLV,
reachability); placement's is per variable but relational where a field's
grade depends on its root's liveness (Classes.cpp:99-122); exclusivity is
relational across calls. Stack and placement read nothing of each other
but the frame lifetime in types. Stage-1 counts: not measurable here.

**§5.8 (dialect-design).** Grades the subsystem writes: `own`, `excl`, the
view grade (borrow), frame lifetime; `lin` is the frontend's
(Signatures.cpp:26-41, Stack.cpp:346, Commit.cpp:86-95). Consumption read
five ways (§2.6).

**§5.11 (oom).** Item 7: the three quadratic shapes above (§3.1).

## 4. Issues

Paths under `foreign/idr/`. All *read* unless marked. Dispositions name
the target change of §5 (T1 to T16).

### 4.1 Headers and pass records

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-01 | include/idr/Transforms/Ownership.h:48 | dead | `GEN_PASS_DECL_IDRRCPLACE`: no `IdrRcPlace` record exists since 4c87dcc5 deleted `Place.cpp` (*measured*: `grep -rn IDRRCPLACE include lib tools` finds only this line) | delete |
| C-02 | include/idr/Transforms/Ownership.h:50; lib/Transforms/Ownership/Knots.cpp | cpp | idr-knots is declared in counting's header and lives in its directory, yet runs right after defunctionalization (Pipeline.cpp:74) and reads only the type graph (Knots.cpp:23) | move with the type graph's checks (lane 01/05); no behaviour change |
| C-03 | include/idr/Transforms/Ownership.h:61-69; lib/Transforms/Ownership/Commit.cpp:153-182 | ods / upstream | `createRcCommit(const Exclusivity &, const SymbolTable &, Statistic &)`: a `PassWrapper` with no `Passes.td` record, handed the parent's state by constructor (0003 "Exclusivity is no analysis") | T5: Exclusivity a cached program analysis; the commit a registered nested pass reading `getCachedParentAnalysis` |
| C-04 | include/idr/Transforms/Ownership.h:105-128 | state / rederivation | `enum class Class` (seven cases) computed per value per step and dropped; `Phantom`, `Constant`, `StaticRead` restate staticness found by a chain walk (0003) | T1 + T2: static in the grade; the class *is* the grade; delete the enum |
| C-05 | include/idr/Transforms/Ownership.h:142-153 | state | `Classes` holds `DenseMap<Value, Class>` per step; constructed six times per function (Reshape.cpp:78 per match, :117, :160 per block, :232, :262; Placement.cpp:80) | T2/T3: deleted |
| C-06 | include/idr/Transforms/Ownership.h:155-159; Classes.cpp:124-130 | ladder / state | `usedIn(value, region)` walks every use per region (O(uses × depth) per call); `endsInCrash` is `isa<ub::UnreachableOp>(block.back())` | T3 (the walk visits each region once); "ends in a crash" from the terminator's declared kind (a no-successor terminator, lane 03) |
| C-07 | include/idr/Transforms/Ownership.h:166-182; Take.cpp:33-78 | cpp | two coordinates for one point: `Point` (Analysis/Ownership.h:68) and `(Block &, Block::iterator)`; `reuseAt` converts (Reuse.cpp:51) | one coordinate (`Point`) in every signature |
| C-08 | include/idr/Transforms/Ownership.h:200; Placement.cpp:364-375; Reshape.cpp:101-105 | rederivation | a match's default binding is merged into its scrutinee twice, under two rules (types equal and not linear; or region does not use the scrutinee) | T3: the match forwards the scrutinee into the default region as a successor input; counting reads the move; both merges deleted (QL2 evidence) |
| C-09 | include/idr/Transforms/Passes.td:525-527 vs Stack.cpp:78-80 | list | the stack budgets written twice, in the description and the constants | one source (the constants, named in the description by reference, or a generated table) |
| C-10 | include/idr/Transforms/Passes.td:537-578 | upstream | idr-rc-grades and idr-rc-exclusive are program passes because grading signatures and placing bodies must not meet a verifier (4c87dcc5); but `idr.call`'s callee check is in `verifySymbolUses` (lib/IR/Func/Call.cpp:29-59), run only when the program verifies | T6: grading, placement and commit as passes nested on `idr.func`, conventions read from a frozen analysis or the call |

### 4.2 idr-rc-cells, idr-rc-grades, the boundaries

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-11 | Cells.cpp:30-50 | upstream | a walk-collect-rewrite loop over `idr.con`; the cell type built in C++ (`cast<BoxType>(unrestricted(type))`, :41) | a rooted rewrite on the walk driver (§5.2 E3), `CellNewOp`'s result type from a builder taking the con (lane 03) |
| C-12 | Cells.cpp:30 | cpp | `runOnProgram(idr::ProgramOp)` on a function pass ignores its argument; the function is `getOperation()` | StagedPass hands a function pass its function (lane 13) |
| C-13 | Grades.cpp:41-44 | upstream | `boundaries` and `rebindDefaults`, function-local, run in `parallelForEach` inside a program pass | move into idr-rc-cells (nested); `rebindDefaults` deleted (C-08) |
| C-14 | Grades.cpp:54-65 | upstream | reuse, reshape and placement per function in `parallelForEach` inside a program pass | T6: nested pass manager |
| C-15 | Grades.cpp:45-49 | rederivation | Borrows reads Reuses (a parameter a reuse takes apart is owned, Borrows.cpp:7-9, 43-44): reuse decisions made on a simulated body before any count exists | T4: reuse after placement; the forced-owned reason computed from the body's shape (owner: NQ2) |
| C-16 | Buffers.cpp:30-36 | ladder / upstream | upstream ops found by name (`dyn_cast<memref::AllocOp>`, `<memref::StoreOp>`) (0003 "the owned stage reads upstream's buffer ops by name") | crossing ops of their own or effects (`Allocate` on the result, `storedBy`); lane 11 and 03 decide |

### 4.3 Classes and placement

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-17 | Classes.cpp:24-37 | ladder | `ownsReference` switch over `Class` (switch 1 of 3) | T2: `isOwned(type)` |
| C-18 | Classes.cpp:45 | ladder | `isa_and_nonnull<memref::AllocOp, OwnGiveOp>(def)` | C-16 |
| C-19 | Classes.cpp:51 | rederivation | consumption read from the operand's grade (`consumes` without symbols) beside the callee-signature reading elsewhere | T7: one reading, the declared `Free` |
| C-20 | Classes.cpp:52-61 | rederivation / ladder | `isStatic` walks the definition chain per query; `isa_and_nonnull<ub::PoisonOp, BigSmallOp>` picks `Phantom` | T1 |
| C-21 | Classes.cpp:62-86 | state | memo map plus recursion through `aliveAt`, owned assumed on re-entry (unreachable blocks) | T3: the reverse walk's live set answers "root alive after this use" in O(1) |
| C-22 | Classes.cpp:99-122 | ladder / rederivation | `aliveAt`: switch over `Class` (switch 2 of 3), `definitionChain` walk, `usedAfter` per user (which climbs ancestors and asks `decides`, Θ(N) on a match) | T3 |
| C-23 | Placement.cpp:65-96 | rederivation | placement re-derives classes for every value, then plans each value forward along its block | T3: one reverse walk per function |
| C-24 | Placement.cpp:101-133 | ladder | `plan` switch over `Class` (switch 3 of 3) | T2/T3 |
| C-25 | Placement.cpp:136-146, 276, 295 | rederivation | `takes(operand)` = `consumes(operand, &symbols)`: the op's `FlowEdges` rebuilt per operand per query (lib/IR/Effects.cpp:44-90), the callee's signature read through a shared `SymbolTable` | T6 + T7: the call's conventions on the call, consumption a declared effect read once |
| C-26 | Placement.cpp:152-161 | (keep) | `writes(op, value)` reads a declared `Write` on the value: an update holds its array until its region ran | essential; already on effects |
| C-27 | Placement.cpp:184-236 | state | `placeOwned` recursion: `usersIn` re-walks all uses per block (Uses.cpp:84-90), `usedIn` per region (:199, :214), `decides` per user (:193): *conjecture* O(regions × uses) per value on wide matches | T3 |
| C-28 | Placement.cpp:231-232 | rederivation | `assert` of the owned stage's terminator rule, which the verifier holds | delete (the verifier is the one check) |
| C-29 | Placement.cpp:242-250 | state | `placeBorrowed` recursion with the same per-region `usedIn` | T3 |
| C-30 | Placement.cpp:264-304 | rederivation | `materialize` runs a second whole-function walk to find every owned operand that does not take (consumption asked again) | T3: the walk emits views as it meets reads |
| C-31 | Placement.cpp:311-350 | ladder / rederivation | `gradeViews`: `dyn_cast<FieldOp>`, `isa<TakeOp, UnpackOp>` with a hand call of `inferReturnTypes`, `MatchOpInterface` then `dyn_cast<MatchOp>` for case arguments: result types re-inferred by hand after grading | one loop over ops with `InferTypeOpInterface` (upstream), the case arguments from the match interface; no op list |
| C-32 | Placement.cpp:356-358 | (keep) | `grades` per value, `changes` per op: no per-point state | the reverse walk keeps the same output shape |

### 4.4 Reshape, take, reuse

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-33 | Reshape.cpp:34-56 | rederivation | a select of references becomes `match_lit` here, after idr-rc-stack has had to handle selects (Stack.cpp:371-375) | T11: in idr-rc-cells; Stack's select case deleted |
| C-34 | Reshape.cpp:69-107 | rederivation | `takeApart`: where a matched box dies, computed with `whereDies` (callee grades) beside Reuses' computation of the same (any call takes over, Reuses.cpp:192-200) and placement's own drops | T3/T4: drop specialization at the drops the walk placed; one death point |
| C-35 | Reshape.cpp:78 | state | `Classes(fn)` rebuilt per match | T2 |
| C-36 | Reshape.cpp:113-138 | rederivation | `ownFields` re-classifies every value to insert a dup after each field read that needs its own reference (Lean's derived borrows, decided per step) | T3: the walk decides view or own at the read |
| C-37 | Reshape.cpp:149-210 | state | `sinkConsumers` builds `Classes` per block (:160); `readBetween` iterates every use with `findAncestorOpInBlock`; an optimization (avoids a dup) with no action wrapper, inside a lowering-role pass; its outcome changes whether a dup appears, hence exclusivity and idr-demand's verdict | keep as an optional code motion before placement, wrapped as an action; owner question NQ1 on acceptance |
| C-38 | Reshape.cpp:191-199 | ladder | `isa<FieldOp>(user)` for "a field read from it" | `readFrom` (IR/Ownership.h:60) |
| C-39 | Reshape.cpp:231-254 | ladder | `takeReadSums`: `isa<DataType>`, every user a `FieldOp` of one tag | T3: drop specialization of a sum (an unpack) at its drop |
| C-40 | Reshape.cpp:261-284 | rederivation | `takeReadBoxes` repeats Reuses' `readBoxes` (Reuses.cpp:94-135): both find boxes only read through one constructor and take them where they die | T3/T4: one rule after placement |
| C-41 | Reshape.cpp:291-306 | rederivation / ods | `movable` reads effects by resource `TypeID` (`Allocate` on `LinResource`, `Free` on `ReferenceResource`): a speculation-like predicate written by hand | declared: `isMemoryEffectFree` but for `Free` of its own consumed operands (T7); the `Lin` allocate goes with the regrade casts (lane 03, DS4) |
| C-42 | Reshape.cpp:310-321 | (keep) | `feeders` with `OnceWorklist` | keep with C-37 |
| C-43 | Take.cpp:44-56 | (keep, essential) | `buildsCell ? TakeOp : UnpackOp` | two ops: a take gives a token and frees a cell, an unpack does neither |
| C-44 | Take.cpp:58-64 | ladder | `dyn_cast<FieldOp>` over users | `readFrom`/the field-read interface |
| C-45 | Reuse.cpp:37-67; lib/Analysis/Ownership/Reuses.cpp:59-266 | rederivation / state | reuse decided on a simulated body: `Held` (`variant<Value, TakenField>`), `Virtual`, `moved`, `takesAt`, then replayed by `reuseAt` | T4: drop-guided reuse after placement deletes the simulation (lane 07 for the analysis side) |
| C-46 | Reuse.cpp:61-62 | dead | `site.cells.empty()` cannot hold: `record` is reached only from `fits`, which returns true only after pushing a cell (Reuses.cpp:208-227, 199) | `Site::cells` non-empty by type (first cell plus rest), branch deleted |
| C-47 | Reuse.cpp:25-28 | (keep) | `ReuseAction`: each reuse optional | keep; owner NQ1 (skipping one changes idr-demand's verdict) |

### 4.5 idr-rc-stack

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-48 | Stack.cpp:78-80 | budget | 256, 1024, 64 bytes; never fails; units are bytes of the target's layout | keep (AGENTS.md's budget); C-09 |
| C-49 | Stack.cpp:92-103 | ladder / rederivation | `placeable` climbs to `isa<idr::FuncOp>` while the lowering finds the frame by `getParentWithTrait<AutomaticAllocationScope>` (lib/Conversion/Cells.cpp:93): the frame scope said twice | the upstream trait in both |
| C-50 | Stack.cpp:116-269 | state / upstream (solver layer) | a private graph and marking: `DenseMap<Value, unsigned>`, per-node `SmallVector<unsigned, 2>` both ways | T9: the solver layer's CSR graph and `mark`, dense numbering by per-function extract |
| C-51 | Stack.cpp:197-209 | cpp | `mark(seeds, bool backward)`: direction as a flag | `Forward`/`Backward` as types (§5.3 S1) |
| C-52 | Stack.cpp:226-243 | rederivation | per `Passes` edge: `symbols.lookup`, `getParentOfType<FuncOp>`, `tail::inTailPosition`, `cycles.together`, `loopsInFrame` (memoized per callee in `DenseMap<Operation *, bool>`) | facts the call graph and tail analysis already hold, read from the cached analyses (lane 10, 05) |
| C-53 | Stack.cpp:291 | rederivation | a whole-program walk only to count `numBoxes` | count in the Inference walk |
| C-54 | Stack.cpp:344-353 | (upstream) | signature rebuilt from entry block types (`setFunctionType`) | upstream's FunctionOpInterface duplication; keep |
| C-55 | Stack.cpp:358-376; Commit.cpp:101-117 | ladder / rederivation | two hand lists of "where a value meets a slot of a declared type": forwarded values, `dyn_cast<CallOp>` against callee params, `dyn_cast<arith::SelectOp>` (Stack), `dyn_cast<ReturnOp>` against results (Commit) | T10: one slot query over interfaces (`CallOpInterface`, `ReturnLike`, `RegionBranchOpInterface`, `SelectLikeOpInterface`) |
| C-56 | Stack.cpp:285-382 | upstream | a program pass, serial; the graph build is a per-op walk that could be per function | T9: extract per function in parallel, link, mark |

### 4.6 idr-rc-exclusive, commit, specialization, share

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-57 | Exclusive.cpp:39-46 | rederivation | the program solved twice (0003) | T5: one solve over a graph with a potential copy per copyable function, keys read off it, copies made after (§5.7 L5) |
| C-58 | Exclusive.cpp:51-53 | upstream | a nested `OpPassManager` built inside the pass to run a pass holding references | T5: the commit in the pipeline (Pipeline.cpp), reading the cached analysis |
| C-59 | Commit.cpp:84-98 | ladder | `op.hasTrait<SameValue>() ? ... : !isa<CallOp>(op) && solved.proves(result)` | `CallOpInterface` for "results are the callee's" |
| C-60 | Commit.cpp:126-137 | cpp | dead paths ended deepest first by a depth lambda and a sort | keep (essential order), or end paths in one post-order walk |
| C-61 | Commit.cpp:140-146 | ods | identity shares removed by a hand loop | a `ShareOp` folder (value when the types are equal) (lane 03/04) |
| C-62 | Commit.cpp:35-56 | (keep) | `meet`: an internal disagreement of solver and commit is an error, a dead path ends | keep; the error becomes an `internal error:` diagnostic |
| C-63 | Specialize.cpp:73-83, 124-127 | list / rederivation | the copy named from a string of positions (`contentName(sym, "excl", key)`), its collision checked by `symbols.lookup` beside `ContentNames::intern`, the one check (include/idr/IR/Symbols.h:283-293) | T12: an interned typed key (function, mask) through `ContentNames` |
| C-64 | Specialize.cpp:52-57; Commit.cpp:103 | cpp | `llvm::zip` where lengths must agree | `zip_equal` |
| C-65 | Specialize.cpp:9-11, 51-57 | (essential, owner) | one key per function: every followed parameter exclusive; a call exclusive at some followed parameters only goes to the original | owner rc-Q2 (a mask key is finite too) |
| C-66 | Share.cpp:27-63 | rederivation / state | `shareTainted`: two whole-program walks, `DenseMap<Operation *, SmallVector<unsigned>>` keyed by function, `symbols.lookup` per call; a callee's "dups a borrowed parameter" recomputed as a scan of every dup | T5: an edge of exclusivity's graph (a dup of a view of v shares v at its consuming uses), shares made by the commit (lane 07) |
| C-67 | Share.cpp:54 | rederivation | consumption read as `useOf` (operand grade) | T7 |
| C-68 | Signatures.cpp:26-35 | list | switch over `Borrows::Param {Untracked, Borrowed, Owned}`, an enum restating the grade's `Permission` | Borrows answers a `Permission` (lane 07); `atPermission` writes it; switch deleted |
| C-69 | Signatures.cpp:22-44, 49-76 | upstream | every signature written by a program-wide loop, then every call's results reset from its callee (:71-75) | T6: each function writes its own signature and its calls' conventions in the nested pass; call results follow by the call's builder |

### 4.7 idr-demand

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-70 | Demand.cpp:41-46 | cpp | `std::get_if<idr::Same>(&source)`: a validator over `Source` | one exhaustive match (§5.5 D2) |
| C-71 | Demand.cpp:50 | rederivation | `itself` walks `definitionChain` through same-value positions per query | the value's identity through `SameValue` read once (T13) |
| C-72 | Demand.cpp:62-77 | rederivation | the promise found by walking each recycle's token back to its take and the take's value back to a parameter (0003 "a token without its cell") | T13; `!idr.token<box, @C>` (lane 01) |
| C-73 | Demand.cpp:104, 114 | cpp | the promised parameters keyed by the callee's name (`StringAttr`) | key by `FuncOp` (or by the convention in the type, T13) |
| C-74 | Demand.cpp:62-77 with Reuse.cpp:61-64, Stack.cpp:321, Reuses.cpp:158 | (owner) | the promise binds only where reuse recycled a parameter's cell: a skipped `ReuseAction`, or a parameter made frame by idr-rc-stack (then never reused), removes the promise and the refusal | owner NQ1 |
| C-75 | Demand.cpp:132-135 | (keep) | report the calls that share, else every breaking call | keep (diagnostic policy) |

### 4.8 What counting hands the lowering (lane 12's files)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-76 | lib/Conversion/Counting.cpp:91-107; lib/Conversion/Cells.cpp:109-146 | ladder (in C++) | static against dynamic uniqueness is a C++ branch on `isExclusive(type)` in two lowering patterns | T8: `idr.is_unique` with a folder; drop specialization in idr IR |
| C-77 | lib/Conversion/Counting.cpp:74-76, 108-110 | rederivation | the lowering fuses a field's dup and drop by looking for a field whose one use is an `idr.drop` | T8: drop specialization in IR drops dead fields in the unique arm |
| C-78 | lib/Conversion/Fields.cpp:21-49 | rederivation | kept fields found by walking `ResultCarriesOperand` chains back to the take, a fact placement knew | reuse specialization in IR beside drop-guided reuse (T4), lane 12 |

### 4.9 Costs counting pays in other lanes' files

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-79 | lib/Analysis/Ownership/Uses.cpp:96-104; lib/IR/Verify/Linearity.cpp:27-33 | rederivation / state | `decides(op)` re-asks the region-branch interface for every region of the op on every call (Θ(N) on an N-case match); counting asks it per user, per ancestor, per last use (§3.1) | T3 removes counting's per-query use; lane 07 (and §5.1 C4: the match answers in O(1)) for the rest |
| C-80 | lib/IR/Effects.cpp:44-90 | rederivation | `consumes` rebuilds an op's `FlowEdges` per operand asked | T6 + T7 (lane 02) |
| C-81 | lib/Analysis/Ownership/Borrows.cpp:16-19 | rederivation | borrow inference predicts idr-trmc's tail calls | T16, NQ3 (lanes 07, 10) |

### 4.10 Categories with no entry

- *per-target*: none (*measured*: `grep -in
  "triple\|aarch64\|x86\|darwin\|linux\|pagesize\|apple"` over the
  subsystem finds nothing). The stack budgets are bytes of the target's
  layout (Stack.cpp:314), which the target's entry decides.
- *idris*: the subsystem has no Idris code. Its one Idris-side input is
  the registry's `InPlaceType` hook (`compiler/src/IdrisMLIR/Registry/Entry.idr:258-260`,
  `Recognized.idr:183-186`, for `Linear.List.LList` and `Linear.Nat.LNat`),
  which becomes `SumKind::InPlace` (`include/idr/IR/IdrBase.td:123`) and
  idr-demand's promise; NQ1 bears on whether the promise should be stated
  there per parameter (lanes 14, 16).
- *attribute*: none (W-E4 above).

## 5. Target design

*Conjecture* throughout: a plan for the owner and the coordinator, not a
decision. Each change gives its representation, what it deletes, and the
one line the skill asks for.

### 5.1 The shape after the cutover

Counting becomes Perceus as MLIR passes (§5.10 R1), on the grades in
types, with one honest solver for its two markings and no per-step
reclassification:

1. **idr-rc-cells** (nested on `idr.func`): `con` with a cell to
   `cell.new` + `cell.init`; a select of references to a match (T11); the
   buffer crossings (C-16, lane 11); the static lifetime written at the op
   that makes a value (T1).
2. **idr-rc-stack** (program): the frame marking in the solver layer
   (T9). Unchanged in meaning.
3. **Borrows** (a program analysis, lane 07; rc-Q1 decides what it
   infers), then **idr-rc-grades** nested on `idr.func`: the function
   writes its own signature and its calls' conventions from the frozen
   Borrows (T6), then placement as a reverse walk (T3), drop
   specialization at the drops it placed (T3), drop-guided reuse (T4).
4. **idr-rc-specialize** (program): grade specialization from one
   exclusivity solve over potential copies (T5, T12); materialize copies,
   redirect calls; leave the solve as the cached `Exclusivity`.
5. **idr-rc-exclusive** (nested on `idr.func`): the commit, reading
   `getCachedParentAnalysis<Exclusivity>` (T5), writing the function's own
   excl grades; `idr.is_unique` folds (T8).
6. upstream `symbol-dce`; **idr-demand** (T13).

### 5.2 The changes

**T1. The static lifetime in the grade** (0003, "The static lifetime in
the grade"; lane 01 owns `Idr_Lifetime`).
- Representation: `Lifetime ∈ {Static, Heap, Frame}`, ordered, written once
  at the op that makes a value whose reach is persistent (a constant,
  poison, a small big, a global's buffer), kept by every pass, joined at
  `idr.share`.
- Deletes: `isStatic` callers here (Classes.cpp:52-61), `Class::Phantom`,
  `Class::Constant`, `Class::StaticRead` and Placement's plans for them
  (Placement.cpp:108-123), the static branch of Reuses' `reusable`
  (Reuses.cpp:160-165, lane 07).
- Line: *a value whose staticness changes when a pass rewires a chain
  (6f774119) becomes unrepresentable; the chain walk per query is deleted.*

**T2. The class is the grade.**
- Representation: once T1 holds, what `Class` says is in the type:
  untracked (the type holds no reference), view (the borrow grade), owned
  (`own`/`excl`), static (T1). The one decision left, a field read *view
  or owned at its read* (`Borrowed` against `OwnedAtRead`), is made by T3's
  walk and written as an `idr.dup` after the read.
- Deletes: `enum class Class`, `Classes`, `ownsReference`, the three
  switches over `Class` (Classes.cpp:24-37, 99-122; Placement.cpp:101-133),
  the six constructions (C-05).
- Line: *the per-step `DenseMap<Value, Class>` is deleted; every reader
  reads the type, the one per-value carrier every pass keeps (§5.8 T1).*

**T3. Placement as one reverse walk per function, with the live set as
its state** (§5.10 A1-A3, M2, R1.3; §5.9 Design 4; §5.7 M1).
- Representation: values numbered densely per function in one pre-order
  walk (§5.1 Design 3, §5.3 I7, §5.5 D3's `Id<Tag>`/`IndexVector`); one
  backward walk of the region tree carrying the set of owned values live
  after the current point (a bit vector or a sparse set). At a use that
  consumes a value still live: `dup` (late). After a value's last use, or
  at the head of a region of a deciding op for values live in a sibling
  region but not this one: `drop` (early). An op that does not decide (a
  loop) holds what its regions read. A field read whose root is live past
  the field's last use stays a view; otherwise it takes its reference at
  the read (Lean's derived borrows, §5.10 B3). Then, at each `drop` of a
  value whose constructor is known (a case region's scrutinee, a box only
  read through one constructor, a sum), drop specialization: the `take`
  (or `unpack`) that moves the live fields out (§5.10 A3), which is what
  `takeApart`, `takeReadBoxes` and `takeReadSums` do today by predicting
  the death point.
- Deletes: `Placement` (Placement.cpp:65-360), `usedIn` and the per-region
  queries, `reshape`'s `takeApart`, `takeReadBoxes`, `takeReadSums`,
  `ownFields` (Reshape.cpp:69-138, 231-284), `Take.cpp`'s
  `keepsCountedField`, the second walk of `materialize`, `gradeViews`'
  op list (C-31), the default-binding merges (C-08, with the match
  forwarding its scrutinee into the default region as a successor input,
  lane 03).
- Cost: O(ops + regions) bit-set operations per function; each region of a
  match is visited once, so no `decides`-per-query and no per-region use
  scan (the O(N²) shapes of §3.1 go).
- Line: *"where a value dies" is computed once, by the walk that places
  its drop; the three derivations of a death point (Reuses, Reshape,
  Placement) are deleted.*
- Essential, kept: `writes` (an update holds its array, Placement.cpp:152-161);
  crash-ending regions placing nothing; consumer sinking (C-37) as an
  optional action before the walk.

**T4. Drop-guided reuse after placement** (§5.10 A4, A7, M7; rc-Q3).
- Representation: a forward walk per function after T3, holding a map from
  cell size to the tokens of the takes T3 made, intersected at region
  exits; a `cell.new` of a size in the map becomes `cell.recycle` of a
  token; a token left over is dropped. Reuse specialization (unchanged
  fields not rewritten, §5.10 A7) is decided here, where the take and the
  init are both in hand, and written into the IR (today the lowering
  re-finds it, `lib/Conversion/Fields.cpp:21-49`).
- Deletes: the Reuses analysis' simulation (`Held`, `TakenField`,
  `Virtual`, `moved`, `takesAt`, `readBoxes`, `record`; Reuses.cpp:59-266,
  lane 07), `Reuses::Site`, `reuseAt` (Reuse.cpp), the dead empty-cells
  branch (C-46).
- Dependency: Borrows today reads Reuses to keep owned a parameter a reuse
  will take apart (Borrows.cpp:7-9, 43-44). Under T4 that forced reason
  becomes a syntactic fact of the body (the parameter is matched and a
  same-size cell is made after it on that path: Reuses' `fits`, kept
  alone), or goes (Koka's choice). Owner question NQ2.
- Line: *a reuse decided on a simulated body becomes unrepresentable:
  reuse rewrites drops that exist.*

**T5. Exclusivity a cached analysis, solved once; the commit a nested
pass** (0003; §5.7 L5; lane 07 owns the solve).
- Representation: the solve's graph holds, for each function some call
  could send to an exclusive copy, a second set of nodes (the potential
  copy); a call picks a version by its arguments' state as the solve
  runs; afterwards each potential copy some call chose is materialized.
  The taint of `shareTainted` (a dup of a view of `v` shares `v` at its
  consuming uses, across calls) is an edge kind of the same graph. The
  result is `Exclusivity`, an `AnalysisManager` analysis of the program,
  which idr-rc-specialize leaves preserved and idr-rc-exclusive reads
  with `getCachedParentAnalysis`.
- Deletes: the second solve (Exclusive.cpp:39-46), `createRcCommit` and
  `RcCommit` (C-03), the nested pipeline built in the pass (C-58),
  `shareTainted` as an IR rewrite before the solve (C-66).
- Line: *a solve handed from pass to pass by constructor is
  unrepresentable; the second solve is deleted.*

**T6. Conventions on the call; grading nested on functions** (C-10).
- Representation: `idr.call` carries its callee's parameter conventions
  (owned, borrowed; later excl) as an inherent property, as it already
  carries the callee's `effects` and checks them in `verifySymbolUses`
  (`lib/IR/Func/Call.cpp:52-57`). Before Borrows, every convention is
  owned (the rule Reuses assumes today, Reuses.cpp:195); idr-rc-grades
  writes Borrows' answer into the function's own signature and into each of
  its own calls. Because the callee check runs only when the program
  verifies (verifySymbolUses), a function pass may grade its signature and
  body alone, and the program is checked whole after the nested pipeline.
- One fact, one place: the property is a second copy of the callee's
  convention, legitimate only as the `effects` copy is, with one source
  (the callee's type) and a check against it in `verifySymbolUses` (§5.8
  DS2.1's "a cache with one source, checked"). The alternative keeps one
  copy: every reader asks the frozen Borrows analysis
  (`getCachedParentAnalysis`); then `consumes` needs the analysis, and no
  upstream pass reading effects sees a call's consumption. The owner
  chooses (NQ4).
- Deletes: the `parallelForEach` loops in program passes (Grades.cpp:41,
  54); the `const SymbolTable *callees` argument of `consumes` and
  0003's dual-mode `ownsParameter` (lib/IR/Effects.cpp:24-37); the
  program-wide signature writers (Signatures.cpp:22-76) as separate
  steps; cross-thread reads of siblings' signatures.
- Line: *a half-graded program between two verifier runs becomes
  unrepresentable without a program pass: each function's grades and body
  change in one nested pass; consumption is read off the call itself.*
  (Owner question NQ4: a dialect change, lane 03.)

**T7. Consumption as `Read` + `Free`, read one way** (§5.2 M2, row 2;
§5.8 EF3; lane 02 declares).
- Representation: every operand that takes over its reference declares
  `MemRead` + `MemFree` on one reference resource (one class,
  `Idr_Consumed<T>`; a call's from its conventions property, T6, by a trait
  of row 3); `dup`, `drop`, `take` on the same resource rather than the
  default one (today two resources, §3.1 R1.5 row).
- Deletes in this subsystem: the five readings of §2.6 become one query
  (`hasEffect<Free>` on the operand); `movable`'s resource comparisons
  (Reshape.cpp:291-306) become "no effect but frees of its own operands".
- Line: *two answers to "does this use consume" become unrepresentable;
  four C++ derivations are deleted.*

**T8. Uniqueness as an op that folds** (§5.10 R1.4; lanes 03, 04, 12).
- Representation: drop specialization (T3) and reuse (T4) emit
  `scf.if (idr.is_unique %x)` with the unique arm (fields move out, cell
  freed or recycled) and the shared arm (live fields dup'd, cell
  released); `idr.is_unique` reads the count resource and folds to true on
  an `excl` operand, and canonicalization deletes the shared arm.
- Deletes: the `isExclusive` branches of `LowerTake` and
  `LowerCellRecycle` (C-76), the lowering's dup/drop fusion by shape
  (C-77).
- Line: *the static and the dynamic case are one op; the branch on
  exclusivity in the lowering is deleted.*

**T9. idr-rc-stack in the solver layer** (§5.3 S1, §5.6 shape G, §5.1
Design 3).
- Representation: the frame rules' edges (unchanged, `IR/Lifetimes.h`) as
  one CSR graph built by a per-function extract (in parallel, nodes
  numbered per function with a base offset) and a serial link of `Passes`
  edges; `mark<Backward>` from escapes and heap fills, `mark<Forward>` from
  framed cells; the header states what upstream lacks (a scope between
  function and module; state per value, §5.1 A4, A6) and the size (8 bytes
  per edge, one bit per node per marking).
- Deletes: `Inference`'s `DenseMap<Value, unsigned>` and per-node vectors
  (C-50), the `bool backward` flag (C-51), the statistic walk (C-53),
  `placeable`'s `isa<FuncOp>` (C-49).
- Line: *a per-value hash entry and a per-node heap vector become a slot in
  two arrays; the frame scope is said once (`AutomaticAllocationScope`).*

**T10. One slot query** (C-55).
- Representation: one function beside `forwardedValues`
  (`include/idr/IR/Flow.h:42-43`) that gives each operand with the type of
  the slot it moves into: a call's arguments against its callee's
  parameters (`CallOpInterface`), a return against its function's results
  (`ReturnLike`), a region branch's forwarded values, a select's choices.
- Deletes: the two hand lists (Stack.cpp:358-376, Commit.cpp:101-117).
- Line: *the case dispatch over `CallOp`/`ReturnOp`/`SelectOp` is deleted
  into interfaces read once.*

**T11. No select of references reaches counting** (C-33).
- Representation: idr-rc-cells turns `arith.select` of references into the
  match Reshape builds today (Reshape.cpp:34-56); the owned stage's
  verifier may state it.
- Deletes: Stack's select meeting (Stack.cpp:371-375), `rewriteSelects`.
- Line: *a reference chosen by a non-region op in counting's input becomes
  unrepresentable.*

**T12. Grade specialization keys interned** (C-63, C-65).
- Representation: key = (function, mask of exclusive followed parameters),
  interned by `ContentNames` (`include/idr/IR/Symbols.h:283-293`). Today's
  rule is the all-ones mask; a finer mask is the owner's (rc-Q2), still
  finite, so no budget.
- Deletes: `copyName`'s string and the hand collision check.
- Line: *a name that stands for a key is a typed key; the second
  name-collision check is deleted.*

**T13. The in-place promise where it is made** (C-70 to C-74; owner NQ1).
- Today the promise is read off reuse's output (Demand.cpp:62-77), so an
  optimization's choice decides whether a program is refused. If the owner
  wants the promise to be the program's: the frontend's in_place type plus
  the function's own match on a quantity-1 parameter of it, decided before
  counting and written as a convention of the parameter (T6's property and
  the function type); idr-demand checks every call passes it exclusive;
  idr-rc-stack never frames such a parameter and T4 always recycles it.
- Deletes: the token walk (C-72), `itself` (C-71), the name-keyed map
  (C-73).
- Line: *a refusal that depends on whether an optimization fired becomes
  unrepresentable* (if NQ1 says so; otherwise the essential rule stays and
  only C-70 to C-73 change).

**T14. Pass facts in ODS** (C-01, C-03, C-09). The commit and
idr-rc-specialize declared in `Passes.td`; `GEN_PASS_DECL_IDRRCPLACE`
deleted; the budgets named once. *Line: a pass whose facts ODS does not
hold is deleted.*

**T15. Knots with the type graph** (C-02). *Line: no state or branch
changes; the pass moves to the area whose analysis (`TypeGraph`) it reads,
so counting's header declares only counting.*

**T16. Counting and TRMC** (§5.10 M10; lane 10). Borrows predicts what
idr-trmc will make a tail call (Borrows.cpp:16-19). If TRMC ran before
counting (Koka's order), the prediction goes; counting must then place
around `dest.write` and holes (frames already makes some, Passes.td:430-449).
Owner question NQ3. *Line: a second derivation of TRMC's decision inside
borrow inference is deleted, if the order changes.*

### 5.3 Order inside the subsystem, and dependencies

1. T1 (needs lane 01's `Idr_Lifetime`), T11, T15, T14 (no dependency).
2. T7 and T6 (lanes 02, 03: the reference resource, the call's property).
3. T2 + T3 together (needs T1, T6, T7; the dense numbering of the solver
   layer, lane 05).
4. T4 (needs T3; lane 07 deletes Reuses' simulation; NQ2 decides Borrows'
   forced reason).
5. T8 (needs T3, T4; lanes 03, 04, 12).
6. T9, T10 (solver layer, lane 05; independent of 3-5).
7. T5, T12 (lane 07's solve; after T6 so the commit is nested).
8. T13 after NQ1; T16 after NQ3.

Each step is one hard cutover of its files; the counts of the suites'
statistics (`numDups`, `numDrops`, `numReuses`, `numExclusive`) are the
before-and-after measure (§8).

## 6. Evidence for the owner's questions

No answers: what our code says, by ID.

**rc-Q1 (borrow inference).**
- We infer borrows, over the whole program at once, on `DataFlowSolver`
  (`lib/Analysis/Ownership/Borrows.cpp:29-41`): every parameter starts
  borrowed and becomes owned for named reasons (taken apart by a reuse;
  passed to an owned parameter; stored in a constructor or a buffer;
  returned or forwarded; an owned value passed by a tail call within a
  cycle; a self call that TRMC will make a tail call) (`:7-21`). The
  program's root and every quantity-1 parameter are owned (`:22-25`).
  This is Lean's design (§5.10 B2) with Lean's forced reasons, but not
  per SCC, and with no frame-limited restriction: nothing checks that the
  caller uses the argument later or that it has constant size.
- Counting depends on it in three places: the signatures (Signatures.cpp:22-44),
  the class of a parameter (Classes.cpp:77-84), and the taint of
  exclusivity: a callee that dups a parameter it borrows makes every
  caller's value shared at its consuming use (Share.cpp:21-47), so a
  borrowed parameter can cost a caller its exclusivity, which an owned one
  that moves would not.
- Borrow decisions come after reuse decisions and read them
  (Borrows.cpp:43-44, Grades.cpp:45-47).

**rc-Q2 (how much exclusivity is static; run-time test as fallback).**
- R1 and R2 are both built. One solve marks exclusivity (lane 07); its
  answer is written into types (Signatures.cpp:49-76, Commit.cpp:84-98).
  Grade specialization is in counting, after placement, not in
  idr-optimize (Specialize.cpp): one copy per function, key "every
  followed parameter exclusive" (`:9-11`), keys closed over a copy's
  callees and over calls a key's result feeds (`:107-117`), no budget
  (at most one copy per function, so at most twice the functions that
  take a followed parameter shared). A call exclusive at some followed
  parameters but not all goes to the original (`givesExclusive`,
  `:52-57`).
- The run-time fallback exists: a take of a value not proven exclusive
  tests the count (`lib/Conversion/Counting.cpp:93-107`); a recycle of a
  token not proven exclusive tests for null (`lib/Conversion/Cells.cpp:128-140`).
- One place allows no fallback: a type that promises in place
  (`SumKind::InPlace`) must be passed exclusive where its cell is
  recycled, or the program is refused (`Demand.cpp:99-137`,
  `Rule::Uniqueness`, an `OutsideLanguage` category, `IdrBase.td:226`).

**rc-Q3 (a space guarantee).**
- Placement's rules are Perceus's (drops right after the last use on each
  path, Placement.cpp:233; on entry to a region that does not use the
  value, :201-202; at the definition of an unused value, :186-189; dups
  only before consuming uses, :218-226). No proof or test says the result
  is garbage-free.
- Borrowing is unrestricted (rc-Q1), which the frame-limited result says
  can hold memory no constant bounds (§5.10 A5).
- Reuse takes at the predicted death point and holds the emptied cell (a
  constant size) to the first same-size `cell.new` on the path, across
  calls (Reuses.cpp:208-227).
- The tests check soundness only: every cell freed by the end
  (`tests/rc-live/rc-live.mlir:7-16`, `%differential`'s live cells), and
  that every cell is reused where expected (`tests/expect-reuses-every-cell`);
  none states garbage-freedom or a frame bound (*measured*: `ls tests |
  grep -i "rc-\|reuse\|stack"` and the files read).

**rc-Q4 (threads and shards).** No counted cell is treated as shared
between threads anywhere in the subsystem; it has no mark-shared step. The
runtime's count is a plain saturating `uint32_t` with no atomics in
`runtime/Rc/` (`runtime/Rc/Counting.cpp:3-5, 43-52`; *measured* grep
above); `unique` is count 1 and not a stack cell (`:55-60`). Threads in
counting are the compiler's own (`parallelForEach`, Grades.cpp:41, 54).

**rc-Q5 (drops at last use, everywhere).** That is the rule today, with
four exceptions, each in the code: an op that does not decide (a loop)
holds a value from outside for as long as it runs (Placement.cpp:209-217);
a region that ends in a crash places nothing (Placement.cpp:201,
Reshape.cpp:83, 97, 104, 280); a borrowed argument lives in the caller
across the call (rc-Q1); and where a drop after a call would break a tail
call within a cycle, Borrows makes the parameter owned so the callee drops
it (Borrows.cpp:14-16). Nothing is lexical; Idris has no destructor to
order.

**QL2 (SSI for ownership).**
- For: every ownership change already defines a value (`borrow`, `dup`,
  `share`, `take`, `unpack`, `lin.enter`, `lin.use`, `own.adopt`,
  `own.give`, `include/idr/IR/IdrOwnershipOps.td:62-424`); a case region
  binds its fields as arguments, which `takeAtEntry` replaces by a take's
  results (Take.cpp:44-56); no step of counting keeps a per-point fact
  (§3.1).
- Against, or not yet: counting *undoes* one binding, the default region's
  rebinding of the scrutinee, because it places "the same value as one"
  (Placement.cpp:364-375, Reshape.cpp:101-105, kept by c4d38e9b for
  nat-parity); "is this value alive at that op" is answered by walking
  uses (`usedAfter`, `lib/Analysis/Ownership/Uses.cpp:106-129`), a per-point
  question SSI with region-scoped borrows would make structural; a borrow
  has no scope of its own (`idr.borrow` per read, Placement.cpp:290-303).
- The frame lifetime is per value, in types (Stack.cpp:344-353), which is
  the SSI form.

**Related questions this code bears on.**
- *DD-Q1 (normalize `!idr.lin<i64>`)*: counting never places a value whose
  type holds no reference (Classes.cpp:45); a linear word reaches no step
  of counting.
- *DD-Q6 (borrows as regions)*: borrows are unscoped views made per read
  (Placement.cpp:254-256, 290-303); their lifetime is their owner's, which
  placement guarantees by never dropping the owner before the view's last
  use (`aliveAt`, Classes.cpp:99-122).
- *Q-O1 (structured match after defunctionalization)*: every counting step
  reads region structure (Q-W4 above).
- *Q-E2 / Q-O3 (facts into types)*: counting writes all its answers into
  types and ops (W-E4 above) but carries two between passes outside the IR:
  `Exclusivity` by constructor (C-03) and `Reuses` through the analysis
  manager (Grades.cpp:45).
- *Q-llvm-2, Q-E3, oom-2 (budgets)*: the stack budgets are bytes of the
  target's layout and only leave cells on the heap (Stack.cpp:78-80,
  315-318); idr-demand's refusal rests on the exclusivity solve and on
  placement, neither budgeted.

### 6.1 New questions for the owner

- **NQ1. Is the in-place promise a property of the program or of the
  optimizer's output?** idr-demand binds the promise only where an
  `idr.cell.recycle` takes its token from a take of the parameter
  (Demand.cpp:59-77; `include/idr/Transforms/Passes.td:616-621`). So skipping one `ReuseAction`
  (Reuse.cpp:25-28, 61-64, an MLIR action, skippable by a debug counter),
  or idr-rc-stack making the parameter frame (it writes parameters of the
  frame, Stack.cpp:344-353, and Reuses never reuses a frame box,
  Reuses.cpp:158), removes the promise and with it the refusal, and also
  the in-place rebuild for every caller. Likewise `sinkConsumers`
  (Reshape.cpp:149-210), an unwrapped optimization, decides whether a dup
  appears, hence exclusivity, hence the verdict. AGENTS.md says acceptance
  is a property of the program, never of the optimizer, and an
  optimization role says skipping it changes nothing but stack and heap
  (`include/idr/Transforms/Passes.td:24-27`); skipping idr-rc-stack (an
  optimization) could, by the same chain, *add* a reuse and so a refusal.
  Should the promise be stated where it is made (the
  in_place type plus the function's own rebuild of a quantity-1
  parameter, before counting), with stack and reuse bound to honour it
  (T13)? (*Read* chain; no program was run to show it.)
- **NQ2. Reuse before or after borrow inference?** Today reuse is decided
  first and borrow inference keeps a reused parameter owned (Lean's order,
  Borrows.cpp:7-9). Drop-guided reuse after placement (Koka's order, T4)
  deletes the simulation but needs the forced-owned reason from somewhere
  else (a syntactic check, or none). Bears on rc-Q1 and rc-Q3.
- **NQ3. Counting before or after TRMC?** Borrows predicts idr-trmc's tail
  calls today (Borrows.cpp:16-19); Koka runs TRMC first (§5.10 M10).
- **NQ4. Conventions on the call?** `idr.call` already copies its callee's
  `effects` and verifies them in `verifySymbolUses`
  (`lib/IR/Func/Call.cpp:52-57`). Should it carry its callee's parameter
  conventions the same way (T6), so consumption is read off the call and
  grading can run nested on functions? Bears on DD-Q7.

## 7. Deletion list

By file and symbol, under §5's changes (T-number in brackets). Lane
coordination where the symbol is not this lane's.

- `include/idr/Transforms/Ownership.h`: `GEN_PASS_DECL_IDRRCPLACE` (now);
  `GEN_PASS_DECL_IDRKNOTS` moves (T15); `createRcCommit` (T5); `enum class
  Class`, `ownsReference`, `class Classes` (T1, T2); `usedIn` (T3);
  `rebindDefaults` (T3, with lane 03's forwarding of the default binding);
  `reuseAt` (T4); `keepsCountedField` (T3); `writeOwnedGrades`,
  `writeExclusiveGrades` as program-wide steps (T6); `shareTainted` (T5,
  lane 07); the `(Block &, Block::iterator)` overloads of `takeAt` in
  favour of `Point` (C-07).
- `lib/Transforms/Ownership/Classes.cpp`: the whole file (T1, T2, T3);
  `endsInCrash` moves to the terminator's declared kind (C-06).
- `lib/Transforms/Ownership/Placement.cpp`: `Placement` (`run`, `plan`,
  `usesBy`, `takes`, `at`, `incBeforeOp`, `placeOwned`, `placeBorrowed`,
  `viewOf`, `materialize`, `gradeViews`), the terminator `assert`,
  `rebindDefaults`; replaced by the reverse walk (T3). `writes` survives
  into the walk.
- `lib/Transforms/Ownership/Reshape.cpp`: `rewriteSelects` (moves to
  idr-rc-cells, T11), `takeApart`, `takeReadSums`, `takeReadBoxes`,
  `ownFields` (T3), `movable`'s resource comparisons (T7); `sinkConsumers`
  and `feeders` stay as one optional action (C-37).
- `lib/Transforms/Ownership/Take.cpp`: `keepsCountedField` (T3);
  `takeFields`' `dyn_cast<FieldOp>` (C-44).
- `lib/Transforms/Ownership/Reuse.cpp`: the whole file (T4); with it the
  dead `site.cells.empty()` branch (C-46).
- `lib/Analysis/Ownership/Reuses.cpp` (lane 07): `Held`, `TakenField`,
  `Virtual`, `moved`, `takesAt`, `virtuals`, `readBoxes`, `considerTake`,
  `record`, `Reuses::Site` (T4).
- `lib/Transforms/Ownership/Commit.cpp`: `RcCommit`, `createRcCommit`
  (T5), the position list in `commit` (T10), the idle-share loop (C-61,
  a folder), `!isa<CallOp>` (C-59).
- `lib/Transforms/Ownership/Exclusive.cpp`: the second
  `Exclusivity::solve`, `redirectCalls`' separate pass over a second solve,
  the nested `OpPassManager` (T5).
- `lib/Transforms/Ownership/Specialize.cpp`: `copyName`, the
  `symbols.lookup(name)` collision check (T12).
- `lib/Transforms/Ownership/Share.cpp`: the whole file as an IR pre-pass
  (T5; the taint becomes a graph edge, lane 07).
- `lib/Transforms/Ownership/Signatures.cpp`: the switch over
  `Borrows::Param` (C-68; `Borrows::Param` itself, lane 07); the
  program-wide loops (T6).
- `lib/Transforms/Ownership/Grades.cpp`: both `parallelForEach` loops
  (T6); the pass becomes nested on `idr.func`.
- `lib/Transforms/Ownership/Buffers.cpp`: the `dyn_cast` ladder on memref
  ops (C-16, with lanes 11 and 03).
- `lib/Transforms/Stack/Stack.cpp`: `Inference`'s storage (`ids`,
  `byNode`, `out`, `in`) and `mark` (T9), `placeable`'s `isa<FuncOp>`
  (C-49), the `numBoxes` walk (C-53), the `arith::SelectOp` meeting (T11),
  the meeting list (T10).
- `lib/Transforms/Demand/Demand.cpp`: `handedOn`'s `get_if` (C-70),
  `itself` (C-71), `rebuilt`'s token walk (C-72), the `StringAttr`-keyed
  map (C-73); the whole definition of the promise if NQ1 moves it (T13).
- `include/idr/Transforms/Passes.td`: the budget numbers in idr-rc-stack's
  description (C-09).
- `lib/IR/Effects.cpp` (lane 02): `ownsParameter`'s `callees` mode and
  `consumes`' `SymbolTable *` argument (T6).
- `lib/Conversion/Counting.cpp`, `Cells.cpp`, `Fields.cpp` (lane 12): the
  `isExclusive` branches (T8), the dup/drop fusion by shape (C-77), the
  kept-field re-derivation (C-78).
- Tests that check a deleted state (lane 19 judges): fixtures that spell
  `Class`-specific placements of static data, and any test of the
  `idr-rc-commit` pass name outside `Passes.td` (*conjecture*; not
  inventoried here).

## 8. Risks, unknowns, measurements needed

**The biggest risk.** T3 replaces a placement whose rules were fixed by
many bug hunts (4108916a, 4603d0cb, 6f774119, 8835e5df, 503ed5e7,
3d279eb9 in `git log`) with Perceus's reverse walk. Perceus is proved
garbage-free, so the counts should be equal or fewer; but our placement
carries rules Perceus does not state (an update holds its array,
Placement.cpp:148-161; static data; memo cells never taken apart,
Reshape.cpp:58-61; buffer crossings; a force's captures, 6f774119), and a
mismatch is a leak or a double release found only by running. The gate is
the suites' own statistics and the live-cells differential
(`tests/rc-live`), compared before and after, per test.

**Other risks.**
- NQ1: if the promise moves to the source (T13), programs accepted today
  may be refused (a call that shares where no reuse fired) and vice versa;
  the suites' uniqueness tests (`tests/uniqueness-shared-rebuild`) decide.
- T4 changes which cells are reused (after borrows, by drops that exist):
  `tests/expect-reuses-every-cell`, `rc-nested-reuse`, `rc-reuse-read-field`
  are the measure; frame-limitedness is what the owner may want stated
  (rc-Q3).
- T6 needs the call's convention property (a dialect change, lanes 03, 14:
  the Idris mirror regenerates) and relies on `verifySymbolUses` running
  only at the program; if any verifier on a function reads a callee's
  signature, the nested form fails until it moves.
- T5's single solve over potential copies doubles the graph's
  copyable part; lane 07 must show it stays linear.
- The quadratic shapes of §3.1 (`decides`, `usedIn`, per-block `Classes`)
  are *conjecture* from the code; they may already bite on stage 1.

**Measurements needed** (none can run in this checkout: no compiler is
built; each command is for the build machine).
- Per idr-rc step, time and peak footprint on the stage-1 module:
  `idris-mlir-opt <stage1>.mlir --idr-target --idr-pipeline
  --mlir-timing --mlir-pass-statistics` with the footprint record oom-3
  proposes.
- The case-count distribution of matches and, for the largest, the number
  of values used in more than one case (the O(N²) placement and `decides`
  risk).
- How often `decides` is asked per pass, and `Classes` constructed per
  function (a counter, or a Tracy plot per call site).
- Stack inference's node and edge counts and the share of nodes no
  candidate reaches (W-E2).
- Grade specialization's copy count and the code-size growth it causes
  (rc-Q2).
- The suites' `numDups`, `numDrops`, `numTakes`, `numReuses`,
  `numExclusive`, `numStackCells` now, as T3, T4, T5 baselines.
- Whether any refusal of `Rule::Uniqueness` in the suites changes when
  `idr-reuse-site` or `idr-stack-cell` actions are skipped
  (`-mlir-debug-counter=idr-reuse-site-skip=...`): the test of NQ1's
  chain.

**Unknowns.**
- Whether Perceus's reverse walk over regions keeps the self tail calls
  that Placement keeps by construction (Placement.cpp:32-34); Borrows'
  tail reasons may need to move into the walk.
- Whether the default region's binding can be a forwarded successor input
  in the match's `RegionBranchOpInterface` today (lane 03), which C-08's
  deletion needs.
- How Lean-style borrows (rc-Q1) and drop-guided reuse (NQ2) interact on
  the suites: no measurement.

## 9. Sources read

**Instructions and rules, in full:** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `audits/p0/README.md`.

**Proposals, in full:** `proposals/0000-mlir-native.md` (lines 1-11,141,
read in chunks: §0-§4, §5.1-§5.11 with every lane's findings, designs,
questions and notes, §6-§9); `proposals/0003-facts-once.md`.

**The subsystem, line by line:**
`foreign/idr/include/idr/Transforms/{Ownership,Stack,Demand,Pipeline}.h`;
`foreign/idr/include/idr/Transforms/Passes.td` (1-75, 186-205, 480-627)
and `InnerPasses.td`;
`foreign/idr/lib/Transforms/Ownership/{Buffers,Cells,Classes,Commit,Exclusive,Grades,Knots,Placement,Reshape,Reuse,Share,Signatures,Specialize,Take}.cpp`;
`foreign/idr/lib/Transforms/Stack/Stack.cpp`;
`foreign/idr/lib/Transforms/Demand/Demand.cpp`;
`foreign/idr/lib/Transforms/Pipeline.cpp` (25-60, 120-135).

**What it hands the lowering (lane 12's), read for that only:**
`foreign/idr/lib/Conversion/Counting.cpp` (whole), `Cells.cpp` (60-160),
`Fields.cpp` (1-60).

**What it calls, read for the interfaces it uses (other lanes'):**
`foreign/idr/include/idr/Analysis/Ownership.h` (whole);
`foreign/idr/lib/Analysis/Ownership/Reuses.cpp` (whole), `Uses.cpp`
(whole), `Borrows.cpp` (1-80);
`foreign/idr/include/idr/IR/{Ownership,Lifetimes,Flow}.h` (whole),
`Grades.h` (declarations), `Symbols.h` (265-300);
`foreign/idr/lib/IR/Effects.cpp` (20-126); `lib/IR/Func/Call.cpp` (20-80);
`lib/IR/Verify/Linearity.cpp` (15-60), `lib/IR/Verify/Uses.cpp` (20-40);
`foreign/idr/include/idr/IR/IdrOwnershipOps.td` (ops and effects, 33-424,
by grep; 98-136 in full); `include/idr/IR/IdrBase.td:123, 226`;
`include/idr/Support/Actions.h` (1-40).

**Runtime, for rc-Q4 and W6 only:** `runtime/Rc/Counting.cpp` (1-80);
`grep -rln atomic runtime`.

**Idris side, for the in-place hook only:**
`compiler/src/IdrisMLIR/Registry/Entry.idr` (258-260, 343, 362, 409),
`Registry/Recognized.idr` (183-186), `Term.idr` (100-126),
`Frontend/Translate/Types.idr:814` (by grep).

**Tests, for rc-Q3 only:** `tests/rc-live/rc-live.mlir` (1-30); the list
of `tests/` directories naming idr-rc or idr-demand (*measured*: 73).

**History:** `git log --oneline` of the subsystem's paths (25 commits);
`git show` of b8301ebe (message and the Stack.cpp diff), ffa91113, 4c87dcc5,
a7bf77b4, 3d279eb9, 8835e5df, 503ed5e7, da66bd95, c4d38e9b, 651164af,
6f774119, 4603d0cb (messages and stats).

**Other wave-2 documents:** `audits/p0/07-ownership-analysis.md` (its
layout and progress, to avoid duplicating lane 07's scope).
