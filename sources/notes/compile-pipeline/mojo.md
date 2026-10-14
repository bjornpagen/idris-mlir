# The Mojo compiler (modular/modular at 9211931)

Research report of 2026-10-14 for the pipeline cutover proposal, written by a research agent from read-only reading, kept verbatim. Paths are as the report gives them: `M/` and `L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`, Modular paths are relative to `~/Documents/modular` at 9211931, MLton paths are under `code/mlton/` here or the fetch named in it. Claims marked recalled or inferred are not read from source.

---

I read everything and changed nothing. I ran no builds and nothing inside the Modular tree. Modular paths below are relative to `~/Documents/modular`, read at revision **9211931**; proposals 0001 and 0004 cite 4b0d20f, so their line references need re-checking against this revision.

The short version:
- **The design to take** is a dataflow-ordered, bottom-up ready set over the call graph. Each function runs its cleanup pipeline once, after its callees are finished, so the result doesn't depend on how threads are scheduled.
- **What not to take**: their concurrency runtime (AsyncRT), their canonicalizer settings (idris-mlir already has the same ones), and their machine-code linker (it needs an LLVM patch).

## 1. The pipeline end to end

Passes are assembled in `Mojo/lib/Compiler/Pipeline/Pipeline.cpp` and driven by `Mojo/lib/Compiler/KGENCompiler.cpp`. The default flow (`KGENCompiler.cpp:1086-1092, 1177-1182`) runs these stages in order:

1. **Generate library** (`Pipeline.cpp:55-115`).
   - Module passes: LowerSemanticCF, CheckLifetimes, LowerLIT, RemoveUnusedParams, EliminateDeadSymbols, InlineParametric, ApplyInliner.
   - Nested per parametric function (`addNestedPass<GeneratorOp>`): SROA, Mem2Reg, SCCP, Canonicalizer.
   - Before instantiation they inline only "nodebug" functions, because more "increases pressure on the elaborator and reduces cache granularity" (`:80-91`).
2. **Elaborate** (`:117-158`): OutlineClosures, CSE (nested), LiftAndFoldApply, ReorderParamOps, then ElaborateGenerators, which instantiates the generics as a module pass.
3. **First optimisation** (`:181-254`).
   - EliminateDuplicateFunctions, then dead-symbol removal, ResolveCompilerPromises, calling-convention lowering, InferFunctionAttrs.
   - **AutomaticInline**, a module pass with an inner per-function pipeline (`:206-231`).
   - Then nested FuncOp passes: SROA, Mem2Reg, Canonicalizer, RaiseForLoops, LoopUnrolling, SCCP, CSE.
4. **Late optimisation** (`:256-286`): ArgPromotion, nested loop and cleanup passes, then LowerClosures, LowerAsyncFunctions and DeadArgumentElimination as module passes.
5. **Lowering to the LLVM dialect** (`ObjectCompiler/KGENToLLVMPipeline.cpp:24-55`) is a single PassManager over the whole module, with nested `LLVMFuncOp` passes. It is followed by `translateModuleToLLVMIR` (`ObjectCompiler.cpp:815-856`) and bitcode linking (`:1047-1051`).

**How it runs in parallel**
- AsyncRT's CPUDevice is installed as the MLIRContext's thread pool through an `llvm::ThreadPoolInterface` adapter (`AsyncRT/lib/CompilerSupport/Context.cpp:33-43`, `AsyncRT/include/AsyncRT/CompilerSupport/LLVMThreadPool.h`). Every nested pass manager and every `mlir::parallelForEach` therefore runs on one shared work queue.
- Some module passes are parallel internally:
  - call-graph construction (`TransformUtils/CallGraphUtils.h:194-198`);
  - AutomaticInline and EliminateDuplicateFunctions, both as ready sets;
  - the SCC-graph passes InferFunctionAttrs, ArgPromotion, IPDF and ResolveCompilerPromises (`TransformUtils/SCCUtils.h`);
  - DeadArgumentElimination (`Transforms/DeadArgumentElimination.cpp:670-676`);
  - the elaborator's expansion graph.
- The offload loop over targets is serial, because LLVM options are global state (`KGENCompiler.cpp:626-628`).

