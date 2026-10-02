# MLIR survey: what the pinned tree offers that we do not use yet

Research note, 2026-10-02, against our tree at 57b22ac and the pinned MLIR
in `.toolchain/llvm-project` (commit 85ac5602, the lock's `llvmorg-23.1.2`,
`toolchain.lock.json:6`). Paths starting with `mlir/` are in that tree.

The question: what in the pinned MLIR could replace code of our own, make a
pass of ours unnecessary, or add a capability we want, grounded in our
pipeline (`foreign/idr/lib/Registration.cc:16-44`, the simplify round in
`foreign/idr/lib/Passes/Simplify.cc:207-228`) and our measurements
(`bench/README.md`). The rules it serves are AGENTS.md's: as much work as
possible done by upstream MLIR, facts proved by Idris kept in types, nothing
dropped silently.

Status of claims: **read** (the code, both trees), **measured** (run here
with the pinned `mlir-opt`), **conjecture** (reasoned, not run). A claim
without a mark is read.

## Short answer

- The pipeline already leans on upstream where upstream fits: `canonicalize`,
  `cse`, `sccp`, `int-range-optimizations`, `symbol-dce`,
  `remove-dead-values`, the inliner (with our profitability callback), the
  region-branch canonicalization patterns on our matches, `inlineCall`,
  `moveLoopInvariantCode`, `upliftWhileToForLoop`, the DataFlow solver
  (three analyses of ours run on it), `IntegerRangeAnalysis`, the remark
  engine, the action tracer and debug counters, the structural type
  conversion of `scf`, 1:N dialect conversion, the LLVM target passes. What
  remains ours is either a decision MLIR cannot take for us (what to
  specialize, what to borrow, what to reuse, what is a continuation) or a
  workaround with a report in `upstream/`.
- Of the mechanisms we do not use, three are worth work now: `missed`
  remarks on every transformation a pass declines (§1), the value-bounds
  interface for array indices (§2), and moving our hand-rolled fixpoint
  analyses onto the solver and `Liveness` (§3). One finding is a missing
  upstream report: `composite-fixed-point-pass` cannot host our simplify
  loop because `sccp` defeats its fixpoint test, which we measured (§6).
- Nothing in the pinned tree replaces `idr-stack`, `idr-rc`, `idr-narrow`,
  `idr-specialize`, `idr-defunctionalize`, `idr-contify` or `idr-trmc`: the
  nearest upstream mechanisms (`mem2reg`/`sroa`, `promote-buffers-to-stack`,
  ownership-based deallocation, `arith-int-range-narrowing`,
  `duplicate-function-elimination`, the inliner's SCC rule) work on a
  different representation or decide a different question; the long tail
  says which precondition each would need.
- The effects census (§C) finds no declaration an upstream pass turns into a
  wrong answer today. Three declarations are sound by pipeline order or by
  the owned-stage verifier rather than by what they say, and one folder has
  a latent hole (`FieldOp::fold` on a pending field); they are listed with
  what would make each honest.

## The baseline: what upstream already does for us

- The pipeline steps (`Registration.cc:17-43`): `idr-contify`,
  `idr-simplify`, `idr-defunctionalize`, `canonicalize`, `idr-stack`,
  `idr-rc`, `idr-trmc`, `idr-tail-loops`, `idr-narrow`, `idr-lower`,
  `canonicalize,cse`, `idr-returned-arguments`, `canonicalize,cse`,
  `convert-scf-to-cf,convert-to-llvm,reconcile-unrealized-casts`. The
  simplify round (`Simplify.cc:207-228`): `idr-loop-breakers`,
  `idr-effects`, `idr-inline{default-pipeline=idr-canonicalize}`,
  `idr-specialize`, `sccp`, `int-range-optimizations`, `idr-canonicalize`,
  `cse`, `idr-eval`, `idr-prune`, `symbol-dce`,
  `remove-dead-values{canonicalize=false}`, `symbol-dce`.
- Every pass manager verifies after every pass: `PassManager` starts with
  `verifyPasses(true)` (`mlir/lib/Pass/Pass.cpp:1023`), and
  `idris-mlir-cc` builds one per step (`foreign/idr/tools/idris-mlir-cc.cc:539-557`),
  so `-verify-each` is on without asking. The owned-stage rule runs as the
  verifier of `idr.stage` (`foreign/idr/lib/Dialect/Dialect.cc:773-779`),
  which is what AGENTS.md means by "the verifier checks after every pass".
- Our ops carry the interfaces upstream passes read: `MemoryEffectsOpInterface`
  and `ConditionallySpeculatable` through `Idr_MayCrash`
  (`foreign/idr/include/idr/IdrOps.td:291-309`, `foreign/idr/include/idr/Idr.h:143-175`),
  `RegionBranchOpInterface` with invocation bounds on both matches
  (`foreign/idr/lib/Dialect/Ops.cc:903-969`), `InferIntRangeInterface` on
  every op that computes an integer or a big (`IdrOps.td:361-363, 407-408,
  843-846, 861, 900-901, 912-913, 926-929, 940, 952, 970, 979`), and
  `func.call` answers `MemoryEffectOpInterface` from the callee's facts
  (`foreign/idr/lib/Facts/CallEffects.cc:29-53`). The upstream consumers
  and their rules: canonicalize's dead-op erasure keeps an op whose effects
  are more than allocations of its own results and reads
  (`mlir/lib/Interfaces/SideEffectInterfaces.cpp:43-110`); CSE merges ops
  that are memory-effect free, or have a single `Read` with no conflicting
  write between (`mlir/lib/Transforms/Utils/CSE.cpp:264-274, 168-230`);
  LICM's pass hoists `isPure` ops (`mlir/lib/Transforms/Utils/LoopInvariantCodeMotionUtils.cpp:111-118`);
  `control-flow-sink` sinks `isMemoryEffectFree` ops
  (`mlir/lib/Transforms/ControlFlowSink.cpp:44-46`); `remove-dead-values`
  keeps what liveness marks live: operands of ops with memory effects,
  returns of public functions, and what computes those
  (`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp:51-77`).
- The facts the dialect derives for its own patterns are the same
  declarations read once more: `onlyAllocates` and `performsIO`
  (`Dialect.cc:821-866`) classify an op by its effect instances, so
  case-of-case and sinking (`foreign/idr/lib/Dialect/Canonicalize/{CaseOfCase,Sink}.cc`)
  move an op exactly when its declarations allow.

## Top ten

Ranked by expected value against our measurements, cheapest first among
equals. Each names what it is, what of ours it replaces or improves, the
precondition, the risk and what it moves.

### 1. `missed` remarks wherever a pass declines (capability; cheap)

- **What:** the remark engine (`mlir/docs/Remarks.md:58-98`;
  `mlir/include/mlir/IR/Remarks.h:739-744`) has four kinds; we emit
  `Passed`, `Analysis` and, in `idr-eval` only, `Missed`
  (`foreign/idr/include/idr/Passes.td`, IdrEval's description;
  `foreign/idr/lib/Canonicalize/Pass.cc:104-111`). `RemarkEmittingPolicyFinal`
  (`Remarks.h:655-662`, `Remarks.md:200-216`) keeps only the last remark
  per location, so a loop a later round does uplift is not reported as
  missed by the round before.
- **Improves:** every place a pass gives up without a word: a function whose
  self call is not in tail position or whose decision form fails
  (`foreign/idr/lib/Passes/TailLoops.cc:544-554`), a counted loop kept as
  `scf.while` because its counter is used after (`TailLoops.cc:516-523, 568`,
  the `uplift-final-counter` pin), a web `idr-narrow` does not prove small
  (`foreign/idr/lib/Passes/Narrow.cc:216-223, 436-449`), a cell that escapes
  (`foreign/idr/lib/Stack/Pass.cc:56-60`, with the use that lost it,
  `Stack/Escape.cc:148-199`), a parameter borrow inference leaves owned
  (`foreign/idr/lib/Ownership/Borrow.cc:6-19`), a value exclusivity finds
  shared (`Ownership/Exclusive.cc:136-169`, the op that shared it), a call
  specialization refuses by binding time (`foreign/idr/lib/Specialize/Specialize.cc:52-57`).
  The ablation table (`bench/README.md:107-134`) says what each mechanism
  is worth; the remarks would say, per program, where each one stopped.
  This is the brief's "a loop left scalar" for the loops we have today.
- **Precondition:** none; `idris-mlir-cc --remarks=<category>` and
  `--remarks-file` already stream every kind (`idris-mlir-cc.cc:463-482`;
  `tests/idr/obs/round-trace.mlir`). A `reason` per decline, an enum of
  reasons per pass as `findings/simd.md` §6 proposes for vectorization.
- **Risk:** none at runtime (opt-in); a test that matches remark text goes
  stale on wording, so tests state a reason's name, not its sentence.
- **Moves:** nothing in the table directly; it is how the next ten rows get
  diagnosed. Code: the `return failure()` and `continue` sites above.

### 2. `ValueBoundsOpInterface` for array indices and Idris's own range tests

- **What:** `mlir/include/mlir/Interfaces/ValueBoundsOpInterface.h` builds
  an affine constraint set over index-typed values and shaped dimensions
  and answers `compare(lhs, LT, rhs)`, `computeConstantBound`,
  `computeConstantDelta` (`:238-292`). `scf.for` induction variables,
  `arith` ops, `memref.dim` and friends implement it
  (`mlir/lib/Dialect/{Arith,SCF,MemRef,Tensor,Vector,Affine,Linalg,GPU}/IR/ValueBoundsOpInterfaceImpl.cpp`).
  Integer-typed values are admitted with `ValueBoundsOptions::allowIntegerType`
  (`:60-65`).
- **Improves:** `ArrayGetOp`/`ArraySetOp::getCrashCause` always answers
  "out of bounds" (`Ops.cc:1269-1270`), so every array access carries a
  crash effect and `idr-lower` emits a check (`foreign/idr/lib/Lower/Arrays.cc:49-53, 111-112, 132-133`)
  that LLVM later folds against the program's own test (`Arrays.cc:5-7`).
  With the bounds proved before lowering, an access in a loop over
  `[0, memref.dim)` would have no crash effect (the op becomes IO only),
  and the program's own `arith.cmpi slt %i, %len` (Idris's `pos < max arr`)
  folds in MLIR by the same query, which `int-range-optimizations` cannot
  do (two symbolic values). The same query answers `idr.str.index`
  (`Ops.cc:1162-1172`).
