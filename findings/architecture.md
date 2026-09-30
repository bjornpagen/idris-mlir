# Architecture: the optimizer's frame, its global maximum, and the path

Stream "architecture". The question: is idris-mlir's optimizer architecture
the right frame for whole-program, rich-data optimization far more
aggressive than MLton's, and what should change?

The file has three parts:

- **the global maximum** (the target);
- **the path** to it (ordered, with what each step deletes);
- **the six answers with their evidence.**

Experiments, commands and IR excerpts are in
`findings/architecture-experiments.md`.

This file builds on the other streams and does not repeat them:
- `mlir-idioms.md`: MLIR mechanisms we duplicate or misuse;
- `mlir-ownership-types.md` and `memory-theory.md` §6: the owned stage and
  uniqueness as types;
- `representation.md`: Nat, Fin, packing, `Vect` as tensor or vector;
- `facts-ledger.md`: where each Idris fact is lost.

It adds the frame they fit into: how facts are produced and consumed, how
transformations are ordered and why they terminate, which MLIR machinery
does the work, and where the measured failures come from.

Status of claims:
- **measured**: I ran it;
- **read**: a file:line, or a paper section;
- **conjecture**: my judgment, untested.

## The questions

1. Which hand-written analyses should become MLIR dataflow lattices (escape,
   binding times, facts inference, ranges for Int/Nat/Fin)?
2. Should the simplify group be equality saturation? An honest cost and
   benefit, with the phase-ordering history as evidence.
3. Whole-program optimization beyond MLton: what MLton does, and what Idris
   facts make possible.
4. What LLVM should receive from Idris facts, against what it receives today
   (actual IR).
5. Is translation validation or verified rewriting feasible as a safety net?
6. A proposed architecture, as data.

## Verdict

The outer frame is right, and parts of it are ahead of MLton:
- the whole program is compiled at once;
- quantities are types, re-verified after every pass;
- compile-time evaluation runs the program's own lowered code;
- closure analysis already runs on MLIR's DataFlow framework;
- the owned stage has its own verifier.

The inner frame is where the ceiling is:
- **Facts are produced ad hoc, several times, and weaker than Idris knew
  them.** There are six hand-written fixpoints and a weak duplicate of the
  label analysis. The range interfaces are run by no pipeline step.
  Size-change graphs, Nat arithmetic, case blocks as continuations, and
  proofs are all dropped before MLIR.
- **The simplify loop ends because an IR hash stops changing.** Every
  blow-up in the history was patched with a budget.
- **MLIR is used as a slightly better LLVM IR.** Our own passes do what
  MLIR's solver, interfaces, canonicalizer, bufferization and loop
  dialects would do.
- **The transformations that matter most are missing.** Two failures are
  measured:
  - Nat arithmetic is quadratic: 39 s where Chez takes 0.1 s;
  - a non-tail `map` over 400k elements segfaults.

Equality saturation is not the fix. MLIR's DataFlow solver, with
cooperating lattices, already is the "egglog half" worth having.

---

## Part I. The global maximum

One sentence: **Idris states every proved fact as IR structure. One MLIR
DataFlowSolver of cooperating lattices infers the rest. Transformations are
MLIR patterns, interfaces and upstream passes, each declared by the facts it
consumes. Expanding decisions grow a finite lattice, so compilation
terminates by construction. Array code leaves `idr` for
tensor → bufferization → memref → linalg/affine/vector, so MLIR's own
optimizers run on Idris programs. Every fact that a transformation relies on
is checked locally by a verifier.**

### I.1 The IR stack: the fact is in the type

| Level | What lives there | Facts carried structurally | Owner |
|---|---|---|---|
| **Idris** (compiler/) | checking, monomorphisation, representation choice | proves everything below; drops nothing | Idris |
| **idr, value stage** | identified recursive data types (mlir-idioms 1.5); `!idr.nat`; `Fin n`/small Nat as `index` with ranges; `Vect 3 Double` as `vector<3xf64>` (representation.md); `!idr.lin`/`!idr.erased`; ghost values for erased indices and proofs; `!idr.fn` carrying effects and totality (mlir-idioms 5.5); `idr.match`/`match_lit` binding the refined scrutinee (SSI); **join points** in place of case-block functions | quantity, totality, effects, size-change (on recursive calls), ranges by type, coverage (no default region when Idris proved the match complete) | Emit, then the `idr` passes |
| **array stage** | `tensor<…>` + `linalg` for `Vect`s whose contiguity is proved (representation.md, "three proofs"); upstream `vector` | shapes are types; `tensor.dim` is the ghost `n` | MLIR upstream |
| **owned stage** | `!idr.own`/`!idr.uniq`/`!idr.borrow`/`!idr.cell<N>` (memory-theory §6.2, mlir-ownership-types); `memref` after One-Shot Bufferize; frame cells as `alloca`-like ops (mlir-idioms 3.2) | ownership, uniqueness, frame-locality, all as types | `idr` passes plus bufferization |
| **loops** | `scf.for` (counted recursion, raised by `populateUpliftWhileToForPatterns`, pinned: `SCF/Transforms/Patterns.h:81`); `scf.while` for the rest; `affine` where bounds are affine | trip counts from size-change plus Nat | MLIR upstream |
| **LLVM** | `llvm` dialect with `nonnull`/`dereferenceable`/`align`/`range`/`noalias`/`will_return`/`invariant.group` (mlir-idioms 6.3) | every fact that survived, turned into its LLVM form; an `idr.*` attribute left over is an error | `idr-lower` |

