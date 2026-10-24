<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3 fixes: the lanes' handoffs



=== 
L04 recheck 3. HEAD was 4b0d8cd5 at start and at finish. Three of the findings are fixed, eight are left, and none were wrong. Nothing was built or typechecked (D56).

**Fixed**
- **C34, `include/idr/IR/Layout.h:282-284`:** deleted the hand `Layouts::isInvalidated`. `Layouts` reads no other analysis, so MLIR's default invalidation is what it needs. Also dropped the `mlir/Pass/AnalysisManager.h` include it needed; no file that includes `Layout.h` used it.
- **Recursion on a type's nesting, `Families.h:190-213`:** `builds` relates two types, so it cannot be a bit stored when a type is made. It now walks the field pairs with the shared `depthFirst` (`Support/Nest.h`), on a heap stack, and stops descending once a pair builds. The per-pair answer is a new enum `families::RepackStep {BuildsNothing, Builds, ByFields}`. Its function `repackStep` is defined in `lib/IR/Layout/Components.cpp`, next to `layoutMatch`. The recursion is gone and behaviour is unchanged.
- **Stale comment, `Symbols.h:34-39`:** no op format uses `custom<CtorRef>`. The comment now says the match's cases are written with it.

**Left**
- **`eliminates` op ladder, `Symbols.cpp:76-84`:** needs a trait the spec doesn't declare yet. Seam:
  - L03: an `EliminatesOperand` `TraitDef` in `Spec/Core/Interfaces.idr`, and an empty `idr::EliminatesOperand` trait class in `include/idr/IR/Traits.h`.
  - The trait goes on `data.match` (L09, `Spec/Control/Matches.idr`), on `io.put_str` (L13, `Spec/Ops/IO.idr`; `ioOp` currently sets `traits = []`), and on `data.field` (my own spec file, held for the follow-up).
  - The lambda then becomes `user && user->hasTrait<EliminatesOperand>() && user->getOperand(0) == value && (isClosures(value) || isa<StrType>(unrestricted(value.getType())))`.
  - I didn't switch it ahead of the trait: with no op carrying it, raising would silently stop.
- **`foldDialect`, a second fold, `Components.cpp:88-106`:** needs a decision from the coordinator, then a seam.
  - Either L15's `match` (`Support/Match.h`) gains an overload that folds an `mlir::Type` over a closed list of type classes, with the same coverage check and probe. Then `TypeList` and `foldDialect` go.
  - Or the spec declares a type interface, which would split "said once, in one fold" across about 13 units.
  - I recommend the first.
- **D114, checks kept:**
  - The internal errors in `Layouts::sum` and `Layouts::cells` (`Layouts.cpp:186-201`).
  - The memref-without-strides error (`Components.cpp:174-179`).
  - The `llvm_unreachable` at `Layouts.cpp:382`.
- **Spec, for the follow-up sweep:** `sortKind` and `termKind` in `Spec/Families/Terms.idr:53,91` are still unused.
- **Measurement (INT, stage 1):** `shapeBudget = 16` in `Spec/Families/Layout.idr:84`.

**Files for INT:** none added, moved or deleted. Edited: `include/idr/IR/{Layout.h,Symbols.h,Families/Families.h}` and `lib/IR/Layout/Components.cpp`. `Families.h` now includes `idr/Support/Nest.h`.

The working tree also has uncommitted edits from other lanes in `Conversion/Runtime.h`, `Conversion/RuntimeCells.cpp` and `Conversion/Lower/Lower.h`. They aren't mine and I left them alone.


=== 
L21. HEAD was 4b0d8cd5 at start and 8bcce567 at finish. The two commits in between (f5d46b5e, 8bcce567) touched none of L21's files. Nothing was built, typechecked or run (D56). The checks were grep and reading the code.

**C39, take_into's lowering decides and counts (`Lower/Counting.cpp`), reported in decisions-C1-C80 and in deletions-and-targets): fixed.**
- The pass before the lowering, idr-rc-expand (`Expand.cpp:191-209`), already rewrites every `count.take_into` whose type proves nothing into a `count.match_unique`. Its unique region recycles the cell; its shared region makes a fresh cell. So the lowering's own run-time branch could never run, and it restated that shared path below the IR.
- `LowerTakeInto` now works like `LowerTake`. It refuses a take whose type proves nothing as an internal error, and it never tests the count. Its inc, dec and allocate in the lowering are deleted.