- **Precondition:** the index derives from an `scf.for` induction variable
  bounded by `memref.dim` of the same array, so loops must be `scf.for`
  (idr-tail-loops' uplift, `TailLoops.cc:564-575`); indices stay `i64`
  (`IdrOps.td:1186, 1201`) with `allowIntegerType`; the array's `memref.dim`
  is the one memref op the contract keeps (`foreign/idr/lib/Lower/Pass.cc:160-161`).
  A query from `getCrashCause` must not mutate IR (the interface is a
  pure analysis).
- **Risk:** the value-bounds infrastructure "assumes that such integer
  computations do not overflow" (`ValueBoundsOpInterface.h:62-64`), and the
  `arith` implementation reads no `nsw`/`nuw` flags (no such handling in
  `mlir/lib/Dialect/Arith/IR/ValueBoundsOpInterfaceImpl.cpp`, read).
  Idris's `Int` wraps, so only indices built from induction variables or
  from `idr-narrow`'s `nsw` words (`Narrow.cc:165-168`) may enter the
  constraint set; an `arith.addi` without flags must stop the query. That
  is a guard of ours around an upstream analysis, not a new analysis.
- **Moves:** fannkuch-redux, 0.72x of C, which "pays Idris's own range test
  before the compiler's" (`bench/README.md:40, 99-106`); unionfind at
  0.77x, whose remaining check is in `find`'s recursion
  (`bench/README.md:58, 81-91`), which is not a counted loop and gains
  nothing here (conjecture); the `Fin n` indices of `findings/simd.md`
  §2.2 and §3, whose bound is in the type. Whether the MLIR-level proof
  beats LLVM's fold at the end is conjecture: the measured gap may be the
  `Maybe` tag and IO plumbing (`bench/README.md:99-106`), not the check.

### 3. Hand-rolled fixpoints onto the DataFlow solver and `Liveness`

- **What:** `SparseBackwardDataFlowAnalysis` with `visitBranchOperand`,
  `visitCallOperand` and `setToExitState`
  (`mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:405-445, 522-548`);
  `mlir::Liveness` with `isDeadAfter`, `getLiveIn`, `getLiveOut`
  (`mlir/include/mlir/Analysis/Liveness.h:43-78`); the sparse forward
  framework we already run three analyses on (`foreign/idr/lib/Passes/Defunctionalize.cc:1-13`,
  `Ownership/Exclusive.cc:12-16, 131-187`, `Narrow.cc:44-73`).
- **Replaces (conjecture on size):** the worklist over functions with
  parameter summaries in `Stack/Escape.cc:66-95` and the graph it reverses
  (`:108-146`), which is a backward "may escape" analysis with an
  interprocedural call-operand rule (`:186-197`); the module-wide
  "until nothing changes" of borrow inference (`Ownership/Borrow.cc:6-19, 43-60`);
  the greatest-fixpoint refinement of `idr-returned-arguments`
  (`foreign/idr/lib/Passes/ReturnedArguments.cc:57-80`); the `usedAfter`
  search that Perceus placement relies on (`Ownership/Ownership.h:63-65`,
  `Ownership/Counts.cc:1-28`), which `Liveness::isDeadAfter` and the
  per-block live-out sets answer, nested regions included. About 1,100
  lines of our own fixpoint machinery sit in these four files.
- **Precondition:** each analysis must fit the framework's joins. Escape
  needs two lattice points per value (shallow and deep, `Escape.cc:62-64`),
  which a product lattice gives. Returned-arguments needs "callee's
  argument j" relabelled to "the operand passed at this call" when a call's
  result is joined from the callee's returns; the sparse framework joins
  return-operand lattices into call results directly, so the relabelling
  is a custom `visitExternalCall`/call hook of ours (conjecture that it
  stays small). Borrow inference's rule "an owned value passed by a tail
  call from the same cycle" (`Borrow.cc:13-15`) is a property of the call
  graph, which the solver does not see; it stays a pre-pass.
- **Risk:** behaviour must not change; the fixtures that pin these passes
  (`tests/idr/stack/*`, `tests/idr/rc/*`, `tests/idr/returned/arguments.mlir`,
  `tests/programs/linear/*/mlir.expect`) are the check. The solver's
  interprocedural mode is what `idr-prune` and `idr-narrow` already use
  (`Prune.cc:110`, `Narrow.cc:494`).
- **Moves:** no benchmark; code weight, and one worklist discipline instead
  of four. Where a pass's rule is a dataflow rule, the solver is the
  "mechanism we are not using yet".

### 4. `arith-int-range-narrowing` and `arith-unsigned-when-equivalent` after `idr-narrow`

- **What:** `arith-int-range-narrowing{int-bitwidths-supported=32}` narrows
  elementwise ops, comparisons and loop bounds whose ranges fit
  (`mlir/include/mlir/Dialect/Arith/Transforms/Passes.td:60-80`;
  `mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:350-712`);
  `arith-unsigned-when-equivalent` turns signed division, remainder, shifts,
  min/max and comparisons unsigned when operands and results are proved
  non-negative (`Passes.td:31-44`).
- **Improves:** `idr-narrow` makes a proved natural an `i64` with `nsw|nuw`
  and signed comparisons (`Narrow.cc:165-184, 254-258`); nothing after it
  shrinks the word or picks the unsigned form. Upstream does both from the
  same `IntegerRangeAnalysis`, seeded by our `NaturalRanges` (`Narrow.cc:44-66`)
  if the pass is given that analysis (the upstream passes load the stock
  one: `IntRangeOptimizations.cpp:715-766`), or by the ranges the narrowed
  `arith` ops carry anyway.
- **Precondition:** runs after `idr-narrow` and before `idr-lower` on
  `arith` and `scf.for`; our array index stays `i64` (`IdrOps.td:1186`), so
  a narrowed counter meets an `arith.extsi` at the access. `NarrowLoopBounds`
  writes `arith.bounds_narrowing_failed` on a loop it gave up on
  (`IntRangeOptimizations.cpp:539-547`), a discardable attribute of another
  dialect on an `scf.for`, which our attribute rule allows on non-idr ops
  (`Dialect.cc:868-885`).
- **Risk:** low; `nsw` on the narrowed op is what makes the narrowing sound,
  and `idr-narrow` writes it. Value only shows with vectorization: the
  spectral-norm experiment that beat clang used "int-range narrowing to
  i32" (`findings/simd.md` §7, read there, not measured here).
- **Moves:** nothing until the vectorization lane lands; then lane count
  per register for index arithmetic.

### 5. The Transform, Linalg and Vector stack: preconditions for the lane on it

- **What (read):** `transform-preload-library` and `transform-interpreter`
  (`mlir/include/mlir/Dialect/Transform/Transforms/Passes.td:45-70`) run a
  schedule from a `.mlir` library; `transform.structured.vectorize`,
  `tile_using_for`, `fuse`, `split_reduction`
  (`mlir/include/mlir/Dialect/Linalg/TransformOps/LinalgTransformOps.td:2558, 2248, 416, 1801`);
  the vector lowerings as transform ops (`mlir/include/mlir/Dialect/Vector/TransformOps/VectorTransformOps.td:151, 181, 195, 338`);
  `linalg::vectorize` in C++ with masking (`mlir/include/mlir/Dialect/Linalg/Transforms/Transforms.h:1013`);
  `convert-vector-to-llvm` keeps floating reductions ordered unless
  `reassociate-fp-reductions` (`mlir/include/mlir/Conversion/Passes.td:1624`);
  `scf.forall` and `scf.parallel` exist (`mlir/include/mlir/Dialect/SCF/IR/SCFOps.td:333, 815`)
  with `scf-forall-to-for`, peeling and specialization
  (`mlir/include/mlir/Dialect/SCF/Transforms/Passes.td:24-42, 116-124`).
- **Preconditions, stated not planned:** an index space as `linalg.generic`
  over `tensor`/`memref` (the raising `findings/simd.md` §5.1 calls ours);
  `scf.for` loops, never `scf.while` (the uplift pin keeps some as
  `scf.while`, §9 below); effects honest on every op inside the body
  (`linalg.generic` bodies are speculated under masks: `simd.md` §3), which
  §C's census is for; `vector.shuffle`'s mask is static
  (`DenseI64ArrayAttr`, `mlir/include/mlir/Dialect/Vector/IR/VectorOps.td`,
  the `ShuffleOp` definition) and the X86 dialect at this pin has
  dot-product, mask, tile and BF16 ops but no byte shuffle
  (`mlir/include/mlir/Dialect/X86/X86.td:47-1029`), so fannkuch's `pshufb`
  flip is the upstream gap `simd.md` §5.4 names (read).
- **Risk:** the transform interpreter is a second program alongside the
  pass pipeline; `simd.md` §5 chose the C++ utilities. Either way the
  width lives in the target entry (`simd.md` §2.3).
- **Moves:** spectral-norm (0.77x), the n-body SoA form, mandelbrot's lane
  predication (`simd.md` §7); the lane working on it owns the measurement.

### 6. The simplify loop stays ours; the reason is an upstream report we have not filed

- **What:** `composite-fixed-point-pass` (`mlir/include/mlir/Transforms/Passes.td:598-613`)
  runs a pipeline until `OperationFingerPrint` stops changing or
  `max-iterations`, then only warns (`mlir/lib/Transforms/CompositePass.cpp:68-91`).
  `idr-simplify` (`Simplify.cc`) does the same with a structural hash
  because `sccp` re-materializes every constant each run
  (`Simplify.cc:10-18`, `mlir/lib/Transforms/SCCP.cpp:45-60`), and ends in
  `unsupported (compile-time budget)` instead of a warning.
- **Measured:** with the pinned `mlir-opt` on a four-line module that is
  already at its fixpoint, `composite-fixed-point-pass{pipeline=sccp
  max-iterations=5}` and `{pipeline=sccp,canonicalize max-iterations=5}`
  both warn `didn't converge in 5 iterations`; `{pipeline=canonicalize}`
  converges after one round. So the composite pass cannot host a round
  with `sccp` in it, and `idr-simplify`'s hash is a workaround for upstream
  behaviour, which AGENTS.md says needs its report in `upstream/`, its
  `tests/upstream/` check and its `PINS.md` entry.
- **Replaces:** nothing; keep `Simplify.cc:137-176`. The report proposes
  either a fingerprint that hashes constants by value, or `sccp` reusing
  the constant it already has (`OperationFolder::getOrCreateConstant` does
  dedupe within a block, but the old constant is erased and a new one made,
  so the pointer-based fingerprint moves; conjecture on the exact cause).
- **Risk:** none; a report. **Moves:** compile time if upstream fixes it
  and the round's own `canonicalize` stops re-hoisting constants every
  round.

### 7. `control-flow-sink` beside our sinking

- **What:** `control-flow-sink` (`mlir/include/mlir/Transforms/Passes.td:65-86`)
  moves an op whose uses are all in one region that runs at most once into
  that region, never duplicating (`mlir/lib/Transforms/Utils/ControlFlowSinkUtils.cpp:78-125`);
  it asks `getRegionInvocationBounds`, which both matches answer
  (`Ops.cc:925-929, 943-946, 962-965`), and moves `isMemoryEffectFree` ops
  only (`ControlFlowSink.cpp:46`).
- **Improves:** our `SinkIntoRegions` (`Canonicalize/Sink.cc`) moves an op
  only when it meets a consumer it folds against, into every region that
  uses it, within a budget (`Sink.cc:1-17, 26, 63-81`), and admits
  allocating ops and, on every path, crash-capable ones (`Sink.cc:51-61`).
  Upstream's is the complementary rule: unconditional, single region, Pure
  only, so work leaves the paths that do not need it with no profit test.
- **Precondition:** met. **Risk:** it sinks `arith.constant`s too (no
  constant exclusion in `ControlFlowSinkUtils.cpp`, read), which the
  folder hoists back to the entry block on the next canonicalize; our
  fixpoint hash ignores where constants sit (`Simplify.cc:147-149, 153-158`),
  so the round converges, at the cost of churn. Allocating ops
  (`idr.con` of a box, string builders, big ops) are not memory-effect free
  and stay where they are; our pattern keeps that case.
- **Moves:** nothing measured; every match whose one arm needs a Pure
  value computed before it. Low expected value; cheap to try as a round
  member after `idr-canonicalize`.

### 8. `duplicate-function-elimination` on clones

- **What:** merges functions equal in all but name and redirects their uses
  (`mlir/include/mlir/Dialect/Func/Transforms/Passes.td:14-22`;
  `mlir/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:22-78, 94-111`).
- **Improves:** `idr-specialize` shares clones by key before they exist
  (`foreign/idr/lib/Specialize/Clones.h:1-7, 19-22`), not by body after;
  two clones of different keys that simplify to the same body stay two,
  through `idr-rc`, `idr-lower` and LLVM until `MergeFunctions`
  (`foreign/idr/lib/Lower/Target.cc:21`) folds them at the end.
- **Precondition:** the pass compares discardable attributes
  (`DuplicateFunctionElimination.cpp:59-62`), and a clone's `idr.clone`
  names the clone itself (`IdrOps.td:1408-1419`), so no two clones are ever
  equal; and a clone's self calls name it, so bodies differ by callee. To
  use it: compare without `idr.clone`/`idr.hole` and with self-references
  canonicalized, which is an option upstream does not have (conjecture:
  an `exclude-attributes` option is a small upstream change).
- **Risk:** a merged clone must keep the key table consistent (`Clones.h:35-71`);
  `one-clone=@f` fixtures (`tests/idr/expect/one-clone.mlir`) state the
  property. **Moves:** compile time, 1.9 to 13.7 s per program with
  fannkuch-redux, regex-redux and spectral-norm the slow ones
  (`bench/README.md:60-62`); `ack`'s clones that "LLVM closes"
  (`bench/README.md:169-171`) would close earlier. Modest.

### 9. The uplift pin costs narrowing too: `IntegerRangeAnalysis` bounds only `scf.for`

- **What (read):** the range analysis seeds induction variables from
  `LoopLikeOpInterface` bounds (`mlir/lib/Analysis/DataFlow/IntegerRangeAnalysis.cpp:149-200`)
  and widens loop-carried values that keep growing to top
  (`mlir/include/mlir/Analysis/DataFlow/IntegerRangeAnalysis.h:28-45`).
  `scf.while` has no induction variable, so a counter kept in an
  `scf.while` is widened, never bounded.
- **Improves:** `idr-tail-loops` keeps a counted loop as `scf.while`
  whenever its final counter is used (`TailLoops.cc:516-523, 568`), because
  upstream's uplift returns the value one step short
  (`PINS.md` `uplift-final-counter`; `mlir/lib/Dialect/SCF/Transforms/UpliftWhileToFor.cpp:252-265`).
  Such a loop's counter then never narrows in `idr-narrow` (its web is top),
  and never qualifies for §2 or §4. The pin's recorded cost is "stays an
  `scf.while`"; its real cost includes every range-based pass after it.
- **Precondition for the fix:** upstream's correction (the report in
  `upstream/uplift-final-counter`), or our own: after a successful uplift,
  reconstruct the final value as `lb + ceildiv(ub - lb, step) * step` and
  substitute it for the `scf.while` result (conjecture: twenty lines in
  `TailLoops.cc`, no new mechanism), then uplift every counted loop.