### I.2 Facts: one solver, cooperating lattices, one producer each

MLIR's `DataFlowSolver` runs all loaded analyses to a joint fixpoint, and an
analysis may read another's state with dependency tracking. SCCP and
DeadCodeAnalysis already cooperate this way, and IntegerRangeAnalysis
depends on DeadCodeAnalysis (`IntegerRangeAnalysis.h`: "a silent no-op if
DeadCodeAnalysis is not loaded"). That is what egglog claims for Datalog
("cooperating analyses, and lattice-based reasoning",
`zhang-2023-egglog/abstract.tex`), without an e-graph.

| Fact | Lattice | MLIR mechanism | Replaces (file:line) | Consumers |
|---|---|---|---|---|
| Reachability | executable/dead | upstream `DeadCodeAnalysis` | the analysis half of `idr-prune` | prune; every other analysis |
| Constants and **shapes** (partially static values) | ⊥ / const / `ctor C[v…]` / `closure f[v…]` / ⊤, with depth widening (Lean's `maxValueDepth = 8`, `ElimDeadBranches.lean:21-43,141-175`) | a sparse forward analysis with `FieldAnchor`s; the idr folders give constants, as SCCP's do | `Pattern.cc`'s syntactic walk (`shapeOf`), the profitability oracle `Meet.cc:13-31`, `idr-prune`'s special cases | known-case, specialize keys, eval closedness, join-point copies |
| Closure labels | sets of labels, ⊤ | already sparse forward, interprocedural (`Defunctionalize.cc:234-392`) | `Facts/Closures/Passed.cc:34-70`; `Stack/Recursion.cc:24-46` ("an apply calls every address-taken function") | defunctionalize, effects, escape, recursion |
| Integer ranges | `IntegerValueRange` (widening at the pin) | upstream `IntegerRangeAnalysis`, subclassed: `setToEntryState` seeded from types (Nat ≥ 0, `Fin n`, Char, tags); `visitNonControlFlowArguments` for `match_lit` case arguments | nothing (none runs today); `knownNonZero`, which reads constants only (`Ops.cc:20-29`) | `populateIntRangeOptimizationsPatterns(patterns, solver)` (mlir-idioms 6.1); crash causes; bounds; LLVM `range` |
| Effects (io, crash) per function | 4-point lattice on callables | a callable-anchored state in the same solver, reading labels at applies; exposed as `MemoryEffects` with the resource hierarchy (mlir-idioms 3.4) and an external model on `func.call` | `Facts/Infer/Infer.cc:78-88`; the isa chain in `Facts/Moves/Only.cc:16-41`; `RemoveUnusedCall` | upstream `cse`, `loop-invariant-code-motion`, `remove-dead-values` on pure calls; eval; raise |
| Escape | none < contents < reference | sparse **backward**, interprocedural, shaped like upstream `LivenessAnalysis` (`LivenessAnalysis.h:78`) | `Stack/Escape.cc:70-99` (summary worklist), `:112-147` (reversed-graph reachability), `forwardsOf :56` (framework forwarding rebuilt by hand) | frame cells, uniqueness |
| Useful fields | useless/useful per (data, ctor, field) | sparse backward with `FieldAnchor`s | nothing (MLton's `useless`) | useless-field and unused-constructor removal (representation.md R7) |
| Uniqueness | unique/shared | inferred over the call graph; **carried as a type** in the owned stage (memory-theory §6.4) | the runtime test at every reset (`ResetReuse.cc:19-25`) | reset without a test, TRMC, One-Shot Bufferize's `writable` arguments, `noalias` |
| Size-change | per recursive call: argument relation {<, =, ?} | **from Idris** (`GlobalDef.sizeChange`), emitted on the call; composed through inlining and cloning | `BindingTimes.cc:66-85,190-215` (abstract interpretation), and its hack `:121-126` | binding times, `scf.for` raising, branch weights, stack budgets |
| Continuations | per function: its one continuation, or none (Fluet & Weeks) | the **frontend** knows it: case blocks are continuations by construction; contify for the rest | nothing; and the pinned inliner's A→B→A refusal (`Inliner.cpp:709-715`) blocks inlining instead | join points; reuse within one function |
| Borrowed parameters | owned/borrowed | kept (Lean's algorithm, `Borrow.cc`); the result becomes a type (memory-theory §6.2) | nothing | rc |

**Rule R1 (where a fact lives).**
- A fact whose loss would be **unsound** lives in a type or an inherent op
  property, and a **local** verifier rule checks it after every pass. The
  global lattice only produces it:
  - quantity (exists);
  - uniqueness: every call site passes a unique value;
  - frame-locality: a frame value reaches no return, capture or heap
    field;
  - borrowedness;
  - a size-change edge: the argument passed is a field or predecessor of
    the parameter.
- A fact whose loss only **costs speed** may be discardable (totality).
- A fact that **cannot be checked locally** (ranges, shapes) is never
  stored. Its consumer rewrites the IR into an op that cannot express the
  bad state: "parse, don't validate". A division proved non-zero becomes
  `arith.divsi`, and a case proved impossible is deleted.

This is CompCert's "verified validator" shape (`leroy-2009-compcert` §2.2):
the checker is smaller than the transformation.

### I.3 Transformations: declared by what they consume, MLIR-native where possible

| Transformation | Consumes | Kind | Mechanism |
|---|---|---|---|
| folds, known constructor, field/tag of con, output fusion | shapes, constants | shrink | upstream **canonicalize**, with only convergent local patterns (MLIR's own contract, `docs/Canonicalization.md:44-60`); `createCanonicalizerPass` with a listener in place of our copy (mlir-idioms §2) |
| range rewrites | ranges | shrink | `populateIntRangeOptimizationsPatterns` with our solver |
| DCE, CSE, LICM of pure calls | effects via `MemoryEffects` | shrink | upstream `remove-dead-values`, `cse`, `loop-invariant-code-motion`, `symbol-dce` |
| prune dead regions | reachability, shapes | shrink | patterns over solver state |
| contify | continuations | shrink (removes a function) | Emit writes case blocks as regions or join points; a contify pass for the rest |
| join-point specialization (replaces case-of-case copying and `Sink.cc`) | shapes at each jump | expand (decision) | a jump whose argument's shape makes the join body fold gets its own copy, at most one per (join, constructor) |
| inline | size, loop breakers | expand (decision) | upstream `Inliner` with MLton's rule as the profitability callback (exists) |
| specialize | shapes, size-change | expand (decision) | the clone table (exists), with keys from the shape lattice |
| evaluate closed calls | effects, totality, shapes | shrink (a call becomes a constant) | `idr-eval` (JIT, exists); the cache of evaluated keys |
| defunctionalize | labels | representation | exists |
| useless fields, unused constructors, layout, Nat/Fin/Vect representation | useful fields; Idris | representation | representation.md |
| TRMC (destination passing) | uniqueness of the fresh cell, size-change | representation | the hole is an owned-stage `!idr.cell` (memory-theory) |
| recursion schemes over `Vect` → `linalg` | shapes (`Vect`), contiguity proofs, size-change | representation | registry entries first (`Data.Vect.map`/`zipWith`/`foldl`/`replicate`/`index`), then recognition by size-change |
| counted recursion → `scf.for` | size-change (−1 per step to a base of 0), Nat | representation | `idr-tail-loops` emits the canonical `scf.while`; upstream uplift makes it `scf.for`; then `affine` where applicable |
| bufferize arrays | uniqueness (`writable`) | ownership | upstream One-Shot Bufferize and ownership-based deallocation |
| cells: frame, reset/reuse, borrow, counting | escape, uniqueness, borrowed | ownership | the owned stage as types, and bufferization-style simplification of `dup`/`drop` (mlir-ownership-types) |
| lower | everything left | lowering | `idr-lower` sets LLVM attributes; an `idr.*` attribute that reaches it unconsumed is an error |

### I.4 Termination by construction: the decision lattice

- **Shrinking** patterns run to a greedy fixpoint. A measure decreases (op
  count, redexes): MLton's shrinker, Lean's `simp`.
- **Expanding** transformations never run "until the IR stops changing".
  Each round:
  1. solve the lattices;
  2. grow the decision sets `D = (inline edges over origins, spec keys,
     evaluated keys, join copies)`, which are monotone and never retracted;
  3. materialize the new decisions;
  4. shrink to a fixpoint.
- The loop stops when `D` stops growing. `D` is finite:
  - origins × origins for inlining;
  - binding times × `kUnrollLimit` (`Specializer.h:18`) × `kClonesPerOwner`
    (`Clones.h:22`) for keys;
  - one evaluation per call key;
  - (join, constructor) pairs for copies.
- This is Kleene iteration on a finite-height lattice.
  - `structural()` (`Simplify.cc:137-176`) and its reason for existing
    (sccp's constant churn, `Simplify.cc:10-18`) become irrelevant.
  - `max-rounds` stays as an assertion.
  - Today's informal argument (`Simplify.cc:4-8`, "every member of a round
    is finite") becomes the loop condition itself.

### I.5 The phases, with legality by type

1. **Emit.** Every Idris fact becomes IR structure (I.1).
2. **Value stage.** The decision loop (I.4) over the solver (I.2), with the
   shrinking and expanding transformations of I.3.
3. **Representation, once.** Defunctionalize; useless fields; layout;
   Vect/array → tensor/linalg; TRMC; counted loops.
4. **Array pipeline, upstream.** Linalg fusion, tiling and vectorization;
   One-Shot Bufferize; ownership-based deallocation; affine/scf; vector.
5. **Owned stage.** Frame cells, uniqueness, borrow, dup/drop and reuse,
   typed so that the stage *is* the types (mlir-ownership-types; the
   dialect split review-external asked for then comes for free).
6. **Lowering** with LLVM facts.

### I.6 Validation built in

- Verifier rules for every fact in a type (R1).
- A `--validate` mode: differential execution of each changed function
  before and after a pass, through the existing JIT (Part III §5).
- Alive-style SMT checks, or LeanMLIR proofs, for the rule layer.

### I.7 What we delete when we adopt MLIR's mechanism

| Ours | Adopt | Evidence |
|---|---|---|
| hand fixpoints: escape, effects, `Passed.cc`, recursion's label guess | the DataFlowSolver (I.2) | Part III §1 |
| `BindingTimes`'s re-derivation | Idris's size-change, emitted | `facts-ledger.md` §5 |
| `Sink.cc` (`kSinkBudget`), duplication in `CaseOfCase.cc`, `Meet.cc` | join points plus canonicalize; the non-convergent patterns violate `Canonicalization.md:44-60` | Part III §2 |
| `structural()` fixpoint | the decision lattice | I.4 |
| `Canonicalize/Pass.cc` (a copy of the canonicalizer) | `createCanonicalizerPass` with a listener | mlir-idioms §2 |
| `Passes/Scc.h` | `llvm::scc_iterator`, `CallGraph` | mlir-idioms §2 |
| `Facts/Moves/Only.cc` isa chain, `PerformsIO`, `RemoveUnusedCall` | `MemoryEffects` with resources, and an external model on `func.call` | mlir-idioms 3.4 |
| seven isa chains of "what happens to this operand" | one flow interface (`BufferViewFlowOpInterface`'s shape) | mlir-idioms §2 |
| `idr.stack` discardable mark | frame cells as ops with `AutomaticAllocationScope` | mlir-idioms 3.2 |
| `idr.stage` and the path-interpreting `Verify.cc` | owned-stage types (landed 2026-09-30: `!idr.own`, `dup`/`drop`/`borrow`, graded signatures; the walk stays, typed, for alternatives and loops) | mlir-ownership-types |
| Vect as a list of boxes, when contiguity is proved | tensor/linalg/bufferization | representation.md |
| tail loops as bare `scf.while` | uplift to `scf.for`, then affine | I.3 |

---

## Part II. The path, ordered by evidence and leverage

Each step names what it deletes. Measured failures come first.

1. **Nat is a type, with its operations** (representation.md R1). Map the
   natHack's five functions (`third_party/Idris2/src/Compiler/Opts/Constructor.idr:81-93`)
   to big ops through the registry, and make `!idr.nat` non-negative so
   ranges start at 0. **Measured quadratic today** (Part III §3.2).
2. **Case blocks are continuations.** Emit writes them as regions or join
   points, so the MLIR inliner's A→B→A refusal is never reached.
   **Measured**: lost reuse and an unexploited case-of-case in `tree/`. The
   refusal itself deserves an `upstream/` report if anything still relies
   on the inliner there.
3. **One solver.**
   - Load DeadCode, the shape lattice, labels, IntegerRange (seeded, with
     `match_lit` case arguments), and effects on callables.
   - Port escape to backward sparse.
   - Delete `Passed.cc`, the label guess in `Recursion.cc`, the
     `Infer.cc` worklist, and `Pattern.cc`'s shape walk.
   - Add `int-range-optimizations`.
4. **Canonicalize convergent-only, plus join points.** Delete `Sink.cc`,
   the duplication in `CaseOfCase.cc`, `Meet.cc`, and the canonicalizer
   copy.
5. **The decision-lattice loop.** Delete `structural()` as the loop
   condition. **Size-change from Emit**; delete the derivation in
   `BindingTimes.cc`.
6. **Effects as MemoryEffects**, with resources and an external model on
   `func.call`. Adopt upstream `cse`/`licm`/`remove-dead-values` for pure
   calls; delete the isa chains and `RemoveUnusedCall`.
7. **The owned stage as types** (memory-theory §6, mlir-ownership-types).
   Uniqueness gives static reuse and `noalias`. **TRMC** then removes the
   measured stack overflow.
8. **Arrays.** Registry entries for `Data.Vect`'s recursion schemes to
   `linalg` on `tensor`, under representation.md's contiguity proofs.
   One-Shot Bufferize, with unique arguments `writable`. Counted recursion
   to `scf.for`. Floating-point reductions keep Idris's order: no
   reassociation, since Double reductions are not associative and the Chez
   diff would catch the change. Integer (wrapping) reductions may
   reassociate.
9. **LLVM facts** in `idr-lower` (Part III §4).
10. **`--validate`**, and verifier rules for each typed fact.

---

## Part III. The answers, with evidence

### 1. Hand-written fixpoints, and which should be lattices

The inventory, found by grepping `lib/` for worklists (**read**):

| Fixpoint | Where | Lattice | Verdict |
|---|---|---|---|
| Escape, interprocedural | `Stack/Escape.cc:70-99` | per value: none < contents < reference (the Shallow/Deep pair, `Escape.h:63-64`) | **Sparse backward**, shaped like `LivenessAnalysis` |
| Escape, within a function | `Stack/Escape.cc:112-147`; `forwardsOf :56` | same | Same analysis. `forwardsOf` rebuilds by hand the region-branch forwarding the framework already does. "Does this con run again in its frame" is point-sensitive: it stays a local check, or disappears once frame cells are ops scoped by `AutomaticAllocationScope` (mlir-idioms 3.2) |
| Binding times | `Specialize/BindingTimes.cc:66-85` (per (function, abstract arguments)), `:190-215` (per SCC) | `{Same(i), Smaller(i), Top}`, context-sensitive | Not a DataFlow candidate: MLIR's sparse framework is context-insensitive. Take the fact from Idris, which proved it (§3.2) |
| Effects | `Facts/Infer/Infer.cc:78-88` | 4-point per function | A callable-anchored state in the solver. Its defect is imprecision: a closure's crash counts where it is made (`Infer.cc:41-58`), not where it is applied |
| What closures a value passes | `Facts/Closures/Passed.cc:34-70` | a local walk; any block argument is ⊤ (`:67`) | **Delete**: a weak duplicate of `LabelAnalysis` |
| Recursion for stack budgets | `Stack/Recursion.cc:24-46` | an apply calls every address-taken function | Read the labels instead |
| Borrowed parameters | `Ownership/Borrow.cc:57-61` | 2-point per parameter | Keep the algorithm (Lean's, verified downstream); its result becomes a type |
| Defunctionalization, keep or convert | `Passes/Defunctionalize.cc:822-845` | 2-point per key (MLton's `TwoPointLattice`) | Local to the pass: keep |
| Closure labels | `Passes/Defunctionalize.cc:234-392` | sets, ⊤ | **The template**: MLIR sparse forward, interprocedural, `FieldAnchor` |
| Ranges | none | none | `InferIntRangeInterface` on five ops (`Ops.cc:442,861,883,889,903`) is read by no pipeline step (`Registration.cc:15-31`, `Simplify.cc:207-222`). Only `tests/idr/fold/range.mlir` runs it: decorative by the dialect's own standard |

**Ranges.** Measured in `crash/`: in the default region of
`match_lit n {0 …}`, the code tests `n == 0` three more times and guards the
division with `select i1 %9, i64 1, i64 %4` (`crash.pre.ll`). LLVM removes
all of it at O3.

The reason to have ranges *in idr* is the decisions LLVM never sees:
- `knownNonZero` and the crash causes decide `crash`;
- `crash` decides `canMoveAcross`, and with it raising and case-of-case
  legality;
- all of this happens before LLVM exists.

The SSI split is the representation fix (SSA book ch. 11, §11.1: live-range
splitting "to build program representations that provide the static single
information property"). `idr.match` already binds fields; `match_lit`
should bind its refined scrutinee.

### 2. Equality saturation for the simplify group? Cost and benefit

**The fights in the history** (read, `git show`):

| Commit | What happened | Kind |
|---|---|---|
| `5fbc601` → `f5730a2` | a positive supercompiler with a whistle (homeomorphic embedding) and generalization; deleted in the cutover | expanding: unfolding |
| `cc3aebe` → `fc1d6f2` | "embedding for growth, stops that remember their key", replaced by binding times: "the stopped, counted and historied specialization is gone" | expanding: cloning |
| `81b0fa5` | specializing on machine Ints, "one clone per value … until the machine ran out of memory" | expanding: cloning |
| `9b58aaf` | case-of-case through nested matches "grew the module past 15,000 lines within 2,000 rewrites without converging"; backed out | expanding: duplication in canonicalize |
| `8cee6a8` | sink into regions, unbounded: "2,000 to 12,000 lines in 40 s"; hence `kSinkBudget = 64` (`Sink.cc:26,80`) | expanding: duplication in canonicalize |
| `908df5f` | inliner capped at 4 iterations: idr-simplify took 279 s, then 39 s; sink's candidate walk then 14 s | expanding against the round structure |
| `2685edd`, `558250e` | clones close cycles, the inliner unrolls them, "the simplify loop never ended"; loop breakers every round; a structural hash because sccp reorders constants | expanding plus an IR-hash fixpoint |
| `7884dd8` | sccp, prune and remove-dead-values baked the caller's constant into a raised clone; specialize re-specialized: "call-pattern looped" | interprocedural constants against cloning |
| `77d9b14` | write raising removed along with the heap rejections | raise against canonicalize |
| `3d02a0c`, `f748122` | Int counters unrolled as Nats | a fact re-derived by syntax |

Not one fight is between *local, shrinking* rewrites. Those are what
e-graphs solve ("when to apply which rewrite … is called the phase ordering
problem", egg `02-background.tex:344-352`). Every fight is between
**expanding or interprocedural** transformations.

**Benefits** (real, narrow):
- order independence among local rewrites;
- rules as data that can be checked (Ruler/Enumo, `pal-2023-ruler`
  abstract; Alive, §5);
- egglog's lattice analyses beside rewrites. That half we get from the
  DataFlowSolver (I.2). egg's single, upward-only e-class analysis
  (`zhang-2023-egglog/background.tex:360-365`) is too weak for ranges,
  labels and uniqueness together.

**Costs:**
1. **Scaling on functional terms.** "Even with efficient lambda calculus
   encoding, unguided equality saturation can locate only the two simplest
   of these optimizations … even with an hour of compilation time and 60GB
   of RAM" (`koehler-2021-sketch-eqsat/main.tex:173`). Herbie had to cap
   the e-graph's size and time (egg `06-case-studies.tex:30-50`). We would
   be back to budgets.
2. **Regions are binders.** The cost is either de Bruijn encodings
   ("orders of magnitude", Koehler, abstract) or slotted e-graphs, which
   are research-grade: the trace theorem "does not establish concrete
   transition semantics … or refinement of the Java code"
   (`wu-2026-slotted-egraphs/intro_compressed.tex`).
3. **Linearity.** Congruence merges terms without regard to how many
   times they occur. Extraction can use an `!idr.lin` value twice, or drop
   it. Keeping quantities through extraction needs occurrence-aware (ILP)
   extraction. I know of no solution (conjecture; the obstacle is
   structural).
4. **Effects.** World-threaded IO must stay a fixed skeleton. That is
   Cranelift's aegraph design (not in `sources/`; conjecture that it
   transfers), and it covers only pure straight-line code.
5. **Extraction.** DAG extraction is NP-hard. Greedy extraction is exact
   for tree costs only (egg `02-background.tex:395-400`).
6. **Integration.** egglog is Rust.

**Answer.** **No** for the simplify group. The history is cured
structurally:
- expanding transformations leave the greedy driver;
- join points replace duplication;
- the loop runs over decisions (I.4).

**Maybe later**, a bounded e-graph for the region-free, effect-free
peephole layer, with its rules checked à la Alive.

### 3. Whole-program optimization beyond MLton

#### 3.1 MLton, and where we stand

MLton's SSA pipeline is a **fixed sequence**: each pass runs a fixed number
of times, and the order is justified in comments. There is no global
fixpoint (`mlton/ssa/simplify.fun:44-120` at the snapshot's revision
`aa2fd1ad`; not in `sources/code/mlton`, so I fetched it to scratch). Lean's
LCNF likewise has fixed phases, base/mono/impure, with occurrence counts
(`Lean/Compiler/LCNF/Passes.lean:92-160`, fetched).

| MLton pass (`simplify.fun`) | What it does | idris-mlir |
|---|---|---|
| closure conversion, 0CFA (`closure-convert/`) | flow-directed defunctionalization | **parity** (`idr-defunctionalize`) |
| `inlineLeaf` ×2, `inlineNonRecursive` | size rule | **ported** (`Inline.cc:36-38`) |
| `constantPropagation` (data, globals) | abstract values | **stronger in part**: `idr-eval` runs closed calls; shapes are recomputed syntactically |
| `contify` ×3 (`contify.fun:9-12`, Fluet & Weeks) | one continuation → a block | **missing** (measured below) |
| `useless` (`useless.fun:10-25`) | unused fields and arguments | **missing for fields** |
| `removeUnused` ×4 | unused functions, constructors, arguments | partial (`symbol-dce`, `remove-dead-values`); no constructors |
| `simplifyTypes`, `splitTypes` | types simplified and split | **missing** (Emit boxes by recursion alone, `Term.idr:309-310`) |
| `flatten`, `localFlatten` ×3, `deepFlatten` | tuples passed flat | partial (1:n lowering of sums) |
| `knownCase`, `redundantTests` (relational, `redundant-tests.fun:9-60`) | known constructor; tests implied by others | known constructor yes; relational tests **missing** |
| `introduceLoops` ×3, `loopInvariant` ×3 | tail loops; LICM | self tail calls only; LICM left to LLVM |
| packed representation (`backend/packed-representation.fun`) | tags in pointers, nullary constructors as immediates | a header word; nullary constructors are static cells, so a `Nil` test loads memory (`load i32 … and 65535`, `lists.pre.ll`); representation.md R3 |

**Measured: contification.** `insert x (Node l y r) = if x < y then Node
(insert x l) y r else Node l y (insert x r)` elaborates to `insert` plus
`case block 841 in insert`. After idr-simplify:
- `insert` is the loop breaker (`no_inline`) and calls the case block from
  both arms of a `match_lit` on `x < y`, passing the constant `True` or
  `False` (`tree/dump/01-idr-simplify.mlir`);
- the case block is never inlined. The pinned inliner refuses a callee that
  calls its caller back (`Inliner.cpp:709-715`); `no_inline` plays no part.

Consequences:
- the Bool is built, then matched again in the callee. Case-of-case moved
  the call because `Meet.cc:13-25` predicted a fold; no fold came;
- **reuse is lost across the call**: `insert` resets the node's cell and
  frees it (`call void @idris_rt_free_cell(ptr %35)`), and the case block
  allocates a new one (`tree.pre.ll`);
- mutual tail recursion (`mutual/`, `ev`/`od`) stays two functions at the
  MLIR level. Its constant stack depends on LLVM's sibling-call
  optimization, which holds only because the arguments fit in registers
  (measured: 10^8 iterations ran).

An Idris case block *is* a continuation of its parent. Emitting it as one
makes the cycle unrepresentable.

#### 3.2 What Idris facts add beyond MLton

| Idris fact | What it enables | Status and evidence |
|---|---|---|
| **Quantity 1, plus the whole program** | uniqueness inference: reuse with no runtime test; `noalias`; One-Shot Bufferize's `writable` | planned in `ResetReuse.cc:19-25`; designed in memory-theory §6. Today `bump` tests `icmp eq i32 %7, 1` plus the static mark on every node (`lists.pre.ll`) |
| **Fresh cell, plus a constructor around the recursive call** | TRMC / destination passing: `bump (x :: xs) = f x :: bump xs` becomes a loop that writes the hole | **Done** (idr-trmc, `!idr.dest`): `map` over 10^6 elements runs in constant stack (e2e/v3/map-deep), rbtree 1.75 s → 1.37 s. Before: `bump` over 400,000 elements segfaulted (8 MiB stack) |
| **Quantity 0** | erasure (done) | Beyond it: erased *proofs* (`LTE`, `NonZero`, `So`, `Elem`, `=`) could be ghost values that range analysis consumes (mlir-idioms 5.3; open) |
| **Totality and coverage** | speculation and hoisting of pure calls; `willreturn`; complete matches; **eager `Lazy`** whose body is total, crash-free and cheap (strictness as a cost question, not a divergence question) | the eval budget by totality is done (`Eval.cc:52-68`); eager `Lazy` is missing (conjecture that it pays) |
| **Size-change** | binding times, counted loops (`scf.for`), base-case branch weights, recursion-depth bounds for stack budgets (today a flat 64 bytes, `Stack/Pass.cc:38`) | read by the frontend only for polymorphic recursion (`Translate/Recursion.idr:1-7`, `6883563`), then dropped |
| **Nat is a non-negative Integer**, and its operations are Integer's | O(1) arithmetic; range ≥ 0; `index` for small Nats | upstream's "natHack" does this for every backend at the CExp level (`Constructor.idr:81-93`); we read TT. **Measured**: `count (S k) acc = count k (acc + 2)` calls the Prelude's recursive `plus` every iteration. 1.9 s / 8.0 s / 39.2 s for n = 10k / 20k / 40k, where Chez takes 0.11 s for 40k and 0.13 s for 10^7 (`nat/`). `!idr.big` conflates Integer and Nat (`IdrOps.td:79-81`) |
| **Indices** (`Fin n`, `Vect n`) | ranges; no bounds checks; exact sizes; `tensor.dim` | static `n` done: `index (toFin4 n) v` became a 4-way switch with no check (`vect.pre.ll`); symbolic `n` erased |
| **Linearity plus totality** | fusion of producer and consumer, with no duplicated work and no change to termination; for `Vect`, linalg's elementwise fusion does it | missing: `upto`, `bump` and `total'` each build the list (`lists.pre.ll`) |
| **Purity plus totality** | CSE and LICM of *calls* program-wide (upstream passes, once effects are `MemoryEffects`) | partial: `cse` within regions; `canDrop` only |

### 4. What LLVM receives, and what it should

**Measured**: the IR before O3 (`*.pre.ll`) and after O3 with the runtime
linked (`*.O3.ll`, `Lower/Target.cc:28`). mlir-idioms 6.3 lists the LLVM
dialect's attributes; here is the evidence and the fact behind each.

| LLVM fact | Today | Idris fact that justifies it | Value |
|---|---|---|---|
| function attributes | none on generated functions (`define ptr @Main.bump(ptr %0)`); after O3 only `nounwind` | totality + no crash → `will_return`/`mustprogress`; `#idr.effects<none>` → memory effects | small: LLVM cannot infer `willreturn` for recursive functions, but idr already drops dead pure calls |
| `nonnull`/`dereferenceable`/`align 8` on boxes | none; O3 inferred `nonnull` only on `idris_rt_cell` | representation: a box is never null | moderate: speculative loads. The lowering puts `null` placeholders in phis (`phi ptr [ %15, %11 ], [ null, %10 ]`), so set the attributes on values |
| field-load alignment | `load i64, ptr %12, align 4` on 8-aligned cells (`lists.pre.ll`) | the layout | small, free |
| `noalias` | none | **proved uniqueness only**, not `!idr.lin` (AGENTS.md); `allockind("alloc")` on `idris_rt_cell` | after Part II step 7 |
| TBAA / `invariant.group` | none in generated code; the linked runtime's own TBAA (`!tbaa !9816`) sits next to untagged field loads (`lists.O3.ll`) | cells are immutable between construction and reset: `invariant.group` plus a launder at reuse | conjecture; benchmark it |
| `range`, `nsw`/`nuw` | none; the tag is masked (`and i32 %3, 65535`) | tags, Char, Nat ≥ 0, `Fin n` < n. **Not** `nsw` on `Int`: it wraps, and the plain `add` is right | small for tags, real for Nat and Fin |
| crash paths | `declare void @idris_rt_crash(ptr, i64) #0 = { noreturn }`, followed by `br` and a guard `select` before `sdiv` (`crash.pre.ll`; `Lower/Runtime.cc:94-99`, `Lower/Patterns.cc:215-240`) | a crash does not return | add `cold`. O3 already turns what follows a noreturn call into `unreachable`, and the loop comes out clean (`crash.O3.ll`) |
| branch weights | none | size-change (the recursive region is the likely one); a linear binder makes a successful reuse test likely (a heuristic) | conjecture; measure first |
| `llvm.sideeffect` | only in partial loops (`ack`, `readInt`'s `go`) | totality | already right |

**Answer.** Send:
- `will_return` from totality;
- `range` from Nat, Fin and tags;
- `noalias` from proved uniqueness;
- `nonnull`/`dereferenceable`/`align` from the layout;
- `invariant.group` from immutability.

Most of what LLVM "misses" it re-infers at O3, because the runtime is linked
in. The larger gains are facts consumed *before* LLVM (§1, §3).

### 5. Translation validation and verified rewriting

1. **Local checkers for typed facts** (R1). The owned-stage verifier
   (`Ownership/Verify.cc`, `Dialect.cc:436-441`) already works this way,
   and memory-theory §6.4 does the same for uniqueness. Termination is
   trusted from Idris; losing it only costs speed.
2. **Differential execution through the existing JIT.** `idr-eval` already
   lowers, JITs, meters and reifies in a child process. A `--validate` mode
   runs each changed function before and after a pass on inputs enumerated
   from its types, and compares the results. Totality makes the comparison
   meaningful within the meter. This is bounded validation, like Alive2's:
   it "misses bugs" but raises no false alarms (`lopes-2021-alive2`,
   abstract). `tools/bisect.sh` and the action framework
   (`Support/Actions.h`) already bisect to a single action; extend both to
   every rewrite.
3. **Verified local rules.**
   - The rules in scope: the DRR patterns, the folders, known-constructor.
   - The SMT theories: bitvectors, algebraic datatypes, and strings and
     ints for strings and bigs.
   - The track record: Alive checked 300 LLVM rules and found eight wrong
     (`lopes-2015-alive`, abstract).
   - Regions: LeanMLIR proves peephole rewriting sound over SSA with
     regions (`bhat-2024-verifying-peephole`, abstract and §4.1).
   - The cost: formal semantics of the `idr` ops, checked against the
     runtime, which is their meaning.
4. **Not feasible:** SMT validation of the whole program across inline,
   clone, eval and defunctionalize. Alive2 is intraprocedural and bounded.

**Answer.** Items 1 and 2 are cheap; 2 is nearly free, because the JIT
exists. Item 3 is moderate. Item 4 is not feasible.

### 6. Architecture as data

This is Part I: the IR stack (I.1), the facts (I.2), the transformations
(I.3), termination (I.4), the phases (I.5), validation (I.6), and the
deletions (I.7).

**Keep:**
- quantities as types, re-verified after every pass;
- `LabelAnalysis`, as the template;
- `idr-eval`, both as an optimizer and as the validation oracle;
- MLton's inline rule and the loop breakers;
- the owned-stage verifier and `Borrow.cc`;
- `idr-expect` properties, which become verifier rules wherever they are
  facts (`reuses-in-place` → uniqueness).

---

## Open questions

- **Join points in MLIR.** A jump from nested `idr.match` regions to a
  named continuation is non-local, and structured regions forbid it. The
  options:
  - region values in the style of `rgn.val`/`rgn.run`
    (`bhat-2022-lambda-ultimate-ssa/paper.tex:1693-1714`);
  - blocks inside the function;
  - a yield that names its join.

  Which one keeps `RegionBranchOpInterface` and the solver working?
- **Recognizing recursion schemes over `Vect`.** The registry first; then
  when does size-change plus a TRMC shape justify a `linalg.generic`?
  Floating-point order must be kept.
- **Size-change across erasure.** Idris's `SCCall` matrices index source
  arguments, implicit ones included. Emit needs a map to MLIR parameters
  after erasure and monomorphisation. Composition is standard (Lee, Jones,
  Ben-Amram), but untested here.
- **The decision lattice.** Does every interaction today's rounds find
  appear as growth of `D`? Unknown for `7884dd8`-style interactions through
  sccp.
- **Eager `Lazy`.** It needs a cost bound on the thunk body.
- **ackdyn** (MLton 2.3x faster, per the README). The O3 IR of `ack` is a
  tight loop plus one recursive call (`ackdyn.O3.ll`). The gap is likely
  frame and calling-convention cost, not the optimizer. Not investigated.
