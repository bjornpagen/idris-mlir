# Upstream MLIR and LLVM mechanisms against our custom C++

Research report of 2026-10-14 for the pipeline cutover proposal, written by a research agent from read-only reading, kept verbatim. Paths are as the report gives them: `M/` and `L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`, Modular paths are relative to `~/Documents/modular` at 9211931, MLton paths are under `code/mlton/` here or the fetch named in it. Claims marked recalled or inferred are not read from source.

---

# Upstream MLIR/LLVM mechanisms vs. idris-mlir's custom C++: inlining, call graph, parallelism, dataflow, lowering, codegen

Path prefixes: `M/` = `.toolchain/build/llvm-project/mlir/`, `L/` = `.toolchain/build/llvm-project/llvm/`, `idr/` = `foreign/idr/`. Everything below was read from the pinned tree. I edited nothing and built nothing.

## 1. mlir::Inliner

**Traversal.** `runTransformOnCGSCCs` walks `llvm::scc_iterator<const CallGraph*>` in post-order. It copies each SCC before advancing, so the transformer can delete nodes (M/lib/Transforms/Utils/Inliner.cpp:285-299). SCCs are visited strictly one after another. The CallGraph is never updated after an inline. Only the `CGUseList` symbol-use counts change (Inliner.cpp:695-705). Calls exposed by an inline reach the current SCC's worklist through `processInlinedBlocks` (384-395), but no new SCC structure ever forms.

**Per-SCC loop** (`inlineSCC`, 472-491): `optimizeSCC` runs, then `inlineCallsInSCC`, repeating until an iteration inlines nothing or `maxInliningIterations` is reached.
- `optimizeSCC` runs the pipeline on **every** node of the SCC on every iteration. It skips nodes with child callables and nodes that are not IsolatedFromAbove (497-514), then recomputes their symbol uses (522-524).
- `inlineCallsInSCC` walks each node's body to collect calls (604-616), keeps an inline history so it does not unroll through a cycle (618-692), and blocks recursive edges from the next iteration on (712-714).
- When a callee is single-use and discardable, it is inlined in place (moved, not cloned) and deleted (661-668, 702-705).

**Hard-coded legality** (`shouldInline`, 720-769), checked before the profitability callback:
- no call that is a terminator;
- no callee that calls itself or calls its caller back (A→B→A), checked against the stale static edges (729-734);
- no callee that is an ancestor of the call;
- no multi-block callee into a single-block region unless `canHandleMultipleBlocks` is set.

**InlinerConfig** (M/include/mlir/Transforms/Inliner.h:27-97) has five knobs:
- `defaultPipeline`, an `OpPassManager` builder;
- `opPipelines`, keyed by op name;
- `maxInliningIterations`;
- `cloneCallback`;
- `canHandleMultipleBlocks`.

The profitability callback receives only `ResolvedCall{call, sourceNode, targetNode}`. The header itself says the interface "might need to be extended" (Inliner.h:120-125). The runner hook `RunPipelineHelperTy` (117-118) is how a pass supplies `runPipeline`.

**The stock pass.**
- Its default pipeline is `canonicalize` (InlinerPass.cpp:33-35).
- `max-iterations` defaults to 4 and `inlining-threshold` to -1U (M/include/mlir/Transforms/Passes.td:319-340).
- The threshold is a callee/caller op-count ratio, and it **walks both regions for every candidate call** (InlinerPass.cpp:98-128). That is O(size) per call, with no growth cap and no caller cap.

**Parallelism.** It exists only inside one SCC. `optimizeSCCAsync` keeps `getNumThreads()` copies of the pipelines and runs `failableParallelForEach` over the SCC's nodes, after a serial `am.nest` for each node to avoid races (528-568). Idris SCCs are almost all singletons, so the inliner is effectively serial; idr's own comment says the same (idr/lib/Transforms/Inline/Inline.cpp:10-14).

