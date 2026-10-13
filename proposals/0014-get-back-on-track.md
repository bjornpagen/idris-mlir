# 0014: get back on track

**Status:** decided (2026-10-12), against `main` at 25890d32. Stages C1
to C5 and H1 to H2 were carried out as one cutover by the swarm packet
`0015-cutover-swarm/`, whose `contracts.md` is the more specific decision
where the two differ (no compatibility owed, `idr.func` at once, the
erased grade deleted from the dialect, Tracy as a preset instrumented
through the pass manager, the dialect's readability taken now). The
cutover is committed; it is unbuilt until the owner's machine runs it. G0, G1 (§12, what remained of the former 0001 and 0002)
and S (§6.1, self-hosting) stay here. Its §1 to §4 read the tree before
the cutover, at 25890d32. Claims are marked: *read* (the path),
*measured* (the record), *recalled* (from memory, to be checked),
*conjecture*, *decision*.

**The one sentence.** Self-hosting did not fail at the frontend. It failed
where every program fails once it is large enough: the C++ side walks the
whole module once per pass, once per round, on one thread, over an IR
that is far larger than the program, and it re-derives after every pass
what it already knew. The fix is representational, not a tuning: one
representation for each fact, the function as the unit of work, the
frontend emitting what it decided, and the C++ written as the MLIR
project it is. This proposal starts first. What remained of the LLVM pin
(the former 0001) and of the representation cutover (the former 0002) is
§12, and it is the gate G1. Self-hosting follows (§6.1), then sharding;
every other proposal waits for them.

## 1. Where the wall is

*Measured* (HANDOFF.md, 2026-10-10, arm64 macOS): stage 0, the frontend
on Chez compiling its own sources, emits a 405 MB text module of 58,305
functions and 7,664 data declarations in 137 s at 9.1 GB peak. The
sources are about 64k lines of the fork and 13k of the frontend (*read*:
`wc` over `compiler/`).

*Read* (`bugs/simplify-does-not-finish.md`): the C++ pipeline has never
finished on that module. Round 1 of `idr-simplify` does not return in
four minutes; the sample sits in the first whole-module verify, on one
thread, in `idr::verify::program`.

Three terms compound, each *read*:

- **Every pass is a module pass.** 26 of the 27 passes in
  `foreign/idr/include/idr/Passes.td` anchor on `::mlir::ModuleOp`; the
  one op-agnostic pass, `idr-canonicalize`, is run on the module too.
  MLIR parallelizes over the nested operations of a function pass and
  never inside one module pass (`sources/docs/mlir/docs/PassManagement.md`,
  "Pass Manager"). Threading was turned on in 96e1d308; the pool has
  nothing to run, which the bug note says at its line 51.
- **The whole program is re-verified after nearly every pass.** The
  module's `idr.program` attribute verifier calls the whole-program
  check (`foreign/idr/lib/Dialect/Verify/Attributes.cc:41`), which walks
  every operation, rebuilds the type graph and runs linearity on every
  function. The linearity check numbers the whole region once per linear
  value (`foreign/idr/lib/Verify/Linearity.cppm:43`); IO code has a
  world per bind, so the check is quadratic in a function. A round runs
  eleven passes (`foreign/idr/lib/Simplify/Round.cppm`); the budget is
  64 rounds (`Passes.td`, `max-rounds`). Several passes also hash the
  module twice with `OperationFingerPrint` to learn whether they changed
  anything (`Simplify/Pass.cc`, `Specialize/Pass.cc`, `Inline/Pass.cc`).
- **The handoff is larger than the program.** Erased parameters are
  emitted as values of `!idr.erased` (`compiler/src/IdrisMLIR/Emit/Types.idr:18`,
  `Emit/Bodies.idr:334`). Instances are keyed on types and
  implementations and the key is printed into the symbol name
  (`compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:61`). Newtype
  wrappers, curried method shims and delays of evaluated values survive
  into MLIR (`bugs/idris-mlir-handoff-investigation.md` §3, from a dump;
  the mechanism is *read* in `Translate/Instances.idr`). C++ removes all
  of it again, every round, over the whole module, with
  `remove-dead-values`, `idr-identity`, the inliner and canonicalize.

The same bug is already in `make test`. *Read* (HANDOFF.md, §12):
`programs/prelude/every-interfaces-export` (282 lines) and
`every-types-export` (224 lines) compile and then hit their time limits.
They are the largest library-surface programs in the suite. That is the
wall at a size where it can be debugged in minutes.

The last three commits (45c2c5d0, 96e1d308, 25890d32, *read*) cut
constant factors on symbol lookups and type walks and published scope
chains to worker threads through atomics on the dialect object. None
touches the three terms above, and the note after them says so.
96e1d308 also deleted `idr-eval` and the JIT, which the static normalization plan
scheduled after its replacement exists (now 0016); it does not. The second compilation of every e2e test,
"without evaluation", now compiles the same program twice.

The ground, *read* (§12, HANDOFF.md): `make test` is not green on
arm64; the bench was last recorded on 2026-10-07, before the LLVM trunk
cutover and the representation cutover of 2026-10-09; x86_64 Linux is
unbuilt at the pin. By AGENTS.md's own rule a change is done when it
builds and passes on both targets, so nothing since 2026-10-09 is done.

## 2. The thesis: representation, then control

AGENTS.md already states the rule this proposal applies: one thing, one
representation; when a new case shows up, change the data and its
invariants until the case is no longer special before adding a branch, a
flag or a guard. The lineage behind it (Brooks, Pike's Rule 5, Raymond,
Torvalds) says the same: show me your tables and the flowcharts are
obvious.

The wall is that rule broken at three levels:

1. **The handoff carries what the frontend already decided**, so the
   C++ side re-decides it. Erasure, newtypes, saturated method calls and
   arity are facts of Idris types; the frontend has them and prints them
   away. Every C++ pass that recovers them is a branch added where the
   data should have changed.
2. **A fact about the program is held in several places.** Effects,
   totality, breaker status and clone keys are discardable attributes
   read by string in 28 places (*read*, `grep` over `lib/`), policed by a
   trait on every op because nothing else can. The effects pass keeps a
   second copy on the pass instance across rounds (`Facts/Pass.cc`,
   `Facts/Infer.cppm`). Symbol tables and the may-hold-world memo are
   held in thread-local chains with atomic heads on the dialect
   (`Dialect/Symbols/LookupSymbol.cc`, `HoldMemo.cc`). MLIR's pass
   rules forbid every one of these (`PassManagement.md`, "Operation
   Pass": no mutable state across runs, no global mutable state), and
   its analysis manager exists so that no pass needs them.
3. **The unit of work is the unit of meaning.** Whole-program facts
   (reachability, effects, labels, exclusivity, binding times) need the
   module. The rewrites that use them need one function. Today both run
   as module passes.

Speed comes from removing that waste, not from cutting a rule. What
stays, from AGENTS.md: no pass drops multiplicities, erasure or
linearity, which live in types; the verifier checks after every pass;
nothing miscompiles silently; tests check behaviour; a bug in upstream is
fixed upstream; both targets, always.

## 3. What MLton does that we do not

*Read*: `sources/docs/mlton/doc/guide/src/{CompilerOverview,SSASimplify,
WholeProgramOptimization,Contify,Useless,RemoveUnused,Flatten}.adoc`,
`sources/code/mlton/mlton/ssa/{inline,contify,useless,remove-unused}.fun`,
and `sources/notes/sharded-compilation/whole-program-at-scale.md` §3,
which records the Weeks 2006 talk (the slides' text did not extract on
this machine).

- **A sequence of passes, not a fixpoint loop.** SSA simplification is a
  fixed list of 23 optimization passes under one `Simplify` functor;
  looping is a bounded knob, `-loop-passes <n>` (*read*,
  `SSASimplify.adoc`). After every pass runs `shrink`, a cheap local
  simplifier (known case, dead code, jump threading, blocks jumped to
  once), so each pass sees canonical input and runs once (*recalled*:
  `Shrink.adoc` is not vendored). Ours is a 64-round fixpoint of eleven
  module passes whose termination `max-rounds` asserts.
- **Self-compile figures.** *Measured* (the note, from the talk): 26.2k
  functions and 719k statements before optimization, 1.8k and 365k
  after; the goal was a self-compile under five minutes; no parallelism.
  Monomorphisation growth at most 30% in practice. 0CFA over all of
  MLton under 2 s, by type-based preprocessing, hash-consed sets and
  union-find. Our stage-0 module has 58k functions before anything runs.
- **One pass per question.** `RemoveUnused` finds unused datatypes,
  constructors, constructor arguments, functions, arguments, returns,
  blocks and statements in one fixpoint over two-point lattices with
  handlers (`remove-unused.fun`: `Used`, `Coned`, `Deconed`, `MayReturn`,
  `MayRaise`). `Useless` is one dependence graph. Ours spreads the same
  question over `remove-dead-values`, `symbol-dce`, `idr-identity`,
  canonicalize's dead-op erasure and `idr-returned-arguments`, each a
  module walk.
- **Contification by dominators** (Fluet and Weeks, `contify.fun`): a
  function that always returns to one place becomes a continuation. Ours
  inlines a function called exactly once (`Simplify/Contify.cppm`).
  The inline rule is MLton's (`Inline/Decisions.cppm`).
- **Flatten and DeepFlatten**: tuple arguments and fields passed and
  stored flat. Ours has this in `Layouts::components` and the array
  element layout (*read*, the competitor survey of 2026-10-02, adff318a).

The lesson is the pass discipline: whole-program meaning with a linear
number of whole-program walks, each written once around one analysis,
and local cleanup kept cheap and separate. MLton had no parallelism; MLIR
gives it for free once the passes are shaped for it.

## 4. What the pinned MLIR offers that we do not use

*Read*: `sources/docs/mlir/docs/PassManagement.md`, `PatternRewriter.md`,
`Canonicalization.md`, `BytecodeFormat.md`, `Rationale/Rationale.md`
("Multithreading the compiler"), and the vendored headers under
`sources/code/mlir/include/mlir/`. The survey of 2026-10-02 (f2d6df36,
deleted with `findings/`) covered the pass set; this is the pass
*infrastructure*, which it did not.

- **Nested pass managers on functions.** A pipeline nested with
  `nest<func::FuncOp>` runs every pass on one function before the next,
  "improves the cache behavior of the compiler" and lets "an entire
  function pipeline be run on each function asynchronously"
  (`PassManagement.md`, "OpPassManager"). The rationale: passes are
  copied into one instance per thread; functions are not SSA values, so
  they share no use lists (`Rationale.md`, lines 1052 to 1064).
- **Analyses.** Free-standing classes "computed lazily on-demand and
  cached", queried with `getAnalysis<>`, `getCachedParentAnalysis<>` and
  `getChildAnalysis<>`, kept across passes by `markAnalysesPreserved<>`
  and refined by `isInvalidated` (`PassManagement.md`, "Analysis
  Management"). A function pass reads a module-level fact through
  `getCachedParentAnalysis`. We use the manager in eleven lines, nearly
  all in `idr-inline`, and rebuild `References`, the symbol table,
  `CloneTable`, `BindingTimes`, the type graph and effects per pass.
- **Dynamic pipelines through `runPipeline`**, so that "all analyses,
  instrumentations and other pass manager related components are
  integrated"; "a `PassManager` should generally never need to be
  constructed within a `Pass`" (`PassManagement.md`, "Dynamic Pass
  Pipelines"). The driver builds 25 pass managers from text
  (`Driver/Run.cppm`), one per step, so no analysis survives a step.
- **One dataflow solve for several analyses.** The `DataFlowSolver`
  loads several analyses into one fixpoint and is interprocedural by
  configuration (`Analysis/DataFlowFramework.h:283-300`,
  `DataFlowConfig::setInterprocedural`). `sccp`'s constant propagation,
  dead-code analysis, integer ranges, liveness (what `remove-dead-values`
  uses), our closure labels (`Defunctionalize/Analysis.cppm`, already on
  the solver) and effects can share one run and one walk.
- **Two pattern drivers.** `walkAndApplyPatterns` is "a fast and simple
  driver" with no revisits, for rewrites that need no fixpoint; the
  greedy driver is for canonicalization (`PatternRewriter.md`, "Common
  Pattern Drivers"). A fold is preferred to a pattern wherever it fits
  (`Canonicalization.md`). Thirteen files of ours use patterns; 28
  rewrite by hand with a builder over 140 `walk` sites (*read*, `grep`).
- **Instrumentation.** Pass timing in tree mode shows every analysis
  computed, as `(A)` rows, and so "can also be used to identify when
  analyses are being invalidated and recomputed"; multi-threaded timing
  separates user from wall time (`PassManagement.md`, "Pass Timing").
  This is the instrument for the baseline below.
- **The inliner.** Upstream's `InlinerPass` runs its nested pipeline on
  the callables of a strongly connected component in parallel
  (*recalled*: `Inliner::Impl::optimizeSCCAsync`). Ours hands it a
  pipeline runner that does nothing (`Inline/Pass.cc`).
- **Inherent properties.** `UnitProp` already carries `moves` on
  `idr.array.get` (`IdrOps.td`). A fact that lives as a property or an
  inherent attribute of an op has a typed accessor and the op's
  verifier; a discardable one has a string and a policing trait.
- **Bytecode.** A versioned, stable format with reader and writer
  already linked (`BytecodeFormat.md`; `lib/Mlir.cppm`).
- **CallGraph with `llvm::scc_iterator`**, `FunctionOpInterface` and
  `CallableOpInterface` (`Interfaces/{FunctionInterfaces,CallInterfaces}.td`):
  a function op of ours that implements them is a function to the
  inliner, the call graph and `symbol-dce`.

## 5. The design

### 5.1 The handoff: the frontend emits what it decided

The frontend drops from the contract everything it already knows is not
there at runtime, and keeps in types everything a pass could lose:

- no quantity-0 position anywhere: no `!idr.erased` parameter, field,
  argument or constant;
- no newtype constructor: a declaration of one constructor and one
  runtime field is that field;
- a method call whose implementation is fixed is a direct, saturated
  call of the implementation's function, not an apply of a shim's
  lambda;
- a definition is emitted at its syntactic arity and called saturated;
  a closure is built only for a real partial application;
- instance keys are alpha-normalized (no binder names, no case-block
  counters), and the key lives in an attribute of the function, not in
  its symbol;
- no `idr.delay` around a value already evaluated.

What crosses the boundary unchanged: `!idr.lin<T>`, `!idr.world`, the
owned grades, `idr.total`, data declarations and their shapes. Erased
means nothing at runtime, so an erased position carries nothing MLIR
could drop; a grade of one or of ownership is what a pass can lose, and
stays a type. This resolves the tension between AGENTS.md ("erasure
lives in types") and the handoff brief ("no zero-quantity values"): both
hold, for different quantities.

Each item is measured on the stage-0 dump by function count, operation
count and bytes, with the brief's Phase 1 script, before and after.

### 5.2 Facts: one representation each

- **`idr.func`**, the one dialect change. It implements
  `FunctionOpInterface`, `CallableOpInterface` and `Symbol`, so the
  upstream inliner, call graph and `symbol-dce` work on it unchanged, and
  carries totality, effects, breaker status and clone key as inherent
  attributes or properties with generated accessors. Its verifier owns
  the per-function rules: linearity and the owned stage. No `idr.*`
  discardable attribute on a function remains, and no string attribute
  name outside ODS.
- **Analyses, not caches.** `References`, effects, binding times, the
  clone table, the type graph, may-hold-world and may-hold-closure become
  analyses of the module under the analysis manager, preserved by the
  passes that do not change what they read. `SymbolScope`, `HoldMemo`,
  `SymbolsHeld`, the `holdsSymbols` switch, the thread-local chains, the
  atomics on the dialect and the effects pass's cache are deleted.
  Symbol lookups go through one `SymbolTableCollection` owned by the
  analysis.
- **One interprocedural solve per round** (§5.3), on the solver, for
  every fact that is a dataflow fact.

### 5.3 The round: MLton's shape with MLIR's parallelism

A round of the simplify loop becomes:

1. **Facts** (module analyses, read-only): references and loop
   breakers; the solver run with constants, dead code, ranges, liveness,
   labels and effects; binding times and the specialization decisions.
2. **Local rewrites** (a nested `idr.func` pipeline, parallel over
   functions, each function verified after each pass): identity,
   canonicalize with the dialect's patterns, cse, the local part of dead
   value removal, redirecting calls to clones that exist.
3. **Symbol changes** (module, cheap, no walks): inserting the clones
   the decisions named, inlining through the upstream inliner with its
   SCC-parallel pipeline, erasing dead symbols.

Rounds end on a change flag the passes already compute, never on a hash
of the module. The round count stays bounded and asserted; the bound is
re-measured once the diet and the shape are in (conjecture: single
digits, as MLton's `-loop-passes` default). The passes that stay ours
(specialize and raise, defunctionalize, rc with borrow and exclusivity,
trmc, tail loops, narrow, in-bounds, stack, demand) are decisions MLIR
cannot take, as the 2026-10-02 survey found; each is re-housed along
0011 §2.1's line, its analysis in step 1 and its rewrite in step 2, not
rewritten.

### 5.4 Verification: at the level the pass ran

MLIR verifies the operation a pass ran on. Once rewrites are function
passes, the verifier after each of them is one function's, in parallel,
and `idr.func`'s verifier runs linearity in one numbering per region.
The module's `idr.program` verifier keeps only the module-level rules
(one root, declared types, acyclic containment) and runs after module
passes and at parse, as today. AGENTS.md's "the verifier checks after
every pass" stays literally true and stops costing a module walk per
function pass.

### 5.5 The pass layer as an MLIR project

PINS.md records that MLIR's API "is forbidden by the C++ profile", so all
of `foreign/idr` is quarantine code, written as 314 C++20 module units
(284 of them partitions) importing one wrapper of every MLIR header,
with 111 `.cc` glue units for anything that touches ODS, a clang crash on module layout
carried as a pin, and no compiler cache for `make build` (*read*:
`PINS.md` `mlir-cxx-api`, `clang-module-layout-forward-declaration`;
`README.md` "Setup"). That is the gnarliness, and it is structural.

`foreign/idr` becomes a plain in-tree MLIR dialect: headers and `.cpp`
under `include/idr/{IR,Analysis,Transforms}` and `lib/`, built with
upstream's `add_mlir_dialect_library` and `add_mlir_library`, cached by
ccache like the toolchain. The hardening flags (`-fsanitize=undefined`
with traps, zero-initialized locals, zeroed call-used registers, no
strict aliasing; *read*: `CMakeLists.txt:285-301`) move to a `hardened`
preset; Release keeps full LTO and nothing that slows a compiler's hot
loops. The dialect's ODS, traits, interfaces, DRR patterns and the
generated Idris syntax are unchanged.

### 5.6 The driver

One typed `PassManager` built by constructors, function steps nested,
dynamic pipelines through `runPipeline`, text pipelines only in
`idris-mlir-opt` for tests. The handoff is read as text until the diet
has shrunk it; then the parse is measured and bytecode is taken if the
parse still shows in the profile.

## 6. Staged plan

Every stage is gated by `make check`, `make test-idr`, `make test` and
`make test-mlir-tools` on arm64 macOS, the compile-time record of the
suite (`tests/compile-times.sh --against`) not worse than the stage
before, and `tests/determinism/threads-*` byte-identical under one
thread and under the pool. Where a stage changes no behaviour, the
702-program corpus's outputs are byte-identical.

| Stage | Change | Proof |
| --- | --- | --- |
| G0 | Baseline. Bootstrap on arm64; `make test` with timing; `tests/compile-times.sh`; `-mlir-timing` in tree mode and `--stats` on `every-interfaces-export` and the ten slowest; function, op and byte counts of the stage-0 dump by the brief's script. 0011's S0 is this stage. | a committed record in this directory |
| C1 | `foreign/idr` as an MLIR project (§5.5); `mlir-cxx-api` and the module-layout pin retired; ccache on `make build` | no behaviour change; `test-idr` 269 green; rebuild times recorded |
| C2 | Verification at the level the pass ran (§5.4); `idr.func` (§5.2) with linear linearity | the two set-aside programs pass within their limits |
| C3 | Analyses replace caches (§5.2); the deletions named there | suite compile total not worse; `(A)` rows show each analysis computed once per round |
| H1 | Handoff diet, first half: erased positions, newtypes, trivial delays (§5.1) | stage-0 dump counts recorded; corpus identical |
| C4 | The round in MLton's shape (§5.3): the solver run, the nested function pipeline, the upstream inliner's parallel pipeline, no module hash | wall time under the pool below one thread's; round counts recorded |
| H2 | Handoff diet, second half: saturated method calls, arity, alpha-normalized keys in attributes | counts recorded; corpus identical |
| G1 | Green on both targets, the bench on both against the 2026-10-07 and 2026-10-03 records by ratio to C, regressions beyond the spread bisected (§12) | §12's lists empty |
| C5 | The driver (§5.6); parse measured; bytecode if it shows | parse time recorded |
| S | self-hosting, in the steps of §6.1 | the self-host record in HANDOFF.md |

C1 is first because it is mechanical, changes no behaviour, and every
later stage iterates faster on a cached build. C2 is the one that also
closes the two `make test` timeouts. H1 and H2 run on the Idris side in
parallel with C3 and C4.

### 6.1 Self-hosting, after the cutover

Self-hosting is the first priority, and sharding is right after it. The
cutover is written and unbuilt; these steps take it to a compiler that
compiles itself, each one measured before the next starts.

1. **Integrate.** The cutover's lanes as one tree: `make typecheck` and
   `make check` clean on this checkout, every C++ unit compiling against
   the typecheck slice of LLVM.
2. **Green on the owner's machine.** `make build`, `make test`,
   `make test-idr` and `make test-mlir-tools` on arm64 macOS, the two
   set-aside programs within their limits, G0's record taken on the
   cutover tree. A failure is read from the code and fixed in the tree.
3. **Break the wall by measurement.** The pipeline on the stage-0 module
   with `-mlir-timing` and a Tracy capture (the `profile` preset): the
   first time the C++ side finishes on it. The pass or analysis that
   dominates is fixed first. LLVM's single module is the term no pass
   change touches, so 0011's S2 (units, split codegen, an ordered link)
   is pulled forward here and taken as soon as the record shows codegen
   as the cost.
4. **The diet and the memory.** The stage-0 dump's functions, operations
   and bytes against §1's, and the peak resident memory of the
   frontend and of the pipeline. The frontend's 9.1 GB peak is a wall of
   its own; the stage that shrinks it is the one the measurement names.
5. **`make self`.** Stages 1 to 3 on the self-compiled frontend, stage 2
   byte-identical to stage 3, and every stage's output byte-identical
   under one thread and under the pool (`tests/determinism`).
6. **The test runner off Chez.** The runner (`tests/Main.idr`,
   `Runner.idr`) compiled by the self-hosted compiler, so `make test`
   needs no Chez at all; Chez stays only as the host of stage 0.

Then sharding: 0011's S0, S1, S2 (if step 3 has not already taken it)
and S8, with 0009's P1, P2 and P4.

Arrays come right after `make self`, ruled by the owner on 2026-10-12,
ahead of sharding: 0007's stage 1 lands as one hard cutover. It purges today's array stack (the
unsized `Linear.Array`, the memref loops, `idr-in-bounds`, about 6,300
lines; 0007 §15) and rebuilds it MLIR first, on ranked tensors and
One-Shot Bufferize. The self-hosted compiler stands on today's arrays:
the fork's `Libraries/Data/Table.idr` is a growable `Linear.Array`, Core
threads `Data.IORef`, and its binary format reads and writes
`Data.Buffer` (*read*: their imports). Those users are ported in the
same change, and `make self` stays green across it.

## 7. Measures

- The suite's compile-time record, total and the ten slowest, against
  G0; the two set-aside programs within their limits.
- The stage-0 dump: functions, operations, bytes, after H1 and H2.
- The pipeline on the stage-0 dump: wall and user time per pass and per
  analysis, first recorded at S and compared with G0's extrapolation.
- Rounds to the fixpoint per program, before and after C4.
- The bench on both targets by ratio to C, against the last records: no
  program worse beyond the run-to-run spread, or it is bisected.
- Determinism: one thread against the pool, byte for byte, on every
  program of `tests/determinism`.

## 8. Rejected alternatives

- **Cutting constant factors further** (the path of the last three
  commits): lookups and memos leave the three terms of §1 in place.
- **The sharded compiler (0011) now**: the in-process split of §5.3 is
  its precondition and most of its gain on one machine; sharding across
  processes is for later and needs 0010.
- **Parametric `!idr.data<@T, [...]>`** (the brief's §3.12): a change to
  every pass's type handling for no effect on the wall. Deferred to a
  proposal of its own with a measurement.
- **Dropping grades from the IR to shrink it**: AGENTS.md forbids it, and
  it is not where the bytes are; erased positions and names are.
- **Keeping C++20 modules in `foreign/idr`**: the profile fights the
  framework, two pins exist because of it, and the build cannot be
  cached.
- **A larger round budget or longer test limits**: they hide the bug the
  two programs show.
- **Static normalization (0016) as the fix**: it shrinks what the
  frontend emits later and is wanted, but it does not change how the
  C++ side walks what it is given.
- **A fresh C++ side**: the decisions in the passes are right and tested
  (`tests/idr`, 256 fixtures); they are re-housed, not rewritten.

## 9. Decisions

- D1 (owner): this proposal starts first; self-hosting (§6.1) follows,
  then sharding; every other proposal waits for them; what remained of
  the LLVM pin and of the representation cutover is G1 (§12).
- D2: `foreign/idr` is written as an in-tree MLIR dialect, in upstream's
  layout and build, without C++20 modules; the hardening flags are a
  preset, not the Release build.
- D3: every rewrite is a function pass under a nested pass manager;
  module passes only compute analyses or change symbols; no pass holds
  IR-derived state across runs, and nothing of ours is thread-local or
  atomic.
- D4: one representation per fact: `idr.func` carries the facts of a
  function as inherent data; every other fact is an analysis under the
  manager or a lattice on the solver.
- D5: the frontend emits no quantity-0 position, no newtype constructor,
  no shim where the implementation is fixed, functions at arity, keys
  alpha-normalized in attributes; grades of one and of ownership stay
  types.
- D6: the round is a sequence of facts, local rewrites and symbol
  changes; it ends on a change flag, bounded, and the bound is measured.
- D7: a stage lands only with its proof in §6; a stage that makes the
  compile-time record worse is not taken until it does not.

## 10. Rules changed

The cutover carried these out with C1; they stand as its record.
When C1 lands: AGENTS.md's "C++ in `foreign/idr/`, following
bjornpagen/cpp-starter" becomes "C++ in `foreign/idr/`, an in-tree MLIR
dialect in upstream's layout and conventions"; PINS.md's `mlir-cxx-api`
and `zones-on-demand` entries are retired with it. Three `make check`
rules change in the same commit (*read*: `tests/spec/*/run`):
`spec/cpp-starter` becomes the rule of the MLIR layout (the `dev`,
`release`, `lint` and new `hardened` presets, `-Werror`, no exceptions
or RTTI, no `asan-ubsan`); `spec/file-size` and `spec/verifier-every-pass`
search `.cpp` and `.h` where they search `.cc` and `.cppm`. The 400-line
ratchet of `spec/file-size` and the rule that nothing turns the verifier
off stay as they are. No other rule of AGENTS.md changes: the grades stay
in types, the verifier still checks after every pass, tests still check
behaviour.

Static normalization is now 0016's. Its differential against
`idr-eval` is gone with the pass (96e1d308, and the cutover deleted what
remained), so it is proved against the committed outputs of
`tests/programs/eval` and the corpus instead; 0016 records that.

## 11. Open questions for the owner

- The Release preset: full LTO with no sanitizer, or keep UBSan traps in
  Release until the first measurement says what they cost? G0 can
  measure both builds on the suite.

Two earlier questions are settled by the cutover: `idr.func` replaced
`func.func` in the handoff at once, and the frontend's instances and the
C++ clones share one key representation, `#idr.instance`.

## 12. What remains of the LLVM pin and the representation cutover

Both were integrated before this proposal: the LLVM pin is llvm main
7208ba24, built by one recipe for both targets (`tools/bootstrap.sh`), and
the representation cutover is in the tree (93f5d9c9, 327c2e30,
0451b1b8). On arm64 macOS at 8395d4f7 `make build` passed, `make check`
was 26/26, `make test-idr` 269/269 and `make test-mlir-tools` 17/17, and
`make self` (1ce907d3) built stages 1 to 3 with stage 2 matching stage 3
(*measured*, recorded then). None of it has run on the cutover tree.
What follows is G1. A target that has not run an item is NotRun, never
green.

**Not run.**

- **x86_64 Linux.** `tools/bootstrap.sh llvm` (stage 1, the target's C
  library, the runtimes and stage 2, into `.toolchain/llvm`), then
  `make build`, `make check`, `make test`, `make test-idr` and
  `make test-mlir-tools`. It is also the first run of the runtime
  platform layer's Linux branches, and the Linux check of the retirements
  PINS.md records, observed on arm64 only. A failure that reproduces with
  upstream dialects and tools is a patch in `upstream/`; any other is
  ours, fixed in the tree.
- **The bench.** `bench/run.sh` on each target, compared with that
  target's last record (`bench/runs/2026-10-07-f5a4dff9-darwin-arm64`,
  `bench/runs/2026-10-03-861acdc`) by each program's ratio to its own C
  (`bench/README.md`); the ratio to C takes out the clang both columns
  share. A program whose ratio is worse beyond the run-to-run spread is a
  regression, bisected and fixed. Chez's column is not part of the
  comparison, so a Chez time-out does not stop the run.
- **Peak live cells of `thunk-consumes-list`.** The runtime reports live
  cells only at exit (`runtime/Io/Ending.cpp`), and a peak counter would
  put a compare on every allocation. The measure is max RSS at two lengths
  of the consumed list, 10^5 and 10^6: bounded means the larger run's max
  RSS is less than twice the smaller's, where a list kept alive gives ten
  times.
- **`tests/upstream-idris/run`.** Its `common.sh` still skips base's
  pointer and environment functions as raw pointers, which compile as
  runtime handles. That skip goes, then it runs, and its results show
  the tests that now pass (file, directory, clock and environment).

**Not proved.**

- **Compile times.** The last whole-suite record met its bound (649
  compilations, 1551.3 s against 1440.0 s, x1.08). G0 re-records it on
  the cutover tree; `bounds-unrelated-size`, `every-io-export` and
  `io-loop-through-helper` are read with pass timing there, and a pass
  that grew is fixed or its cost stated.
- **Sensitivity.** Of the 32 program, accept and reject rows, 13 fail at
  the launch base and so discriminate, and the rest pass there by design
  as non-regression rows.

**The owner's decision not yet carried out.** `--demand in-place` stays
opt-in until the bench run above passes with it on; then it is the
default.

**Seams left in the tree.** Read after the cutover, before its build; each
is rechecked at G1 and fixed where the representation can say it once:

- `isCell` in `foreign/idr/lib/Conversion/Facts.cpp` still names
  `FnType` and `LazyType`;
- which memo labels are `by_name` is decided by a list in
  `Transforms/Defunctionalize/ByName.cpp`, where a trait would say it
  once;
- `closureLabel` does not see memo labels;
- `--demand` with `--without idr-demand` is accepted silently;
- an `array.new` fill function that never returns is an internal error;
- a partially applied `castPtr` is still rejected.