**Code generation is split for parallel LLVM**
- The split strategy comes from the backend (`TargetBackend.h:102,172-175`). The host backend uses PerExported, or PerFunction when `enableLLVMPerFunctionSplitting` is set (`Target/Host/HostBackend.h:33-35`). Defaults: per-function splitting off, parallel llc on (`CompilationOptions.h:247-248`).
- `emitArchiveParallelCompilation` (`ObjectCompiler.cpp:858-897`) splits the LLVM module.
  - `splitPerExported` (`LLVMIRUtils.cpp:301-420+`) groups each exported root with its transitive callees, and merges the users of mutable globals into one split.
- Each split becomes an AsyncRT task that runs the LLVM optimisation pipeline in its own context (`ObjectCompiler.cpp:1178-1243`).
- Each optimised split is split again per function for llc (`:540-606`, `splitPerFunction` at `LLVMIRUtils.cpp:569+`). Each part goes through a bitcode round-trip into a fresh LLVMContext with its own TargetMachine (`ObjectCompiler.cpp:377-500`).
- `MCLinker` (`MCLinker.h:26-36`) links the MachineFunctions back into one object.
- The whole `emitArchive` is a cached transform (`ObjectCompiler.cpp:1149-1166`).

## 2. AutomaticInline.cpp in depth

**Graph.** Nodes live in a `MapVector<FuncOp, Node>` in module order (`CallGraphUtils.h:140-142`). Each caller's call-site list is built by one thread walking its body in program order. The `callers` lists are filled in parallel under a mutex, so their order is nondeterministic (`:160-198`). SCCs come from `llvm::scc_iterator` rooted at an external node that points at uncalled or exported functions. Nodes not reached from it are marked unreachable (`AutomaticInline.cpp:417-437`).

**Ready set (fork-join).** Each node owns a "done inlining" future (`:106-112, 181`). `inlineNode` (`:439-491`) works like this:
1. It collects the futures of each distinct callee that can be inlined, i.e. one not in the caller's SCC and reachable (`:341-354, 443-450`).
2. With no such callee, it queues `completeFunctionProcessing` straight away (`:452-457`).
3. Otherwise it attaches a continuation that fires when every listed callee is done (`:460-490`). The continuation:
   - walks the call sites in program order;
   - applies the heuristic to the callee in its final form;
   - copies the callee body in with `inlineRegion` (`InliningUtils.cpp:43-123`);
   - then runs `completeFunctionProcessing` once.

`completeFunctionProcessing` (`:380-410`) runs the inner pipeline on that one function, optionally re-verifies its debug info, and marks the node done. A counter of work items releases the main thread (`:412-415, 493-501`). Functions in the same SCC never wait on each other, so cycles cannot deadlock.

**Heuristic.**
- `always_inline` callees are always inlined; cycles among them are a compile error (`:289-339, 663-669`).
- Otherwise the callee must be marked Automatic and outside the caller's SCC (`:356-374`), and its function attributes must match the caller's, ignoring the kernel id (`:52-67, 346-349`).
- The only size rule: callee op count (debug-info ops excluded, `InliningUtils.cpp:324-334`) below **10, 20 or 50** at O1, O2, O3, and 0 at O0 (`:625-641`).
- There is no caller budget, no factor for the number of calls, and no growth accounting.
- The size is computed lazily, after the callee's own pipeline has run (`:161-166`), so the decision weighs the callee's final size.

**Inner pipeline**, once per function (`Pipeline.cpp:206-222`): SimplifyCF, SROA, Mem2Reg, Canonicalizer, CSE, HoistTrivialInvariants, Canonicalizer, SimplifyCF, SROA, Mem2Reg, StackReuse, CSE, Canonicalizer. That is **13 passes**; 0004 says twelve. `PerThreadPassManagers` keeps one PassManager per OS thread, with the verifier off (`InliningUtils.cpp:285-322`).

**Determinism comes from the dataflow order**, not from any scheduler rule:
- Each body is a function of its own body and its callees' final bodies.
- A callee is only read after it is marked done (`:408`).
- Callees are inlined in call-site order.
- The lazy size counter can race, but every racer computes the same value (`:192`).
- Dead functions are erased afterwards, serially, in module order (`:705-708`).
- Deferred debug-info updates run in a fork-join where each task touches only its own function (`:693-703`).

