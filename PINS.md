<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately other than the profile the C++ follows (upstream MLIR's
layout and conventions for foreign/idr, an in-tree dialect of headers and
.cpp; the language profile of CMakeLists.txt for the build and the
runtime) because the pinned toolchain, platform or dependency requires
it, a deliberate deviation from that profile, or a pinned source the
build takes beside the toolchain. An entry's `sites` say where the tree
meets it; the essay lives here, once.

A bug in a pinned upstream is fixed by a patch to its source, carried in
`upstream/<bug>/` and applied by `tools/bootstrap.sh` (upstream/README.md);
its entry's workaround is that patch, and the entry goes when the pin moves
past upstream's fix. Where code of ours still stands in for a patch, because
the toolchain has not been rebuilt with it or because the bug has no patch
yet, the entry says what that code is and when it goes.

Tombstone ritual: on every toolchain bump, read this file top to bottom,
re-test every retire condition, and delete what upstream fixed, with the
patches the new pin has upstream's fix for — one file, one sweep.

The LLVM pin is a commit of llvm main, not a release: the patch we carry
for a bug we send upstream is then its pull request, one diff, not two.
Every dependency is fast-forwarded to its latest about weekly (the LLVM
umbrella projects, modular and Idris 2 at main, the rest at their latest
release), and when a patch of ours lands upstream. Each bump is one
commit: the lock, the gitlinks, the carried patches rebased or dropped,
the toolchain rebuilt from it by the one recipe (`tools/bootstrap.sh`) on
every target, the full suites green on each, and this file's sweep.

## dead-code-nested-symbol-use

