<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# transforms-b: Ownership, Effects, Bufferize, Tail, StructureLoops, Stack, Optimize, Pipeline

Read whole: every file of `lib/Transforms/{Ownership,Effects,Bufferize,Tail,StructureLoops,Stack,Optimize}/`, `lib/Transforms/Pipeline.cpp`, and the headers `Bufferize.h`, `BufferizeModels.h`, `Effects.h`, `Optimize.h`, `Ownership.h`, `Pipeline.h`, `Stack.h`, `StructureLoops.h`, `Tail.h`, `InnerPasses.td`, plus the parts of `Passes.td` for these passes. To trace values I also read `Analysis/Ownership.h`, `Analysis/Tail.{h,cpp}`, `IR/Grades.h`, `IR/Ownership.h`, `IR/Verify/Uses.cpp`, `OpsOwnership.cpp`, the ODS of `idr.con`, `idr.reuse`, `idr.take`, `idr.func` and the matches, `Canonicalize.h`, `Contracts.h`, and the PINS entry `inline-unreachable`. I changed nothing.

## The area as it stands

The passes already lean on MLIR. idr-rc is a program pass that runs two nested function passes holding read-only tables. Placement decides region semantics through `RegionBranchOpInterface` (`decides`). Bufferization is One-Shot with upstream's function-boundary models. The tail passes and returned-arguments use `walkAndApplyPatterns`. idr-optimize erases dead functions with symbol-dce. The `Point` variant and `Reuses::Site::box` (a value or a field an earlier take gave) are good sums.

The defects are in what the IR lets a pass see:
- **One constructor, two ops.** `idr.con` and `idr.reuse` differ only in where the cell comes from, so readers carry a `variant<ConOp, ReuseOp>` and the reuse rewrite keeps maps from old ops to new ones.
- **A take's results built by hand.** They are a function of the value's type and the tag, but three builders, an accessor and the verifier each spell that rule, four different ways.
- **Function bodies that may hold several blocks.** An `idr.func` body admits several blocks, which arise from one transient inliner state. Every later pass then guards, assumes, or silently mishandles that case.
- **Facts held only in prose.** Some contracts live only in pass descriptions and are re-checked or worked around downstream: the stage a pass needs, and the rule that no linalg op over counted elements reaches idr-rc.
- **Hand-written case analysis instead of interfaces.** It appears in returned-arguments (a ladder over `scf` op kinds that `RegionBranchOpInterface` answers) and in the ordered loop nests: an optional world threaded by flags, a test in every iteration for the first one, and a rank-0 special case that the empty product removes.

## Findings, ranked (branches removed against risk)

### transforms-b-1: a take's results are a function of (value type, tag), spelled five ways

