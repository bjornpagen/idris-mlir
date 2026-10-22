# Recheck 3: the first seam batch's handoffs


=== 
L21 lane: one item closed, three left, none already done. Nothing was built, typechecked or run, and I made no git write.

HEAD at start: a8ec2839. HEAD at finish: a8ec2839.

**L09 seam, phase 3 built per function (`foreign/idr/lib/Conversion/Lower.cpp`): closed.** This was the one blocking compilation.
- `struct Lowering` now has a `ControlFlowLowering controlFlow;` member, built from `*program.getContext()` next to `target` in the constructor.
- `lowerFunction` now returns `lowerControlFlow(fn, lowering.controlFlow)`.
- I updated the struct's comment to name phase 3's conversion among the things made once.
- What changed: the scf-to-cf patterns and target are no longer rebuilt for every function. They are built once per pass run and shared, unchanged, by every worker.
- `lowerControlFlow` has no other caller, and `populateJoinLoweringPatterns` has no reference left outside `audits/` and `proposals/`.

**L11/L13 C101 seam, truncate the exit status to i8 (`RuntimeCalls.cpp:224`, `LowerExit`): left.** It waits on the spec, which has not changed:
- `Spec/Core/Ods.idr:106` still has no 8-bit kind (L03).
- The exit row at `Spec/Ops/IO.idr:162` is still `[TakesInt64]` (L13).
- The runtime's prototype is generated from that row. Truncating to i8 now would no longer match the generated `int64_t` entry.

**L03's C42 item, make the lowering a function pass: left for the coordinator.**
- P0's C42 text (`proposals/0000-mlir-native.md:2641`) still says "function pass".
- The binding contract `parts/contracts/spec-core.md:107` anchors idr-lower on the program instead.
- One of the two needs the coordinator's amendment. The alternative would be a change in `compiler/spec`, which I don't own.

**My own handoff's spec follow-up, `count.take_into`'s operand claims `unique self` after idr-rc-expand: left.**
- It belongs in `Spec/Counting/Declarations.idr`, which is L07's file (with L03).
- L21 owns no path under `compiler/spec/`.
- It was marked "not required".

**Files:** none added, moved or deleted, so INT has no CMake wiring to do. Edited: `foreign/idr/lib/Conversion/Lower.cpp`.


=== 
L07 had four items. The one INT was waiting on is closed. Two others are left: one is optional, one waits on L04. The fourth needed nothing. Nothing was built, typechecked or run.

1. **The type-inference declarations in `compiler/spec/IdrisMLIR/Spec/Counting/Declarations.idr` (blocking INT): closed.**
   - Lines 212 and 233 (`count.take`, `count.unpack`) now say `InfersTypes InferredOnly`.
   - Lines 323 and 423 (`cell.init`, `own.adopt`) now say `InfersTypes AlsoCompatible`.
   - No `Declares InferType` is left in `Spec/Counting/`. The new names come in through `Core.Vocabulary`, which already imports `Core.Interfaces` publicly.
   - What this removes: which inference methods an op defines used to be picked by comparing method names as strings. It is now a two-case choice.
   - The C++ (`Ops.cpp:171,179`, `Takes.cpp:106,119`, `CellInit.cpp:226,236`) already defines these methods in that form, so it needs no change.

2. **L21's optional suggestion that `count.take_into`'s operand claim `unique self` once `idr-rc-expand` has run: left.** L21 marked it "not required". `idr-rc-expand` runs inside the Owned stage, so no stage boundary falls after it. Stating the claim would need a new stage or stage fact in L03's `Pipeline/Stage.idr`. Which stage holds the fact is a core-shape choice for the coordinator.

3. **L12's request that counting expand a boxed element's take into `idr.match_unique`: left, waiting on L04.** Whether an element is boxed is still known only to the lowering's layout (`Layout.h:173`). Nothing in the spec or IR carries it yet, so counting has nothing to expand on.

