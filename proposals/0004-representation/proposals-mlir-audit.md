<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Proposals 0006 to 0020 against MLIR's grain

**Status:** an audit, 2026-10-17, at the owner's request: "make sure we
re-evaluate all our other proposals to be mlir friendly too ... and make
sure our representation first refactor is mlir aware". It changes no
proposal and no source. A proposal takes a finding into its own text when
its stage starts; until then this file holds it.

**Ground.** Every upstream mechanism named here was *read* in the pinned
tree. `M/` is `.toolchain/llvm-project/mlir` at llvm main 7208ba24, and
line numbers are that commit's. Paths under `foreign/idr/` are written
from there. A claim not checked is marked *conjecture*.

**What was asked of each proposal:**
- one op per semantics, or an op whose meaning a flag switches;
- shared shape as an interface;
- effects, constraints, types and folds declared in ODS;
- value and memory at separate levels, lowered progressively;
- upstream's machinery where it fits: bufferization,
  `DestinationStyleOpInterface`, `TilingInterface`, `TypeConverter` and
  dialect conversion, the dataflow framework, the analysis manager, pass
  options and instrumentation, `SymbolTable`, properties, `ub`;
- upstream dialects (scf, cf, arith, memref, linalg, tensor, vector,
  llvm) reused where they fit, never mirrored.

**Verdicts.** *Maps onto MLIR*: the design uses upstream's mechanism
wherever one exists, or has no MLIR surface. *Mostly*: it does, except in
the places listed, each with its upstream-shaped form. *Fights it*: its
core runs against upstream's mechanisms. No proposal here fights MLIR
outright; six are *mostly*, ten *map*.

**The representation wave.** Where a finding meets a lane of 0004's
packet, the section names the finding and the lane. The lane's correction
should take the MLIR form given here.

| Proposal | Verdict | The change that buys most |
|---|---|---|
| 0006 toolchain bump | maps | the survey retires our gap fills against main |
| 0007 qualification | maps | the structured refusal as a metadata attribute and a note |
| 0008 shards | mostly | a `DeviceMappingAttrInterface` mapping chooses which `scf.forall` forks |
| 0009 sharded compiler | mostly | whole-program facts as managed analyses; lazy bytecode for workers |
| 0010 typed APL | mostly | the generating ops destination-style and tileable |
| 0011 array interpreter | maps | none needed; §13 Q2's default has an MLIR reason |
| 0012 data-oriented frontend | maps | attributes and properties in bytecode as data, not text |
| 0013 flattened data | mostly | packed buffers on memref; D10 as a pass over a cached analysis |
| 0014 typechecker | maps | none (no MLIR surface) |
| 0015 self-host features | maps | the `Double` literal match as `arith.cmpf` |
| 0016 relational core | maps | a rule for D3's new ops |
| 0021 Rust interop | mostly | a symbol per binding; the run-time checks as guard ops |
| 0017 licensing | maps | none (no MLIR surface) |
| 0018 Apple DMP | maps | D3 as a schedule step at the lowered stage, no `idr.prefetch` |
| 0019 Fin words | mostly | signedness as the op, not a flag |
| 0020 niche sums | maps | none needed |

## 0006: the toolchain bump

**Verdict: maps onto MLIR.** It moves pins and carried patches. Its rule
(fix in upstream, carry the patch, retire it when the pin passes the fix)
is the MLIR-first rule. Two places to tighten:

1. **Patch 06's conflicting hunk.** The proposal offers two ways: drop the
   hunk for main's #208881 (0edf6243), or route main's loop through the
   patch's `replaceUsesWithPoison`.
   - *Upstream-shaped:* drop the hunk. Main's fix is then the one copy of
     the rule, as AGENTS.md prefers ("upstream's own fix, backported").
     06 keeps only what main lacks.
   - *Buys:* no local variant of a pass upstream maintains; a smaller PR
     for 06.
2. **No retirement check for our own gap fills.** The survey checks
   patches and headers. It never asks whether main closed a gap that an
   op or a pass of ours fills.
   - *Upstream-shaped:* each bump checks 0010 §19's list against main and
     deletes what main now covers, in the same commit, as 01's retirement
     is done. The list is:
     - `transform.idr.vectorize_lanes`, which exists because a transform
       param admits no arithmetic. At the pin, `M/include/mlir/Dialect/
       Transform/IR/TransformOps.td` has `ParamConstantOp` (:1121) and
       `MatchParamCmpIOp` (:964), and no arithmetic (*read*);
     - `idr.tie_shape`;
     - the `memref.get_global` lowering;
     - patch 24 (One-Shot on `FunctionOpInterface`) and U2 (the sparse
       passes on it).
   - *Buys:* our C++ shrinks at each bump, not only when someone notices.