| Field | Content |
|---|---|
| ID | transforms-b-1 |
| Evidence | `Ownership/Take.cpp`: `taken()` L27; `takeAt` builds the result list by hand, with a token when `!ctor.fields.empty()` and no box check (L40-45); `takeAtEntry` adds a token when `isa<BoxType>(unrestricted(..)) && block.getNumArguments() != 0` (L56-61); `takeFields` builds its own list (L70-72). `lib/IR/OpsOwnership.cpp`: `movedField` L22 duplicates `taken`; `TakeOp::getToken` tests `isa<BoxType> && getNumResults() != 0` (L87-90); `getFields` drops 0 or 1 (L92); `TakeOp::verify` recomputes the exact expected list from `isBoxed && !fields.empty()` (L96-115). The same cell rule ("a box constructor with fields has a cell, else it is an atom") is spelled again in `Analysis/Ownership/Reuses.cpp` `dies` L183-186 and `fits` L208-210, and with different box tests in `Stack/Stack.cpp:73` (`isa<BoxType>(type)`, no `unrestricted`), `Ownership/Reshape.cpp:105`, `Analysis/Tail.cpp:21` and `Tail/Trmc.cpp:185`. Count: 5 spellings of token presence, 3 hand-built result lists, 2 copies of the field rule, and 6 box tests written separately, of which Stack's disagrees with the rest. |
| Counterexample | `takeAt` on an unboxed sum with fields builds a token that the verifier rejects. Today only the callers' unstated invariant prevents it. Stack's test lacks `unrestricted`, so an `idr.con` of `!idr.lin<!box>` at stage `first` is never put on the stack, while Reuses and the ConOp verifier treat the same value as a box. |
| Root cause | The result list of `idr.take` is inferable from its operand type and its `tag` property, but the op declares its results as given. The cell rule has no single home. |
| Correction | `idr.take` implements `InferTypeOpInterface`. `inferReturnTypes` reads the scrutinee's type and the tag: a token when the constructor has a cell, then each field at `fieldType(value, field)`, owned where it holds references. `isCompatibleReturnTypes` is today's `movesAs`, since the commit later writes the excl grade. The builder is `(value, tag)`. "Has a cell" becomes one predicate beside `fieldType` in `Grades.h`/`Layout`, and `getToken` and every box test call it. |
| Deletion | `taken`, the three hand-built result lists, `movedField`, the verifier's hand comparison (replaced by `verifyInferredResultTypes`), the four other spellings of token presence, and the divergent box tests in Stack, Reshape and Reuses. |
| Consumers | `include/idr/IR/IdrOwnershipOps.td`, `lib/IR/OpsOwnership.cpp`, `include/idr/IR/Grades.h` or `Layout.h`, `lib/Transforms/Ownership/Take.cpp`, `Reshape.cpp`, `include/idr/Transforms/Ownership.h` (the take helpers' signatures), `lib/Analysis/Ownership/Reuses.cpp`, `lib/Transforms/Stack/Stack.cpp`, `lib/Analysis/Tail.cpp`, `lib/Transforms/Tail/Trmc.cpp`. |
| Discriminator | A unit box in `foreign/idr/unittests/` builds a take for every (data type, tag) of a small type set, boxed, unboxed, linear and fieldless, and checks that it verifies. Before, `takeAt` on an unboxed sum with fields fails verification; after, it is not expressible. The `tests/rc-arrays/*` fixtures verify after idr-rc. A stage-`first` fixture with a linear box con that does not escape is put on the stack after the fix and not before. |
| Verification here | `make typecheck` (C++ compiles). The unit box and the rc fixtures need the owner's build (`make test-unit`, `make test-idr`). |
| Size and risk | About 45 lines and 14 branch sites go. The risk is low: the inferred list is exactly what the verifier already demands. The essential case stays: an atom has no cell, so its take gives no token. |
| Insight | 6 (parse once: the type is inferred), 4. |

### transforms-b-2: `idr.reuse` is `idr.con` with a cell, held as a second op

| Field | Content |
|---|---|
| ID | transforms-b-2 |
| Evidence | `IdrOwnershipOps.td:128-153` `Idr_ReuseOp` has the same tag, fields, holes, dests, assembly and accessors as `Idr_ConOp` (`IdrOps.td:263-299`), plus `$token`. `OpsOwnership.cpp:42-80` duplicates `getDataType`/`getField`/`getDest`/`build`/`verify`, and `FlowOps.cpp:219` duplicates the flow edges. `Analysis/Tail.h:43` defines `using Built = std::variant<ConOp, ReuseOp>` with the comment "both have the same fields, holes and destinations, so what reads one reads either"; `Tail.cpp:20-39` has `builtBox` with 2 dyn_casts, plus `fieldOf`, `fieldCount` and `opOf` as `std::visit`s. `Tail/Trmc.cpp:85-92` has two `rebuilt` overloads, and L96-107 and L121-122 three more visits. `Ownership/Reuse.cpp:47-69` keeps `rebuiltValues`, `rebuiltOps`, `now<T>`, two `boxOf` and two `pointOf` overloads, only because each site's `idr.con` is replaced by a new op that later sites still name. Further pairs: `isa<ConOp, ReuseOp>` in `Verify/OwnedOps.cpp:127` and `Expect/Does.cpp:36`, branches in `Expect/TestsNothing.cpp:34`, `Expect/ReusesInPlace.cpp:27` and `Rc.cpp:149-150`, a walk in `Demand.cpp:67`, `Verify/Program.cpp:121-126`, and conversion's separate `LowerReuse` (`Conversion/Counting.cpp:60`), `Fields::kept(ReuseOp)` and `Facts.cpp:83`. About 20 branch sites. |
| Counterexample | A pass that rebuilds a constructor must handle both ops or silently drop reuse. Trmc does it with a variant; any new constructor rewrite must remember to. Inside idr-rc, a `Reuses::Site` pointing at an op an earlier site replaced reads a stale pointer unless the remap is consulted. |
| Root cause | Where a box's cell comes from (fresh on the heap, a stack slot, or a taken cell) is a placement parameter of one operation. It is held as a unit attribute (`stack`) on one op and as a separate op for the third case. |
| Correction | `idr.con` takes an optional `$token` operand, the cell it is built in. The verifier holds `token ⇒ box`, `token ⇒ !stack` and `token ⇒ owned stage`. Memory effects, the folder (`token ⇒ no fold`) and speculation (`token ⇒ not speculatable`) read it. The reuse rewrite is `con.getTokenMutable().assign(cell)` in place: no op is replaced, so every `Site` stays valid. |
| Deletion | The `ReuseOp` def and its five methods and flow edges, `Built` and its helpers, Trmc's second `rebuilt` and its visits, Reuse.cpp's two maps, `now`, and the `boxOf(Value)` and `pointOf` overloads, plus every `isa<ConOp, ReuseOp>` pair. `LowerReuse` merges into the con lowering. Its token-or-allocate branch is essential and stays, now in one place. |
| Consumers | `IdrOwnershipOps.td`, `IdrOps.td`, `lib/IR/OpsCon.cpp`, `OpsOwnership.cpp`, `FlowOps.cpp`, `Verify/OwnedOps.cpp`, `Verify/Program.cpp`, `Analysis/Tail.{h,cpp}`, `Analysis/Ownership/Reuses.cpp`, `Transforms/Ownership/Reuse.cpp`, `Rc.cpp`, `Tail/Trmc.cpp`, `Demand/Demand.cpp`, `Expect/{Does,TestsNothing,ReusesInPlace}.cpp`, `Conversion/{Counting,Fields,Facts,Cells}.cpp`, `include/idr/Conversion/Fields.h`, and the fixtures that print `idr.reuse` (`tests/verify-owned-stage`, `rc/*`). |
| Discriminator | `--verify-roundtrip` on the owned-stage fixtures. `tests/rc-nested-reuse` (a site whose box is a constructor an earlier site rebuilt) must keep its reuse count (`idr-rc.reuses` statistic). Trmc on a reusing recursion (`tests/rc-arrays/*` through `idr-trmc`) keeps the reuse. The verifier rejects `token` with `stack`. |
| Verification here | `make typecheck`. The behaviour is owed to the owner's build. |
| Size and risk | About 150 lines and about 20 branch sites go. The risk is medium: the con's effects, folder and speculation must exclude the token case, and the conversion patterns merge. The essential three-way cell source stays, once, in the lowering. |
| Insight | 12 (homogeneous coordinates: "build in cell c" for each source), 7, 16 checked: reuse is not a different operation. |

### transforms-b-3: an `idr.func` body admits several blocks that only an inliner transient makes

| Field | Content |
|---|---|
| ID | transforms-b-3 |
| Evidence | `IdrOps.td:146` declares `region AnyRegion:$body`. The frontend writes one block (`compiler/src/IdrisMLIR/MLIR.idr:422` writes `^bb0` only). The one source of a second block is inlining a callee that ends in `ub.unreachable` into a function body (PINS `inline-unreachable`: "such a callee is inlined into a function body"). It leaves a dead continuation block, and nothing removes it: the idr canonicalizer has region simplification off (`Canonicalize.h:40-46`). In this area: `Ownership/Reshape.cpp:37-46` raises an internal error for a multi-block region, but skips the function body itself (`op != fn.getOperation()`); Placement walks each block on its own and assumes one. `Tail/AccumulatorPlan.cpp:167,215` refuse multi-block functions, a lost optimization; L195 and L201 test `hasOneBlock()` on match regions, which `SizedRegion<1>` (`IdrMatchOps.td:23`) already guarantees (dead). `Optimize/PureCalls.cpp:127-144` walks a dominator tree for multi-block regions. `Bufferize/Releases.cpp:115-128` checks block reachability. `TailLoops.cpp`, `WhileDo.cpp`, `Loop.cpp` and `Trmc.cpp` read `fn.getBody().front()` without a guard. Cross-area: `Inline/Inline.cpp:35-43` (`fitsRegion` keeps such calls out of match regions), `Analysis/EscapesCycles.cpp:73`, `Escapes.h:62`, flow and linearity through branches, and `tests/defunc-choice/block-argument.mlir`, the one fixture with `cf.cond_br`. About 12 branch sites, one silent assumption in four passes, and one internal error. |
| Counterexample | Take a function that inlines a crashing callee at the top level. Its dead continuation survives into idr-accumulate, which then leaves it unaccumulated, and into idr-rc, whose placement places that block's values per block, unchecked. `Reshape::check` accepts it. |
| Root cause | The body allows any number of blocks, though every producer but one transient makes one. The transient's continuation is dead by construction (the callee never returns) and is not removed where it is made. |
| Correction | `idr.func`'s body is `SizedRegion<1>`. The inline step (`Inline.cpp` `inlineCalls`, `Contify.cpp`) erases the continuation it makes dead (`mlir::eraseUnreachableBlocks` on the caller's body) before the pass ends. A body is then one block by construction. Calls of non-returning callees in match regions can then inline too. |
| Deletion | `Reshape::check` and its internal error; the four `hasOneBlock` tests in AccumulatorPlan; PureCalls' dominator-tree path; `mayRunAfter`'s block-reachability tail; `fitsRegion`'s multi-block case; EscapesCycles' multi-block case; flow and linearity through block arguments of non-entry blocks (IR area); `block-argument.mlir`. |
| Consumers | `include/idr/IR/IdrOps.td`, `lib/Transforms/Inline/Inline.cpp`, `Optimize/Contify.cpp`, `Ownership/Reshape.cpp`, `Tail/AccumulatorPlan.cpp`, `Optimize/PureCalls.cpp`, `Bufferize/Releases.cpp`, `Analysis/EscapesCycles.cpp`, `Analysis/Escapes.h`, `lib/IR/Flow.cpp`, `Verify/Linearity.cpp`, `tests/defunc-choice/block-argument.mlir`, PINS.md `inline-unreachable` (its sites text). |
| Discriminator | The verifier rejects a two-block `idr.func`. A fixture inlines a crashing callee at the top level and runs idr-optimize: after the fix the body verifies as one block and a following `idr-accumulate` fires; before, the body has two blocks. |
| Verification here | `make typecheck`. The inliner behaviour is owed to the owner's build (`make test-idr`, `make test-mlir-tools`). |
| Size and risk | About 60 lines and 12 branch sites in this area; more across the IR. The risk is medium: this touches the inliner and the PINS-recorded patch 07, whose own behaviour stays, and the erase happens after it. What stays essential: a crash ends its block with `ub.unreachable`. |
| Insight | 4, 6 (the invariant made at its one source), 8. |