4. **L08's note on `Counting/Borrows.cpp:145`: already done.** It calls `forEachJoinParameter(FuncOp, (BlockArgument, uint32_t))`, which matches L08's new definition in `Walks.h:89`.

From my own earlier handoff, nothing in my files was left. Its two fixes still hold in the live tree: `Counts`/`countsOf` are gone, and `own.adopt` is legal only from First to Owned. One seam is still open in someone else's file: L16 must delete the `ownAdoptOp` builder in `compiler/src/IdrisMLIR/Dialect/Idr.idr:1008`.

**Files:** none added, moved or deleted. Edited only `compiler/spec/IdrisMLIR/Spec/Counting/Declarations.idr`.

**HEAD:** a8ec2839 at start, 44a0d101 at finish. The commits in between touched none of L07's files.


=== 
L04: two items fixed in my own spec files, one was already done, and the rest are still blocked. Nothing was built, typechecked or run.

**INT blocker, `Families/Ops.idr:150`: fixed.** It now reads `InfersTypes InferredOnly`, so it no longer names the removed `InferType`. `data.field` has no type rules, so the generator's check that refuses a hand inference beside type rules does not apply. The hand C++ (`OpsConReads.cpp:94`) already takes the adaptor form, so nothing changes there.

**L03's namespace seam, `Families/Dialect.idr:131`: already done** by a8ec2839, which writes `DialectNamespace`.

**`sortKind` and `termKind` (`Families/Terms.idr`): fixed.** Both unused functions are deleted. The `SortKind` and `TermKind` types stay, because the dialect's enums and wire codecs use them. A search of the whole tree, `audits/` aside, finds no remaining reference.

**The `eliminates` op ladder (`Symbols.cpp:76-84`) and the trait it needs on `data.field`: left.** Neither `Spec/Core/Interfaces.idr` nor `IR/Traits.h` declares an `EliminatesOperand` trait yet, so the seam stands:
- L03 declares the `TraitDef` and the empty C++ trait class.
- L09 puts the trait on `data.match`, L13 on `io.put_str`, and I put it on `data.field`.
- Then the lambda becomes one `hasTrait` test.

I can't add the trait first: until an op carries it, the check would silently stop matching anything.

**`foldDialect` (`Components.cpp:88-106`): left.** It still needs the coordinator to choose between two fixes. `Support/Match.h` has no overload that folds an `mlir::Type` yet.

**L12's seam, "whether an element is boxed becomes a fact the IR carries": left.** The boxing is already decided once, from the element type and the target's sizes, by `Layouts::element(type).boxed`, and counting already reads `Layouts`. What is missing is the box itself as an IR value, which `match_unique` would need. That is a choice of which op or type holds the box, which goes to the owner or coordinator, and an earlier box type was deleted. It also needs L07's expansion.

**Left as they were:** the D114 checks in `Layouts.cpp` and `Components.cpp`, and the `shapeBudget` measurement.

**Files:** none added, moved or deleted. Edited `compiler/spec/IdrisMLIR/Spec/Families/Ops.idr` and `compiler/spec/IdrisMLIR/Spec/Families/Terms.idr`.

**HEAD:** a8ec2839 at start, 1ad6989f at finish. The commits in between are other lanes' and touch none of my files.


=== 
I closed the one seam another lane addressed to me. The two items in my own handoff were already in the tree, and C32 stays open because it needs a measurement. Nothing was built, typechecked or run, and I made no git write.

**HEAD:** 9a981e27 at start, 1ad6989f at finish (other lanes committed in between).

**Seam from L03's handoff (fixes-a.md:115): `InPlace/Unique.cpp` should ask `graph.onCycle(c)`.** Closed.
- In `foreign/idr/lib/Transforms/InPlace/Unique.cpp`, `solve` decided for itself whether a component is cyclic (`members.size() == 1 && !graph.callsItself(...)`). That copy is deleted.
- It now calls `graph.onCycle(component)`, the one place in `ProgramGraph` that decides it. The fixpoint repeats only for a cyclic component.
- None of my other files restate the cycle test.

