<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane `defunc`: the label solve, defunctionalization, deduplication, the effects pass

Lane 06 of wave 2 (audits/p0/README.md). Scope: `foreign/idr/lib/Analysis/Labels.cpp`,
`LabelSites.cpp`, `include/idr/Analysis/Labels.h`, `lib/Transforms/Defunctionalize/`,
`lib/Transforms/Deduplicate/`, `lib/Transforms/Effects/` (`Effects.cpp`,
`Constants.cpp`), their headers, and what they read of `lib/IR/TypeGraph.cpp`
and `lib/IR/DataRemap.cpp` (owned by lanes 01 and 03).

Marks: *read* (path:line, commit, proposal section), *measured* (count with its
command), *recalled*, *conjecture*. Paths below are relative to the repository;
`idr/` abbreviates `foreign/idr/`.

## 1. Reading notes

Written while reading, in the proposal's order. Each note: the ID, what it
says (*read* from the proposal), and the bearing on this lane.

**§2, §3 (brief, walls).**
- §2 pipeline: deduplicate is the *first* pass, defunctionalize the second
  ("every closure becomes a constructor of a closed sum; everything after is
  first-order"), effects the fourth (after knots). Labels and LabelSites are
  named "the defunctionalization label solve"; `Transforms/Effects/Constants`
  is listed among the users of upstream's dataflow framework.
- §3 row 73bba53f: `idr-defunctionalize` 843 s, "the table of data types
  rebuilt per declaration". A wall of this lane's, fixed by a representation;
  the fix must survive the cutover (check how it is held today, §2/§4).

**§5.1 mlir-analysis.**
- A4/A6/B7-style costs: a `DataFlowSolver` state is ~2.9 KB fixed; per-value
  dense numbering is 0.13 B/bit. Bears on `Transforms/Effects/Constants.cpp`
  (a dataflow user in this lane): per-function or whole-program?
- 5.1.2 item 3: "the defunctionalization label solve (a whole-program closure
  set, before which nothing is first-order)" stays ours, honestly, in the
  solver layer, with a header naming what upstream lacks.
