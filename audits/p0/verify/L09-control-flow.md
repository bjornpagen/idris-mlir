<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L09: control flow: regions, join points, upstream's early exit

Lane L09 of the P0 verification swarm. Rulings in scope: D18, D19, D25,
D30 (a jump is a tail transfer), D10 (as it bears on control flow). HEAD
`e96bb991` at the start (2026-10-21T21:31Z) and at the finish (checked
again before writing, 2026-10-21T22:00Z). Nothing was built, run or
typechecked. The only commands with outputs were reads, `gh pr view` and
`gh pr diff` of PR #166688, and `git apply --check` and `patch --dry-run`
of that diff against *copies* of the pin's files in a scratch directory
outside the repository (§1.3.3). Paths without a prefix are relative to
the checkout; `idr/` abbreviates `foreign/idr/`; `pin/` abbreviates
`.toolchain/llvm-project/` (MLIR at 7208ba24, 2026-10-08); "the PR" is
llvm/llvm-project#166688 at head `968e49b1`.

Read in full: the representation-first skill, `AGENTS.md`, the proposal,
`audits/p0/design/match-and-counting.md`, the PR's description and whole
diff (5,152 lines). Read by section: 03 §5.2 and its rows O-9, O-12,
O-13, O-16, O-44, O-50, O-52, O-56; 04 §3.2, §4 rows C06 to C09, C25,
C60, §5 T3 to T7; 10 §4.4, §4.6, §4.8, §5 D1, D4, D5, D8, D9; §5.1 C1 to
C4; §5.4 F7; §5.9 C3, E1 to E3; synthesis A §5.8; the sibling files
L05 (§2.5 rule 8, its seam table) and L14 (§2.1) for the two seams they
fix. Code read: `idr/include/idr/IR/IdrMatchOps.td`, `IdrOps.td`
(operand constraints), `IdrCheckOps.td:42-50`; `idr/lib/IR/OpsMatch.cpp`,
`Regions.cpp`, `Tail.cpp`, `Flow.cpp:30-115`, `OpsConReads.cpp:100-190`,
`Verify/Linearity.cpp:20-135`, `Canon/CaseOfCase.cpp`, `Canon/Eta.cpp:39-73`;
`idr/lib/Transforms/Optimize/Contify.cpp` (the dispatch names
`Transforms/Inline/Contify.cpp`; the file is under `Optimize/`),
`Tail/{TailLoops,Loop,WhileDo,Trmc}.cpp`; `idr/lib/Conversion/Matches.cpp`,
`Lower.cpp:110-150`, `idr/lib/Transforms/Pipeline.cpp:60-190`; MLton's
`ssa/contify.fun` (`sources/code/mlton`). At the pin:
`ControlFlowInterfaces.{td,h,cpp}`, `RegionKindInterface.*`,
`Dominance.cpp`, `Verifier.cpp:30-200`, `SideEffectInterfaces.cpp:43-110,
300-342`, `DeadCodeAnalysis.cpp:440-560`, `SparseAnalysis.cpp:130-360`,
`InliningUtils.cpp`, `SCFToControlFlow.cpp:295-460`, `SCF.cpp` (the
hunks the PR touches), `SCFOps.td:1172-1178`, `BuiltinTypes.td:1262-1280`,
`CommonTypeConstraints.td:160-180`, `OpBase.td:95-106`,
`OpDefinition.h:770-800`, `OpDefinitionsGen.cpp:4035-4066`,
`StructuralTypeConversions.cpp:195-270`, `UBOps.td:73`.

## 1. Verification

Each claim: **holds**, **holds with a correction**, or **refuted**, with
its ground and one class: *defect* (confirmed in the source),
*incomplete* (structural incompleteness), *mismatch* (integration
mismatch), *unverified* (behaviour not run), *simplification* (optional).