**Rechecked against the live tree:**
- **C202:** already done. `ownership::upstreamElement` (`Facts.h:330`) is the one check; `Walks.h:53` and `Chains.cpp:142` both call it.
- **C178 / §5.2:** already done. No `DenseMap` keyed by `Value`, `Operation` or `Block` remains in any file I own.
- **C32 (with L14):** left. It needs a stage-1 measurement on the four targets, which needs a build.
- Nothing I own in `compiler/spec/` was outstanding.

**Seam for L02** (their files, same issue, still open in the live tree):
- `foreign/idr/lib/Transforms/Effects/Component.cpp:110-114`: the `callsItself` lambda plus `members.size() > 1` should become `graph.onCycle(c)`.
- `foreign/idr/lib/Transforms/Effects/Writer.cpp:63`: `members.size() == 1 && !graph.callsItself(members.front())` should become `!graph.onCycle(c)`.

**Files for INT:** none added, moved or deleted. Modified: `foreign/idr/lib/Transforms/InPlace/Unique.cpp`.


=== 
L14 seams: HEAD was a8ec2839 at start and 1ad6989f at finish (other lanes committed in between). Nothing was built or run; all checks were grep and reading.

- **L09's seam, a numbering over one region: closed.** `Extraction.h` gains `enum class Scope {Isolated, Nested}`. `Numbering<Tag, Scope>` (default `Isolated`) keeps `at` for a function, where a lookup cannot miss. A nested region gets its own constructor and `find`, which returns none for a value made outside the region. `inWalkOrder` now has a version over a region, and the function version calls it, so both are numbered in the same order. Seam for L09 in `IdenticalRegions.cpp`: `Body` uses `solver::Numbering<BodyValue, solver::Scope::Nested>` and an `IndexVector<Node, Value> partner`. Its private `DenseMap` goes. The compare becomes `n ? partner[*n] == rv : lv == rv`.
- **C116, the decide step paired with its apply group: closed.** L03's `RunDeciding` has landed, so the header comment in `Decision.h` now says the pipeline's list pairs each decide step with its apply group.
- **D108, the follow-up after L18: closed.** L18's uncommitted working-tree change deletes `inlining::Admission` and the optimizer's admission. I deleted `egraph::arenaBytes`, which now has no caller. `nodesPerOp()` moved from public `EGraph.h` into the engine's internal `detail` namespace in `Engine.h`; `Rules.cpp` defines it and only `Build.cpp` uses it. If L18's change does not land, this breaks: `InlinePass.cpp` and `Component.cpp` call `arenaBytes` at HEAD.
- **D103: left, it is L12's.** The two rules belong in `Spec/Arrays/Memory.idr`, with their C++ beside `MoveOut`. The engine needs nothing new: a `Rewrite` can replace a read or erase a write.
- **Op ladder in `IdentitiesRecord.cpp`: left.** Still no spec interface. Seam: L03 or an area lane declares the interface, and L04 (`data.con`) and L13 (`nat.pred`, `big.add`) implement it.
- **Left as they were:**
  - C156 and C32 need a measurement.
  - D57 and D98 are the owner's.
  - The §5.2 layering is for the coordinator and INT.
  - The map at `Simplify.cpp` is INT's §5.2 work.

**Files:** none added, moved or deleted. Edited:
- `foreign/idr/include/idr/Analysis/Solver/{Extraction,Decision}.h`
- `foreign/idr/include/idr/Transforms/EGraph.h`
- `foreign/idr/include/idr/Transforms/EGraph/Engine.h`
- `foreign/idr/lib/Transforms/EGraph/{Rules,Simplify}.cpp`


=== 
L18, recheck 3 seams. HEAD was a8ec2839 at start and 1ad6989f at finish. None of the commits in between touched my files. Nothing was built, typechecked or run.

