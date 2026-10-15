# U03 — The ready-set optimizer: each function once, after its callees are final

## Permitted outcome
1. Mandatory. `idr-optimize` (C12's `IdrOptimize`) is the ready set of
   C07: one module pass that builds the components of upstream's call
   graph through `Scc.h`, processes each function once its callee
   components are final (inline step, requests, inner pipeline once, the
   bounded local loop), calls C09's node table and analyses and C10's
   effects writes and constants summaries at the points C07 §6 fixes,
   runs in waves and puts made nodes into the module only between them,
   erases dead functions serially in module order at the end, and
   reports `numInlined`, `numCapped`, `numErased`, `numNodes` and one
   `finished` remark.
2. Mandatory. Inline decisions are C08: `idr::inlineSize`,
   `idr::inlining::Facts`, `worthInlining`, `fitsCap`, the numbers 40,
   60, 320 and 10,000, read on the callee's final facts at each call.
3. Mandatory. `idr-contify` (C12's `IdrContify`, declared in
   `Optimize.h`) is C07 §7: a private function whose one use is a call
   from another member of its component is moved into that call.
4. Mandatory. `idr-identity` reads `Identities::givesBack` (C09 §8)
   through `getCachedParentAnalysis<idr::Identities>()`; without it the
   pass fails with an internal error naming what it lacks.
5. Mandatory. `References` and `Holds` as C07 §8 and §9: References'
   sites are the symbol uses that name an `idr.func`; Holds walks C01's
   identified types.
6. Mandatory. `Canonicalize.h` and `Scc.h` keep their code; their
   comments stop naming the mechanisms this lane deletes.
7. Mandatory. Every unit of `## Delete` is gone from this lane's writes.

No consumer adaptation outside these writes: a consumer of a deleted or
changed declaration (U04, U05, U08, U10, U17) adapts in its own files;
this lane lists each in its handoff.

## Owner / exclusive writes
- `IDR/Transforms/Simplify` (`foreign/idr/lib/Transforms/Simplify/`):
  deleted whole.
- `INC/Transforms/Simplify.h`: deleted.
- `IDR/Transforms/Optimize` (new): `Optimize.cpp`, `ReadySet.cpp`,
  `Component.cpp`, `Waves.cpp`, `Contify.cpp` (no header beside them: the
  scheduler is declared in `Optimize.h`).
- `INC/Transforms/Optimize.h` (new): C07 §3.
- `IDR/Transforms/Inline`: `Inline.cpp` rewritten as the inline step;
  `Prepare.cpp` deleted.
- `INC/Transforms/Inline.h`: rewritten (section Implement).
- `IDR/Transforms/Identity` (`Identity.cpp`) and
  `INC/Transforms/Identity.h`: the summary read.
- `IDR/Analysis/Inline.cpp` and `INC/Analysis/Inline.h`: C08.
- `IDR/Analysis/References.cpp` and `INC/Analysis/References.h`: C07 §8.
- `IDR/Analysis/Holds.cpp` and `INC/Analysis/Holds.h`: C07 §9.
- `INC/Transforms/Canonicalize.h`: comment only.
- `INC/Support/Scc.h` and `IDR/Support/Scc.cpp`: comment only.

**Excluded:** `foreign/idr/include/idr/Transforms/Passes.td`,
`lib/Transforms/Pipeline.cpp`, `lib/Driver/Run.cpp:120` and
`tools/idris-mlir-opt.cpp` (the registration of the deleted round
instrumentation) are U06's; `lib/Transforms/Specialize/`,
`include/idr/Transforms/Specialize.h`, `include/idr/Analysis/Specialize.h`,
`lib/Analysis/BindingTimes.cpp`, `lib/Analysis/Identities*.cpp` and
`include/idr/Analysis/Identities.h` are U04's;
`lib/Transforms/Effects/`, `include/idr/Transforms/Effects.h`,
`lib/Analysis/Effects.cpp`, `include/idr/Analysis/Effects.h`,
`lib/Analysis/Constants.cpp` and `include/idr/Analysis/Constants.h` are
U05's; `include/idr/IR/` and `lib/IR/` (the dialect's inliner interface
`lib/IR/Func/Inliner.cpp`, `TypeGraph`, `FuncOp`) are U01's;
`lib/Transforms/Deduplicate/` is U16's; `lib/Transforms/Expect/` and
`tests/idr/` are U17's; the rest of `tests/` is U18's; every
`CMakeLists.txt` is the coordinator's.