**Why it never repeats cleanup:**
- Every function's pipeline runs exactly once.
- A callee is copied in already cleaned.
- There is no iteration, no change detection and no module-wide fixed point.

The catch for idris-mlir: calls that the cleanup only exposes afterwards are not inlined in this pass. Mojo can afford that because it lowers closures later (`:281`). Idris cannot.

## 3. The canonicalizer

Mojo's canonicalizer (`Transforms/Canonicalizer.cpp:476-523`) is a greedy rewrite with all registered patterns plus 7 KGEN patterns, and with **region simplification disabled** (`:496-502`). They give two reasons:
- "KGEN IR only has single-block regions" (`include/Mojo/KGENPasses.td:35-38`). Their structured, label-based control flow has no CFG for the simplifier to clean.
- "FIXME(#25742): The MLIR region simplifier has exponential behaviour" (`KGENToLLVMPipeline.cpp:43-47`), which also applies to their upstream canonicalizer run on the LLVM dialect.

How it differs from upstream's:
- The traversal is the config's default, bottom-up; idris-mlir uses top-down.
- There are no options for disabling patterns or testing convergence.
- Control-flow cleanup is a separate single-walk pass, SimplifyCF (`Transforms/SimplifyCF.cpp:38-120`).

What it costs is plain greedy pattern work. The upstream driver still erases unreachable blocks on every iteration even when region simplification is off (pinned `GreedyPatternRewriteDriver.cpp:~895`).

idris-mlir **already has this configuration** (`foreign/idr/include/idr/Transforms/Canonicalize.h:34-38`). The only thing that brings region simplification back is `simplifyRegions` inside `InlineCleanup` (`Inline/Inline.cpp:153`). There is nothing to port here. The lesson is about *where* the canonicalizer runs, not its settings.

## 4. Elaboration (instantiating generics) and caching

**Instantiation.** The `ExpansionGraph` maps (parameter values, generator) to a node (`Elaborator/Elaborator.h:41-86`). Parameter values are uniqued MLIR attributes, so the key is structural.
- `getOrCreateNode` (`Elaborator.cpp:1675-1693`) creates a node under a lock.
- A caller registers as a waiter on its callee node and is resumed once that node is done (`:1746-1756`). It is a demand-driven ready set.
- Names derive from content: `mangleParameterValues(gen, params)` (`IREvaluatorContext.cpp:108-126`).
- Order is restored at the join: instantiations are grouped by generator in module order, sorted by printed parameters, and deferred symbols are sorted by name (`Elaborator.cpp:2944-2989`).

**Bounding growth.** The only bound is `maxDepth`, which defaults to unlimited (`KGENPasses.td:500-502`; error at `Elaborator.cpp:719-726`). Duplicates are removed after elaboration by EliminateDuplicateFunctions (`Transforms/EliminateDuplicateFunctions.cpp`):
- It hashes and compares bodies with `OperationEquivalence`, ignoring operands (`:31-80`).
- It works bottom-up over a ready set, rewriting a caller's call sites to its callees' representatives before inserting the caller itself (`:188-225`).
- It then picks the lexicographically smallest member of each class, so the result does not depend on which thread inserted first (`:227-254`).
- Merging is therefore transitive in a single pass.

**Caches.** Compile-time evaluation results are cached per region, thread-locally plus globally (`InterpreterCache.h:24-90`; `Elaborator.cpp:853-881`). `Cache/` is a content-addressed blob store with a chain of delegate backends, keyed by a 128-bit xxhash (`Cache/docs/README.md`).
- `cachedTransform` (`Cache/include/Cache/CachedTransform.h:138-246`; `Cache/lib/CachedTransform.cpp:206-358`) keys on the textual pipeline plus the module's bytecode with locations stripped "to ensure determinism across different builds" (`:73-98`).
- It stores diagnostics plus output bytecode.
- It is **whole-module only** (call sites: `KGENCompiler.cpp:1181, 1225, 1285`; `ObjectCompiler.cpp:1163, 1686`).

There is **nothing like per-function content-keyed deltas**. The nearest equivalent is keying instantiation nodes by content.