**C42, `lower` should be a function pass (`Lower.cpp`): the code is right; P0's wording is out of date.**
- The binding contract `audits/p0/verify/parts/contracts/spec-core.md:107` already settles this. idr-lower is "anchored on the program ... a pass cannot replace its anchor `idr.func`, so C42's per-function lowering runs inside it." The spec's `Pipeline.idr:456` declares it the same way, and no worker-and-merge scheduler is left.
- C42's text needs the coordinator's amendment.
- Another way to do it: run phases 1 to 3 as a separate pass on `llvm.func`. That would need a change in `compiler/spec`, which this pass may not touch, and a coordinator call.

**Dead function `Runtime::loadInfo`: fixed.**
- I deleted its declaration (`Runtime.h`) and its definition (`RuntimeCells.cpp`).
- `storeInfo` had one caller, `storeInfoAndWords`, so I moved its one store in there and deleted it. Its comment about memo cells was out of date.

**LLVM attribute names written as text (`Lower/Attributes.cpp`): fixed.**
- The passthrough attributes now come from the generated case names, `EnumTraits<FunctionAttribute>::names`. The spec already spells those cases with LLVM's names ("mustprogress", "nofree", "nosync").
- The one list left by hand is `ownFields{WillReturn, NoUnwind}`: the attributes upstream's `llvm.func` has a typed field for. That is a fact about upstream's op, not ours, so it stays. The order of the emitted attributes is unchanged.

**Program symbol table built twice (`Lower/Functions.cpp`, `Lower.cpp`): fixed.**
- Both `SymbolTable`s are gone. `viewsWhereAsked` and `prepareLifetimes`/`putBytes` now find each callee through the pass's `solver::ProgramGraph`, which is the one index of calls.
- `Lower.h` now includes `ProgramGraph.h` instead of `SymbolTable.h`.

**Not mine, but my file is involved:** L09's finding that `Matches.cpp` `lowerControlFlow` builds its patterns per function. If `lowerControlFlow` took prebuilt patterns and target, `Lowering` in `Lower.cpp` would build them once and pass them in.

**Possible follow-up in the spec (not required):** the spec could say that `count.take_into`'s operand claims `unique self` once idr-rc-expand has run. That would make the refused case impossible to write (L07 and L03).

**Files:** none added, moved or deleted, so INT has no CMake wiring to do. I modified `include/idr/Conversion/{Runtime.h, Lower/Lower.h}` and `lib/Conversion/{Lower.cpp, RuntimeCells.cpp, Lower/Attributes.cpp, Lower/Counting.cpp, Lower/Functions.cpp, Lower/Rooms.cpp}`.


=== 
L11, recheck 3. Three findings fixed, four left, two wrong. Nothing was built or run, per D56.

**Fixed**
- **The stream vtable** (`runtime/Io/Io.h`). The table of nine function pointers is gone, along with its four rows and `rowOf`. Each stream kind is now its own type: `InputStream`, `OutputStream`, `ErrorStream`, `FileStream{handle, file}` and `NotOpenStream`. A `Stream` concept states what each kind must do, and the pack in `StreamKinds` checks it. `withStream(handle, use)` is the one fold: it switches once on the slot's kind and gives `use` the typed stream. EBADF is saved once at that boundary. `streamOf`, the stored `Slot *` that could dangle, and the `never`, `notOpen` and `fileOf` helpers are deleted. `pollDescriptor` now takes a descriptor. Every caller is rewritten to `withStream`: `Bytes.cpp`, `FileTimes.cpp`, `Files.cpp`, `Lines.cpp`, `Input.cpp`, `Output.cpp` and `Handles.cpp`.
- **The name-prefix test** (`lib/Driver/Prepare.cpp:74-85`). The internalize step no longer keeps symbols by `starts_with("idris_rt_")`. It keeps exactly the generated table `idr::runtime::functions`, each entry looked up once with `Module::getFunction`. C ABI functions that programs never call are now internalized and can be dropped.
- **The reducer's per-op patterns** (`tools/idris-mlir-reduce.cpp`). Instead of one `PoisonResults` per registered op with `ub.poison` skipped by its name string, there is one `MatchAnyOpTypeTag` pattern. It skips `ub.poison` by type, because remaking a poison would never end.