## Read first
- `contracts/C07-ready-set.md` and `contracts/C08-inline-decisions.md`
  (this lane's), whole; `contracts.md` for C01, C02, C03, C06, C09, C10,
  C12 once it exists, the contract files under `contracts/` until then.
- `proposals/0004-compile-time/README.md`: §2.7 (consequences of the
  order), §3.2 and §3.4 (why the rounds never decayed, where the cost
  is), §4 stages 5 to 10 and the determinism rules, §6 (the rows this
  lane owns), §8 ranks 1, 2 and 6, §9, §10 (L3's row and the
  thresholds), §11 D13, D14, D15, D16, D17, D25, D38, D39, D45, D47.
- `sources/notes/compile-pipeline/mojo.md` §2 and §5,
  `upstream-mlir-llvm.md` §1, §3, §4, `mlton.md` §3,
  `casework-audit.md` §1.B, §1.D, §3.
- `sources/code/modular/Mojo/lib/Transforms/AutomaticInline.cpp:100-200,
  380-501`, `sources/code/modular/Mojo/include/Mojo/TransformUtils/SCCUtils.h:60-170`
  (the design rebuilt; no line is copied).
- `sources/code/mlton/mlton/ssa/inline.fun:217-295`,
  `mlton/ssa/contify.fun:1-140, 309-420`,
  `mlton/control/control-flags.sml:1011-1041, 1224-1226`.
- Pinned MLIR under `.toolchain/build/llvm-project/mlir`:
  `lib/Transforms/Utils/Inliner.cpp:490-568, 720-769` (per-thread
  pipelines, the serial `nest`, the legality rules),
  `include/mlir/Transforms/InliningUtils.h:30-160` (`inlineCall`),
  `lib/Pass/Pass.cpp:560-700, 1138-1170` (`runPipeline`, `nest`, the
  verifier after each pass), `include/mlir/Analysis/CallGraph.h`,
  `lib/Analysis/CallGraph.cpp:60-160`, `include/mlir/IR/Threading.h`,
  `../llvm/include/llvm/Support/ThreadPool.h:60-75`.
- Our tree: `lib/Transforms/Simplify/` (every file, for what it did and
  what goes), `lib/Transforms/Inline/Inline.cpp:55-324`,
  `lib/Transforms/Inline/Prepare.cpp`, `lib/Analysis/Inline.cpp`,
  `lib/Analysis/References.cpp`, `lib/Analysis/Holds.cpp`,
  `lib/Transforms/Identity/Identity.cpp`, `include/idr/Support/Scc.h`,
  `lib/IR/Func/Inliner.cpp` (U01's interface, read only),
  `include/idr/IR/IdrOps.td:15-60` (`FuncOp::absorb`, `no_inline`),
  `include/idr/Support/Profile.h`, `include/idr/Support/Actions.h`,
  `lib/Transforms/Specialize/Clones.cpp` and `Specialize.cpp` (what the
  nodes replace, read only), `compiler/src/IdrisMLIR/Emit/Declarations.idr:60-80`
  (who writes `no_inline`).

## Fixed decisions
- The graph is upstream's `mlir::CallGraph`, its `Call` edges between
  `idr.func` nodes, and a force edge from a function to every label of
  each memo sum it forces (C10 §2, §7), its components from
  `idr::components` over the functions in module order (0004 §4 stage
  6). After defunctionalization every closure is a direct call (C06). A
  constructor or a match naming a label is no edge: building a cell runs
  nothing.
- `calls(f)` is counted when idr-optimize begins and frozen; a made node
  has 1 (C08, D14).
- One node's work is C07 §4.3's loop, its order fixed: inline step, the
  inner pipeline, the requests its redirect step made (parked until the
  requested nodes are final); it stops when an iteration after the first
  inlines nothing and follows no request. A component's finish writes the
  call effects again before the entries (C07 §4.3). The inner pipeline is C07
  §4.2's six passes, run through `Pass::runPipeline` from per-thread
  copies of one `OpPassManager`.
- Inlining is `mlir::inlineCall` with the dialect's interface, cloning
  the callee's final body, in walk (pre-)order over the calls present at
  the step's start; the caller absorbs the callee's totality. The
  single-block rule is upstream's. A callee is a candidate exactly when
  its node is final.
- The ready set runs in waves (C07 §5): a wave is the turn of every
  component that can go on, run under `mlir::failableParallelForEach`;
  between waves, on the pass thread with no turn running, made nodes go
  into the module, finished components become final, requests become
  waits or merges, and the next wave is read off what is final. No unit
  holds a `std::atomic` or a lock on schedule state: what a wave reads is
  fixed for it. `runPipeline` nests an analysis manager per function, and
  `AnalysisManager::nest` inserts into a map no worker may read while it
  changes (`Pass.cpp:1161-1168`), so a function is inserted, entered and
  nested only between waves. A body is built detached, by C09's `build`,
  in the turn C09's `claim` picks, then inserted by C09's `insert`, after
  its owner, by name.
- Cycles among made nodes merge into one component (C07 §5.3). C03 runs
  the module rules from the root's `verifySymbolUses`, which a pipeline
  on one function never calls, so the root runs as any function.
- State of the run lives in `idr::optimize::ReadySet` (C07 §3), a module
  analysis the pass takes before the first wave, which is also C09's
  `Schedule`; C09's table and analyses and C10's summaries are module
  analyses the pass takes first, so the inner pipeline's passes find them
  cached. A node's `final` and its waits change only between waves.
- Dead functions are erased at the end of idr-optimize, serially, in
  module order: every private `idr.func` no symbol use reaches from the
  root.
- Contification is C07 §7: one use, a call from another member of its
  component, moved in with `inlineCall` without cloning, sweeps until
  none moves. It applies no cap: it copies nothing.
- Statistics are C12's four; remarks come only from the pass thread
  (upstream remarks are not thread-safe, upstream-mlir-llvm §7): one
  `progress` remark after each wave (metrics `final`, `nodes`, `made`),
  one `finished` at the end. The turns' counts are summed between waves
  and added to the statistics by the pass.
- Every number: 40, 60, 320 (0004 §6, "Kept"); 10,000 (D25); 1,024 is
  C09's (D39) and is not written in this lane's code.

## Inputs
- C01: identified data types, their kind (closures, memo, plain) and
  constructors, for `Holds` through U01's `TypeGraph`; how a label
  constructor is named (a symbol reference to its function).
- C02: `idr.func`'s `no_inline` and `total` with `FuncOp::absorb`; the
  call-site `effects` verified equal to the callee's.
- C03: the root is the one public `idr.func`, and its `verifySymbolUses` runs the
  module rules.
- C06: the postconditions of defunctionalization (no closure, apply or
  suspension; dispatch arms are direct calls carrying no `effects`).
- C09: `idr::specialize::Nodes` (`start`, `takeRequests`, `claim`,
  `build`, `insert`), `idr::specialize::Schedule`, `idr::BindingTimes::solve`,
  `idr::Identities::solve` and `givesBack`, `idr::createIdrRedirect()`.
- C10: `idr::writeCallEffectsOnReady`, `idr::writeEntriesOnFinal`,
  `idr::forcedLabels`, `idr::ConstantSummaries` (`publish`),
  `idr::createIdrConstants()`.
- C12: the `IdrOptimize`, `IdrContify` and `IdrIdentity` defs, their
  statistics and dependent dialects; `createIdrRedirect`.

## Outputs
- C07: `include/idr/Transforms/Optimize.h` (`NodeAction`, `Node`, `Scc`,
  `ReadySet` as C09's `Schedule`, `buildInnerPipeline`, `Scheduler`), the pass
  behaviour of §4 and §5, the call points of §6, `idr-contify` of §7,
  `References` of §8, `Holds` of §9, `Scc.h` of §2. Consumers: U04, U05,
  U06, U17, and U01, U02, U08 for `Scc.h`.
- C08: `include/idr/Analysis/Inline.h` (`idr::inlineSize`,
  `idr::inlining::Facts`, `worthInlining`, `fitsCap`, the four
  constants). Consumers: U04, U17, U18.

## Implement
- `include/idr/Transforms/Optimize.h`: exactly C07 §3.
- `lib/Transforms/Optimize/ReadySet.cpp`: `ReadySet`'s constructor (one
  node per function in module order; `facts.calls` from a parallel walk
  of every body, slots merged in module order; `mlir::CallGraph` of the
  module, its `Call` edges among `idr.func` nodes; `idr::components`;
  one `Scc` per component with `callers` and `unfinishedCallees`);
  `nodeOf`, `lookup`, `isFinal`, `Scc::leader` (path-halving through
  `mergedInto`).
- `lib/Transforms/Optimize/Component.cpp`: a component's turn (C07 §4.3):
  the scheduler's constructor, the idle copies of the inner pipeline
  under a mutex, the member loop, building claimed nodes, the finish.
  Each turn opens `idr::profile::ThreadTrace`, each member
  `IDR_ZONE(<function name>)`. A starter
  begins its node's work under `idr::support::perform<NodeAction>` once
  per node.
- `lib/Transforms/Optimize/Optimize.cpp`: `buildInnerPipeline`; the
  `Optimize` pass (`impl::IdrOptimizeBase`): takes the analyses of C07
  §4.1, nests every function, runs the scheduler, checks every node
  final (else the internal error "internal error: idr-optimize: the ready
  set stopped with @<f> not final"), erases dead functions, emits the
  remarks, sets the statistics, marks `Holds`, `TypeGraph`, `Layouts`
  preserved. `getDependentDialects` adds the inner pipeline's to the
  def's. It keeps `static_assert(LLVM_ENABLE_STATS, ...)`, which left
  with the deleted Simplify unit, with its reason.
- `lib/Transforms/Optimize/Contify.cpp`: `impl::IdrContifyBase`, C07 §7,
  on `SymbolUserMap` and `idr::components` over the call graph's
  `idr.call` edges; takes the place of the deleted Simplify unit.
- `include/idr/Transforms/Inline.h` and `lib/Transforms/Inline/Inline.cpp`:
  namespace `idr::inlining`: `struct Step { unsigned inlined = 0, capped
  = 0; };` and `Step inlineCalls(idr::FuncOp caller,
  llvm::function_ref<const idr::optimize::Node *(mlir::StringAttr)> nodeOf);`
  the inline step of C07 §4.3, measuring the caller with `inlineSize` at
  its start.
- `include/idr/Analysis/Inline.h` and `lib/Analysis/Inline.cpp`: exactly
  C08.
- `lib/Transforms/Identity/Identity.cpp`: `GiveBack` reads
  `Identities::givesBack`; the comment says the identities are each
  component's, solved when it is taken up.
- `include/idr/Analysis/References.h`, `lib/Analysis/References.cpp`:
  C07 §8; the walk is `walkStoredAttributes` on every op, each
  `FlatSymbolRefAttr` the table resolves to an `idr.func` a site; the
  rest of the analysis as today.
- `include/idr/Analysis/Holds.h`, `lib/Analysis/Holds.cpp`: C07 §9 over
  C01's identified types.
- `include/idr/Transforms/Canonicalize.h`: the comment says the
  configuration is that of every canonicalizer, the inner pipeline's
  included, without naming rounds or inlining iterations.
- `include/idr/Support/Scc.h`: the comment drops the loop-breaker
  sentence.
- `lib/Transforms/Optimize/Waves.cpp`: `Scheduler::run`, the next wave,
  settling a wave (C07 §5.1, §5.2), waits and merges (§5.3).
- Failure paths: a hook or a pipeline that fails emits its diagnostic and
  fails its turn; the wave stops and the pass fails. A made name already in the table, a node left not
  final, a merge that would take in a function the module held: internal
  errors, never `unsupported`.

## Delete
- `lib/Transforms/Simplify/` whole: `Simplify.cpp` (`idr-simplify`, the
  `CompositeFixedPointPass` loop, `max-rounds`, `scc-pipeline`, the
  `OperationFingerPrint` fixpoint and the RDV resume loop, the
  `unsupported (compile-time budget)` error, `SimplifyInstrumentation`
  and its records), `Round.cpp` (`buildSimplifyRound`), `Scc.cpp`
  (`runSimplifySCCPipeline`, `buildSimplifySCCPre/Delta/Post`),
  `RoundFacts.cpp` (`idr-round-facts`), `Trace.cpp` (the census and the
  round remarks), `LoopBreakers.cpp` (`idr-loop-breakers`, its
  `no_inline` marks and its reading of `break_last`), `Contify.cpp`
  (replaced by `Optimize/Contify.cpp`).
- `include/idr/Transforms/Simplify.h` whole.
- `lib/Transforms/Inline/Inline.cpp`'s `idr-inline` pass, `InlineCleanup`,
  the `idr.inlined` seed marks, the preparation and inline repeat with its
  `OperationFingerPrint` cycle guard, the use of upstream's `Inliner`
  driver and `CallGraph` rebuilt per cycle.
- `lib/Transforms/Inline/Prepare.cpp` whole (ForceAtCapture,
  ForceOfOneConstant, the `.capture<n>` names) and its three declarations
  in `Inline.h`.
- `idr::InlineDecisions` and its analysis (`lib/Analysis/Inline.cpp:21-129`).
- `References::callsUnknown`, `idr::closureLabel`, and every
  `isExternal()` test in this lane's files (D7).
- `Identity.cpp`'s comment on identities found once per round.

## NOT TO DO
- Do not keep the rounds, a fixpoint loop, a module fingerprint, an
  iteration counter or a budget that refuses, in any form, under any name
  (`OperationFingerPrint`, `max-rounds`, `compile-time budget`).
- Do not add a pass option, a toggle, a dual path, or a flag that selects
  the old behaviour; experiments compare binaries (D2).
- Do not mark anything with a discardable attribute (`idr.inlined` or
  any successor) or name a function from a counter.
- Do not write `Passes.td`, `Pipeline.cpp`, `Run.cpp` or the tools (U06),
  the specialization or effects units (U04, U05), the dialect (U01),
  tests (U17, U18) or a build list (coordinator); report what they need.
- Do not port `AsyncRT`, `PerThreadPassManagers` or `CallGraphUtils.h`
  (D24); do not run a `PassManager` per thread: the inner pipeline runs
  through `runPipeline`.
- Do not insert, erase or nest a function while a turn runs, and do not
  share schedule state between turns of a wave.
- Do not re-read `calls(f)` after the pass begins, or read a callee that
  is not final.
- Do not apply the inline rule or the cap in `idr-contify`, and do not
  contify a function of two or more call sites.
- Do not compute effects, constants, identities or binding times in this
  lane: call C09's and C10's declarations.

## Tempting partial solutions
- **Keep upstream's `Inliner` with a profitability callback.** It
  re-optimizes every node of a component on every iteration and parallels
  only inside one component (0004 §3.4); rejected by acceptance 3 (each
  node's action begins once) and 6 (no `mlir::Inliner` in the lane).
- **Run the inner pipeline per function with a fresh `PassManager`.**
  Turns off the instrumentation the outer manager carries and loads
  dialects from workers; rejected by acceptance 6.
- **Make a node while other turns run, guarded by a reader-writer lock
  around `runPipeline`.** A writer starves under continuous readers, and
  the module's analysis map is read inside upstream code the lock cannot
  reach; rejected by acceptance 6 (insertion only between waves).
- **Let a requester go on past a node that is not final yet.** Whether
  the node's body is inlined then depends on timing; rejected by
  acceptance 4 (determinism at 1, 2 and 8 threads).
- **Keep LoopBreakers to cut cycles among made nodes.** A cycle is a
  merged component and its members are never inlined into one another;
  rejected by acceptance 6 (no `no_inline` written, no `LoopBreakers`).
- **Contify every function of one call.** Builds bodies past the cap
  before the ready set can stop it (0004 §3.2: single-call absorption
  builds the giant); rejected by acceptance 5.
- **Keep `InlineDecisions` as a module analysis and read it per call.**
  It decides on bodies before they are final; rejected by acceptance 6.

## Acceptance
1. `python3 proposals/0004-compile-time/check-units.py` on every `.cpp`
   of this lane shows no failure of this lane's own code; a failure
   caused by a header another lane has not written yet (C01, C09, C10,
   C12's `Passes.h.inc`) is listed as a seam with the contract it waits
   on in the handoff.
2. No file of `foreign/idr/lib/Transforms/Simplify/` and no
   `Simplify.h`, `Prepare.cpp` or `InlineDecisions` remains; `grep -rn`
   over this lane's writes finds no name `## Delete` lists, and none of
   `CompositeFixedPointPass`, `getBreakLast`, `setNoInline`, `maxRounds`,
   `isExternal`, `callsUnknown`, `closureLabel`.
3. Source review: a node's work begins under `NodeAction` exactly once;
   the inner pipeline is built in one place and run only through
   `runPipeline`; every insertion, symbol-table entry, `nest` and erasure
   happens on the pass thread between waves.
4. Source review: every map iterated for output is ordered (module order,
   key order or name order); no output depends on thread count.
5. Source review: `idr-contify` moves only a function of one call site
   in a component with its caller, never clones, and applies no cap.
6. Source review: no `mlir::Inliner`, no `PassManager` constructed in the
   lane, no `setNoInline`, no option in either pass, every number cites
   C08.
7. On the owner's machine (listed, not run here): `make test-idr`'s
   `optimize/once`, `optimize/pure-call`, `optimize/caller-cap`,
   `optimize/totality`, `names/reorder`; `tests/determinism` at 1, 2 and
   8 threads; the D25 record and the optimizer segment under 600 s on
   stage 0 (0004 §10).

## Stop and return
Return when the outcome is written and checked as far as this machine
allows: the changed paths, each mapped to an outcome; C07 and C08 as
supplied; check-units output for every unit of the lane; every seam:
C09's and C10's declarations as built, C01's identified-type accessors
for `Holds`, C12's generated `IdrOptimize`, `IdrContify` and (C10's)
`IdrConstants` bases, U06's deletion of the round instrumentation's
registration, the uses of `References::callsUnknown` and
`idr::closureLabel` outside this lane. Report a conflict between C07 and
a sibling's contract with the evidence and keep working on the rest.
