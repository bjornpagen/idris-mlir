<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5: §6's deletions, the lanes' deletion lists, §8's suspected bugs, the library CMake lists

HEAD at start 17725fdd, at finish 5c726265. Commits that landed while
this was read:
- ae599560 and 5c726265 (queue; L19y's double-bits test), which touch
  no file cited here;
- 2bcbd726 and 59dcc964 (queue);
- 16ac96c4 and cb5cd6fb (D126 2b-T, 2c-T: `Tail.h`, `Tail.cpp`, `Inliner.cpp`, `ProgramGraph`, Frames, Lifetimes, `Lower/Functions`);
- 410113a7 and 04c2393d (L14x, D127: `Fold.h`, `Fold/*`, `EGraph/*`);
- 7aefe545 and b1f1cee7 (audits and proposals only);
- 269058fc (D126 2b-S: `LabelSites`, `ValueFacts`, `Statics`, `Convert`).

Every row citing those files was read again at b1f1cee7. Its lines
still hold, unless the row says otherwise.

Nothing was built, typechecked, generated or run.

How the tree was searched: `git grep --untracked -n -w <symbol>` over
the tree, leaving out `audits/`, `proposals/`, `sources/`,
`third_party/` and `.claude/`, unless a row names a narrower path. A
symbol counts as gone when that search finds no definition or use of it
in code, tests, CMake or the specification. Names that only appear in
history comments are listed in §4.

Paths are under `foreign/idr/` unless they start with another top-level
directory. `spec/` is `compiler/spec/IdrisMLIR/Spec/`. Owners come from
`ownership.json`.

Grounds:
- *read*: the cited line was opened.
- *measured*: a `git grep`/`ls`/`comm` count, with the command named.

## Counts

| part | rows | Done | Partial | Missing | Superseded | Regressed |
| --- | --- | --- | --- | --- | --- | --- |
| §6 and the lane lists | 106 | 95 | 10 | 0 | 1 | 0 |

A row is one top-level bullet of §2 that ends "Done", one N row of §1,
or the S row of §3.

| part | rows | Fixed | Still present | Refuted |
| --- | --- | --- | --- | --- |
| §8's suspected bugs | 33 | 31 | 1 (latent, unreached) | 1 (void, D48) |

The library CMake lists name 332 sources, and every one exists. Every
one of the 332 `.cpp` files under `lib/` is named. Recheck 2 counted 98
stale sources; there are now 0.

## 1. §6 and the lane lists: not Done

### N1. Tail position's climb (D30, C20; L10 §2.1) — **Partial**, in flight (2b-T: `Tail.h`, `Tail.cpp`; 2b-S: `LabelSites.cpp`)

- **Gone:** `TailPosition.cpp`, D30's second definition (*measured*: 0 hits).
- **Still there:** `IR/Tail.cpp`'s climb. This is the first definition, which D30 and C20 delete.
  - `lib/IR/Tail.cpp:108-119`: `inTailPosition` climbs `rejoinOf` up the regions.
  - `:122-127`: `decide(CallOp)` is that climb.
  - `:217`: the verifier's fallback reads it.
- **Who calls the climb:**
  - 17 files re-decide every call's kind through it. *Measured*: `git grep -l 'tail::decide(\|decideTails(' -- lib include` gives 17. Among them: `Inliner.cpp:74`, `Bufferize.cpp:354`, `Columns.cpp:82`, `Deduplicate.cpp:396`, `Narrow.cpp:190`, `Contify.cpp:235`, `Redirect.cpp:160`, `include/idr/Transforms/Optimize/Tails.h:21-24`.
  - Four readers ask it of ops that are not calls: `Analysis/LabelSites.cpp:213`, `Transforms/Defunctionalize/Edits.cpp:99`, `Tail/AccumulatorPlan.cpp:203`, `Tail/Continuations.cpp:229, 266`.
- Ground: read.
- Owner: L10, with L18 (`Optimize/Tails.h`, `Edits.cpp`) and L14 (`LabelSites.cpp`).
- **Remaining:**
  - C20 says the kind is written by the frontend and by each pass that makes a call, and checked by the region verifier's one walk (`tailEnds`/`verify`).
  - Delete `inTailPosition` and `decide`, and with them `Optimize/Tails.h`'s `decideTails`.
  - Have each pass in the 17 files write the kind it knows. The inliner composes the site's kind.
  - Give the four non-call readers a recorded fact in place of the climb.

### N2. The cycle rule, restated after the four deciders went (D30, §6 "the four cycle deciders"; L10, L14) — **Partial**

- **Gone:** the four deciders D30 names: `Borrows.cpp`, `Stack.cpp`, `Recursion.cpp`, `TailCallPlan.cpp`.
  - `Stack.cpp` and `TailCallPlan.cpp` no longer exist, and `Recursion.cpp` is gone with them (*measured*).
  - Borrows no longer tests cycles (*read*: `Analysis/Ownership/Borrows.cpp:20-26`).
  - Recheck 3's two restatements now ask the graph: `Analysis/Ranges.cpp:220` and `include/idr/Analysis/Solver/SummarizeImpl.h:42` (*read*).
- **Still there:** the rule "more than one member, or a self call" is written out in four places.
  - `include/idr/Analysis/Solver/ProgramGraph.h:139-141`: `onCycle`, whose comment says "the one place a component is decided cyclic".
  - `include/idr/Analysis/Solver/Components.h:76-82`: the partition's own `cycles` bit.
  - `lib/Transforms/Effects/Component.cpp:116`: `members.size() > 1 || !own.front().sites.empty()`.
  - `lib/Transforms/Optimize/Settle.cpp:186-191`: one member with no self call marked `Acyclic`.
- Ground: read.
- Owner: L14 (`Components.h`, `ProgramGraph.h`), L02 (`Effects/Component.cpp`), L18 (`Settle.cpp`).
- **Remaining:**
  - `ProgramGraph::onCycle` reads the partition's `cyclic(c)`.
  - The optimizer's components (`Effects/Component.cpp`, `Settle.cpp`) ask one query, the schedule's or the partition's, in place of their own test.

### N3. Effects: a reading outside the one API (§6 "every reading but the one API") — **Partial**

- **Done:** L02 §1.4's whole table is gone (§2, "Effects" below). Recheck 3's `ResetsUnshared` finding is closed.
- **Still there:** `lib/Transforms/Tail/Outline.cpp:134`: `assert(isPure(op) && ...)`. It reads upstream's effect and speculation interfaces directly. *Measured*: the only such reader outside `IR/Effects*`.
- Ground: read. Owner: L10.
- **Remaining:** ask the effect API (`effects::whole(op).onlyComputes()`, as `AccumulatorPlan.cpp:151` does) or drop the assert.

### N4. L16 §2.6, T1: `applyOver`'s `ValueType` refusal — **Partial**, in flight (L16ee, `Translate/*`)

- **Gone:** `Terms.valueType` (*measured*). The remaining `valueType` hits are `Emit/Index.idr:249` and a local at `Translate/Cases.idr:573`.
- **The TTC side is done:** the TTC keeps a `let`'s type (`compiler/checker/src/Core/TTC.idr:502-505, 640-643`).
- **Still there:** `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:1499-1503` refuses "a runtime position ... whose type is not known here".
- Ground: read. Owner: L16.
- **Remaining:** read the application's type from the kept `let` and `PLet` types at the boundary. Delete the refusal.

### N5. L16 §2.6, T2: `siblings`, `coversAll`, `instanceOf` — **Partial**, in flight (L16ee)

- **Still there:**
  - `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr:375-394`: `siblings`, constructors found through the first constructor's type.
  - `:399-404`: `coversAll`.
  - `:584-600`: `instanceOf`.
  - `compiler/src/IdrisMLIR/Frontend/Growth/Sites.idr:2439`: `siblings`.
- Recheck 3 reported the same rows.
- Ground: read. Owner: L16.
- **Remaining:** read each match's constructor set and instance from the TTC's `scTy` and the constructor table, once at the boundary. Delete the three functions.

### N6. L16 §2.6, T6: `rootOf`'s climb — **Partial**, in flight (L16ee)

- **Done:**
  - `keyOrigin` no longer searches (*read*: `compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr:80-111`).
  - A case or with block's parent is a `Name` (*read*: `compiler/checker/src/Core/Name.idr:49-50`).
  - `outermost` is now an unrelated function (`Translate/Types.idr:1057`).
- **Still there:** `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:620-645`. `rootOf` climbs `Nested (outer, _)` by context placement. A nested name's parent is still `(Int, Int)` (`compiler/checker/src/Core/Name.idr:43`).
- Ground: read. Owner: L16 (and L17 for the checker's name).
- **Remaining:** the checker keeps a nested block's parent as a typed name, as it already does for case and with blocks. `rootOf` reads that parent; delete the climb.

### N7. L16 §2.6 and §6: the growth check's run-time re-check — **Partial**, in flight (L16ee; D68, D128)

- **Gone:** `Proof/Bound.Term` (*measured*: no `Term` in `Proof/Bound.idr`).
- **Still there:**
  - `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-216`: `unsound` (an `internal` error), `heightWithin`, `sizedWithin`.
  - `Translate/Types.idr:601-606, 904-905`: `boundsHold`.
  - `Translate/State.idr:1516-1524`: `TS.bounds`, `TS.sizes`.
  - `Proof/Requests.idr:733-760, 1010`: `lteThrough`, `climb`, `fitsWithin`, `within`.
- Ground: read. Owner: L16.
- **Remaining:** D128 deletes the run-time re-check with C257's site walk. Delete each symbol above once the walk ties every request to its site.

### N8. L17 §2.8: `TTImp/PartialEval.idr`'s namespace — **Partial**

- **Gone:** the file and every other L17 §2.8 symbol (§2).
- **Still there:**
  - `compiler/checker/src/Core/Name/Namespace.idr:266-267`: `partialEvalNS`.
  - `compiler/checker/src/Core/Context.idr:68`: `visibleNS = [partialEvalNS]`.
  - Nothing defines a name in that namespace. Recheck 3 reported the same rows.
- Ground: read. Owner: L17.
- **Remaining:** delete `partialEvalNS`, the default that makes it visible, and `K_PE` if nothing else names it.

### N9. L19 §2.9: Contracts' hand `Relation` and `Breakable` — **Partial**

- **Gone:** the module clone and the length guard (*measured*: no `clone` call or `size()` guard).
- **Still there:**
  - `lib/Transforms/Contracts/Contracts.cpp:55-70`: the hand `Relation` enum and name table.
  - `:230, 248-266`: `Breakable` repeats `Relation`'s three cases for the test pass's option.
- Ground: read. Owner: L19.
- **Remaining:** delete `Breakable`, so the option is an `Option<Relation>`. L19 §2.9 then replaces the hand table with its per-function records.

### N10. L12 §2.7 and I12: the array externs' hand table and case — **Partial**

C6 was withdrawn and replaced on 2026-10-21 (L03 §1.9): the rows are no
longer generated; each names the specification's op instead. That
changes the form; the deletion stands.

- **Done:** `merge`'s identity entry is gone (`compiler/src/IdrisMLIR/Registry/Recognized.idr:115`).
- **Still there:**
  - `compiler/src/IdrisMLIR/Registry/Entry.idr:210-213`: a hand enum `ArrayPrim` (`AReshape` … `AMerge`, `ATabulateIO`).
  - `Translate/Terms.idr:2306-2320`: a hand case composing each one, e.g. `merge` from `Reshape` and `Extent`.
  - The specification declares no op or composition for them (*measured*: `merge` 0 hits in `spec/Arrays`).
- Ground: read. Owner: L16 (registry, translation), with L12.
- **Remaining:**
  - Each array extern's registry row names the specification op, or a composition the specification declares.
  - `ArrayPrim` and the hand case over it go (I12).

## 2. §6 and the lane lists: Done

### P0 §6, by area

**Effects**
- L02 §1.4's table: `bodyEffect`, `componentEffects`, `writeEffects`, `effectsCovered`, `appendEffect`, `effectInstances`, `solveEffects`, `observableRuns`, `LabelsRun`, `doesOf`, `usesWorld`, `onlyAllocates`, `performsIO`, `mayRunAt`, `anyEffect`, `Idr_Effect`, `Effect::none`, `bitEnumContains`, `setEffects(` all give 0 (*measured*). `IOResource` is named only at AGENTS.md:517.
- The remaining `Does`/`classify` is the one templated classifier (`include/idr/IR/Effects/Classify.h:48, 108`).
- `lib/Analysis/Effects.cpp` and `Transforms/Effects/Effects.cpp` are gone. `include/idr/Analysis/Effects.h` now holds the one derivation (`:1-30`).
- No test file has `effects<` (*measured*). Done.
- `Expect/ResetsUnshared.cpp:32-39` asks `effects::eachOwnEffect`. Done.

**Types and ops**
- The grade's free enums and functions (D88, D90): `QType`, `Lifetime::Heap`, `fitsIn`, `holdsOwn`, `mayBeFrame`, `!idr.lin`, `!idr.own`, `!idr.qtype`, `!idr.view<`, `view.make`, `idr.view`, `frame_lifetime`, `idr.share` all give 0 (*measured*).
  - The hold algebra is the generated table (`include/idr/IR/Generated/Grades.h.inc:180`, read by `lib/IR/Grades.cpp:210`).
  - The grade verifier checks carrier facts only (`lib/IR/Grades.cpp:108-122`). Done.
- The kind and role table: `namespace role`, `emptyRole`, `TableCtor`, `TableMember`, `DataDefinition`, `isBoxed` give 0. `kindOf` is the lifetimes' (`include/idr/IR/Lifetimes.h:184`). Done.
- `ValueFacts`' 55 hand answers: "no answer is written here" (`lib/IR/ValueFacts.cpp:3-9`); builtins answer as external models. Done; in flight (2b-S).
- Marker traits no reader needs: each of the 10 generated traits has a C++ reader (*measured*: `git grep -w` per trait outside `Generated/` and the trait headers, 2 to 12 hits). `ResultUsesMax`, recheck 3's gap, is now defined (`include/idr/IR/Traits.h:114`). Done.
- The hand `def`s of family members: every `.td` of ours is under `include/idr/IR/Generated/`, apart from tests' fixture files (*measured*: `git ls-files '*.td'`). Done.
- `own.adopt` and `own.give`'s def-use verifiers: `own.adopt` has none (`include/idr/IR/Generated/IdrOps.td:2689-2701`); `own.give`'s is local (`lib/IR/Counting/Ops.cpp:192-198`). Done.
- 38 hand folders: one runtime fold (`include/idr/IR/Fold.h:3-15`). The 21 `Op::fold` bodies left call no runtime function, and `ToIntOp::fold` is gone (*measured*). Done; in flight (L14x).
- `#idr.types`, `MutableType`, sealing, `DataRemap`, `Declarations`, `DataBody.cpp`, `Fit.cpp`, `!idr.box`, `Idr_SumKind`, `Idr_CtorRole`: 0 hits in code (*measured*). Done.
- The `tag` attributes (C19): no op has a `$tag` argument (*measured*: `grep ':\$tag'` gives 0). `getTag()` is derived from the refined type (`IdrOps.td:172-173`). `CtorRef` remains only as the match cases' syntax (`lib/IR/OpsMatchSyntax.cpp:51-76`). Done.
- Lifetime variables in types (D63): `LifetimeVar`, `lifetimeVars` give 0. A lifetime's kind is `spec/Lifetimes/Kind.idr:25`. Done.

**Analyses**
- `CallCycles`, `Recursion` (only the frontend's `Translate.Recursion` module and prose remain), the `SymbolUserMap` constructions, `Scc.h`, `Scc.cpp`, `stronglyConnected`, `MonotoneWorklist`, `FiniteLattice`, `ReadySet`, `ReturnedAnalysis`, `KnownLattice`: 0 (*measured*). Details in the L14 rows below. Done.

**Counting**, **control flow**, **arrays**, **lowering and runtime**: the lanes' rows below.

**Simplification**
- `applyPatternsGreedily`, `applyOpPatternsGreedily`, `GreedyRewriteConfig`, `createCanonicalizerPass`, `createCSEPass`, `getCanonicalizationPatterns` and `hasCanonicalizer` give 0, and `lib/Transforms/Canon/` is gone (*measured*). Done.

**Frontend representation bugs**
- A `Nat` literal is one constant (`compiler/src/IdrisMLIR/Emit/Operations.idr:262`).
- A case binds its scrutinee refined (`lib/IR/OpsMatchSyntax.cpp:51`), and `data.field` takes a refined value (`IdrOps.td`, `Idr_DataFieldOp`).
- `array.read` gives back `$after` (`IdrOps.td:943-956`).
- `WithBounds` is a sum (`compiler/checker/src/Libraries/Text/Bounded.idr:76-78`). Done.

**Process**
- The pipeline order is held once: `lib/Transforms/Pipeline.cpp:3-7` reads the specification's list.
- `remove-dead-values` and `createRemoveDeadValues` give 0.
- Patches 06, 28 and 63 have no `.patch` (*measured*: `ls upstream/{06,28,63}-*`).
- `bench/run.sh` raises no `ulimit -s`.
- No "1 MiB" text in `tests/`.
- `tests/defunc-tag-limit` is gone.
- D115: `tools/bootstrap.sh:926` sets `-DLLVM_ENABLE_ASSERTIONS=ON`. `CMakeLists.txt:36-45` strips `NDEBUG` and refuses an LLVM built without assertions, except in the typecheck build (D120). Done.

### L04 §2.18

- `Idr_DataType` as a `MutableType`, with `getCtors`, `getCtor`, `getTags`, `isClosures`, `isAtom`, `getListElement`, `walkLabels`, `replaceLabels`, `seal`, `solveHeld`, `roleTag`, `verifyBody`, `isDefined`: 0 in code (*measured*).
  - `isMemo` and `getHeld` are new functions, on family facts and on packages (`include/idr/Analysis/Ownership/Facts.h:170`, `lib/IR/Lifetimes/Ops.cpp:230`).
  - `Idr_DataType` is now a family application (`IdrTypes.td:12`). Done.
- `Idr_BoxType`, `Idr_SumType`, `Idr_DataTableAttr`, `Idr_BaseListOf`, and the bytecode's `BoxType`, `TableCtor`, `TableMember`, `DataTable`: 0. Done.
- `#idr.instance` on bodies: no such attribute (*measured*: `InstanceAttr` gives 0). A stale comment remains (§4). Done.
- `canonicalText`, `canonicalHash`: 0. Done.
- `idr.program`'s `types` property: its arguments are `sym_name`, `root`, `stage` (`IdrOps.td`, `Idr_ProgramOp`). Done.
- The alias by name and `data_types`: 0. Done.
- `TypeGraph`'s value walk, `boxed`, `inlined`: it reads members by family (`lib/Analysis/Solver/TypeGraph.cpp:3-19`). Done.
- On the Idris side, all done (`Translate/*` in flight):
  - `DataShape`, `IdrSum` and `Newtype` give 0.
  - The module has no table of data types (`compiler/src/IdrisMLIR/Emit/Index.idr:3-8`).
  - A match gets one crash default (`Translate/Cases.idr:286-288`).
  - Numerals are no longer mapped to `NatT`: `natCase` runs only on `NatT` (`Cases.idr:619-627`), and `Fin` and `Elem` are families (`TypeConstructors.idr:359-369`).

### L14 §1.4

- `CallCycles`, `Recursion`: 0 in `foreign/`. Done.
- The seven caller-only `SymbolUserMap` constructions: 0. `upstream/88-…/README.md:23` records it as history. Done.
- The twelve name-keyed maps: all gone, including recheck 3's `SpecializeState.h` `byName` and `Contracts.h` `bySymbol`.
  - The `StringAttr` keys left: the graph's own symbol resolution (`include/idr/Analysis/Solver/ProgramGraph.h:167, 217`), constant arrays (`lib/Conversion/Lower.cpp:255`), renames (`Lower/Functions.cpp:36`).
  - The four pointer-keyed maps are gone with their files (*measured*). Done.
- `Scc.cpp`'s graph copies: `include/idr/Support/` has no `Scc.h` (*measured*: `ls`). Done.
- Returned's whole-module solve:
  - `Tail/Returned.cpp` and `ReturnedArguments.cpp` are gone.
  - Dead results are one fixpoint over the program's results (`lib/Transforms/Optimize/Results.cpp:3-17`).
  - No `[[maybe_unused]]` anywhere (*measured*). Done.
- Each solver's private graph and numbering:
  - The stack inference is gone.
  - `Identities.h`'s `Outside` is now a concept over `FunctionId` (`:71-73`).
  - `Expect.h`'s `FunctionNumbering` is a concept over the graph's ids (`:200-215`).
  - Bufferize's aliases are numbered in one walk (`include/idr/Transforms/BufferizeModels.h:60-62`). Done.
  - The handle-to-id numbering maps that remain are listed under "Seen outside the range".
- L14 §2.10's conditional deletion, `Transforms/Effects/Constants.cpp:73-169`, waits on an upstream SCCP export that no carried patch provides (*measured*: no `upstream/*sccp*` but 02 and 17, both other bugs). It is outside §1.4 and not counted.

### L05 §2.10

- `Lifetime::Heap`, the hand enum, `fitsIn`/`joined`, `holdsOwn`, `mayBeFrame` and `QType::verify` went with D88/D90's grade (above). Done.
- `madeStatic`: 0. The one `isStatic` left reads the type (`lib/Transforms/Specialize/Consumer.cpp:201`). `Phantom`: 0. Done.
- `Owned*.cpp`: no file. One linearity verifier remains (`lib/IR/Verify/Linearity.cpp:3-12`). Done.
- `isCountedElement`: 0. Done.
- `idr-rc-stack`, `lib/Transforms/Stack/`, `loopsInFrame`: 0 (*measured*). Done.
- Borrows on `DataFlowSolver`: Borrows is a backward marking (`lib/Analysis/Ownership/Borrows.cpp:28-35`). `DataFlowSolver` is used only by Ranges, Constants and Narrow (*measured*). Done.
- `IDRIS_RT_STACK_CELL`: 0 (D78). A header is `count` and `info` (`runtime/idris_rt.h:76-79`). Done.
- The Idris side's `Lifetime`: `Syntax/Idr.idr` is gone. The kind comes from `spec/Lifetimes/Kind.idr:25`. Done.

### L07 §2.15

- `Reuses.cpp`, `Reuses`, `TakenField`: 0. Done.
- `Uses.cpp` and its symbols, `Positions.cpp`: 0. The `definedAt`, `heldIn` and `usedAfter` hits are other functions: the checker's, Growth's, `Borrows.cpp:103`. Done.
- `Analysis/Ownership/Values.cpp`: gone. Done.
- `Classes.cpp`, `ownsReference`, `endsInCrash`: 0. Done.
- `Placement`: the name is now the reverse walk's state (`include/idr/Transforms/Counting/Placement.h:1-11, 144`). `rebindDefaults`: 0. Done.
- Reshape's `takeReadSums`, `takeReadBoxes`, `rewriteSelects`, `sinkConsumers`: 0. The `takeApart` hits are Columns' and Entry's. Done.
- `Take.cpp`, `Transforms/Ownership/Grades.cpp`: gone. The reuse walk is `Transforms/Counting/Reuse.cpp`. Done.
- `LowerDrop`'s token branch: gone (`lib/Conversion/Lower/Counting.cpp:68-80`). The fusion by shape: no match. Done.
- `LowerTake`: the name stays for the take of a value its type claims unique, with no test (`Lower/Counting.cpp:84-103`). The branching one C39 deletes is gone, and so is recheck 3's `LowerTakeInto` branch (`:105-134`). Done.
- `Conversion/Cells.cpp`'s exclusive branch: gone (*measured*: `isUnique` in `lib/Conversion` only at `Elements.cpp:127` and `Lower/Counting.cpp:167`). Done.
- `Conversion/Fields.cpp`, `Fields.h`: 0. Done.
- Borrows' reading of `Reuses` and its cycle restriction: gone. `Demand.cpp`: gone (L08 row). `tests/rc-reuse-read-field`: gone. Done.
- `Elements.cpp:64-82`'s test: **Superseded**, see S1.

### L08 §2.7

- `Transforms/Demand/Demand.cpp`, `Demand.h`, `IdrDemand`, `createIdrDemand`: 0. `Optimize/Demand.cpp` is a different pass, for unread parameters (`:3-18`). Done.
- `unknownFrom`: 0. A dead end forwards nothing (`lib/Analysis/Ownership/ExclusivityGraph.cpp:11-14`). Done.
- `givesExclusive`: 0. The `copyable` hit is `std::copyable`. Done.
- The second solve and the hand pass manager: "solved once by context" (`lib/Transforms/Ownership/Exclusive.cpp:3-4`). No `PassManager` in the file (*measured*). Done.
- `HoldingState`, `Inference`, Borrows' `DataFlowSolver`, `Sharing::Unknown`: 0. Done.

### L09 §2.11

- Contification works over one dominator tree: no single-site rule, no `SymbolUserMap`, no `CallCycles`, no root found by name, and the body stays one block (`lib/Transforms/Optimize/Contify.cpp:3-30, 283-299`). Done.
- `Tail/Loop.cpp`, `WhileDo`: 0. There is one loop construction (`Tail/TailLoops.cpp:5-9`). Done.
- Case-of-case copies only the dispatch (`lib/Transforms/Joins/CaseOfCase.cpp:3-7`). Done.
- The three enclosing-match walks: `Eta.cpp` is gone, and "enclosing" gives 0 in `lib/`. Done.
- The poison yields: none in `Conversion/Matches.cpp`. `runningRegions`: 0. `!idr.cont`: 0 (the `idr.cont` hits are `idr.contents`). Done.
- The join lowering is L09 §2.8's phase 3, one conversion beside upstream's SCF patterns (`lib/Conversion/Matches.cpp:274-300, 374-381`). Done.

### L10's list

- `TailPosition.{cpp,h}`, `TailCallPlan.{cpp,h}`, `Conversion/Frame.{cpp,h}`: gone. Done.
- `numFrameBound` appears only at AGENTS.md:251. The `frameBound` left is counting's per-function bound (`include/idr/Transforms/Counting/Bound.h:54`). `leaked` names only the `CellsLeaked` ending. Done.
- `endsTail`, `inTailPositionModuloContext`, `forTails`, `reachesTailCall`, `passesOnPrevious`, `tailMatch`: 0. Done.
- The climb itself: **Partial**, see N1.
- Frames:
  - `memberCalled`, `closureLabels`, `madeInRest`, `caseCallee`, `FramesPlan`, `FramesMade`, `stackTypeOf`, `answerTypeOf`, `fromAnswer`, `asAnswer`: 0. The `restOf` hit is another function (`lib/IR/ConAttr.cpp:98`).
  - No `ub.unreachable` in `Transforms/Tail` (*measured*).
  - The `heldAs` re-entries are gone; `heldAs` remains only at `include/idr/IR/Grades.h:307` and `Conversion/Matches.cpp:87`.
  - Frames are a family whose fields keep their declared types (`Tail/FramesFamily.cpp:35-46`). Done.
- `stackSize`, `guardSize`, `alternateSize`, `Support/Stack.h`: 0 or absent. Done.
- The countdown recognizer and `Site`'s optional: 0. Done.

### L11 §2.10

- `heapRegion`, `ensure_init`, `initialising`, `is_initialised`, `liveCells`, `forgetCell`, `idris_rt_live_cells`, `tooLarge`, `checkStatus`, `IDRIS_RT_CRASHED`, `reportLiveCells`, `idris_rt_main_return`, `idris_rt_io_exit`, `idris_rt_crash_str`, `idris_rt_gmp_init`, `MAP_NORESERVE`, `RootKind::Status`, `countFoldLeak`, `IDRIS_RT_LIVE`, "stack exhausted", "no stack could be reserved": 0 each (*measured*). Done.
- `Io/Ending.cpp`: gone; the endings are in `runtime/End/End.cpp`. Initialisation is explicit (`runtime/Alloc/Cells.cpp:267`, `runtime/Start/Runner.cpp:115`). Done.
- `reserve` maps `PROT_NONE` (`runtime/Platform/Posix/Memory.cpp:27-32`). No `idris-mlir: ` prefix in `runtime/`. Done.
- `crashMessage` and `StaticData::message`: sites are `Idr_SiteAttr` on 9 ops (*measured*). Done.
- The harness's three ending protocols: `harness/lib/` holds only `harness.sh`. Done.
- Proposal 0017's text is amended (`proposals/0017-apple-dmp.md:5-12`). Done.
- `tests/runtime-start`'s "million" case: kept but rewritten. It now runs on the 64 MiB the program states (`tests/runtime-start/start.c:70-73`), which is D32's form, so the case no longer rests on the fixed reservation it was deleted for. Done.

### L12 §2.7

- `StructureLoops/Nests.cpp`: gone (a stale README mention, §4). `lowerOrdered`, `cloneRegion`, `emptyOf`, `structurable`: 0. The `valuesOf` and `formOf` hits are frontend functions. Done.
- `GeneratingOpInterface`, `Idr_Iteration`, `getIterations`, `getExtentBound`, `reifyTabulated`, `reifyDimOfResult`, `boundTabulated`: 0. Done.
- `TabulateIOOp`, our `TransposeOp`, `TransposeColumns`, `ElementUpdateOp`: 0. Transpose is upstream's `linalg.transpose`, admitted (`spec/Arrays/Declarations.idr:67`). `LowerUpdate` is not templated (`lib/Conversion/Arrays.cpp:200`). Done.
- `StoreModel`, `HeapReadModel`, `MemoRunModel`, `MatchModel`, `EnterModel`, `UseModel`, `isLink`, the C++ `heldType`, `#idr.world`: 0. Done.
- `sharers` reads classes computed once (`lib/Transforms/Bufferize/Releases.cpp:105-108, 156-159`). Done.
- `StructuredLoops.cpp`'s property reads the IR (`lib/Transforms/Expect/StructuredLoops.cpp:19-38`). Done.
- `merge`'s identity entry: gone. Done.
- The `I64` coordinates: array accesses take `Index` (`IdrOps.td:893, 906, 921`). Done.
- 0009 §8 and §20 item 2 are amended (`proposals/0009-typed-apl/README.md:537-560, 979-990`). Done.
- The hand compositions in `Terms.idr`: **Partial**, see N10.

### L16 §2.6

- `Forced.idr`, `erasedArgs`, `quantitiesOf`, `lastRuntime`: 0. Erasure has one source (`compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:472-475`). Done.
- `Profile.imports` reads the session's imports (`Frontend/Profile.idr:110-141`). `elaboratedFile`: 0. `Resolve.homeOf` maps the session's typed `foundIn` (`Frontend/Resolve.idr:74-96`). Done.
- `TS`: `fns`, `seen`, `symbols`, `instances`, `Registered`, `loops`, `inFlight`, `places` are gone, and `spelled` is typed `(ModuleIdent, Name)` (`Translate/State.idr:1480-1530`). `bounds` and `sizes` remain: **Partial**, see N7. Done otherwise.
- `mostUses`, `holdFor`, `quantityText`: 0. Done.
- Emit:
  - The world is no value of the module (`Emit/Monad.idr:125-135`).
  - `idr.refusals`: 0.
  - `functionOp` writes a termination proof per component (`Emit/Closures.idr:62-79`). Done.
- `Facts.terminating`: `Facts.idr` is gone. `Types.signed`: 0. The newtype collapse: 0. Done.
- `delayedLets` moves only lets around a `Delay` the elaborator inserted (`Translate/Closed.idr:335-347`). Done.
- The decimal doubles: a double crosses as its bits (`MLIR/Bytecode.idr:689-694`). `Syntax/Idr.idr`: gone. `DataShape` and the Index table: gone. Done.
- T1, T2, T6 and the growth re-check: see N4 to N7.

### L17 §2.8 (now `compiler/checker`, D117, D118)

- The D55 and D53 symbols (`ambigLimit` … `KwAutoImplicitDepth`): 0. Done.
- `abandonIfCycle` throws `CantSolveGoal`, not `InternalError` (`compiler/checker/src/Core/AutoSearch.idr:696-708`). Done.
- The timer, `foreignImpl` and its kin, `caseTreeHeuristics`, `nextIdxByScore`, `debugElabCheck`, `processTTImpFile`, `mkRunTime`, `compileRunTime`, `toCompileCase`, `canInlineCaseBlock`, `canInlineDef`, `refersToRuntimeM`: 0 in code. The checker's README records them as history. Done.
- `PMDef` has no run-time tree (`Core/Context/Context.idr:94-97`). `calcRefs` has no `Bool` (`TTImp/ProcessDef.idr:690-705`). No commented TTC writes (*measured*). Done.
- `Path.idr`'s Windows forms and its `System.Info` import: gone (`Libraries/Utils/Path.idr:5-22`). Done.
- `partialEvalNS`: **Partial**, see N8.

### L19 §2.9

- `harness/lib/{mlir,expect,differential,run,e2e,profile,lit,actions,determinism,heap,fuzz}.sh`: gone, only `harness.sh` remains. The harness is Idris and depends on `idris-mlir-spec` alone (`harness/harness.ipkg:7-9`). Done.
- `Prims.idr` names each builtin's specification op (`harness/Prims.idr:3-12`). The meanings and spellings stay the test's, as I8 says. Done.
- `Expect.h`'s declarations and `Lookup.cpp`'s table are made from `ExpectProperties.inc`, printed from `harness/Properties.idr` (`include/idr/Transforms/Expect.h:95-98`, `ExpectProperties.inc:3-5`). `tests/expect-coverage` has no `sed` over `Lookup.cpp`. Done.
- `Quantities.cpp`'s `keyOf`, silent drop and `spelled`: 0. Done.
- Contracts' clone and length guard: gone. `Relation` and `Breakable`: **Partial**, see N9.
- Pass names in RUN lines: tool options only (*measured*: `--idr-expect` 23, `--idr-pipeline` 7, `--idr-contracts` 5, `--idr-target` 4; no transform pass). Done.
- Brittle lines (*measured*), Done:
  - 42 `expected-error` lines, each a short property prefix.
  - No `facts:` remarks.
  - 25 `CHECK` lines, all in check tests' near-miss and witness fixtures.
- `bench/run.sh`'s `ulimit -s`, the "1 MiB" comments, `defunc-tag-limit`: gone. Done.

## 3. Superseded

- **S1. The element take's run-time test** (C39, L07 §2.15, L12; `Elements.cpp:64-82`) — **Superseded by C250 (corrected, 2026-10-22)**.
  - Whether a copy of the array shares an element's box is known only at run time.
  - So `takeOut` keeps one test, made only where the array's claim does not cover its storage (`lib/Conversion/Elements.cpp:109-135`).
  - Ground: read.

## 4. Comments naming deleted symbols

History, fine:
- AGENTS.md:251 (`numFrameBound`), :354 (`DataRemap`), :517 (`IOResource`).
- `upstream/27-one-shot-tensor-like-copy/README.md:78` (`DataRemap`).
- `upstream/88-symbol-table-walk-iterative/README.md:23` (`SymbolUserMap`).
- `compiler/checker/README.md:81-82, 93-94, 102-106` (`mkRunTime`, `compileRunTime`, `PartialEval`, `delayDepth`, `processTTImpFile`, `isWindows`, `Volume`, `dirSeparator`, `pathSeparator`, `pathLookup`).
- `bench/records/2026-10-13-*/about:4` (`ulimit -s`).

Stale, written as present fact:
- `compiler/src/IdrisMLIR/Ids.idr:102`: "Emit writes it as #idr.instance". No such attribute exists. Owner L16.
- `upstream/58-delinearize-empty-basis/README.md:45`: names `StructureLoops/Nests.cpp`'s `rank == 0` case, which is gone. Owner L06.

## 5. §8: the suspected bugs

| # | bug | verdict | evidence | ground |
| --- | --- | --- | --- | --- |
| 1 | acceptance rests on reuse, stack, inliner, borrows, dead code | Fixed | idr-in-place runs right after defunctionalization and knots (`include/idr/IR/Generated/Pipeline.h.inc:25-31`); the promise is decided on the program as written (`lib/Transforms/InPlace/InPlace.cpp:3-11`); `Demand`, `Stack`, `Reshape` are gone | read |
| 2 | exclusivity: a crash case counts as an unknown predecessor | Fixed | a block that never returns forwards nothing (`lib/Analysis/Ownership/ExclusivityGraph.cpp:11-14`) | read |
| 3 | a function's summary ignores its ops: the handle-table read, `exit`, memo state | Fixed | rows are derived from ops (`include/idr/Analysis/Effects.h:1-30`); `runtime_state`, `exit`, `memo_state` are resources (`include/idr/IR/Generated/EffectTree.h.inc:323-332`) | read |
| 4 | IO ops without `IOResource`; declarations that do not state their runtime function | Fixed | the specification declares each: `handle.string` reads runtime state and carries the `NotAString` guard (`spec/Ops/Platform.idr:497-505`); `array.new` allocates and writes counts (`spec/Arrays/Memory.idr:82-83`); `array.yield` consumes (`spec/Arrays/Generating.idr:305`); `own.adopt` gives a new identity (`spec/Counting/Declarations.idr:446`); `nat.from_big` writes a count and acquires nothing, as its runtime function does (`spec/Ops/Bigs.idr:365-383`) | read |
| 5 | an `Allocate` on an identity reads as fresh memory to `LocalAliasAnalysis` | Still present, latent and unreached | `FreshIdentity` is still `Allocate` on `Identity` (`spec/Effects/Declaration.idr:301`); no pass of ours runs an alias analysis (*measured*: `AliasAnalysis` 0 in `foreign/`); L01's I5 patch is owed by the first pass that adopts one. Owner: L01 | read |
| 6 | the designed lowering gives a row `memory(none)` and an IO row `willreturn` | Fixed | counts and memo state write `ArgMem`/`Other`; IO withholds `willreturn` (`spec/Effects/LLVM.idr:123-147`) | read |
| 7 | Euclid, the shifts and char conversions written several times; `ToIntOp::fold` | Fixed | one template (`include/idr/IR/Numeric/`), used by the runtime (`runtime/Big/Arithmetic.cpp:7-8, 19-22, 111-121`), the lowering (`lib/Conversion/Scalars.cpp:13`, `Checks.cpp:14-15`) and the folds (`lib/IR/OpsChecks.cpp:18-20`); `ToIntOp::fold` gone | read |
| 8 | `delay` lacks the capture rule; `dup` accepts a quantity-1 view | Fixed | `lazy.delay` carries `ResultUsesMax` (`IdrOps.td:2757-2758`); `count.dup` takes only counted values (`IdrOps.td:2501`, `lib/IR/Counting/Ops.cpp:35, 100-109`), so a scoped view cannot be duplicated; a once value is held to one use by `Verify/Linearity.cpp:3-8` | read |
| 9 | (void) `DataRemap`'s content keys | Refuted, void (D48) | `DataRemap` is gone (*measured*) | measured |
| 10 | the TTC drops a `let`'s type | Fixed | `Let`, `PLet`, `PVTy` keep their type (`compiler/checker/src/Core/TTC.idr:502-520, 640-653`) | read |
| 11 | erasure decided five ways; a block's parent as printed text | Fixed | one erasure source (`Translate/Closed.idr:472-475`); `CaseBlock (parent : Name) (ordinal : Nat)` (`compiler/checker/src/Core/Name.idr:49-50`); the nested parent's climb is N6 | read |
| 12 | Emit demotes a quantity-1 binder; `quantities-kept` drops colliding keys | Fixed | a binding holds "its binder's [quantity], never demoted" (`Emit/Monad.idr:137-146`); `keyOf` and the silent drop give 0 in `Expect/Quantities.cpp` | read |
| 13 | termination unsound under specialization; `delayedLets`; doubles as text | Fixed | a component's divergence comes from its proof (`lib/Transforms/Effects/Component.cpp:116-118`), and a call is deleted only if its row is speculatable (`include/idr/Analysis/Effects.h:62`); `delayedLets` only for the elaborator's `Delay` (`Translate/Closed.idr:335-347`); doubles cross as bits (`MLIR/Bytecode.idr:689-694`) | read |
| 14 | a lift depends on lock order | Fixed | a form's number is internal, and names read its digest (`include/idr/Transforms/SpecializeState.h:85-90`); keys are interned by content (`Specialize.h:205-225`) | read |
| 15 | inlining edits a function outside a pass | Fixed | leaf inlining is the inner pass `idr-inline-leaves` (`include/idr/IR/Generated/IdrInnerPasses.td:22`); `idr-inline` is a pass (`lib/Transforms/Inline/InlinePass.cpp:3-11`) | read |
| 16 | `absorb` clears `total`; a static memo cell; dedup before the knot check; seven refused tests | Fixed | `absorb` gives 0; a memo cell never folds (`lib/IR/OpsCon.cpp:115-123`) and suspensions have no fold; knots run before dedup (`Pipeline.h.inc:28-34`); the seven tests now expect `compile: exit 0` (*read*: `tests/{runtime-closure-implementation,dictionary-field-two-implementations,dictionary-field-opaque-type,static-argument-stuck-implementation,runtime-closure-index-function,runtime-closure-scope-constructor-field,runtime-closure-shape-constructor-field}/expected`, not run) | read |
| 17 | counting: borrows over allocations; crash paths without drops; extra tests | Fixed | the frame-limited borrow rule (`lib/Analysis/Ownership/Borrows.cpp:3-18`); crash paths free before their last allocation (`lib/Transforms/Counting/Placement.cpp:51-54`); the frame lifetime is gone; a token free makes 0 or 1 tests (`runtime/Rc/Counting.cpp:112-125`); recycle has no `isUnique`; an update takes out and puts back into the same box (`lib/Conversion/Arrays.cpp:200-240`) | read |
| 18 | Borrows' solve dropped behind `[[maybe_unused]]`; `own` recurses | Fixed | `[[maybe_unused]]` gives 0 (*measured*); Borrows is one marking (`Borrows.cpp:28-35`) | read |
| 19 | three walks rebuild a match's constructor; contification leaves two blocks | Fixed | the walks are gone (L09 row); contify makes one entry block (`Optimize/Contify.cpp:283-299`) | read |
| 20 | returned-arguments drops a tail callee's result, not its caller's | Fixed | the functions tail calls join lose a result together or not at all (`lib/Transforms/Optimize/Results.cpp:13-17`); `ReturnedArguments` gives 0 | read |
| 21 | a linear value loses its quantity at a frame's push | Fixed | a frame's fields are the held values' graded types (`Tail/FramesFamily.cpp:35-46`); a push checks the hold (`lib/IR/OpsCon.cpp:104-109`); no `heldAs` in Tail/ | read |
| 22 | every linear array read from a cell is a writable root | Fixed | writable only where the cell claims `unique self` (`lib/Transforms/Bufferize/Releases.cpp:59, 226-236`; D122) | read |
| 23 | `merge` as identity drops its extents | Fixed | `Registry/Recognized.idr:115`; `Translate/Terms.idr:2306-2320` uses the extents given | read |
| 24 | crash sites from `Location` merge under `MergeIdenticalRegions` | Fixed | the site is an attribute, `Idr_SiteAttr`, on `crash.cause`, `crash.message` and the guards (`IdrOps.td:1784, 1795`; 9 ops, *measured*), which `OperationEquivalence` compares (`lib/Transforms/Joins/IdenticalRegions.cpp:76, 92`) | read |
| 25 | no stack probes; the guard over the signal stack; "stack exhausted" status 1 | Fixed | each stack has its own guard (`runtime/Start/Runner.cpp:3-5`); program frames are sized and checked at build, and the runtime's code keeps its probes (`lib/Driver/LinkRuntime.cpp:81-89`, `CMakeLists.txt:431`); reaching the guard is the internal error `StackExhausted` (`spec/Runtime/Endings.idr:152-166`) | read |
| 26 | snmalloc's fatal errors abort unflushed; a refused commit ignored | Fixed | `Pal::error` ends through the runtime (`runtime/Alloc/Cells.cpp:46-53`); a refused commit is a refusal (`:17-18, 92, 108-128`); patches `upstream/94-…`, `95-…` | read |
| 27 | the `idris-mlir:` prefix; buffered output lost; four crashes without a site; `getString` | Fixed | no prefix; `end` writes pending output first (`runtime/End/End.cpp:237-244`); the four cases name `Main.idr:19:12` (`tests/buffer-range/cases/{3,9,below-zero,no-input}/expected-stderr`); `handle.string`'s guard (`spec/Ops/Platform.idr:505`) | read |
| 28 | pool workers get the OS's default stacks | Fixed | the runner's sizes are kept for a tool's other threads, and each worker has its guard (`runtime/Start/Runner.cpp:40-47, 59-75`) | read |
| 29 | the pipeline order held twice; dead `remove-dead-values` | Fixed | §2 "Process" | read |
| 30 | `maxNumRewrites` unset; the greedy driver where our ops are | Fixed | no greedy driver (*measured*, §2 "Simplification") | measured |
| 31 | `OsOp::fold` reads the build machine's triple; the fork's Windows path grammar | Fixed | the fold reads the module's target or folds nothing (`lib/IR/OpsPlatform.cpp:34-44`); `Libraries/Utils/Path.idr:5-22` | read |
| 32 | patch 27 cites a test that does not exist | Fixed | `tests/upstream-one-shot-tensor-like-copy` exists (*measured*: `ls -d`) | measured |
| 33 | (fixed on main) `Positions` | Fixed | 0be4e660; `Positions.cpp` gone | measured |

## 6. The library CMake lists

Command, at b1f1cee7 and again at each HEAD in between:
- extract every `*.cpp` named in `foreign/idr/lib/CMakeLists.txt` and `lib/{Analysis,IR,Support,Target,Transforms}/CMakeLists.txt`, with comment lines removed;
- prefix each with its list's directory;
- `comm` the result against `git ls-tree -r --name-only HEAD foreign/idr/lib | grep '\.cpp$'`.

Results:
- 332 sources named, 332 files present, 0 named and missing, 0 present and unnamed. *Measured.*
- `EGraph/Values.cpp` was untracked at start (L14x). It was listed by `lib/Transforms/CMakeLists.txt:24` and committed in 410113a7.
- No `lib/Conversion/` or `lib/Driver/` list exists; `lib/CMakeLists.txt` names their sources.

## Seen outside the range

- Handle-to-id numbering maps outside `IdrIR` (§5.2, C236):
  - `include/idr/Analysis/Solver/Extraction.h:145`, `Solver/LabelPoints.h:94`, `lib/Transforms/Bufferize/Releases.cpp:117`, `lib/Transforms/Narrow/Widths.cpp:104`.
  - `lib/Transforms/EGraph/Simplify.cpp:147` maps `Operation *` to `Root`, which holds per-node state, not an id.
- `compiler/src/IdrisMLIR/Frontend/Finite.idr:172`: an `internal` error ("the growth check is unsound"), which D112 asks to be a type or a proof. It goes with N7.
- `include/idr/Driver/Verdict.h:78`: statistics as a `std::map<std::string, uint64_t>`, keyed by name text.