**Cost per iteration, per SCC:** one body walk to collect calls, one symbol-use walk per node, a pipeline dispatch per node, plus the one-time `CGUseList` walk over every symbol table (127-162) and the CallGraph build (two full walks, M/lib/Analysis/CallGraph.cpp:99-110). idr sets the iteration limit to UINT_MAX (Inline.cpp:238). A `do` block of n statements therefore costs n iterations, each walking the whole caller: O(n·size) on a large root.

**Hooks idr already uses** (Inline.cpp:234-293):
- the precomputed decision set as the profitability callback (262-265);
- the clone callback for `absorb` plus seed marking (241-261);
- `componentPipeline` (`InlineCleanup`, seeded `applyOpPatternsGreedily`, 76-157) as the default pipeline;
- the runner, to skip functions nothing was inlined into (272-278).

That is about the full extent of the API. What the API lacks:
- a "dirty node" notion, so idr builds `marks` itself;
- a legality override, which is why Contify exists;
- caller context in the cost callback.

**LLVM's inliner, for comparison.**
- Its cost is a threshold on instruction cost: default 225 (L/lib/Analysis/InlineCost.cpp:59-60, 77-78), 250 at O3 (L/include/llvm/Analysis/InlineCost.h:46), hint 325, cold 45, hot call site 3000 (InlineCost.cpp:81-82, 117-122).
- It charges 5 per instruction, 25 per call (141-142, 153-154) and 25 per loop (InlineCost.h:51).
- Analysis stops the moment cost crosses the threshold, so a decision is cheap (InlineCost.cpp:1133-1146).
- The last call to a local function gets the `LastCallToStaticBonus` (InlineCost.cpp:2106, 2201; L/include/llvm/Analysis/TargetTransformInfoImpl.h:98).
- Growth is bounded by `intra-scc-cost-multiplier` on call sites inlined through an SCC (L/lib/Transforms/IPO/Inliner.cpp:72-80), inline history (389-403), `inline-max-stacksize` (InlineCost.cpp:157), and devirtualization repeats `MaxDevirtIterations` (Inliner.cpp:599-643).
- There is no explicit caller size cap. The bound comes from the per-callee threshold plus the multipliers.
- Unlike MLIR, LLVM updates its LazyCallGraph incrementally (L/include/llvm/Analysis/CGSCCPassManager.h:417, 428).

idr's rule (idr/lib/Analysis/Inline.cpp:23-25, 42-53, with leaf ≤ 40, small 60, product 320, decided once bottom-up) is the right shape for the callback. It is effectively the LLVM threshold plus last-call bonus, collapsed into one formula.

## 2. CallGraph, scc_iterator, indirect calls

- `CallGraphNode` edges are `Abstract`, `Call` or `Child` (M/include/mlir/Analysis/CallGraph.h:43-89). `GraphTraits` makes the graph usable with `scc_iterator` (250-262).
- Edges are built only from `CallOpInterface` ops (CallGraph.cpp:74-97). Every top-level callable gets an abstract edge from the external node, which a FIXME admits is over-conservative (113-135).
- `eraseNode` is O(nodes) (158-172).
- **Indirect calls:** for a `Value` callee, `resolveCallable` returns the defining op (M/lib/Interfaces/CallInterfaces.cpp:187-201). If that op is not a callable, the call maps to `UnknownCalleeNode` (CallGraph.cpp:146-155), and the inliner drops it (Inliner.cpp:322-333).
- `idr.apply` is such a call: `getCallableForCallee` returns the closure value (idr/include/idr/IR/IdrClosureOps.td:104-131). So an apply is invisible to the graph, and a closure naming `@f` contributes **no edge**.
- MLIR has no reference edges. LLVM's LazyCallGraph does: it treats taking a function's address as a potential call (L/include/llvm/Analysis/LazyCallGraph.h:82-90, `Kind::Ref` at 132).

This gap is exactly why idr keeps its own `References` graph (closure, suspend and constant labels are references; idr/lib/Analysis/References.cpp:3-15). That graph feeds LLVM's iterative Tarjan through `idr/include/idr/Support/Scc.h:3-8, 23-52`, which LoopBreakers and InlineDecisions use. The SCC algorithm is already upstream; only the graph is custom.