### transforms-b-4: returned-arguments walks `scf` ops by kind where `RegionBranchOpInterface` names the predecessors

| Field | Content |
|---|---|
| ID | transforms-b-4 |
| Evidence | `Tail/Returned.cpp` `resultOf` L92-125 is a ladder: poison, `scf::IfOp`/`IndexSwitchOp` with an empty-region case, `arith::SelectOp`, `scf::WhileOp` (result to condition args), `scf::ForOp` (result to iter args), `func::CallOp`, and a default. `argumentOf(BlockArgument)` L127-146 covers the entry, the hypothesis, the while after-body, the while before-body (carried), and the for body with a separate `index == 0` case for the IV. That is 11 cases, 6 of them one rule ("a region-branch value is the join of what flows into it"). The pinned MLIR has `RegionBranchOpInterface::getPredecessorValues` (`ControlFlowInterfaces.td:305`). The owned verifier already reads regions this way ("No op is known by its kind", `Verify/OwnedRegions.cpp:9`). |
| Counterexample | Any other region branch on lowered code (`scf.execute_region`, an op a later pass makes) is "no one argument". The result is silently kept, never wrong but never dropped, and each new op costs two more cases here. |
| Root cause | The analysis names op kinds instead of asking the interface they all implement. |
| Correction | A value that is a successor input of a `RegionBranchOpInterface` op (a result, or a region argument; the scf.for IV is not one) is the join of `getPredecessorValues` over its index. The hypothesis map (`assumed`) applies to every region argument on a cycle. Poison (bottom), select and call stay their own cases. |
| Deletion | The `IfOp`/`IndexSwitchOp`, `WhileOp`×2 and `ForOp`×2 cases, the IV special case, and the empty-region case. |
| Consumers | `lib/Transforms/Tail/Returned.cpp`. |
| Discriminator | `tests/returned-threaded/` is empty today, so a fixture is owed. Lowered functions thread an argument through an `scf.if`, an `scf.while` and a recursive call, and the property is `idr-returned-arguments.dropped` equal to the number of such results, with each caller using its argument. A second case threads it through `scf.execute_region`: dropped after the fix, kept before. |
| Verification here | `make typecheck`. The fixtures are owed to the owner's build. |
| Size and risk | About 30 lines and 7 branches go. The risk is low to medium: termination still rests on the hypothesis. What stays essential: poison as bottom, select's two arms, and a call read through the callee's solution. |
| Insight | 7, plus MLIR mechanism first. |