- **Risk:** the reconstruction must match the loop's exit value exactly,
  including zero iterations (the lower bound), which is the bug's own
  statement. **Moves:** the `counted-loop` property
  (`foreign/idr/lib/Expect/Loops.cc:57-81`) for loops whose counter is
  returned; the Nat decision's "a counted-down loop has no tag test
  inside" (`findings/decision-nat.md`, Tier 1) for those loops.

### 10. Actions for bisection on the decisions that matter

- **What:** `tracing::Action` with `-mlir-debug-counter=<tag>-skip=N,<tag>-count=M`
  and `-mlir-print-debug-counter` (`mlir/docs/ActionTracing.md:148-212`);
  `idr-eval-call` is already one (`tests/idr/obs/debug-counter.mlir`), and
  `--log-actions-to` with `--log-actions-tags` is wired
  (`idris-mlir-cc.cc:485-496`).
- **Improves:** the decisions a wrong answer or a slow program would be
  bisected over are not actions yet: a clone made (`Specialize/Specialize.cc`,
  `Specialize/Raise.cc`), a call contified (`Contify.cc:92-101`), a cell
  marked for the stack (`Stack/Pass.cc:62`), a take and reuse inserted
  (`Ownership/ResetReuse.cc`), a parameter borrowed (`Borrow.cc`), a web
  narrowed (`Narrow.cc:522-526`). With a counter, `--without` (`bench/README.md:107-134`)
  becomes per-decision instead of per-mechanism.