## 3. Pass-manager parallelism and analysis preservation

- **Scheduling.** A nested `OpPassManager` runs async whenever threading is on (M/lib/Pass/Pass.cpp:847-852). It makes `maxConcurrency` copies of the pipeline (927-931), collects the direct children of the anchor op serially, calling `am.nest` for each (950-977), and dispatches them with `parallelForEach` (991-1009).
- **`failableParallelForEach`** (M/include/mlir/IR/Threading.h:35-79) uses an atomic index over the range with a `ThreadPoolTaskGroup`, so a worker that waits also takes work. It stops at the first failure, sets per-element order IDs for diagnostics, and runs serially when threading is off or there is at most one element. `parallelFor` and `parallelForEach` are wrappers (116-143).
- **Determinism.** The result is deterministic only under the documented pass contract: never inspect or modify siblings, keep no mutable state across runs (sources/docs/mlir/docs/PassManagement.md:29-51). Diagnostics are re-ordered by element index (Diagnostics.cpp:1041-1049).
- **A module pass processing independent units** uses the same primitives directly: slots per unit, filled in parallel and merged in order. idr already does this in LoopBreakers.cpp:100-111, Inline.cpp (Analysis):67-88 and Specialize.cpp:73-76.

**What survives:**
1. A pass's preserved set is applied to its op's analyses (Pass.cpp:619). Custom `isInvalidated` hooks are honoured (M/include/mlir/Pass/AnalysisManager.h:88-96, 184-191).
2. **An adaptor (the nest itself) preserves nothing.** After every nested pipeline, all module analyses are dropped and `childAnalyses` is cleared (Pass.cpp:619 with an empty set, then 1183-1186). This holds even when every nested pass preserved everything.
3. **Every nested or dynamic pipeline clears its op's analyses on exit** (`scope_exit am.clear()`, Pass.cpp:673-679). Function analyses therefore never survive from one nest to the next. This applies to the inliner's per-callable `runPipeline` as well.
4. A child pass may only read a parent analysis that is already cached (`getCachedParentAnalysis`, AnalysisManager.h:301-311).

That last rule is exactly the RoundFacts workaround (idr/lib/Transforms/Simplify/RoundFacts.cpp:6-16, 35-45), re-run before every nest.

Two smaller facts:
- The verifier is skipped only when a pass preserved all analyses (Pass.cpp:631-640). Upstream CSE marks unchanged runs that way (M/lib/Transforms/CSE.cpp:51). Canonicalizer, SCCP, SymbolDCE and RDV never do.
- Statistics are collected by walking the static pipeline (M/lib/Pass/PassStatistics.cpp:62-136). Passes run through `runPipeline` (composite, inliner) are never printed, hence `SimplifyInstrumentation` (idr/lib/Transforms/Simplify/Simplify.cpp:34-40, 244-377).

## 4. Dataflow

- **`DataFlowSolver`.** One FIFO `std::queue` worklist (M/include/mlir/Analysis/DataFlowFramework.h:475). States live in a map keyed by anchor. Re-running means `eraseState` or `eraseAllStates` plus an optional `analysisFilter` re-init (345-372). There are no summaries and no incremental invalidation.
- **Interprocedural mode** is the default (285-303). It is silently disabled when the top op is not a SymbolTable (M/lib/Analysis/DataFlowFramework.cpp:126-127). That is why `int-range-optimizations` nested per function is intraprocedural and cheap (M/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:748-770; idr measured 30 s on the module against 3 s nested, Round.cpp:57-66).
- **Sparse forward and backward.** Calls go through `visitCallOperation`. With interprocedural off, or for an external callable, they go to `visitExternalCallImpl` instead (M/lib/Analysis/DataFlow/SparseAnalysis.cpp:229-251, 277-302, 523-538).
- **Callable predecessors** (`DeadCodeAnalysis`):
  - Public symbols get unknown predecessors (DeadCodeAnalysis.cpp:192-195).
  - **Any non-call symbol use** (an `idr.closure @f`) gives unknown predecessors (226-236).
  - A non-symbol callee (`idr.apply`) makes the call's results unknown (433-451).
  - So module-level SCCP (M/lib/Transforms/SCCP.cpp:135-144) propagates arguments only into functions that no closure names.