### transforms-b-5: idr-rc lowers linalg loops over counted elements that no pass makes

| Field | Content |
|---|---|
| ID | transforms-b-5 |
| Evidence | `Ownership/Buffers.cpp:30-52` (`loopCountedElements`) turns every buffer-semantics `LinalgOp` whose payload holds references into `scf.for` loops, with an internal error, and erases the unread counted loads that lowering leaves. The `Passes.td:511-517` comment and dependent dialects (affine) exist for it, as does the `bufferForms` doc (`Ownership.h:149-156`). The only linalg producer before idr-rc is idr-structure-loops. Its contract (`Passes.td:369`, "No array of non-word elements reaches linalg") holds by construction: `Forms.cpp:160` (transpose of words only), `overWords` (L78-93), and `readsOf` requiring word reads (L139). Bufferization copies with `memref.copy` (no `memCpyFn` set in `Bufferize.cpp`). No `tests/rc-arrays` fixture holds a linalg op. That is 1 dead path with 3 branches and 1 internal error. |
| Counterexample | None reachable. The fallback guards a state another pass's contract excludes, and nothing states that contract as a check. |
| Root cause | idr-structure-loops' guarantee is prose, so idr-rc keeps a fallback for its violation. |
| Correction | The program verifier holds the guarantee from stage `first` on: a `linalg` op inside an `idr.func` has no payload argument that holds references. idr-rc trusts it. |
| Deletion | `loopCountedElements` and its internal error, the unread-load erasure, the affine dependency and comment in `IdrRc`, and the corresponding sentence of `bufferForms`' doc. |
| Consumers | `lib/Transforms/Ownership/Buffers.cpp`, `include/idr/Transforms/Ownership.h`, `include/idr/Transforms/Passes.td` (IdrRc), `lib/IR/Verify/Program.cpp`. |
| Discriminator | A fixture with a `linalg.generic` over a buffer of `!idr.str` at stage `first` is rejected by the verifier. All `tests/structure-columns/*` and `tests/rc-arrays/*` fixtures still verify. |
| Verification here | `make typecheck`. |
| Size and risk | About 25 lines and 4 branches go. The risk is low, provided the frontend emits no linalg (confirmed: `compiler/src` has none). Nothing essential is lost. |
| Insight | 6 (parse at the boundary, once). |

### transforms-b-6: the stage a pass runs at is prose, checked by hand in 2 passes

| Field | Content |
|---|---|
| ID | transforms-b-6 |
| Evidence | `Ownership/Rc.cpp:62-66` checks `Stage::First` and raises an internal error; `Effects/Effects.cpp:31-34` refuses `Stage::Higher`. No other pass checks: idr-defunctionalize sets `first` without checking `higher` (`Defunctionalize/Pass.cpp:140`), idr-lower sets `lowered` without checking `owned` (`Conversion/Lower.cpp:227`), and idr-demand, idr-trmc and idr-tail-loops rely on `owned`. Their stage is a sentence in `Passes.td` (L180, L470, L534). Roles are already data (`Passes.td:37-48`, `-gen-pass-roles`). |
| Counterexample | `idris-mlir-opt --idr-demand` on a `first`-stage program reads grades that are not there yet and reports nothing. `--idr-rc` on an owned program is caught only because Rc checks for itself. |
| Root cause | A pass's precondition and postcondition on the program's stage are not data. The pipeline's order encodes them, and they are re-checked by hand in two places. |
| Correction | `IdrPass` takes `requires` and `sets` stage records (an `IdrStage` class with the four stages and `any`). `idris-mlir-tblgen` emits them beside the roles. One instrumentation installed by both tools checks, before each idr pass on a program, its stage against `requires`, and reports an internal error naming the pass. A spec test checks that each pass's `requires` in `buildPipeline` order is the stage the previous pass `sets`. |
| Deletion | The two hand checks and the stage sentences in the descriptions (generated instead). |
| Consumers | `include/idr/Transforms/Passes.td`, `tools/idris-mlir-tblgen` (pass-roles generator), `lib/Transforms/Ownership/Rc.cpp`, `lib/Transforms/Effects/Effects.cpp`, the tools' setup (`tools/idris-mlir-opt.cpp`, `lib/Driver/Run.cpp`), `tests/spec/*` (new spec). |
| Discriminator | `--idr-demand` on a `first`-stage fixture now errors. The spec fails if two pipeline passes are reordered across a stage change. |
| Verification here | The TableGen generator and the spec run under `make typecheck` and `make check`. |
| Size and risk | 2 hand checks go and about 10 implicit preconditions become checked. The risk is low. |
| Insight | 14 (control as data), 6. |