**Closed**
- **INT's blocker, `Closures/Memo.idr:132`:** it now reads `InfersTypes InferredOnly`. The hand `MemoTakeOp::inferReturnTypes` already takes the adaptor form, so the C++ needs no change.
- **L14's seam, the admission in two places:** deleted.
  - `inlining::Admission` is gone from `Inline.h`, along with its `<mutex>` and `<condition_variable>` includes.
  - In `InlinePass.cpp` I deleted its definitions, its `enter`/`leave` calls and the `Memory.h` and `ErrorHandling` includes. The `runPipeline` lambda now only decides tails.
  - The optimizer's copy is gone too: `Component.cpp`'s `round` admission and its two includes, `Optimize.cpp`'s ledger and `Memory.h`, and the constructor parameter and member in `OptimizeScheduler.h`.
  - idr-simplify's process-wide `HostArenas` is now the only place an e-graph is admitted.
- **`labelled` in `Edits.cpp` (my spec item):** the spec now declares `BuildsLabelOpInterface` in `Closures/Declarations.idr`. Its methods are `getResult`, `getCalleeAttr` and `getIndexArgs`, each met by the op's own generated accessor. `fn.closure` and `lazy.suspend` take it through `namesFunction` (renamed from `symbolUse`), and it is in `declarations.interfaces`. `Edits.cpp` now walks that interface once, so the local concept `OfFunction`, its `<concepts>` include and the two walks by op class are deleted. `lazy.delay` stays its own walk: it names no function and builds the forced state, which is a genuinely different case.

**Already done**
- **ResultUsesMax:** L03's `idr::ResultUsesMax<Result, From...>::Impl` matches what the generator prints, and no hand verifier repeats its rule. The spec needs no change.

**Left**
- **D60:** still waiting on L16's `Translate/Types.idr` dimension link, which needs a decision.
- **D75:** an owner or coordinator decision (which op holds the join-point promise).

**Seams**
- **L14:** with the admission gone, `egraph::arenaBytes` and the public `nodesPerOp()` can become internal to the engine.
- **INT:** the comment at `lib/Transforms/CMakeLists.txt:107` should drop "with its admission of what may still be inlined", if that refers to the deleted admission.
- **INT:** the generator needs to be run, so that `IdrInterfaces.h.inc` and the ODS pick up `BuildsLabelOpInterface` and `memo.take`'s adaptor form.

**Files:** none added, moved or deleted. Edited:
- `compiler/spec/IdrisMLIR/Spec/Closures/{Memo,Declarations}.idr`
- `foreign/idr/include/idr/Transforms/{Inline,OptimizeScheduler}.h`
- `foreign/idr/lib/Transforms/Inline/InlinePass.cpp`
- `foreign/idr/lib/Transforms/Optimize/{Component,Optimize}.cpp`
- `foreign/idr/lib/Transforms/Defunctionalize/Edits.cpp`


=== 
L02 recheck-3 seams. HEAD was 44a0d101 at start and 1ad6989f at finish. The three commits in between touched none of my files. Nothing was built, typechecked or run. No L02 handoff for recheck 3 exists in fixes-a.md or fixes-b.md, so I took L02's open recheck-3 findings as well as L14's seam.