- **Liveness and RDV.** `RunLivenessAnalysis` is one serial solve over the module (M/lib/Analysis/DataFlow/LivenessAnalysis.cpp:224-244), followed by a whole-root walk (M/lib/Transforms/RemoveDeadValues.cpp:811-857). idr measured about 40 s of a 385 s round (Round.cpp:68-77).

**Per-SCC or summarized.** Nothing upstream runs per SCC. `visitExternalCall` is the hook for a summarized design: run each function's solve in parallel with interprocedural off, and override `visitExternalCall` to apply a callee summary computed bottom-up over `scc_iterator`. SCCs whose callees are all done could be solved concurrently, with a fixpoint inside each SCC. The driver and the summary lattice would be ours; the solver and analyses stay upstream.

## 5. Lowering and translation per partition

- **Lowering passes.** `convert-to-llvm` and `convert-vector-to-llvm` are op-agnostic. `convert-func-to-llvm` is anchored on `ModuleOp`, and `reconcile-unrealized-casts` is op-agnostic (M/include/mlir/Conversion/Passes.td:38, 1705, 493, 1192). A func→llvm.func conversion replaces the function op, so it cannot be anchored on the function. It can be anchored on a **nested `builtin.module`**, and a `pm.nest<ModuleOp>()` then lowers the partitions in parallel (Pass.cpp:954-1009).
- **Translation.** `translateModuleToLLVMIR(Operation*, LLVMContext&)` (M/include/mlir/Target/LLVMIR/Export.h:32-36) accepts any op that is a SymbolTable and IsolatedFromAbove (M/lib/Dialect/LLVMIR/IR/LLVMDialect.cpp:4932-4935), so a sub-module qualifies.
  - It mutates only that op (`ensureDistinctSuccessors`, DI legalization; ModuleTranslation.cpp:2735-2736) and converts in a fixed order (2747-2786).
  - Each call needs its own `llvm::LLVMContext` (L/include/llvm/IR/LLVMContext.h:63-67).
  - Concurrent translation of sibling sub-modules on one `MLIRContext` is plausible but is neither documented nor tested upstream; validate it with TSan.
- **Splitting.** MLIR has no module-splitting utility. Doing it means:
  - creating N `builtin.module` children;
  - moving each lowered function into one of them by a deterministic key (name hash or cluster, as `SplitModule` does);
  - cloning a body-less declaration of every symbol referenced from another partition into the referrer, since each sub-module is its own symbol table;
  - giving every definition referenced from another partition external **hidden** linkage, and dso_local where the target allows;
  - copying `#llvm.target` and the data layout onto each partition (idr/lib/Driver/Run.cpp:150-151).

idr's lowering tail is all top-level module passes today (idr/lib/Transforms/Pipeline.cpp:134-172), so these would need re-anchoring.

## 6. LLVM side

- **`SplitModule`** (L/include/llvm/Transforms/Utils/SplitModule.h:26-42):
  - It externalizes all locals unless `PreserveLocals` is set (SplitModule.cpp:230-239).
  - With `PreserveLocals`, it unions each local with its users into balanced clusters, sorted for determinism (110-200, 175), and distributes the rest by MD5 of the name (206-224).
  - It clones the module once per partition (284-296) and keeps module inline asm only in partition 0 (293-294). The FIXMEs warn about visibility and about internal symbols defined in asm (SplitModule.h:32-38).
- **`splitCodeGen` is no longer public.** `ParallelCG.h` is absent from the pinned tree. The live pattern is in `L/lib/LTO/LTOBackend.cpp:517-570`:
  - serialize each partition to bitcode on the main thread;
  - parse it in a fresh `LTOLLVMContext` on a pool thread;
  - give each task its own `TargetMachine`;
  - try `TM->splitModule` first (TargetMachine.h:508), then fall back to `SplitModule`.