### transforms-b-7: grade specialization erases dead copies with its own reachability walk

| Field | Content |
|---|---|
| ID | transforms-b-7 |
| Evidence | `Ownership/Specialize.cpp:141-168` (`eraseUnused`) builds a `SymbolUserMap`, a once-worklist and a kept set over originals and copies; it is called at `Rc.cpp:112`. A function's visibility is derived, public only for the root (`IdrOps.td` FuncOp description), so that upstream symbol walks drop unused functions, and idr-optimize does exactly that with symbol-dce (`Optimize/Optimize.cpp:110-119`). |
| Counterexample | A copy only another dead copy calls is handled by the hand walk's own rules. symbol-dce already covers it. |
| Root cause | A hand-written mechanism where the tree's own convention, a derived visibility, gives the upstream one. |
| Correction | After `redirectCalls`, idr-rc runs `createSymbolDCEPass()` nested on the program, as idr-optimize does. |
| Deletion | `eraseUnused` and its declaration (`Ownership.h:84-86`), and `Copies` as its parameter. |
| Consumers | `lib/Transforms/Ownership/Specialize.cpp`, `Rc.cpp`, `include/idr/Transforms/Ownership.h`. |
| Discriminator | `tests/rc-exclusive` and `second-redirect` keep the same functions after the pass. A spec-style property: after idr-rc, every function is reachable from the root. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines and 4 branches go. The risk is low: in the pipeline nothing else is unreachable at idr-rc. A standalone `idris-mlir-opt --idr-rc` on a fixture with an unreachable function would now drop it. |
| Insight | Library first; 13. |

### transforms-b-8: the ordered tabulation threads an optional world through seven flag tests

| Field | Content |
|---|---|
| ID | transforms-b-8 |
| Evidence | `StructureLoops/Nests.cpp` `tabulated(..., std::optional<Value> world)` L50-190: `withWorld` (L56-61), `initial` (L62), and `if (world)` at L64, L75, L100, L117, L134 and L169. `lowerOrdered` (L283-290) has two cases that differ only in passing `std::nullopt` or `t.getWorld()`. That is 7 branches. |
| Counterexample | A path that forgets one test (an args list without the world) passes a tabulation's region one value too few. Each new carried value would be another optional. |
| Root cause | The world is the one carried state of `idr.tabulate_io` and none of `idr.tabulate`, held as an optional rather than as a range that may be empty. |
| Correction | `tabulated` takes `ValueRange state` (empty for `idr.tabulate`, `{world}` for `idr.tabulate_io`) and always appends `state` and `carried.take_back(state.size())`. |
| Deletion | `withWorld`, `initial`, the 6 `if (world)`, and the duplicated `.Case`. |
| Consumers | `lib/Transforms/StructureLoops/Nests.cpp`. |
| Discriminator | Programs in `tests/programs` with an IO tabulation keep their output. `idr-expect` `structured-loops` holds on `tests/structure-columns/*`. |
| Verification here | `make typecheck`. |
| Size and risk | About 20 lines and 7 branches go. The risk is low. |
| Insight | 8 (the empty range as the null object). |

### transforms-b-9: the ordered tabulation tests every iteration for the first and special-cases rank 0

| Field | Content |
|---|---|
| ID | transforms-b-9 |
| Evidence | `StructureLoops/Nests.cpp`: a rank-0 special case (L66-79). In the dynamic-cell path, `count` starts from `extents.front()` (L129-131), which is undefined at rank 0. Each iteration builds an `atFirst` and-chain over all IVs (L155-159) and an `scf.if` (L160-173) that yields the precomputed first cell or runs a second `cloneRegion` (L171). That is 3 branches, a per-iteration test, and a duplicated region. |
| Counterexample | A rank-0 tabulation of dynamically sized cells would read `extents.front()` of an empty list if the special case were removed. Every iteration of a large domain pays the and-chain. |
| Root cause | Two coordinate choices: the domain's size starts at its first extent instead of the empty product 1, and the domain is walked as a closed nest with a sentinel test instead of the half-open rest `[1, count)` after the first cell. |
| Correction | `count` is the product of the extents from constant 1. Under `count != 0` (essential: an empty domain has no first cell), the first cell is made and written at the zero index, then one `scf.for` over linear `k ∈ [1, count)`, with `affine.delinearize_index` giving the row-major indices, runs the moved region. At rank 0 the loop is empty. |
| Deletion | The rank-0 block, the per-iteration and-chain, the inner `scf.if`, and the second region clone. |
| Consumers | `lib/Transforms/StructureLoops/Nests.cpp`. |
| Discriminator | A program tabulating arrays of dynamically sized cells (rank 0, 1 and 2, including an empty domain) gives the same output, and the first cell is still the first written. `idr-expect` `structured-loops` holds. |
| Verification here | `make typecheck`. |
| Size and risk | About 35 lines and 3 branches go, plus one region clone. The risk is medium: delinearization costs a div/rem per iteration on this path. Each step there already allocates a cell, so the trade is likely favourable, but the owner's bench decides. What stays essential: `cellsKnown` (whether the shape is known before the region runs) and `count != 0`. |
| Insight | 11 (half-open), 8 (no sentinel test), 12 (empty product). |