**Left**
- **C101** (`idris_rt_exit(uint8_t)`): this needs the spec first. The runtime's prototype is generated from the spec, so changing the runtime alone would not compile. Seams:
  - L03: `Spec/Core/Ods.idr:106` gains a byte status kind, and `Generator/Cpp.idr:432,459` spells it `uint8_t`.
  - L13: `Spec/Ops/IO.idr:161` uses that kind.
  - L21: `Conversion/RuntimeCalls.cpp:224` truncates the guarded status to i8.
  - Then `End.cpp:323` (mine) drops its cast.
- **C24** (null handle held twice): this needs a new `Spec/Runtime/Handles.idr`, which is L11's spec, so it waits for the follow-up. The generated null handle would then replace `Io.h:40`. Seam for L16: `Registry/Primitives.idr:368,371`.
- **C201 / C98** (stack sizes per target): needs the stage-1 measurement, with INT.
- **D112** (`llvm_unreachable` at `Main.cpp:56`, `Options.cpp:331`, `Outcome.cpp:62`): not done. Under D114 our C++ asserts freely.

**Wrong**
- **C110**: the coordinator has already corrected C110's text (`proposals/0000-mlir-native.md:3334-3336`) to name `idr/IR/Numeric/` as the header's place, so the tree matches it.
- **C44**: C44 is about the *prepared* runtime, and its bitcode does live beside the object: `besideObject` at `Prepare.cpp:91`, read only from there by `readPrepared` at `ReadRuntime.cpp:293-323`, with no switch. The archive members carrying bitcode is how the archive is built. The flag sets are the target entries, the one place a target is decided (`CMakeLists.txt:231,316`). `findBitcodeInMemBuffer` reads any object format, so our code has no per-target branch.

**For INT**: no files added, moved or deleted.

**HEAD**: 4b0d8cd5 at start, 2501ca2f at finish (other lanes committed in between).


=== 
**L14, recheck 3**

HEAD was 4b0d8cd5 at start and 2501ca2f at finish. Nothing was built, typechecked or run.

**Fixed**
- **Dead decide-before-apply check (Decision.h, C116):** I kept `solver::decided`, because it is C116's one const-view check. Under D114 its run-time check is allowed. L12 now calls it (`Narrow.cpp:86`), so it is no longer dead. I rewrote the header comment, which claimed the pipeline's record pairs the steps, to say what the code does.
- **`Editor::moveInto`:** deleted from the header and the .cpp.
- **`Offsets::itemsOf`:** deleted, along with the `items` table that only it read.
- **Bool walk phase (Elaborate.cpp):** `demand` now uses `depthFirst` with `Descend`, so `Step::expanded` is gone. I updated the stack comments in Engine.h and Elaborate.cpp.
- **C109:** `TypeGraph.h` now says "an array of mutable memory".
- **C34:** deleted the hand-written `isInvalidated` in `ProgramGraph.h` and `TypeGraph.h`, which only repeated MLIR's default, plus the include that became unused.
- **Cycle decider restated:** `ProgramGraph::onCycle(SccId)` is now the one place a component is decided cyclic, and `onCycle(FunctionId)` calls it. `Ranges.cpp` and `SummarizeImpl.h` use it; their own copies are deleted.
- **D108:** every round of idr-simplify now waits for room in one process-wide memory budget for its e-graph (`HostArenas`, `Admitted` in `Simplify.cpp`), whichever pass runs it. The size comes from the function's own node budget (`Function::arena()`, `detail::bytesPerNode` in Engine.h). The first round's e-graph is gone before the second is admitted, so a run never holds one budget while waiting for another.