## 5. Concurrency infrastructure and determinism

**AsyncRT** is about 16k lines.
- The work queue has local, affinity, lock-free global and overflow queues (`AsyncRT/docs/WorkQueue.md:74-99`).
- Tasks must never block, and `await` lends the waiting thread to the queue (`:140-152`).
- Futures with continuations: `AsyncValue.h`, `Algorithms.h`.
- `ForkJoin` (`Runtime/ForkJoin.h:22-66`) is a counter plus a completion future.

Their determinism rules:
1. Dataflow order: a unit reads only inputs that are already final.
2. A canonical sort where parallel work joins.
3. Names derived from content.
4. Lexicographically smallest representatives.
5. Erasure deferred and done serially.
6. Node maps kept in a MapVector.

**Remaining hazards in their code:**
- The parallel-built `callers` lists. SCCUtils' worklist inside a multi-node SCC visits callers in that order (`SCCUtils.h:83-95`), which is only safe for analyses that converge to a unique fixed point.
- Codegen dedup across splits keeps whichever split gets there first (`ObjectCompiler.cpp:1209-1219`), so which split owns a duplicated function depends on timing.

## 6. Licensing for a port

- **All headers are Apache 2.0 with LLVM Exceptions.** Every source file I checked carries the header (example: `AutomaticInline.cpp:1-12`): Mojo/lib 370/370, Mojo/include 177/177, Support 359/359, AsyncRT 64/64, Cache 11/11. The root `LICENSE` is the same Apache-2.0-with-LLVM-exception text, plus LLVM's third-party paragraph.
- **There is no root NOTICE file**, so §4(d) brings nothing along.
- **`Licenses/` does not apply to the source.** `Licenses/LICENSE` is the *MAX Community License* for shipped products (`Licenses/README.md`). `Licenses/Third-Party-Notices` covers product binaries (LLVM, curl, zlib, zstd and others). None of it travels with these source files.
- **xxhash.** `Support/HashUtils` links an external xxhash library (BSD-2), which `Cache` uses. Replace it with LLVM's built-in `llvm/Support/xxhash.h`.
- **The open-source export is incomplete.** `Support/max_license/Tracy/*` and `Support/internal/*` are not in the export (`Support/BUILD.bazel:614-630`), yet AsyncRT includes `Support/max_license/Tracy/Tracy.h`. AsyncRT will not compile from this tree as it stands.
- **LLVM version.** Modular builds against LLVM commit `8d4fc8f1` with its own patches (`bazel/public-patches/llvm_source.bzl:7,13-53`). That commit is not in idris-mlir's checkout, so I couldn't measure the API distance; both trees use the new `Op::create(b, …)` builders.
- **The machine-code linker needs non-upstream LLVM changes.** MCLinker depends on `llvm-machinefunction-sti-ref-to-ptr.patch` and on reaching into LLVM's private members (`LLVMAccessorHelper.cpp:41-69,150`). That is incompatible with AGENTS.md's upstream rule.
- **What Apache §4 requires of us:**
  - ship the licence texts (already in `LICENSES/`);
  - keep Modular's header verbatim;
  - add a prominent change note to each modified file;
  - the patent grant travels with the code.

  The LLVM exception waives §4(a), (b) and (d) for portions embedded in compiled objects. idris-mlir's protocol already covers all of this (`proposals/0001-licensing.md` §1, §3, §4): an SPDX line, the header kept, a changes line naming 9211931, and a PINS.md entry.
- **`AI_TOOL_POLICY.md` only matters for sending work back to Modular** (it asks for an `Assisted-by:` trailer and a human in the loop). It doesn't restrict porting.

## 7. Ranked list of what to port or rebuild

1. **SCC ready-set scheduler** (`SCCUtils.h:60-170`, 191 lines, over `CallGraphUtils.h`, 255 lines).
   - Its parts: atomic counters on each SCC (`:116-118`), a worklist inside each SCC, and bottom-up rewrites.
   - **Rebuild it on the same design** on top of idris-mlir's deterministic `idr/Support/Scc.h`, using MLIR's thread pool with `llvm::ThreadPoolTaskGroup`. `wait(group)` already lends the waiting worker (pinned `ThreadPool.h:68-72`). Estimate 150-250 lines.
   - **Replaces** the rounds and their instrumentation in `Simplify.cpp` (383), `Round.cpp` (79), `Scc.cpp` (112), `RoundFacts.cpp` (48), `Trace.cpp` (49), and every module fingerprint.
   - Leaving out loop-breaker edges (which `Scc.h` already does) makes the ready set acyclic apart from self-loops.
   - Don't port CallGraphUtils itself: its parallel build makes caller order nondeterministic.