## 0007: the qualification (G1)

**Verdict: maps onto MLIR.** G1 runs suites. Two of its items already
have an MLIR home.

1. **D17, the structured refusal.** Its four fields are what was found,
   where, why, and what form compiles, rendered in one place. The rule
   already rides in the diagnostic: `idr::refuse` puts a `RuleAttr` in
   `Diagnostic::getMetadata()` (`lib/IR/Attrs.cpp:37-44`).
   - *Upstream-shaped:*
     - "where" is the diagnostic's `Location`, as now;
     - "what was found" is an attribute in the same metadata, never text:
       a `TypeAttr`, a `FlatSymbolRefAttr` or an `#idr.instance`. One
       AttrDef, `#idr.refusal<rule, found>`, replaces the bare `RuleAttr`;
     - "what form compiles" is a note at the location where that form
       goes, `Diagnostic::attachNote` (`M/include/mlir/IR/Diagnostics.h:272`);
     - "why" is the rule's phrase, generated from `Idr_Rule` (IdrBase.td)
       for C++ and Idris alike;
     - the one renderer is the driver's diagnostic handler, reading the
       metadata.
   - The frontend's refusals happen in Idris, before any MLIR exists.
     They use the same generated `Rule` and the same fields: 0004's
     idris-frontend-1 (L21) makes a refusal data from the start.
   - *Buys:* no refusal site formats prose. The reject tests compare the
     rendering of data.