**L14 seam: call `graph.onCycle(c)`**
- `Effects/Writer.cpp` `addCycles`: closed. It now skips any component where `!graph.onCycle(component)`, and its own copy of the cycle test is gone.
- `Effects/Component.cpp:110-114`: left as stated, because the call doesn't fit. The optimizer's components grow and merge apart from the frozen graph's, so `writeComponent` is handed members and has no `SccId` to ask about. I simplified it instead: the `callsItself` lambda is deleted. A site is only ever a call of a member, so the test is now "more than one member, or the lone member has any site". A comment says why.
- `InPlace/Unique.cpp` (L08's): already done. It calls `graph.onCycle(component)`.

**cxx-rules L02: dead `licensesDropOrMove` (`Analysis/Effects.h:65`)**: closed by deleting it. The same rule is already enforced elsewhere:
- **Deleting a call:** a crash or a divergence in a call's row is declared as a write on that state (`callEffectsOf`, `rowSet`/`emitRow`), so the call is never dead.
- **Moving a call:** `speculatable` reads `mayNotReturn`.
- The comment on `speculatable` now says this. Nothing outside `audits/` refers to the deleted function.

**C178: solver state outside the footprint**: closed. These are now `footprint::Vector`, and their `<vector>` includes are replaced by `Footprint.h`:
- `Writer.cpp` `writable` and `owners`
- `Parts.cpp` `seeds`
- `Transforms/Effects.h` `WriteNodes::first`
- `Component.cpp` `writable` and `owners`, plus the other per-member tables there: `byId`, `own`, `untouched` and `bounded`

**L02i's routed `holdsNoComponent`**: already done (zero hits in the code).

**Spec (`Spec/Functions/`)**: nothing addressed to me. No `InferType` or `"idr" :::` seams and no D112 escapes.

**Files for INT:** none added, moved or deleted. Edited:
- `foreign/idr/include/idr/Analysis/Effects.h`
- `foreign/idr/include/idr/Transforms/Effects.h`
- `foreign/idr/lib/Transforms/Effects/{Writer,Component,Parts}.cpp`


=== 
L12, closing the seams left by recheck 3. HEAD was a8ec2839 at start and 1ad6989f at finish (other lanes committed in between). Nothing was built, typechecked or run, so none of these changes is checked by a compiler yet.

**Closed**
- **L03's seam, Narrow.cpp:226-228.** idr-narrow now gets its nested passes from the pipeline: `::idr::pipeline::applyGroupOfIdrNarrow(nested)` from the generated `ApplyGroups.h.inc`, replacing the hand-written `nest<FuncOp>().addPass(createIdrNarrowWords())`. The pass no longer keeps its own copy of which passes run inside it; the pipeline list pairs the decide step with its group.
- **D103, the two missing skeleton rules (my spec item, also routed to me by L14 and L13).** Both are added in `Spec/Arrays/Memory.idr`, with their C++ in `Arrays.h` and `OpsArrayFusion.cpp`:
  - `ForwardWritten` (on `array.get`): a read of an element right after a write of the same element, with nothing between changing the array, becomes the written value.
  - `DeleteOverwritten` (on `array.set`): a write of an element right after another write of it, with nothing between touching the array, deletes the first write.
  - Both apply only before counting starts. Neither fires on a value Idris marked use-exactly-once, since forwarding would add a use and deletion would remove its only use.
  - They share the helpers I pulled out of MoveOut's code (`OnMemoryOf`, `lastBefore`, `sameElement`, `memoryOf`), so MoveOut lost its inline copies of them.

**Left**
- **C39/C107, `takeOut`'s run-time `isUnique` test in Elements.cpp.** Neither prerequisite has landed: the IR still doesn't say whether an element is boxed (L04), and counting doesn't yet turn the take into a uniqueness match on the box (L07). Deleting the test before both land would miscompile shared boxes.
- **D71:** still an open owner question.

**Seams for other lanes**
- **L19, still open:** `Expect/NarrowedLanes.cpp:24-32` still uses `Accumulations` and `laneWidth`. It won't compile until it switches to `outsideAccumulations` and `integerWidth`, as my earlier handoff set out.
- **L19:** a behaviour test for the two new rules. tests/ isn't mine.
- **INT:** wire up `ApplyGroups.h.inc`. Regenerating the specification adds the two rules to `Rewrites.h.inc`.

**Files:** none added, moved or deleted. Edited:
- `compiler/spec/IdrisMLIR/Spec/Arrays/Memory.idr`
- `compiler/spec/IdrisMLIR/Spec/Arrays/Declarations.idr`
- `foreign/idr/include/idr/IR/Arrays.h`
- `foreign/idr/lib/IR/OpsArrayFusion.cpp`
- `foreign/idr/lib/Transforms/Narrow/Narrow.cpp`