- sites: every analysis on MLIR's solver that loads DeadCodeAnalysis
  (narrowing's copy analysis and Ranges, per function);
  remove-dead-values, if the qualification's trial brings it
  back (C35)
- workaround: `upstream/29-dead-code-nested-symbol-use/llvm.patch`: the use
  is resolved in the table being walked; checked by
  tests/upstream-dead-code-nested-symbol-use
- retire: drop the patch when the pin has the fix

## aarch64-sibcall-callee-pop

- sites: foreign/idr/lib/Conversion/Lower/Functions.cpp (every function
  of the program takes `tailcc`) and TailCalls.cpp (its tail calls
  `musttail`); every arm64 target
- workaround: `upstream/30-aarch64-sibcall-callee-pop/llvm.patch`: a
  function with stack arguments to pop makes no sibling call, under
  SelectionDAG and GlobalISel; checked by
  tests/upstream-aarch64-sibcall-callee-pop
- retire: drop the patch when the pin has the fix

## greedy-multi-region-ancestors

- sites: the greedy driver inside the upstream passes the pipeline runs
  over a module that still holds multi-region ops (`convert-linalg-to-loops`,
  `convert-vector-to-scf`, `expand-strided-metadata`,
  `convert-vector-to-llvm`'s pre-lowering, D99), whose every visit of such
  an op asks whether it is dead across all its regions; our own greedy
  rewrites are gone (D98)
- workaround: `upstream/62-greedy-multi-region-ancestors/llvm.patch`: an
  ancestor with several regions is revisited once the worklist is empty;
  checked by tests/upstream-greedy-multi-region-ancestors
- retire: drop the patch when the pin has the change

## sqrt-negative-fold

- sites: `createOrFold` in the conversions; the e-graph computes a root
  itself, by the host's `sqrt` as the fold does, and leaves the NaN of a
  negative one applied
- workaround: `upstream/61-sqrt-negative-fold/llvm.patch`: a quiet NaN for
  a negative non-zero operand, -0 for -0; checked by
  tests/upstream-sqrt-negative-fold
- retire: drop the patch when the pin folds it

## cse-nested-linalg-index

- sites: a tabulate in a tabulate's body, a linalg.generic in another's
  body; the e-graph pass, which takes cse's place and must key an op with
  `DependsOnParent` by its parent as cse's key does (D98; L14's seam).
  Upstream's cse itself runs nowhere now (D98, D100)
- workaround: `upstream/56-cse-nested-linalg-index/llvm.patch`: the trait
  `DependsOnParent` on `linalg.index`, and cse's key for such an op holds
  its parent; checked by tests/upstream-cse-nested-linalg-index
- retire: drop the patch when the pin has the fix

## linalg-index-int-range

- sites: foreign/idr/lib/Transforms/Narrow (the range analysis after
  idr-structure-loops); foreign/idr/lib/Driver/Register.cpp, which
  registers the model
- workaround: `upstream/57-linalg-index-int-range/llvm.patch`: an external
  model of `InferIntRangeInterface` for `linalg.index`, [0, extent - 1],
  promised by the Linalg dialect; checked by
  tests/upstream-linalg-index-int-range
- retire: drop the patch, and the registration in Register.cpp, when the
  pin has the fix (in ODS, the registration goes with it)

## inline-unreachable

- symptom: the upstream inliner aborts on a single-block callee whose
  body ends in `ub.unreachable`: its fast path erases the terminator and
  continues the block with the operations after the call, the hook that
  declines it (`allowSingleBlockOptimization`) is asked of the caller's
  dialect, and the `ub` dialect declines nothing and implements no
  `handleTerminator`. The inliner's region patterns likewise skip a region
  that ends in `ub.unreachable`
- sites: none in our code; the patch. A body that never returns (a crash,
  a body Idris proved impossible, a match none of whose regions returns)
  ends in `ub.unreachable`, as Emit writes it and the e-graph's match
  rules leave it (foreign/idr/lib/Transforms/Joins/MatchRules.cpp).
  idr-optimize's leaf inlining calls upstream's `mlir::inlineCall`
  (foreign/idr/lib/Transforms/Inline/Inline.cpp) and idr-inline runs
  upstream's `Inliner` (Inline/InlinePass.cpp), both through the fast
  path the patch fixes. The match ops declare `SingleBlock`, which the
  inliner reads: such a callee is inlined into a function body, and a call
  of it in a match region stays a call, since the block after it would be
  a second block of the region
- workaround: `upstream/07-inline-unreachable-terminator/llvm.patch`, the
  pull request: the hook is asked of the terminator's dialect, the `ub`
  dialect declines the fast path for `ub.unreachable` and keeps it as the
  end of its block, and the inliner pass leaves a call of such a callee in
  a region that must stay one block
- retire: drop the patch when the pin has the merged fix (not on main at
  416f328b)

## ub-unreachable-effects

- sites: none in our code; the patch. Every body that never returns ends
  in `ub.unreachable`, and the derived effect row and every effect query
  over it read the op's own declaration: the external model that gave it
  no effects in our code (`NeverRuns`) is deleted, so the patch alone
  carries the fact
- workaround: `upstream/87-ub-unreachable-effects/llvm.patch`:
  `NoMemoryEffect` on the op, unspeculatable still; checked by
  tests/upstream-ub-unreachable-effects, which runs the report's
  `unreachable-effects.mlir` under `-canonicalize` and finds the region
  op gone
- retire: when the pin's `ub.unreachable` declares no memory effects

## mlir-recursion

- symptom: MLIR recurses on the depth of its input in many places, each
  needing a native stack that grows with the IR it reads: a constant
  nested a few thousand deep overflowed an 8 MiB stack with a bare SIGSEGV
  (6,000 levels of builtin array in `mlir-opt`)
- sites: foreign/idr/include/idr/Driver/Tool.h (`runTool`: the tools run
  on the runtime's runner, runtime/Start/Runner.cpp, on a small stack the
  target entry measures, `IDRIS_MLIR_TOOL_STACK_BYTES`, behind a one-page
  guard that stack-clash probes make enough; darwin-stack-clash)
- workaround: one carried patch per family of MLIR's recursion on input
  size (C99), each with its PINS entry and tests/upstream-<bug> check: the
  textual parse, print and alias collection of nested builtin arrays and
  dictionaries (10), the walks (80), the attribute walker and replacer
  (81), clone (82), destruction (83), region DCE (84), slices (85),
  the symbol-table walk (88), the sparse and dense analyses'
  initialization (89), the comparison of operations and regions (90),
  bufferization's buffer types along chains of values (91), dead-code
  initialization (92) and call graph construction (93)
- left, for the stage-1 stack painting to measure (D33, S1), each
  recursing through code no explicit stack inside MLIR's own reaches: the
  op parser and printer, which reach a nested region through the op's own
  parse and print hooks (the alias collection's dummy printer with them);
  a dialect attribute's parameters, through its parser and printer; and
  the rewriter's `eraseOp`, which recurses through a `std::function` when
  a listener is attached (`PatternMatch.cpp`), with
  `Operation::dropAllDefinedValueUses`
- retire: when the pin has every family's fix, or the painting shows the
  ones left within the measured stack
- upstream: one RFC on Discourse for the family set, then one pull
  request per family (upstream/10-recursive-attribute-parser's plan)

## bytecode-deferred-quadratic

- sites: none in our code; the patch. The frontend hands idris-mlir its
  module as bytecode, which the driver reads as it reads text
- workaround: `upstream/03-bytecode-deferred-quadratic/llvm.patch`: the
  reader keeps the entries waiting on a deferred parse as a path, each
  waiting on the one above it, so a chain of n deferrals takes O(n) parses
  and a cycle fails with `cyclic reference to attribute index: N`
- retire: drop the patch when the pin's reader resolves deferred entries
  in linear time and rejects cycles (the patch's two tests pass unpatched)

## vectorize-precondition-body

- sites: none in our code; the patch. The vectorization schedule's
  `transform.idr.vectorize_lanes` decides with the precondition alone
  (foreign/idr/lib/Target/Schedules.cpp), before it changes anything; a
  generic it refuses stays whole, and convert-linalg-to-loops runs its
  body in the program's order. A tile the precondition accepts and
  `linalg::vectorize` then refuses would be an internal error there
- workaround: `upstream/04-vectorize-precondition-body/llvm.patch`, the
  pull request: the precondition and `vectorizeOneOp` share one rule for a
  body op no hook takes (a constant or an ElementwiseMappable op), and the
  precondition checks it for every body op of every linalg op, so
  `vectorize` fails before it creates any IR
- retire: drop the patch when the pin's precondition refuses such a body
  (the pull request landing on main)

## int-range-narrowing-exactness

- symptom: upstream's narrowing
  (`arith::populateIntRangeNarrowingPatterns`) makes an elementwise op an
  op on the narrow type whenever the ranges of its operands and results fit
  it. At llvmorg-23.1.2 three narrowed ops then computed something else: a
  shift whose amount can reach the narrow width (poison there), a `remsi`
  that can see INT_MIN % -1 of the narrow type (undefined behaviour once
  `llvm.srem`, where the wide op gives 0), and a `remui` of a word that may
  be negative, which the narrow op reads as another number. Main's
  44a4dbf32 (#218495) fixed the shift, and 28db2071a69c (#233323) the
  unsigned ops. Main at 416f328b still lets a `remsi` narrow whose dividend
  can be the narrow minimum while its divisor can be -1
- sites: none in our code; the patch. idr-narrow-lanes versions a
  vectorized loop when its wide integer ops fit 32 bits, and the narrowing
  of its copy leaves wide an op whose 32-bit form would compute something
  else (tests/linarray-lanes-exact)
- workaround: `upstream/09-int-range-narrowing-exactness/llvm.patch`, the
  `remsi` half alone: it does not narrow when the dividend's range holds
  the narrow signed minimum and the divisor's holds -1
- retire: drop the patch when the pin's narrowing handles `remsi`

## int-range-ne-either-view

- sites: none in our code; the patch. Every reader of `evaluatePred`:
  the numeric domain's interval instance (`Intervals::equal`,
  foreign/idr/lib/IR/Ops/Numeric.cpp), the bigs' comparisons
  (foreign/idr/lib/IR/OpsBigs.cpp), and upstream's `arith.cmpi` range
  under `IntegerRangeAnalysis`
- workaround: `upstream/102-int-range-ne-either-view/llvm.patch`:
  `sne || une`; checked by tests/upstream-int-range-ne-either-view, on
  the report's `ne-either-view.mlir`
- retire: drop the patch when the pin's `isStaticallyTrue` accepts either
  view

## fp-call-folding

- symptom: on llvm main at 416f328b, LLVM's constant folder computes a
  call of `llvm.exp`, `llvm.log`, `llvm.sin`, `llvm.cos`, `llvm.atan` or
  `llvm.pow` on constants with the compiling machine's libm
  (`ConstantFoldScalarCall1`, `ConstantFoldFP`, ConstantFolding.cpp), so
  a folded value could differ in its last digit from what the target
  computes (C198, C210). `llvm.tan`, `llvm.asin` and `llvm.acos` are not
  folded at the pin (*read*)
- sites: the driver's LLVM options (foreign/idr/lib/Driver/Main.cpp), the
  LLVM pipeline it runs (foreign/idr/lib/Target/Optimize.cpp); the
  lowering emits the nine math ops as upstream's MathToLLVM does, as
  those intrinsics, with neither `nobuiltin` nor `strictfp`
- workaround: upstream's own switch, no patch:
  `-disable-fp-call-folding` (ConstantFolding.cpp:68-71), which
  `canConstantFoldCallTo` and `ConstantFoldIntrinsic` read, set by the
  driver after the command line so that no argument unsets it. It is not
  narrowed: no call whose type holds a float folds in LLVM, `llvm.sqrt`,
  `llvm.floor` and `llvm.ceil`, which C198 keeps folding, among them;
  MLIR folds those before the lowering, and LLVM's lost folds are only
  optimizations (unmeasured). GlobalOpt's evaluator of static
  constructors folds calls without asking the switch (Evaluator.cpp:499);
  nothing of ours has one (the runtime's are refused,
  foreign/idr/lib/Driver/ReadRuntime.cpp), so nothing reaches it
- retire: never while LLVM folds with the compiling machine's libm
- upstream: none; the switch is upstream's

## forward-dataflow-callee-lookup

- sites: none in our code; the patch
- workaround: `upstream/05-forward-dataflow-callee-lookup/llvm.patch`: the
  solver builds one `SymbolTableCollection` per `initializeAndRun`, the
  span over which the IR does not change, and hands it to its analyses;
  the forward analyses resolve callees through it, and `DeadCodeAnalysis`
  uses it in place of the collection it kept across runs
- retire: drop the patch when the pin's forward analyses resolve callees
  from a symbol table (`tests/upstream-forward-dataflow-callee-lookup`
  then shows it with the pristine tools)

## pass-timing-dynamic-pipeline

- sites: none in our code; the patch. idris-mlir runs one pass manager
  (foreign/idr/lib/Driver/Run.cpp), whose timing is the report
- workaround: `upstream/19-pass-timing-dynamic-pipeline/llvm.patch`:
  #169615's change as the rewritten file spells it, under which every
  pass records its scope for the pipelines it runs, and a test of ours
  that fails without it
- retire: drop the patch when the pin has #169615 (or another fix the
  patch's test passes with)

## one-shot-module-function-interface

- sites: none in our code; the patch. idr-bufferize (foreign/idr/lib/Transforms/Bufferize)
  runs the module driver on idr.program, attaches upstream's
  `func_ext::FuncOpBufferizableModel`, `CallOpBufferizableModel` and
  `ReturnOpBufferizableModel` to idr.func, idr.call and idr.return, and runs
  empty tensor elimination on a module analysis of its own
- workaround: `upstream/24-one-shot-module-function-interface/llvm.patch`, four
  pull requests in one diff: a reland of upstream's reverted #110322 (the
  driver, its state, the models and the type converter on
  `FunctionOpInterface`, `CallOpInterface` and `ReturnLike`; the functions
  limited to function ops with a `BufferizableOpInterface` implementation,
  so a `transform.named_sequence`, the revert's cause, stays an other op;
  the models public templates and their queries exported; a function that
  never returns analyzed with no aliasing result); the strongly connected
  components of the call graph, with each cycle's boundaries iterated to a
  fixpoint (`analyzeCallCycle`, one `FuncBoundaryFacts` per function); the
  return values that
  may not be writable recorded per function and read by the call model's
  `isWritable`, with a value that definitely aliases one of its op's
  operands writable on its own (`OneShotAnalysisState::isWritable` asked
  the op even then, so a call result equivalent to an argument was copied
  before a write); and the nearest symbol table for empty tensor elimination's
  module analysis and for a constant's global
- retire: drop each part when the pin carries upstream's fix for it; the
  patch goes when all have (`tests/upstream-one-shot-module-function-interface`
  then passes with the pristine tools); the models stay upstream's templates

## early-exits

- sites: the join points of the control-flow lane (`idr.join` and
  `idr.loop` define a builtin `token` per target; `idr.jump` exits to it
  across `idr.data.match` and `idr.lit.match`, which carry
  `PropagateControlFlowBreak`); every upstream analysis that reads the
  edge (dead code, SCCP, the sparse and dense analyses, post-dominance,
  the inliner's refusal of an escaping region); the lowering through
  `scf.if` and `scf.index_switch`
- workaround: `upstream/65-early-exits/llvm.patch`, llvm/llvm-project
  #166688 (head 968e49b1) rebased by hand onto the pin, five hunks placed
  where the pin's text moved; its own gaps are 66 to 71 below; checked by
  tests/upstream-early-exits
- retire: when the pin passes the merge of #166688; if upstream merges
  another form, ours moves to it only when it keeps every fact this one
  keeps (D82), and a rejection of the pull request is a new ruling

## early-exit-propagation-helpers

- sites: the generated `getSuccessorRegions` of `idr.data.match`,
  `idr.lit.match`, `idr.join` and `idr.loop`; `scf.index_switch` (71)
- workaround: `upstream/66-early-exit-propagation-helpers/llvm.patch`: the
  two exported from ControlFlowInterfaces, unchanged; checked by
  tests/upstream-early-exit-propagation-helpers
- retire: with early-exits, or when #166688 exports them

## early-exit-dead-match

- sites: `idr.data.match` under `idr.join` whose cases all `idr.jump`; every
  erasure of dead ops (the e-graph pass's cleanup, dead-code elimination)
- workaround: `upstream/67-early-exit-dead-match/llvm.patch`:
  `wouldOpBeTriviallyDead` keeps a root an exit leaves; checked by
  tests/upstream-early-exit-dead-match
- retire: with early-exits, or when #166688 covers it

## early-exit-region-inliner

- sites: a known `idr.data.match` case ending in `idr.jump`; `scf.if` with a
  constant condition around an exit
- workaround: `upstream/68-early-exit-region-inliner/llvm.patch`: the path
  stops at a successor the op does not own; checked by
  tests/upstream-early-exit-region-inliner
- retire: with early-exits, or when #166688 covers it

## early-exit-successor-inputs

- sites: a dead or duplicate join-point parameter seen from a match that
  holds only some of the jumps to it
- workaround: `upstream/69-early-exit-successor-inputs/llvm.patch`: both
  skip an input the op does not own; checked by
  tests/upstream-early-exit-successor-inputs
- retire: with early-exits, or when #166688 covers them

## early-exit-region-graph

- sites: the linearity verifier's `isRepetitiveRegion` on matches;
  bufferization's repetitive-region queries for arrays in loops;
  `insideMutuallyExclusiveRegions` of an op in a join op's body and one in
  the join region a jump nested in the body enters (the in-place rule's
  `ownership::entryOf`, bufferization's `mayRunAfter`)
- workaround: `upstream/70-early-exit-region-graph/llvm.patch`: only the
  op's regions are nodes, and nested exits landing on it are edges;
  checked by tests/upstream-early-exit-region-graph
- retire: with early-exits, or when #166688 covers it

## early-exit-index-switch

- sites: the lowering of `idr.data.match` to `scf.index_switch`, nested jumps
  lowered by upstream's `convert-scf-to-cf`; a crash case ending in
  `ub.unreachable` or a crash terminator of ours
- workaround: `upstream/71-early-exit-index-switch/llvm.patch`: the
  switch propagates exits as `scf.if` does, and both accept any
  terminator that never returns (`scf::op_impl::isNoReturnTerminator`);
  checked by tests/upstream-early-exit-index-switch
- retire: with early-exits, or when #166688 covers it

## scc-iterator-node-numbers

- sites: the solver layer's components (the program graph over
  `mlir::CallGraph`, 73); the inliner's component walk
- workaround: `upstream/72-scc-iterator-node-numbers/llvm.patch`: visit
  numbers by node number when the graph numbers its nodes; checked by
  tests/upstream-scc-iterator-node-numbers
- retire: when the pin's `scc_iterator` reads node numbers

## call-graph-dense-ids

- sites: the solver layer's program graph (L14), which reads
  `CallGraphNode::getIndex()` and `CallGraph::getSCCs()` and keeps what
  upstream cannot hold (tail kinds, sites, the editor); upstream's inliner
- workaround: `upstream/73-call-graph-dense-ids/llvm.patch`: dense ids
  minted by the graph, stable for its life, and its bottom-up components
  as ranges of one kept permutation; checked by
  tests/upstream-call-graph-dense-ids
- retire: when the pin's `CallGraph` holds dense ids and kept components
  in a form that keeps every fact this one gives

## pass-adaptor-preserved-analyses

- sites: the nested `idr.func` groups of the pipeline, after which the
  program graph and the solver layer's cached analyses survive
- workaround: `upstream/74-pass-adaptor-preserved-analyses/llvm.patch`:
  the adaptor preserves the intersection of what its nested passes
  preserved, as LLVM's pass manager does; checked by
  tests/upstream-pass-adaptor-preserved-analyses
- retire: when the pin's adaptor preserves the intersection

## thread-pool-stack-size

- sites: every pool a tool hands MLIR, each worker on the stack the
  runtime's runner gave the tool's own thread, D33's measured bound with a
  margin, sized in one platform place (C43), through one strategy
  (`idr::driver::onToolStack`, foreign/idr/include/idr/Driver/Tool.h):
  the compiler's driver's pool (foreign/idr/lib/Driver/Compile.cpp),
  idris-mlir-reduce's, which it hands the context it makes
  (foreign/idr/tools/idris-mlir-reduce.cpp), and idris-mlir-opt's, which
  it hands `MlirOptMain` (mlir-opt-main-thread-pool)
- workaround: `upstream/75-thread-pool-stack-size/llvm.patch`:
  `ThreadPoolStrategy::StackSizeInBytes`; checked by
  tests/upstream-thread-pool-stack-size
- retire: when the pin's pool takes a stack size

## mlir-opt-main-thread-pool

- sites: foreign/idr/tools/idris-mlir-opt.cpp, which builds its pool
  through `idr::driver::onToolStack` and sets it on the config it hands
  `MlirOptMain`
- workaround: `upstream/100-mlir-opt-main-thread-pool/llvm.patch`:
  `MlirOptMainConfig::setThreadPool(llvm::ThreadPoolInterface *)`, the
  pool every context `MlirOptMain` makes for its input shares when
  threading is enabled; `--mlir-disable-threading` still disables it.
  Its check, tests/upstream-mlir-opt-main-thread-pool, runs the report's
  `callers-pool.cpp`
- retire: when the pin's `MlirOptMain` takes a caller's pool

## thread-pool-thread-start

- sites: `idr::driver::onToolStack` (foreign/idr/include/idr/Driver/Tool.h),
  every tool pool's strategy, which names the runtime's function that
  installs the tools' signal stack on the calling thread
- workaround: `upstream/101-thread-pool-thread-start/llvm.patch`, applied
  after 75's: `ThreadPoolStrategy::OnThreadStart`, a `void (*)()` each
  thread a pool starts calls on itself before any task. Its check,
  tests/upstream-thread-pool-thread-start, runs the report's
  `signal-stack.cpp`, whose worker overflows into its guard and whose
  handler prints `ok` on the worker's signal stack
- retire: when the pin's pool runs a client's function on each thread it
  starts

## dataflow-state-storage

- sites: the per-function solves on upstream's framework: narrowing's
  copy analysis and Ranges, measured on it before any leaves it (C32,
  S3)
- workaround: `upstream/77-dataflow-state-storage/llvm.patch`: small maps
  and sets inline, the solver's uniquer single-threaded; about fifteenfold
  less per state; checked by tests/upstream-dataflow-state-storage
- retire: when the pin's solver keeps small states inline

## operation-equivalence-symbol-hook

- sites: the deduplication of functions by partition refinement over
  upstream's `OperationEquivalence` (L18), which retires the port of
  Modular's `EliminateDuplicateFunctions` (C10)
- workaround: `upstream/79-operation-equivalence-symbol-hook/llvm.patch`:
  an optional `MapSymbolRefFn` through which symbol references are
  compared and hashed, in attributes, properties and those types; checked
  by tests/upstream-operation-equivalence-symbol-hook, which should cover
  a type naming a symbol as well as an attribute
- retire: when the pin's `OperationEquivalence` takes such a hook

## walk-iterative

- sites: every pass, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/80-walk-iterative/llvm.patch`: the eight walks on
  one explicit-stack engine, with the same order and the same erasure,
  skip and interrupt behaviour for every iterator kind; checked by
  tests/upstream-walk-iterative
- retire: when the pin walks without recursion on nesting depth

## attr-type-walker-iterative

- sites: the substitution of family index terms
  (foreign/idr/lib/IR/Families/Substitute.cpp), the type graph
  (foreign/idr/lib/Analysis/Solver/TypeGraph.cpp),
  operation-equivalence-symbol-hook's
  mapping, and upstream's symbol-use walks and renames, under the tools'
  one small stack (D33, C43, C99)
- workaround: `upstream/81-attr-type-walker-iterative/llvm.patch`: an
  explicit stack with the same order, caches and cycle handling; checked
  by tests/upstream-attr-type-walker-iterative
- retire: when the pin walks and replaces without recursion on depth

## clone-iterative

- sites: upstream's inliner and every clone of an operation with regions
  (the e-graph's elaboration, idr-narrow's copies, bufferization), under
  the tools' one small stack (D33, C43, C99)
- workaround: `upstream/82-clone-iterative/llvm.patch`: the same two
  steps, the second from an explicit stack, in the same order; checked by
  tests/upstream-clone-iterative
- retire: when the pin clones without recursion on nesting depth

## destruction-iterative

- sites: every erase and every module freed, under the tools' one small
  stack (D33, C43, C99)
- workaround: `upstream/83-destruction-iterative/llvm.patch`, applying
  after 82: teardown from an explicit stack, every reference dropped
  before anything is freed, references dropped through parent links;
  checked by tests/upstream-destruction-iterative
- retire: when the pin destroys without recursion on nesting depth

## region-dce-iterative

- sites: every greedy rewrite the upstream passes run on lowered functions
  end each round in `simplifyRegions` (expand-strided-metadata,
  convert-vector-to-scf, convert-linalg-to-loops, the schedule's
  `transform.apply_patterns`), under the tools' one small stack (D33,
  C43, C99)
- workaround: `upstream/84-region-dce-iterative/llvm.patch`: explicit
  stacks with the same order and the same erasures; checked by
  tests/upstream-region-dce-iterative
- retire: when the pin's region DCE runs without recursion on depth

## slice-iterative

- sites: the vectorizer's reduction matching
  (foreign/idr/lib/Target/Schedules.cpp, through
  `vectorizeLinalgOpPrecondition`) and bufferization's empty-tensor
  elimination (`moveValueDefinitions`), under the tools' one small stack
  (D33, C43, C99)
- workaround: `upstream/85-slice-iterative/llvm.patch`: explicit stacks
  with the same slices in the same order; checked by
  tests/upstream-slice-iterative
- retire: when the pin slices without recursion on chain length

## symbol-table-walk-iterative

- sites: dead-code analysis's initialization (the ranges analysis,
  foreign/idr/lib/Analysis/Ranges.cpp; idr-narrow's copies,
  foreign/idr/lib/Transforms/Narrow/Copy.cpp) and upstream's
  inliner in idr-inline (its use lists,
  foreign/idr/lib/Transforms/Inline/InlinePass.cpp), under the tools' one
  small stack (D33, C43, C99)
- workaround: `upstream/88-symbol-table-walk-iterative/llvm.patch`,
  applying after 80: a stage-aware walk with a stack of each open
  operation's visibility, the same tables passed in the same post-order
  with the same visibility; checked by
  tests/upstream-symbol-table-walk-iterative
- retire: when the pin walks symbol tables without recursion on depth

## dataflow-iterative-initialization

- sites: the sparse forward initialization of the integer range solves
  (the ranges analysis, idr-narrow's copies), under the tools' one small
  stack (D33, C43, C99);
  nothing of ours runs a sparse backward or dense analysis, whose
  initializations are the same traversal
- workaround: `upstream/89-dataflow-iterative-initialization/llvm.patch`:
  one traversal from an explicit worklist in the recursions' order
  (`DataFlowAnalysis::initializeNested`), so every state is created and
  visited as before; a dense analysis's `initialize` override is now
  called on the top operation alone, and none overrides it; checked by
  tests/upstream-dataflow-iterative-initialization
- retire: when the pin initializes the sparse and dense analyses without
  recursion on depth

## sparse-region-successors-protected

- sites: foreign/idr/lib/Analysis/Ranges.cpp (`SummarizedRanges`, whose
  override refines a literal match's default region and hands every
  other successor to the base, C211)
- workaround: `upstream/103-sparse-region-successors-protected/llvm.patch`:
  the declaration moves into `protected:` beside `visitCallOperation`
  and `visitCallableOperation`; applies alone and after 89's. Checked by
  tests/upstream-sparse-region-successors-protected, on the report's
  `override.cpp`
- retire: when the pin declares it protected

## operation-equivalence-iterative

- sites: the e-graph's identical-regions rule
  (foreign/idr/lib/Transforms/Joins/IdenticalRegions.cpp) and the
  deduplication of functions by partition refinement
  (foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp), on
  program-sized bodies, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/90-operation-equivalence-iterative/llvm.patch`,
  applying after 79, whose symbol hook it keeps: one comparison from an
  explicit stack of the pairs of regions being compared, in the
  recursion's order, so the callbacks are called in the same order and
  the same first difference stops it; one symbol mapper per comparison;
  checked by tests/upstream-operation-equivalence-iterative
- retire: when the pin compares operations and regions without recursion
  on nesting depth

## buffer-type-iterative

- sites: the bufferization of arrays, One-Shot Bufferize over the
  compiler's models (foreign/idr/lib/Transforms/Bufferize/), on
  program-sized chains, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/91-buffer-type-iterative/llvm.patch`: the
  computation from an explicit stack of the values in progress, held in
  `BufferizationState`; an implementation's question with no answer yet
  fails, the value is computed by a frame of its own, and the
  implementation runs again, so every one is asked the same values in the
  same order with the same invocation stack and answers. It holds for an
  implementation that asks the same values when run again and acts on a
  failed question only by failing, as upstream's and the compiler's
  models do (the interface's documentation states it); checked by
  tests/upstream-buffer-type-iterative
- retire: when the pin computes buffer types without recursion on the
  length of a chain

## dead-code-iterative-initialization

- sites: every solve on upstream's framework, under the tools' one small
  stack (D33, C43)
- workaround: `upstream/92-dead-code-iterative-initialization/llvm.patch`:
  the same pre-order from a worklist; checked by
  tests/upstream-dead-code-iterative-initialization
- retire: when the pin initializes it without recursion on depth

## call-graph-iterative-construction

- sites: every build of `mlir::CallGraph` (the program graph, the
  inliner), under the tools' one small stack (D33, C43)
- workaround: `upstream/93-call-graph-iterative-construction/llvm.patch`:
  the same pre-order from a worklist; checked by
  tests/upstream-call-graph-iterative-construction
- retire: when the pin builds it without recursion on depth

## function-interface-edits

- sites: `idr.func`'s positional facts (where each scoped value lives and
  the bounds between lifetimes, what it gives back, its untouched and
  bounded parameters), kept by its own edits
  (foreign/idr/lib/IR/Func/Edits.cpp) under every caller, upstream's
  passes among them (C187)
- workaround: `upstream/99-function-interface-edits/llvm.patch`: the four
  edits are interface methods with the present bodies as their defaults,
  and the single-item forms reach them through the operation; checked by
  tests/upstream-function-interface-edits
- retire: when the pin's `FunctionOpInterface` dispatches the four edits
  to an operation's own

## one-shot-tensor-like-copy

- sites: the bufferization of graded arrays, `!idr.graded<uses, hold, T>`
  tensor-like where `T` is (D43, L12), whose copy idr-bufferize's hook
  makes through a cast of the array
- workaround: `upstream/27-one-shot-tensor-like-copy/llvm.patch`:
  `BufferizationOptions::tensorAllocationFn`, a copy of every tensor-like
  out-of-place operand, and the copy of a result given only to the uses the
  result had before it; checked by tests/upstream-one-shot-tensor-like-copy,
  a graded array copied at the cast that makes it
- retire: when the pin copies such an operand, and gives a result's copy
  only to the result's earlier uses

## tensor-like-per-instance

- sites: `!idr.graded<uses, hold, T>` and every bridge of a graded tensor
  (D43, L12)
- workaround: `upstream/64-tensor-like-per-instance/llvm.patch`:
  `isTensorLike`/`isBufferLike` through `extraClassOf`, and the shape
  traits gone; checked by tests/upstream-tensor-like-per-instance
- retire: when the pin decides tensor-likeness per instance

## kept-digest

- symptom: upstream's storage is fixed when it is constructed, and the
  mutable part of one changes only through `mutate`, under the uniquer's
  write lock. But MLIR gives a storage its kind (its abstract attribute or
  type, and through it its dialect) only after constructing it:
  `StorageUniquer::get` runs the init function after `construct`. A deep
  part's content digest is what its dialect's bytecode writes of it, so no
  storage can compute its digest when it is made
- sites: foreign/idr/include/idr/IR/Families/FamilyStorage.h (`KeptDigest`,
  in the storages of a family and a constant constructor),
  foreign/idr/lib/IR/Types.cpp (in a data type's storage), and
  foreign/idr/lib/IR/ContentNames.cpp, which reads a digest from its
  storage and keeps it there the first time it computes one (U08,
  d73d79c20)
- workaround: each of the three storages holds the digest beside its key,
  in two atomic words and a flag, filled the first time the digest is
  asked, outside `mutate`, and read with no lock ever after. Two workers
  that ask at once each compute the one digest and keep it, and a reader
  that sees it marked kept sees it whole. Not through `mutate`: a reader
  would have to race it or take the uniquer's lock, and optimizer workers
  queued on that lock for half of a ten-minute window when a data type's
  facts were read that way (98c6315c). Not made eagerly either: most parts
  are never digested
- retire: when a storage can compute its digest as it is constructed, or
  no digest is asked of these parts
- upstream: none

## simdutf-constexpr-implementation

- sites: runtime/Strings/Simd.h (`rt::strings::utf8`, a constant of the
  class the target's entry names, IDRIS_RT_SIMDUTF_CLASS), and every call
  of the runtime into simdutf through it, each direct, so the stack bound
  sees its callee; the runtime compiles simdutf from the bootstrap's
  export (runtime-library-export)
- workaround: `upstream/98-simdutf-constexpr-implementation/simdutf.patch`:
  `constexpr` on the base constructor and on every architecture's but
  rvv's, which asks the processor for Zvbb; checked by
  tests/upstream-simdutf-constexpr-implementation
- retire: when a pinned simdutf release has constexpr constructors

## snmalloc-arm-yield-asm

- sites: the runtime's snmalloc, compiled by runtime/Alloc/Cells.cpp from
  the bootstrap's export (runtime-library-export)
- workaround: `upstream/49-snmalloc-arm-yield-intrinsic/snmalloc.patch`:
  one `#elif __has_builtin(__builtin_arm_yield)` branch that emits the
  same instruction as an intrinsic, applied to the export since snmalloc
  became a patch project (2026-10-21); checked by
  tests/upstream-snmalloc-arm-yield-intrinsic
- retire: when the snmalloc pin moves past upstream's change

## runtime-library-export

- symptom: the fixes of the libraries the runtime compiles are patches to
  their source, snmalloc's (94, 95, 49) and simdutf's (98), which the
  runtime's build cannot apply to the submodules it would compile
- sites: tools/bootstrap.sh (steps `snmalloc` and `simdutf`, one
  `step_export`), tools/patches.sh (projects `snmalloc` and `simdutf`),
  tools/verify-pins.sh (`sysroot`); the toolchain files, which name the
  exports as `IDRIS_MLIR_SNMALLOC` and `IDRIS_MLIR_SIMDUTF`;
  runtime/CMakeLists.txt, which compiles both from them
- workaround: the bootstrap exports third_party/snmalloc and
  third_party/simdutf, each at its gitlink, the lock's revision, with its
  patches applied in the order of their numbers, into
  .toolchain/<name>/src, stamped with them; the runtime compiles those
  copies
- retire: a library's export goes when it carries no patch
- upstream: none
- status (2026-10-21): snmalloc's new with this bump; simdutf's with C169

## snmalloc-pagemap-sanity-checks

- sites: the runtime's heap (runtime/Alloc), snmalloc's bounded flat map
  over the heap's one span (C5, C100); its frees are of cells its types
  prove are heap cells
- workaround: `upstream/94-snmalloc-pagemap-sanity-checks/snmalloc.patch`:
  the tests run only under `sanity_checks`; null still reads the default
  entry; checked by tests/upstream-snmalloc-pagemap-sanity-checks
- retire: when a pinned snmalloc release gates them

## snmalloc-notify-using-result

- sites: the runtime's heap under a strict host (overcommit mode 2,
  `ulimit -v`), which must end with status 111 (D35, D37)
- workaround: `upstream/95-snmalloc-notify-using-result/snmalloc.patch`:
  `notify_using` and `notify_using_readonly` return false when `mprotect`
  fails; every caller already handles it; checked by
  tests/upstream-snmalloc-notify-using-result
- retire: when a pinned snmalloc release reports the failure

## darwin-stack-clash

- sites: tools/bootstrap.sh (stage 2's and GMP's flags, the same on every
  target; stage 1 built from the patched tree, since it compiles stage 2's
  LLVM); CMakeLists.txt's target entries and the runtime's probe flags,
  which give our tools and the runtime the flag (C5, C59)
- workaround: `upstream/86-darwin-stack-clash/llvm.patch`: Darwin joins the
  systems the driver passes the flag for; checked by
  tests/upstream-darwin-stack-clash, which compiles the report's
  `large-frame.c` for arm64-apple-macosx14.0 with the flag and `-Werror`
  and finds the probe loop
- retire: when the pin's driver passes the flag for Darwin

## mirrored-sources

- symptom: GMP's official host (gmplib.org) is unreachable here; the
  submodule is a clone of a GitHub mirror (arthenica/gmp)
- sites: .gitmodules, toolchain.lock.json (`release`, `release_sha256`),
  tools/bootstrap.sh (`verify_release`)
- workaround: it is pinned by commit to its release tag; the lock records
  the official release tarball and its SHA-256 (as buildroot and Homebrew
  publish it). The gmp step fetches the tarball when it can and
  refuse a SHA-256 that differs, or a file the release ships that the
  pinned commit lacks or holds otherwise; the files the commit has beyond
  the release (GMP's release leaves out its development tests, and one
  x86-64 assembly file, `mpn/x86_64/addaddmul_1msb0.asm`) are named in the
  stamp. The build is the commit's files either way. When it cannot
  fetch it, it says so and the stamp records `not verified`
- retire: when the official host is reachable and the check has passed
  once
- upstream: none

## idris-support-host-cc

- symptom: the pinned toolchain builds everything else with the stage-2
  clang, for the target, but Idris's C support library is a shared object
  loaded by Chez Scheme, a dynamically linked process of the host's C
  library (glibc on Linux, libSystem on macOS): a host program
- sites: tools/bootstrap.sh (steps `chez` and `idris`)
- workaround: the pinned Chez Scheme and Idris 2 are built with the host's C
  compiler; they are host programs and never link into an executable
- retire: when Chez Scheme itself is built on the pinned toolchain for the
  host
- upstream: none

## effectful-argument-inline

- sites: everything the stock host compiles to run: stage 0, the test
  runner, the benchmarks' Chez baseline
- workaround: `upstream/96-effectful-argument-inline/idris.patch`: a
  value the body never uses that is a computation is kept, evaluated
  before the body by a `let` the inliner never inlines; a recursive call
  is an identity's only where its other arguments are no computations;
  checked by tests/upstream-effectful-argument-inline
- retire: when the Idris pin carries upstream's fix

## coverage-repeated-split

- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/104-coverage-repeated-split/idris.patch`: the walk
  that proposes missing patterns names a re-split variable's arguments as
  the later split binds them; checked by
  tests/upstream-coverage-repeated-split
- retire: when the Idris pin carries upstream's fix (open issues #550 and
  #3710 report the symptom)

## case-tree-fallthrough-copies

- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/105-case-tree-fallthrough-copies/idris.patch`:
  each copy of a fallthrough keeps, in its cases on the variable just
  matched, only the alternatives that variable can still take; checked by
  tests/upstream-case-tree-fallthrough-copies
- retire: when the Idris pin carries an upstream fix that keeps such
  trees small

## size-change-call-paths

- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/106-size-change-call-paths/idris.patch`: the path
  is lazy, built only where a loop is reported; checked by
  tests/upstream-size-change-call-paths
- retire: when the Idris pin carries upstream's fix

## delayed-case-expected-type

- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/107-delayed-case-expected-type/idris.patch`:
  `delayElab` hands the delayed elaborator its hole's type, at which
  `checkCase` elaborates the block; checked by
  tests/upstream-delayed-case-expected-type
- retire: when the Idris pin carries upstream's fix for #3418

## case-split-pattern-fragment

- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/108-case-split-pattern-fragment/idris.patch`:
  where an unsolved meta is applied to the variable a case splits and
  every clause splits it, the case function takes the variable twice,
  those metas applied to an unsplit copy at quantity 0; a case with a
  clause whose pattern there is a variable is left as the stock Idris
  builds it, since that clause solves the metas; checked by
  tests/upstream-case-split-pattern-fragment
- retire: when the Idris pin carries upstream's fix for #62

## delayed-retry-doubling

- sites: everything the stock host checks: stage 0 and the libraries;
  correct code is unaffected, an error in it is slow to report
- workaround: `upstream/109-delayed-retry-doubling/idris.patch`: an
  attempt that would begin with every metavariable unsolved that was
  unsolved when the last one failed is not run, its error kept; checked by
  tests/upstream-delayed-retry-doubling
- retire: when the Idris pin carries an upstream fix

## coverage-erased-index-first

- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/110-coverage-erased-index-first/idris.patch`: an
  erased function's coverage tree takes the arguments a run would keep,
  from the left, then the erased ones from the right; the tree a
  definition is evaluated by, and a kept function's coverage tree, are
  unchanged; checked by tests/upstream-coverage-erased-index-first
- retire: when the Idris pin carries an upstream fix

## coverage-nested-empty-type

- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/111-coverage-nested-empty-type/idris.patch`: a
  type is empty also when each constructor that fits it takes an argument
  of an empty type, the arguments its return type determines replaced by
  what the type has there, or read under what the other arguments' types
  hold of the fresh names (a type with one constructor holds what its
  return type and its arguments' types hold, `Refl`'s two sides equal);
  an argument's type is looked into only while it is smaller than the
  type it is an argument of; checked by
  tests/upstream-coverage-nested-empty-type
- retire: when the Idris pin carries an upstream fix

## do-local-definition-scope

- sites: every do block the stock host checks: stage 0 and the libraries
- workaround: `upstream/112-do-local-definition-scope/idris.patch`:
  `expandDo` adds a bound name, a let-bound name and the names a local
  block defines to those names, as the lambda, `let ... in` and the local
  block it translates to do; checked by
  tests/upstream-do-local-definition-scope
- retire: when the Idris pin carries an upstream fix

## type-implicit-binding-order

- sites: every type the stock host checks: stage 0 and the libraries
- workaround: `upstream/113-type-implicit-binding-order/idris.patch`:
  `checkBindHere` retries a type's constraints in match mode before its
  defaults and before binding its unsolved implicits, the order a term's
  elaboration takes; checked by tests/upstream-type-implicit-binding-order
- retire: when the Idris pin carries an upstream fix

## let-delayed-elaborator-dropped

- sites: every let the stock host checks: stage 0 and the libraries
- workaround: `upstream/114-let-delayed-elaborator-dropped/idris.patch`:
  `runDelays` keeps the delayed elaborators it does not retry and puts
  them back for the retries around it; checked by
  tests/upstream-let-delayed-elaborator-dropped
- retire: when the Idris pin carries an upstream fix

## size-change-as-pattern-doubling

- sites: every definition the stock host checks: stage 0 and the libraries
- workaround: `upstream/115-size-change-as-pattern-doubling/idris.patch`:
  `knownOr` returns the known result instead of the comparison that gave
  it; checked by tests/upstream-size-change-as-pattern-doubling
- retire: when the Idris pin carries an upstream fix

## record-update-variable-type

- sites: every record update the stock host checks: stage 0 and the
  libraries
- workaround: `upstream/116-record-update-variable-type/idris.patch`:
  `checkUpdate` reads the record's name off the variable's type in the
  environment while the expected type is not yet a type constructor's,
  and checks the update against the expected type as before; checked by
  tests/upstream-record-update-variable-type
- retire: when the Idris pin carries an upstream fix

## case-scrutinee-postponed-constraints

- sites: every case the stock host checks: stage 0 and the libraries
- workaround: `upstream/117-case-scrutinee-postponed-constraints/idris.patch`:
  `checkCase` solves the postponed constraints (no default applied) where
  the scrutinee's type is still headed by a metavariable, before it gives
  the type up; checked by tests/upstream-case-scrutinee-postponed-constraints
- retire: when the Idris pin carries an upstream fix

## clause-metavariable-pruning

- sites: every unification the stock host solves in a term: stage 0 and
  the libraries
- workaround: `upstream/118-clause-metavariable-pruning/idris.patch`:
  where a solution does not shrink, `unifyHole` prunes each elaborator's
  metavariable in it of the clause's pattern variables it cannot depend
  on (solving it as a fresh one over those it keeps) and shrinks the
  solution again; checked by tests/upstream-clause-metavariable-pruning
- retire: when the Idris pin carries an upstream fix