2. **"The analyses, once each."** G1 reads it off `-mlir-timing`'s `(A)`
   rows. Only an analysis the analysis manager computes has a row.
   idr-rc builds `Reuses`, `Borrows` and `Exclusivity` by direct
   construction (`lib/Transforms/Ownership/Rc.cpp:73-110`), so they can be
   computed twice and never show.
   - *Upstream-shaped:* every whole-program fact is a managed analysis
     (0013's second item below). Then the record G1 reads covers them.
   - *Buys:* the check means what it says.

## 0008: shards

**Verdict: mostly maps onto MLIR.** Most of it is the grain:
- the fork is an isolated region whose operands are the message;
- the send check is a method of `ValueFactsTypeInterface`;
- the grid is upstream's `shard.grid` and `shard.process_linear_index`
  (`M/include/mlir/Dialect/Shard/IR/ShardOps.td:31, 140`);
- per-shard constant tables are `llvm.mlir.global` with `tls_mode`
  (`M/include/mlir/Dialect/LLVMIR/LLVMOps.td:1429`);
- frames come from the LLVM dialect's coroutine intrinsics
  (`M/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:938-1050`).

Three places do not:

1. **"The one lowering of `scf.forall`" (§8).** It collides with 0010
   §7.1's tile-and-fuse. `transform.structured.tile_using_forall`
   (`M/include/mlir/Dialect/Linalg/TransformOps/LinalgTransformOps.td:2402`,
   `TileUsingForallOp`) makes the `scf.forall` that
   `fuse_into_containing_op` (`:533`) fuses producers into, for tiles
   inside one core. If every forall lowers to a fork per shard, L1 tiles
   fork across shards.
   - *Upstream-shaped:* a forall's `mapping` says what its iterations are
     spread over. It is an attribute implementing
     `DeviceMappingAttrInterface`
     (`M/include/mlir/Dialect/SCF/IR/DeviceMappingInterface.td:22`), as
     GPU's `#gpu.block<x>` is.
     - A `#idr.shard` mapping is written by the schedule when it tiles
       for cores (`tile_using_forall ... mapping = [#idr.shard]`).
     - Only a forall with that mapping lowers to forks.
     - Every other forall lowers by upstream's `scf-forall-to-for`
       (`M/include/mlir/Dialect/SCF/Transforms/Passes.td:116`,
       `SCFForallToForLoop`).
   - *Buys:* the choice is data on the op, not a convention between two
     proposals. "Counts nothing" stays an assertion, made only on a
     forall that has the mapping.
2. **`wait` as a trait and an effect bit (§2).** §2 adds a `Waits`
   `NativeOpTrait`, read by `idr::bodyEffect`, and a fourth `Idr_Effect`
   bit (IdrAttrs.td:212). Each of the other three bits has an MLIR
   resource (`Idr_IOResource`, `Idr_CrashResource`,
   `Idr_DivergenceResource`, IdrInterfaces.td:68-72), declared in each
   op's ODS effects.
   - *Upstream-shaped:* an `Idr_WaitResource` beside them. Each waiting
     op declares `MemoryEffects<[MemWrite<Idr_WaitResource>]>`: a wait lets
     other tasks run, so nothing may move across it. The summary's `wait`
     bit is derived from that resource by the one table that maps bits to
     resources (0004's ir-verify-6 and analysis-3, lane L03).
   - *Buys:* no second classifier and no trait. Every upstream pass that
     reads effects (CSE, LICM, the greedy driver's dead-op erasure,
     `remove-dead-values`) leaves a wait in place without being told.
3. **`idr.wait`, a terminator with two successors (§2).** It forwards the
   answer and the next world to `resume`.
   - *Upstream-shaped:* `BranchOpInterface`
     (`M/include/mlir/Interfaces/ControlFlowInterfaces.td:23`) with
     `getSuccessorOperands`. Our flow interface already reads forwarding
     from it (`idr::forwardedValues`, IdrFlow.td), and so do upstream's
     liveness and `remove-dead-values`.
   - *Buys:* `idr.wait` declares no flow edge of its own, and no CFG
     reader treats it as unknown.

**Kept, the reason checked.** The frames lower straight to
`llvm.intr.coro.*`, not through upstream's async coroutine ops
(`M/include/mlir/Dialect/Async/IR/AsyncOps.td:454-537`). Their
`async.coro.begin` lowering allocates the frame with `aligned_alloc`
(`M/lib/Conversion/AsyncToLLVM/AsyncToLLVM.cpp:364-410`,
`CoroBeginOpConversion`), and the patterns are private to
`convert-async-to-llvm`. So they cannot put the frame behind our header or
on the runtime's allocator. Rejecting `async.execute` and
`async-parallel-for` stands: both bring `mlirAsyncRuntime`.

## 0009: a sharded whole-program compiler

**Verdict: mostly maps onto MLIR.** What is built uses MLIR's threading,
pass statistics and bytecode. Four places:

1. **Facts handed to passes by constructor (§3.1, S3 to S5).** idr-rc
   builds its whole-program facts directly and hands them to nested
   passes as constructor arguments: `createRcPlace(reuses, callees)` and
   `createRcCommit(*solved, symbols)` (`Rc.cpp:87, 110`). idr-optimize
   binds its callee table when the pipeline is built (0004's
   transforms-b-10, lane L13). §3.1 keeps summaries as "plain C++ data".
   - *Upstream-shaped:* a whole-program fact is a program analysis in the
     analysis manager, a class built from `(Operation *, AnalysisManager &)`.
     The function passes nested under the program read it with
     `getCachedParentAnalysis` (`M/include/mlir/Pass/Pass.h:265-272`). A
     pass that keeps it says so with `markAnalysesPreserved`. Inside a
     pass, `runPipeline` on the program reuses the pass's own manager
     (`M/lib/Pass/Pass.cpp:591`), so idr-rc's nested runs see the cache.
     S3 then parallelizes an analysis's construction, not a side table.
   - *Buys:* every step is a registered pass that `idris-mlir-opt` runs
     alone; analyses appear in the timing record and in 0007's check;
     "frozen facts read by units" is the manager's cache by construction.
2. **S6's units as bytecode.** S6 plans one bytecode file per unit.
   - *Upstream-shaped:* MLIR's reader loads isolated regions lazily:
     `BytecodeReader(buffer, config, /*lazyLoad=*/true, ...)` and
     `materialize` (`M/include/mlir/Bytecode/BytecodeReader.h:30-62`). An
     `idr.func` is `IsolatedFromAbove`, and the frontend's writer already
     gives each function a section of its own
     (`compiler/src/IdrisMLIR/MLIR/Bytecode.idr`, its header). A worker's
     context reads the one module file and materializes only its unit's
     functions.
   - *Buys:* S6 needs no unit format and no merge. D18's merge stays only
     for the Idris half's parallel writers (S8).
3. **D19's liveness.** The pipeline's liveness is upstream's:
   `remove-dead-values` (`lib/Transforms/Pipeline.cpp:74-76`) over
   `RunLivenessAnalysis`
   (`M/include/mlir/Analysis/DataFlow/LivenessAnalysis.h:102`) on
   `DataFlowSolver`.
   - *Upstream-shaped:* sharding it by §4 is a change to the solver, so it
     is an upstream patch with its written plan under `upstream/`, never a
     liveness of ours beside it.
   - *Buys:* one liveness.
4. **The ready set beside `mlir::Inliner`.** Upstream's inliner walks the
   call graph's SCCs bottom-up and runs a pipeline on each
   (`M/include/mlir/Transforms/Inliner.h:27, 103`,
   `InlinerConfig::setOpPipelines`). That is the ready set's shape, run
   serially. Running independent components in waves is what upstream
   lacks, so the ready set stays.
   - *Upstream-shaped:* record it as a gap with its upstream plan, as 0010
     §19 records its ops, so the bump that brings a parallel SCC walk
     retires it (0006's second item).

## 0010: a typed array language

**Verdict: mostly maps onto MLIR.** Its ruling (one MLIR image per fact,
upstream's wherever one exists) is the grain, and most rows of its §2
point at upstream mechanisms. Four places do not:

1. **The generating ops are neither destination-style nor tileable.**
   - `idr.tabulate` takes sizes and makes its tensors (IdrArrayOps.td:99).
     That is the shape §4.1 rejects `tensor.generate` for: no
     destination, always allocates.
   - `GeneratingOpInterface` (IdrInterfaces.td:123) restates part of
     `TilingInterface`: `getRank` and `getExtent` are the ranges of
     `getIterationDomain` (`M/include/mlir/Interfaces/TilingInterface.td:91`),
     and `getIterations` is `getLoopIteratorTypes` (:80) plus one case.
   - So `idr-structure-loops` must turn each op into `linalg` or a
     hand-built `scf.for` nest (`lib/Transforms/StructureLoops/Nests.cpp`,
     297 lines) before upstream's tiling, fusion or bufferization can
     touch it. And §4.4 plans `idr.scan` and `idr.scatter` as second ops
     beside `scan_last` and `accumulate`.

   *Upstream-shaped*, which stage 4 already names as its first try:
   - **`DestinationStyleOpInterface`**
     (`M/include/mlir/Interfaces/DestinationStyleOpInterface.td:14`).
     `tabulate` takes `outs`, a `tensor.empty` of its sizes; a fold or a
     scan takes its inits as `outs`. Bufferization then comes from
     `DstBufferizableOpInterfaceExternalModel`
     (`M/include/mlir/Dialect/Bufferization/IR/DstBufferizableOpInterfaceImpl.h:22`),
     the model linalg uses.
   - **`TilingInterface`**: the iteration domain, the iterator types,
     `getTiledImplementation` (:118) and `generateScalarImplementation`
     (:458).
     - `fuse_into_containing_op` fuses any `TilingInterface` producer
       (`LinalgTransformOps.td:533`), so stage 3's tile-and-fuse works on
       the generating ops themselves, before anything is structured.
     - The tiling model refuses to tile or fuse an op whose region does
       more than compute and crash, read from its
       `RecursiveMemoryEffects`. Effects are final when stage 3 runs.
   - **The ordered form** is the op's `generateScalarImplementation`,
     driven by `scf::lowerToLoopsUsingSCFForOp`
     (`M/include/mlir/Dialect/SCF/Transforms/TileUsingInterface.h:491`).
     It takes only ops with buffer semantics
     (`M/lib/Dialect/SCF/Transforms/TileUsingInterface.cpp:2606-2612`), so
     the structuring moves after bufferization and shrinks to one
     decision there: a pure op over words becomes `linalg.generic` for the
     vectorizer, and every other op becomes its scalar implementation.
   - **The one case DPS cannot meet as written** is a cell whose
     dimensions the cells give, which Nests.cpp makes at the first index
     before the array. The size exists only after one step, so the case
     is the problem's: the first step is peeled, and the destination is a
     `tensor.empty` of that cell's dimensions.

   *Buys:* Nests.cpp's nest builder; the planned `idr.scan` and
   `idr.scatter` second ops (§4.4's open question, answered:
   `accumulate`'s op is the one scatter, with the same three models);
   structuring before fusion; one interface, upstream's, where two are
   declared.
2. **D32's third `Iteration` case.** `Idr_Iteration` is parallel and
   ordered (IdrArrayOps.td:38). D32's default adds "any association".
   - *Upstream-shaped:* that case is upstream's
     `utils::IteratorType::reduction`
     (`M/include/mlir/Dialect/Utils/StructuredOpsUtils.td:15`), and its
     tiling is `PartialReductionOpInterface` (`TilingInterface.td:508`).
     The mapping:
     - parallel is `parallel`;
     - any association is `reduction`, with the partial-reduction model;
     - ordered is `reduction` with no partial-reduction model, which
       upstream tiles only with an in-order `scf.for`.

     Only ordered has no upstream name. The enum keeps it and spells the
     other two as upstream does.
   - *Buys:* §6's iterator is the one place the order fact lives, and
     upstream's tiling reads it unchanged.
3. **The linear wrapper and the buffers retype (§8, stage 2).** Today
   `!idr.lin<tensor<…>>` is no tensor to One-Shot, so `idr-bufferize`
   remakes every data type that holds a tensor and retypes every function
   (`DataRemap` kind `buffers`, D42).
   - *Upstream-shaped:* stage 2's own design. A field of array type is the
     cell's buffer from the frontend on, and `!idr.lin<T>` is tensor-like
     where `T` is, through `TensorLikeType` and `BufferLikeType`
     (`M/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td:18, 41`)
     with submission 27's per-instance hook. Take it as the design now,
     not as a stage-2 decision: every later stage builds on whichever
     bufferization contract holds.
   - *Buys:* the remap pass, `heldType`, the retype loop, and the reason
     the release and link models exist (§8 lists them).
4. **Two counting protocols for one element access (§13).** Value and
   memory are not kept apart for arrays a world orders.
   - A value array's buffer is read and written with upstream's
     `memref.load` and `memref.store`, and idr-rc makes each count
     explicit with `idr.own.adopt` and `idr.own.give`
     (IdrOwnershipOps.td:190, 205).
   - An array a world orders uses `idr.array.get` and `idr.array.set`
     (IdrArrayOps.td:304, 322), whose counts the lowering makes, unseen by
     idr-rc and the owned verifier: `LowerArrayGet` takes a reference,
     `LowerArraySet` releases the old element
     (`lib/Conversion/Arrays.cpp:172-198`).

   *Upstream-shaped:* the world-ordered ops are the value level the
   frontend writes. idr-rc lowers them to the memory level the buffers
   already use: `memref.load` then `idr.dup`, `idr.own.give` then
   `memref.store`. The memref's own effects order the accesses; the
   array ops already declare them on the array and not on the IO
   resource (`Idr_ArrayOp`). *Conjecture:* nothing observable reorders
   once the world token stops threading them, since §13 already rests on
   those effects.

   *Buys:* one counted-element protocol; idr-rc may borrow an element it
   reads instead of always counting it; the lowering's hidden counts go.

**Kept, the reason checked:** `transform.idr.vectorize_lanes` (no param
arithmetic, 0006 above); `idr.tie_shape` (no upstream op ties a
parameter's dimension to a size); `#idr.world` as a memref memory space
(the type the memref passes know).

## 0011: the array interpreter

**Verdict: maps onto MLIR.** It is Idris. What it hands MLIR is ordinary
IR: constants as `#idr.con` and `#idr.closure` in `idr.constant`, a
`ConstantLike` op the dialect materializes, and memo cells.

1. **§13's question 2 has an MLIR reason for its default.** A primitive
   with constant operands is folded on the MLIR side by its op's folder,
   which calls the runtime (`hasFolder` on the `Idr_Runtime` ops,
   `lib/IR/Fold`), and across blocks by upstream's `sccp`
   (`M/include/mlir/Transforms/Passes.td:442`, `SCCPPass`). So a
   normalizer that applies no primitive loses only primitives inside a
   recursion, which no C++ pass may run anyway (0009 D6).
   - *Upstream-shaped:* A3 emits what it stops at as calls whose constant
     arguments are `idr.constant` or `arith.constant` ops, so the folders
     and SCCP compose with it.
   - *Buys:* question 2 closes on its default. The alternative, folding
     through base's primitives, would be a second meaning beside the
     folders.
2. **A5's hooks follow 0010's stage 4.** The kernels hook onto `idr.scan`
   and `idr.scatter` (§6). If 0010 takes its first finding above, they
   hook onto the generating ops and the one scatter op instead. Nothing
   changes here until 0010 decides.

## 0012: a data-oriented frontend

**Verdict: maps onto MLIR.** Its boundary with MLIR is the bytecode the
frontend writes, in upstream's format. The format offers more than the
frontend uses in two places. Both are emission costs O0 decides (D0), and
neither changes a table.

1. **Attributes as text (§4.9).** Every idr attribute (`#idr.con` and its
   runs, `#idr.closure`, `#idr.big`, `#idr.instance`, the keys) goes as its
   assembly, so the driver runs the parser once per distinct constant.
   `IdrBytecode.td` has records for the idr types and the data table
   only: `IdrDialectAttributes`' elements are `[DataTable]`.
   - *Upstream-shaped:* a `DialectAttribute` record per attribute in
     `IdrBytecode.td` (`M/include/mlir/IR/BytecodeBase.td:157`).
     `mlir-tblgen -gen-bytecode` writes the C++ reader from it, and
     idris-mlir-tblgen the frontend's encoder, as for the types. This is
     ODS in the tree, not the upstream patch §4.9 names.
   - *Buys:* no text round trip for constants; a list constant's run is
     read as data.
2. **Properties through the attribute dictionary.** The writer puts each
   op's inherent attributes in one attribute dictionary and leaves the
   properties section empty, so the reader builds and uniques a
   `DictionaryAttr` per op and `setAttrs` splits it (`MLIR/Bytecode.idr`,
   its header).
   - *Upstream-shaped:* each op's properties in the properties section,
     in the encoding ODS generates (`BytecodeOpInterface::readProperties`
     and `writeProperties`,
     `M/include/mlir/Bytecode/BytecodeOpInterface.td:20-38`). The
     frontend's writer is generated from the same ODS.
   - *Buys:* no dictionary per op, and O2's byte-identical rule holds
     against the C++ writer's own form.

## 0013: compiler-chosen flattened layouts

**Verdict: mostly maps onto MLIR.** A layout is a type over one
declaration, columns go through dialect conversion's one-to-N rewrites
(`OneToNOpAdaptor` and `replaceOpWithMultiple`, as
`lib/Conversion/Arrays.cpp` uses them), and the exclusive grade is the
gate. D4's rejection of one allocation for all columns is right: it would
need a bufferization model beside upstream's. Two places do not fit:

1. **The packed buffer's memory level (F1).** The proposal names the type
   and the cursors, not what a cursor lowers to, so idr-lower would grow
   a third hand-made memory path beside cells and arrays.
   - *Upstream-shaped:* `!idr.packed<T>` and its cursor ops are the value
     level. The memory level is upstream's:
     - the buffer is a `memref<?xi8>` in the default memory space,
       counted as one cell as a value array's buffer is (`idr.own.adopt`
       at its allocation);
     - a cursor is an `index`;
     - a field read is `memref.view`
       (`M/include/mlir/Dialect/MemRef/IR/MemRefOps.td:2471`) then
       `memref.load`;
     - growth is `memref.realloc` (`:277`).

     `memref-to-llvm` lowers all of it. The `ptr` dialect
     (`M/include/mlir/Dialect/Ptr/IR/PtrOps.td`: `ptr.load` :207,
     `ptr.ptr_add` :366, `ptr.type_offset` :619; lowered by
     `M/lib/Conversion/PtrToLLVM`) is the alternative if a view per read
     costs. F1 settles which.
   - *Buys:* no cursor lowering of ours; D4's "one count per buffer" is
     the protocol buffers already have.
2. **D10's packing step inside idr-rc.** "A module step between step 4
   ... and step 5" puts a decision in the middle of `Rc.cpp`'s
   `runOnOperation`, reading the `Exclusivity` value step 4 hands to step
   5 by constructor (`Rc.cpp:95-110`).
   - *Upstream-shaped:* `Exclusivity` is a program analysis (0009's first
     item). Step 5, `createRcCommit`, is a function pass nested under the
     program that reads it with `getCachedParentAnalysis`. The packing
     choice is its own pass between the grades and the commit, and keeps
     the analysis. This needs the program between steps 4 and 5 to verify
     at the owned stage; if it does not, making it verify comes first.
   - *Buys:* D10 adds a pass, not a branch in idr-rc. Each step runs alone
     in `idris-mlir-opt`.

## 0014: a type checker for the fork

**Verdict: maps onto MLIR (no MLIR surface).** It is the fork's checker.
It touches MLIR only in what it rejects: the `smt` dialect
(`M/include/mlir/Dialect/SMT/IR/SMT.td`), for D3's reasons (a solver's
answer is no Idris term, and a C++ solver is outside the one foreign
world). Nothing to change.

## 0015: the features self-hosting asked for

**Verdict: maps onto MLIR.** Each feature compiles to ordinary idr data
and calls, and no pass has a case for one (D9). That is the grain. One
place:

1. **D13's match on a `Double` literal.** It needs no new scrutinee kind
   in `idr.match_lit`, which takes `i1`, words, strings, bigs and
   naturals (IdrMatchOps.td:73).
   - *Upstream-shaped:* Idris's `==` on `Double` is C's, which is ordered
     equality, `arith.cmpf oeq`. The frontend emits a chain of
     `arith.cmpf oeq` against each literal, in the alternatives' order,
     each matched as an `i1`.
   - *Buys:* no `f64` case in `match_lit`, and no folder or lowering for
     one. arith's folders do the rest.

## 0016: the relational core

**Verdict: maps onto MLIR.** It is an Idris library. Its MLIR boundary is
`sparse_tensor` for the plans that fit and `linalg` fusion of specialized
pipelines, both upstream's. One rule to write down for D3:

1. **D3's new ops.** "Hash tables, strings, tries, data-dependent control
   become `idr` ops or runtime primitives."
   - *Upstream-shaped:* each is one op per semantics, its effects
     declared in ODS on the structure it touches. A hash table is memory,
     as an `IOArray` is: a handle in `#idr.world`, or a counted cell, with
     `MemRead` and `MemWrite` on it, never on the IO resource. Its guard
     is an `Idr_Guarded` mark, its fold the runtime's. Data-dependent
     control is `scf.while` and `scf.if` over those ops, never an op of
     ours.
   - *Buys:* the dialect grows by data, not by control.

## 0021: Rust as the one foreign world

**Verdict: mostly maps onto MLIR.** The grain holds for the foreign type
(counted, answering `ValueFactsTypeInterface`), the effects (through
`MemoryEffectOpInterface` on the existing resources), the closures
(through the flow interface), and the shims (joined as runtime bitcode).
Two places do not:

1. **The callee as a string and the signature on every call (§9.2).**
   `idr.rust.call "symbol"(...)` holds an inherent string and an inherent
   `function_type`. Every call restates its binding's signature, and no
   `SymbolTable` sees the callee, so SymbolDCE, the call graph and symbol
   verification cannot either.
   - *Upstream-shaped:*
     - one declaration per binding: a new op, `idr.extern @sym : <grades>`,
       holding the binding's effects. It is a `Symbol` with no region,
       which keeps "every `idr.func` has a body";
     - the declaration implements `CallableOpInterface`
       (`M/include/mlir/Interfaces/CallInterfaces.td:173`) without a
       region, so `CallGraph` makes it an external node;
     - `idr.rust.call @sym(...)` implements `CallOpInterface` (:73) and
       `SymbolUserOpInterface`
       (`M/include/mlir/IR/SymbolInterfaces.td:209`), whose
       `verifySymbolUses` checks the operands against the declaration, as
       `idr.call` checks against its callee.
   - *Buys:* the signature, the IO claim and the effects are said once per
     binding; the lowering declares each shim once; an unused binding goes
     by SymbolDCE.
2. **The run-time checks in the lowering (§8.3).** The alias and
   uniqueness tests are emitted by `idr.rust.call`'s lowering "only where
   the grade does not decide them", and `tests-nothing` reads the op's
   operands specially.
   - *Upstream-shaped:* the dialect's guard mechanism: a guard op
     (`GuardOpInterface`, IdrInterfaces.td:106; `Idr_CheckOp`,
     IdrCheckOps.td:71) that the total op names in its ODS
     (`Idr_Guarded`), folded away where the operand shows the condition.
     `idr.check.unique` and `idr.check.distinct` guard `idr.rust.call`'s
     by-value and `&mut` operands. Each folds to its operand where the
     operand's grade is `excl`, and two exclusive operands are distinct
     by their grades. After idr-rc the grades are types, so the folder
     sees what the lowering sees.
   - *Buys:* the lowering emits no test; `tests-nothing` reads guards
     through the interface, as for every other check; a test the folder
     removed is visible in the IR before lowering.

## 0017: licensing

**Verdict: maps onto MLIR (no MLIR surface).** The one piece near MLIR,
idris-mlir-tblgen writing the licence line into the modules it
generates, is generation from one source. Nothing to change.

## 0018: the heap as Apple's DMP reads it

**Verdict: maps onto MLIR.** Most of it is the runtime and LLVM. D3's
placement is the one MLIR question.

1. **Where D3's prefetch lives (§9).** Option (a) adds a pass of ours in
   the arrays stage and an `idr.prefetch` op on a box. The vectorization
   schedule already runs after idr-entry (0010 §7), where a reference is
   a lowered word (`!llvm.ptr`), so the op is not needed.
   - *Upstream-shaped:*
     - a reference is prefetched by `llvm.intr.prefetch`
       (`M/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:163`,
       `LLVM_Prefetch`), and an index gather by `memref.prefetch`
       (`M/include/mlir/Dialect/MemRef/IR/MemRefOps.td:1452`);
     - the distance is a key of the target's DLTI entry, read by
       `transform.dlti.query`
       (`M/include/mlir/Dialect/DLTI/TransformOps/DLTITransformOps.td:18`),
       as `max_vector_op_width` is;
     - "d iterations ahead" is software pipelining. Upstream's
       `scf::pipelineForLoop` takes a schedule hook
       (`PipeliningOption::getScheduleFn`,
       `M/include/mlir/Dialect/SCF/Transforms/Transforms.h:129-197`;
       `transform.loop.pipeline`,
       `M/include/mlir/Dialect/SCF/TransformOps/SCFTransformOps.td:226`)
       that puts an op of iteration i+d into iteration i.

     So D3 is a step of the schedule library: the pipeliner, if its hook
     admits a prefetch stage (*conjecture*, P2 checks), else one transform
     op of ours beside `vectorize_lanes`, naming its gap.
   - *Buys:* no `idr.prefetch` and no pass outside the schedule. The
     distance is one DLTI fact, as 0010 D20 and D29 want.

## 0019: `Fin n` as a machine word

**Verdict: mostly maps onto MLIR.** Option (c) is the grain: builtin
integers, upstream's range analysis and the vectorizers, and no
`!idr.fin<n>` (§6.1). It is right that no upstream op asserts a range to
carry `[0, n)` (*read*: none under `M/include`), and that
`IntegerRangeAnalysis` reads an `i8`'s unsigned range from its width. One
place fights:

1. **Signedness as a flag.** Builtin integers are signless; upstream puts
   the sign in the op (`arith.divsi` and `divui`, `extsi` and `extui`,
   `cmpi slt` and `ult`). F1 makes unsigned words common, and D5 converts
   them with `idr.big.from_int` "unsigned", whose meaning a
   `UnitAttr:$is_signed` switches (IdrBigOps.td:202).
   - The flag is on ten ops: `idr.div` and `idr.mod`
     (IdrScalarOps.td:16-20), `idr.shl` and `idr.shr` (:48-50),
     `idr.to_char` (:75), `idr.int_head` (:113), `idr.io.put_int`
     (IdrIOOps.td:40), `idr.str.show` (IdrStringOps.td:90),
     `idr.str.to_int` (:225) and `idr.big.from_int`.
   - 0004's ir-ops-15 (lane L16) removes the two combinations where the
     flag means nothing. Everywhere else it switches semantics.
   - *Upstream-shaped:* one op per reading.
     - An unsigned quotient or remainder of a guarded divisor is
       `arith.divui` or `arith.remui` after `idr.check.nonzero`; only
       signed Euclidean division and remainder stay ours, with no flag.
     - A natural from a word is `idr.nat.from_int` (unsigned by its
       result), an Integer from a word `idr.big.from_int` (signed).
     - Each other flagged op becomes its two readings. The shifts'
       "defined for every amount" meaning is a few `arith.select`s over
       arith's shifts, which the frontend can write so that arith's
       folders and range analysis see it; whether that beats one op of
       ours is the README's "smaller op set" measurement.
   - *Buys:* `custom<Signedness>` and every folder's flag branch go.
     arith's folders, canonicalizations and range transfer functions serve
     the unsigned words F1 makes. L16 should take this form rather than
     only removing the two combinations.

## 0020: niche layouts of sums

**Verdict: maps onto MLIR.** The dialect does not change: `idr.con`,
`idr.field`, `idr.tag` and `idr.match` stay abstract over the layout.
The layout reaches the lowering through the `TypeConverter`'s one-to-N
conversion (`lib/Conversion/Lower.cpp:91-97`), and the tag's facts reach
LLVM as `range` attributes. That is value and memory kept apart, lowered
progressively. Nothing to change; one note:

1. **Sizes upstream can ask for.** A cell's size and a value's components
   are answered by `Layouts`, an analysis of ours. Upstream asks a type
   for its size through `DataLayoutTypeInterface`
   (`M/include/mlir/Interfaces/DataLayoutInterfaces.td:612`), which
   `DataLayout` and the new `M/include/mlir/ABI/ABITypeMapper.h` read.
   Answering it from `Layouts` would let upstream size an idr type.
   Nothing in N1 to N5 needs that, so it waits for a consumer.

## Ranked: the redesigns that buy the most

1. **0010.** The generating ops destination-style and tileable
   (`DestinationStyleOpInterface`, `TilingInterface`, partial reduction
   where any association is proved), stage 2's tensor-like wrapper as the
   design now, and one counted-element protocol. It deletes the nest
   builder, the planned second scan and scatter ops, the buffers retype,
   and the lowering's hidden counts, and every later array stage builds
   on it.
2. **0008.** A `#idr.shard` forall mapping, `wait` as an effect resource,
   and `idr.wait` as a `BranchOpInterface`. The first is a correctness
   fix: without it, 0010's tile-and-fuse foralls fork across shards.
3. **0013, with 0009's first item.** Whole-program facts as managed
   analyses read through `getCachedParentAnalysis`, so idr-rc's steps and
   D10's choice are passes, and packed buffers on memref. It reaches past
   0013: idr-rc, idr-optimize's callee table (transforms-b-10) and 0007's
   check all take the same mechanism.
4. **0021.** A symbol declaration per binding, and guard ops for the
   run-time checks.
5. **0019.** Signedness as the op, across ten flagged ops; widens 0004's
   ir-ops-15.
6. **0018.** D3 as a schedule step at the lowered stage, with no
   `idr.prefetch`.
7. **0012.** Bytecode records for the attributes, and properties written
   as properties.
8. **0007.** The refusal as one metadata attribute and a note.
9. **0009's rest.** Lazy bytecode for S6, liveness sharded upstream, the
   ready set recorded as a gap.
10. **Small or none:** 0006 (retirement check), 0015 (`arith.cmpf`), 0016
    (a rule for D3), 0011, 0020, 0014, 0017.