**Seams (other lanes' files)**
- **L18:**
  - Delete `inlining::Admission`: `Inline.h:106-123` and `InlinePass.cpp:45, 57-62, 94-108`.
  - Delete the optimizer's admission: `Component.cpp:67-70`, `Optimize.cpp:71`, `OptimizeScheduler.h:101, 128`.
  - These are now redundant. Until they go, the inliner and optimizer count each e-graph twice, which is safe but redundant.
  - After that, `egraph::arenaBytes(ops)` and the public `nodesPerOp()` become engine-internal (mine).
- **L15:** `depthFirst`'s stack (`Nest.h:38`) should use the footprint allocator so it is counted. `Memory.h`'s comment still names the optimizer as the reader of the host's memory.
- **L02 and L08:** `Effects/Component.cpp:110-114`, `Effects/Writer.cpp:63` and `InPlace/Unique.cpp:297` should call `graph.onCycle(c)`.
- **L03:** the pass record has no field pairing an apply step with its decide step (C116).

**Left**
- **Op ladder in IdentitiesRecord.cpp:164-190:** needs an op interface declared in the spec, implemented by `data.con`, `nat.pred` and `big.add`. Left as a spec item for the follow-up.
- **D103:** the skeleton rules belong in L12's `Memory.idr`, with their C++ in the op lane's files (spec). The engine needs nothing new: a rule's `Rewrite` can already forward the written value or erase the overwritten write.
- **C156 and C32:** both need a stage-1 measurement.
- **D57 and D98:** owner questions.
- **§5.2 layering:** for the coordinator and INT. "`IdrSolve` names no MLIR" contradicts C33, under which the graph wraps `mlir::CallGraph`.
- **Pointer-keyed map at Simplify.cpp:95:** the audit is partly wrong here. The map numbers rewrite roots by the only identity MLIR's erasure listener reports, an address. It holds no per-node state (that is a BitSet by id) and dies when the rewrites finish. Moving it into a single IR-handle numbering in IdrIR is INT's §5.2 work.

**Files for INT:** none added, moved or deleted. `IdrEGraph` now includes `idr/Support/Memory.h`, which needs `idris_rt` (already linked through IdrIR).


=== 
L12, recheck 3. HEAD was 4b0d8cd5 at start and ea9928a6 at finish (other lanes committed meanwhile). Nothing was built or run.

**Fixed**
- **Op ladder in idr-narrow-words** (`Narrow.cpp:139-151`, D7/R8): the conversion test now reads `BigOfIntegerOpInterface`, then the `ConstantLike` trait on a big result (this covers both `idr.constant` and `ub.poison`), then `BigToIntOp`, the one op `word()` writes. The poison-only "asked" condition is gone. As a result, a big poison nobody narrowed is now folded and moved to the function entry, as big constants already were. That is a small behaviour change.
- **Narrow's own decide-before-apply check** (C116): it now calls `solver::decided(getCachedParentAnalysis<Ranges>(program))`. L14 has kept `decided`, and it now has this caller.
- **`LaneWidth{bits, bool lanes}`**: replaced by `std::optional<IntegerWidth>` with `enum class Spread {Scalar, Lanes}`. There is no `{0,false}` sentinel any more: an op that computes on no integer gets none.
- **D7 in `Widths.cpp:81`**: `isa<CastOpInterface, SelectLikeOpInterface>`, both upstream interfaces.
- **Numbering map in Narrow.h**: the `Accumulations` class becomes `outsideAccumulations(root)`. Its op map is local and freed when the search ends; `computesWideLanes` and `Copy::fits` now loop over the returned ops.
- **Numbering map in BufferizeModels.h** (and C178): the `AliasClasses` map is now a local `footprint::DenseMap` in `related()`. Releases are numbered in the same walk, and `sharers` takes a `Node`, so nothing asks by IR handle after the walk.
- **C178, `Linalg.cpp:41`**: the map is now a `footprint::DenseMap`, so its memory is counted. It is local and freed on return.
- **Dead `extentsOf`**: deleted from `StructureLoops.h` and `Lowering.cpp`. `domainOf` still has other callers.
- **Stale "idr-rc's"** in `Memrefs.cpp:80`: the comment now says "counting's", with no pass name.
- **C144, `uncounted`** in `OpsArrayFusion.cpp`: it now reads `countingAt == StageCounting::Uncounted`. Every pass that fuses runs at First or earlier, where both columns agree.

**Left**
- **C39/C107/§6, `takeOut`'s run-time `isUnique` test on a boxed element**: it can't go from my files alone. The box exists only in the lowering's layout. Deleting the test needs two things first:
  - L04: whether an element is boxed becomes a fact the IR carries.
  - L07: counting expands the take into `idr.match_unique` on the box, unfolded when the buffer is not `unique deep`.
  
  Deleting the branch before that would miscompile shared boxes. It also needs a build.
- **D103 (`spec/Arrays/Memory.idr` skeleton rules)**: in compiler/spec, which this pass doesn't touch; left for the follow-up.
- **D71 claim level** (`Releases.cpp:58`): an open owner question.

**Seam for L19** in `lib/Transforms/Expect/NarrowedLanes.cpp`, `widestLane`: this file no longer compiles until it changes. It should become:
```
for (Operation *op : narrow::outsideAccumulations(loop))
  if (auto w = narrow::integerWidth(op); w && w->spread == narrow::Spread::Lanes)
    bits = std::max(bits, w->bits);
```
Its comment's "laneWidth" becomes "integerWidth".

**Files for INT**: none added, moved or deleted.


=== 
**Lane L18, recheck 3.** HEAD was 4b0d8cd5 at start and 2501ca2f at finish; none of the commits in between touched L18 files. Nothing was built, typechecked or run.

**C178, program-sized maps outside the footprint (8 sites): fixed**
- `Optimize/Contify.cpp`: `groups` is now a footprint vector found by a per-node index, so there is no hash map.
- `Optimize/Waves.cpp`: `turnOf` is deleted. `enable` queues each component's steps together, leaders in order, so a step for a new leader opens its turn.
- These maps and sets became `footprint::DenseMap` or `footprint::DenseSet`:
  - `Settle.cpp` `nodeOf`
  - `Specialize/Order.cpp` `known` and `sizes`
  - `Deduplicate.cpp` `inAttributes` and `inTypes`
  - `Captures.h` `ownerOf`, and `Captures.cpp` `seen`
  - `CaptureDrops.cpp` `anew`
  - `Declare.cpp` `firstOf`
- I made the same change to the other program-sized maps in my files: `Defunctionalize.h` (`ids`, `converted`, `matchIds`, `coercionIds`), `Optimize.h` (`blocked`), and `SpecializeState.h` (`byKey`, `byDigest`).

**Duck-typed `labelled` in `Edits.cpp:73`: fixed.** A local concept, `OfFunction`, now states the shared shape (the op's result, callee and index terms), and the lambda is constrained by it. Declaring an interface in `Spec/Closures` would go further; that is spec work, left for the follow-up.

**`bool` walk phase in `Convert.cpp:90-125`: fixed.** It now uses `depthFirst`, computes each part's fields once, and takes converted fields off a result stack. I changed `Order.cpp` `sizeOf` the same way. Two bugs in that code are fixed too:
- It called `con.getType()`, which `ConAttr` doesn't have because it is untyped; it now converts `con.getData()`.
- A constant built as a run of several cells was rebuilt as one constructor holding every cell's fields. It is now rebuilt cell by cell with `ConAttr::getRun`.

**Extra bug, not in the audit: fixed.** In `Declare.cpp`, the type replacer dropped a data type's refinement and binders when it declared the family anew. They are now kept, as `Substitute.cpp` does.

**`SpecializeState.h:212` `byName`: fixed, map deleted.**
- Across waves, a name is found through the graph editor's `find` plus `byFunction`.
- Within a wave, `admit` now sorts the asks by name itself (moved from `Settle.cpp`) and compares each ask with the one before it.
- The two-keys-on-one-name internal error is kept in both `request` and `admit`.

**D60, no static tensor copy: left.** It is blocked on L16: `Translate/Types.idr:102-130` writes an array dimension as `Dynamic` with no link to its index variable. How that link is represented needs a coordinator or owner decision. Specialization can make the tensor type static only after that.

**D75, a missed promised join point raises no error: left, needs an owner or coordinator decision.** Contify can't tell a promised continuation from any other function. The open question is which op holds the promise: Emit writing `idr.join` itself (L16 with L09), or a promise fact on `idr.func`. The audit's guess that deduplicate, running first, could silently merge two such continuations comes down to the same question.

**ResultUsesMax (L03 with L18): left as a seam with L03.** `foreign/idr/include/idr/IR/Traits.h` must declare `::idr::ResultUsesMax<unsigned...>::Impl` (an `OpTrait::TraitBase`), or the generator must stop printing it. The spec side (`Spec/Closures/Declarations.idr:229`) is left for the follow-up.

**Files for INT:** none added, moved or deleted.


=== 
HEAD was 4b0d8cd5 at start and 13793d77 at finish. The commits in between touched none of my paths. Per D56 nothing was built, typechecked or run, so none of the fixes below is verified.

**Fixed**
- **Named.cpp recursion:** `locationNames` now uses upstream's `LocationAttr::walk`, which is iterative under carried patch 81. It still descends only names and fusions.
- **ResetsUnshared (D9):** `onCountOf` now asks `effects::eachOwnEffect` and returns `effects::Does`. An op that declares nothing touches the count, and so does a count effect that names no value. This is stricter than before: if a borrowing call breaks `resets-unshared` in cfold, rbtree or bubble-sort, send it back to me.
- **Continuations (C33, stale comment):** `SymbolUserMap` deleted. `contified` reads the program graph's `callSites` and `callers`, so it now holds only for a first-order program before lowering, and fails elsewhere. Its description is updated in `Properties.idr` and `ExpectProperties.inc`. Its func.func case moved out of `expect-calls` into a new `expect-contified` test.
- **Contracts.h `bySymbol`:** deleted. Each record now finds its function through the program's symbol table, which the crash-sites check already builds.
- **C178, LabelsLeast:** per-point state moved into footprint containers.
- **C72:** the comment in `Report.cpp` is fixed.
- **C12:** the five prose errors now name only the property. The two verifier rejections use `{{}}`, upstream's own form. The two quantities-kept lines became one, because `-verify-diagnostics` matches every error to the first expectation that fits.
- **C60, io-buffer:** rewritten with one build. io.c is given the page size, writes past the buffer at every offset, and is compared with the same pieces written straight to the descriptor (`io direct`). The input is padded so it crosses each refill at every offset. `IDRIS_RT_IO_BUFFER_SIZE` is gone.
- **C7, registry-only:** now scans `compiler/spec` for names in the registry's namespaces and names built from literals, ignoring file names. Bare namespace words are skipped there: the spec uses `Builtin`, `Data` and `Control` as MLIR, enum and directory names. Added one allowlist entry (a doc comment in Checks.idr) and planted witness and near-miss spec files.
- **world-unsafe-perform:** now expects `library`.
- **frontend-beside:** the module it compiles is now written inline.
- **Prims `Width.signed`:** now the spec's `Signedness`, and Sem and Fuzz match on it.
- **Gen Bools:** replaced by `Fit` (Within | Overran) and `Coverage` (Whole | Partial).
- **C66:** added `tests/elaboration-search-grows`. Cons2 is refused, and the near program elaborates `natToFinLT 3 {n = 10}`. The header's line 17 assumes the refusal is reported at `%search`; that is a guess until it runs.

**Wrong**
- **Expect.h `FunctionNumbering`:** it is not a copy of the program graph. Properties hold at every stage, including func.func and llvm.func (Expect.h:20-23). The graph exists only from defunctionalization to lowering (ProgramGraph.h:3-6), and constant-stack reads `musttail` after lowering (ConstantStack.cpp:69-76). It only numbers functions into bit sets, which cxx-rules.md:104 itself allows.

**Left**
- **C197, guards found by name:** needs a spec change. `Guard.check` (Core/Op.idr:360-366) should become a closed sum of the four guard ops in Ops/Checks.idr:251-288. Then `harness/Prims.idr:413-448` becomes a total match with no `Left` branch.
- **Shell and awk machinery (3,234 lines):** porting it to Idris is a large job that needs a build to check; possibly an owner question.
- **C126:** needs a build, plus a way to print checked terms from both the fork and stock Idris (seam with L17).

**Files for INT:** no C++ was added, moved or deleted. Added:
- `tests/expect-contified/expect-contified.mlir`
- `tests/elaboration-search-grows/{Main.idr, expected, near/Main.idr, near/cases/no-input/expected-stdout}`
- `tests/registry-only/witness/compiler/spec/IdrisMLIR/Spec/Ops/Strings.idr`
- `tests/registry-only/near-miss/compiler/spec/IdrisMLIR/Spec/Generator/Outputs.idr`