- **Driving it through `lto::backend`.** Regular-LTO `lto::backend` runs O-level opt and then split codegen (597-622). It is reachable through `lto::LTO(Config, ThinBackend, ParallelCodeGenParallelismLevel)` (L/include/llvm/LTO/LTO.h:412-414).
- **ThinLTO-style pipelines.** `buildThinLTOPreLinkDefaultPipeline` and `buildThinLTODefaultPipeline` (L/include/llvm/Passes/PassBuilder.h:282-290) parallelize optimization too, with summary-driven imports. Thin backends initialize the time profiler per thread (L/lib/LTO/LTO.cpp:1702-1715).
- **Linker.** lld takes many objects routinely (`--threads`, `--thinlto-jobs`, `--lto-partitions`: lld/MachO/Options.td:33-45, lld/ELF/Options.td:653).

**Today idr is serial end to end.** It translates the whole module, links the runtime bitcode, internalizes all but `main`, runs one O3 and emits one object (Run.cpp:164-201; idr/lib/Target/Optimize.cpp:44-59), then links one object with the runtime (idr/lib/Driver/Compile.cpp:68-81).

**What deterministic parallel emission needs:**
1. **A fixed N**, a function of the module (for example its size) and never of `--num-threads`.
2. **Where to split:**
   - Simplest is after the whole-module O3: externalize (not `PreserveLocals`), because after `internalize` almost everything is local, and clustering locals with their users would collapse the program into one partition. Mark the externalized symbols hidden and dso_local so cross-partition calls stay direct.
   - Splitting before O3 (ThinLTO-style) loses cross-partition LLVM inlining. That matters mostly for the runtime's `available_externally` bodies, which each partition can link itself; the MLIR side already did whole-program inlining.
3. **One `LLVMContext` and `TargetMachine` per task, and objects written in index order.**
4. **A check of the runtime's inline asm** (Run.cpp:209) against the partition-0 rule.
5. **A check that musttail and the tail calls from `idr-tail-calls` hold across object boundaries on both Mach-O and ELF.**

## 7. Diagnostics, remarks, tracing

- **`ParallelDiagnosticHandler`** (M/include/mlir/IR/Diagnostics.h:720-748; M/lib/IR/Diagnostics.cpp:994-1063) buffers diagnostics per order ID and replays them stable-sorted when it is destroyed. Diagnostics from untracked threads fall through to other handlers (1014-1017). The engine itself is locked (278-279). idr's verdict handler (Run.cpp:248-256) therefore sees worker errors only after the parallel region, in element order.
- **Remarks are not thread-safe.** `RemarkEngine::report` and `reportImpl` take no lock (M/lib/IR/Remarks.cpp:255-269), and the `Final` policy writes an unguarded `DenseSet` (M/include/mlir/IR/Remarks.h:679-682). Emit remarks only from the pass thread. idr's fixpoint remark already does, from the module-level `runAfterPass` (Simplify.cpp:365-368).
- **`TimeTraceProfiler`** keeps one `thread_local` instance per thread (L/lib/Support/TimeProfiler.cpp:56-57). Each worker must call `timeTraceProfilerInitialize` and then `timeTraceProfilerFinishThread` (393-423). Neither MLIR's thread pool nor LLVM's calls these; only LTO.cpp does. idr's profile instrumentation handles it per thread (idr/lib/Support/Profile.cpp:12-24, 107-153), and parallel codegen tasks would need the same.
- **MLIR timers** may be nested from other threads (M/include/mlir/Support/Timing.h:226-227).

## 8. Custom mechanism → upstream replacement → remaining gap