2. **Per-function inline-then-pipeline-once driver** (`AutomaticInline.cpp:380-501`; about 350 of its 715 lines carry over).
   - **Replaces** `Inline/Inline.cpp` (324): InlineCleanup, the seed marks, the cycle guard, and the use of upstream's Inliner.
   - **Changes needed:**
     - Graph edges must include closure-label references.
     - After the inner pipeline, add a local loop that inlines calls exposed by cleanup into already-final callees, bounded by a budget.
     - Use upstream `mlir::inlineCall`.
     - Run the inner pipeline through `Pass::runPipeline` from a pool of per-thread `OpPassManager` copies (upstream's pattern, pinned `Inliner.cpp:526-567`). This keeps the verifier and Tracy instrumentation that `PerThreadPassManagers` turns off.
   - **Keep idris-mlir's richer decision rule** (`Analysis/Inline.cpp:23-25,41-53`), but evaluate it against the callee's final size the way Mojo does, and add a budget for the caller.
   - The Mojo "heuristic shape" in 0004 §3 is about *when* the decision is taken, not its rule: Mojo's rule has no budget at all.
3. **Specialisation as demand-driven nodes in the same ready set** (rebuilt, not ported: Elaborator `:1675-1693, 1746-1756, 2944-2989`).
   - **Replaces** `idr-specialize`'s generation loop and RedirectPass.
   - **Required fix:** clone names `<owner>.spec<n>` (`Specialize/Clones.cpp:20`) depend on order. Under parallel execution they must come from the key, or be numbered at a sorted join.
   - Keep `kClonesPerOwner`; Mojo has no comparable bound by default.
4. **EliminateDuplicateFunctions** (301 lines; port nearly all of it).
   - **Replaces** `idr-deduplicate`'s "left for a later run" limitation (`Deduplicate/Deduplicate.cpp:20`) with transitive merging in one pass.
   - Keep idris-mlir's rules for which uses may be renamed, and its comparison of facts.
5. **Parallel codegen baseline** (rebuilt).
   - Design from `ObjectCompiler.cpp:540-606, 858-897, 1178-1243`, implemented with upstream `llvm::SplitModule` (pinned `SplitModule.h:40-42`) and the pattern of LLVM's LTO `splitCodeGen` (`LTOBackend.cpp:517-557`): bitcode round-trip, a fresh context and TargetMachine per partition, a **fixed** partition count so output is byte-identical at any thread count, and N objects handed to lld.
   - About 150 lines across `lib/Driver/Artifacts.cpp` and `Target/Optimize.cpp`.
   - Port `splitPerExported` (about 300 lines) only if per-partition optimisation is wanted. Never port MCLinker or `LLVMAccessorHelper`.
6. **Bottom-up SCC summaries** (the pattern of IPDF, InferFunctionAttrs and ArgPromotion on top of SCCGraph). This is the design for 0004's interprocedural half of SCCP and for effects, as summaries computed callee-first. DeadArgumentElimination (695 lines) is a reference for a parallel alternative to remove-dead-values, but trying the upstream fix comes first.
7. **Not worth porting:**
   - AsyncRT: 16,114 lines, missing the Tracy headers, and MLIR's thread pool is enough.
   - `PerThreadPassManagers`: upstream has an equivalent.
   - The Canonicalizer: the configuration is already in place.
   - `Cache/` (~1,000 lines including the blob cache): only relevant for 0006 shard memoisation later, and a synchronous rebuild on LLVM's xxhash would be about 200 lines.

**Candidates to push upstream:**
- A DAG-parallel SCC traversal mode for MLIR's Inliner, which today parallelises only inside one SCC.
- A reduced reproducer and fix for the exponential region simplifier (Mojo's FIXME #25742).