- **Precondition:** single-threaded context (the counter handler is not
  thread-safe, `ActionTracing.md:168-170`); ours already runs one pass
  manager per step on a module. **Risk:** none; **Moves:** debugging time,
  and the ablation table's granularity.

## The long tail

| Mechanism (pinned path) | What of ours it touches | Verdict and precondition |
| --- | --- | --- |
| `mem2reg`, `sroa` with `MemorySlotInterfaces` (`mlir/include/mlir/Transforms/Passes.td:400-429, 452-486`; `mlir/include/mlir/Interfaces/MemorySlotInterfaces.td:14-88, 448-576`) | `idr-stack` (`Stack/`), the cells it puts in `llvm.alloca` byte arrays (`Stack/Cell.cc:11-28`) | No. They promote loads and stores of an existing slot to SSA; `idr-stack` decides which heap cells may be slots at all (escape analysis on boxes), a question neither asks. After lowering, our slot is `!llvm.array<N x i8>` written through byte GEPs; LLVM's own SROA handles it at O3 (`Lower/Target.cc:28`). MLIR's would need a struct-typed alloca with typed accesses (`mlir/lib/Dialect/LLVMIR/IR/LLVMMemorySlot.cpp:141, 416-428, 839-856`), for a job LLVM already does. Conjecture: no measurable gain. |
| `promote-buffers-to-stack` (`mlir/include/mlir/Dialect/Bufferization/Transforms/Passes.td:572-592`) | `idr-stack` | No. It moves `memref.alloc` to `memref.alloca` by size and rank; our boxes are not memrefs, and our arrays are runtime cells with counts (`Lower/Arrays.cc:1-7`). Precondition: arrays as `memref.alloc`, which the count in the cell header rules out. |
| One-Shot Bufferize and ownership-based deallocation (`mlir/docs/Bufferization.md:30-67, 282-288`; `mlir/docs/OwnershipBasedBufferDeallocation.md:55-76, 206-226`) | arrays as `memref` (`findings/decision-inhouse-linear.md`) | Limits, read: function boundaries are not bufferized by default and "recursive calls are not supported" (`Bufferization.md:282-285`); the dealloc ABI never acquires ownership of an argument and "must not return a MemRef with the same allocated base buffer as one of its arguments (in this case a copy has to be created)" (`OwnershipBasedBufferDeallocation.md:61-70`), which is exactly what a threaded array does on every read and write (`idr-returned-arguments` exists for it, `ReturnedArguments.cc:1-15`). The decision to keep arrays as counted memrefs stands; tensors wait for value-semantic `Vect`. |
| `loop-invariant-code-motion`, `loop-invariant-subset-hoisting` (`Passes.td:392-398`) | `TailLoops.cc:558-562` | Already used through `moveLoopInvariantCode` with our predicate (`invariantCode`, `TailLoops.cc:534-537`: pure, speculatable, and no owned result, since an owned value hoisted out is consumed once per iteration). The pass's default is `isPure` (`LoopInvariantCodeMotionUtils.cpp:111-118`) and would hoist an owned `idr.con` of an unboxed sum out of a loop; ours is right to be stricter. Subset hoisting is for `tensor.extract_slice`/`insert_slice` pairs (`:122-227`): the tensor path only. |
| `affine-raise-from-memref`, `affine-scalrep`, `affine-loop-fusion`, `affine-super-vectorize`, `affine-simplify-with-bounds` (`mlir/include/mlir/Dialect/Affine/Transforms/Passes.td:398-409, 300, 46, 346, 433`) | arrays and loops | Far. Raising needs `affine.for` around `memref.load/store`; our loops are `scf.for`/`scf.while` and our accesses are `idr.array.*` on the world, lowered to GEPs into a runtime cell, never `memref.load`. Precondition: arrays accessed through `memref` ops over a view of the cell's elements, and loops as `affine.for` (bounds affine in symbols), which the raising lane would produce; then `affine-scalrep` forwards a store to the load that follows it in fannkuch's swap. Conjecture. |
| `scf` loop transforms: peeling, specialization, rotation, zero-trip check, `promoteIfSingleIteration`, `replaceWithAdditionalYields` (`mlir/include/mlir/Dialect/SCF/Transforms/Passes.td:24-42`; `Transforms.h:59-107`; `Patterns.h:83-85`; `mlir/lib/Dialect/SCF/Transforms/{RotateWhileLoop,WrapInZeroTripCheck}.cpp`; `mlir/include/mlir/Interfaces/LoopLikeInterface.td:90, 228`) | `TailLoops.cc` | Peeling and specialization serve vectorized tails (§5). Rotation makes a do-while of our while-do loops; LLVM rotates loops itself at O3, so no gain expected (conjecture). `replaceWithAdditionalYields` could simplify how `WhileDo` carries arguments, a code-shape change only. |
| `scf-for-loop-canonicalization` (`Passes.td:16-22`) | loops with `affine.min/max` | Nothing to do: we have no affine ops. |
| `IntegerDivisibilityAnalysis`, `StridedMetadataRangeAnalysis` (`mlir/include/mlir/Analysis/DataFlow/IntegerDivisibilityAnalysis.h:29-37`, `StridedMetadataRangeAnalysis.h:24-30`) | `idr-narrow` | New at this pin. Divisibility could prove `big.mod` by a constant on an even counter; no program of ours asks it yet. Conjecture, low. |
| The inliner's cost model and interface (`mlir/include/mlir/Transforms/Inliner.h:120-125`; `Passes.td:316-337`; `mlir/lib/Transforms/Utils/Inliner.cpp:703-715`; `mlir/include/mlir/Transforms/InliningUtils.h:64-89`) | `Inline/Inline.cc`, `Contify.cc`, the `inline-unreachable` pin | Already used: our MLton rule is the `ProfitabilityCallbackTy` (`Inline.cc:147-150`), stricter and cheaper than `inlining-threshold`. The SCC rule that refuses a callee that calls its caller (`Inliner.cpp:709-715`) is why `idr-contify` exists (`Contify.cc:6-16`), and it is policy, not a hook. The `ub.unreachable` terminator hook is the `ub` dialect's to implement (`PINS.md` `inline-unreachable`); a second `DialectInlinerInterface` for a dialect that already has one is not registrable (conjecture: interface registration is one per dialect per interface), so the pin stands until the report lands. |
| `symbol-dce`, `sccp`, `cse`, `remove-dead-values`, canonicalize options (`Passes.td:19-63, 88-101, 127-287, 439-450, 496-539`) | the round | Used. `remove-dead-values` skips a function any non-call op names (`mlir/lib/Transforms/RemoveDeadValues.cpp:278-290`), which is the `remove-dead-values-address-taken` pin's root. `region-simplify=aggressive` merges identical blocks within a region: our regions are one block each, so nothing. `cse-between-iterations` is redundant with the round's `cse`. `trivial-dce` (`Passes.td:103-125`) is what the greedy driver already does. |
| `OperationFingerPrint`, `composite-fixed-point-pass` | `Simplify.cc` | See §6: measured non-convergence with `sccp`; keep ours; file the report. |
| `duplicate-function-elimination` | clones | See §8. |
| Math: `math-uplift-to-fma`, polynomial approximation, `convert-math-to-libm` vs `convert-math-to-llvm` (`mlir/include/mlir/Dialect/Math/Transforms/Passes.td:14-20`; `mlir/lib/Dialect/Math/Transforms/UpliftToFMA.cpp:26-29`; `PolynomialApproximation.cpp:9-10`; `mlir/include/mlir/Conversion/Passes.td:807, 842`) | Doubles, `tests/programs/prelude/symbols` | No, by the Chez diff. FMA uplift requires the `contract` fastmath flag we never set (`Lower/Target.cc:9`, `FPOpFusion::Strict`); the polynomial approximations change digits; libm calls are what Chez makes, and `convert-math-to-llvm`'s intrinsics become the same libm calls at `-O3` unless LLVM folds a constant argument with the host's libm (conjecture; a risk only when cross-compiling to arm64 macOS, where the folded digit may differ from Apple's libm at runtime). |
| `arith-emulate-wide-int`, `arith-emulate-unsupported-floats` (`Arith Passes.td:82-122`) | bigs, doubles | No: bigs are GMP, doubles are `f64`. |
| `generate-runtime-verification`, `RuntimeVerifiableOpInterface` (`Passes.td:300-313`; `mlir/lib/Dialect/MemRef/Transforms/RuntimeOpVerification.cpp:228-256`) | array bounds checks | No: it emits `cf.assert` on `memref.load/store`, whose failure is not `idris_rt_crash` (exit status, message, pending output: `Lower/Runtime.cc:90-112`). The check itself is §2's. |
| The `ptr` dialect (`mlir/include/mlir/Dialect/Ptr/IR/PtrOps.td:64-619`: `load`, `store`, `ptr_add`, `type_offset`, `gather`, `scatter`, masked forms) | `Lower/Runtime.cc`'s `llvm.getelementptr`/`load`/`store` | Conjecture: a target-neutral address layer that would keep cell accesses above the LLVM dialect one stage longer, where `vector` gathers from cells could form. No need today; worth a look when the SoA split of `simd.md` §4 needs gathers. |
| `CallGraph` with `llvm::scc_iterator` (`Inliner.cpp:22, 282-296`) | `Passes/Scc.h` (74 lines, used by five passes) | Partial fit: `CallGraph` resolves `CallOpInterface` only, so `idr.closure` and closure constants, which our cycles include (`LoopBreakers.cc:12-15`), would be lost. `llvm::scc_iterator` over a `GraphTraits` of ours replaces the Tarjan in `Scc.h` with less code (conjecture). |
| `LocalAliasAnalysis` (`mlir/include/mlir/Analysis/AliasAnalysis/LocalAliasAnalysis.h:21-35`) | arrays | No: array accesses are IO-ordered by the world; LLVM's alias analysis runs on the lowered GEPs. |
| Resource hierarchy for effects: `isDisjointFrom`, `isAddressable` (`mlir/include/mlir/Interfaces/SideEffectInterfaces.h:78-95`; `CSE.cpp:214-230`) | our four resources (`Idr.h:51-73`) | New at this pin: CSE lets a write on a resource disjoint from a read's resource not block the merge. Our heap reads are `Pure` (see §C), so nothing is blocked today; declare `IOResource`, `CrashResource`, `DivergenceResource` and `LinResource` non-addressable when a read-declaring op appears. Conjecture, low. |
| Remark policies and formats (`Remarks.h:642-662`; `Remarks.md:194-290`) | `idris-mlir-cc --remarks` | Used with `RemarkEmittingPolicyAll` and one regex for all kinds (`idris-mlir-cc.cc:477-481`); `Final` and per-kind categories come with §1. |
| `-mlir-print-ir-after-all`, `-mlir-print-ir-tree-dir` (`mlir/lib/Pass/PassManagerOptions.cpp:36-62`) | `--dump-after` (`idris-mlir-cc.cc:102-105`, `tests/idr/pipeline/cc-steps.mlir`) | Both available since `applyPassManagerCLOptions` runs on every step's manager (`idris-mlir-cc.cc:555`); the tree printer numbers per manager, and we run one per step, so our numbering stays. Keep ours. |
| PDLL, IRDL (`mlir/docs/PDLL.md`; `mlir/tools/mlir-pdll`) | `Dialect/Canonicalize.td` (nine DRR patterns) | No gain: DRR states them in forty lines; PDLL would state the same; IRDL declares dialects at runtime, which a compiler with one dialect does not need. |
| Bytecode (`PINS.md` `bytecode-deferred-quadratic`, `mlir-recursion`) | `Eval/Reify.cc` | Nothing new at this pin for either; the `tests/upstream/` checks say when. |
| `DestinationStyleOpInterface` (`mlir/include/mlir/Interfaces/DestinationStyleOpInterface.td`) | `idr-returned-arguments` | A tied operand/result is what the pass detects after the fact; declaring the tie on `idr.array.*` would say it up front. Conjecture; the pass is 244 lines and runs after lowering on every function, not only arrays. |
| `GenerateRuntimeVerification`, `view-op-graph`, `print-op-stats` (`Passes.td:300-313, 431-437, 553-580`) | observability | `print-op-stats` could replace the op count in the round trace (`Simplify.cc:112-119`); trivial. |

## C. Effects census

Every op of the dialect: its traits and declared effects (`IdrOps.td`), what
`idr-lower` does (`foreign/idr/lib/Lower/`), and whether an upstream reader
of the declaration (CSE, LICM, canonicalize's dead-op erasure,
`remove-dead-values`, `control-flow-sink`, our `onlyAllocates`) could be
misled. Verdicts: **correct**; **suspicious** (sound today for a reason
outside the declaration); **wrong** (none found). Lines are `IdrOps.td`
unless a file is named. `Alloc(result)` is `MemAlloc` on the op's own
result, which makes an unused op dead and keeps CSE from merging two
(`SideEffectInterfaces.cpp:77-92`; `CSE.cpp:264-274`).

| Op | Traits and declared effects | What the lowering does | Verdict |
| --- | --- | --- | --- |
| `idr.data`, `idr.ctor` (320-353) | `Symbol`; no effects | erased after conversion (`Lower/Pass.cc:194-195`) | correct |
| `idr.constant` (361-375) | `ConstantLike, Pure`, ranges for bigs | static data, or components (`Lower/Patterns.cc:124-132`) | correct |
| `idr.con`, unboxed (378-389; `Ops.cc:448-461`) | no effects, `Speculatable` | tag and slot values (`Patterns.cc:53-70`) | correct |
| `idr.con`, box | `Alloc(result)` on the default resource, or the automatic-allocation-scope resource with `idr.stack` (`Ops.cc:452-455`); `NotSpeculatable` | `idris_rt_cell` or the frame's alloca, then stores (`Patterns.cc:46-51, 14-22`; `Stack/Cell.cc:11-28`) | correct. The stack mark is a discardable attribute, but dropping it only makes the cell a heap cell: nothing silent is lost. |
| `idr.field` (393-404) | `Pure` | a slot value, or a load from the cell (`Patterns.cc:105-110`) | **suspicious**: a load declared effect-free. Sound because a cell's fields never change while a reference to it is live, and the owned-stage verifier forbids reading a view after its owner's consuming use (`Ownership/Verify.cc:1-11`); `idr.reuse` rewrites a cell only through a token of a consumed box. The declaration cannot say this without a resource per cell; the verifier is what holds it. |
| `idr.field` fold (`Ops.cc:505-515`) | | | **suspicious (latent)**: the fold returns the constructor's operand for a field of an `idr.con`, with no exclusion for a `dest.pending` operand; a read of that field after its `idr.dest.write` would fold to poison. Unreachable today only because no folder runs on idr IR after `idr-trmc` (`Registration.cc:30-35`; `Narrow.cc:529-531` folds its own ops only; `TailLoops.cc:509-511` erases dead ops only). Fix: refuse the fold when the operand is a `PendingOp`. |
| `idr.tag` (407-414) | `Pure`, range `[0, n-1]` | a slot, or a load of the header (`Patterns.cc:82-85`) | **suspicious**, as `idr.field`: a header load declared pure, held by the same rule. |
| `idr.dest.pending` (433-442) | `Pure` | poison components (`Patterns.cc:149-159`) | correct |
| `idr.dest.of` (444-453) | `Pure` | an address into the cell (`Patterns.cc:162-172`) | correct |
| `idr.dest.write` (456-463) | `MemWrite` on `$dest`; no speculation interface | a store (`Patterns.cc:174-183`) | correct. It consumes the value's reference; the consumption is not an effect (see `func.call`). |
| `idr.match`, `idr.match_lit` (470-513) | `RecursiveMemoryEffects, RecursivelySpeculatable`, `RegionBranchOpInterface` | tag load and `scf.index_switch`, or comparisons and `scf.if` (`Lower/Matches.cc:51-136`) | correct |
| `idr.yield` (515-520) | `Pure, ReturnLike, Terminator` | `scf.yield` | correct |
| `idr.closure` (526-536) | `Pure`, folds to a constant | JIT only: a new cell (`Lower/Closures.cc:15-31`) | correct, with a condition: CSE may merge two equal closures into one value; a closure is immutable, counting runs later on uses, and in JIT mode cells are arena cells with no count (`Runtime.cc:143-148`). The executable path never lowers one (`Lower/Pass.cc:88-101`). |
| `idr.apply` (539-559) | `CallOpInterface`, no effect interface | JIT only: indirect call (`Closures.cc:35-64`) | correct: unknown effects, never moved or erased; `facts::passed` covers the closures a call is given (`CallEffects.cc:35-36`). |
| `idr.crash` (566-570) | `MayCrash`: `MemWrite` crash and IO; `NotSpeculatable` | `idris_rt_crash`, cold, noreturn (`Runtime.cc:90-113`) | correct |
| `idr.may_loop` (578-582) | `MemWrite` divergence and IO | `llvm.sideeffect`, or the JIT tick (`Runtime.cc:122-131`) | correct |
| `idr.div`, `idr.mod` (588-615) | `MayCrash` unless the divisor is a nonzero constant, then no effects and `Speculatable` | `crashIf(b == 0)`, then division with a safe divisor and the Euclidean fix (`Patterns.cc:250-307`) | correct |
| `idr.to_char` (617-626) | `Pure`, range | arith (`Patterns.cc:309-332`) | correct |
| `idr.to_byte` (630-637) | `MayCrash` unless a byte constant; range `[0,255]` | `crashIf(x > 255)`, trunc (`Patterns.cc:335-349`) | correct |
| `idr.to_int` (641-647) | `CallsRuntime, MayCrash` unless finite constant | `crashIf(!finite)`, `idris_rt_to_int` (`Patterns.cc:421-423, 448-494`) | correct |
| `idr.double_head`, `idr.int_head` (650-671) | `Pure, CallsRuntime`, range | runtime call with `range` on the result (`Patterns.cc:429-446, 482-486`) | correct, assuming the runtime function has no observable effect (it is the folder's meaning too, `Fold/Fold.cc:1-6`). |
| `idr.str.append`, `cons`, `from_char`, `show`, `substr`, `reverse` (678-741) | `CallsRuntime`, `Alloc(result)` | runtime call (`Patterns.cc:448-494`) | correct: dead when unused, never merged; operands borrowed, result owned (`Fold.cc:18-23`). |
| `idr.str.pack`, `idr.str.concat` (707-719) | `CallsRuntime`, `Alloc(result)` | two walks of the list's cells, then `idris_rt_str_alloc` and writes (`Lower/Strings.cc:33-60, 88-157`) | correct; the walk's loads are reads of immutable cells, undeclared as `idr.field`'s are, held by the same rule; the list is borrowed (`Strings.cc:6-7`). |
| `idr.str.tail` (743-757) | `CallsRuntime, MayCrash<1>`: `Alloc(result)`, crash unless known non-empty | `crashIf(empty)`, call | correct |
| `idr.str.length` (759-767) | `Pure, CallsRuntime`, range | call with `range` | correct |
| `idr.str.index`, `idr.str.head` (769-793) | `CallsRuntime, MayCrash` unless constants prove the index | `crashIf`, call | correct |
| `idr.str.cmp`, `to_int`, `to_double` (795-823) | `Pure, CallsRuntime` | call (`Patterns.cc:497-527` for cmp) | correct |
| `idr.big.add`, `idr.big.mul` (843-862) | `CallsRuntime, AllTypesMatch, ResultCarriesOperand`, `Alloc(result)`, ranges; no speculation interface | inline small case, cold call (`Lower/Bigs.cc:61-97`) | correct; conservative: never hoisted (an allocation may fail). |
| `idr.big.sub`, `and`, `or`, `xor`, `neg` (830-838, 861, 863-865, 887-894) | `CallsRuntime`, `Alloc(result)` | inline (sub) or call | correct |
| `idr.big.div`, `idr.big.mod` (867-885) | `CallsRuntime, MayCrash<1>` | `crashIf(b is the small 0)`, call (`Patterns.cc:407-416`) | correct |
| `idr.big.pred` (900-908) | **`Pure`**, `CallsRuntime`, range | `a - 2` when small, else `idris_rt_big_pred`, which allocates (`Bigs.cc:101-116`) | **suspicious**: the one big op whose cold-path allocation is undeclared, unlike its siblings. Sound today: before `idr-rc` a merged or hoisted `big.pred` is one immutable value counted at its uses; between `idr-rc` and `idr-lower` nothing runs CSE or LICM on idr ops. Declaring `Alloc(result)` like `big.add` costs the fold nothing and removes the exception. |
| `idr.big.cmp` (912-921) | `Pure, CallsRuntime`, range | inline compare, cold call (`Bigs.cc:158-177`) | correct |
| `idr.nat.to_big` (926-935) | `Pure`, type-tied | the value itself (`Patterns.cc:137-145`) | correct |
| `idr.nat.from_big` (940-947) | `CallsRuntime`, `Alloc(result)`, range | inline clamp, cold call (`Bigs.cc:120-136`) | correct |
| `idr.big.from_int` (952-963) | `CallsRuntime`, `Alloc(result)`, range | inline tag, cold call for 64-bit (`Bigs.cc:182-217`) | correct |
| `idr.big.small` (970-976) | `Pure`, range | shift and or (`Bigs.cc:220-231`) | correct: the pass that writes it is the proof (965-969). |
| `idr.big.to_int` (979-986) | `Pure, CallsRuntime`, range | inline shift, cold call (`Bigs.cc:235-253`) | correct |
| `idr.big.from_double` (988-1003) | `CallsRuntime, MayCrash<1>` | `crashIf(!finite)`, call | correct |
| `idr.big.to_double` (1005-1012) | `Pure, CallsRuntime` | call | correct |
| `idr.big.show`, `idr.big.from_str` (1014-1030) | `CallsRuntime`, `Alloc(result)` | call | correct |
| `idr.io.put_str`, `put_char`, `put_int`, `put_double`, `get_byte`, `eof` (1040-1080, 1124-1128) | `PerformsIO, CallsRuntime`, `MemRead`+`MemWrite` IO | call | correct |
| `idr.io.get_line` (1086-1090) | as above plus `Alloc(str)` | call | correct |
| `idr.io.write_bytes`, `idr.io.read_bytes` (1098-1119) | as the IO ops; the range "must lie in the buffer, else the program crashes" (1095-1096, 1111) but no `MayCrashOpInterface` | call | **suspicious (minor)**: `idr-effects` reports such a function `io` without `crash` (`Facts/Infer/Infer.cc:43-44`). Harmless: an `io` function is never evaluated, dropped or moved (`Facts/Evaluation/CanEvaluate.cc:15`; `Dialect.cc:839-845`), and the crash is ordered by the IO write it already declares. Implementing the interface would make the fact true. |
| `idr.world.new` (1137-1142) | `PerformsIO`, `MemWrite` IO | nothing (`Patterns.cc:198-205`) | correct (`findings/decision-inhouse-linear.md`, the forged world) |
| `idr.array.new` (1169-1180; `Ops.cc:1238-1247, 1268, 1272-1275`) | `PerformsIO`; effects: IO read and write, `Alloc(array)`; crash cause none | `idris_rt_array_new`, a fill loop with `inc` per element and one `dec` (`Arrays.cc:59-97`) | correct: IO keeps it when unused (the fill's reference moved in). |
| `idr.array.get` (1184-1195; `Ops.cc:1269, 1276-1279`) | IO read and write, `MemWrite` crash (always) | `crashIf(index >= length)`, load, `inc` (`Arrays.cc:101-119`) | correct; the cell's own read is undeclared and ordered by the IO resource. §2 would make the crash conditional. |
| `idr.array.set` (1199-1210; `Ops.cc:1270, 1280-1283`) | IO read and write, `MemWrite` crash | `crashIf`, load old, `dec`, store (`Arrays.cc:122-142`) | correct, as above. |
| `idr.dup` (1258-1273) | `MemRead`+`MemWrite` on `$value` | `idris_rt_inc` per counted component, static data skipped (`Lower/Counting.cc:16-28`) | correct: never dead, never merged, ordered with every drop. |
| `idr.drop` (1275-1284) | `MemRead`+`MemWrite`+`MemFree` on `$value` | `idris_rt_dec`, or `idris_rt_free_cell` for a token (`Counting.cc:31-46`) | correct |
| `idr.borrow` (1290-1297) | `Pure` | the value (`Counting.cc:155-162`) | correct; the view's lifetime is the verifier's. |
| `idr.share` (1303-1310) | `Pure` | the value (`Counting.cc:145-152`) | correct |
| `idr.reuse` (1320-1328) | `MemWrite` on `$token`, `Alloc(result)` | exclusive token: header and stores; else `scf.if null ? allocate : header`, then stores (`Counting.cc:50-82`) | correct: the write keeps an unused reuse (it consumes the token). |
| `idr.take`, box (1332-1352) | `MemRead`+`MemWrite`+`MemFree` on `$value` | loads; exclusive: the cell is the token; else `scf.if count==1 ? cell : (inc fields, dec cell, null)` (`Counting.cc:88-142`) | correct |
| `idr.take`, unboxed sum or atom | same declaration | slot values, or nothing (`Counting.cc:97-111`) | correct, over-declared: no memory is touched; conservative. |
| `idr.lin.enter`, `idr.lin.use` (1438-1459) | `MemAlloc` on the lin resource on the result; ranges pass through | the value (`Patterns.cc:137-145`) | correct, by design (1425-1432): a fresh value no pass merges, erased when unused. |
| `func.call` (`CallEffects.cc:29-53`) | IO read and write when `io`; crash write; divergence write; IO write for either; `Alloc` on the lin resource for every non-scalar result | the call | **suspicious (ordering)**: after `idr-rc`, a call may consume an owned argument; the consumption is not an effect, so an unused call of a pure callee is "trivially dead" and its erasure would leak the argument's reference. No DCE runs between `idr-rc` and `idr-lower` (`Registration.cc:28-36`), and the owned-stage verifier would report the unconsumed reference as an error, not a wrong answer. The same holds for `idr.con` of a box, `idr.reuse`, `idr.dest.write` and terminators that consume. An honest declaration is a `MemFree`-like effect on each consumed operand once the stage is owned (conjecture: `getEffects` reading the operand grade). |

Three things to take from the census:

- No declaration lets CSE, LICM, canonicalize or `remove-dead-values` change
  what a program computes today; `tests/idr/effects/{alloc,call-effects}.mlir`
  and `tests/idr/canon/{facts,unused-call}.mlir` state the properties the
  declarations are held to.
- Four spots are sound by something other than what they declare: the
  owned-stage verifier (`idr.field`, `idr.tag`, the string walkers), the
  pipeline's order (`big.pred`'s allocation, `FieldOp::fold` on a pending
  field, consumption by calls and constructors). Each has a one-line fix
  that makes the declaration carry the fact; the fold's is the one to make
  first, since a folder added after `idr-trmc` would meet it.
- The vectorization lane (§5) speculates op bodies under masks; it should
  start from this table, not from the traits alone.