- 5.1.2 item 4 / patch 29: "a non-call symbol use (a closure's label) as an
  unknown caller" — closure labels are symbol uses; after defunctionalization
  no closure label survives, so this only matters before it (dedup runs
  before defunc: check how dedup treats a closure's symbol use).
- 5.1.2 item 7, F1: whole-program facts in a module-level analysis read by
  nested passes through `getCachedParentAnalysis`; no attribute or type
  created on a solver's hot path (F3) — bears on defunc's type rebuilding.
- Design 3 / QA4: one solver layer with dense numbering, CSR graph, concepts.
  W2 (lattice of every analysis; Design 1 or 3), W5 (attributes/types made on
  a hot path), W6 (function anchoring), W7 (backward callee resolution).
- E1/E2: `CallGraph` ~150-700 B per function; `SymbolTableCollection`
  ~2 MB at 70k symbols; `SymbolUserMap` ~40 MB (64-bucket `SetVector` per
  symbol). Bears on dedup (redirects calls) and defunc (label → function).

**§5.2 mlir-ods.**
- A5: an op's effects are all-ODS or all-hand; `RecursiveMemoryEffects` the one
  sanctioned dynamic form. A9: the transform dialect's `InferEffects` pass
  infers a per-argument summary and stores it on function arguments; its call
  op's hand `getEffects` looks the callee up (linear scan, a wall at 70k).
  Directly the shape of our effects pass if it summarises functions: check
  where the summary lives (attribute? analysis?) and who reads it.
- D2/D3/M10: a mutable type's body is read without a lock; a growing table in
  an immutable attribute is quadratic (73bba53f's shape). Bears on how defunc
  extends `#idr.types` with closure sums.
- Rows 1-4 (effects), row 23 (families from lists), H5 (symbol checks in
  `verifySymbolUses`, not `verify()`).
- Owner Qs (5.2.4): Q1 divergence/crash deletable when dead, Q2 effects from
  types, Q3 resource tree, Q5 stages. W1 (hand `getEffects`), W3, W9 (passes
  that change nothing mark analyses preserved).

**§5.3 llvm.**
- B7/I7: per-node `DenseMap` is ≥64 buckets; dense numbering is LLVM's move.
- B8/M4: "Our graphs (exclusivity's graph, `idr-rc-stack`'s flow graph, the
  label solve's graph) get them by specializing `GraphTraits` once";
  `lib/Support/Scc.cpp` is a hand-rolled `scc_iterator`.
- C2 SCCP: no stored dependents, users from use lists — the scaling shape.
- S0: "before S1 is given an analysis, wave 2 asks of it: could the dialect
  carry this answer (a type, a token, an op) so that no pass solves for it?"
  Applies to the label solve (could the frontend's types already carry the
  closure set?) and to the effects pass (could the world token / ODS effects
  carry it?).
- S1: `idr::solve` Graph/Lattice/Analysis/Solution, `mark` for two-point
  lattices; SCC schedule; one instantiation per analysis.
- I3 (`get_if` chains → one match), I5 (hot callbacks → templates), I6
  (worklists → schedules), I8 (lists mirroring records generated).
- lane-note to mlton: lld ICF is an optimistic partition refinement for
  deduplicating functions, parallel by double-buffering class ids.
- Wave-2 Qs (5.3.4): every worklist, DenseMap per node, function_ref,
  variant; "Exclusivity's graph, `idr-rc-stack`'s flow graph and the label
  solve's graph: their node and edge representations, and whether one CSR
  `Graph` type with `GraphTraits` serves all three."

**§5.4 modular.**
- F3: `CallGraphUtils.h`/`SCCUtils.h` CRTP schedule (callees first,
  fork-join on leaf SCCs); F4: `EliminateDuplicateFunctions` original — hash =
  attributes but name + `OperationEquivalence::computeHash` per body op,
  equality `isRegionEquivalentTo`, callees before callers by AsyncRT chains,
  cycles skipped, one mutex around the set, calls redirected to the class's
  lexicographically smallest symbol, duplicates left for DCE.
- 5.4.2 item 3: "Our port replaced AsyncRT's per-node chains by waves by
  height with a barrier per wave"; with an `SCCGraph` on MLIR's pool "the port
  becomes one more client and the waves go".
- Design 1 (one call-graph schedule, both directions) deletes "the
  deduplicator's waves". Q-M1 (spine), Q-M4 (porting more of Modular).
- Wave-2 Qs: which analyses are call-graph summaries (`Effects`, `LabelSites`,
  the deduplicator listed); "The deduplicator's waves: idle time per wave";
  hand `getEffects` that exist because an attribute changes meaning.
- lane note to mlton: Mojo closures are struct types specialized per closure,
  no defunctionalization; Mojo dedups after elaboration.

**§5.5 cxx26.**
- D1: dispatch once where the set is open (ops: interfaces/traits), monomorphic
  below; D2: `std::variant` + one exhaustive `match`, `get_if`/
  `holds_alternative` banned outside it; D3: solver state as `IndexVector`
  keyed by a graph-minted `Id`, transfer as template parameter, `extern
  template`; D4: one list in one place (TableGen or a consteval-checked table).
- Wave-2 Qs: every variant's alternative count and use form; every
  function_ref; hand lists restating ODS.

**§5.6 ecosystem.**
- A4/H3/5.6.2 item 2: CIRCT's `InstanceGraph` is a maintained call graph in
  the `AnalysisManager`; "Our pipeline changes calls in defunctionalize,
  contify, optimize ... and symbol DCE; §2 lists ... `LabelSites` ... each of
  which may derive call-graph facts on its own."
- H5: CIRCT Dedup hashes modules in `failableParallelForEach`, "each module's
  SHA-256 computed alone and references to other modules combined later" —
  the alternative to callee-first waves: hash bodies independently, resolve
  cross-references after (Q-E4 proposes porting it).
- 5.6.2 item 3: summaries in a typed table, never in attributes (Enzyme and
  Triton put them in discardable attributes; AGENTS.md forbids it). W-E4.
- 5.6.2 item 6 / Design 1 shape G: "the defunctionalization label solve ...
  fit[s] this form": extract, solve on plain arrays, write back.
- Design 1 `ProgramGraph`: maintained by defunctionalize (it adds apply
  dispatch functions and calls), contify, inline, specialize, symbol DCE.
- Q-E2 (where a summary lives: analysis or IR — the effects pass's summary is
  the case), Q-E4 (porting CIRCT/IREE, Dedup's hashing).
- W-E1 (call-graph/SCC derivations: `LabelSites` named), W-E4 (facts in
  discardable attributes), W-E5 (budgets), W-E6 (queries that walk a match's
  regions: `RecursiveMemoryEffects`), W-E7 (`DenseMap<Value,...>` solver
  state), W-E8 (IR after defunc single-block regions?), W-E9 (state copied
  per edge).

**§5.7 library.**
- B3: "every interprocedural fact (who calls whom, which closures flow where,
  what a callee does to its arguments) lies outside the IR's use lists by
  design" — the label solve and the effects pass are exactly two of these.
- B4: Bhat-Grosser λrc regions may not escape: "the representation, not an
  analysis, bounds the flow".
- M6/L3: the context-lock wall and 73bba53f are "a mutable, nominal type read
  while it may change"; L3 build-then-freeze interned program tables,
  "Costs: a rebuild when defunctionalization or specialization adds types".
- M7: the reference graph = calls plus closure and constant references.
- L4: "The label (closure) flow, the reference graph and effect propagation
  are relations ... union-find canonicalization for analyses whose
  constraints are equalities (labels flowing through constructor fields
  unify; Steensgaard over Andersen)". "Lost precision makes a closure sum
  larger, never unbounded, so it changes code quality, not acceptance."
  "Deletes (conjecture): bespoke worklists in the label solve and in
  effects. MLton's 0CFA is the serial precedent."
- L5 clones as keys; QL3 rules vs transfer functions.
- Wave-2: per analysis, PLV / independent / relational; forward/backward.

**§5.8 dialect-design.**
- DS4 row `closure`, `apply`: "legal only before defunctionalization
  (`ConversionTarget`)" (O4) — "flags or checks for 'after defunc'" deleted.
- DS4 rows `delay`, `suspend`, `force`, `memo.run`, `MemoState` → a `lazy.`
  family; `con`, `field`, `tag` → `data.*`, constructor and field as indices.
- DS4 `func`, `call`, `return` → `func.*` unless `!idr.fn` carries conventions
  and effects (T6); DS2.1: a call carries the callee's effect set as an
  inherent property verified in `verifySymbolUses`, or effects are a cached
  analysis — the effects pass's target either way.
- T6: "A call's effects are then read off the callee's type, once, instead of
  being re-inferred (§2's `Analysis/Effects`)"; B9: a direct call's callee is
  a sibling symbol a parallel function pass may not read.
- DS3: data types as an immutable table on `program` "adding a type rebuilds
  the table (73bba53f's cost) unless the frontend emits it whole" — defunc
  is the pass that adds types (closure sums).
- EF1/DD-Q2: divergence as effect or speculation; EF2 resource tree.
- DD-Q3 (world), DD-Q7 (own function op with effects in its type).

**§5.9 mlton (read most carefully).**
- B3/B4: one constraint-generating abstract interpreter, each reachable block
  visited once; cells are union-find nodes with handler lists; a set cell
  sends only differences; no worklist over program points, no round count.
- B5: abstract values are type-shaped; "a first-order type (no arrow inside)
  maps to a **single shared** abstract value for the whole program"; facts
  about constructor fields live once per constructor. State sized by types
  and constructors.
- D2: 0CFA "as **one traversal** of SXML that emits constraints"; an
  application installs a handler on the function's lambda set; a constructor
  application coerces into the constructor's one abstract value; lambda sets
  hash-consed (`UniqueSet`), set equality pointer equality; `send` pushes only
  the difference; mutable containers unified, not coerced.
- D3: "Closure sets become sums **per distinct set**, not per function type":
  one SSA datatype per hash-consed set, one constructor per lambda carrying
  its environment tuple, memoized on the set; where a smaller set flows into a
  larger one a `case` re-tags (`coerce`); an application is a `case` over the
  set's constructors calling each lambda's function. Free variables by a
  separate linear pass.
- D4: closure conversion's output is shrunk per function; the converter
  relies on the shrinker as its normal form.
- F5: polyvariance duplicates a let-bound higher-order function per reference
  under `(n-1)*(size-small) <= product` *before* the flow analysis, so 0CFA
  sees separate copies.
- H table, 73bba53f: "new datatypes are pushed to a list and emitted once
  (`newDatatypes`, `closure-convert.fun:472, 532`) ... per-set info memoized on
  the set's plist".
- I1 (Danvy-Nielsen: one apply per type, or grouped; MLton's is the finest
  grouping, one per flow set), I2 (Futhark: restrict until every application
  is statically known; no sum at all), I3 (Kovács: closure-freedom by type).
- M4: "If our sum is one per function type (or per label class) rather than
  one per distinct flow set, every `apply` dispatches over every closure of
  that type" — Q-W1 asks which. M9: we specialize after defunctionalization,
  "when the label solve has already merged every call site's closures" —
  Q-W5, Q-O4.
- Design 1: the solver layer as a constraint-generating interpreter with
  cells; "`Labels`/`LabelSites` (the defunctionalization label solve is D2's
  0CFA, a set domain)" and `Effects` are listed as deletable into it.
- Design 3: "the label solve's answer is the closure sums (one per flow set,
  D3, with re-tagging coercions where sets meet)"; per-pass facts never a side
  table.
- Design 7: polyvariance before defunctionalize.
- Owner Qs: Q-O2 (the model), Q-O3 (facts into types), Q-O4 (order).
  Wave-2: Q-W1 (largest matches' origin; sum per type/label class/flow set),
  Q-W2 (state shape per analysis), Q-W5 (is optimize's specialization
  polyvariance; what does it recover the label solve merged).

**§5.10 rc.** M8: "`Captures` may vanish under defunctionalization ... a
closure's captures are its constructor's fields" (lane 07's to check; the
closure constructor's fields are this lane's output).

**§5.11 oom.** 5.11.2 (A): "the passes acceptance rests on
(defunctionalization, the label solve, counting, lowering) cannot be budgeted
at all: their memory must be bounded by construction." A1: each solver's
header states its state's size in program units; a state sized by a product
of two program quantities is a wall (wave-2 item 7).

**§8 (owner's questions this lane bears on).** Q-O4 (8.8), Q-E4 (8.2),
Q-M4 (8.2), Q-O2 (8.4) as assigned; also Q-O3, Q-E2, DD-Q7 (8.3), Q-M1,
QA4, QL3, Q-E1 (8.4), Q-llvm-2/Q-E3 (budgets), ods-Q1/DD-Q2 (divergence:
the effects pass's `Divergence`), DD-Q3 (world).

**§9.** D2: own solvers allowed, named honestly, in code of their own.

**proposals/0003-facts-once.md (read).**
- Header: built so far "the force dispatch's and an apply's cases placed at
  their labels (8e2fbec7)".
- "Defunctionalization and the optimizer (defunc lane)": (a) `Effects.cpp`
  "preserves only `SymbolTable` though it writes only effects, so Contify
  rebuilds `CallCycles`"; (b) `Defunctionalize/Pass.cpp` "builds a
  `TypeGraph` outside the manager for a statistic and Knots builds it again";
  `TypeGraph(op)` also built by `Layouts`, `layout::fit`, the program
  verifier; (c) optimizer items (lane 09's).
- "The dialect: matches and locations": "**Deduplicate** fuses only the
  function's location; fuse op by op along the lockstep equivalence";
  frames' `closureLabels` "walks every value's type on every run though the
  sums are `TypeGraph::declarations()`" (lane 10's file, this lane's fact).
- Representation-wave leftovers: `DataType::Body` is `{kind, ctors,
  instance}` with role/kind pairs checked by tables; "there is no
  `DataType::memo()`, so the force dispatch keeps a catch-all internal error
  (`Defunctionalize/Forces.cpp`)"; owed: `Body` as one alternative per kind
  ("closure labels each with its function; a memo's labels, running and
  forced"). MoveOut classifies effects a second way beside `idr::classify`
  (`lib/IR/Effects.cpp`); resources read as effect bits by hand; the
  crash-site count (every `NoReturn`) and `bodyEffect`'s `MayCrash`
  disagree. "`holdsLabels(Value)` (`lib/IR/Flow.cpp`) repeating
  `carriesLabels(Type)` (`Analysis/Labels.h`)". `SpecKeyAttr`'s `origin`
  (lane 09).
- Target lane: "`effects` and `total` reach no LLVM attribute" (the effects
  pass's output is not lowered; lane 12).

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*: `wc -l`)

| part | files | lines |
| --- | --- | ---: |
| label solve | `idr/include/idr/Analysis/Labels.h` 325, `idr/lib/Analysis/Labels.cpp` 377, `LabelSites.cpp` 231 | 933 |
| defunctionalization | `idr/include/idr/Transforms/Defunctionalize.h` 298; `lib/Transforms/Defunctionalize/`: `Pass.cpp` 162, `Decide.cpp` 62, `Keys.cpp` 216, `Moves.cpp` 56, `Declare.cpp` 278, `Converter.cpp` 186, `Patterns.cpp` 287, `PatternsCalls.cpp` 83, `Forces.cpp` 162 | 1,790 |
| deduplication | `include/idr/Transforms/Deduplicate.h` 40; `lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp` 228 (Modular port, Apache-2.0 WITH LLVM-exception), `Equivalence.cpp` 233 (ours) | 501 |
| effects | `include/idr/Transforms/Effects.h` 34, `lib/Transforms/Effects/Effects.cpp` 43; `include/idr/Analysis/Effects.h` 64, `lib/Analysis/Effects.cpp` 96 | 237 |
| constants (idr-optimize's inner step, filed under Effects) | `lib/Transforms/Effects/Constants.cpp` 209; `include/idr/Analysis/Constants.h` 59, `lib/Analysis/Constants.cpp` 43 | 311 |
| total | 20 files | 3,772 |

Command: `wc -l` over the twenty files above (bash array; the total
printed is 3,772). Read beside them (owned by other lanes): the effect rule
`bodyEffect`, `componentEffects`, `writeEffects`, `effectInstances`
(`idr/lib/IR/Func/Func.cpp:185-266`, `include/idr/IR/Func.h:27-59`), the
call's effects and symbol-use verifier (`lib/IR/Func/Call.cpp:29-72`), the
flow vocabulary and the closure ops' edges (`include/idr/IR/FlowEdges.h`,
`lib/IR/Flow.cpp:64-92`, `lib/IR/FlowOps.cpp:57-173`), `TypeGraph`
(`include/idr/IR/TypeGraph.h`, `lib/IR/TypeGraph.cpp:1-80`), `layout::fit`
(`lib/IR/Layout/Fit.cpp`), `DataRemap`/`Declarations`/`ContentNames`
(`include/idr/IR/Symbols.h:101-304`), `idr::components`
(`lib/Support/Scc.cpp`), the roles (`include/idr/IR/IdrDialect.h:146-180`),
the pass records (`include/idr/Transforms/Passes.td:100-188`,
`InnerPasses.td:61-71`), the pipeline (`lib/Transforms/Pipeline.cpp:61-80`),
`labels-least` (`lib/Transforms/Expect/LabelsLeast.cpp`).

Pattern counts over the twenty files (*measured*, `grep -c -F` per token,
summed): `isa<` 3, `dyn_cast` 12, `std::variant<` 1, `std::visit` 5,
`llvm::makeVisitor` 5, `std::get_if` 2, `std::get<` 2, `holds_alternative`
0, `function_ref<` 10, `virtual` 4 (one interface), `template <` 2,
`requires`/`concept` 0, `DenseMap<` 29, `DenseSet<` 7, `SetVector<` 2,
`parallelFor` 3, `failableParallelForEach` 1, `walk(` 15, `getAnalysis<` 5,
`AnalysesPreserved` 4, `internal error` 5, `assert(` 7,
`getPropertiesAsAttribute` 3, `getAttrDictionary` 3, `switch (` 0,
`TypeSwitch` 0.

### 2.2 The pipeline position and the stages (*read*)

`Pipeline.cpp:61-80`: `idr-deduplicate` (stage any), `idr-defunctionalize`
(Higher → First), `idr-knots`, `idr-effects` (First → First), then
`idr-contify` and `idr-optimize`, whose inner pipeline ends with
`idr-constants` (`InnerPasses.td:61-71`). The stages are records the pass
base class enforces (`Passes.td:40-71`, `::idr::StagedPass`): defunctionalize
may run only on a Higher program and leaves it First; effects requires First.

### 2.3 The label solve (*read*)

- **Points.** A point is a value whose type carries labels (a closure or a
  suspension, `carriesLabels`, `Labels.h:59-61`), a function parameter (its
  entry argument, `LabelSites.cpp:27-32`), a function result keyed by
  `(StringAttr name, index)` (`Labels.h:108`), or an anchor: a constructor
  field, a shaped type's elements, a lazy type's forced state, a memo sum's
  state, a capture, a hole (`FlowEdges.h:86-122`). A point is a
  `PointKey = std::variant<Value, FlowAnchor, ResultKey>` (`Labels.h:109`),
  32 bytes by the alternatives' sizes (*conjecture*, arithmetic from the
  definitions). A value of any other type has no node (`Labels.h:22-23`;
  `LabelSites.cpp:67-68`): MLton's first-order values sharing one abstract
  value (§5.9 B5).
- **Reading.** One serial `program->walk` (`LabelSites.cpp:165-175`) asks
  every op for its flow edges (`flowEdgesOf`, `Flow.cpp:71-82`), keeps those
  carrying labels, expands constants (`LabelSites.cpp:119-146`), and states
  them through a virtual `Statements` interface (`Labels.h:121-127`) with two
  implementations: the solve's `Graph::Builder` (`Labels.h:235-244`) and the
  oracle `Derivation` (`LabelsLeast.cpp:34-102`). A use that moves into two
  points unifies them (`LabelSites.cpp:106-110`). A dispatch (an
  `idr.apply`) is stated on its callee point (`LabelSites.cpp:81-84`); a
  force is no dispatch: it reads the forced anchor of its lazy *type*
  (`FlowOps.cpp:168-171`), and a suspension's label result is unified with
  that anchor (`FlowOps.cpp:154-158`).
- **Graph and solve.** A union-find over nodes (`Labels.h:264-267`); a class
  holds a `SetId` and its successor nodes (`Labels.h:220-223`); sets are
  interned in a `SetTable` (`Labels.h:179-203`, MLton's `UniqueSet`), unions
  memoized per sorted id tuple (`Labels.cpp:101-124`). Labels are ranked by
  name first (`Labels.cpp:184-208`). The solve is waves
  (`Labels.cpp:213-300`): take every class downstream of a new edge, collapse
  each cycle (`idr::components`, `Labels.cpp:261`), compute each class's set
  once in topological order, then scan **every** dispatch for labels it has
  not run (`Labels.cpp:288-298`) and fire them (`Labels.cpp:303-307`,
  `readFiring`, `LabelSites.cpp:179-194`). Termination: a wave after the
  first exists only because a firing new to its dispatch happened
  (`Labels.cpp:18-21`). No budget, no round count (*read*).
- **Answer.** `labels::Solution` (`Labels.h:153-174`): `DenseMap<PointKey,
  Node> nodes`, `DenseMap<OpOperand *, FlowPoint> sinks`, a vector of one
  uniqued `ArrayAttr` per node, one attribute per distinct set
  (`Labels.cpp:316-331`), and a reference to the program's `SymbolTable`.
  The `Labels` analysis (`Labels.h:283-321`) is cached in the
  `AnalysisManager` and invalidated unless it and `SymbolTable` are preserved.
- **State size.** Per solve: P nodes (two vectors of 4 bytes plus a class of
  a `SetId` and a `SmallVector<Node, 2>`), the two maps above (buckets of
  about 40 and 56 bytes by the key and value types, *conjecture*), the
  interned sets (Σ|S| over distinct sets), firings. Per wave: a
  `DenseMap<Node, unsigned>`, an edge list and an SCC graph over the classes
  taken (`Labels.cpp:216-261`). History: 7adc6095 replaced a per-class label
  copy and a `(node, label)` worklist (Θ(P·L), 300 GB projected at 65,536
  labels) by this, measured 0.15 → 10.4 s on `defunc-tag-limit` from 1k to
  65,536 labels (*read*, the commit message and `audits/label-solve.md` at
  77eaa5b1).
- **Readers.** `idr-defunctionalize` (`Pass.cpp:109`, every key), the
  `labels-least` property (`LabelsLeast.cpp:137`), nothing else
  (*measured*: `grep -rn 'getAnalysis<idr::Labels>'`, two sites).

### 2.4 Defunctionalization (*read*)

- **Decision, serial.** `Slots::decide` (`Declare.cpp:72-102`) builds the one
  `Slots` object (`Defunctionalize.h:115-231`) in order: keys of every
  signature (`Keys.cpp:43-54`), widening (`Moves.cpp:39-54`: a closure,
  suspension or constant whose every use sinks into one larger key takes
  it), every key any value or type names (`Keys.cpp:56-70`), names from
  content (`Decide.cpp:43-53`), every sum with its body under one
  `Declarations` (`Declare.cpp:78-85`, the 73bba53f fix), signatures,
  dispatch names, constants, and a dispatch function per memo sum
  (`Forces.cpp:51-160`). A key is `(carrier at no grade, label set)`
  (`Defunctionalize.h:56-65`): **one sum per flow set**, MLton's D3.
- **Conversion, parallel.** `failableParallelForEach` over the functions
  (`Pass.cpp:138-141`); each builds its own `Plan` (three `DenseMap`s keyed
  by `Value` and `OpOperand *`, `Defunctionalize.h:104-108`;
  `Keys.cpp:192-214`), its own `SlotTypeConverter` (value-based conversion,
  target materialization = MLton's re-tagging `coerce`,
  `Converter.cpp:102-121`), its own `ConversionTarget` (`Pass.cpp:58-82`) and
  its own `RewritePatternSet`, holding seven op patterns, two call patterns
  and one `RetypePattern` per registered op of the context except a
  hand-written list of nine (`Patterns.cpp:269-285`), frozen by
  `applyFullConversion` per function, with pattern rollback on
  (`Pass.cpp:97-100`) because the plan is keyed by values the conversion
  would otherwise erase (`Pass.cpp:84-86`).
- **Rewrites.** A closure or suspension becomes its label's constructor
  (`Patterns.cpp:38-68`); an apply a match with one case per label calling
  the label's function (`Patterns.cpp:92-177`), poison when the set is
  empty; a force a call of `<sum>.force` (`Patterns.cpp:182-205`); a delay the
  memo sum's Forced state (`Patterns.cpp:72-86`). The dispatch function
  matches the cell: a label's case runs `idr.memo.run` (memoized) or calls
  directly (`by_name`), Running crashes, Forced yields (`Forces.cpp:88-156`).
- **After.** One `DataRemap` remakes every data type that holds a slot
  (`Declare.cpp:219-236`); `layout::fit` builds a `TypeGraph` and a second
  `DataRemap` for boxes (`Pass.cpp:144-147`, `Fit.cpp:24-37`); a third
  `TypeGraph` is built for one statistic (`Pass.cpp:150-158`).
- **by_name.** Decided before the decision by `observableRuns`
  (`Pass.cpp:110-115`, `Effects.cpp:49-95`) minus static suspensions
  (`Pass.cpp:120-127`), and threaded as a `function_ref<bool(FuncOp)>`
  through four functions (`Defunctionalize.h:127, 188-195`).
- **Whole-program walks in one run** (*read*): `readProgram`; the statics
  walk (`Pass.cpp:121-127`); `observableRuns`' body walks
  (`Effects.cpp:63-73`, parallel); `widen` (`Moves.cpp:40`); the Slots
  constructor (`Keys.cpp:56-70`); the constants walk (`Declare.cpp:89-92`);
  one plan walk and one conversion walk per function (parallel); two
  `DataRemap` retypes; three `TypeGraph` walks (two in `fit` and the
  statistic, *read*: `Fit.cpp:25`, `Pass.cpp:152`; `layout::fit` builds one).

### 2.5 Deduplication (*read*)

`EliminateDuplicateFunctions.cpp:88-226`: collects each body's symbol uses in
parallel (`:100-111`, `SymbolTable::getSymbolUses`, which sees a closure's
label); builds its own reference graph and its components
(`idr::components`, `:122-143`); excludes every member of a cycle of two or
more (`:142`); per height, hashes in parallel (`:151-155`, 32 bits kept) and
forms classes serially with an `std::unordered_map` and a linear scan of
`sameFunction` per bucket (`:159-173`); renames to the lexicographically
smallest member (`:177-188`, a `DeduplicateMergeAction`); fuses the members'
locations onto the kept one (`:196-199`); one `DataRemap` renames every use
(`:206-224`). `Equivalence.cpp` hashes and compares bodies op by op through a
`Reading` (an `AttrTypeReplacer` that renames references, `:41-60`) applied
to `getAttrDictionary()` and `getPropertiesAsAttribute()` of every op
(`:101-102, 143-146`) and to the function's facts (`:66-76`). PINS.md's
entry `eliminate-duplicate-functions` (`PINS.md:786-815`) records the port.
History: 234b81a0 (first version: 1,985 groups, 7,505 of 107,732 functions
erased on stage 0 "in about a second of pass time", *read*).

### 2.6 Effects and constants (*read*)

- **idr-effects** (`Effects.cpp` Transforms, 29-40) calls `solveEffects`
  (`Analysis/Effects.cpp:36-47`): a `SymbolTableCollection` and a whole-program
  `SymbolUserMap` per run, then, over `CallCycles`' components callees first
  (serial), `componentEffects` (`Func.cpp:207-220`: or of each member's
  `bodyEffect` and each outside callee's call effects) written to the members
  and every call of them (`writeEffects`, `Func.cpp:225-230`). One pass, no
  iteration: least fixpoint of a monotone or over the SCC DAG. The summary is
  the `Effect` bit enum {io, crash, diverge}, an inherent property of
  `idr.func` and `idr.call` (`IdrOps.td:162-163, 219-220`), each call
  verified to contain its callee's in `verifySymbolUses` (`Call.cpp:29-61`)
  and declared to MLIR by a hand `getEffects` (`Call.cpp:65-72`) through a
  hand table bits → resources (`Func.cpp:250-266`). It preserves only
  `SymbolTable` (`Effects.cpp:38`).
- **bodyEffect** (`Func.cpp:189-205`), the one rule read by idr-effects, by
  idr-optimize's `Scheduler::finish` (`Optimize/Component.cpp:215`) and by the
  program verifier after every pass (`Verify/Program.cpp:61-71`): diverge
  unless `total`; io if a parameter holds a world or the body has
  `idr.world.new`; crash at a `MayCrashOpInterface` op; everything at a
  `RunsLabelsOpInterface` op.
- **observableRuns** (`Analysis/Effects.cpp:49-95`): a backward reach over a
  graph of runs (calls, and the labels each apply or force runs, through a
  `function_ref` callback), from functions holding an `ObservableIO` op,
  with a `OnceWorklist`. `ObservableIO`'s only reader (*measured*:
  `grep -rn ObservableIO idr/lib`, one site).
- **idr-constants** (`Transforms/Effects/Constants.cpp:171-197`): upstream's
  `DataFlowSolver` per function, `setInterprocedural(false)`, with
  `DeadCodeAnalysis` and a `SparseConstantPropagation` subclass whose
  `visitExternalCall` reads callee summaries from idr-optimize's ready set
  (`Analysis/Constants.cpp:36-43`); the rewrite (`Constants.cpp:73-163`) is
  upstream SCCP's static `rewrite` (`mlir/lib/Transforms/SCCP.cpp:42-104`)
  re-written with actions and statistics.

### 2.7 Threading (*read*)

Deduplicate, defunctionalize and effects are `idr.program` passes; each
parallelizes inside itself on MLIR's pool (`parallelFor`,
`failableParallelForEach`): dedup's use collection and hashing, the
defunctionalization's `observableRuns` body walks and per-function
conversion. The label solve, the decision, dedup's class formation, the
remaps and `solveEffects` are serial. idr-constants runs per function under
idr-optimize's own scheduler. No mutex or atomic in the subsystem
(*measured*: `grep -c -e mutex -e atomic` over the twenty files: 0).

## 3. Reconciliation with the proposal

### 3.1 Wave-1 findings and designs against the code

| finding / design | verdict | evidence |
| --- | --- | --- |
| §2: Labels/LabelSites are "the defunctionalization label solve" | holds | `Labels.h:3-32`; its two readers, §2.3 |
| §2: `Transforms/Effects/Constants` "still on upstream's dataflow framework" | holds, and already in §5.1 Design 1's shape | per function, interprocedural off, summaries through `visitExternalCall` (`Constants.cpp:186-191`, `Analysis/Constants.cpp:36-43`) |
| §3 row 73bba53f, "the table of data types rebuilt per declaration" | holds as fixed | `Declarations` takes every type at once when it ends (`Symbols.h:101-137`; `Declare.cpp:78-85`); but the pass still runs two whole-program remaps and three `TypeGraph` walks (§2.4) |
| §5.1 5.1.2 item 3: the label solve stays ours, honestly | holds; it is already ours, off the framework | `Labels.cpp` holds no `DataFlowSolver`; the pass record still says "A sparse dataflow analysis finds the labels" (`Passes.td:127`), stale |
| §5.1 5.1.2 item 4 / patch 29: a closure's label is a non-call symbol use | holds for dedup | dedup reads every symbol use, labels included (`EliminateDuplicateFunctions.cpp:23-26, 100-111`); after defunctionalization a label survives only as a `role::Label` function inside a data type body (`IdrDialect.h:156-160`), which `DataRemap` renames (`EliminateDuplicateFunctions.cpp:202-212`) |
| §5.1 F3 / W5: no attribute or type made on a hot path | refuted in this subsystem | `getAttrDictionary()` (which builds and uniques a `DictionaryAttr` for an op with properties, `mlir/lib/IR/Operation.cpp:292-299`) and `getPropertiesAsAttribute()` per op, and an `AttrTypeReplacer` per reading, in dedup's hash and compare (`Equivalence.cpp:69, 101-102, 144-145`, run in `parallelFor`, `EliminateDuplicateFunctions.cpp:152`); `getAttrDictionary()` per op in the decision (`Keys.cpp:62`); upstream's `OperationEquivalence` reads raw dictionaries and `hashProperties`/`compareOpProperties` instead (`mlir/lib/IR/OperationSupport.cpp:731-744, 895-910`) |
| §5.2 A9 / §5.8 DS2.1: a call carries its callee's effect set as an inherent property verified in `verifySymbolUses` | holds (already built) | `IdrOps.td:162-163, 219-220`; `Call.cpp:29-61`; but the call's `getEffects` is hand-written from the property (`Call.cpp:65-72`) through a hand table (`Func.cpp:250-266`): recipe row 3, not ODS |
| §5.2 M1 / §2 trait layer: three representations of "does IO" | holds | `bodyEffect` reads world-typed parameters and `idr.world.new` (`Func.cpp:191-197`); the IO ops declare `IOResource` effects; `Idr_PerformsIO`'s own comment says effects do not read it (`IdrInterfaces.td:292-297`) |
| §2: traits "read once or never (`ObservableIO`)" | holds: read once | `Analysis/Effects.cpp:66` is its one reader |
| §5.3 M4: the label solve's graph gets `scc_iterator` through `GraphTraits` | holds in part | the solve calls `idr::components` per wave (`Labels.cpp:261`), itself a `GraphTraits` adapter over `llvm::scc_iterator` (`Scc.cpp:22-53`); the graph is the union-find's successor lists, not a CSR graph |
| §5.3 B8: `lib/Support/Scc.cpp` "a hand-rolled `scc_iterator`" | refuted | it wraps `llvm::scc_begin` (`Scc.cpp:42`); lane 05 owns it |
| §5.4 F4, 5.4.2 item 3: the port's "waves by height with a barrier per wave" | holds | `EliminateDuplicateFunctions.cpp:140-189`; the PINS.md entry says so (`PINS.md:798-803`) |
| §5.4 F4: Modular skips cycles | holds in the port | `EliminateDuplicateFunctions.cpp:31-34, 142` |
| §5.6 5.6.2 item 6: the label solve fits extract, solve, write back | holds in part | extract (`readProgram`), solve (`Graph::solve`), answer (`Solution`), but points are keyed by hashed pointers (`Labels.h:169-171`), extraction is one serial walk (`LabelSites.cpp:169`), and the answer is read by value lookup, not by walk order |
| §5.6 W-E1 / Design 1's maintained `ProgramGraph` | holds as a need | dedup derives its own reference graph and SCCs (`EliminateDuplicateFunctions.cpp:100-143`); defunctionalization adds calls (every apply case, every force) and maintains no graph; idr-effects reads `CallCycles` and does not preserve it (`Effects.cpp:38`, 0003's item) |
| §5.7 L4: label flow as relations, union-find for equalities | holds in part | unifications become two inclusions, a cycle collapsed into one class (`Labels.cpp:148-154`): union-find for equalities; inclusions are Andersen subsets, as MLton's |
| §5.9 D3 / M4 / Q-W1: one sum per flow set | holds | key = (carrier, label set) (`Defunctionalize.h:54-65`, `Keys.cpp:75-79`); a smaller set moving into a larger key is rebuilt by a match (`Converter.cpp:48-98`, MLton's `coerce`); an apply is a match over its key's labels (`Patterns.cpp:92-177`, MLton's `apply`); widening makes a closure built only to move into one larger key take that key and need no coercion (`Moves.cpp:37-54`); fixture `defunc-coerce` states it |
| §5.9 B5: state sized by types and constructors | holds | anchors are per constructor field, element type and lazy type (`FlowEdges.h:86-122`); a non-carrier value has no node (`LabelSites.cpp:67-68`) |
| §5.9 D2: hash-consed sets | holds | `SetTable` (`Labels.h:176-203`) |
| §5.9 D2: `send` pushes only the difference along edges | refuted: ours re-sweeps | a wave retakes every class downstream of a new edge (`Labels.cpp:223-228`), rebuilds its SCC graph (`Labels.cpp:231-261`), and scans every dispatch (`Labels.cpp:288-298`), changed or not |
| §5.9 F5 / M9 / Design 7: no polyvariance before the flow analysis | holds | deduplicate → defunctionalize → … → optimize (`Pipeline.cpp:66-82`); the solve has one point per function parameter (`LabelSites.cpp:27-32`), so a function's parameter holds the union of every call site's labels |
| §5.9 H, 73bba53f: "new datatypes pushed to a list and emitted once" | holds now | `Declarations` (above) |
| §5.9 Design 3: "the label solve's answer is the closure sums" | holds for the output; refuted for the pass's inside | inside the pass the answer travels as per-function `Plan` maps keyed by values (`Defunctionalize.h:104-108`) until the conversion writes the types |
| §5.8 DS4: `closure`, `apply` legal only before defunctionalization by `ConversionTarget` | holds (already built) | `Pass.cpp:64-65`, and the stage records (`Passes.td:123-124`) |
| §5.10 M8: `Captures` may vanish | evidence for lane 07 | a closure's captures are its label constructor's fields (`Declare.cpp:180-190, 200-205`) |
| §5.11 5.11.2(A): the label solve cannot be budgeted; memory bounded by construction | holds for the budget, not for the bound | no budget or count (`Labels.cpp:18-21`); time is O(W·(P+E)) plus O(W·D) for the dispatch scan (§4 L-11), W the waves, D the dispatches: a product of two program quantities in the worst case (§5.11 A1) |
| 0003 defunc lane: effects preserves only `SymbolTable`; defunc builds a `TypeGraph` for a statistic | both hold | `Effects.cpp:38`; `Pass.cpp:150-158` (and `Fit.cpp:25` builds another) |
| 0003: Deduplicate fuses only the function's location | holds | `EliminateDuplicateFunctions.cpp:194-199` |
| 0003: the force dispatch's catch-all internal error | holds | `Forces.cpp:144-150` |
| 0003: `holdsLabels(Value)` repeats `carriesLabels(Type)` | holds | `Flow.cpp:90-92` against `Labels.h:59-61` |

### 3.2 Wave-2 questions of §5 that fall here, by ID

- **§5.1 W2** (each analysis: lattice, scope, summaries, Design 1 or 3).
  Label solve: a set of labels per point, interned, per class of a
  union-find, whole program, relational (inclusion with conditional edges),
  no summaries possible before the call graph exists (calls through values):
  Design 3 (solver layer), shape G. Effects: three bits per function, a
  summary over the SCC DAG, callees first: Design 1's summary layer.
  `observableRuns`: one bit per function, a backward mark over the run graph:
  the summary layer's other direction. idr-constants: upstream's
  `Lattice<ConstantValue>` per value, per function, summaries per callee:
  Design 1 as built. Dedup: a class id per function over its own reference
  graph: a partition, not a lattice (§5).
- **§5.1 W3** (`getPredecessors`, `getSuccessorOperandInputMapping()`,
  `isRepetitiveRegion`, edge tables per query): none in the twenty files
  (*measured*: `grep -c` of each, 0); the label solve reads region forwarding
  through `forwardedValues` (`Flow.cpp:42-62`, lane 02's), per terminator.
- **§5.1 W5** (attributes or types made on a hot path): yes, §3.1 row F3;
  plus one `ArrayAttr` per distinct final set (`Labels.cpp:323-329`), which
  is the key's identity and stays: output-sized.
- **§5.1 W6** (function anchoring): the three passes are anchored on
  `idr.program` by necessity (whole-program); each parallelizes internally on
  the context's pool (§2.7); idr-constants is anchored on `idr.func`
  (`InnerPasses.td:61`).
- **§5.1 W7** (backward analysis callee resolution in a scoped solve): none:
  idr-constants is forward, interprocedural off, a function holds no symbol
  table (`Constants.cpp:186-188`).
- **§5.2 W1** (hand `getEffects`): none in the twenty files; the effects this
  lane writes are read by `CallOp::getEffects` (`Call.cpp:65-72`), a hand
  method that is effects-from-a-property (row 3), lane 02's to redeclare.
- **§5.2 W9** (passes that change nothing mark analyses preserved): dedup
  does (`EliminateDuplicateFunctions.cpp:191-192`), idr-constants does
  (`Constants.cpp:195-196`); idr-effects writes only properties but preserves
  only `SymbolTable` (`Effects.cpp:38`); defunctionalize always changes the
  program.
- **§5.3, every worklist**: `observableRuns`' `OnceWorklist<unsigned>`
  (`Effects.cpp:85-94`, FIFO, dense index nodes: a mark); the label solve's
  waves (`Labels.cpp:313-315`) with a per-wave `order` vector and a
  `DenseMap<Node, unsigned>` (`Labels.cpp:216-228`); the oracle's
  `OnceWorklist<pair<unsigned, FlatSymbolRefAttr>>` (`LabelsLeast.cpp:100`,
  test-only by design).
- **§5.3, every DenseMap**: all are one per solve or per function, none per
  node (the per-node state is vectors, `Labels.h:264-267`); 29 sites listed in
  §4. Pointer-keyed whole-program maps: `Solution::nodes`, `Solution::sinks`
  (`Labels.h:169-171`); per function: `Plan`'s three (`Defunctionalize.h:105-107`).
- **§5.3, every `function_ref`**: `byName` (4 signatures,
  `Defunctionalize.h:127, 188-195`), a predicate that is data; `LabelsRun`
  (`Effects.h:51-52`), called per runner, callee's static type known;
  `ConstantsOf` (`Constants.h:39`), per call per solve; all three are
  "callbacks threaded through code that knows its static type" (§4).
- **§5.3, every variant**: `PointKey` (`Labels.h:109`, 3 alternatives, a
  hash key), `FlowPoint`/`FlowAnchor`/`FlowEdges::Edge` (lane 02's types,
  read with exhaustive `makeVisitor`, `LabelSites.cpp:64-85, 92-100,
  151-162`, `Keys.cpp:85-96`), `Role` (`std::get<role::Label>` at
  `Converter.cpp:54`, `Patterns.cpp:128`; `get_if` at `Forces.cpp:62`; a
  visit with a catch-all at `Forces.cpp:100-151`), the ready set's `Callee`
  (`get_if` at `Constants.cpp:182`).
- **§5.3, the label solve's graph and one CSR `Graph`**: nodes are a dense
  `Node` (`Labels.h:77`), edges are `SmallVector<Node, 2>` successor lists on
  union-find classes, rebuilt per wave (`Labels.cpp:231-245`); a dynamic
  graph (firings add edges, merges collapse nodes), so a frozen CSR serves
  its input (the static statements) but not its solve state.
- **§5.4, summaries over the call graph and own SCC orders**: idr-effects
  (callees first, `CallCycles`); `observableRuns` (callers first, its own
  run graph, `Effects.cpp:79-82`); the deduplicator (callees first, its own
  reference graph and `idr::components`, `EliminateDuplicateFunctions.cpp:100-143`);
  the label solve is no call-graph summary (it builds the call graph's
  indirect edges).
- **§5.4, the deduplicator's waves' idle time**: not measurable here (no
  built compiler); the measurement is the per-height task count
  (`byHeight[h].size()`) and the time per height on stage 1 (§8).
- **§5.4, a hand `getEffects` that exists because an attribute changes
  meaning**: `CallOp::getEffects` reads the `effects` property
  (`Call.cpp:65-72`); the property is this lane's output.
- **§5.4, `CallOpInterface` once specialization is done**: `idr.call` and
  `idr.apply` already implement it (`LabelSites.cpp:81-84` casts an apply to
  `CallOpInterface`, `Effects.cpp:68`).
- **§5.4, options selecting implementations**: none.
- **§5.6 W-E2** (states kept against values whose type leaves the question
  open): the label solve keeps nodes only for values of a closure or lazy
  type, plus anchors and function interface points (`LabelSites.cpp:67-68`):
  exactly the open set by type.
- **§5.6 W-E3** (analyses computed by more than one pass): effects by
  idr-effects, again per component by idr-optimize (`Component.cpp:215`), and
  checked by the program verifier after every pass (`Verify/Program.cpp:61-71`);
  `TypeGraph` three times in one defunctionalization (§2.4); `CallCycles`
  rebuilt after idr-effects.
- **§5.6 W-E4** (a fact in a discardable attribute): none here: `effects`,
  `total` are properties; `by_name` is in the type's body (a role field,
  `IdrDialect.h:156-160`).
- **§5.6 W-E5** (budgets): none in the subsystem (*measured*: `grep -n -i
  -e budget -e limit -e cap` finds none in the twenty files' code). The
  label solve's termination is by firings, dedup's by heights, effects' by
  the SCC DAG.
- **§5.6 W-E6** (queries that walk a match's regions): none; the conversion
  *builds* matches (`Converter.cpp:69`, `Patterns.cpp:111`, `Forces.cpp:87`).
- **§5.6 W-E7** (`DenseMap<Value, …>` solver state): `Solution::nodes`
  (`PointKey`), `Solution::sinks`, `Plan`, `Slots::widened`
  (`Defunctionalize.h:210`), dedup's `values` maps (`Equivalence.cpp:130, 199`).
- **§5.6 W-E8** (single-block regions after defunctionalization): an
  `idr.func` body is one block (`Flow.h:10`) and every region the conversion
  builds has one block (`Converter.cpp:75-76`, `Patterns.cpp:146`,
  `Forces.cpp:94-95, 127-128`); lane 03 confirms for every op.
- **§5.6 W-E9** (state copied per edge or branch): none; a class holds a set
  id (`Labels.h:220-223`).
- **§5.7, PLV, independent or relational**: label solve relational
  (inclusion with conditional edges); effects independent per function (bits),
  a summary; constants PLV per value; dedup a partition.
- **§5.9 Q-W1**: sums are per flow set (§3.1). Where stage 1's largest
  matches come from cannot be measured here; an apply's match has as many
  cases as its key has labels (`Patterns.cpp:109-115`), so a key reached by
  every continuation passed to one higher-order function is one such match
  (`defunc-tag-limit`: one sum of 65,537 constructors, `audits/label-solve.md`
  at 77eaa5b1, §2).
- **§5.9 Q-W2**: label solve: per type (anchors) and per carrier value, flow
  insensitive by SSA, cells merged by union-find, waves instead of handlers;
  effects: per function; `observableRuns`: per function; dedup: per function.
- **§5.11 W7** (state sized by a product): the label solve's O(W·D) dispatch
  scan and O(W·(P+E)) re-sweeps (§4 L-10, L-11); the per-function pattern set
  of O(registered ops) (§4 D-3) is functions × registered ops.
- **§5.11 W8** (attributes made per function or value): §3.1 row F3.

## 4. Issues

All *read* at the cited lines unless marked. IDs: L (label solve), D
(defunctionalization), U (deduplication), E (effects), C (constants).

### 4.1 The label solve

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| L-1 | `Labels.h:59-61`; `Flow.cpp:90-92` | rederivation | `carriesLabels(Type)` and `holdsLabels(Value)` are one predicate twice (0003) | one fact on the carrier: `Carriers::of(type).holdsLabels()` beside `Carriers` (`FlowEdges.h:49-80`), or the type interface lane 01 gives `ValueFacts`; both free functions go |
| L-2 | `Labels.h:66-72`, `Labels.cpp:43-55`; `LabelSites.cpp:119-121`; `Declare.cpp:243-245`; `Pass.cpp:74-80`; `Pass.cpp:121-127` | rederivation, ladder | "does this constant part hold a closure" asked five ways: a memo map (`ClosureParts`, a `dyn_cast<ClosureAttr>`/`<ConAttr>` ladder), the reading, the conversion, the constant's legality (a walk per legality query, `audits/label-solve.md` item 6), the statics walk | the fact computed once per attribute at construction, a recursive property in `ConAttr`'s storage (FIRRTL's `RecursiveTypeProperties`, §5.8 E1, T7; lane 01 owns `ConAttr`); `ClosureParts` and the legality walk go |
| L-3 | `Labels.h:104-113` | state | a point is a hashed `std::variant<Value, FlowAnchor, ResultKey>`; a parameter is keyed by its entry `Value`, a result by `(StringAttr, unsigned)`: two coordinates for one kind of point | dense point ids minted by the extractor: (function id, index) for parameters and results, a per-function value number, an interned anchor id; `PointKey`, `ResultKey`, `keyOf` go |
| L-4 | `LabelSites.cpp:27-32, 150-163, 181` | rederivation | every parameter point and every firing finds its function by name in the `SymbolTable` (with an `assert`) | function ids from the program graph (§5.6 Design 1); no lookup by name in the solve |
| L-5 | `Labels.h:121-127, 235-244`; `LabelsLeast.cpp:34-102` | cpp | a virtual `Statements` interface with two implementations, called once per edge | the extractor's output is data (arrays of sources, links and dispatches) that the solve and `labels-least` both read; the interface and `Builder` go |
| L-6 | `Labels.h:153-174` | state | the answer is two whole-program pointer-keyed maps (`nodes`, `sinks`) and a reference to the program's `SymbolTable` | a vector indexed by point id and a per-operand sink id, read back in extraction order (§5.6 shape G); the maps and the table reference go |
| L-7 | `Labels.h:156`, `Labels.cpp:342-345` | state | `labelsOf` answers the empty set on a missed key: a lookup that can miss | with ids from one walk the read is total; the miss branch goes |
| L-8 | `Labels.h:160, 317` | rederivation | `function(label)` looks a label's function up by name per question | a `Label`-indexed vector of functions, built where labels are ranked (`Labels.cpp:184-191`) |
| L-9 | `Labels.cpp:216-261` | state | each wave builds a `DenseMap<Node, unsigned>`, an edge list, a `seen` vector and a fresh `idr::components` graph (`Scc.cpp:35-40`) over every class it takes | the classes' successors as one CSR with `GraphTraits` (§5.3 S1), the SCC taken over it in place |
| L-10 | `Labels.cpp:218-228` | state, cost | a wave takes every class downstream of a dirty node, changed or not: O(W·(P+E)) over W waves | difference propagation (§5.9 D2: a class enqueued only when its set grows; cycles found only around added edges); measure W first (§8) |
| L-11 | `Labels.cpp:288-298` | state, cost | every dispatch is scanned every wave: O(W·D) | dispatches hung on their callee's class and checked only when its set changed (the shape the pre-7adc6095 `Class` had) |
| L-12 | `Labels.cpp:303-307`; `LabelSites.cpp:179-194` | state | a `Builder` per firing; a name lookup per firing | function ids (L-4); firings appended to the edge arrays |
| L-13 | `Labels.cpp:371-375`; `Labels.h:287-289` | state | the analysis reads the `SymbolTable` analysis and is invalidated with it | depends on the program graph instead; one analysis fewer to keep in step |
| L-14 | `LabelSites.cpp:91-102` | rederivation | a flow from a `Whole` value scans every operand of the op for uses of it, per edge | the op declares the use (`FlowPoint::of(OpOperand&)`), lane 02; or an operand index |
| L-15 | `LabelSites.cpp:106-110` | state (precision) | a use that moves into two points unifies the two: one sink per operand, so the plan can hold one key per use | essential only under per-operand plan keys; with types-first (§5, T1) an operand may coerce into each sink; owner question (§6) |
| L-16 | `LabelSites.cpp:165-175` | state, threading | the extraction is one serial walk of the program | per-function extraction in parallel into arrays, concatenated in function order (§5.6 shape G) |
| L-17 | `Passes.td:127-133` | dead (doc) | "A sparse dataflow analysis finds the labels": the solve is a union-find inclusion solve | the record says what `Labels.h:3-32` says |

### 4.2 Defunctionalization

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| D-1 | `Defunctionalize.h:99-108`; `Keys.cpp:188-214` | state, rederivation | each function's `Plan` copies the decision into three maps keyed by `Value` and `OpOperand *` | types first: the decision writes each carrier value's sum type in place and inserts the coercions before any op is replaced (§5, T1); `Plan` goes |
| D-2 | `Pass.cpp:84-86, 97-99` | upstream, state | pattern rollback stays on only so the plan's pointer keys stay distinct | the one-shot driver (`allowPatternRollback = false`, §5.2 E6) or no conversion driver at all (T1) |
| D-3 | `Pass.cpp:87-96`; `Patterns.cpp:282-284` | state, cost | every function, closure or not, builds its own converter, target and a pattern set of one `RetypePattern` per registered op of the context, frozen per function by `applyFullConversion`: functions × registered ops pattern objects and one freeze per function (*conjecture* on the count: hundreds to over a thousand ops with LLVM, linalg, vector, transform registered, `Register.cpp:75-86`) | one stateless pattern set frozen once per pass (T1 makes the patterns stateless); a function with no carrier value and no closure op is not visited |
| D-4 | `Patterns.cpp:274-281` | list | a hand list of nine op names exempt from `RetypePattern` | goes with `RetypePattern` (D-5) |
| D-5 | `Patterns.cpp:240-265`; `Support/Remake.h:26` | upstream | a generic remake of every op with new result types | `Value::setType` in place under T1; the remake goes |
| D-6 | `Pass.cpp:61-65` | list, ods | the ops legal only at the Higher stage are listed in the target | a trait on those ops in ODS (or the stage facts, `Func.h:62-80`) that the target reads; lane 03 |
| D-7 | `Pass.cpp:66-69` | state | a function is legal when its type equals the decision's signature found by name | under T1 the signature is set in place; the dynamic legality goes |
| D-8 | `Pass.cpp:74-80` | rederivation | a constant's legality walks its attribute per query | L-2's cached property |
| D-9 | `Pass.cpp:81`; `Converter.cpp:138-154` | state | every unknown op's legality is a plan lookup per operand, result and block argument | goes with D-1 |
| D-10 | `Pass.cpp:110-134`; `Defunctionalize.h:125-127, 188-195`; `Declare.cpp:74, 147, 162, 174, 204` | cpp | `by_name` is a predicate threaded through four functions as a `function_ref` | a fact per label computed before the decision (data: a bit per label function), or read off the effects summary (T3); the parameter goes |
| D-11 | `Pass.cpp:116-127` | rederivation | "a static suspension is a closure constant that captures every parameter of its label", re-derived by counting captures | the frontend emits a static suspension as such (an attribute kind or op), lane 14/15; *conjecture* that it knows |
| D-12 | `Pass.cpp:144-147`; `Fit.cpp:24-37` | rederivation | after the remake, `layout::fit` builds a `TypeGraph` and runs a second whole-program `DataRemap` for boxes | boxes decided on the decision's own sums and passed to the one remap (`DataRemap::create`'s `boxed`, `Symbols.h:183-185`); one retype per pass (*conjecture*: needs the type graph over the planned types) |
| D-13 | `Pass.cpp:150-158` | rederivation | a third `TypeGraph` walk for one statistic (0003) | the statistic from D-12's box decision; the walk goes |
| D-14 | `Keys.cpp:56-70` | state, W5 | a serial walk of every op noting keys, `types.walk(op->getAttrDictionary())` building a `DictionaryAttr` per op with properties (`Operation.cpp:292-299`) | the data types from the program's table, which holds every body once (b9d4d592), and the types of values and signatures; no attribute made per op |
| D-15 | `Keys.cpp:139-143` | rederivation (minor) | a label's capture count is its inputs minus the carrier's arity | keep: a total function of a verified signature; or read the sum's constructor once made |
| D-16 | `Keys.cpp:133-137`; `Declare.cpp:50-65` | cpp | `assert`/`.at()` on maps for "every key has its sum, every lazy key its dispatch", true by `decide`'s construction | a `SumId` minted by `decide`, the sums a vector indexed by it; the lookups cannot miss |
| D-17 | `Moves.cpp:41` | ladder | `isa<ClosureOp, SuspendOp, ConstantOp>` lists the ops that make a carrier value | read their `Source`/`Constant` edges (`FlowEdges.h:282-314`), which already say it |
| D-18 | `Moves.cpp:39-54` | state | widening is another whole-program walk with a sink lookup per use | over the extracted arrays (a value's sinks are statements), with the solve |
| D-19 | `Declare.cpp:89-92` | state | another whole-program walk for the constants | folded into the one extraction walk (T1) |
| D-20 | `Declare.cpp:198-205`; `IdrDialect.h:156-160` | idris-style flag (C++) | `role::Label` carries `byName`, meaningful only in a memo sum | lane 01's typed body per kind (0003's owed `Body`): a closure label `{fn}`, a memo label `{fn, Memoized or ByName}`; the flag goes |
| D-21 | `Declare.cpp:243-276` | ladder | `convertConstant` repeats L-2's closure/constructor ladder | one walker over the closed set of constant parts (L-2) |
| D-22 | `Declare.cpp:219-236`; `Symbols.h:170-171` | cpp | `DataRemap::Leaf` is an `std::function`; the leaf lambda `dyn_cast`s shaped types | lane 03's API (a template parameter); noted |
| D-23 | `Converter.cpp:48-84` | rederivation, cost | each coercion rebuilds a map from function to tag over the whole target sum and reads roles with `std::get` | the keys' `labelTag` binary search (`Declare.cpp:56-60`) over name-ordered labels: O(\|from\| log \|to\|) per coercion instead of O(\|to\|) |
| D-24 | `Converter.cpp:53-54`; `Patterns.cpp:127-128`; `Forces.cpp:62, 96-151` | idris-style invariant (C++) | `std::get<role::Label>` (aborts), a `get_if`, and a visit whose catch-all is an internal error: "every constructor of a closure sum is a label" lives in a comment | typed body views (`DataType::closures()`, `memo()`, 0003's owed item, lane 01); the asserts and the catch-all go |
| D-25 | `Patterns.cpp:131-134`; `LabelSites.cpp:183-184` | cpp (minor) | `assert` that a label fits its callee's carrier, which the flow verifier holds (`FlowEdges.h:373-382`) | keep (an internal invariant), or typed so it cannot fail |
| D-26 | `Patterns.cpp:221-238` | upstream | a hand signature pattern instead of `populateFunctionOpInterfaceTypeConversionPattern`, since a result's key is the function's | goes under T1 (signatures set in place) |
| D-27 | `Forces.cpp:36-47` | ladder (minor) | `placesIn` walks a location by a `dyn_cast` ladder | upstream's `LocationAttr::walk` |
| D-28 | `Forces.cpp:135-137` | string identity | "a suspension forced itself" as a crash string | lane 03's crash reason enum (§5.8 DS4) |
| D-29 | `Forces.cpp:124-131` | ods (note) | the memo exchange's region ends in `idr.array.yield` | lane 03/11's yield design; noted |
| D-30 | `Defunctionalize.h:91-97`; `Declare.cpp:132-135` | state | `Signature::place` is `std::optional<Location>`: present for program functions, absent for dispatch functions, a kind as a `Maybe` | the dispatch's place is known (`Forces.cpp:67-71`); store it, the optional goes |
| D-31 | `Keys.cpp:28-31` | ladder (minor) | arity by `dyn_cast<FnType>`, 0 for a lazy carrier | a carrier type interface (`arity()`), lane 01 |
| D-32 | `Pass.cpp:138-141` | threading (keep) | per-function parallelism inside a program pass | essential: the decision is whole-program and immutable, the conversions read it; state the contract in the header |

### 4.3 Deduplication

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| U-1 | `EliminateDuplicateFunctions.cpp:91-143` | rederivation | its own symbol-use graph and its own SCCs and heights (§5.6 W-E1) | the maintained program graph with label references as edges (§5.6 Design 1) |
| U-2 | `EliminateDuplicateFunctions.cpp:140-189` | state, threading | a barrier per height: hashing waits for the classes below | one parallel hash of every body with references as slots, then a bottom-up combine of class ids (CIRCT Dedup's shape, §5.6 H5), or partition refinement (T4) |
| U-3 | `EliminateDuplicateFunctions.cpp:31-34, 142` | precision | no member of a cycle of two or more functions is ever merged | partition refinement merges cycles (MLton's `Redundant`, §5.9 F4; lld ICF, §5.3 D2); owner question (§6) |
| U-4 | `EliminateDuplicateFunctions.cpp:152-159` | cpp | the 64-bit hash truncated to 32 bits, classes bucketed in an `std::unordered_map` | the full `hash_code` in a `DenseMap` (or a sort by hash) |
| U-5 | `EliminateDuplicateFunctions.cpp:164-166` | state | a candidate is compared with each class head of its bucket | keep (output-sized with a full hash) |
| U-6 | `EliminateDuplicateFunctions.cpp:194-199` | rederivation (locations) | only the function's location is fused (0003) | fuse op by op along `BodyEqual`'s correspondence |
| U-7 | `EliminateDuplicateFunctions.cpp:206-212` | cpp | a rename-only `DataRemap` built with a leaf that always answers nothing | lane 03's API (a rename-only remap); noted |
| U-8 | `Equivalence.cpp:41-60` | upstream, W5 | each reading builds an `AttrTypeReplacer` that makes new `SymbolRefAttr`s to rename references | references compared as class ids; an upstream patch giving `OperationEquivalence` a symbol-reference hook (the generalization `PINS.md:810-815` already plans), under `upstream/<bug>/` |
| U-9 | `Equivalence.cpp:66-76` | W5 | a function's facts are read through `getPropertiesAsAttribute()` (a uniqued dictionary per call) | compare the properties with the name and `instance` cleared, as upstream DFE does (`DuplicateFunctionElimination.cpp:64-71`) |
| U-10 | `Equivalence.cpp:101-102` | W5, rederivation | per op, `getAttrDictionary()` (inherent attributes included) *and* `getPropertiesAsAttribute()` are built and hashed: inherent attributes twice, two attributes made per op, in a `parallelFor` | upstream `OperationEquivalence::computeHash` reads the raw dictionary and `hashProperties()` (`OperationSupport.cpp:731-744`) |
| U-11 | `Equivalence.cpp:143-146` | W5 | the comparison builds the same attributes on both sides per op | `compareOpProperties` (`OperationSupport.cpp:908-910`) |
| U-12 | `Equivalence.cpp:82-201` | upstream | own value and block numbering for hash and compare | upstream's `isRegionEquivalentTo` and its value cache (`OperationSupport.cpp:769-879`) once U-8's hook exists |
| U-13 | `Equivalence.cpp:44-46` | precision (note) | a data type's labels are not read through renames, so functions whose types name merged labels compare unequal until a later run | under partition refinement labels are class ids too |
| U-14 | `Specialize/Consumer.cpp:121-125` | W5 (lane 09) | raising interns consumer forms with the same `hashFunction`/`sameFunction` | inherits U-8 to U-12's fix |

### 4.4 Effects

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| E-1 | `Analysis/Effects.cpp:36-39` | state | a `SymbolTableCollection` and a whole-program `SymbolUserMap` per run, whose walk visits every label in every function type (`audits/label-solve.md` item 6) | callers from the program graph; no user map |
| E-2 | `Transforms/Effects/Effects.cpp:37-38` | rederivation | preserves only `SymbolTable` though it writes only properties, so `CallCycles` is rebuilt (0003) | preserve what it does not change (or the maintained graph) |
| E-3 | `Func.cpp:189-205` (lane 03's file, this lane's rule) | ladder, rederivation | the summary is re-derived from op classes (`isa<MayCrashOpInterface>`, `isa<WorldNewOp>`, `isa<RunsLabelsOpInterface>`) and world-typed parameters, not from the ops' declared effects: the second and third representations of "does IO" (§5.2 M1) | the join of the ops' declared memory effects (one fact, ODS) with the callees' summaries; divergence from `total` (Idris's fact) |
| E-4 | `Func.cpp:233-266` | list | a hand table from the three bits to resources, which restates the ops' ODS declarations ("as the idr.io ops declare it") | the summary held in MLIR's vocabulary (the resources' set), the call's effects generated from it; the table and the bit enum's own meaning go (lane 02 owns the resources) |
| E-5 | `Func.cpp:198-199` | rederivation | before defunctionalization an op that runs a label is "anything", though the label solve knows what it runs | effects solved once over calls and label runs, before the conversion (T3) |
| E-6 | `Analysis/Effects.cpp:49-95`; `Effects.h:48-61` | rederivation, cpp | `observableRuns` is a second summary over the same runs: its own graph, its own worklist, a `function_ref` callback | one summary solver over one run graph (T3); the callback and the function go |
| E-7 | `Analysis/Effects.cpp:66`; `IdrInterfaces.td:298-308` | ods | `ObservableIO` is a marker trait for "an effect the outside sees" | a resource of the tree (an outside child of IO, §5.2 A8, §5.8 EF2) the summary carries; the trait goes (lane 02) |
| E-8 | `Analysis/Effects.cpp:27-31`; `Func.cpp:216` | rederivation | each call's callee found by name, with an `assert` | callee ids from the program graph |
| E-9 | `Analysis/Effects.cpp:40-46` | threading | components solved serially | a wavefront over the SCC DAG (§5.1 5.1.2 item 7), if measured worth it |
| E-10 | `Effects.cpp` (Transforms); `Component.cpp:215`; `Verify/Program.cpp:61-71` | rederivation (W-E3) | one rule, three computations: the pass, the optimizer per component, the verifier after every pass | keep one rule; whether idr-effects stays a pass is §6's new question |
| E-11 | `Transforms/Effects.h:21-31`; `Analysis/Effects.h:48-61` | layout | idr-optimize's step lives in the effects directory and header; defunctionalization's by-name question lives in the effects analysis | each with its owner (the solver layer's summary file; the optimizer) |

### 4.5 Constants

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-1 | `Transforms/Effects/Constants.cpp:73-169` | upstream | upstream SCCP's static `replaceWithConstant` and `rewrite` (`mlir/lib/Transforms/SCCP.cpp:42-104`) rewritten to add actions and statistics | an upstream patch exporting the rewrite over a `RewriterBase` (a listener carries our actions); ours goes |
| C-2 | `Constants.cpp:180-185` | cpp | `std::get_if<Final>` on the ready set's `Callee` | lane 09's type, matched once (§5.5 D2) |
| C-3 | `Analysis/Constants.h:39-55` | cpp (minor) | `ConstantsOf` as a `function_ref` | a template parameter of the analysis, or the summary table passed as data |
| C-4 | `Constants.cpp:188-190` | upstream (keep) | `DeadCodeAnalysis` and SCCP per function on the framework | keep; §5.1 U1 cuts its state cost |

## 5. Target design

All *conjecture* until built and measured. The subsystem already holds the
right algorithms in most places: MLton's 0CFA with interned sets and one sum
per flow set (§3.1), a one-pass summary over the SCC DAG for effects, a
per-function upstream solve with summaries for constants. What it lacks is
the representation around them: the answer travels in pointer-keyed maps and
callbacks instead of dense ids and types; the conversion pays per function
for machinery its own plan forces; three analyses of "what a function may
do" run separately; deduplication creates attributes per op and cannot see
cycles. Seven changes, ranked by leverage.

### T1. Types first: the decision writes its answer into the types, and the conversion is one walk

- **Representation.** After `decide`, one walk per function (parallel, as
  now, reading the immutable decision) does, op by op in order: give each
  carrier result and block argument its key's sum type in place
  (`Value::setType`); give the function its converted signature; before an
  operand whose sink key differs from its value's, insert the coercion (the
  rebuild match, `Converter.cpp:48-98`, with the keys' binary-search tag
  lookup, D-23); replace a closure, suspension or delay by its constructor,
  an apply by its match, a force by its call, reading the operands' sum
  types. The driver is the walk driver (`walkAndApplyPatterns`, one
  post-order walk, op-rooted patterns, §5.2 E3) or a plain walk; the stage
  verifier at the pass's end refuses any closure op or carrier type left
  (`Verify/Program.cpp:214-219` already holds "past Higher, no labels"), which
  is where the `ConversionTarget`'s list said it before.
- **Deletes.** `Plan` (`Defunctionalize.h:99-108`, `Keys.cpp:188-214`),
  `SlotTypeConverter` (`Converter.cpp:102-184`, its materialization kept as a
  free function), `addTarget` and its legality callbacks (`Pass.cpp:56-82`),
  `RetypePattern`, the `handled` list and the per-function pattern set of one
  pattern per registered op (`Patterns.cpp:240-285`), `FuncSignaturePattern`
  (`Patterns.cpp:221-238`), pattern rollback (`Pass.cpp:97-99`), and with
  them D-1 to D-9 and D-26.
- **The line.** The plan is unrepresentable: a carrier value's key is its
  type from the moment the decision is written; the check "every value has
  its slot's type" moves to the stage boundary (the verifier); the
  per-function freeze of O(registered ops) patterns is deleted.
- **Essential case kept.** The coercion where a smaller set meets a larger
  one (MLton's `coerce`): two flow sets genuinely differ.
- **Risk.** Op accessors that `cast` a closure or lazy type
  (`ApplyOp::getCallee`'s type) must not be called on a value already
  retyped; the walk replaces each closure op before anything reads its
  result's new type, or reads only operands. Measure against today's
  conversion on stage 1 (§8).

### T2. The label solve in the solver layer: extract, solve on arrays, read back by order

- **Representation.** Shape G (§5.6 Design 1) with the S1/D3 vocabulary
  (§5.3, §5.5): each function extracted in parallel into arrays (its carrier
  values numbered in walk order from a base; parameters and results as
  (function id, index); anchors interned in one table; sources, links and
  dispatches as three arrays); the solve unchanged in algorithm (union-find,
  `SetTable`, firings) but over those ids, with each dispatch hung on its
  callee's class and checked only when that class's set grows (L-11), and a
  wave's work bounded by what changed (L-10, MLton's difference sending,
  §5.9 D2); the answer a `std::vector<SetId>` by point id, one `ArrayAttr` per
  distinct set, and a `Label`-indexed vector of functions. Readers walk each
  function in the extraction's order (no `Value` → id map), or read a
  per-function numbering cached in the `AnalysisManager` (Q-llvm-3).
  `labels-least` reads the same arrays.
- **Deletes.** `PointKey`, `ResultKey`, `keyOf` and its name lookups
  (`Labels.h:104-113`, `LabelSites.cpp:27-32, 150-163`), the `Statements`
  interface and `Builder` (`Labels.h:115-127, 235-244`), `Solution::nodes`,
  `sinks` and its `SymbolTable` reference (`Labels.h:153-174`), the per-wave
  dispatch scan (`Labels.cpp:288-298`), the per-wave SCC graph copy
  (`Labels.cpp:231-261`); L-3 to L-14, L-16.
- **The line.** A point without a dense id, and a label set read by a lookup
  that can miss, are unrepresentable; the O(W·D) scan is deleted.
- **Header** (the solver layer's rule, §4): upstream has no closure flow
  analysis and none is possible on `DataFlowSolver` (per-anchor states own
  their values, no SCC merging; `audits/label-solve.md` §2 at 77eaa5b1); the
  memory is P ids + E edges + Σ|S| over distinct sets + F firings, sized by
  the program's carriers, never by a product (§5.11 A1).

### T3. One summary of what a function may do, solved once, before the conversion, in MLIR's vocabulary

- **Representation.** The program graph (§5.6 Design 1), its edges the calls
  plus, for this one solve, the label solve's runs (an apply runs its
  callee's labels, a force its suspension's). One summary per function: the
  set of resources its ops' *declared* memory effects touch (ODS, lane 02's
  resource tree, with an outside-world child of IO for what is observable),
  joined with its callees' summaries, plus divergence from Idris's `total`;
  solved bottom-up over the SCCs in one pass (shape S, a finite lattice,
  no count). `by_name` is "the label's summary touches the outside world".
  The conversion writes every function's and call's `effects` from it, and
  gives each dispatch function the union of its labels' summaries (and the
  crash of its Running case), which is what idr-effects computes today
  after the fact.
- **Deletes.** `observableRuns` and `LabelsRun` (`Analysis/Effects.cpp:49-95`,
  `Effects.h:48-61`), `bodyEffect`'s op-class ladder and its "a label runner
  may do anything" arm (`Func.cpp:189-205`), the `ObservableIO` trait
  (`IdrInterfaces.td:298-308`), the bits-to-resources table
  (`Func.cpp:233-266`) once the summary is held as resources, the
  `SymbolUserMap` build (`Analysis/Effects.cpp:36-39`), and idr-effects as a
  separate whole-program pass (its record `Passes.td:169-188`), or what is
  left of it becomes the summary's first solve.
- **The line.** "Does IO" has one representation, the ops' declared
  effects; what a label runner may do is known, not "anything"; two solves
  of one question (observable runs, effects) become one.
- **Essential cases kept.** Divergence is Idris's `total`, not an effect any
  op declares (owner's ods-Q1/DD-Q2 decide whether it stays an effect); a
  component's members share one summary (recursion).
- **Dependencies.** Lane 02 (the resource tree, effects in ODS), lane 03
  (`CallOp::getEffects`, the `effects` property), lane 05 (the program graph,
  `CallCycles`), lane 09 (idr-optimize recomputes a component's summary by
  the same rule as bodies change).

### T4. Deduplication as partition refinement over upstream's equivalence

- **Representation.** Every body hashed once, all in parallel, by upstream's
  `OperationEquivalence::computeHash` (raw dictionary and `hashProperties`,
  no attribute made) with each symbol reference hashed as a slot; an initial
  partition by (facts, shape hash); refinement: a class splits by the tuple
  of the classes its members' references name, labels in data types
  included; stop when no class splits (a partition only refines, so at most
  n rounds, by construction, no budget); each final class confirmed by
  `isRegionEquivalentTo` with references mapped through class ids. One
  `DataRemap` renames, as now. This is MLton's `Redundant` (§5.9 F4) and
  lld's ICF (§5.3 D2, double-buffered class ids if run in parallel).
  Second choice, if merging cycles is unwanted: CIRCT Dedup's shape (one
  parallel hash with references as slots, then a bottom-up combine of class
  ids, §5.6 H5), which keeps today's cycle exclusion and drops the barrier.
- **Upstream.** `OperationEquivalence` takes no hook for symbol references;
  the patch adding one (with its test and plan, `upstream/<bug>/`) is the
  generalization `PINS.md:810-815` names as the port's retirement, and
  upstream's `duplicate-function-elimination` on `FunctionOpInterface` could
  then run transitively.
- **Deletes.** Heights and waves (`EliminateDuplicateFunctions.cpp:122-189`),
  the cycle exclusion (`:142`), `Reading`/`AttrTypeReplacer`, `BodyHash`,
  `BodyEqual`, `factsOf`'s dictionary (`Equivalence.cpp:41-201`), the 32-bit
  truncation; U-1 to U-5, U-8 to U-13 (and U-14 for raising).
- **The line.** Duplicate mutually recursive functions become mergeable; the
  per-height barrier and every attribute made per op are deleted.

### T5. One remap per defunctionalization

- **Representation.** The boxes decided from the type graph of the
  decision's sums and the program's types before the remap, and handed to
  the one `DataRemap::create(program, "defun", leaf, boxes)`
  (`Symbols.h:183-185`); the "largest boxed sum" statistic read off that
  decision.
- **Deletes.** `layout::fit`'s second remap and `TypeGraph` in this pass
  (`Pass.cpp:144-147`), the statistic's `TypeGraph` (`Pass.cpp:150-158`):
  D-12, D-13.
- **The line.** Two whole-program retypes and three `TypeGraph` walks per run
  become one retype and one walk.

### T6. The closed set of constant parts, answered once

- **Representation.** Whether a constant part holds a closure is a property
  `ConAttr` computes when it is made (lane 01), and one visitor over the
  closed set of parts (closure, constructor, other) serves the reading, the
  conversion and the statics; the frontend states a static suspension
  instead of the pass counting captures (lane 14/15).
- **Deletes.** `ClosureParts` (`Labels.h:63-72`, `Labels.cpp:43-55`), the
  constant legality walk (`Pass.cpp:74-80`), the statics walk's arithmetic
  (`Pass.cpp:116-127`); L-2, D-8, D-11, D-21.
- **The line.** Five readings of one recursive fact become one stored fact.

### T7. The C++ that remains

`SumId` handles minted by `decide` (D-16); typed body views from lane 01 so
no `std::get`, `get_if` or catch-all reads a role (D-20, D-24); the
`by_name` predicate as data (D-10); `ConstantsOf` as a template parameter or
a table (C-3); upstream SCCP's rewrite exported over a `RewriterBase`, our
actions as a listener (C-1, an `upstream/` patch); `carriesLabels` as one
fact on `Carriers` (L-1); the pass record's description corrected (L-17).

### Order and dependencies

1. T6 and L-1 (small; lane 01's `ConAttr`, lane 02's `Carriers`).
2. T2 (the solver layer's ids and graph, the coordinator's S1/shape G
   decision; the program graph, §5.6 Design 1).
3. T1 with T5 (needs T2's read-back or the current `Solution`; lane 01's
   typed bodies, lane 03's stage verifier).
4. T3 (lane 02's resources, lane 03's call effects, lane 05's graph, T2's run
   edges; lane 09 adopts the same summary).
5. T4 (independent; the upstream patch first).
6. T7 throughout.

### What belongs in the solver layer

The label solve (a set domain over a dynamic inclusion graph: shape G, its
own solver, honestly named); the summary of effects and observability
(shape S over the program graph's SCC DAG, one schedule for both
directions, Q-M1); deduplication's partition refinement (a partition
solver, the same graph). idr-constants stays where it is: upstream's
framework per function with summaries (shape L, §5.1 Design 1), patched for
state cost (§5.1 U1).

## 6. Evidence for the owner's questions

No answers: what our code says, by ID (all *read* unless marked).

**Q-O4 (polyvariance before the label solve?).**
- The order is deduplicate, defunctionalize, knots, effects, contify,
  optimize (`Pipeline.cpp:66-82`); specialization runs inside idr-optimize,
  after every closure is a constructor.
- The solve has one point per function parameter and per result
  (`LabelSites.cpp:27-32`, `Labels.h:108`), so every call site of a function
  feeds one set; `tests/defunc-coerce/defunc-coerce.mlir:3,14-20` states it:
  `@Main.use`'s argument holds `[@Main.add, @Main.inc]` from two calls, and
  each call rebuilds its singleton into the union's sum (`Converter.cpp:48-98`),
  a match per coercion at run time, and the apply inside is a two-case match
  (`Patterns.cpp:92-177`).
- Anchors are per type: closures stored in one constructor field share one
  set program-wide (`FlowEdges.h:88-93`), and every suspension of one lazy type
  returns into one forced set (`FlowOps.cpp:154-158, 168-171`). Polyvariance
  over functions does not split these; only the frontend's monomorphized
  types do.
- Interaction with deduplication: polyvariant copies of a higher-order
  function have identical bodies, so idr-deduplicate would merge them back;
  it runs first today ("so the label sets are made over fewer functions",
  `Pipeline.cpp:63-65`), so a polyvariance step fits between it and
  defunctionalize and never before it.
- Measurement available once built: the pass's statistics `sums`,
  `constructors` and `largestBoxedSum` (`Passes.td:161-166`, `Pass.cpp:147-158`)
  on stage 1, with and without such a step. Whether idr-optimize's
  specialization recovers per-site precision (folds an apply's match on a
  known constructor) is lane 09's evidence (§5.9 Q-W5).

**Q-E4 (port from CIRCT and IREE?).**
- Our hashing is already parallel inside a height
  (`EliminateDuplicateFunctions.cpp:151-155`), but each hash reads the renames
  of the heights below (`Equivalence.cpp:41-60, 207-216`), hence the barrier;
  CIRCT Dedup hashes references as placeholders and combines afterwards
  (§5.6 H5), which removes that dependency. What transfers is that shape,
  a few dozen lines; its FIRRTL specifics do not.
- A maintained call graph (`InstanceGraph`'s shape) would be kept by the
  passes here that change calls: idr-deduplicate (renames, erases,
  `:202-224`), idr-defunctionalize (adds a dispatch function per memo sum and a
  call per apply case and per force, `Declare.cpp:93-100`,
  `Patterns.cpp:161-162, 190-191`); idr-effects changes none.
- The Apache-2.0 header and the PIN marker of a port are kept as in
  `EliminateDuplicateFunctions.cpp:1-15`; its `PINS.md` entry
  (`:786-815`) is the model.

**Q-M4 (port more of Modular, or rewrite?).**
- Of Modular's `EliminateDuplicateFunctions`, the port keeps the header, the
  lexicographically smallest member kept (`:177-182`) and parallel collection
  of uses (`:100-111`); AsyncRT's chains became waves by height (`:140-189`),
  the set under a mutex became serial class formation (`:159-173`), and the
  comparison is ours (`Equivalence.cpp`). Little of the original remains;
  T4 would retire the port.
- `SCCGraph`'s clients in this subsystem: idr-effects (callees first, over
  `CallCycles`, serial, `Analysis/Effects.cpp:40-46`), `observableRuns`
  (callers first, its own graph, `:79-93`), the deduplicator's heights
  (callees first, its own SCCs, `:122-143`).

**Q-O2 (a constraint-generating interpreter as *the* solver layer).**
- The label solve already is cells over SSA values and type-shaped anchors,
  flow-insensitive, merged by union-find, sets interned (`Labels.h:176-279`),
  no program points; it differs from MLton in solving by waves, not handlers
  (`Labels.cpp:213-300`), and it pays O(W·D) and O(W·(P+E)) for it (L-10,
  L-11).
- Effects is a one-pass summary over the SCC DAG (`Analysis/Effects.cpp:36-47`)
  and `observableRuns` a two-point mark (`:85-94`): both already in the model.
- The one `DataFlowSolver` user here, idr-constants, is per function and
  intraprocedural with summaries (`Constants.cpp:186-191`): Q-O2's "kept
  only for intraprocedural analyses whose state fits".

**Q-O3 (facts into types).** The label solve's answer reaches the types only
when each function's conversion ends; in between it is copied into three
maps per function (`Defunctionalize.h:99-108`), which forces pattern
rollback (`Pass.cpp:84-86`). T1 is Q-O3 inside the pass. `by_name` already
lives in the type's body (`IdrDialect.h:156-160`).

**Q-E2 and DD-Q7 (where a summary lives; our own function op).** Effects
live in the IR today: the `effects` property of `idr.func` and of each
`idr.call` (`IdrOps.td:162-163, 219-220`), each call checked to contain its
callee's in `verifySymbolUses` (`Call.cpp:52-57`), each function's coverage
checked by the program verifier after every pass (`Verify/Program.cpp:61-71`),
rewritten by idr-optimize as bodies change (`Component.cpp:215`); the cost is
that every pass changing a body or a call keeps them right (idr-contracts
writes them for tests, `Contracts.cpp:196-246`). They reach no LLVM attribute
(0003, target lane).

**Q-M1, Q-E1 (one schedule, one program graph).** Three summaries here would
share one graph: references (dedup, labels included), calls (effects), calls
plus label runs (observability, and T3's effects).

**QA4, QL1, Q-llvm-3 (one state representation, dense numbering).** The solve
uses typed dense ids inside (`Node`, `Label`, `SetId`, `Dispatch`,
`Labels.h:76-87`) and pointer-keyed maps at its edges (`Labels.h:169-171`,
`Defunctionalize.h:105-107`); T2 extends the ids to the edges.

**QL3 (rules or transfer functions).** The label solve's reading is already
rules as data (source, link, dispatch, and the firing rule, `Labels.h:115-140`)
read by two engines, the solve and the `labels-least` oracle
(`LabelsLeast.cpp:34-102`).

**Q-llvm-2, Q-E3, oom-2 (budgets).** None here: no budget, count or cap in
the twenty files (§3.2 W-E5). Defunctionalization refuses nothing
(`Pass.cpp:7-9`), acceptance rests on it, so its cost must be bounded by
construction; today's worst case is O(W·(P+E) + W·D) in the solve and
functions × registered ops in the conversion's pattern sets (D-3).

**ods-Q1, DD-Q2 (divergence).** The `diverge` bit is "not `total`"
(`Func.cpp:190`), Idris's fact; a dispatch function is made `total`
(`Forces.cpp:73-78`) though its Running case crashes (`Forces.cpp:135-137`).

**DD-Q3 (the world).** IO is found by world-typed parameters and
`idr.world.new` (`Func.cpp:191-197`), so the world value is how effects see IO
today; DS2.1 would leave the ops' declared effects as the only source, which
is T3's summary.

**Q-llvm-7 (the giant SCC).** The deduplicator merges no member of a cycle
of two or more functions (`EliminateDuplicateFunctions.cpp:142`), and every
member of a component gets one effects summary (`Analysis/Effects.cpp:41-46`):
a giant SCC in stage 1 would hold every duplicate inside it and share one
effect set.

### New questions for the owner

- **NQ-defunc-1. Deduplication across cycles.** Partition refinement (T4)
  merges duplicates inside call-graph cycles, which today's pass never does
  (`EliminateDuplicateFunctions.cpp:142`); it changes which functions survive
  and where their locations point. Adopt it, or keep the exclusion with
  CIRCT's barrier-free hashing?
- **NQ-defunc-2. Effects before the conversion.** Fold idr-effects into
  defunctionalization's decision (T3), one summary over calls and label runs
  that also decides `by_name`, idr-optimize keeping it current; or keep a
  separate pass after the conversion?
- **NQ-defunc-3. Types first (T1).** Replace the per-function dialect
  conversion by one walk that writes the decision into the types, legality
  checked by the stage verifier, though the skill names
  `TypeConverter`/`ConversionTarget` for lowering? The types here depend on
  the value (its flow set), not the type, which is why the pass keeps a plan
  per function today.
- **NQ-defunc-4. One sink per operand.** A use that moves into two points
  unifies them (`LabelSites.cpp:106-110`), coarsening both sets so the plan
  holds one key per use. Keep, or let the operand be coerced into each sink?

## 7. Deletion list

By the change that deletes it (§5); *conjecture* until built.

- **T1** — `include/idr/Transforms/Defunctionalize.h`: `struct Plan`,
  `class SlotTypeConverter` (its `coerce` kept as a free function over keys),
  `SlotPattern`, `populateDefunctionalizePatterns`'s `RetypePattern` loop,
  `populateCallOpTypeConversionPattern`, `populateReturnOpTypeConversionPattern`
  (their bodies become walk steps); `Slots::plan`. `Pass.cpp`: `addTarget`,
  `convert`'s converter, target, per-function `RewritePatternSet`,
  `ConversionConfig` (rollback). `Converter.cpp`: `SlotTypeConverter`'s
  constructor, `typeOf`, `keyOf`, `sinkKey`, `legal`. `Patterns.cpp`:
  `RetypePattern`, `FuncSignaturePattern`, the `handled` array.
  `PatternsCalls.cpp`: the file (its moves become walk steps).
  `idr/Support/Remake.h`'s `remakeOp` stays: it has five other users
  (*measured*: `grep -rn 'remakeOp('`: Raise, Trmc, Columns' ArrayOps, Calls,
  Tensors, Columns.h).
- **T2** — `include/idr/Analysis/Labels.h`: `PointKey`, `ResultKey`, `keyOf`,
  `class Statements`, `Graph::Builder`, `Solution::nodes`, `Solution::sinks`,
  `Solution::table`, `Solution::function`, `Labels::labelsAt` (by key).
  `LabelSites.cpp`: `parameterValue`, `keyOf`, `Graph::nodeOf` by key,
  `Graph::Builder::*`. `Labels.cpp`: the per-wave dispatch loop
  (`:288-298`), the per-wave `vertexOf`/`edges`/`seen` copies (`:216-245`).
  `lib/Transforms/Expect/LabelsLeast.cpp`'s `Derivation : Statements`
  (reads the arrays instead).
- **T3** — `include/idr/Analysis/Effects.h`: `LabelsRun`, `observableRuns`;
  `lib/Analysis/Effects.cpp`: `observableRuns`, `solveEffects`'s
  `SymbolUserMap`; `lib/Transforms/Effects/Effects.cpp` and the `IdrEffects`
  record (`Passes.td:169-188`) if the summary's first solve moves into
  defunctionalization (NQ-defunc-2); `lib/IR/Func/Func.cpp`: `bodyEffect`'s
  `isa` arms and its `RunsLabelsOpInterface` arm, the `rows` table and
  `effectInstances` once the summary is held as resources (lane 02, lane 03);
  `Idr_ObservableIO` (`IdrInterfaces.td:298-308`) and `ObservableIO`
  (`include/idr/IR/Traits.h:62-67`); `Pass.cpp:110-115`'s callback and the
  `byName` `function_ref` parameters (`Defunctionalize.h:125-127, 188-195`).
- **T4** — `lib/Transforms/Deduplicate/Equivalence.cpp`: `Reading`,
  `factsOf`, `BodyHash`, `BodyEqual` (upstream's `OperationEquivalence` with
  the patched hook); `EliminateDuplicateFunctions.cpp`: `componentOf`,
  `height`, `byHeight`, the cycle exclusion, `std::unordered_map`, the 32-bit
  truncation, the Modular header and `PIN(eliminate-duplicate-functions)`
  with its `PINS.md` entry (a fresh implementation retires the port).
- **T5** — `Pass.cpp:144-147`'s `layout::fit` call (the boxes go into the one
  remap) and `Pass.cpp:150-158`'s `TypeGraph`.
- **T6** — `ClosureParts` (`Labels.h:63-72`, `Labels.cpp:43-55`) and every
  member holding one (`LabelSites.cpp:55`, `Defunctionalize.h:230`); the
  `ConstantOp` legality walk (`Pass.cpp:74-80`); the statics' capture count
  (`Pass.cpp:116-127`) if the frontend states it.
- **T7** — `assert`s and `.at()`s replaced by `SumId` handles
  (`Keys.cpp:135`, `Declare.cpp:53, 58, 64`); `std::get<role::Label>`
  (`Converter.cpp:54`, `Patterns.cpp:128`), `std::get_if<role::Label>`
  (`Forces.cpp:62`) and the catch-all arm (`Forces.cpp:144-150`) with lane 01's
  typed views; `holdsLabels` (`Flow.cpp:90-92`) or `carriesLabels`
  (`Labels.h:59-61`), one of them; `idr/lib/Transforms/Effects/Constants.cpp`'s
  `replaceWithConstant` and `Rewrite` (upstream's, patched); the stale
  description in `Passes.td:127`.

## 8. Risks, unknowns, measurements needed

No compiler is built in this checkout, so every cost below is *conjecture*
from the code until measured on stage 1.

**Risks, the largest first.**
1. **D-3, the per-function pattern set.** Every one of some 70,000 functions
   builds a `RewritePatternSet` holding one `RetypePattern` per registered op
   of the context and freezes it in `applyFullConversion`
   (`Pass.cpp:87-100`, `Patterns.cpp:282-284`; the freeze is the implicit
   `FrozenRewritePatternSet(RewritePatternSet &&)`,
   `mlir/include/mlir/Rewrite/FrozenRewritePatternSet.h:50`, *read*), closure
   or not. With LLVM,
   linalg, vector, transform, affine and the rest registered
   (`Register.cpp:75-86`) that is plausibly hundreds to over a thousand
   pattern objects and one freeze per function: a candidate for §3's next
   wall, in a pass acceptance rests on. Measure first:
   `ctx->getRegisteredOperations().size()` in the compiler's context, and
   the time and allocations of `convert` per function (a Tracy zone).
2. **The label solve's waves** (L-10, L-11): W·D dispatch checks and W
   re-sweeps of downstream classes. W is the length of the longest chain of
   "a firing adds an edge that reaches another dispatch", unknown on stage 1;
   `defunc-tag-limit` has W = 1 (`audits/label-solve.md` §3 at 77eaa5b1), so
   the fixture does not exercise it. A program whose continuations are
   applied by functions passed as continuations (CPS, monadic code) is the
   case to measure.
3. **Attributes made per op in dedup** (U-9 to U-11): two uniqued
   dictionaries per op per hash and per side of each compare, made from worker
   threads, each taking the context's uniquer locks and living for the whole
   compile (§5.1 F3). Measure dedup's time against its thread count, and the
   allocator's growth over the pass.
4. **T1's in-place retyping**: an op accessor that casts a closure or lazy
   type, called after its operand was retyped, would assert; the walk must
   replace each closure op from its operands and the decision alone. The
   fixtures `defunc-*` (22, *measured*: `ls tests | grep -c '^defunc-'`) and
   their `%differential` runs are the behaviour check.
5. **T3's equivalence**: effects read from declared memory effects must give
   the bits today's rule gives on every fixture that states them (the 16
   `effects-*` fixtures, *measured*: `ls tests | grep -c '^effects-'`, and
   `--idr-expect=effects`), and `by_name` must stay exactly where
   `observableRuns` puts it (`effects-memo-label`, `defunc-memo-by-name`);
   "a crash writes the IO resource" (`Func.cpp:253-254`) must become the
   resource tree's ordering (ods-Q3).
6. **T4 changes outputs**: merging cycles changes which name survives and
   where locations point; refinement rounds are at most the number of
   functions, each over every reference: measure the rounds on stage 1.
7. **Precision trades left as they are**: a use with two sinks unifies them
   (L-15); forced state and fields are per type (§6 Q-O4); one sum per flow
   set costs a coercion match where sets meet, against one dispatch per type
   (Danvy-Nielsen's grouping, §5.9 I1): code size and run time unmeasured.

**Unknowns.**
- Where stage 1's largest matches come from (§5.9 Q-W1): whether the
  frontend's IO and monadic code reaches defunctionalization as closures
  whose continuations merge at one higher-order function's parameter is
  lane 15's (how `Emit/Closures.idr` and the translation produce
  `idr.closure`).
- How much of idr-effects' answer idr-optimize overwrites anyway
  (`Component.cpp:215`), which decides NQ-defunc-2.
- Whether every data type the decision must key is in the program's table
  (D-14's premise; b9d4d592 says the table holds every body once).

**Measurements needed, on stage 1, once built.**
- `idris-mlir-opt --idr-defunctionalize --mlir-pass-statistics
  --mlir-timing`: `sums`, `constructors`, `largestBoxedSum`, `boxed`, and the
  pass's time; Tracy zones around `readProgram`, `Graph::solve`, `decide`,
  each `convert`, `remake`, `layout::fit`.
- Counters for the solve (§5.9 Design 6): P, E, D, F, W, classes taken per
  wave, distinct sets, Σ|S|, the largest set.
- idr-deduplicate: heights, functions per height, time per height (the
  barrier's idle time, §5.4's wave-2 question), groups merged.
- idr-effects: the `SymbolUserMap` build against the solve; idr-optimize's
  recomputation count.
- The program verifier's `effectsCovered` per pass (`Verify/Program.cpp:61-71`),
  a whole-program body walk after every pass (lane 13's verifier budget).

## 9. Sources read

**Instructions and proposals, in full.** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0000-mlir-native.md` (§0-§4, every lane of §5 in
order: 5.1 mlir-analysis, 5.2 mlir-ods, 5.3 llvm, 5.4 modular, 5.5 cxx26,
5.6 ecosystem, 5.7 library, 5.8 dialect-design, 5.9 mlton, 5.10 rc, 5.11 oom
(its findings by search for this subsystem's terms, its 5.11.2-5.11.5 in
full), §6-§9); `proposals/0003-facts-once.md`; `audits/p0/README.md`.

**The subsystem, line by line.** `foreign/idr/include/idr/Analysis/Labels.h`;
`lib/Analysis/Labels.cpp`, `LabelSites.cpp`;
`include/idr/Transforms/Defunctionalize.h`;
`lib/Transforms/Defunctionalize/{Pass,Decide,Keys,Moves,Declare,Converter,Patterns,PatternsCalls,Forces}.cpp`;
`include/idr/Transforms/Deduplicate.h`;
`lib/Transforms/Deduplicate/{EliminateDuplicateFunctions,Equivalence}.cpp`;
`include/idr/Transforms/Effects.h`; `lib/Transforms/Effects/{Effects,Constants}.cpp`;
`include/idr/Analysis/{Effects,Constants}.h`; `lib/Analysis/{Effects,Constants}.cpp`.

**What it reads, in the parts cited.** `include/idr/IR/FlowEdges.h` (whole),
`include/idr/IR/Flow.h` (whole), `lib/IR/Flow.cpp:42-140, 270-335`,
`lib/IR/FlowOps.cpp:1-200`, `include/idr/IR/IdrFlow.td` (whole),
`include/idr/IR/IdrInterfaces.td:174-195, 280-320`, `include/idr/IR/Func.h:1-80`,
`lib/IR/Func/Func.cpp:140-300`, `lib/IR/Func/Call.cpp:1-100`,
`include/idr/IR/TypeGraph.h` (whole), `lib/IR/TypeGraph.cpp:1-80`,
`lib/IR/Layout/Fit.cpp` (whole), `include/idr/IR/Symbols.h:101-324`,
`include/idr/IR/IdrDialect.h:140-220`, `include/idr/IR/IdrBase.td:115-135`,
`include/idr/IR/IdrOps.td` (the `effects` properties, by search),
`include/idr/Support/Scc.h`, `lib/Support/Scc.cpp`,
`include/idr/Support/Worklist.h:1-60`, `include/idr/Support/Remake.h` (by
search), `include/idr/Transforms/Passes.td:1-210`,
`include/idr/Transforms/InnerPasses.td:61-71`, `lib/Transforms/Pipeline.cpp:50-100`,
`lib/Transforms/Expect/LabelsLeast.cpp:1-140`,
`lib/Transforms/Expect/SolvedEffects.cpp`, `lib/IR/Verify/Program.cpp:40-80`,
`lib/Transforms/Optimize/Component.cpp:200-230`, `lib/Driver/Register.cpp:60-100`,
`lib/Transforms/Specialize/Consumer.cpp` (its use of the dedup helpers, by
search); `tests/defunc-coerce/defunc-coerce.mlir`; the `tests/` listing;
`compiler/src/IdrisMLIR/Emit/Closures.idr:1-40` (header only); `PINS.md:780-815`.

**Upstream, at the pin.** `.toolchain/llvm-project/mlir/lib/Transforms/SCCP.cpp:30-110`;
`mlir/lib/IR/OperationSupport.cpp:725-760, 765-910`;
`mlir/lib/IR/Operation.cpp:285-352`;
`mlir/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:1-80`.

**History.** `git log --oneline` of the label solve's files (10 commits), of
`Defunctionalize/` (16), of `Deduplicate/` (7), of the effects and constants
files; `git show` of 7adc6095 (the interned-set solve), 73bba53f (the
843 s table rebuild), 234b81a0 (dedup's first version), 0a884489
(idr-optimize's call effects without a whole-program map), 8e2fbec7 (the
dispatch's locations); `audits/label-solve.md` at 77eaa5b1 (whole).

**Commands for the measurements.** `wc -l` over the twenty files (§2.1);
`grep -c -F` per pattern over them (§2.1); `grep -rn
'getAnalysis<idr::Labels>'`; `grep -rn ObservableIO foreign/idr/lib`; `grep
-rn 'remakeOp('`; `grep -c -e mutex -e atomic` over the twenty files (0);
`grep -n -i -w -e budget -e limit -e cap -e maxIter -e threshold` over them
(none); `ls tests | grep -c '^defunc-'` (22) and `'^effects-'` (16).
