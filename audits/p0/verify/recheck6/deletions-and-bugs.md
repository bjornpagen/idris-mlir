<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: §6's deletions, the lanes' deletion lists, §8's suspected bugs, the library CMake lists

HEAD at start 9f4889dd, at finish 80a2ec31. 80a2ec31 records C282 in
the proposal alone, a grade claim rule that touches no §6 or §8 row.

Commits that landed while this was read:
- e72a024f (L12v, `count.share`'s bufferization model);
- 13b0e15e (C280);
- 29153f20 (L16em, obligation 5: `Term.Termination` loses `Acyclic`);
- 2d7ee52d (L11z, C279);
- e518e35c (C281, L16em's stop);
- d093dbfb (L17bc: a case tree's `scTy` scoped);
- f7271225 (L03aa);
- 258be23d (L06j, patch 27);
- 1ab74a9d (L16en, Emit's constructor result claim);
- 80a2ec31 (C282, the proposal alone);
- 3beee5fd, ada7d302, b2a2c4ae, 1f998972 (audits and the queue).

The cited files those commits touch were read again:
- At b2a2c4ae:
  - `Translate/State.idr` (N7);
  - `spec/Ops/Bigs.idr` (§8 #4);
  - `Generated/IdrOps.td` (§8 #8, #24);
  - `lib/Transforms/Pipeline.cpp` (Process);
  - `Emit/Closures.idr` (L16's Emit row);
  - `Core/Case/CaseTree.idr` (N5's prerequisite).
- At 1ab74a9d, for 258be23d and 1ab74a9d:
  - `lib/IR/OpsCon.cpp` (§8 #16, #21; its lines shifted by one);
  - `Emit/Operations.idr` (the `Nat` literal);
  - `PINS.md` (Process);
  - `tests/upstream-one-shot-tensor-like-copy` and patch 27's README
    (§8 #32).

No verdict changed. Two citations moved: `nat.from_big` is now
`spec/Ops/Bigs.idr:405-415`, and §8 #16 and #21 are cited at 1ab74a9d.

C281 (e518e35c) amends C257, the route N7 waits on. It changes what
deletes N7's symbols, not whether they go.

Every verdict is against the committed tree (`git grep … HEAD`,
`git show HEAD:<path>`): at b2a2c4ae, and at 1ab74a9d for the files its
last two commits touch. The checkout holds uncommitted edits by running
lanes (`Optimize.h`, `Schedule.cpp`, `Open.cpp`, the checker's
`Unify.idr`, `TTImp/Elab/*.idr` and others). None was counted.

Nothing was built, typechecked, generated or run.

How the tree was searched: `git grep -n -w -F <symbol> HEAD` over the
tree, leaving out `audits/`, `proposals/`, `sources/`, `third_party/`,
`.claude/`, `bench/records/` and `AGENTS.md` (C251: AGENTS.md's "Never:"
lines and dated records are history kept on purpose), unless a row names
a narrower path. A symbol counts as gone when that search finds no
definition or use of it in code, tests, generated files, CMake, the
specification or current documentation. Names that appear only as
history are listed in §4.

Paths are under `foreign/idr/` unless they start with another top-level
directory. `spec/` is `compiler/spec/IdrisMLIR/Spec/`. Owners come from
`ownership.json`.

Grounds:
- *read*: the cited line was opened at b2a2c4ae.
- *measured*: a `git grep`/`ls-tree`/`comm` count at b2a2c4ae, with the
  command named.

## Counts

| part | rows | Done | Partial | Missing | Superseded | Regressed |
| --- | --- | --- | --- | --- | --- | --- |
| §6 and the lane lists, recheck 5 | 106 | 95 | 10 | 0 | 1 | 0 |
| §6 and the lane lists, recheck 6 | 106 | 99 | 5 | 0 | 1 | 1 |

Rows are recheck 5's: one top-level bullet of §2 that ends "Done", one N
row of §1, or the S row of §3. N1, N2, N3, N4 and N8 are now Done. The
regression is L19 §2.9's brittle lines: five prose `expected-error`
texts in three tests added since recheck 5 (R1).

| part | rows | Fixed | Still present | Refuted |
| --- | --- | --- | --- | --- |
| §8's suspected bugs, recheck 5 | 33 | 31 | 1 (latent, unreached) | 1 (void, D48) |
| §8's suspected bugs, recheck 6 | 33 | 31 | 1 (latent, unreached) | 1 (void, D48) |

The library CMake lists name 337 sources, and every one exists. Every
one of the 337 `.cpp` files under `lib/` is named. Recheck 5 counted 332.

## 1. §6 and the lane lists: not Done

### N5. L16 §2.6, T2: `siblings`, `coversAll`, `instanceOf` — **Partial**

- **Gone:**
  - `siblings`: no definition or use in `compiler/src` (*measured*: the 10
    hits are prose about passes and sibling ops).
  - Cases' `coversAll`: gone. The `coversAll` left is an unrelated proof
    lemma (`compiler/src/IdrisMLIR/Proof/Covers.idr:1798`). Both went in
    088c8197.
- **Still there:**
  - `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr:592-611`:
    `instanceOf`.
  - It reads the family from the binder's Core type (`DataT d` through
    `dataFamilies`).
  - Where the Core type names a choice, it falls back to normalising the
    binder's Idris type at each match (`normaliseClosed ity'`, then
    `dataOf`).
  - The match's own `scTy` is read only for an equality proof
    (`Cases.idr:691`).
- **What changed under it:** d093dbfb (L17bc) made `scTy` a term of the
  tree's own variables at its node, so the fact T2 asks for is now
  readable at the boundary. That was the queue's L16ek item.
- Ground: read. Owner: L16.
- **Remaining:** see the dispatchable items (L16-1).

### N6. L16 §2.6, T6: `rootOf`'s climb — **Partial**, unchanged since recheck 5

- **Done:** `keyOrigin` no longer searches, and a case or with block's
  parent is a `Name` (`compiler/checker/src/Core/Name.idr:49-50`).
- **Still there:**
  - `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:567-589`:
    `rootOf` climbs `Nested (outer, _)` by context placement (`:578`) and
    enters each parent once through `Walk`.
  - `Translate/Boundary.idr:187`: `parentOf (Nested (outer, _) _) =
    Just (Resolved outer)`.
  - `compiler/checker/src/Core/Name.idr:43`: `Nested : (Int, Int) ->
    Name -> Name`. The parent is still a session's context index.
- Ground: read. Owners: L16 (frontend), L17 (checker).
- **Remaining:** L17-1, then L16-2.

### N7. L16 §2.6 and §6: the growth check's run-time re-check — **Partial**, unchanged; the route is now C281

- **Still there:**
  - `compiler/src/IdrisMLIR/Frontend/Finite.idr`: `unsound` at `:171-172`,
    an `internal` error; `heightWithin` at `:180-188`; `sizedWithin` at
    `:190-216`.
  - `Translate/Types.idr`: `boundsHold` at `:601-606`; its uses at
    `:906-907`.
  - `Translate/State.idr`: `TS.bounds` at `:1981` and `TS.sizes` at
    `:1985`.
  - `Proof/Requests.idr`: `lteThrough` at `:733`, `climb` at `:745-754`,
    `fitsWithin` at `:759-763`, `within` at `:1010`.
- **The route:** C281 (e518e35c, for the owner's review) amends C257.
  - The growth model's walk records every decided request in its tree.
  - The translation folds that tree and computes no request of its own.
  - With the lemma's induction over the model's walk, that deletes
    `Finite.unsound`, `heightWithin`, `sizedWithin`, `Types.boundsHold`
    and the translation's request computation.
- Ground: read. Owner: L16.
- **Remaining:** L16-3.

### N9. L19 §2.9: Contracts' hand `Relation`, `Breakable` and the length guard — **Partial**; recheck 5 is corrected

- **Gone:**
  - The module clone. Contracts compare per-function records
    (`lib/Transforms/Contracts/Contracts.cpp:100-105`, `recordOf`).
  - `Breakable`: 0 (*measured*; 7878bda0). The test option is an
    `Option<Relation>` read from the one table (`:341-366`).
- **Still there:**
  - **The length guard.** `Contracts.cpp:150-151`:
    `if (before.size() != now.size()) return;`.
    - Recheck 5 reported it gone. It was there then too
      (5c726265:`Contracts.cpp:132`).
    - Its comment (`:143-145`) rests the skip on "the derivation the
      copying passes share", and `:119-121` says the same of a copy.
    - Nothing checks that a changed list is what that derivation gives.
      So L19 §3.2's loss stands: "a pass that drops one parameter and
      weakens another escapes".
  - **The hand table.** `Contracts.cpp:61-89`: the `Relation` enum and
    its constexpr name-and-breaker table. L19 §2.9 replaces it by
    derivation. The idr-expect properties are already printed from
    `harness/Properties.idr` into `ExpectProperties.inc`.
- Ground: read. Owner: L19.
- **Remaining:** L19-1, L19-2.

### N10. L12 §2.7 and I12: the array externs' hand table and case — **Partial**, unchanged

C6 was withdrawn and replaced on 2026-10-21 (L03 §1.9): each row names
the specification's op. The deletion stands.

- **Done:** `merge`'s identity entry is gone (`Registry/Recognized.idr:115`
  composes it from the extents given).
- **Still there:**
  - `compiler/src/IdrisMLIR/Registry/Entry.idr:210-213`: the hand enum
    `ArrayPrim`.
  - `Entry.idr:219-239`: the hand `generatedOperands` table.
  - `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:2383-2569`:
    `arrayTerm`, the hand case composing each primitive, `merge` from
    `Reshape` and `Extent` among them (`:2429-2442`).
  - The readers: `Registry/Faster.idr:69, 97`, `Recognized.idr:73, 115`
    and `Frontend/Resolve.idr:468, 568`.
  - The specification declares no op or composition for them
    (*measured*: `git grep -i -w 'merge\|reshape' HEAD -- spec/Arrays`
    gives 0).
- Ground: read. Owners: L16 (registry, translation) and L12
  (specification).
- **Remaining:** L12-1, then L16-4.

## 2. §6 and the lane lists: Done

Every row below was checked for a regression at b2a2c4ae by the search
above. "0" means no hit outside history. Each residual hit is accounted
for.

### Recheck 5's not-Done rows now Done

- **N1. Tail position's climb** (D30, C20 as amended by C203's
  sharpening of 2026-10-23) — **Done** in f46fe91d.
  - `inTailPosition`, `wayOf`, `repackedTailOf` and `decide(CallOp)` give
    0 (*measured*). `tail::decided` (`EGraph/Elaborate.cpp:451`) is a
    stage test.
  - Where a function's tails are is read one way, down from its body:
    `tailsOf` and `sourcesOf` (`include/idr/IR/Tail.h:66-86`). The
    verifier checks both ways against the same walk
    (`lib/IR/Tail.cpp:298-330`).
  - C203 sharpened keeps `decideTails` (`Optimize/Tails.h:34-49`, rebuilt
    on the walk) for the passes whose edit moves a call without knowing
    its kind.
    - Its 12 calls (*measured*) are exactly C203's list: the first-order
      program (`Defunctionalize/Pass.cpp:78`), the e-graph's write-back
      (`EGraph/Elaborate.cpp:452`), inlining (`Inline.cpp:160`,
      `InlinePass.cpp:50, 62`), narrowing (`Narrow.cpp:192`), capture
      drops (`CaptureDrops.cpp:116`), raising (`Specialize/Raise.cpp:161`),
      frames (`Tail/Frames.cpp:189`) and TRMC (`Tail/Trmc.cpp:164-165`).
    - A pass that knows the kind writes it (`Deduplicate.cpp:399`,
      `Contify.cpp:246`, `Redirect.cpp:145, 208`, `Open.cpp:943`).
  - The four readers that asked it of ops that are not calls now read
    the function's tails once: `Analysis/LabelSites.cpp:311`,
    `Defunctionalize/Edits.cpp:91`, `Tail/AccumulatorPlan.cpp:281`,
    `Tail/Continuations.cpp:226, 261`.
  - Ground: read.
- **N2. The cycle rule written in four places** (D30) — **Done** in
  fc6fb0f8.
  - It is stated once: `isCycle(members, edgeToItself)`
    (`include/idr/Analysis/Solver/Components.h:48-53`).
  - Its askers: the partition's `cyclic` (`:104`), `ProgramGraph::onCycle`
    (`ProgramGraph.h:141-144`), Effects' component (`Effects/Component.cpp:118`)
    and Settle (`Optimize/Settle.cpp:193`).
  - Each supplies only its reading of a lone member's self-edge. The
    optimizer's components grow apart from the frozen graph, so they
    cannot share its `SccId`.
  - The four hand tests are gone (*measured*: no
    `members.size() > 1 ||` outside `Components.h:52`).
  - Ground: read.
- **N3. Effects read outside the one API** — **Done** in 7878bda0.
  - `Tail/Outline.cpp` has no `isPure` (*measured*: `isPure` 0).
  - The two readers left ask the effect API and upstream's speculation
    interface: `IR/Lifetimes/Loans.cpp:166` (`effects::whole(op) ==
    EffectSet{} && isSpeculatable(op)`) and `Tail/AccumulatorPlan.cpp:151`.
    Recheck 5 named that form as the remedy.
  - Ground: read.
- **N4. `applyOver`'s `ValueType` refusal** (L16 §2.6, T1) — **Done** in
  088c8197.
  - The refusal text "whose type is not known here" gives 0 (*measured*).
  - `applyOver` takes the function's Idris type as a `ClosedTerm`, not a
    `Maybe` (`Translate/Terms.idr:1594-1597`).
  - An argument past every binder the type shows is refused as
    `CompiledModule`, malformed checked input (`:1611-1614`).
  - Ground: read.
- **N8. `partialEvalNS`** (L17 §2.8) — **Done** in 1c8e1d7d (L17bb).
  - `partialEvalNS` and `K_PE` give 0 in code.
  - The one hit is the checker's README account of the deletion
    (`compiler/checker/README.md:85`), which C251 keeps.
  - Ground: measured.

### P0 §6, by area

**Effects**
- L02 §1.4's table gives 0 each (*measured*): `bodyEffect`,
  `componentEffects`, `writeEffects`, `effectsCovered`, `appendEffect`,
  `effectInstances`, `solveEffects`, `observableRuns`, `LabelsRun`,
  `doesOf`, `usesWorld`, `onlyAllocates`, `performsIO`, `mayRunAt`,
  `anyEffect`, `Idr_Effect`, `Effect::none`, `bitEnumContains`,
  `IOResource`, `setEffects(`.
- `lib/Analysis/Effects.cpp` and `Transforms/Effects/Effects.cpp` are
  absent. No test has `effects<`. Done.
- `Expect/ResetsUnshared.cpp` asks the one API. Done.

**Types and ops**
- The grade's free enums and functions (D88, D90) give 0 each: `QType`,
  `Lifetime::Heap`, `fitsIn`, `holdsOwn`, `mayBeFrame`, `!idr.lin`,
  `!idr.own`, `!idr.qtype`, `!idr.view<`, `view.make`, `idr.view`,
  `frame_lifetime`, `idr.share`. Done.
- The kind and role table gives 0 each: `namespace role`, `emptyRole`,
  `TableCtor`, `TableMember`, `DataDefinition`, `isBoxed`. Done.
- `ValueFacts`' 55 hand answers. Done.
  - The type answers are printed from the specification
    (`lib/IR/ValueFacts.cpp:3-12`).
  - Four answers that the type's parameters decide are written by hand
    (`:203-225`: `LifetimeType`, `ReuseTokenType`, `DestType`,
    `CellType`). D126 round 3-A (aaa578c6) declares them so.
- Marker traits no reader needs. Done.
  - 14 of the 15 generated native traits have a C++ reader outside
    `Generated/` and `Traits.h` (*measured*: 2 to 14 hits each).
  - The fifteenth, `ResultUsesMax`, is read by its own `verifyTrait`
    (`Traits.h:113-129`), which MLIR runs on every op that carries it.
- The hand `def`s of family members. Done.
  - Every `.td` of ours is under `include/idr/IR/Generated/` (*measured*:
    `git ls-files '*.td'`).
  - The only others are tests' witnesses and near misses, `sources/`
    snapshots and an upstream patch's fixture.
- `own.adopt` and `own.give`'s def-use verifiers. Done.
- 38 hand folders: `ToIntOp` gives 0. Done.
- `#idr.types`, `MutableType`, `DataRemap`, `DataBody.cpp`, `Fit.cpp`,
  `!idr.box`, `Idr_SumKind`, `Idr_CtorRole` give 0. Done.
  - `Declarations`' 114 hits (*measured*) are other things: spec module
    names, `Lower/Declarations.cpp`, the checker's doc styles.
  - No `class Declarations` or `Declarations::` is in `foreign/`.
- The `tag` attributes (C19). Done.
  - No op has a `$tag` argument.
  - The one `:$tag` hit is a builder's `$tags` list
    (`Generated/IdrOps.td:570`).
- Lifetime variables in types (D63): `LifetimeVar` and `lifetimeVars`
  give 0. Done.

**Analyses**
- 0 each: `CallCycles`, `Scc.h`, `Scc.cpp`, `stronglyConnected`,
  `MonotoneWorklist`, `FiniteLattice`, `ReadySet`, `ReturnedAnalysis`,
  `KnownLattice`.
- `Recursion` is only the frontend's `Translate.Recursion` module and
  prose.
- `SymbolUserMap` appears only in `upstream/88-…` (upstream's code) and
  that patch's test. Done.

**Simplification**
- 0 each: `applyPatternsGreedily`, `applyOpPatternsGreedily`,
  `createCanonicalizerPass`, `createCSEPass`.
- `GreedyRewriteConfig`, `getCanonicalizationPatterns` and
  `hasCanonicalizer` appear only in `upstream/62-…` and `65-…` patches
  and in `tests/no-fuel/witness/` (a planted witness, C251). Done.

**Frontend representation bugs**
- A `Nat` literal is one constant
  (`compiler/src/IdrisMLIR/Emit/Operations.idr:251-252`).
- `array.read` gives back `$after` (`Generated/IdrOps.td:963, 971`).
- `WithBounds` is a sum (`compiler/checker/src/Libraries/Text/Bounded.idr:76-78`).
- Done.

**Process**
- The pipeline order is held once: `lib/Transforms/Pipeline.cpp:3-7`
  reads the specification's list.
- `createRemoveDeadValues` gives 0. `remove-dead-values` appears only in
  `PINS.md`'s account of the retired patches and in `upstream/`.
- Patches 06, 28 and 63 have no `.patch` (*measured*).
- `bench/run.sh` has no `ulimit`.
- No "1 MiB" in `tests/`.
- `tests/defunc-tag-limit` is absent.
- D115 holds.
  - `tools/bootstrap.sh:926` passes `-DLLVM_ENABLE_ASSERTIONS=ON`.
  - `foreign/idr/CMakeLists.txt:36-45` strips `NDEBUG` and refuses an
    LLVM without assertions outside the typecheck build. Recheck 5 cited
    the top-level `CMakeLists.txt`, a slip.
- Done.

### L04 §2.18

- 0 each: `getCtors`, `getCtor`, `getTags`, `isClosures`, `isAtom`,
  `getListElement`, `walkLabels`, `replaceLabels`, `solveHeld`, `roleTag`,
  `isDefined`. The one `verifyBody` is upstream's, in
  `upstream/99-…/README.md:59`. Done.
- `Idr_BoxType`, `Idr_SumType`, `Idr_DataTableAttr`, `Idr_BaseListOf`,
  `BoxType`, `DataTable`: 0. Done.
- `InstanceAttr`: 0. Recheck 5's stale `Ids.idr` comment is gone
  (`#idr.instance` 0 in `compiler/src`). Done.
- `canonicalText`, `canonicalHash`, `data_types`: 0. Done.
- `idr.program`'s `types` property and `TypeGraph`'s value walk: as
  recheck 5. Done.
- The Idris side: `DataShape`, `IdrSum`, `Newtype` give 0. Done.

### L14 §1.4

- `CallCycles`, `Recursion`, the seven `SymbolUserMap` constructions,
  the twelve name-keyed and four pointer-keyed maps, `Scc.cpp`'s
  copies: as above, 0. Done.
- Returned's whole-module solve: `ReturnedArguments` 0. Dead results
  are one fixpoint (`lib/Transforms/Optimize/Results.cpp:3-17`).
  `[[maybe_unused]]` gives 0. Done.
- Each solver's private graph and numbering: as recheck 5. Done.

### L05 §2.10

- `madeStatic`, `Phantom`, `isCountedElement`, `idr-rc-stack`,
  `loopsInFrame` and `IDRIS_RT_STACK_CELL` give 0.
- One linearity verifier remains.
- `DataFlowSolver` is used only by Ranges, Constants and Narrow
  (*measured*: `include/idr/Analysis/{Ranges,Constants}.h`,
  `Transforms/Narrow.h`, `lib/Analysis/Ranges.cpp`,
  `Transforms/Effects/Constants.cpp`).
- Done.

### L07 §2.15

- 0 each: `Reuses`, `TakenField`, `Positions.cpp`, `ownsReference`,
  `endsInCrash`, `rebindDefaults`, `takeReadSums`, `takeReadBoxes`,
  `rewriteSelects`, `sinkConsumers`, `Fields.h`, `Fields.cpp`.
- `Uses.cpp`'s one hit is `lib/IR/Verify/Uses.cpp`.
  - That file holds the structural source and value positions. It has
    stood since 1e1a3827.
  - It is not `lib/Analysis/Ownership/Uses.cpp`, which L07 deletes and
    which is absent.
  - `lib/Analysis/Ownership/` holds `Borrows`, `Exclusivity`,
    `ExclusivityAnalyses` and `ExclusivityGraph` alone (*measured*).
- Done.
- `Elements.cpp`'s take test: **Superseded**, see S1.

### L08 §2.7

- 0 each: `IdrDemand`, `createIdrDemand`, `unknownFrom`, `givesExclusive`,
  `HoldingState`, `Sharing::Unknown`. Done.
- `Inference` names Borrows' marking class
  (`lib/Analysis/Ownership/Borrows.cpp:109-127`), a CSR marking over the
  program graph. It is not the `DataFlowSolver` inference L08 deletes.
  - The class stood at recheck 5 too (5c726265:`Borrows.cpp:109`), so
    recheck 5's "0" was a miscount, not a deletion.
  - Done.

### L09 §2.11

- 0 each: `WhileDo`, `Eta.cpp`, `runningRegions`, `!idr.cont`.
- `Tail/Loop.cpp` and `Tail/WhileDo.cpp` are absent.
- Done.

### L10's list

- 0 each: `TailPosition.{cpp,h}`, `TailCallPlan.{cpp,h}`, `numFrameBound`,
  `endsTail`, `inTailPositionModuloContext`, `forTails`,
  `reachesTailCall`, `passesOnPrevious`, `tailMatch`.
- `Conversion/Frame*` is absent.
- The climb: N1, Done.
- Frames give 0 each: `memberCalled`, `closureLabels`, `madeInRest`,
  `caseCallee`, `FramesPlan`, `FramesMade`, `stackTypeOf`, `answerTypeOf`,
  `fromAnswer`, `asAnswer`.
- `heldAs` is now a general cast helper whose precondition is that the
  hold fits (`include/idr/IR/Grades.h:343-348`). It has over twenty
  callers.
  - No pop in `Tail/` re-asserts a pushed value's quantity.
  - The one `Tail/` caller forgets an accumulator's refinement
    (`Tail/Accumulate.cpp:78-83`).
- `stackSize`, `guardSize`, `alternateSize`: 0.
- Done.

### L11 §2.10

- 0 each: `heapRegion`, `ensure_init`, `initialising`, `is_initialised`,
  `liveCells`, `forgetCell`, `idris_rt_live_cells`, `tooLarge`,
  `checkStatus`, `IDRIS_RT_CRASHED`, `reportLiveCells`,
  `idris_rt_main_return`, `idris_rt_io_exit`, `idris_rt_crash_str`,
  `idris_rt_gmp_init`, `MAP_NORESERVE`, `RootKind::Status`,
  `countFoldLeak`, `IDRIS_RT_LIVE`, `crashMessage`.
- "stack exhausted" and "no stack could be reserved" give 0.
- `runtime/` has no `idris-mlir: ` prefix.
- `harness/lib/` holds `harness.sh` alone.
- Done.

### L12 §2.7

- 0 each: `Nests.cpp`, `lowerOrdered`, `cloneRegion`, `emptyOf`,
  `structurable`, `GeneratingOpInterface`, `Idr_Iteration`,
  `getIterations`, `getExtentBound`, `reifyTabulated`,
  `reifyDimOfResult`, `boundTabulated`, `TabulateIOOp`,
  `TransposeColumns`, `ElementUpdateOp`, `StoreModel`, `HeapReadModel`,
  `MemoRunModel`, `MatchModel`, `EnterModel`, `UseModel`, `isLink`,
  `#idr.world`.
- The `heldType` hits are the growth model's field
  (`Growth/Heads.idr:764`), not the C++ one.
- Recheck 5's stale `upstream/58-…` sentence is gone. Done.
- The hand compositions in `Terms.idr`: N10, Partial.

### L16 §2.6

- 0 each: `Forced.idr`, `erasedArgs`, `quantitiesOf`, `lastRuntime`,
  `elaboratedFile`, `mostUses`, `holdFor`, `quantityText`,
  `idr.refusals`, `Types.signed`.
- Erasure has one source (`Translate/Closed.idr:411-414`, `eraseArgs`).
- Emit writes a termination proof per component
  (`Emit/Closures.idr:71-79`, `Terminates` or `MayDiverge`).
- `delayedLets` moves only the elaborator's `Delay`
  (`Translate/Closed.idr:283-285`).
- `TS.bounds` and `TS.sizes` remain: N7.
- Done otherwise. T1 is Done (N4). T2, T6 and the growth re-check are
  N5 to N7.

### L17 §2.8

- 0 each: `ambigLimit`, `KwAutoImplicitDepth`, `foreignImpl`,
  `caseTreeHeuristics`, `debugElabCheck`, `toCompileCase`,
  `canInlineCaseBlock`, `canInlineDef`, `refersToRuntimeM`.
- The `mkRunTime`, `compileRunTime`, `processTTImpFile` and
  `nextIdxByScore` hits are history in `compiler/checker/README.md` and
  `upstream/{52,105,110}-…`.
- `isWindows`, `Volume`, `dirSeparator`, `pathSeparator` and
  `pathLookup` appear in the checker's README account of the deletion.
  The one exception is `tests/system-info/Main.idr:12`, a user program
  calling base's `isWindows`.
- `Path.idr` imports no `System.Info`.
- `partialEvalNS`: N8, Done.

### L19 §2.9

- `harness/lib/` holds `harness.sh` alone. The harness depends on
  `idris-mlir-spec` alone (`harness/harness.ipkg:9`). Done.
- `Prims.idr`, the Expect declarations and `Quantities.cpp`'s `keyOf`
  (0): as recheck 5. Done.
- Pass names in RUN lines: tool options only. Done.
  - *Measured*: `--idr-expect` 27, `--idr-pipeline` 7, `--idr-contracts`
    6.
  - Inside `--pass-pipeline` strings: `idr-pipeline` 40, `idr-expect` 16.
  - No transform pass.
  - `--idr-target` is gone with C279.
- `bench/run.sh`'s `ulimit -s`, the "1 MiB" comments and
  `defunc-tag-limit` are gone. Done.
- **R1. Brittle lines — Regressed.**
  - 75 `expected-error` lines (*measured*; recheck 5 counted 42).
  - Most are a property prefix (`expected <property>:`,
    `contract <relation> broken by`) or `{{}}`.
  - Five check a prose verifier message, and none did at recheck 5
    (*measured* at 5c726265):
    - `tests/owner-ended-after-field-read/owner-ended-after-field-read.mlir:81`
      ("uses a value used once that is already used on the same path")
      and `:103` ("binds in its shared region other than"), added by
      19307ee9 (L07z);
    - `tests/partial-self-call-diverges/partial-self-call-diverges.mlir:40`
      ("which lack divergence"), added by a6dccbff (L02y);
    - `tests/root-takes-and-gives-nothing/root-takes-and-gives-nothing.mlir:25`
      ("is the root, so it takes nothing; it takes 1 arguments") and `:34`
      ("is the root, so its results hold no runtime value"), added by
      1af4154c (L19p).
  - C12 and L19 §2.9 delete prose `expected-error` texts.
  - No `facts:` remark is left. The two hits are prose in `run` scripts.
  - `CHECK` lines are only in check tests' witnesses, near misses and
    `run` scripts.
  - Owner: L19. Remaining: L19-3.

## 3. Superseded

- **S1. The element take's run-time test** (C39, L07 §2.15, L12;
  `Elements.cpp`): **Superseded by C250 (corrected, 2026-10-22)**,
  unchanged.
  - `takeOut` tests only where the array's claim does not cover its
    storage. `boxSharingOf` is `Unshared` under `unique self`
    (`lib/Conversion/Elements.cpp:109-135`).
  - Ground: read.

## 4. Comments naming deleted symbols

History, fine (C251):
- AGENTS.md's "Never:" lines.
- `compiler/checker/README.md:81-113`: `mkRunTime`, `compileRunTime`,
  `PartialEval`, `partialEvalNS`, `processTTImpFile`, `isWindows`,
  `Volume`, `dirSeparator`, `pathSeparator`, `pathLookup`.
- `PINS.md:67-96`, the retired patches.
- `upstream/*/README.md`'s accounts.
- `bench/records/*`.

Stale, written as present fact: none found. Recheck 5's two are gone:
- `compiler/src/IdrisMLIR/Ids.idr`'s `#idr.instance` sentence;
- `upstream/58-…/README.md`'s `Nests.cpp` sentence.
Both went in 7878bda0.

## 5. §8: the suspected bugs

| # | bug | verdict | evidence at b2a2c4ae | ground |
| --- | --- | --- | --- | --- |
| 1 | acceptance rests on reuse, stack, inliner, borrows, dead code | Fixed | defunctionalize, knots, in-place, then deduplicate (`Generated/Pipeline.h.inc:23-33`); `Demand`, `Stack`, `Reshape` absent | read |
| 2 | exclusivity: a crash case counts as an unknown predecessor | Fixed | `lib/Analysis/Ownership/ExclusivityGraph.cpp:11-17` | read |
| 3 | a summary ignores its ops: handle-table read, `exit`, memo state | Fixed | `runtime_state`, `exit`, `memo_state` are resources (`Generated/EffectTree.h.inc:72-82, 219`) | read |
| 4 | IO ops without `IOResource`; declarations not stating their runtime function | Fixed | `handle.string` reads runtime state and guards `NotAString` (`spec/Ops/Platform.idr:496-505`); `array.new` allocates and writes a count (`spec/Arrays/Memory.idr:80`); `array.yield` consumes (`:222`); `own.adopt` and kin give a new identity (`spec/Counting/Declarations.idr:195-494`); `nat.from_big` writes a count and acquires nothing (`spec/Ops/Bigs.idr:405-415`, moved by f7271225) | read |
| 5 | an `Allocate` on an identity reads as fresh memory to `LocalAliasAnalysis` | Still present, latent and unreached | `FreshIdentity` is still `Allocate` on `Identity` (`spec/Effects/Declaration.idr:301`); no pass of ours runs an alias analysis (*measured*: `AliasAnalysis` 0 in `foreign/`) | read |
| 6 | the lowering gives a row `memory(none)` and an IO row `willreturn` | Fixed | counts and memo state write `ArgMem` and `Other`; IO withholds `willreturn` (`spec/Effects/LLVM.idr:123-149`) | read |
| 7 | Euclid, shifts, char conversions written several times; `ToIntOp::fold` | Fixed | one template (`include/idr/IR/Numeric/`), included by `runtime/Big/Arithmetic.cpp:7-8`, `lib/Conversion/Scalars.cpp:13`, `Checks.cpp:14-15`; `ToIntOp` 0 | read |
| 8 | `delay` lacks the capture rule; `dup` accepts a quantity-1 view | Fixed | `lazy.delay` carries `ResultUsesMax` (`Generated/IdrOps.td:2792`); `count.dup` takes a counted value used many (C87, `isUsedMany` in its constraint), so a scoped or once value cannot be duplicated | read |
| 9 | (void) `DataRemap`'s content keys | Refuted, void (D48) | `DataRemap` 0 | measured |
| 10 | the TTC drops a `let`'s type | Fixed | `compiler/checker/src/Core/TTC.idr:505, 517, 520, 642-652` | read |
| 11 | erasure decided five ways; a block's parent as printed text | Fixed | one source (`Translate/Closed.idr:411-414`); `CaseBlock (parent : Name)` (`Core/Name.idr:49-50`); the nested parent is N6 | read |
| 12 | Emit demotes a quantity-1 binder; `quantities-kept` drops colliding keys | Fixed | `Emit/Monad.idr:138`, `Emit/Declarations.idr:33`; `keyOf` 0 in `Expect/` | read |
| 13 | termination unsound under specialization; `delayedLets`; doubles as text | Fixed | divergence from the proof (`Effects/Component.cpp:118-120`); `delayedLets` (`Closed.idr:283-285`); doubles as bits (`MLIR/Bytecode.idr`) | read |
| 14 | a lift depends on lock order | Fixed | names read a form's digest; judging takes no lock (`include/idr/Transforms/SpecializeState.h:7, 105-121, 144`) | read |
| 15 | inlining edits a function outside a pass | Fixed | `idr-inline-leaves` is an inner pass (`Generated/IdrInnerPasses.td:22`) | read |
| 16 | `absorb` clears `total`; a static memo cell; dedup before knots; seven refused tests | Fixed | `absorb` 0 in code (the hit is a lexer comment); a memo cell never folds (`lib/IR/OpsCon.cpp:133-141`); knots before dedup; the seven tests expect `compile: exit 0` (*read*, not run) | read |
| 17 | borrows over allocations; crash paths without drops; extra tests | Fixed | the frame-limited rule (`Borrows.cpp:1-19`); on a path that ends the process every value is freed before its last allocation (`Counting/Placement.cpp:58-61`); a token free tests at most null (`runtime/Rc/Counting.cpp:110-125`) | read |
| 18 | Borrows' solve behind `[[maybe_unused]]`; `own` recurses | Fixed | `[[maybe_unused]]` 0; Borrows is one marking (`Borrows.cpp:109-127`) | read |
| 19 | three walks rebuild a match's constructor; contify leaves two blocks | Fixed | as recheck 5; `Eta.cpp` 0 | read |
| 20 | returned-arguments drops a tail callee's result, not its caller's | Fixed | `Optimize/Results.cpp:13-17`; `ReturnedArguments` 0 | read |
| 21 | a linear value loses its quantity at a frame's push | Fixed | a push checks the hold (`OpsCon.cpp:126-128`); no `heldAs` pop in `Tail/` (§2, L10) | read |
| 22 | every linear array read from a cell is a writable root | Fixed | `Bufferize/Releases.cpp:59` (`bufferClaim = Unique::Self`) | read |
| 23 | `merge` as identity drops its extents | Fixed | `Translate/Terms.idr:2429-2442` | read |
| 24 | crash sites from `Location` merge under `MergeIdenticalRegions` | Fixed | `Idr_SiteAttr:$site` on 9 ops (*measured*, `Generated/IdrOps.td`) | read |
| 25 | no stack probes; guard over the signal stack; "stack exhausted" | Fixed | `runtime/Start/Runner.cpp:3-5`; `StackExhausted` (`spec/Runtime/Endings.idr:152`); the text gives 0 | read |
| 26 | snmalloc's fatal errors abort unflushed; a refused commit ignored | Fixed | `runtime/Alloc/Cells.cpp:47-53` | read |
| 27 | `idris-mlir:` prefix; buffered output lost; four crashes without a site; `getString` | Fixed | no prefix; the four cases print `prog: fatal: Main.idr:19:12: …` (`tests/buffer-range/cases/{3,9,below-zero,no-input}/expected-stderr`) | read |
| 28 | pool workers get the OS's default stacks | Fixed | as recheck 5 | read |
| 29 | pipeline order held twice; dead `remove-dead-values` | Fixed | §2 "Process" | read |
| 30 | `maxNumRewrites` unset; the greedy driver where our ops are | Fixed | §2 "Simplification" | measured |
| 31 | `OsOp::fold` reads the build machine's triple; the Windows path grammar | Fixed | the fold reads the module's target or folds nothing (`lib/IR/OpsPlatform.cpp:30-50`); §2 L17 | read |
| 32 | patch 27 cites a missing test | Fixed | `tests/upstream-one-shot-tensor-like-copy` exists (*measured*: `git ls-tree`) | measured |
| 33 | (fixed on main) `Positions` | Fixed | `Positions.cpp` 0 | measured |

## 6. The library CMake lists

Command, at b2a2c4ae:
- extract every `*.cpp` named in `foreign/idr/lib/CMakeLists.txt` and
  `lib/{Analysis,IR,Support,Target,Transforms}/CMakeLists.txt`, with
  comments removed;
- prefix each with its list's directory;
- `comm` the result against
  `git ls-tree -r --name-only HEAD foreign/idr/lib | grep '\.cpp$'`.

Results:
- 337 sources named, 337 files present, 0 named and missing, 0 present
  and unnamed. *Measured.*

## Seen outside the range

These are unchanged since recheck 5:
- The handle-to-id numbering maps outside `IdrIR` (§5.2, C236):
  `Solver/Extraction.h:145`, `Solver/LabelPoints.h:94`,
  `Bufferize/Releases.cpp:117`, `Narrow/Widths.cpp:104`.
- `EGraph/Simplify.cpp:147`'s per-node `Root` map.
- `include/idr/Driver/Verdict.h:78`'s statistics keyed by name text.

New:
- `Translate/Terms.idr:1636`: an `internal` error, "an application …
  whose Core type … is no function's". It is in `applyOver`, which N4
  left. The Core type is read apart from the Idris type that says it is
  a function's. That is D112's, with L16ek's `Types.coreTypeIn` returning
  both (queue).

## Dispatchable items, by owner

**L16** (`compiler/src`). Every item waits on L16em's files
(`Translate/`, `Growth/`; the threading pass, whose route C281 now
sets).
- **L16-1 (N5).** Read a constructor match's family off the case tree's
  `scTy` once, at the boundary.
  - Where: `Translate/Cases.idr:534` and `:592-611`.
  - `scTy` is scoped since d093dbfb.
  - Delete `instanceOf`'s Core-type lookup and its per-match
    normalisation of the binder's Idris type.
  - The registry's mismatch refusals (`HookShape`) stay, read from the
    same type.
  - Evidence: N5.
- **L16-2 (N6, frontend half; after L17-1).** `rootOf` reads a nested
  block's typed parent.
  - Delete the climb and its `Walk`: `Translate/Closed.idr:567-589`.
  - Delete `Boundary.parentOf`'s `Nested` arm: `Translate/Boundary.idr:187`.
  - Evidence: N6.
- **L16-3 (N7, by C281).** The growth model's tree records each decided
  request, and the translation folds it.
  - Delete `Finite.idr:171-216` (`unsound`, `heightWithin`,
    `sizedWithin`), `Types.idr:601-606, 906-907` (`boundsHold`) and
    `State.idr:1981-1986` (`TS.bounds`, `TS.sizes`).
  - Delete `Proof/Requests.idr`'s `lteThrough`, `climb`, `fitsWithin` and
    `within` (`:733-763, 1010-`) once nothing asks them.
  - Delete the translation's own request computation.
  - C281 is for the owner's review, which does not block the work.
  - Evidence: N7.
- **L16-4 (N10; after L12-1).** Each array extern's registry row names
  its specification op or declared composition.
  - Delete `ArrayPrim` and `generatedOperands`
    (`Registry/Entry.idr:210-239`).
  - Delete the `arrayTerm` hand case (`Translate/Terms.idr:2383-2569`).
  - Update their readers (`Registry/Faster.idr:69, 97`,
    `Recognized.idr:73, 115`, `Frontend/Resolve.idr:468, 568`).
  - Evidence: N10.

**L17** (`compiler/checker`)
- **L17-1 (N6, checker half).** Keep a nested function's parent as a
  typed name, as `CaseBlock` and `WithBlock` keep theirs, written to the
  TTC.
  - Where: `Core/Name.idr:43`, today `Nested : (Int, Int) -> Name -> Name`.
  - Waits on L17bd, which is running in `compiler/checker`. Its
    uncommitted edits in the checkout are `Core/Unify.idr`,
    `TTImp/Elab/{Ambiguity,Case,Check}.idr` and `TTImp/Utils.idr`. The
    TTC encoding (`Core/Binary.idr`) was last committed in d093dbfb.
  - Evidence: N6.

**L12** (`spec/Arrays`)
- **L12-1 (N10).** Declare in `spec/Arrays/` the op, or the composition
  of declared ops, that each array extern of the registry names.
  - The externs: `reshape`, `merge`, `take`, `drop`, `concat`, `pad`,
    `transpose` (upstream's `linalg.transpose`, already admitted),
    `LArray`'s `read`, `write`, `thaw`, `shape`, `grow`, and
    `tabulateIO`.
  - Today `merge` and `reshape` give 0 there.
  - Waits on: the checkout has no uncommitted edit under `spec/Arrays/`.
    L12v, the last L12 lane dispatched, stopped at C280 (13b0e15e).
    Whether L12v still holds the directory is the coordinator's record.
  - Evidence: N10.

**L19** (`foreign/idr/lib/Transforms/Contracts`, `tests/`)
- **L19-1 (N9).** Delete `linear-kept`'s length guard
  (`Contracts/Contracts.cpp:150-151`) and the copy exemption it shares
  (`:119-121`).
  - A function whose parameter or result list changed is compared with
    what its record gives once the change is applied: the dropped
    positions removed, then the rest compared by position. For a result
    the one re-inference, `families::takenTypes` (C278), can supply it.
  - So dropping one parameter while weakening another is caught
    (L19 §3.2).
  - Evidence: N9. Recheck 5's "gone" is corrected.
- **L19-2 (N9).** Print the `Relation` enum and its name-and-breaker
  table (`Contracts.cpp:61-89`) from Idris records beside
  `harness/Properties.idr`'s, as `ExpectProperties.inc` is printed.
  - If the coordinator rules a four-row constexpr table the form, this
    item closes by that record instead.
- **L19-3 (R1).** Replace the five prose `expected-error` texts with
  `{{}}`, the form ten sibling tests use, or with a property prefix
  (C12).
  - The lines: `tests/owner-ended-after-field-read/owner-ended-after-field-read.mlir:81, 103`,
    `tests/partial-self-call-diverges/partial-self-call-diverges.mlir:40`,
    `tests/root-takes-and-gives-nothing/root-takes-and-gives-nothing.mlir:25, 34`.
  - Each test still asserts that the verifier refuses at that op.

**L01** (`spec/Effects`): not dispatchable now.
- §8 #5's patch, L01's I5, is owed by the first pass that adopts
  upstream's alias analysis. None does.

## Queue items found done

In `handoffs/L16-queue.md`:
- "From recheck 5's §6 report, waiting: N1 … and N2 …, after L10z":
  done by f46fe91d (L10x and L10w, C203 sharpened) and fc6fb0f8 (L14w).
- "N4, N5, N6's frontend half and N7, in L16ee's files": N4 is done by
  088c8197. N5 is half done there (`siblings`, Cases' `coversAll`).
- "From L16ek: the checker's TTC keeps a case tree's `scTy` unscoped
  (L17: keep it scoped)": done by d093dbfb (L17bc).
- "`Caps.idr:135, 165` name the deleted `closedHeight`": gone
  (`closedHeight` 0), in 088c8197.
- D126 round 2c:
  - "Hand readings of the tail kind outside Tail.h: `Accounts.cpp:66`,
    `Func/Call.cpp:273`, `EGraph/Build.cpp:64`": none left (*measured*:
    the remaining `getTailKind()` readers outside `Tail` are the program
    graph's row, the lowering and the frame questions).
  - "`Frames.cpp:154-164` and `Lifetimes/Pass.cpp`'s `framingOf` ask one
    question twice": `framingOf` 0. The program graph answers
    `runsOnFrame` (0642ef67).
- From spec round 4: "the frontend's `Term.Termination` keeps
  `Acyclic`": done by 29153f20 (L16em).
- Recheck 5's small rows (N3, `Breakable`, `Ids.idr`, upstream 58):
  done by 7878bda0. N8 is done by 1c8e1d7d (L17bb).