### 1.1 D18: the lossless representation at every point

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| A form that loses a known fact is used only for a stated performance reason, after the fact is carried elsewhere. | **holds as a target; violated today in four places of this area** | (1) The match drops the refined constructor and three walks rebuild it, each with its own identity rule (*read*: `OpsMatch.cpp:78-94` looks through linear positions; `OpsConReads.cpp:123-138` requires the value itself; `Canon/Eta.cpp:39-47` looks through linear positions). (2) The general tail loop turns "this path continues" into a run-time `i1` beside poison halves (*read*: `Tail/Loop.cpp:7-14, 43-58`). (3) The lowering turns a crash arm into a yield of poison (*read*: `Conversion/Matches.cpp:30-37`), losing "this region never returns" at the MLIR level (LLVM still sees the runtime's no-return call, so no run-time cost, *conjecture*). (4) `Contify.cpp:34-42, 119-121` leaves a second block in a function body before the lowering, a CFG form D19 forbids. | defect (1, 2); simplification (3); defect (4) |
| Join points are "a third shape, between regions and blocks". | **holds** | They keep each match's single entry and its canonical rejoin and add a continuation shared by sites that are not siblings (match-and-counting §2, §3). `lift-cf-to-scf`'s multiplexer is upstream's proof that regions alone pay a run-time selector for that sharing (*read* there, `CFGToSCF.cpp:1-100`). | — |

### 1.2 D19: regions, join points, blocks only at the lowering

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| A match is a region per case, each a single-entry, single-exit scope rejoining at the op's results, from the frontend to the lowering. | **holds with a correction** | Under D25 a case region can also end in a jump, which leaves the match without rejoining it, or in `ub.unreachable`. Exact wording: a case region is single-entry, and it ends in exactly one of three ways: it yields to the match's results, it jumps to an enclosing join point, or it never ends. L13's closed sum `Yields \| Stops \| Jumps` (L13 §2) is this. | mismatch (wording) |
| A join point is "a named continuation local to its function, jumped to with typed arguments (grades and reuse tokens among them), never an allocated closure". | **holds with three corrections** | (a) It is named by an SSA token that its op defines, not by a name. (b) The join point's typed arguments must include erased, quantity-0 index and lifetime arguments (§2.4). Without them a recursion whose type index changes per step (`go : Vect k a -> ...` called at `k - 1`) cannot be a join point: the jump's argument type `Vect (k-1)` differs from the parameter's `Vect k`. (c) "Never an allocated closure" holds only if the token cannot escape. The proposal's `!idr.cont<...>` does not make escape unrepresentable (§1.3.4, I1); upstream's builtin `token` does. | incomplete (b); mismatch (c) |
| "A linear, non-escaping continuation called in tail position ... is a join point." | **holds with a correction** | Linearity gives "applied at most once per path", not "non-escaping". A linear `k` stored in another closure, passed to a call, or returned escapes (match-and-counting §9, last paragraph, *read*). Formation is decided by escape and tail position. Linearity is not a formation condition: a non-linear continuation applied in several tail positions is also a join point (GHC does not require linearity, *recalled*). Linearity adds a counting fact: each argument is moved, never duplicated (§3). The producer and every application must sit in one function, and only inlining makes that true for a continuation passed as an argument (§9 of the same document). So formation is an optimization, not something read off the program as written (owner question Q1). | mismatch |
| "A local tail call contification finds" is a join point. | **holds; 10 C-1's "essential" premise is refuted** | `Contify.cpp:10-13` says a second call site "would need a branch out of a match region into a block they share, which a structured body cannot hold". 10 C-1 kept that as essential under regions. With join points the shared target is a join region and each call a jump, so Fluet and Weeks's full analysis applies on regions (§2.5). | — |
| A recursive join point is a loop. | **holds; the encoding needs one more op** | A join region re-entered from inside itself is a natural loop once lowered. Repetition differs from a non-recursive join in what the op may do: its regions may run many times, and in partial code it may diverge. By "one op per semantics" (AGENTS.md) that difference is an op, `idr.loop`, beside `idr.join` (§2.1, I2). | incomplete |
| Blocks only at the lowering, through upstream's `convert-scf-to-cf`. | **holds with a correction** | Matches lower to `scf.index_switch` and through upstream's pass (*read*: `Conversion/Matches.cpp:75-104`; `Pipeline.cpp:186`). The join ops are ours, so upstream's pass cannot lower them. Their lowering is a pattern of ours, run in the same conversion as upstream's patterns, as the PR's `LoopOpLowering` is (§2.8). A jump nested in a match reaches it only if `scf.index_switch` carries exits, which the PR does not give it (U5). | incomplete |
| The rationale: regions keep the scopes counting reads; blocks would drop them. | **holds** | match-and-counting §2's table, read against Lean, Koka and MLton there. The counting detail is L07's. | — |

### 1.3 D25: upstream's early exit, carried as a patch

#### 1.3.1 The PR as it stands (*measured*: `gh pr view 166688 -R llvm/llvm-project --json ...`)

- Open. Created 2025-11-06. Two commits; the last committed 2026-07-22T10:51Z, the PR updated 2026-07-22T11:14Z. 3,965 lines added, 202 deleted, 44 files. Every review is `COMMENTED`: there is no approval. The latest review round (Matthias Springer, 2026-06-12 to 06-15) asks about API shapes. One request: `getRegionBranchSuccessorOwner` should return `SmallVector<RegionBranchOpInterface>`. So names and signatures may still move.
- D25's "about 2,000 outside tests": **holds with a correction**. 1,700 lines are added outside paths containing `/test/` (including about 85 lines of LangRef), and 2,265 inside them (*measured*: awk over the diff, counting `+` lines per file).
- D25 names `Verifier.cpp` among the changed files. **Correction:** the PR adds one `#include` there. The check that a breaking terminator crosses only propagating ops is per dialect, in each terminator's own verifier (PR `SCF.cpp`, `verifyLoopTerminatorTarget`). `idr.jump` must carry that check itself (§2.1).
- The PR description is stale against its diff. The description speaks of "a new `RegionTerminator` trait", a "propagating successor sentinel" and `resolveTerminatorSuccessors`. The diff instead has an interface, `RegionExitTerminatorOpInterface`, and no sentinel. It routes propagation through each intermediate op's own `getSuccessorRegions` (*read*). The dispatch's `RegionTerminator` is that interface.
- An earlier revision encoded the target as a count of regions in op properties: a 2026-03-09 review comment by timnoack is about the `num-breaking-control-region` property offset. The head encodes it as a builtin `token` (*read*: the PR's comments and diff). So the encoding D25 adopts is the PR's current one.

#### 1.3.2 The interfaces, exactly (*read*: the PR's `RegionKindInterface.td`, `RegionKindInterface.h/.cpp`, `ControlFlowInterfaces.cpp`, `SCF.cpp`)

| name | kind | members | who implements it, for us |
| --- | --- | --- | --- |
| `PropagateControlFlowBreak` | native op trait | `verifyTrait`: the op has regions. Nothing else. | `idr.match`, `idr.match_lit`, `idr.join`, `idr.loop`. **Never** `idr.lifetime` or `idr.borrow` (seam with L05, §2.13). |
| `HasBreakingControlFlowOpInterface` | op interface | `static bool acceptsTerminator(Operation *)`, provided by the trait `HasNestedTerminator<[...]>`; `bool hasNestedPredecessors()`, whose default walks the subtree | `idr.join`, `idr.loop`, with `HasNestedTerminator<["JumpOp"]>` |
| `RegionExitTerminatorOpInterface` | op interface | `SmallVector<Operation *> getPotentialTargets()`; its `verify` `static_assert`s that the op is a terminator | `idr.jump`. It returns the token's owner op in O(1). `idr.yield` does not need it, since nothing of ours uses the PR's implicit-terminator class. |
| `RegionBranchTerminatorOpInterface` | upstream, existing | `getMutableSuccessorOperands` | `idr.jump`: its arguments. Matthias Springer asked on the PR whether an exit must implement this interface; for us it must, since an intermediate `RegionBranchOpInterface` op is asked about the point `RegionBranchPoint(jump)`. |
| `TokenProducerTrait` / `TokenConsumerTrait` | at the pin already | the core verifier allows token results and entry-block arguments only on producers, and token uses only on consumers | `idr.join` and `idr.loop` produce; `idr.jump` consumes. ODS adds the consumer trait automatically for an operand typed `Token` (*read*: `pin/mlir/tools/mlir-tblgen/OpDefinitionsGen.cpp:4053-4065`). |
| helpers | free functions | `getNestedBreakingControlFlowInfo`, `hasBreakingControlFlowOps`, `findPotentialBreakTargets`, `visitNestedBreakingControlFlowOps`, `mightHaveBreakingControlFlow`, `getRegionBranchSuccessorOwner` | read by our passes only through upstream's interfaces |

What each upstream reader then does (*read*):
- **Dead code** (`DeadCodeAnalysis::visitRegionTerminator`, pin `:505-515`). It asks the jump's *immediate* parent: the terminator interface's default `getSuccessorRegions` calls the parent op (pin `ControlFlowInterfaces.td:456-460`). That parent's `getSuccessorRegions(RegionBranchPoint(jump))` must return the target's successor. The PR's hunk at pin `:541-545` takes the successor inputs from the owner (`getRegionBranchSuccessorOwner`). So `idr.match`'s generated `getSuccessorRegions`, which today answers "the match" for any terminator (`IdrMatchOps.td:63-68`), must forward a jump whose target is an ancestor. The PR writes that forwarding as `static` helpers in `SCF.cpp` (`terminatorPropagatesThrough`, `appendPropagatedTerminatorSuccessors`), so no other dialect can call them (I3, U8).
- **SCCP**. The forward sparse analysis joins each known predecessor's operands at a region entry (pin `SparseAnalysis.cpp:298-357`). It takes a jump's operands from `getSuccessorOperands` and the inputs recorded by dead code. Successor inputs must follow the non-successor inputs as one contiguous run (`:329-350`). **Consequence:** in a join region's entry block the tokens come first and the parameters after, as `scf.loop`'s token is argument 0.
- **Sparse and dense backward** analyses. The PR rewrites the backward analyses to the owner's inputs. The forward ones need no change (*read*: the hunks).
- **Dominance.** Only post-dominance changes. Forward dominance needs nothing, since a token dominates its uses by construction. No pass of ours reads post-dominance (*measured*: `grep -rln 'PostDominance\|postDominates' idr/lib idr/include` finds none).
- **Inlining.** The PR makes `inlineRegionImpl` *refuse* a region whose parent has an escaping exit (PR `InliningUtils.cpp`, one check). It does not "read nested jumps as edges", as D25 says. The canonicalizer's region inliner is not covered (U2).
- **Region-branch verification.** `verifyRegionBranchOpInterface` (pin `:160-224`) enumerates `getAllRegionBranchPoints`. The PR extends that enumeration, for every op with the trait or the interface, with every nested exit found by a subtree walk (PR `ControlFlowInterfaces.cpp`, the hunk at pin `:524`). So the jump-to-parameter edge is checked once at each op between the jump and its target, and each such op walks its whole subtree on every verification (§1.5, measurement M2).

#### 1.3.3 The backport's conflicts with the pin (*measured*)

Method: copy the pin's 31 existing files the PR touches (the other 13 are new), plus every file of our carried patches that overlap them, to `/tmp/l09-check2`. Apply our carried `upstream/{05-forward-dataflow-callee-lookup,07-inline-unreachable-terminator,29-dead-code-nested-symbol-use,56-cse-nested-linalg-index}/llvm.patch` in name order: each applies cleanly. Then run `git apply --check` (zero fuzz, which is what `tools/bootstrap.sh:697-708` uses) and `patch --dry-run` (fuzz 2) on the PR's diff. Applying the PR to the bare pin gives the same result: our patches add no conflict.

| file | hunk | zero fuzz | fuzz 2 | cause at the pin | resolution |
| --- | --- | --- | --- | --- | --- |
| `mlir/lib/Conversion/SCFToControlFlow/SCFToControlFlow.cpp` | 1 of 4 (base `:311`) | fails | **fails** | the pin added `copyLLVMDialectAttrs` between `} // namespace` and `propagateLoopAttrs` (pin `:316-330`) | put `LoopOpLowering`'s declaration inside the anonymous namespace and `lowerIfOpToCFG` after it, before `copyLLVMDialectAttrs`. The pin's `IfLowering` is the PR's base text (pin `:405-459`), so hunk 2 applies as written. |
| `mlir/lib/Dialect/SCF/IR/SCF.cpp` | 21 of 22 (base `:3467`, `WhileMoveIfDown`) | fails | **fails** | the pin rewrote the loop to assign into each condition operand (pin `:3455-3474`) and still calls `ifOp.thenYield()` / `elseYield()`, which the PR deletes | rename the two calls in the pin's new text to `thenTerminator()` / `elseTerminator()`. If the hunk is dropped instead, the file does not compile. |
| `mlir/lib/Interfaces/ControlFlowInterfaces.cpp` | 14 of 15 (base `:733`, `MakeRegionBranchOpSuccessorInputsDead`) | fails | applies | the pin added `const bool isIsolated = ...` (pin `:732`) | insert the PR's `isSuccessorInputOwnedBy` skip after that line |
| `mlir/lib/Transforms/Utils/CMakeLists.txt` | 1 of 1 | fails | applies, but wrongly | the pin already has `DEPENDS MLIRTransformsDialectInterfaceIncGen` (pin `:18-19`); with fuzz the PR adds a second `DEPENDS` block | add `MLIRRegionKindInterfaceIncGen` to the existing `DEPENDS` list |
| `mlir/tools/mlir-opt/mlir-opt.cpp` | 1 of 2 | fails | applies | the context line `registerPrintTosaAvailabilityPass();` moved | insert the declaration by name order |

Everything else applies, with offsets of up to 103 lines. Every pin caller of the deleted `IfOp::thenYield`/`elseYield` lies in a file the PR rewrites (*measured*: `grep -rln -e 'thenYield()' -e 'elseYield()' pin/mlir pin/flang` lists only `SCFOps.td`, `SCF.cpp`, `ValueBoundsOpInterfaceImpl.cpp`, `BufferizableOpInterfaceImpl.cpp`, `XeGPUUtils.cpp`). The APIs the PR calls exist at the pin: `OpWithFlags` (pin `IR/Operation.h:1169`), `LDBG(level)` (`DebugLog.h:47`), `RegionSuccessor::isOperation`/`getSuccessorOp` (`ControlFlowInterfaces.h:219-227`), `getTerminatorPredecessorOrNull` (`:273`), and `TokenType`/`TokenProducerTrait`/`TokenConsumerTrait` (`CommonTypeConstraints.td:167-177`, `OpBase.td:101-104`). **So the backport is the PR rebased by hand, with these five hunks resolved.** `git apply` takes no fuzz, so a raw copy of the PR's diff would fail the bootstrap step.

**D25's file name is wrong** (*read*). D25 says `upstream/<id>/llvm-project.patch` (proposal `:407`; match-and-counting `:363, :404`). The project is `llvm`: `tools/patches.sh:13-27` finds `-name "$1.patch"` for `llvm`, every carried patch is `llvm.patch`, and `tests/upstream-patches/run:4-16` refuses "a patch named for no project". Correction: `upstream/<NN>-early-exits/llvm.patch`. (*mismatch*)

#### 1.3.4 Gaps our use reaches: upstream defects in the PR or beside it

The PR's own `scf` ops avoid most of these by accident: `scf.break` and `scf.continue` declare no memory effects, `scf.loop` has one region, and the PR adds no `scf.if` test with a constant condition. Our ops reach every one of them. Each is *read* in the source, and each reproduction is a measurement to take (M6).

- **U1. A resultless match whose cases all jump is deleted as dead.** `isOpTriviallyDead` is `use_empty() && wouldOpBeTriviallyDead`. For an op with `RecursiveMemoryEffects`, the implementation (pin `SideEffectInterfaces.cpp:43-110`) visits nested ops and treats the root as dead if every nested op declares no effect or only reads. The PR does not touch it. Counterexample: the join op's body `idr.match %xs -> () { case @Nil {...; idr.jump %k(%c0)} case @Cons {...; idr.jump %k(%s)} }` followed by `ub.unreachable`. If `idr.jump` declares no effect, as an op that only transfers control should, the greedy driver erases the match and the join body becomes `ub.unreachable`: a miscompile. `scf.break` escapes this only because it declares no `MemoryEffectOpInterface`, which counts as "unknown" (`:102-104`). Fix, carried: in that walk, an op implementing `RegionExitTerminatorOpInterface` whose potential target is not inside the root makes the root not dead. This costs O(1) per visited op. (*defect*)
- **U2. The canonicalizer's region inliner mutates IR and then fails.** `InlineRegionBranchOp` (pin `ControlFlowInterfaces.cpp:1210-1305`) follows `computeSingleAcyclicRegionBranchPath` (`:1136-1175`). For a known case region ending in a jump, the path continues into the *target's* region, an op the pattern does not own. The pattern then inlines the case block, erases the jump, and asks the match for the target's inputs, which asserts in a debug build. Finally it returns "path ends after a different operation" (`:1288`) after it has already changed the IR. `idr.match` registers this pattern (`OpsMatch.cpp:189`), and so does `scf.if` at the pin (`SCF.cpp:2734`), so `scf.if %true { scf.break [%l] }` reaches it too. Fix, carried: the path stops when `getRegionBranchSuccessorOwner(successor) != op`. (*defect*)
- **U3. The successor-input patterns edit inputs owned by another op.** The PR guards `MakeRegionBranchOpSuccessorInputsDead` with `isSuccessorInputOwnedBy`. It leaves `RemoveDeadRegionBranchOpSuccessorInputs` (pin `:859-934`) and `RemoveDuplicateSuccessorInputUses` (`:1006`) unguarded, and both build their map from the root's branch points, which now include nested exits. Counterexample: a dead join parameter, seen from a match that holds only some of the jumps to it. The pattern erases the parameter and the operands of *those* jumps, and the other jumps keep theirs, which the verifier refuses. Fix, carried: the same ownership predicate in the other two patterns. (*defect*)
- **U4. The region-graph traversal indexes another op's regions.** `traverseRegionGraph` (pin `:234-305`), which serves `isRepetitiveRegion` and `insideMutuallyExclusiveRegions`, sizes `visited` by the op's region count and then pushes every region successor of each level-1 terminator. A jump that is a direct terminator of a match case yields a region of the join op, and the code then reads `visited[region->getRegionNumber()]` with another op's numbering. It reads out of bounds when the join region's number is at least the match's region count. In the other direction, the traversal sees only level-1 terminators, so a loop whose back jump is nested in a match reports "not repetitive". Two readers of ours hit it: `Verify/Linearity.cpp:121-131` calls `isRepetitiveRegion` on every match the PR makes non-exclusive, and bufferization's repetitive-region queries matter for arrays inside loops (L12). Fix, carried: skip successors not owned by the op, and add nested exits that target its regions, as `getAllRegionBranchPoints` already does. (*defect*; read, not run)
- **U5. `scf.index_switch` does not carry exits.** The PR makes only `scf.if` propagate. `scf.index_switch` is `SingleBlockImplicitTerminator<"scf::YieldOp">` (pin `SCFOps.td:1172-1178`), its lowering expects `scf.yield`, and its structural type conversion (pin `StructuralTypeConversions.cpp:199-269`) does too. `idr.match` lowers to it (`Conversion/Matches.cpp:96-102`). So D25's "idr-lower's own lowering of nested jumps [is] never built" cannot hold with the PR alone. Fix, carried as an extension in the PR's own form: the trait, an implicit-terminator class accepting any exit (the PR's `IfOpImplicitTerminatorType`) and `ub.unreachable`, the forwarding in `getSuccessorRegions`, guarded canonicalizations, `IndexSwitchLowering` leaving non-yield terminators, and the structural conversion leaving them. (*incomplete*)
- **U6 (not needed by this design).** `scf.loop`, `scf.break` and `scf.continue` have no structural type conversion. That gap matters only to a design that lowers join points to `scf.loop`, which §2.8 does not.
- **U8 (simplification).** Export `terminatorPropagatesThrough` and `appendPropagatedTerminatorSuccessors` from `SCF.cpp` to `ControlFlowInterfaces`. Every propagating `RegionBranchOpInterface` op needs them, and otherwise each dialect writes its own copy.

#### 1.3.5 D25's statements, item by item

| claim | verdict | ground |
| --- | --- | --- |
| "The encoding: the PR's is ours, a token defined by the target op." | **holds** | The PR's token is a builtin `token` entry-block argument of the receiving op (*read*: PR `SCFOps.td`, `LoopOp`; `SCF.cpp`, `getLoopTargetFromToken`). |
| "`idr.jump %tok(...)` terminates with its target in its `!idr.cont<...>` token." | **refuted as written** | The PR's token is the builtin `token`. A dialect type `!idr.cont<...>` falls outside the pin's token rules: the verifier compares against the builtin type exactly (`pin/mlir/lib/IR/Verifier.cpp:122-146`), and `AnyType` excludes only the builtin type (`CommonTypeConstraints.td:173`). Every `AnyType` operand of ours would accept `!idr.cont`: `idr.call`'s arguments (`IdrOps.td:216`), `idr.return` (`:245`), `idr.con`'s fields (`:290`), `idr.yield` (`IdrMatchOps.td:168`), the closure apply (`IdrClosureOps.td:134`), `cell.init`'s fields (`IdrOwnershipOps.td:258`). So match-and-counting §5.4's claim that the type has "an operand type constraint every other op lacks" (`:384-387`) is false. The argument types are also the target region's entry arguments already, so a typed token holds them twice. Correction: builtin `token` (I1). |
| `idr.join` implements `HasBreakingControlFlowOpInterface`; `idr.match`, `idr.match_lit` implement `PropagateControlFlowBreak`. | **holds with corrections** | `PropagateControlFlowBreak` is a trait, not an interface. Beyond those two: `idr.join` also needs `PropagateControlFlowBreak`, so that a jump to an outer join point can cross an inner one, and `TokenProducerTrait`. The matches' `getSuccessorRegions` must forward propagated exits (§1.3.2). |
| "Upstream's SCCP, dead code, dominance and inlining read nested jumps as edges." | **holds for SCCP and dead code; corrected for dominance and inlining** | §1.3.2. U2 to U4 are further readers the PR leaves wrong. |
| "No control-flow reading of ours stands beside them." | **holds after two consumer adaptations** | `idr::forwardedValues` (`Flow.cpp:44-62`), which every flow edge of ours passes through (exclusivity, borrows, the stack inference), reads `branch.getSuccessorInputs` on the jump's *parent*, so `zip_equal` would fail on a propagated edge. It must read the owner's inputs. `verify::alternatives` (`Linearity.cpp:27-33`) tests "every successor of a region is the op". With a jump in a case that test fails, which makes the linearity count *sum* uses across cases. It must test "no region successor is a region this op owns". |
| "The conservative modelling of §5.4 and idr-lower's own lowering of nested jumps are never built." | **the first holds; the second holds only with U5** | With U5, nested jumps are lowered by upstream's `scf.if` and `scf.index_switch` lowerings, which leave them in place. The join ops' own lowering, of level-1 jumps only, is ours, as every op of ours has its own (§2.8). |
| "Always carry the patch"; "fast-forward every dependency". | **holds** | After the fast-forward, §1.3.3's measurement is repeated against the new pin. The resolutions above are what a rebased patch carries until upstream merges. |

### 1.4 D30: a jump is a tail transfer

| claim | verdict | evidence |
| --- | --- | --- |
| Every call in tail position is a jump: a loop, a join point, or `musttail`. A jump never grows the stack. | **holds** | `idr.jump` is a terminator, so nothing in its block follows it. Its target is a region of an enclosing op in the same function, so it pushes no frame, and it lowers to `cf.br` (§2.8). A back jump is a back edge. |
| "One fact per call": tail position decided once and held on the call. | **holds; jumps need no such fact, and contification rewrites it** | (a) Tail position is a *precondition of forming* a jump: a call becomes a jump only if it was in tail position relative to the place the join op goes. It is not an invariant the IR must check, since the PR's early-exit semantics define an exit from a non-tail match soundly, and no pass forms one. (b) When Fluet and Weeks's analysis puts a function at a *non-tail* continuation (§2.5), the tail calls inside its body stop being tail calls, and the pass that moves them must rewrite their fact. The stack stays bounded: the function was only ever called with that continuation, so the frame the call held before is the frame the callee's call holds after (*derivation*). This is a seam with L10 (§2.13). |
| "A failure is a compiler bug." | **holds** | A jump cannot fail to be a tail transfer, because its representation admits nothing else. |

### 1.5 D10, as it bears on control flow

| paid now | at | evidence | removed by |
| --- | --- | --- | --- |
| "This path continues" as a run-time `i1` plus poison halves | program run time | `Loop.cpp:7-14, 43-58` | `idr.loop`: the back jump is the edge (I2) |
| The refined constructor rederived by walking ancestors per query, three ways | compile time | `OpsMatch.cpp:78-94` (called from `getEntrySuccessorRegions`, `getRegionInvocationBounds`, so on every SCCP visit of a match); `OpsConReads.cpp:123-138`; `Eta.cpp:39-47` | the refined case binding with a constructor set (§2.4, I6) |
| Running regions recounted at each yield's arrival | compile time | `Tail.cpp:93-96, 120, 213` (10 IT-7) | the count is the op's own: its case-list length plus one if the default is non-empty, O(1). With join points, TRMC reads arrivals off jumps and yields once (L10). |
| A self call recognized by comparing names | compile time | `Tail.cpp:50-53`; `Contify.cpp:96` (10 C-2) | the program graph's dense identity (L14) |
| `CallCycles` and a `SymbolUserMap` rebuilt per run | compile time | `Contify.cpp:89, 128`; not preserved, `:133` (10 C-4, C-5) | the program graph (L14) |
| Tail position climbed per query, by recursion on nesting depth | compile time | `Tail.cpp:23-35` (`endsTail` ↔ `inTailPosition`), also against D33 | D30's fact on the call (L10) |
| A shared continuation written as a selector or copied | program run time / code size | `CaseOfCase.cpp:141-176` copies the whole consumer into every yielding region | case-of-case through join points (I8) |
| The PR's subtree walk per propagating op per verification | compile time | PR `getAllRegionBranchPoints`; AGENTS.md verifies after every pass | measure (M2). If it is a wall, enumerate foreign exits only at their target (I10). |
| A jump-to-parameter edge verified at every op between them | compile time | §1.3.2 | the same as the row above |

### 1.6 match-and-counting.md, which D19 and D25 delegate the encoding to

| claim | verdict | evidence |
| --- | --- | --- |
| §5.1: the pin has none of the early-exit work. | **holds** | *measured*: `grep -rl PropagateControlFlowBreak pin/mlir/include pin/mlir/lib` gives 0 files |
| §5.2(d): an exit from depth is "the same op as `idr.jump` with the op's own token". | **refuted as unnecessary** | A jump is always a tail transfer (§1.4), so every match between it and the join op is in tail position. A value meant for after the join op is a plain yield through each enclosing match, and each match yields its result. No exit token is needed, and every token designates a join region. |
| §5.4: the body's entry block takes one token per target, and the join regions jump to siblings. | **incomplete** | Values defined in region 0 do not dominate sibling regions, so a join region cannot see the body's tokens. Sibling and self jumps need tokens in each region's own entry block. §2.1 resolves it with two ops: `idr.join` keeps its tokens in the body (non-recursive by construction), and `idr.loop` puts them in every region (N per region, for a recursive group of N). |
| §5.4: "Our own passes ... read the jump edges off one generated interface method of `idr.join`" until the backport. | **holds as moot** | D25 carries the backport from the start, so this second tier is never written. |
| §6: contification with `A = Uncalled \| Unknown \| Cont \| Func` and one dominator tree. | **holds with an addition** | A continuation must be named on regions: §2.5's return point. |
| §10: no reason survives for blocks before the lowering. | **holds** | — |

### 1.7 The deletions the dispatch names

| deletion | verdict | where | replaced by |
| --- | --- | --- | --- |
| Contify's one-call-site rule | **holds** | `Contify.cpp:95-101` (`uses.size() != 1`, `cycles.together`), and its reason at `:10-13` | Fluet and Weeks on the program graph (§2.5). Also deleted: the second-block workaround (`:34-42, 119-121`), the root found by name (`:96`), and the per-run `SymbolUserMap` (`:89`). |
| its rebuilt `CallCycles` | **holds** | `Contify.cpp:128`; only `SymbolTable`, `TypeGraph` and `Layouts` preserved, `:133` | the program graph, edited in place by `moveInto` and `setCallees` (L14 §2.1.5) |
| the flag-payload loop with poison halves | **holds** | `Tail/Loop.cpp` whole; `WhileDo.cpp` whole (311 lines); `TailLoops.cpp`'s split between the two (10 TL-4) | `idr.loop`, formed by contification's self-edge case (§2.7) |
| TRMC's `runningRegions` recount | **holds** | `Tail.cpp:93-96`, read at `:120, :213` | the count from the op; arrivals off jumps and yields (L10's unit) |
| the three enclosing-match walks | **holds** | `OpsMatch.cpp:78-94`; `OpsConReads.cpp:123-138`; `Eta.cpp:39-47` | the refined case binding (§2.4) |
| the `tag` attributes of `field`, `take`, `unpack` | **holds** | `IdrOps.td:333`; `IdrOwnershipOps.td:318, :343` | the operand's refined type names the constructor (L04 owns the type) |

## 2. Boundaries

The exact end state of this area as the design stands after this file's
corrections. Nothing here is written by hand into `.td`. Each op below is
an entry of the Idris specification (D16), whose generated TableGen names
upstream's records (D51).

### 2.1 Ops and the token

**The token.** Upstream's builtin `token`, nothing of ours. The pin's
verifier enforces its rules for every op of every dialect: only an op
with `TokenProducerTrait` defines one, as a result or an entry-block
argument; only an op with `TokenConsumerTrait` uses one; it is never a
non-entry block argument (`Verifier.cpp:122-178`); and `AnyType` excludes
it. Of our ops, only `idr.join` and `idr.loop` produce tokens and only
`idr.jump` consumes them, so a token cannot be stored, passed, returned,
yielded, captured, or passed as a jump argument. Escape is refused by
upstream's existing checks, with no walk of ours.

**`idr.join`**: a group of non-recursive join points (GHC's `join`).
- Regions: the body, region 0; then join regions 1 to N, with N ≥ 1. Each region is one block (`SizedRegion<1>`), so there are no blocks before the lowering.
- The body's entry block has exactly N `token` arguments: argument i designates join region i+1. A join region's entry block has its parameters only. Their grades are in their types (`!idr.lin<T>`, `!idr.excl<T>`, a reuse token, a view of a lifetime). Its erased index and lifetime variables are binders of the region (D48's region binder, §2.4), not block arguments.
- Results: `Variadic<AnyType>`.
- Terminators of its regions: `idr.yield` (to the op's results), `idr.jump`, `ub.unreachable`.
- Traits and interfaces: `RecursiveMemoryEffects`; `TokenProducerTrait`; `HasBreakingControlFlowOpInterface` with `HasNestedTerminator<["JumpOp"]>`; `PropagateControlFlowBreak`; `RegionBranchOpInterface`, declaring:
  - `getSuccessorRegions(parent)` = [body];
  - from `idr.yield` = [the op];
  - from a jump whose token this op owns = [region `argNumber + 1`];
  - from a jump whose token an enclosing op owns = that owner's answer (U8's helper);
  - `getSuccessorInputs`: the op's results, a join region's parameters, and nothing for the body;
  - `getRegionInvocationBounds`: [1,1] for the body, [0,1] for a join region;
  - `getPredecessors` overridden to read the token's uses, O(uses) (03 O-13's pattern).
- Non-recursive by construction: the body's entry arguments do not dominate the join regions, so no join region can name its own op's tokens. It never repeats and never diverges. A join region may jump to an *enclosing* op's join regions.

**`idr.loop`**: a recursive group of join points (GHC's `joinrec`; D19's "a recursive join point is a loop").
- Shaped as `idr.join`, except that *every* region's entry block begins with the same N tokens. Argument i designates join region i+1. A join region's parameters follow its tokens (tokens first, §1.3.2).
- Adds `LoopLikeOpInterface` (`getLoopRegions` = its join regions), so upstream's LICM reads it. `getRegionInvocationBounds` is [1,1] for the body and [0, unknown] for a join region.
- In code that came from a function without `total`, each join region's entry holds `idr.may_loop`, the existing marker (`IdrCheckOps.td:42-50`, lowered to `llvm.sideeffect`, `Conversion/Scalars.cpp:48-56`). The pass that makes the back jump inserts it, and inlining moves it with the code. A loop from total code carries none, so it may be deleted when unused, as D13 allows.
- Canonical form: an `idr.loop` whose join regions never jump into its own op becomes an `idr.join`. This is a canonicalization, not a verifier error, as an `scf.loop` that never continues is valid.

The two ops form one family in the specification (D9: "ops that differ in a parameter are one family whose members come from a list"). Their parameter, the scope of the tokens, is the essential difference: whether the op's regions can repeat.

**`idr.jump %t <idx...> (%a... : T...)`**
- Operands: `Token:$target` (ODS adds `TokenConsumerTrait`), and `Variadic<AnyType>:$args`, which excludes tokens. A list attribute of index terms, D48's index language, instantiates the target region's erased binders. Checked by substitution, as `idr.call`'s are (D48).
- Traits and interfaces: `Terminator`; `RegionBranchTerminatorOpInterface` (`getMutableSuccessorOperands` = its arguments); `RegionExitTerminatorOpInterface` (`getPotentialTargets` = the token's owner op, read as `cast<BlockArgument>(t).getOwner()->getParentOp()`, O(1)).
- Effects: static, none. U1 is what makes "none" safe (§1.3.4).
- Its own verifier:
  1. The token is an entry-block argument of a region of an `idr.join` or `idr.loop` (read off the op's declared trait, not a list of ops).
  2. Every op between the jump and the owner carries `PropagateControlFlowBreak`: an ancestor walk, O(depth), the PR's own check shape.
  3. The owner accepts it.
  4. The argument count and types equal the target's parameters after substitution.

**`idr.match`, `idr.match_lit`**: as now (`IdrMatchOps.td:25-37`), plus:
- `PropagateControlFlowBreak`, and a generated `getSuccessorRegions` that forwards a propagated exit;
- `verifyMatchRegions` (`OpsMatch.cpp:30-36`) admits `idr.jump`. 03 O-50's region-end trait declares the three ends once;
- an exhaustive match whose regions all jump or stop has no results, is followed by `ub.unreachable`, and has its ops after it erased (as the PR's `SimplifyIfWithBreakingControlFlowInBothBranches` does for `scf.if`);
- the refined case binding (§2.4).

**`idr.yield`**: `ParentOneOf` gains `JoinOp` and `LoopOp` (`IdrMatchOps.td:164`).

### 2.2 Invariants

1. A token designates exactly one join region. Its owner op and argument number say which, in O(1); there is no attribute to keep in step.
2. A jump lies inside its target's op (dominance), and every op between them propagates exits (the jump's verifier).
3. A jump's argument types equal its target's parameters under its index substitution.
4. A join region of an `idr.join` is entered at most once per entry of the op. Only an `idr.loop`'s join regions repeat.
5. A match's regions are alternatives: no region of a match is a successor of another region of that match. An `idr.join`'s or `idr.loop`'s regions are sequential: the body first, then at most one join region at a time.
6. A recursive join region of partial origin holds `idr.may_loop`. One of total origin holds none.
7. Every op is one block per region until the lowering.

### 2.3 What each upstream reader reads, and where ours adapt

| reader | reads | from our ops |
| --- | --- | --- |
| dead code, SCCP, sparse forward | a jump's successor via its parent's `getSuccessorRegions`; inputs from the owner | the matches' forwarding; the join ops' inputs |
| sparse and dense backward (liveness) | the same, through the PR's rewrite | — |
| region-branch verification | every branch point, nested exits included | all four ops; U4 for repetitive regions |
| the canonicalizer's region patterns | owned inputs only, after U2 and U3 | the matches register them (`OpsMatch.cpp:188-190, 244-246`); the join ops also register the dead and duplicate input patterns, which then delete dead join parameters together with every jump's operand |
| LICM | `LoopLikeOpInterface` | `idr.loop` |
| `wouldOpBeTriviallyDead` | escaping exits, after U1 | — |
| ours: `forwardedValues` (`Flow.cpp:56-62`) | the owner's inputs (adapted) | flow edges per jump operand, read once: exclusivity, borrows, the stack inference |
| ours: linearity (`Linearity.cpp:27-33, 121-131`) | alternatives by ownership (adapted); repetition through U4 | the max over match cases, the sum over a join's regions, a used repeated region counted twice |

### 2.4 Match refinement, with D48's index refinement

Seam with L04, which owns the type's shape. What control flow needs:
1. **A case binds the refined scrutinee first.** Its type is "a value of this family at this index, known to be one of the constructors in S". In a case S is the singleton {C}. In the default S is the complement of the match's cases, and an empty S means no region: the exhaustive empty default, 03 O-44's one spelling. Field reads (`field`, `take`, `unpack`) take an operand whose S is a singleton, and carry no tag. A nested match on a refined value has no region for a tag outside S, so its taken region is read off the type in O(1). That deletes all three walks, including the default-region fold `takenFromEnclosing` makes today (`OpsMatch.cpp:85-91`), which a singleton type alone would lose. This generalizes synthesis A §5.8's and G DP-37's `!idr.ctor<T, @C>` from a constructor to a set.
2. **A case binds its constructor's index variables as quantity-0 binders of the region** and assumes the constructor's index equation. If the equation contradicts the scrutinee's index, the case does not exist: the verifier refuses a region for it, and coverage reads that (`head`'s `@Nil` at `n + 1`, D48). When the equation leaves one constructor possible, the match has one region and no tag test, and the region-inlining fold removes the match.
3. **Values whose types mention a refined index enter the case refined.** The match forwards them as entry successor operands, the same value at the refined type, with no run-time form. The refinement then lives in SSA types inside the region, and no verifier collects equations from ancestors. Without this, `zip`'s second match keeps a default and a tag test that Idris proved dead: its type is still `Vect n b` inside the first match's `@Cons` case (I6). Upstream's dataflow sees forwarded values as equal to their sources, so constant propagation is unaffected.
4. **`idr.match_lit` needs no refined type.** In case k the scrutinee *is* k, so a canonicalization replaces its uses inside that region with the constant, as upstream's `scf.if` does for its condition (`ConditionPropagation`, pin `SCF.cpp:2260`, registered at `:2729`). Literal matches then lose `takenFromEnclosing` too.
5. **Join regions bind erased index and lifetime parameters**, and jumps pass terms for them. A recursive join point over a decreasing index is therefore representable (§1.2 (b)). `areTypesCompatible` on the join ops accepts an argument that is an instance of the parameter's pattern, so upstream's edge verification passes. The jump's verifier checks the exact substitution.

### 2.5 Contification after Fluet and Weeks, on the program graph

Reads L14's `ProgramGraph`: dense function ids, callers and callees as compressed rows, each edge with its tail kind (L10's fact on the call) and its number of sites. Also reads one pre-order walk per function, done by this pass alone, which computes each call's **return point**. A call's return point is *Tail* if its fact says tail. Otherwise it is the outermost op X of the call's yield chain: the chain climbs while the call's results are passed unchanged to a yield, then the yielding match's results to the next yield, and so on. X is the call itself when its results go to any other op. Return points are numbered per function, and each is a continuation node.

**Graph** (after `contify.fun`'s `AnalyzeDom`, `sources/code/mlton/mlton/ssa/contify.fun:294-470`, *read*). Nodes: functions, continuation nodes, and a root. Edges:
- root to the program's root function, and root to every function whose callers are not all known (none, in a closed first-order program);
- root to every continuation node;
- f to g for each tail call in f of g;
- k to g for each non-tail call of g whose return point is k;
- root to f for every f unreachable from the root function.

One dominator tree (`llvm::DominatorTreeBase` over a `GraphTraits` view of the compressed rows). A(g) is the ancestor of g just below the root: `Func f`, `Cont k`, `Unknown` (idom is the root, reachable) or `Uncalled`.

**Rewrite.** One per target. All functions with the same A form one group.
- *Cont k, k = (f, X)*: X is wrapped in a join op. X becomes the op's body and its results the op's results. Each call in X's chains to a group member becomes a jump.
- *Func f*: the join op wraps the outermost op common to the yield chains of f's tail calls into the group (f's body, at worst).
- Members become join regions: their parameters become join parameters, their erased parameters become region binders, and their `idr.return` becomes `idr.yield`.
- Calls between members become jumps. The group is an `idr.loop` if its jump graph has a cycle, otherwise nested `idr.join`s in topological order. Independent members share one flat `idr.join`.
- A member's tail calls out of the group become non-tail calls whenever X is not in tail position, and the pass rewrites their fact (§1.4).
- The graph is edited with `moveInto(g, f)` per member and `setCallees(f, ...)` once (L14 §2.1.5). Rows are re-derived per function after the pass (D22).

**Cost.** One walk per function, a graph of F + K nodes and one edge per call, one dominator computation, one rewrite. No iteration, no budget. It runs at today's slot (`Pipeline.cpp:80`, before `idr-optimize` at `:82`) and again in the optimizer's bottom-up step once inlining exposes direct tail calls; MLton runs it three times, E1. That is a fixed sequence of runs, never a fixpoint.

**Policy.** A size cap may decline to contify a group into a function already at the cap (L18's ready set, `Contify.cpp:21-24`). That only leaves the program less optimized (AGENTS.md).

**What it subsumes.** Today's rule (one call site, on a cycle with its caller) is the case A = `Cont k` with one call. Self tail calls are the case in §2.7.

### 2.6 Join-point formation and case-of-case

**Formation for a continuation value** (in the optimizer, after inlining; seam with L18):
- *Condition*: a closure constructor of a known label in f whose every use is an application in f, each in tail position relative to one region. None of its uses is a store, a return, a call argument, or a capture into another closure.
- *Rewrite*: a join region holding the lambda's body, with its captures as parameters, or as free values where they dominate the join op. Each application becomes a jump.
- *Linearity* (`!idr.lin` on the closure sum) is not required. It tells counting that each argument is moved (§3).
- *Cost*: per function, linear in the constructor's uses.

**Case-of-case through join points** replaces `CaseOfCase.cpp`'s copy of the whole consumer (`:141-176`). Take an inner match M1 whose result has one consumer, M2, a match on it. Each yielding region of M1 gets a copy of M2's *dispatch*: a match whose every case only jumps. Each case *body* of M2 becomes one join region of one flat `idr.join` that replaces M2: its parameters are that case's fields, or for the default the scrutinee. In a region where M1 yields a constructor, the copied dispatch folds to a jump that passes the fields, and no constructor is built. GHC does the same, binding each outer alternative as a join point and pushing only the case into the inner arms (*recalled*).
- *Growth*: one jump per case of M2 per yielding region of M1, before folding. Today the growth is M2's whole size times M1's yielding regions.
- *Termination* is by construction: each step moves a dispatch strictly deeper, bounded by nesting depth, with no budget. The fight with `YieldFields` (c179ab2d; 04 C08) cannot arise, because no constructor remains to move back out.
- *Profitability* stays as today: some region meets a fold (`canon::meetsInSomeRegion`).

### 2.7 A recursive join point as a loop

A function with a self tail call becomes:

```
%r = idr.loop -> R { ^body(%k: token): idr.jump %k(%args...) }
               join { ^go(%self: token, %p...): <old body; each self tail call is idr.jump %self(...)> }
idr.return %r
```

plus `idr.may_loop` at `^go`'s entry when the function is not total. The canonicalizer keeps it: there is a back jump. This one rewrite serves contification's self-edge case, and TRMC's clone, which runs after counting (`Pipeline.cpp:131-132`). Turning a call into a jump keeps counting's decisions, since the join parameters take the callee's parameter grades and placement has already dropped what the call did not take. It deletes `Loop.cpp`, `WhileDo.cpp`, and the decision ladder in `TailLoops.cpp` (10 TL-1 to TL-4, W-1 to W-4).

Today `WhileDo.cpp:12-15` builds the shape that upstream's uplift turns into `scf.for`. With `idr.loop` the counted loop reaches LLVM as a natural loop, whose IndVarSimplify and SCEV find the trip count. Nothing in the pipeline reads an `scf.for` that came from a tail call: the arrays' loops come from `lowerToLoopsUsingSCFForOp` (D43). That claim is *conjecture* until M5 measures it.

### 2.8 The lowering

1. **Phase 1 (idr-lower, per function, on idr types).** `idr.match` becomes `scf.index_switch`. U5 is what lets a case end in `idr.jump` or `ub.unreachable`, and lets the poison yields of `Matches.cpp:30-37` go. `idr.match_lit` becomes `scf.index_switch` or the `scf.if` chain (`Matches.cpp:108-164`); `scf.if` propagates under the PR.
2. **Phase 2 (type conversion, `Lower.cpp:144`).** Structural conversion patterns of ours for `idr.join`, `idr.loop` and `idr.jump` convert region argument and operand types, beside upstream's `populateSCFStructuralTypeConversionsAndLegality`, which U5 extends to `scf.index_switch` regions ending in an exit.
3. **Phase 3, replacing `createSCFToControlFlowPass()` at `Pipeline.cpp:186`.** One conversion with upstream's `populateSCFToControlFlowConversionPatterns` and our join pattern, on upstream's own target. The join pattern:
   - legalizes nested regions first, as the PR's `LoopOpLowering` does. After that, every jump to the op is a level-1 terminator of a block of one of its regions, because the `scf.if` and (with U5) `scf.index_switch` lowerings leave exits in place;
   - splits the parent block;
   - inlines the body's blocks and each join region's blocks before the continuation block;
   - erases each region's leading tokens;
   - turns each jump into `cf.br` to its target region's entry block with its arguments, and each `idr.yield` of the op's regions into `cf.br` to the continuation block.

   An irreducible group, one the body enters at two members of a cycle, lowers like any other. Structured lowering would need a selector (`lift-cf-to-scf`'s multiplexer) for it, a fact known at each edge and paid at run time. An `idr.loop` region is a natural loop to LLVM.
4. **LLVM** does the block-level work (D19).

### 2.9 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| a join op and its join regions | contification (§2.5), self-tail loops (§2.7), formation (§2.6), case-of-case (§2.6) | these four rewrites. The frontend writes matches, not join ops, until 0003's block parent lets it emit case blocks in place (10 D4), and even then as matches. |
| a token | `idr.join` / `idr.loop`'s region entry (`TokenProducerTrait`) | upstream's verifier refuses any other producer |
| a jump | the same four rewrites, together with its target; the canonicalizer copies dispatches (case-of-case) or deletes dead ones | — |
| the refined case binding and its constructor set | the match's case and default regions | the match only; `idr.con`'s refined result is L04's |
| index equations of a case | the family attribute (D48) | L04 |
| forwarded refined values in a case | the frontend (Emit), from the refinement Idris did | Emit |
| `idr.may_loop` in a recursive region | the pass that makes the back jump, in partial code | that pass; inlining moves it |
| a call's tail fact | the frontend; rewritten by contification when it moves a call to a non-tail continuation | L10 owns the fact; this pass edits it |
| return points | contification's own walk | read by nothing else, so held nowhere |
| `PropagateControlFlowBreak` on an op | the specification | four ops: the two matches, `idr.join`, `idr.loop` |

### 2.10 Consumers, errors, cleanup

- **Consumers.** Placement, reuse and borrows (L07) read join live-ins once and jump arguments as moves. Exclusivity (L08) reads edges per jump operand through `forwardedValues`. The stack inference and frames (L10) read join regions as scopes; a frame is an escaped join point. TRMC (L10) reads arrivals off jumps and yields. The linearity verifier, upstream's analyses and patterns (§2.3), LICM, and the lowering.
- **Error paths** (verifier, all internal errors, never refusals):
  - a token from anything but a join op (upstream's message);
  - a jump crossing a non-propagating op (`idr.lifetime`, `idr.borrow`, an array body, `idr.func`);
  - a parameter or argument mismatch;
  - a token used anywhere but `idr.jump` (upstream's message).

  A join point not formed only leaves the program less optimized.
- **Cleanup.** A join region with no jumps is erased together with its token, in every region's entry block. A join region with one jump that is the body's level-1 terminator is inlined at it. An `idr.join` whose body yields and whose join regions are all dead becomes its body. An `idr.loop` with no back jump becomes an `idr.join`.

### 2.11 What it deletes

| what | where |
| --- | --- |
| Contify's single-site rule, its `CallCycles` rebuild, its `SymbolUserMap`, the root found by name, the second-block workaround | `idr/lib/Transforms/Optimize/Contify.cpp:10-13, 34-42, 89, 95-101, 119-121, 128` |
| the general loop, the while-do loop, their split | `Tail/Loop.cpp`, `Tail/WhileDo.cpp` (whole), `TailLoops.cpp:13-23, 128-169` |
| case-of-case's whole-consumer copy | `Canon/CaseOfCase.cpp:141-176` |
| the three enclosing-match walks | `OpsMatch.cpp:78-94` (and its calls at `:168, :176, :235`), `OpsConReads.cpp:123-138`, `Eta.cpp:39-47` and its call at `:70` |
| the `tag` attributes | `IdrOps.td:333`, `IdrOwnershipOps.td:318, :343`, and their printers (`custom<CtorRef>`) |
| poison yields for arms that never return | `Conversion/Matches.cpp:30-37` |
| `runningRegions` (with L10) | `Tail.cpp:93-96` |
| `!idr.cont<...>` | never built |
| the second tier, and idr-lower's own lowering of nested jumps | never built |

### 2.12 Essential distinctions

1. A match's regions are alternatives; a join op's regions are sequential.
2. A non-recursive group differs from a recursive one: repetition, divergence, counting's loop rule.
3. A region ends by a yield, a jump, or never.
4. A loop of total origin differs from one of partial origin: the marker.
5. A jump stays in its function; a call crosses functions and is `musttail` on a cycle (D30).
6. A case region binds a singleton constructor set; the default binds the complement.

### 2.13 Seams

| with | the declaration both sides write against | state |
| --- | --- | --- |
| L04 (families) | the refined type: a family at an index with a constructor set; region binders for index variables; index terms on `idr.jump`; refined values forwarded into a case | **unfixed**: L04 owns the type; this file states what control flow reads |
| L05 (lifetimes) | `idr.lifetime` and `idr.borrow` do not propagate exits; contification and formation make no jump that crosses one (L05 §2.5 rule 8, and its seam table row "L09") | **fixed, by agreement**. A consequence for loops: a per-iteration lifetime ends before the back jump (`idr.lifetime {...; idr.yield next}` then the jump), so a decision that reads values living in the iteration's lifetime keeps that lifetime around the whole loop. |
| L07 (counting) | join live-ins; jump arguments as moves; tokens as jump arguments; specialization of join regions by key | L07's |
| L08 (exclusivity) | an edge per jump operand from `forwardedValues`, reading the owner's inputs | fixed by §2.3 |
| L10 (tail, frames) | the tail fact on calls, rewritten by contification (§1.4); TRMC's arrivals; frames as escaped join points; self-tail loops replaced by §2.7 | **unfixed**: L10 must accept that contification edits the fact |
| L01, L02 (effects) | `idr.jump` declares nothing (needs U1); the join ops are recursive; `idr.may_loop` writes `divergence`; rows re-derived after contification | fixed if U1 is carried |
| L13 (ops) | the region ends `Yields \| Stops \| Jumps`; if integer and `i1` `match_lit` become `scf.index_switch`/`scf.if` before counting (03 O-16), U5 is needed from then on, not only at the lowering | open on O-16 |
| L14 (program graph) | ids, rows with tail kinds and site counts, `moveInto`, `setCallees`; continuation nodes come from contification's own walk, because L14's `Call` aggregates sites by (callee, kind) (L14 §2.1.2) | fixed |
| L12 (arrays) | bufferization's repetitive-region queries inside `idr.loop` depend on U4 | needs U4 |
| L18 (optimizer) | formation after inlining; contification in the bottom-up step; the cap | L18's |

## 3. QTT

**Quantity 0.**
- *Enters:* Idris's erased binders. The frontend emits no parameter, field or argument for them (AGENTS.md), so no join parameter and no jump argument exists for them.
- *Kept:* as region binders of a join region and of a case region (§2.4), and as index terms on a jump. They cost nothing at run time and are checked by substitution.
- *Read:* the match's verifier refuses a case whose equation contradicts the index. The constructor set says which regions exist.
- *Lost today:* nowhere in this area, because the match carries no index yet. Lost under the proposal as written: a refinement that reaches other values inside a case. §2.4(3) keeps it.
- *Used harder:* a known index after refinement leaves one constructor possible, so the match has one region and no tag test. `zip`'s second match costs nothing.

**Quantity 1.**
- *Enters:* as `!idr.lin<T>` on a scrutinee (the match consumes it), on fields (the product of quantities), on join parameters, and on a continuation's closure sum (`(1 k : Res a -> r)` becomes `!idr.lin<K_a>`, match-and-counting §9).
- *Kept:* in types, verified after every pass. The linearity verifier takes the max over a match's alternatives, the sum over a join op's sequential regions, and a used repeated region (`idr.loop`) as two uses, so a free linear value consumed inside a loop region is refused.
- *Read:* a jump argument of quantity 1 is a move. Placement never adds a duplicate at a jump, and a join region's live-ins are moved (L07).
- *Not proved:* uniqueness. A linear binder does not imply unique heap ownership (AGENTS.md); exclusivity must still prove it.

**Non-escape is a type now.** A continuation that has become a join point is a builtin `token`, which upstream's verifier lets only `idr.jump` consume. Escape is unwritable for every op in every dialect. Before formation the continuation is a value, and escape is decided by its uses.

**Quantity ω.** Jump arguments may be shared, and borrowed join parameters are L07's (match-and-counting §7).

**Totality** (Idris-proved, not a quantity). A loop of total origin carries no `idr.may_loop`: it is deletable when unused and lowers with `mustprogress`. Partial origin keeps the marker (D13).

**Coverage.** An exhaustive match has an empty default, the empty constructor set. A crash arm jumps nowhere, so no unknown predecessor reaches a join point (07 D1's precision loss cannot arise).

**Facts a quantity proves that the design still pays for.**
1. The dead default and tag test of a match on a refined value (§2.4(3)): paid at run time today and under the proposal as written. Removed by forwarding refined values.
2. The parametric answer type. In `{0 r : Type} -> ... -> (1 k : A -> r) -> r`, the erased `r` and the linear `k` together prove, by parametricity, that every non-crashing path ends by applying `k` exactly once in tail position, provided nothing else in scope produces an `r` (Wadler's free theorems, *recalled*). Monomorphization by layout instantiates `r` and loses this fact. If the frontend kept it as a fact of the continuation parameter, two readers would use it. (a) Formation after inlining would need no tail check for that parameter. (b) A chain of such continuations that escapes into heap cells is consumed last in, first out: each cell is applied once, and before the cell it wraps. That is D31's typed frame stack, not a counted heap list (L10, L20). *Conjecture*: whether the frontend can keep this fact across monomorphization is L16's question.

**Representations that make a misuse unwritable.**
- builtin `token`: escape;
- region binders with substitution: a jump at the wrong index;
- `idr.join`, whose own tokens are invisible to its join regions: an accidental loop;
- the constructor set: a field read of a constructor the value is not.

## 4. Improvements

**I1. The token is upstream's builtin `token`, not `!idr.cont<...>`.** *owner* (it amends D25's text).
- *Evidence:* §1.3.5 row 2: the pin's token rules (`Verifier.cpp:122-178`, `CommonTypeConstraints.td:167-177`, `OpDefinitionsGen.cpp:4053-4065`), and our `AnyType` operands (`IdrOps.td:216, 245, 290`; `IdrMatchOps.td:168`).
- *Counterexample:* `%k : !idr.cont<(i64)>`, then `idr.call @g(%k)` or `idr.yield %k`. Both pass ODS, and the continuation escapes into a callee or a match result. A non-escaping continuation is then written as escaping, and nothing refuses it short of a walk over its uses.
- *Root cause:* a dialect type is outside `AnyType`'s exclusion and outside the core verifier's token rules. Its argument types restate the target region's entry arguments.
- *Correction:* builtin `token`; the target region is read off the token's owner and argument number; the argument types are the region's.
- *Deletes:* the `!idr.cont` type, its printer and parser, its generated constraint, the check that the type agrees with the region, and any use-walk for escape.
- *Discriminated by:* an IR test where `idr.call @g(%tok)` is refused with upstream's "operand #0 must be any non-token type", and `"x.foo"(%tok)` with "consumes token operand #0 but does not have the TokenConsumerTrait".

**I2. Two ops: `idr.join` (non-recursive, tokens in the body) and `idr.loop` (recursive group, tokens in every region).** *owner* (extends D25's op list; D19's encoding).
- *Evidence:* §1.6 row 3. A value of region 0 does not dominate sibling regions. A repeating region is an essential difference in what the op may do (AGENTS.md "one op per semantics"; GHC's `join` and `joinrec`, *recalled*).
- *Counterexample:* with tokens in every region always, a 100-case consumer under case-of-case gets 100 × 101 = 10,100 token arguments. With one op per join point instead, the nesting is 100 deep, against D33.
- *Root cause:* token scope was not chosen, so repetition became implicit.
- *Correction:* §2.1.
- *Deletes:* `Tail/Loop.cpp`, `Tail/WhileDo.cpp`, `TailLoops.cpp`'s split, the flag payload.
- *Discriminated by:* the verifier refuses (by dominance, upstream's message) a jump in an `idr.join`'s join region to its own op. A counted-loop fixture runs with no `i1` carried across iterations in the lowered IR.

**I3. Carry five upstream fixes beside the PR (U1 to U5) and export the PR's propagation helpers (U8).** *coordinator* (AGENTS.md: an upstream bug is fixed upstream by patch; D25: "always carry the patch").
- *Evidence:* §1.3.4.
- *Counterexamples:*
  - U1: a resultless all-jump match is erased;
  - U2: `scf.if %true { scf.break [%l] }` under `-canonicalize`, IR changed and the pattern then failing;
  - U3: a dead join parameter partly removed;
  - U4: an out-of-bounds read of `visited` from a match whose case jumps to join region #k ≥ its region count;
  - U5: a match with a jump cannot lower.
- *Root cause:* the PR extends what a successor may be (a region of another op) but not every consumer of successors.
- *Correction:* one bug directory each, `upstream/<NN>-<name>/llvm.patch`. Each has its reproducer on upstream's dialects (`scf.loop`, `scf.if`; U5 on `scf.index_switch`), its `tests/upstream-<name>` check, its PINS.md entry, and its plan: a review comment on PR #166688 with the patch.
- *Deletes:* nothing of ours. Each prevents a workaround of ours.
- *Discriminated by:* each reproducer fails before its patch and passes after.

**I4. The backport is `upstream/<NN>-early-exits/llvm.patch`: the PR rebased by hand onto the pin with the five hunks of §1.3.3 resolved.** *coordinator*.
- *Evidence:* `tools/patches.sh:13-27`; `tests/upstream-patches/run:4-16`; `tools/bootstrap.sh:697-708` (`git apply`, no fuzz); §1.3.3's measurement.
- *Counterexample:* `upstream/<id>/llvm-project.patch` fails the policy test, and the PR's raw diff fails at `SCFToControlFlow.cpp` hunk 1 and `SCF.cpp` hunk 21.
- *Correction:* the name and the rebase.
- *Discriminated by:* `tests/upstream-patches` passes, and the bootstrap's `apply` step succeeds.

**I5. The join ops' lowering is ours, beside upstream's SCF patterns in one conversion; nested jumps are upstream's through U5.** *coordinator* (within D25's intent: "no control-flow reading of ours stands beside them").
- *Evidence:* §2.8; `Pipeline.cpp:186`; `Lower.cpp:144`.
- *Counterexample:* lowering `idr.loop` through `scf.loop` nests cannot express an irreducible group, a lexer entered at two states that call each other, without a run-time selector. And `scf.loop` has no structural type conversion (U6).
- *Root cause:* structured upstream ops cannot hold sibling re-entry.
- *Correction:* §2.8.
- *Deletes:* `createSCFToControlFlowPass()` at `Pipeline.cpp:186`, replaced by the combined conversion.
- *Discriminated by:* an irreducible two-state fixture lowers, and runs with output equal on the four targets.

**I6. A refined case binds a constructor *set*, and a case forwards the values its index refinement retypes.** *coordinator* for the match's side; L04 owns the type.
- *Evidence:* §2.4; `OpsMatch.cpp:85-91`, the default-region fold a singleton type would lose.
- *Counterexample:* `zip (x :: xs) (y :: ys)`. Inside the first match's `@Cons` case the second vector's type is still `Vect n b`, so its match needs a default arm and a tag test that Idris proved dead.
- *Root cause:* MLIR types are fixed per value, and the refinement Idris did lives in the case's environment.
- *Correction:* §2.4(1), (3), (4).
- *Deletes:* the three walks, the `tag` attributes, the dead defaults.
- *Discriminated by:* a program test where the lowered `zip` has one tag test per element pair.

**I7. Contification is Fluet and Weeks's, on regions, through return points.** *coordinator* (D19: "a local tail call contification finds").
- *Evidence:* §2.5; `Contify.cpp:10-13`; MLton `contify.fun:294-470`.
- *Counterexample:* a local `go` tail-called from both arms of an `if` stays a function today. Each call is a `musttail` call, and each path through `go` is a call instead of a jump (`Contify.cpp:96`).
- *Root cause:* regions without join points had nowhere to put a shared continuation.
- *Correction:* §2.5.
- *Deletes:* §1.7 rows 1 and 2.
- *Discriminated by:* (a) the lowered function has no call to `go`; (b) refusal fixtures' verdicts are unchanged with contification skipped by a debug counter (acceptance never moves, AGENTS.md); (c) deep recursion through contified bodies runs within D32's computed stack.

**I8. Case-of-case copies the dispatch and shares the bodies through join points.** *coordinator*.
- *Evidence:* `CaseOfCase.cpp:141-176`; 04 C08 (c179ab2d).
- *Counterexample:* a consumer match of size S under an inner match of M yielding regions grows the function by S × M today.
- *Root cause:* no shared continuation.
- *Correction:* §2.6.
- *Deletes:* the whole-consumer copy and the two-level move that kept it from fighting `YieldFields`.
- *Discriminated by:* the canon fixtures converge under `test-convergence`, and op count growth is bounded by dispatch copies (M7).

**I9. Two consumer adaptations of ours, in the same change as the backport.** *coordinator*.
- *Changes:* `Flow.cpp:44-52` reads the owner's inputs. `Linearity.cpp:27-33` defines alternatives as "no region successor owned by this op".
- *Counterexample:* without them, the first match with a jump fails `zip_equal` in `forwardFrom`, and the linearity verifier counts a linear value used once in each of two cases as two uses.
- *Discriminated by:* a linear scrutinee taken apart in one case, with the other case jumping, verifies.

**I10. Verification cost of the PR's per-op subtree walk.** *coordinator*, measured first.
- *Evidence:* §1.3.2. AGENTS.md verifies after every pass, and D33's `else if` ladders nest one match per branch.
- *Counterexample* (*conjecture* until M2): a ladder of depth d costs O(d²) per verification.
- *Correction, if it is a wall:* an upstream change in which an op that only propagates enumerates only the exits it owns. The target enumerates the nested exits that reach it. This also removes U3's cause structurally.
- *Discriminated by:* M2 before and after.

## 5. Work units (draft; none dispatched by this swarm)

**WU1. The backport.**
- *Write set:* `upstream/<NN>-early-exits/{llvm.patch,README.md}`, `tests/upstream-early-exits/{run,expected,suite}`, the PINS.md entry.
- *Outcome:* the toolchain carries the PR.
- *Deletes:* nothing.
- *Must not:* apply the raw diff; edit the pin's checkout.
- *Acceptance:* `tests/upstream-patches` passes; the bootstrap applies the patch. `mlir-opt -sccp` on the PR's `early_exit_dead_code` input folds the comparison to `false`, and `-convert-scf-to-cf` on its `loop_with_iter_args` input gives a back edge carrying the argument. Behaviour is read off results, not op sequences.

**WU2. U1 to U5 and U8.**
- *Write set:* `upstream/<NN>-{dead-op-escaping-exit,inline-path-owner,successor-input-owner,region-graph-nested-exits,index-switch-exits}/`, each with its check under `tests/upstream-*`.
- *Outcome:* each defect of §1.3.4 fixed on upstream's dialects.
- *Must not:* model any of them in our code.
- *Acceptance:* each reproducer fails without its patch and passes with it.

**WU3. The specification's entries.**
- *Write set:* the control-flow ops' entries in `compiler/spec/` (C7; L03 owns the specification's shape), and the generated `.td` and C++ (committed, D49).
- *Outcome:* `idr.join` and `idr.loop` as one family, `idr.jump`, the matches' new trait, and `idr.yield`'s parents.
- *Deletes:* any hand `.td` for these.
- *Must not:* declare `!idr.cont`.
- *Acceptance:* `make check` regenerates byte for byte (D49, D52).

**WU4. The ops' C++ and the two adaptations.**
- *Write set:* `idr/lib/IR/OpsJoin.cpp` (new), `idr/lib/IR/OpsMatch.cpp`, `idr/lib/IR/Regions.cpp`, `idr/lib/IR/Flow.cpp`, `idr/lib/IR/Verify/Linearity.cpp`.
- *Outcome:* §2.1, §2.3, I9.
- *Deletes:* `OpsMatch.cpp:78-94` once L04's refined type lands (otherwise in WU7).
- *Must not:* list ops in a concept (D47).
- *Acceptance:* IR tests refuse escapes (I1) and own-op jumps from an `idr.join` region (I2). An SCCP fixture shows a join parameter constant on every jump folding. A linear value used once per case, with one case jumping, verifies.

**WU5. Contification.**
- *Write set:* `idr/lib/Transforms/Optimize/Contify.cpp`.
- *Outcome:* §2.5. Needs L14's `ProgramGraph` and editor, and L10's tail fact.
- *Deletes:* §1.7 rows 1 and 2.
- *Must not:* add a budget that refuses. A cap may only decline.
- *Acceptance:* I7 (a) to (c). A two-state mutually tail-recursive local pair runs with output equal, and the lowered function has no calls between the two states.

**WU6. Loops.**
- *Write set:* `idr/lib/Transforms/Tail/TailLoops.cpp` (rewritten to §2.7, or absorbed into WU5's self-edge case); delete `Tail/Loop.cpp` and `Tail/WhileDo.cpp`.
- *Outcome:* `idr.loop` with `idr.may_loop` in partial code.
- *Must not:* drop the marker in partial code.
- *Acceptance:*
  - a self-recursive count to 10^8 runs within D32's stack;
  - an unused partial loop that crashes after 10^6 iterations makes the program crash with status 1, which proves it was not deleted (D13, D37);
  - the same loop proved `total` and unused is gone from the lowered program;
  - M5.

**WU7. Case-of-case and the match's refinement canonicalizations.**
- *Write set:* `idr/lib/IR/Canon/CaseOfCase.cpp`, `idr/lib/IR/Canon/Eta.cpp`, `idr/lib/IR/OpsConReads.cpp`, `idr/lib/IR/Canon/MatchPatterns.cpp` (the literal propagation of §2.4(4) and the all-exits form of §2.1).
- *Outcome:* I8 and the walks gone, with L04's type.
- *Must not:* keep `meetsInSomeRegion`'s clone probe if L13's `feeds` declaration lands (04 T2).
- *Acceptance:* I8's discriminator; a nested match on the same value in a default folds.

**WU8. The lowering.**
- *Write set:* `idr/lib/Conversion/Matches.cpp`, `idr/lib/Conversion/Lower.cpp`, `idr/lib/Conversion/Joins.cpp` (new), `idr/lib/Transforms/Pipeline.cpp:180-187`.
- *Outcome:* §2.8.
- *Deletes:* `Matches.cpp:30-37`'s poison yields; `createSCFToControlFlowPass()` in the pipeline.
- *Must not:* lower a nested jump itself; that is U5's lowering.
- *Acceptance:* the program suite with join points runs on all four targets with outputs equal, and I5's irreducible fixture runs.

**WU9. Formation for continuation values** (seam with L18).
- *Write set:* a step in `idr/lib/Transforms/Optimize/` after inlining (L18 owns the file list).
- *Outcome:* §2.6.
- *Acceptance:* the owner's CPS parser (match-and-counting §9) allocates no continuation cell for a parser whose continuation is applied twice in one function after inlining, measured by the runtime's allocation counter in a test build (not shipped, 18 R-AL-5).

**Measurements to take** (none taken here; each needs a build):
- M2: `--verify-each` time on S1's deep-nesting fixture and the stage-1 module, with and without the trait on matches.
- M3: join-point candidates at stage 1 (match-and-counting §11 item 2).
- M4: functions contified under §2.5 against today's rule on the stage-1 module, and the irreducible groups among them.
- M5: instructions per iteration on the benchmarks' self-recursive loops, `WhileDo`'s `scf.for` against `idr.loop`.
- M6: U1 to U5's reproducers.
- M7: case-of-case op growth on the canon fixtures.

## 6. Owner questions

**Q1. Is "a linear continuation called in tail position is never allocated" a promise to users, or an optimization?**
- *Context:* D19 says a join point is "never an allocated closure", and the representation makes that hold once a join point exists (I1). Whether a given continuation *becomes* one depends on inlining: the continuation is built in one function and applied in another until inlining brings them together (match-and-counting §9). A promise must be read off the program as the frontend wrote it, as D24's and D34's are.
- *(A) An optimization.* Formation runs after inlining and may miss a continuation, which then stays a counted heap cell taken apart once and reused. *Costs:* no promise. *Buys:* every continuation the optimizer localizes is free, with no rule to state.
- *(B) A promise for the syntactic subset.* A continuation lambda and all its applications in one function as written, failing with an internal error if missed. *Costs:* a rule with almost no instances in real code, because CPS passes the continuation to another function by design. *Buys:* a stated guarantee for that subset.
- *(C) A promise in general.* *Costs:* it requires guaranteed inlining across functions, which is unbounded code growth. *Buys:* the strongest statement.
- *Recommendation:* (A). The nearest real guarantee is already D30's: such a continuation call never grows the stack. A heap continuation chain on D31's typed frame stacks, not the counted heap, is a better place to promise something (§3, fact 2; L10's).