| idris-mlir mechanism | Upstream that replaces or subsumes it | Gap that remains |
|---|---|---|
| Simplify loop: composite, removal resume, budget (Simplify.cpp:122-211) | `CompositeFixedPointPass` (M/lib/Transforms/CompositePass.cpp:69-99) is already used | The only "changed" signal is a SHA1 over the whole module every round (M/lib/IR/OperationSupport.cpp:986ff). A cheaper bit, "some pass did not preserve all", would need every pass to mark unchanged runs; only CSE does. |
| SimplifyInstrumentation statistics (Simplify.cpp:244-377) | PassStatistics | Stats from dynamic pipelines are never printed (PassStatistics.cpp:62-136). Upstream patch: count dynamic pipelines. |
| RoundFacts before each nest (RoundFacts.cpp) | `getCachedParentAnalysis` | The adaptor preserves nothing (Pass.cpp:619, 1183-1186). Upstream patch: the adaptor intersects its nested passes' preserved sets. That removes the re-runs. |
| LoopBreakers and the References graph (LoopBreakers.cpp:80-142) | `CallGraph` + `scc_iterator` | No reference edges (CallGraph.cpp:74-97). Upstream patch: edges from symbol uses of callables, like LazyCallGraph's Ref edges. The SCC code is already LLVM's. |
| InlineDecisions (Analysis/Inline.cpp) | Inliner profitability callback, already used | The callback gets no caller context or cost API (Inliner.h:120-125). The stock ratio walks regions per call. The rule itself stays ours. |
| `marks` + runner + InlineCleanup seeds (Inline.cpp:55-157, 230-278) | `defaultPipeline`, `applyOpPatternsGreedily` | The inliner re-optimizes every SCC node on every iteration (Inliner.cpp:493-526). Upstream patch: a config option to optimize only nodes inlined into. That deletes `marks` and the runner. The seed attribute could become a rewriter listener. |
| Prepare/inline repeat cycle, cycle guard (Inline.cpp:175-312) | none | The inliner never updates CallGraph or SCCs and never sees closures, so idr must rebuild the graph each cycle. |
| Contify (Contify.cpp:59-116) | `inlineCall` (used at 105) | The inliner refuses A→B→A even when inlining in place, which copies nothing and cannot unroll (Inliner.cpp:729-734 against 661-668). Upstream patch: allow it when the callee has one use and is discardable. That deletes the pass. |
| idr-specialize generations and keys (Specialize.cpp:44-80) | `parallelFor`, SymbolTable; LLVM's FunctionSpecialization handles constants only | Specializing on static structure, raising, and binding times have no upstream analogue. |
| idr-redirect (RedirectPass.cpp) | nested function pass, greedy driver | none beyond the RoundFacts gap |
| idr-deduplicate (Deduplicate.cpp:3-29) | `duplicate-function-elimination` (M/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:23-48); LLVM MergeFunctions, already on (Optimize.cpp) | The upstream pass handles `func::FuncOp` only and has no hook for facts that must match. Upstream patch: generalize it to `FunctionOpInterface`. |
| Defunctionalize (Defunctionalize/Pass.cpp:3-15) | dialect conversion, already used | none |
| SCCP on the module, int-range per function | upstream as is | Closure-named functions are pessimized (DeadCodeAnalysis.cpp:226-236). A summary driver would close this. |
| RDV once per fixpoint | upstream | Serial whole-module solve; no per-SCC mode. |
| Driver: one module → one O3 → one object (Run.cpp:147-202) | `SplitModule` + per-context codegen (LTOBackend.cpp:517-570), or `lto::LTO` with a parallelism level (LTO.h:412-414) | The ~50-line split-codegen helper must be re-hosted, since ParallelCG.h is gone. Needs a fixed N, hidden visibility on externalized symbols, and the inline-asm check. |
| MLIR-level partitioning for lowering and translation | `pm.nest<ModuleOp>`, `translateModuleToLLVMIR(Operation*)` | No splitter or declaration cloner exists. Concurrent translation is unverified. |

**The four upstream changes with the most leverage:**
1. the adaptor's preserved-set intersection;
2. the inliner's dirty-node option;
3. in-place inlining through A→B→A;
4. reference edges in `CallGraph`.

Together they would delete RoundFacts' repetition, the inline runner and marks, Contify, and most of the custom graph code. None of them is a bug fix, so under AGENTS.md they would land as `PINS.md` deviations with an upstreaming plan.