### transforms-b-10: the callee-effects table is bound when the pipeline is built, so function passes go without it or rebuild it

| Field | Content |
|---|---|
| ID | transforms-b-10 |
| Evidence | `Pipeline.cpp:57,87`: the in-program canonicalizers get `createCanonicalizerPass(nullptr)` ("built before any program exists"), so to them every call may do anything. A pure call left dead by idr-columns then survives (conjecture: remove-dead-values keeps an op that declares effects, as `idr.call` does). Meanwhile `StructureLoops/StructureLoops.cpp:52` builds `SymbolTable symbols(getOperation()->getParentOp())` once per function that holds an array op: O(functions) each, and a sibling read from a nested pass. idr-rc already holds the table for its nested runs (`Rc.cpp:85-89`, `Place.cpp`), and idr-optimize holds it for its inner pipeline (`Optimize.cpp:82`). One question, "may a function pass in the program read callees' effects?", gets three answers. |
| Counterexample | On the self module (58,236 functions), each function holding an array op inserts every symbol of the program again. |
| Root cause | `CalleeEffects` is a constructor argument, which can only be null at pipeline-build time, instead of a table the enclosing program pass takes at run time. |
| Correction | One helper beside `runNested` in `Rc.cpp`: a program pass that takes `CalleeEffects{getAnalysis<SymbolTable>()}` and runs function passes nested with it. idr-structure-loops anchors on the program and uses it, as do the in-program canonicalize/CSE groups. The thread-safety argument is idr-rc's: no nested pass writes another function's `effects`. |
| Deletion | The per-function `SymbolTable` in StructureLoops, and the null table for in-program canonicalizers. The null mode remains only for `--idr-canonicalize` run outside a program. |
| Consumers | `lib/Transforms/Pipeline.cpp`, `lib/Transforms/StructureLoops/StructureLoops.cpp`, `include/idr/Transforms/Passes.td` (IdrStructureLoops anchor), `include/idr/Transforms/Canonicalize.h` (other surveyor's area). |
| Discriminator | Compile-time profile of a module with many array functions (Tracy zones). A fixture where idr-columns leaves a dead pure call: erased after, kept before. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines; the gain is complexity and compile time. The risk is low. |
| Insight | One fact, one place; 6. |

### transforms-b-11: while-do's three scopes are a tag switched twice

| Field | Content |
|---|---|
| ID | transforms-b-11 |
| Evidence | `Tail/WhileDo.cpp:48` defines `enum class Scope { Before, After, Exit }`. `blockOf` (L73-83) is a switch plus `llvm_unreachable`; `in` (L85-109) is a switch plus `llvm_unreachable`, plus the special case `scope == Scope::Before` for passed values (L96). That is 2 switches (6 cases), 2 unreachables and 1 special case. |
| Counterexample | A fourth scope needs two more switch arms and a decision about the special case. |
| Root cause | A scope is a block and the values its slots map to. The tag forces a switch to recover both. |
| Correction | `struct Scope { Block *block; ValueRange values; }`, built once the loop exists: before = (before body, before arguments), after = (after body, after arguments), exit = (loop's block, loop results). `in` returns `slot < scope.values.size() ? scope.values[slot] : value`. The before region has only the carried slots, so passed values fall through without a special case. |
| Deletion | Both switches, both unreachables, and the `Before` special case. |
| Consumers | `lib/Transforms/Tail/WhileDo.cpp`. |
| Discriminator | `tests/loops-accumulate/*` keep their loops and counted statistic (`idr-tail-loops.loops`, `.counted`). |
| Verification here | `make typecheck`. |
| Size and risk | About 20 lines and 9 branch points go. The risk is very low. |
| Insight | 7, 11 (the coordinate makes the special case the rule). |

### transforms-b-12: placement's `Class` conflates outcomes its consumers re-split with predicates

| Field | Content |
|---|---|
| ID | transforms-b-12 |
| Evidence | `Ownership.h:99` defines `enum class Class { Untracked, Static, Borrowed, Owned }`. `Placement.cpp` `plan()` (L96-129) splits `Static` again: `phantom()` makes it owned (L109-112), `!readFrom && def && !hasTrait<ResultCarriesOperand>` makes it a view (L113-114), and anything else stays a static read. It splits `Owned` again: `if (readFrom(value)) return;` means a field that ownFields already dup'd (L125-126). `Reshape.cpp` `ownFields` selects `readFrom(x) && classOf(x) == Owned` twice (L137, L141). That is 4 enum cases but 6 outcomes, 5 re-splitting predicates, and one meaning of `Owned` in reshape ("needs its own reference here") and another in placement ("took it already"). |
| Counterexample | Nothing stops a value classed `Owned` with a `readFrom` source from being taken by a future consumer as a fresh owned value. It would be dropped twice: once through its own placement, once through the dup. |
| Root cause | The enum names liveness classes, not the placement decisions made from them. |
| Correction | `Class` names the outcome: `Untracked`, `Phantom` (owned by type, never counted), `Constant` (a view; each consumer dups), `StaticRead` (keeps its grade), `Borrowed`, `OwnedAtRead` (a field or element that takes its own reference where it is read; ownFields' dup), `Owned`. `classOf` decides each once. `plan()` becomes a flat switch, and ownFields selects `OwnedAtRead`. |
| Deletion | The 5 re-splitting predicates in `plan()` and ownFields. |
| Consumers | `include/idr/Transforms/Ownership.h`, `Ownership/Classes.cpp`, `Placement.cpp`, `Reshape.cpp`. |
| Discriminator | Every `tests/rc-arrays/*` fixture verifies after idr-rc (the owned walk) with unchanged `dups` and `drops` statistics. |
| Verification here | `make typecheck`. |
| Size and risk | 5 branches move into one place. The risk is medium (counting). What stays essential: phantom and constant differ (no dup versus a dup that runs nothing). |
| Insight | 4, 7. |

### transforms-b-13: fold and scan share accessors that lowering recovers with casts

| Field | Content |
|---|---|
| ID | transforms-b-13 |
| Evidence | `StructureLoops/Linalg.cpp:155-158`: `bool scan = isa<ScanLastOp>(op)` and three `scan ? cast<ScanLastOp>(op).getX() : cast<FoldLastOp>(op).getX()` ternaries (inits, length, frame rank). `Nests.cpp:196-254` is the template `folded<OpT>`, instantiated twice. `StructureLoops.cpp:31` has `cast<FoldLastOp>` for `Form::Reduction`. `IdrArrayOps.td:141-175` gives both ops identical arguments, results and assembly, and the `Idr_FoldsAnAccumulator` trait. That is 3 ternaries (6 casts) and 1 cast guard. |
| Counterexample | A third last-axis op would need a fourth arm in every ternary. |
| Root cause | The shared accessors are not an interface. |
| Correction | An op interface on the `Idr_FoldsAnAccumulator` ops: `getInits`, `getLength`, `getFrameRank`, `getAccumulators`. `lowerInterchange` and `folded` take it. |
| Deletion | The ternaries and the template's second instantiation. |
| Consumers | `include/idr/IR/IdrInterfaces.td`, `IdrArrayOps.td`, `lib/Transforms/StructureLoops/{Linalg,Nests}.cpp`. |
| Discriminator | `tests/structure-columns/*` unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines and 4 branch points go. The risk is low. What stays essential: the scan writes each step's accumulators (`if (scan)` remains). |
| Insight | 7. |

### transforms-b-14: an optimizer node's lifecycle is three fields and a step kind

| Field | Content |
|---|---|
| ID | transforms-b-14 |
| Evidence | `Optimize.h:138-171` holds `state` (Waiting/Parked/Done), `std::optional<Solved> solved` and `std::optional<Summary> published`. `Waves.cpp:217-220` (finalize) dereferences `*member->solved` and resets it. `ReadySet.cpp:119` has `node->solved ? .. : nullopt`. `Component.cpp:238-246` writes `solved` while the state is Waiting, and L255 sets Done before running. `Waves.cpp:104` (gather) re-derives start or resume from `state` after discarding the `Step` alternative that said it (L88-90). `Waves.cpp:60` skips the empty husk a merge leaves. That is 4 checks and invalid combinations Waiting+solved and Parked-without-solved. |
| Counterexample | A node that is Parked with no `solved` is representable; `givesBack` then answers "nothing". |
| Root cause | Solved belongs to the states the turn writes, but it is held beside them. |
| Correction | The turn-written state is `Waiting \| Parked{on, Solved} \| Done{Solved}`. `published` stays a separate field, written only between waves: workers read `isFinal` of nodes whose turn may be writing its state, which is the essential reason for the split. gather splits by the `Step` alternative, and a merge erases the merged-away `Scc`. |
| Deletion | The `std::optional<Solved>`, the deref, the `solved ?` test, gather's state test, and the husk skip. |
| Consumers | `include/idr/Transforms/Optimize.h`, `lib/Transforms/Optimize/{ReadySet,Component,Waves}.cpp`. |
| Discriminator | `tests/optimize-caller-cap/*` and the determinism check at 1, 3, 5 and 13 threads. |
| Verification here | `make typecheck`. |
| Size and risk | 4 branches go. The risk is low. |
| Insight | 4, 5. |

### transforms-b-15: addition's identity lives in idr-accumulate, not in `idr.big.add`

| Field | Content |
|---|---|
| ID | transforms-b-15 |
| Evidence | `Tail/Accumulate.cpp:105-110`: a tail returning literal zero gets the sum directly (`isZero`) instead of `acc + 0`. `BigAddOp::fold` (`IR/Fold/Bigs.cpp:23-25`) folds only constant pairs. That is 1 branch plus an erase of the dead definition. |
| Counterexample | Every other pass that builds `x + 0` keeps it. |
| Root cause | `x + 0 = x` is a fact of the op, held in one pass. |
| Correction | `BigAddOp::fold` returns the other operand when one is the constant 0. Accumulate builds with `createOrFold`. |
| Deletion | The `isZero` branch in `rewriteClone`. `isZero` itself stays for `isCountdown`. |
| Consumers | `lib/IR/Fold/Bigs.cpp`, `lib/Transforms/Tail/Accumulate.cpp`. |
| Discriminator | `tests/fold-add-zero/*` gets an `x + 0` case. The accumulate fixtures are unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | 1 branch goes. The risk is very low. |
| Insight | One fact, one place. |

### transforms-b-16: a terminator is rebuilt by kind to change its operands

| Field | Content |
|---|---|
| ID | transforms-b-16 |
| Evidence | `Tail/Trmc.cpp:72-80` (`endWithNothing`) re-creates `ReturnOp` or `YieldOp` with no operands. `Tail/Loop.cpp:62-70` (`end`) re-creates a `YieldOp`. Both ops are a variadic operand list. That is 2 isa branches. |
| Counterexample | A third tail terminator would need a third arm. |
| Root cause | Rebuilding instead of changing operands in place. |
| Correction | `modifyOpInPlace(t, [&]{ t->setOperands(values); })`. The one essential change of kind stays: `idr.return` becomes `scf.condition` in Loop. |
| Deletion | The two isa branches. |
| Consumers | `lib/Transforms/Tail/{Trmc,Loop}.cpp`. |
| Discriminator | The trmc and tail-loop fixtures are unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | 2 branches go. The risk is very low. |
| Insight | 7. |

### transforms-b-17: placement asserts a flow rule and then handles its violation

| Field | Content |
|---|---|
| ID | transforms-b-17 |
| Evidence | `Ownership/Placement.cpp:226-229`: `assert(!terminator)` immediately followed by the same `if (terminator) return;`. Release builds silently skip a drop, which leaks. |
| Counterexample | A terminator whose flow did not consume a reference operand would leak in release and abort in debug. |
| Root cause | "A terminator takes over every reference it passes on" is a property of the flow interface, which nothing checks where flow is declared. |
| Correction | `verifyFlow` (or the owned walk) rejects a terminator operand that holds references and is not consumed. Placement keeps the assert only. |
| Deletion | The defensive `if`. |
| Consumers | `lib/Transforms/Ownership/Placement.cpp`, `lib/IR/Flow.cpp` or `Verify/Owned*.cpp`. |
| Discriminator | A fixture with a test op declaring a non-consuming terminator operand is rejected by the verifier. |
| Verification here | `make typecheck`. |
| Size and risk | 1 branch goes. The risk is very low. |
| Insight | 6. |

## Judged essential, kept

- **The four ownership vocabularies.** Each answers a different question:
  - the `Permission` grade (`plain`, `borrow`, `own`, `excl`) in the type;
  - `Borrows::Param`, a parameter's decision; `view` is `borrow` for our types and `plain` for builtin buffers, so it is not a permission;
  - `Exclusivity::Sharing`, the solver's lattice;
  - `Use`, what an operand does.
- **`isStatic` as provenance**, not a grade. A static grade would need a conversion at every owned boundary.
- **Commit's `meet`.** Three real cases on (permission, permission): share, poison on an unreached path, and error.
- **`consumes(operand, callees)`'s two modes.** Inside idr-rc a call's operands have not yet taken their parameters' grades. The state is transient within one pass (IR area).
- **Placement's `keep` flag and its split between deciding and non-deciding ops**, derived from `RegionBranchOpInterface` through `verify::alternatives`, held once.
- **Loop.cpp's payload `(continue, A, R)` with poison.** `scf.while` carries a flat tuple, so this is the essential encoding of a sum.
- **Trmc's first level against its clone (the optional hole).** The first level must return its cell. A sentinel destination would mean a new cell and counts after idr-rc: more machinery than the one branch it would save. Accumulate's seeding with zero already uses the identity coordinate.
- **`isCountdown`.** An algorithmic case (n steps against none), not a representation one.
- **`runMember`'s fixed last step.** Termination by a fixed sequence, as AGENTS.md requires.
- **`Node::published` separate from the state.** Required for race freedom between waves.
- **idr-pure-calls as its own CSE.** Decided by the representation wave (D13, its §11): calls hold no effects.
- **Constants.cpp's copy of SCCP's rewrite.** Upstream's `rewrite` and `replaceWithConstant` are file-static, and the actions need a hook per replacement. This is not a bug, so it gets no patch.
- **Bufferize's match and yield models.** Upstream has no generic region-branch model. The `underOneShot` internal errors are correct: a One-Shot failure is the compiler's.
- **`copyName`'s collision internal errors (Tail, Specialize).** MLIR symbols are strings, and content names make a collision a compiler bug. Uniquifying would let order reach names.
- **WhileDo's `continues()` flag folding.** Upstream arith folds lack `extui(x)==1` and the inversions of `x:i1 == 0`.
- **`Form` and its two switches.** A closed set decided once, with the switch as its evaluator. Elements kept by `moveElementsOut`'s `leaves` (0 or 1 outs) are essential.
- **The stack size budgets.** Policy, never acceptance.
- **The `nullptr` canonicalizers after lowering.** The bodies there hold no `idr.call`.
