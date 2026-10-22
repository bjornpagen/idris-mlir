<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane `canon`: canonicalization and the rewrite layer

Scope: `foreign/idr/lib/IR/Canon/`, `lib/IR/Fold/`,
`include/idr/IR/Canon.h`, `Fold.h`, `lib/Transforms/Identity/`, and
the inventory of every `RewritePattern`, `OpRewritePattern`,
`OpInterfaceRewritePattern`, `populate*Patterns`,
`applyPatternsGreedily`, `GreedyRewriteConfig`, `walkAndApplyPatterns`
and fold hook across `foreign/idr`.

Status: written 2026-10-21 (wave 2). Nothing built or run; every count is over the source, with its command in §9.

## 1. Reading notes

What in the proposal bears on canonicalization, folding and the rewrite
layer, by section and finding ID (*read* in
`proposals/0000-mlir-native.md` unless marked).

**§2, §3 (the brief and the walls).**
- §2 names `IR/Canon/Sink.cpp:114` as an `isa<>` ladder restating trait
  classes (recalled by another agent; checked in §3 below).
- §2's pipeline: "canonicalize and CSE" sits after `columns`, before
  `structure loops`. Canon is also run inside other passes (inventory,
  §2 of this document).
- §3 row `3a96c407, 7987388b`: `idr-optimize` made 75 million pattern
  attempts, "patterns matching any op". That is this lane's wall.
- §3: upstream patch 62 (greedy driver's multi-region ancestors) is
  carried; it bears on every greedy run over a match of many cases.

**§5.1 mlir-analysis.**
- D2 table: the greedy driver's DCE reads `isOpTriviallyDead`
  (`GreedyPatternRewriteDriver.cpp:486`); `runRegionDCE` from
  canonicalize's `simplifyRegions` reads `wouldOpBeTriviallyDead`
  (`RegionUtils.cpp:371-392, 513-621`).
- D3: a `RecursiveMemoryEffects` op's effects are a body walk per query;
  "on a match of 30,000 cases every greedy visit of it walks 30,000
  regions to decide whether it is dead". Directly a cost of every greedy
  run over our matches.
- C2: `getSuccessorOperandInputMapping()` without a source is built per
  application by the region-branch canonicalization patterns; that is
  patch 62's cause. Any of our patterns that query region-branch edges
  per region is the same shape.
- 5.1.2 item 4: `remove-dead-values` comes back split (per function
  upstream; a signature solve of ours). Its final step runs region-branch
  canonicalization patterns greedily (B3, `RemoveDeadValues.cpp:836-865`).
- U3 lists 62 among "the quadratic helpers" to carry.
- G2: the action framework and `-mlir-debug-counter` give bisection of
  pattern applications for free.

**§5.2 mlir-ods (read most carefully).**
- E1: pattern roots decide cost. An op-name root files the pattern under
  that name; an `OpInterfaceRewritePattern`/`OpTraitRewritePattern` is
  copied under every registered op that has it at freeze
  (`FrozenRewritePatternSet.cpp:104-142`); only `MatchAnyOpTypeTag` goes
  to the any-op list merged with every op's own list on every visit
  (`PatternApplicator.cpp:146-190`). The 75 million attempts were
  ops x any-op patterns x iterations.
- E2: the greedy driver: re-walks and re-adds every op per iteration
  (`:868-883`), erases unreachable blocks, per op: trivially-dead erase,
  `op->fold`, then patterns (`:486-625`); then region simplification
  (dead args, block merging at `Aggressive`, `:903-909`). Defaults:
  bottom-up, `maxIterations = 10`, folding and constant CSE on,
  `Aggressive`, strictness `AnyOp` (`GreedyPatternRewriteDriver.h:165-176`).
  Non-convergence returns `failure()`, which a caller must not turn into
  a rejection (AGENTS.md). A change re-queues the op and every ancestor
  (patch 62's quadratic case). New: `enableCSEBetweenIterations`.
- E3: `walkAndApplyPatterns`: one post-order walk, highest-benefit
  pattern per op, no fixpoint, no folding, no DCE, no revisit, skips
  unreachable blocks, may erase only the matched op and descendants.
  Terminates by construction (AGENTS.md's shape for an optimization).
- E4: DRR generates native op-rooted `RewritePattern`s
  (`RewriterGen.cpp:1127-1129`); upstream uses it in arith (53), FIR (8),
  SPIR-V (6), shape (6), shape-to-std (2). PDLL has no production user;
  its C++ output is a string parsed at set build and interpreted on PDL
  bytecode.
- E5: canonicalization declared three ways: `hasFolder` (called before
  patterns; `ConstantLike` results through `hasConstantMaterializer`),
  `hasCanonicalizeMethod` (a static method wrapped into an op-rooted
  pattern), `hasCanonicalizer` (`getCanonicalizationPatterns`). All
  rooted.
- B5: `Commutative`, `Idempotent`, `Involution` have `foldTrait`s run
  after the op's own `fold` (`OpDefinition.h:1165-1171, 1944-2012`).
- Recipe rows 17 (folders, `foldTrait` traits) and 18 (rooted patterns,
  DRR) are this lane's. Design 2 "Rooted rewriting": no
  `MatchAnyOpTypeTag`; one-shot rewrites on the walk driver; greedy only
  for canonicalization, non-convergence never an error, region
  simplification chosen per use. Design 5: DRR for peepholes, no PDLL.
- M6: "the 75 million attempts were a root choice"; inside a function a
  one-shot rewrite is the walk driver's contract.
- M13: DRR yes, PDLL no.
- Q4 (owner, ods-Q4): "DRR allowed, PDLL refused (E4, M13)?" Evidence
  owed in §6.
- Q1: Divergence and crash kept or deletable when dead: bears on
  canonicalize's DCE (which ops `isOpTriviallyDead` may erase).
- W2: every `MatchAnyOpTypeTag` pattern with the set of ops it matches.
  Answered in §3.
- W4: `isa<>` over ops restating traits (Sink.cpp's ladder).
- W9: passes that change nothing mark all analyses preserved.

**§5.3 llvm.**
- B2/I2: a per-pass table over ops is a `TypeSwitch` with
  `DefaultUnreachable`; a classification more than one pass reads is a
  trait or interface.
- B5/I5: a hot callback is a template, a cold one a `function_ref`.
- M12: walks that re-find the same ops; an Attributor-style "walk once"
  index. Bears on canon's helpers that walk the function per call.
- S0: a fact that is a def-use chain belongs in the IR.

**§5.4 modular.**
- F9: Mojo's canonicalizer is upstream's greedy driver over every loaded
  dialect's and registered op's patterns plus seven of its own, frozen
  once in `initialize`, region simplification disabled
  (`Canonicalizer.cpp:470-525`). Direct model for ours.
- F5: Mojo's SCCP reuses upstream folding (`op->fold`, `OperationFolder`)
  without the solver.
- F22: Mojo "shrinks generators" before instantiating.

**§5.5 cxx26.**
- Finding 18: interface- and trait-rooted patterns are indexed per op at
  freeze; a hand list of per-op patterns buys no better indexing than
  `OpInterfaceRewritePattern`/`OpTraitRewritePattern`.
- D1: dispatch once where the set is open (an interface, a trait, a
  rooted pattern), then typed code; a concept may read ODS but never list
  ops. Bears on any `isa<A,B,C>` filter inside a pattern.
- D2: closed sums of our own types through one exhaustive `match`.

**§5.6 ecosystem.**
- A1: CIRCT's IMConstProp uses the op's own `fold` as transfer
  (`IMConstProp.cpp:915`): folders are the one meaning a solver can reuse.
- D2: IREE's `FixedPointIteratorPass` reruns canonicalize/CSE/IPO until
  no pass sets a discardable attribute, up to 10, then fails: a round
  count that refuses and a "changed" fact in an attribute; Rejected. Our
  greedy calls that return `failure()` on non-convergence must not do
  the same (checked in §3).
- D3: IREE reruns its solver after each greedy rewrite round, with a
  `RewriterBase::Listener` that erases states of erased ops.
- E3: Flang's `AliasAnalysisRecursiveEffectsCache` memoizes per-op
  summaries of `HasRecursiveMemoryEffects` ops because effect queries
  re-walk regions: the cost every greedy DCE query on our matches pays.
- W-E5: every budget, round count and cap; W-E6: every query on a match
  that walks its regions. Canon contributes entries (§4).

**§5.7 library.**
- M11: rooted patterns are relational matching's index on the operator;
  an any-op pattern is a full scan (3a96c407). E-class analyses (E2) are
  the model for analyses kept current across rewrites by a listener.
- L6: every pattern rooted on an op name or interface; analyses that
  survive a rewrite updated through `RewriterBase::Listener` deltas.
- QL5: equality saturation out of P0 (no wall is phase-ordering).
- B4 (Bhat and Grosser): dead-region elimination is plain DCE for a
  case's regions; region value numbering by a rolling hash.
- H2 (positive supercompilation): a match propagates what it learned
  into each branch (the scrutinee replaced by the pattern): the
  known-constructor fold inside a case.

**§5.8 dialect-design.**
- DS4 rows that change canon's folds and patterns: `check.nonzero` and
  kin become `arith.cmpi` + one `idr.check` ("five ops; their folders
  (arith folds the condition)"); `divs`/`divu`/... become `arith` where
  the runtime agrees (their folds become arith's); `shls`/`shlu` one op;
  `put_*` become `str.show_*` + `io.write` (O5: "the pure half then
  folds and CSEs with upstream's drivers"); `match_lit` on words
  becomes `scf.index_switch` or `cf.switch` (upstream folds then).
- O5: compose before fusing so pure halves fold with upstream drivers.
- E5 (CIRCT): canonicalization moves between `firrtl.reg` and
  `regreset`, DRR (`FIRRTLCanonicalization.td:669-672`): DRR in
  production outside upstream.
- E2 (CIRCT): a type canonicalization was removed because it lost
  information: normalize only where no op's legality depends on it.
- C1/EF1 and DD-Q2: divergence deletable when dead or not decides what
  canonicalize's DCE may erase.

**§5.9 mlton (read most carefully).**
- E2: the shrinker (Appel and Jim) is per function, two linear sweeps:
  a DFS computing per block in-degree, an `isHeader` bit, occurrence
  counts per variable, and a label meaning (`Block | Bug | Case | Goto
  {dst, args} | Raise | Return`) with goto chains collapsed; then a
  rewrite from the start: inline a block of in-degree one at its only
  jump; a case on a known constructor or constant jumps to the arm and
  decrements the other arms' in-degrees, deleting blocks that reach zero
  recursively; statements rebuilt backwards so `isUsed` is known when a
  binding is kept or dropped. Forward propagation and backward DCE in
  one pass; block-indexed arrays and one `VarInfo` per variable as the
  only state.
- E3: the shrinker is the normal form between passes, not a pass in
  the list: 19 SSA passes call `shrinkFunction` on each function they
  rewrote. "There is no pattern driver anywhere in the SSA optimizer":
  each rewrite is a case over closed sums; `restoreFunction` repairs SSA
  only for the violators.
- D4: closure conversion relies on the shrinker as its normal form
  (`Accum.done` internal error if the shrinker did not finish).
- G2.8: one linear normalizer, called by every pass, instead of a
  rewrite driver. G2.9: immutable functions with a lazy cached CFG.
- H row 3a96c407/7987388b: "no pattern driver; one linear shrinker
  dispatching on closed sums" makes the 75 million attempts
  inexpressible.
- M7: "Upstream MLIR has the pieces: per-op `fold`,
  `walkAndApplyPatterns` ..., and `simplifyRegions`."
- Design 5 (this lane's target): "One linear normalizer, run by each
  pass over what it changed": folders (`hasFolder`), a known-constructor
  fold of the `case` terminator (`simplifyCase`), in one
  `walkAndApplyPatterns` walk with patterns rooted at named ops only,
  then `simplifyRegions`. Each pass calls it on the functions it
  rewrote. Costs: a walk does not revisit what it changed; greedy stays
  for passes that need a fixpoint, measured. Deletes any-op patterns in
  `idr-optimize` and module-wide canonicalize runs whose job is cleanup.
- Design 2: a first-order CFG core with `case` as a terminator; the
  shrinker's `simplifyCase` would then be a fold of that terminator.
- Q-W9 (wave 2, this lane): "Which `idr-optimize` patterns are rooted
  at any op, and which of them are folds of one op, known-constructor
  folds of a match, or block simplifications that upstream's `fold` and
  `simplifyRegions` already do (Design 5)?" Answered in §3.
- Q-O1: structured `match` kept past defunctionalization or not.

**§5.10 rc.**
- R1.4: `is_unique %x` as an op "whose folder returns true when `%x` is
  exclusive by type"; "upstream canonicalization folds the test and
  deletes the shared arm ... No pass special-cases the static case: the
  type decides and the folder applies it." A future fold of this lane.
- A3: Koka's drop specialization and dup/drop fusion run per branch head
  inside one walk (Parc), not as patterns: a model of a cheap
  normalizer.

**§5.11 oom.**
- C4: GHC's simplifier budget is in the program's units but rejects the
  program; C7/A4: every compiler budget counted in program units (ops,
  rewrites), never bytes or seconds, so `stage 2 = stage 3` holds. Bears
  directly on `maxNumRewrites` (unset today, §3) and
  `kSinkDuplicationLimit`.

**§8 owner questions this lane gives evidence for (§6 of this
document):** ods-Q4 (assigned); also ods-Q1/DD-Q2 (dead crash or
divergence), Q-O1 (structured match), QL5 (equality saturation),
Q-llvm-2/Q-E3/oom-2 (budgets), ods-Q6/Q-M2/Q-O5 (verification after
each canonicalize), DD-Q4 (signedness in folds), DD-Q5 (one op, several
runtime functions), Q-O3 (facts into types: non-emptiness).

**proposals/0003-facts-once.md, items in this lane's files.**
- Control lane: a pattern variable's location replaced by the match's
  (`canon::readField`, `Canon/Force.cpp` `capturesOf`, `Canon/Merge.cpp`
  default argument); `Canon/Output.cpp` `writePieces`/`firstChar` take
  the replaced op's location.
- "What an enclosing match says about a value, three ways"
  (`OpsMatch.cpp` `takenFromEnclosing`, `Canon/Eta.cpp` `knownFromMatch`,
  `OpsConReads.cpp` `FieldOp::canonicalize`); `TagOp::fold` never asks.
  Owed: one `knownConstructor(Value, at)` in `Canon.h`.
- `Fold/Bigs.cpp` `BigToIntOp::fold`: an upward walk without
  `definitionChain`'s cycle guard.
- `knownNonEmpty` re-walks the append tree per question (`Crashes.cpp`):
  "Put non-emptiness in the type".
- `feeds()` is a ladder of op kinds (`lib/IR/Canon/Feeds.cpp`). Owed: an
  interface on the consumer (`meets(OpOperand &, Value)`, the fold probe
  its default).
- `MoveOut` classifies effects a second way (`lib/IR/Canon/MoveOut.cpp`:
  its own `Does`, `doesOf`, `isa<ForceOp>` beside `idr::classify`), the
  two disagreeing on `ub.unreachable`.
- `Fold/Values.cpp` walks a list of roles (`DataType::Body` lacks one
  alternative per kind).

## 2. What the subsystem is

All counts *measured* at e96bb991 plus the working tree (no file of this
lane is modified in it); paths below are under `foreign/idr/` unless
they say otherwise.

### 2.1 Files and sizes

`wc -l lib/IR/Canon/* lib/IR/Fold/* include/idr/IR/Canon.h include/idr/IR/Fold.h lib/Transforms/Identity/*`:
2,830 lines.

| file | lines | holds |
| --- | ---: | --- |
| `include/idr/IR/Canon.h` | 97 | the canon API: `retryBetween`, nine `add*Patterns`, `readField`, `readsPlainValue`, `eta`, `buildable`, `feeds`, `meetsInSomeRegion`, `addMerge`, `addCaseOfCase`, `addSink` |
| `include/idr/IR/Fold.h` | 146 | `fold::runtime<Op>` (the ABI table's function), `fold::Scope` (runtime references one fold holds), `strUnary`, `strBinary`, `bigUnary`, `bigBinary<Op>`, `wrapped`, `compared`, `listElements`, `stringOfList` |
| `lib/IR/Canon/Callees.cpp` | 25 | `retryBetween` only (the file's name is left from the deleted `CalleePattern`, *read*: `git show d06ed15c:foreign/idr/lib/IR/Canon/Callees.cpp`) |
| `lib/IR/Canon/Captures.cpp` | 27 | `buildable`: the leaf rule of a constant's parts |
| `lib/IR/Canon/CaseOfCase.cpp` | 187 | `SinkConsumer`, case-of-case, rooted on `MatchOpInterface` |
| `lib/IR/Canon/Eta.cpp` | 75 | record eta, read by `ConOp::fold` |
| `lib/IR/Canon/Feeds.cpp` | 198 | `feeds`, `meetsInSomeRegion`, the fold probe `foldsWith` |
| `lib/IR/Canon/Force.cpp` | 146 | `ForceByName` (on `memo.run`), `StaticCase` (on `match`) |
| `lib/IR/Canon/MatchPatterns.cpp` | 265 | `DropEmptyStringCase`, `EndAfterNoYield`, `YieldFields`, `readField`, `readsPlainValue`, the two hooks' bodies |
| `lib/IR/Canon/Merge.cpp` | 119 | `MergeIdenticalRegions` |
| `lib/IR/Canon/MoveOut.cpp` | 250 | `MoveOut<ArraySetOp>`, `MoveOut<ArrayGetOp>` (read-then-write to `array.update`) |
| `lib/IR/Canon/Output.cpp` | 185 | `PutStrOfBuilder`, `HeadOfBuilder`, the eight `StrBuilderOpInterface` implementations, `PutStrOp::fold` |
| `lib/IR/Canon/PutList.cpp` | 72 | `PutListOfConstant`, `PutListOfCons` |
| `lib/IR/Canon/Rebuild.cpp` | 59 | `MatchOp::rebuild`, `MatchLitOp::rebuild` |
| `lib/IR/Canon/Sink.cpp` | 246 | `SinkIntoRegions`, `kSinkDuplicationLimit`, `nearestSinkable` |
| `lib/IR/Fold/Bigs.cpp` | 219 | 23 big-op folders |
| `lib/IR/Fold/Scope.cpp` | 68 | `fold::Scope` |
| `lib/IR/Fold/Strings.cpp` | 270 | 24 string, `double_head` and `int_head` folders, `stringOfList` |
| `lib/IR/Fold/Values.cpp` | 81 | `wrapped`, `compared`, `listElements` |
| `lib/Transforms/Identity/Identity.cpp` | 95 | `idr-identity` (`GiveBack` on the walk driver), a step of idr-optimize's inner pipeline |

### 2.2 The rewrite layer's inventory (whole tree)

*Measured*: `grep -rn -E "(struct|class) [A-Za-z0-9_]+.*: *(public )?(mlir::)?(OpRewritePattern|OpInterfaceRewritePattern|OpTraitRewritePattern|RewritePattern|OpConversionPattern|ConversionPattern|OpInterfaceConversionPattern)\b" lib include tools unittests`,
`grep -rc matchAndRewrite`, and the driver grep of §9.

**Canonicalization hooks in ODS**: 48 `hasFolder = 1` lines (several in
classes, so 77 ops fold), 9 `hasCanonicalizer = 1` (one is the dialect's,
`IdrBase.td:58`), 1 `hasCanonicalizeMethod` (`FieldOp`, `IdrOps.td:341`).
No `Commutative`, `Idempotent` or `Involution` trait on any op (`grep -rn
"Commutative\|Idempotent\|Involution" include lib`: none). No DRR (`Pat<`
in no `.td`), no `.pdll` file.

**Fold bodies in C++**: 47 in `lib/IR/Fold/` (24 + 23), 22 elsewhere
(`OpsScalars.cpp` 5, `OpsChecks.cpp` 5, `OpsClosures.cpp` 3,
`OpsConReads.cpp` 2, `OpsArrays.cpp` 2, `OpsCon.cpp` 1, `Constants.cpp` 1,
`OpsPlatform.cpp` 1, `OpsGenerating.cpp` 1, `Canon/Output.cpp` 1), and 2
bodies declared in ODS by `extraClassDefinition` on a class
(`IdrScalarOps.td:35-39, 71-75`: the four division and four shift ops).

**Canonicalization patterns, ours**, by root (all rooted; no
`MatchAnyOpTypeTag` anywhere, `grep -rn MatchAnyOpTypeTag`: none):

| pattern | root | where added | root op present at a pipeline canonicalization? (*read*: `Pipeline.cpp`, the conversion targets) |
| --- | --- | --- | --- |
| `SinkConsumer` (case-of-case) | `MatchOpInterface` | `CaseOfCase.cpp:43`, via `MatchOp`'s hook | yes |
| `SinkIntoRegions` | `MatchOpInterface` | `Sink.cpp:205`, via `MatchOp`'s hook | yes |
| `MergeIdenticalRegions` | op name string, added for `idr.match` and `idr.match_lit` | `Merge.cpp:78`, `MatchPatterns.cpp:199-202` | yes |
| `EndAfterNoYield` | op name string, twice | `MatchPatterns.cpp:68` | yes |
| `YieldFields` | op name string, twice | `MatchPatterns.cpp:109` | yes, before the grades only |
| `DropEmptyStringCase` | `MatchLitOp` | `MatchPatterns.cpp:29` | yes |
| `StaticCase` | `MatchOp` | `Force.cpp:101` | yes (root function only) |
| `ForceByName` | `MemoRunOp` | `Force.cpp:66` | yes |
| `MoveOut<ArraySetOp>`, `MoveOut<ArrayGetOp>` | each op's name | `MoveOut.cpp:147, 247` | yes |
| `PutStrOfBuilder` | `PutStrOp` | `Output.cpp:34` | yes |
| `HeadOfBuilder` | `StrHeadOp` | `Output.cpp:50` | yes |
| `PutListOfConstant`, `PutListOfCons` | `PutListOp` | `PutList.cpp:24, 44` | yes |
| `ForceOfOneUse` | `ForceOp` | `OpsClosures.cpp:40` | **no**: `ForceOp` is illegal after defunctionalization (`Defunctionalize/Pass.cpp:64-65`) and no canonicalizer runs before it (`Pipeline.cpp:93, 116, 167, 181`; `Optimize.cpp:64`) |
| `ForceInOneCase` | `SuspendOp` | `OpsClosures.cpp:61` | **no**, same reason |
| `WorldUnused` | `TabulateIOOp` | `OpsTabulate.cpp:247` | yes |
| `FieldOp::canonicalize` | `FieldOp` | `OpsConReads.cpp:101` | yes |
| `GiveBack` (idr-identity, walk driver) | `CallOp` | `Identity.cpp:43` | yes |

**Canonicalization patterns, upstream's, on our ops**:
`populateRegionBranchOpInterfaceCanonicalizationPatterns` (three
patterns: `MakeRegionBranchOpSuccessorInputsDead`,
`RemoveDuplicateSuccessorInputUses`,
`RemoveDeadRegionBranchOpSuccessorInputs`, pinned
`mlir/lib/Interfaces/ControlFlowInterfaces.cpp:1314-1320`) and
`populateRegionBranchOpInterfaceInliningPattern` (`InlineRegionBranchOp`,
`:1322-1328`) on both match ops (`OpsMatch.cpp:187-192, 242-248`), the
inliner with `canon::readField` and `canon::readsPlainValue` as its two
`std::function` callbacks; and `memref`'s
`populateResolveRankedShapedTypeResultDimsPatterns` as the dialect's
canonicalizer (`Dialect.cpp:42-44`).

So each visit of an `idr.match` tries ten patterns (four upstream, six
ours) and of an `idr.match_lit` ten (four upstream, six ours with
`DropEmptyStringCase` for `StaticCase`); every one of the six of ours
re-reads the match's regions (§4).

**Other passes' patterns** (the rewrite layer's inventory; each is its
lane's to redesign):

| file:line | patterns | driver | lane |
| --- | --- | --- | --- |
| `Transforms/Narrow/Carried.cpp:122` | `NarrowJoint`, `OpInterfaceRewritePattern<RegionBranchOpInterface>` | walk (`Narrow.cpp:90`) | 11 |
| `Transforms/Narrow/Ops.cpp:193` | `NarrowWord`, one per op of a generated list plus four by hand (`Ops.cpp:226`, `addNarrowWords<MatchLitOp, CheckNonzeroOp, DupOp, DropOp, GET_BIG_TO_WORD_LIST>`) | walk (`Narrow.cpp:95`) | 11 |
| `Transforms/Narrow/Versions.cpp:175` | `VersionDescending` on `scf.while` | walk (`Narrow.cpp:152`) | 11 |
| `Transforms/Narrow/Narrow.cpp:126-128` | none: an empty `FrozenRewritePatternSet` | `applyOpPatternsGreedily`, `ExistingOps`: the driver as a folder of a list of ops | 11 |
| `Transforms/Narrow/Copy.cpp:128-133` | upstream `arith::populateIntRangeNarrowingPatterns` | greedy, bottom-up, no folding, no region simplification, a listener erasing solver states | 11 |
| `Transforms/Tail/ReturnedArguments.cpp:59, 88` | `DropFromCall`, `DropFromReturn` | walk (`:129`) | 10 |
| `Transforms/Tail/WhileDo.cpp:301` | none | `eliminateTriviallyDeadOps` | 10 |
| `Transforms/Defunctionalize/Patterns.cpp:246-284` | `SlotPattern`s and `RetypePattern`, one copy of `RetypePattern` per registered operation but nine by name (`handled[]`) | `applyFullConversion` per function (`Pass.cpp:100`) | 06 |
| `Transforms/Columns/{ArrayOps,Calls,Tensors}.cpp` | 14 `OpConversionPattern`s, one `ConversionPattern` (`PerColumn`) | `applyPartialConversion` (`Columns.cpp:57`) | 11 |
| `Conversion/*.cpp` | 53 `IdrPattern<OpT>` instantiations, `LowerNoRuntimeForm` (`OpTraitConversionPattern<NoRuntimeForm>`, `Lower.cpp:69`), `LowerRuntimeCall<OpT>` (`RuntimeCalls.cpp:127`), upstream call and return type conversions (`Lower.cpp:142-143`) | `applyFullConversion` per function after a structural walk (`Lower.cpp:176-187`) | 12 |
| `Conversion/FuncToFunc.cpp:31, 51, 60`; `Matches.cpp:166, 174` | `LowerFunc`, `LowerCall`, `LowerReturn`, `LowerMatch`, `LowerMatchLit` | walk (`FuncToFunc.cpp:112`, `Lower.cpp:179`) | 12 |
| `Transforms/Effects/Constants.cpp:73, 160` | none | `OperationFolder` over a `DataFlowSolver`'s constants | 05, 09 |
| `tools/idris-mlir-reduce.cpp:36` | `PoisonResults`, one copy per registered operation but `ub.poison` | the reducer's | 13 |

**Where the greedy driver runs** (*read*, `Pipeline.cpp`,
`Optimize.cpp`): four `canonicalize` + `cse` pairs in the pipeline, two
nested on `idr.func` (`Pipeline.cpp:93-94` after `idr-columns`,
`:116-117` after `idr-bufferize`) and two on `func.func` (`:167-168`
after `convert-linalg-to-loops`, `:181-182` after
`idr-returned-arguments`), all through one helper (`Pipeline.cpp:28-32`:
region simplification off, top-down by the pass's default, every other
option default); and once per function per scheduler step in
idr-optimize's inner pipeline (`Optimize.cpp:64-67`), configured inline
a second time (`setUseTopDownTraversal()`,
`setRegionSimplificationLevel(Disabled)`). Upstream's canonicalizer
collects the patterns of every loaded dialect and every registered op
(pinned `mlir/lib/Transforms/Canonicalizer.cpp:74-81`), and never marks
analyses preserved when nothing changed (`:84-90`; CSE does,
`mlir/lib/Transforms/CSE.cpp:51`).

### 2.3 Facts held and derived; state; readers; threading

- **Held**: nothing between attempts. `Canon.h:8-12` states the rule
  (one frozen set shared by every function the canonicalizer runs on at
  once). No pattern keeps a member that changes, except `GiveBack`
  (`Identity.cpp:64-66`: `unsigned &calls`, a counter the walk driver
  bumps on one thread) and `NarrowWord`/`NarrowJoint` (lane 11).
- **Derived per attempt** (each recomputed on every visit, *read*):
  the yields of every region of a match (`Feeds.cpp:99-104`,
  `MatchPatterns.cpp:142-154`, `CaseOfCase.cpp:155-169`); the shape hash
  of every case (`Merge.cpp:56-72`); the regions a value's users sit in
  (`Sink.cpp:85-100`); whether the scrutinee can be empty
  (`Crashes.cpp:18-43`); whether a consumer folds with a constant, by
  cloning it (`Feeds.cpp:75-93`); an op's effects class (`MoveOut.cpp:71-103`,
  `Flow.h:83-93`); the linear chain to a value's source
  (`Grades.cpp:186-190`, a `SmallPtrSet` per call); the known
  constructor of a value from an enclosing match (three walks, §1's
  0003 item).
- **Folds** call the runtime's own C functions natively (`Fold.h:3-13`),
  each folder converting attributes to C values and back by hand.
  `fold::Scope` (`Scope.cpp:21-32`) releases what a fold took and adds
  any leak to an atomic counter on the dialect (`IdrBase.td:44-52`), which
  only idr-expect's `folds-balanced` reads (`Expect/Folds.cpp:19-27`).
- **Readers outside the subsystem**: `ConOp::fold` (`OpsCon.cpp:109,
  116`), `ClosureOp::fold`, `SuspendOp::fold` (`OpsClosures.cpp:126,
  161`) and `ConstantOp`'s verifier (`Constants.cpp:87`) read
  `canon::buildable`; `ConOp::fold` reads `canon::eta`; the op hooks of
  §2.2 call the `add*` functions; `CheckInBoundsOp::holds`
  (`OpsChecks.cpp:38-39`) and the lowering's static bytes
  (`Conversion/StaticBytes.cpp:126`) use `fold::Scope`.
- **Threading**: the canonicalizer is nested on functions, so the pass
  manager runs it in parallel per function (§5.1 F2 of the proposal);
  idr-optimize runs its inner pipeline under its own scheduler. Each
  fold's runtime counting is per thread (`Fold.h:46-55`); the leak
  counter is a relaxed atomic. `Scope::big` uniques a `StringAttr` in the
  context for every big operand of every fold (`Scope.cpp:38-42`), a
  context lock on the folding hot path (§5.1 F3).

## 3. Reconciliation with the proposal

### 3.1 Findings, one by one

- **§5.2 E1 (roots decide cost): holds, and the cutover holds in part.**
  No `MatchAnyOpTypeTag` remains (*measured*, grep: none; 7987388b's
  message). Sinking and case-of-case are `OpInterfaceRewritePattern<
  MatchOpInterface>` (`CaseOfCase.cpp:43`, `Sink.cpp:205`), filed at
  freeze under `idr.match` and `idr.match_lit` only. But two patterns
  outside this lane still match nearly every op, now spelled by name:
  `RetypePattern` is added once per registered operation except nine
  hand-listed names (`Defunctionalize/Patterns.cpp:268-284`, the list
  `handled[]` restating which ops have a pattern of their own), and
  `PoisonResults` once per registered operation except `ub.poison`
  (`tools/idris-mlir-reduce.cpp:57-63`). Under dialect conversion an
  any-op pattern is tried only at illegal ops, so the by-name expansion
  changes the spelling and the frozen set's size, not what is attempted;
  the honest root for a type conversion over an open op set is the
  any-op root (essential) or an interface, and the hand list is a second
  copy (C65, lane 06). The rooted patterns are rooted, but every one of
  the six of ours on a match re-reads all its regions on every visit
  (§3.2), which a root cannot fix.
- **§5.2 E2 (the greedy driver): holds in part.** The defaults and the
  ancestor requeue are as stated, and patch 62 cites our match patterns
  as its cause (`upstream/62-greedy-multi-region-ancestors/README.md`:
  "ours on `idr.match` and `idr.match_lit` (IR/Canon's SinkConsumer,
  EndAfterNoYield, `getTakenRegion`) read every region too"). What E2
  leaves out: `maxIterations` bounds the *outer* loop only. Inside one
  iteration the worklist runs until empty or `maxNumRewrites`
  (pinned `GreedyPatternRewriteDriver.cpp:463-466`), whose default is
  `kNoLimit` (`GreedyPatternRewriteDriver.h:170`; the canonicalizer's
  `max-num-rewrites` default is -1, pinned `Passes.td:48`). Two patterns
  that move one op back and forth never empty the worklist: c179ab2d's
  message ("idr-yield-fields moved back out, round and round") is that
  case, and neither call site sets the option (`Pipeline.cpp:28-32`,
  `Optimize.cpp:64-66`). So "never an error" holds (the canonicalizer
  ignores convergence unless `test-convergence`, pinned
  `Canonicalizer.cpp:84-90`), but "terminates by construction" does not:
  termination rests on the pattern set having a measure, which nothing
  states (C60, C08).
- **§5.2 E3 (the walk driver): holds.** It already serves every
  one-shot rewrite of ours: idr-identity (`Identity.cpp:81`), narrowing
  (`Narrow.cpp:90, 95, 152`), returned arguments
  (`ReturnedArguments.cpp:129`), the lowering's structure
  (`FuncToFunc.cpp:112`, `Lower.cpp:179`). Canonicalization alone uses
  the greedy driver.
- **§5.2 E4 (DRR, PDLL): holds; our tree uses neither** (*measured*: no
  `Pat<` in a `.td`, no `.pdll`). §6 counts what DRR could state.
- **§5.2 E5 (three ways to declare canonicalization): holds.** We use all
  three: 48 `hasFolder` lines, 9 `hasCanonicalizer`, 1
  `hasCanonicalizeMethod` (§2.2). Every pattern is rooted.
- **§5.2 B5 (`foldTrait` traits): not used.** No op carries
  `Commutative`, `Idempotent` or `Involution` (*measured*). The big ops
  `add`, `mul`, `and`, `or`, `xor` are commutative and could; the
  1b2e31da probe bug came from upstream `arith.xori`'s commutative
  fold relinking a use, so declaring it on ours makes the probe's copy
  necessary for them too (C12).
- **§5.2 M6: holds in part.** Rooted: yes. "Within one function, a
  one-shot rewrite is the walk driver's contract": true of our one-shot
  rewrites (E3 above), not of canonicalization, which keeps the greedy
  fixpoint inside idr-optimize's inner pipeline at every function it
  takes up (`Optimize.cpp:64-67`).
- **§5.2 M13, ods-Q4: evidence in §6.**
- **§5.1 D2 (greedy DCE reads `isOpTriviallyDead`): holds.** D3 holds
  in part for our matches: `idr.match` carries `RecursiveMemoryEffects`
  (`IdrMatchOps.td:26`), but `isOpTriviallyDead` checks `use_empty`
  first (pinned `SideEffectInterfaces.cpp:35-37`), so the whole-body walk
  is paid only by a match none of whose results is used. And the trait
  is load-bearing for canonicalization: upstream's `InlineRegionBranchOp`
  refuses any op without `HasRecursiveMemoryEffects` (pinned
  `ControlFlowInterfaces.cpp:1228-1231`), so replacing it by explicit
  effects (§5.1, 5.1.2 item 6, lane 02) would switch off the known-case
  inlining of every match unless that pattern changes (C50).
- **§5.1 C2 (per-application mapping in the region patterns): holds.**
  `RemoveDeadRegionBranchOpSuccessorInputs` builds
  `getSuccessorOperandInputMapping` for every branch point at each
  application (pinned `ControlFlowInterfaces.cpp:869-871`), on both match
  ops (`OpsMatch.cpp:188, 244`).
- **§5.1 F3, W5 (attributes created on hot paths): holds, one case.**
  `fold::Scope::big` makes a `StringAttr` of a big's decimal text for
  every big operand of every fold (`Scope.cpp:38-42`), only to hand its
  bytes to `idris_rt_str_from_utf8`: a context lock and context memory
  per fold, on the parallel canonicalizer (C41).
- **§5.3 B2/I2 and M12: hold.** `feeds` (`Feeds.cpp:153-190`) is a
  nine-arm per-pass table over ops that two patterns read (sinking and
  case-of-case), so I2 says interface, not `TypeSwitch` (C11). Each
  pattern re-finds ops by walking (M12): §3.2.
- **§5.4 F9 (Mojo's canonicalizer): matches ours.** Upstream's driver,
  patterns frozen once, region simplification disabled: our
  `Pipeline.cpp:28-32` is the same choice, with the reason written (CSE
  beside it).
- **§5.5 finding 18: holds.** Interface roots are filed per op at
  freeze; nothing of ours builds a per-op list by hand except the
  string roots of C19 and lane 11's `addNarrowWords` (C66).
- **§5.6 D2 (IREE's fixed-point pipeline, rejected): holds; we have no
  such pass.** idr-optimize runs its inner pipeline once per function
  per scheduler step; no "changed" attribute exists in canon (*read*:
  `Rebuild.cpp:6-8`, "A match carries no discardable attribute").
- **§5.6 E3 (memoized recursive effects): applies.** `MoveOut`'s
  `doesOf` walks every op between a read and a write, nested regions
  included, per attempt and from both roots (`MoveOut.cpp:71-103,
  171-193`).
- **§5.7 M11, L6: hold.** Our patterns are rooted (M11); no analysis is
  kept across rewrites by a listener in canon (L6 is lane 11's, in
  `Narrow/Copy.cpp:118-127`).
- **§5.8 DS4, O5: bear on canon's forms.** Our canonical form fuses
  output: `put_str(show_sint x)` becomes `put_sint x`
  (`Output.cpp:107-109`), `put_str(a ++ b)` two `put_str`s
  (`Output.cpp:75-78`): the opposite of O5's "compose before fusing"
  (C32, a new owner question, §6). DS4's `check.*` to `arith.cmpi` +
  `idr.check` would delete five guard folds (`OpsChecks.cpp:90-104`) for
  arith's, and `match_lit` on words as `scf.index_switch` would bring
  upstream's own `scf.index_switch` canonicalization (pinned
  `SCF.cpp:3734-3736`).
- **§5.9 E2/E3, M7, Design 5: holds as a diagnosis.** Our
  canonicalization is the opposite of MLton's shrinker in each respect
  the lane names: a fixpoint driver, not one linear sweep; facts
  recomputed per pattern per visit (§3.2), not computed once per
  function before the rewrite; run as a separate pass at four pipeline
  points and once per function inside idr-optimize, not called by each
  pass on what it rewrote. What it shares with the shrinker: a
  known-case selection (upstream's `InlineRegionBranchOp` with our
  `getTakenRegion` and `readField`), dead code after a case that never
  returns (`EndAfterNoYield`, the shrinker's `Bug` meaning), per-op
  folds.
- **§5.10 R1.4: compatible.** A future `is_unique` fold sits in this
  lane's fold layer; nothing here stops it.
- **§5.11 C7, A4: holds; the lane's two budgets are in program units.**
  `kSinkDuplicationLimit` counts ops (`Sink.cpp:54, 119-130`); the shift
  fold's `constantBytes` counts bytes of the constant made
  (`Bigs.cpp:70-77`), a size in the program's terms; neither fails.
- **§2's recalled gap "`IR/Canon/Sink.cpp:114` restates trait classes":
  holds in part.** The line is `isa<ConOp, ClosureOp>(value) &&
  !value->hasTrait<ResultCarriesOperand>()`: it restates "builds a value"
  but not `Idr_BuildsValue`'s set (which also holds `suspend`, `delay`,
  `cell.init`: `IdrClosureOps.td:37, 54, 72`, `IdrOwnershipOps.td:237`),
  and its `ClosureOp` arm is dead in the pipeline (C36).
- **0003's canon items: all still hold** at e96bb991 (each re-read: the
  three enclosing-match walks `Eta.cpp:39-47`, `OpsConReads.cpp:123-138`,
  `OpsMatch.cpp` `takenFromEnclosing`; `BigToIntOp::fold`'s guardless walk
  `Bigs.cpp:176-179`; `knownNonEmpty` `Crashes.cpp:18-43`; `feeds`
  `Feeds.cpp:153-190`; `MoveOut`'s `Does` `MoveOut.cpp:60`; the
  locations at `MatchPatterns.cpp:240-242`, `Force.cpp:54-63`,
  `Merge.cpp:97`, `Output.cpp:75-153`).

### 3.2 What a visit of one match costs today (*read*, then arithmetic)

N = the match's regions, R = its results, B = the ops before it in its
block. Each visit (the driver revisits after any change under the
match; patch 62 makes that once per drain of the worklist) runs:

| pattern | per visit | where |
| --- | --- | --- |
| `MakeRegionBranchOpSuccessorInputsDead`, `RemoveDuplicateSuccessorInputUses`, `RemoveDeadRegionBranchOpSuccessorInputs` | O(N) each (successor mapping of every branch point) | pinned `ControlFlowInterfaces.cpp:718, 859-871, 1006` |
| `InlineRegionBranchOp` | O(N) unless the scrutinee is known | pinned `:1211-1240` |
| `MergeIdenticalRegions` | O(N) hashes of every case body, one `DenseMap` built | `Merge.cpp:56-72` |
| `EndAfterNoYield` | O(N) successor regions when the scrutinee is unknown | `MatchPatterns.cpp:76-83` |
| `YieldFields` | O(R·N) | `MatchPatterns.cpp:120-158` |
| `SinkConsumer` | per result with one consumer: O(N) yields, each a `feeds` call that may clone the consumer to probe a fold; O(N·M) through an inner match of M regions | `CaseOfCase.cpp:50-67`, `Feeds.cpp:75-119` |
| `SinkIntoRegions` | up to O(B) candidates, each O(N) (`usersIn`, and `movesInto` for one that does more than compute) | `Sink.cpp:70-100, 170-196` |
| `StaticCase` / `DropEmptyStringCase` | cheap failure / an append-tree walk | `Force.cpp:104-111`, `Crashes.cpp:18-43` |

So a visit costs about (6 + R)·N + B·N, and a rewrite that changes the
match's results rebuilds it, moving all N regions (`Rebuild.cpp:20-46`).
Six of these questions read the same thing: what each region yields as
each result, and how each region ends. None is cached, and by
`Canon.h:8-12` none may be kept between attempts.

### 3.3 Wave-2 questions answered

- **§5.2 W2** (every `MatchAnyOpTypeTag` pattern and the ops it
  matches): none remains. The two any-op patterns in fact are
  `RetypePattern` (every registered op but nine) and `PoisonResults`
  (every registered op but `ub.poison`), §3.1 E1.
- **§5.2 W9** (passes that change nothing preserve analyses):
  idr-identity does (`Identity.cpp:83-84`); upstream's canonicalizer
  never does (pinned `Canonicalizer.cpp:84-90`), so each of the four
  pipeline canonicalizations and each inner-pipeline run invalidates
  every analysis and is verified even when it changed nothing (C62, an
  upstream patch).
- **§5.1 W3** (per-query edge tables): canon calls no `getPredecessors`;
  it calls `getEntrySuccessorRegions` once per visit
  (`MatchPatterns.cpp:79`); its per-query enumerations of regions are
  §3.2's.
- **§5.1 W4** (`RecursiveMemoryEffects` ops): both match ops
  (`IdrMatchOps.td:26`); upstream's inlining pattern requires it (§3.1).
- **§5.1 W5**: §3.1 F3 (C41).
- **§5.1 W6** (function anchoring): every canonicalize is nested on
  `idr.func` or `func.func` (`Pipeline.cpp:91-95, 114-118, 165-169,
  179-183`), so parallel.
- **§5.6 W-E4** (facts in discardable attributes): none in canon.
- **§5.6 W-E5** (budgets): `maxIterations` 10 (default, never read as
  failure), `maxNumRewrites` unset (no bound inside an iteration, C60),
  `kSinkDuplicationLimit` 64 ops (`Sink.cpp:54`), the shift fold's
  `constantBytes` (`Bigs.cpp:74`), `Narrow/Copy.cpp`'s default iteration
  budget (lane 11). None turns into a failure; the canon tests assert
  convergence with `test-convergence=true` (e.g.
  `tests/canon-force-of-choice/canon-force-of-choice.mlir:4`), a test
  property, not a pass rule.
- **§5.6 W-E6** (queries that walk a match's regions): §3.2's table.
- **§5.9 Q-W9** (idr-optimize's patterns: any-op, folds of one op,
  known-constructor folds of a match, or block simplifications upstream
  does): none is any-op. Folds of one op: the 77 folders, `FieldOp`'s
  and `TagOp`'s known-constructor folds (`OpsConReads.cpp:68-94,
  164-190`). Known-constructor folds of a match: upstream's
  `InlineRegionBranchOp` with our `getTakenRegion` and `readField`
  (`OpsMatch.cpp:189-190`), plus `StaticCase` (`Force.cpp:101`) and
  `DropEmptyStringCase` (`MatchPatterns.cpp:29`). Block simplifications:
  none upstream does for regions; `MergeIdenticalRegions` is what
  `mergeIdenticalBlocks` would do if cases were blocks (§5.9 Design 2),
  and `EndAfterNoYield` is the shrinker's dead code after `Bug`. The rest
  (case-of-case, sinking, yield-fields, move-out, output) have no
  upstream or shrinker counterpart: they are GHC-style transformations
  with a profitability test (`feeds`).
- **§5.3 (worklists, maps, callbacks)**: canon's worklists are
  `knownNonEmpty`'s `OnceWorklist` (`Crashes.cpp:21`) and the `Inside`
  stack (`Sink.cpp:136-159`), both per query; its maps are per attempt
  (`Merge.cpp:31, 57`; `SmallPtrSet`s at `Feeds.cpp:51`, `Sink.cpp:88,
  173`, `MoveOut.cpp:168`, `Grades.cpp:179`). No `std::variant`, no
  `function_ref` of ours on a hot path; the two `std::function`s are
  upstream's inlining-pattern callbacks (C50).
- **§5.4 (two implementations behind an option)**: none in canon.

## 4. Issues

Every claim *read* at the cited line unless marked. "Lane NN" means the
item is in that lane's files and listed here as the rewrite layer's
inventory; its disposition is that lane's. Dispositions name §5's
changes (T1 to T9).

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| C01 | `include/idr/IR/Canon.h:42-44, 88-93` | dead | Stale since 3a96c407: "those tried at every op that move values and consumers into matches", "Tried at every op, added once" for case-of-case and sinking, which are rooted at the matches | goes with T4 (the header is rewritten) |
| C02 | `lib/IR/Canon/Callees.cpp:17-25`, `Canon.h:25-35` | ladder, upstream | `retryBetween`: the ops whose pattern asks about the ops between it and a partner are listed by hand (`isa<MatchOpInterface, ArraySetOp>`, and any op with a match's result as operand), and requeued by an empty `modifyOpInPlace`, because the greedy driver tells only the ops a rewrite changes | T5: the class is a trait declared on those ops; the requeue is essential while effects are ordered by position (owner, DD-Q3), and goes if T4's per-function normalizer replaces the fixpoint |
| C03 | `lib/IR/Canon/Callees.cpp` (name) | dead | Named for the deleted `CalleePattern`/`bindCallees` (`git show d06ed15c:foreign/idr/lib/IR/Canon/Callees.cpp`); holds `retryBetween` only | renamed with T5 |
| C04 | `lib/IR/Canon/Captures.cpp:21-25`; reader `Constants.cpp:87` | ods, ladder | `buildable`, "the one leaf rule of a constant's parts", is an `isa<IntegerAttr, FloatAttr>` ladder living in canon and read by `ConstantOp`'s verifier: a fact of the constant attribute, not of canonicalization | moves to the constant's definition (`ConstantOp::isBuildableWith`, or a `LiteralTypeInterface` method); lanes 01/03 |
| C05 | `OpsCon.cpp:113-118`, `OpsClosures.cpp:124-130, 159-165` | list, cpp | The loop "fold to an attribute when every operand is a constant `buildable` at its type" written three times; `ClosureOp::fold` and `SuspendOp::fold` are the same body, both building `ClosureAttr` | T1: one trait with a `foldTrait` (`Idr_FoldsToConstant<Attr>`); the closure and suspension copies go with T8 if pre-defunc canonicalization goes |
| C06 | `lib/IR/Canon/CaseOfCase.cpp:59-67` | state, rederivation | `candidate` asks `meetsInSomeRegion` per result per visit: O(N) yields, each a `feeds` call | T4 (one yield table per visit) |
| C07 | `CaseOfCase.cpp:101-132` | rederivation | `canRaise` walks every op between the match and the consumer and every value the consumer's regions capture; `canLower` finds the ancestor of every user; per attempt | essential while effects are positional (crash, divergence); T4 computes it once per block |
| C08 | `CaseOfCase.cpp:3-15, 72-96` (c179ab2d) | budget | Case-of-case and `YieldFields` move one constructor in opposite directions; the fix moves the consumer two levels in one rewrite so the pair no longer meets. Termination rests on that case analysis: the pattern set states no measure | T3: the set's measure stated (each pattern lowers a well-founded size) and `maxNumRewrites` bounded in program units (C60) |
| C09 | `CaseOfCase.cpp:78-80`, `Sink.cpp:223-224`, `MoveOut.cpp:214` | ladder | The three callers of C02 | with C02 |
| C10 | `lib/IR/Canon/Eta.cpp:39-47`; `OpsConReads.cpp:123-138`; `OpsMatch.cpp` `takenFromEnclosing` | rederivation | What an enclosing match says about a value, three walks with three identity rules (0003); `TagOp::fold` asks none (`OpsConReads.cpp:164-185`) | T6 now (one `knownConstructor(Value, at)`); the state made unrepresentable by QL2/§5.7 L1 if a case region binds the refined scrutinee (owner) |
| C11 | `lib/IR/Canon/Feeds.cpp:153-190` | ladder | `feeds`: nine arms over op classes (`CallOp`, `PutStrOp`, `StrBuilderOpInterface`/`CheckNonemptyOp`/`StrHeadOp`, `PutListOp`, `ForceOp`, `ConOp`/`ClosureOp`, `MatchOpInterface`/`FieldOp`/`TagOp`, `CallOp` again, `BoxType`) read by two patterns (0003) | T2: an interface on the consumer, `meets(OpOperand &, Value)`, declared per op, the fold fact of T1 its default |
| C12 | `Feeds.cpp:75-93` (1b2e31da) | state, rederivation | `foldsWith` clones the consumer (`cloneWithoutRegions`: a new op, its operands linked into the values' use lists, properties copied) per query to learn whether it folds with a constant; the commit says no use list is touched, but the copy's own uses are linked and unlinked | T2: answered from the declared fact (T1: an `Idr_Runtime` op folds whenever its operands are constant and its guard holds; arith's folders are total on constants); the probe goes |
| C13 | `Feeds.cpp:99-119` | state | `someYield`/`yieldsFeeding` enumerate every region of the match, and of an inner match, per query: O(N), O(N·M) | T4 |
| C14 | `Feeds.cpp:41-59`; `Grades.cpp:186-190`; `Fold/Bigs.cpp:176-179` | rederivation | "The value through its carrying ops" walked three ways: `reader` (a `SmallPtrSet` per query), `linearPositions`/`throughLinear` (`definitionChain`, guarded), `BigToIntOp::fold` (no cycle guard, 0003) | one named step on `definitionChain` for `ResultCarriesOperand` (lane 01 owns `Grades.h`); the guardless walk goes |
| C15 | `Feeds.cpp:154-155, 177-180, 184-185` | dead | Arms for `ForceOp`, `SuspendOp`, `ClosureOp` and closure types: illegal after defunctionalization (`Defunctionalize/Pass.cpp:64-65`), and no canonicalizer runs before it | T8 (owner NQ1) |
| C16 | `lib/IR/Canon/Force.cpp:42-46`; `Flow.h:98` | rederivation | `staticByName` asks `performsIO`, one of §2's three representations of "does IO" | lane 02's one effects model; canon asks the effect |
| C17 | `Force.cpp:113-117` | state | `StaticCase` walks the taken region per attempt for `memo.run`s | minor; T4 |
| C18 | `Force.cpp:54-63`, `MatchPatterns.cpp:240-242`, `Merge.cpp:97`, `Output.cpp:75-153` | rederivation | Locations: a pattern variable's, a piece's, a capture's location replaced by the match's or the builder's though the argument's is in hand (0003) | fixed in the cutover: `FusedLoc` of the argument and the match |
| C19 | `lib/IR/Canon/MatchPatterns.cpp:68-72, 109-113, 199-202`; `Merge.cpp:78-81` | cpp, list | `EndAfterNoYield`, `YieldFields`, `MergeIdenticalRegions` rooted by an op-name string and added twice (once per match op), where an interface root added once is the root (as `SinkConsumer` is) | T4 (one interface-rooted pattern); `populate(..., StringRef root)` and `addMerge`'s `root` go |
| C20 | `MatchPatterns.cpp:85` | ladder | `isa<MatchOpInterface, idr::FuncOp>(block->getParentOp())` lists the parents of a region whose single block may end in `ub.unreachable` | read the region (`hasOneBlock`, its terminator), not the parent class |
| C21 | `MatchPatterns.cpp:76-83` | state | `getEntrySuccessorRegions` and a terminator check of every region per visit when the scrutinee is unknown | T4 |
| C22 | `MatchPatterns.cpp:117-119` | attribute, ladder | `YieldFields` reads the program's stage (`stageFacts(...).grades()`): a canonicalization valid in one stage is switched by a phase fact read inside a pattern. No `idr.func` canonicalization runs after idr-rc in the pipeline (`Pipeline.cpp:91-118` against `addRc` at `:128`), so the read guards fixtures only | T7: populated only by the pre-grade canonicalizer; the stage read goes |
| C23 | `MatchPatterns.cpp:131-158` | state | `constructors` iterates every region per result per visit: O(R·N) | T4 |
| C24 | `MatchPatterns.cpp:29-39`; `Crashes.cpp:18-43`; `OpsChecks.cpp:98-100` | rederivation, idris | Non-emptiness of a string re-walked down its appends per question (an `OnceWorklist` per call), by `DropEmptyStringCase` and `CheckNonemptyOp::fold` (0003) | non-emptiness in the string's type (as `!idr.nat` holds non-negativity), set by the builders and the frontend; the walk and `DropEmptyStringCase` go (the case is then unreachable by the match's own taken-region rule). Owner: Q-O3 |
| C25 | `lib/IR/Canon/Merge.cpp:56-72` | state | `firstRepeated` hashes every case body into a `DenseMap<hash_code, SmallVector>` built per visit (64 buckets once used, §5.3 B7) | T4; Design 2 hands it to upstream's `mergeIdenticalBlocks` (owner Q-O1) |
| C26 | `lib/IR/Canon/MoveOut.cpp:60, 71-103`; `Flow.h:83-93` | rederivation, list | A second `enum class Does { Computes, Effects, Touches }` and `doesOf` beside `idr::Does`/`classify`; they disagree on `ub.unreachable` (0003) | one classifier (lane 02); MoveOut passes its predicate |
| C27 | `MoveOut.cpp:89` | ods, dead | `isa<ForceOp>(op)`: a force's read is not declared in ODS (0003); `ForceOp` is gone after defunctionalization | declared in ODS (lane 02); the arm goes |
| C28 | `MoveOut.cpp:74-80` | ladder | Effects classified by `getResource() == IOResource::get()` and value-type equality: a third hand reading of resources (0003 lists `Placement.cpp` and `Forms.cpp`) | the resource tree's `isa<IOResource>` (§5.2 A8); lane 02 |
| C29 | `MoveOut.cpp:106-115` | rederivation | `usesWorld` walks for world-typed operands and results: "does IO" read off types, the third representation (§2) | lane 02 / DS2 (owner DD-Q3) |
| C30 | `MoveOut.cpp:146-149, 171-193, 247` | state | One question asked from two roots (`MoveOut<ArraySetOp>`, `MoveOut<ArrayGetOp>`), each walking every op between, nested regions included, per attempt | T4; *conjecture*: the read's root is redundant once the write's world operand is the read's result, since replacing the read requeues its users (pinned `GreedyPatternRewriteDriver.cpp` `notifyOperationReplaced`); to be checked against `tests/canon-array-moves` |
| C31 | `lib/IR/Canon/Output.cpp:26-29, 80, 145, 153, 159, 161`; `IdrInterfaces.td:274-288` | cpp, ods | `StrBuilderOpInterface` pairs a `bool` predicate with a partial method (`knowsFirstChar`/`firstChar`, `writesInPieces`/`writePieces`); five `unasked` stubs abort when asked against the predicate | `knowsFirstChar` is static per op: an interface (or DRR patterns, §6) that only the five ops implement; `writePieces` returns `FailureOr<Value>` (the one dynamic case is `pack`/`concat`'s one use); the stubs go |
| C32 | `Output.cpp:107-133` | ods | The canonical form fuses output: `put_str(show_sint x)` to `put_sint x`, and likewise for `show_uint`, `show_double` | owner NQ3 (§5.8 O5 says compose; fuse at lowering) |
| C33 | `lib/IR/Canon/PutList.cpp:49`; `Fold/Values.cpp:51-61` | ods, ladder | A list's cons and nil read off `CtorRole` (`kindOf(...role) != ListCons`; a `switch` with four arms returning nothing): the data type's body has no typed list view (0003) | lane 01's `Body` per kind; canon reads `DataType::listCons()` |
| C34 | `PutList.cpp:55-57`; `Fold/Strings.cpp:229-236` | (essential) | `put_str` or `put_char`, append or cons, by the element type: two runtime functions | essential (the problem has two element types); DRR states it as two patterns with type constraints (§6) |
| C35 | `lib/IR/Canon/Sink.cpp:54, 119-130` | budget | `kSinkDuplicationLimit = 64` ops past the first region; keeps the value in place, never fails | kept (program units, §5.11 C7) |
| C36 | `Sink.cpp:114` | ladder | `isa<ConOp, ClosureOp>(value) && !hasTrait<ResultCarriesOperand>`: "builds a value", narrower than `Idr_BuildsValue`; the `ClosureOp` arm dead in the pipeline | the trait, with its set decided (does a suspension sink? essential or not); T8 |
| C37 | `Sink.cpp:70-100` | state | `movesInto` counts the match's regions (O(N)) for a candidate that does more than compute; `usersIn` enumerates every region per candidate | T4 |
| C38 | `Sink.cpp:161-196` | state, rederivation | `nearestSinkable` re-asks the whole question per visit, interleaving a scan back through the block with a walk of the match (its comment says so) | T4 |
| C39 | `lib/IR/Canon/Rebuild.cpp:20-59` | (essential) | A rewrite that changes a match's results rebuilds it, moving all N regions: O(N) per rewrite | essential under MLIR's fixed result list; Design 2 (a case terminator) makes a moved consumer not rebuild the case (owner Q-O1) |
| C40 | `include/idr/IR/Fold.h:79-120`; `Fold/Bigs.cpp:45-217`; `Fold/Strings.cpp:29-268` | rederivation, ods | Thirty-seven folders convert attributes to the runtime's C arguments and back by hand (sign or zero extension, `wrapped`, `compared`, `scope.attr`), restating per op what the generated ABI table already states: `Abi<Op>::operands` (`OperandKind`: `Int32`, `Int64`, `Double`, `Signed`, `Unsigned`, `Str`, `Big`, ...) and `entry.result` (`ResultKind`: `Wrapped`, `Order`, `Str`, `Big`, ...) (`tools/idris-mlir-tblgen.cpp:731-768, 2976-2986`), which the lowering reads | T1: one generic runtime fold read off `Abi<Op>`, supplied by a trait; the per-op bodies go |
| C41 | `lib/IR/Fold/Scope.cpp:38-42` | state | `Scope::big` uniques a `StringAttr` of the decimal text per big operand per fold, to pass its bytes to the runtime | T1: the runtime string made from the `SmallString` |
| C42 | `Fold/Scope.cpp:28-31`; `IdrBase.td:44-52`; `Expect/Folds.cpp:19-27` | state | A relaxed atomic counter of fold leaks held on the dialect object, read only by idr-expect's `folds-balanced` | kept as a contract, counted in T1's one fold |
| C43 | `Fold/Bigs.cpp:180-183`; `Transforms/Narrow/Narrow.cpp:107-108` | list, ladder | "A big made of a word" as `isa<BigFromSIntOp, BigFromUIntOp, BigSmallOp>` twice | a trait (`Idr_WordToBig`) or the inverse of the generated `BigToWord` record (lane 11 shares it) |
| C44 | `Fold/Bigs.cpp:70-77` | budget | Shifts fold only into constants within `constantBytes`; keeps the op, never fails | kept |
| C45 | `Fold/Bigs.cpp:161-170` | ods | `big.small` folds through `big.from_sint`'s function: the two ops mean one thing where the small's own function is defined | lane 03 (one op per semantics, DS4) |
| C46 | `Fold/Bigs.cpp:39-42` | (essential) | `big.add`'s zero identity checks the operand's type against the result's (owned against view after idr-rc) | essential: the grade is in the type |
| C47 | `Fold/Strings.cpp:175-180`; `Output.cpp:50-63, 90-91` | rederivation | The head of a `str.cons` (through its non-empty guard) stated in `StrHeadOp::fold` and again by `HeadOfBuilder` through `StrConsOp::firstChar` | one place: the fold (it makes no op); `HeadOfBuilder` keeps only builders that make an op |
| C48 | `Fold/Values.cpp:23-43` | (generated) | `compared`: a `switch` over the generated `CmpPredicate` | stays inside T1's `ResultKind::Order` conversion |
| C49 | `lib/Transforms/Identity/Identity.cpp:43-67` | state | `GiveBack` holds a mutable counter and the ready set by reference; the pass is constructed with the set, not given it through the analysis manager | lane 09 |
| C50 | `OpsMatch.cpp:187-192, 242-248` | upstream | Upstream's region patterns rooted by name string with two `std::function` callbacks (`readField`, `readsPlainValue`); `InlineRegionBranchOp` requires `HasRecursiveMemoryEffects` (pinned `ControlFlowInterfaces.cpp:1228-1231`) | kept; lane 02 must keep the trait or carry an upstream change of the precondition |
| C51 | `OpsClosures.cpp:40-58` | dead, rederivation | `ForceOfOneUse` runs `suspend->fold` to decide its own precondition ("whichever the driver reaches first"); dead in the pipeline | T8 |
| C52 | `OpsClosures.cpp:61-91` | dead | `ForceInOneCase`: dead in the pipeline | T8 |
| C53 | `OpsClosures.cpp:124-130, 159-165, 174-184` | dead | `ClosureOp`, `SuspendOp`, `ForceOp` folds: reached only by fixtures run with `--canonicalize` before defunctionalization (`tests/canon-force-of-choice`, `canon-evaluated-suspension`, `canon-force-of-own-constant`) | T8 |
| C54 | `OpsConReads.cpp:68-94, 101-153` | rederivation | `FieldOp::fold` and `FieldOp::canonicalize` split one rule (a field of a known constructor) by whether the grade matches; the enclosing-match walk is C10's | T6 |
| C55 | `OpsChecks.cpp:70-84` | (evidence) | `checkedBefore`: a guard identical to the one before folds away inside its fold, since CSE does not merge ops with a `Crash` effect | goes to upstream CSE if a crash is speculation only (owner ods-Q1) |
| C56 | `OpsChecks.cpp:24-29` | ladder | `CheckNonzeroOp::holds` branches on `BigAttr` against `IntegerAttr` | minor; a literal type's `isZero` (lane 01) or DS4's `arith.cmpi` |
| C57 | `OpsPlatform.cpp:21-30, 37-44` | per-target | `OsOp::fold`: a ladder of triple predicates naming the OS, and a fallback to the build's triple (`IDRIS_MLIR_TARGET_TRIPLE`) for a module without one (0003) | the OS name is the target entry's fact, written into the module by idr-target; the fold reads it; the fallback goes (lane 13) |
| C58 | `include/idr/IR/Canon.h:34, 79-93` | cpp | Canon-internal functions in the public header: `retryBetween`, `feeds`, `meetsInSomeRegion`, `addMerge`, `addCaseOfCase`, `addSink`, `addStaticForcePatterns` have no reader outside `lib/IR/Canon/` (*measured*: `grep -rn "canon::" lib include tools unittests`) | private to canon after T4 |
| C59 | `lib/Transforms/Pipeline.cpp:28-32`; `Optimize/Optimize.cpp:64-66` | list | The canonicalizer's configuration written twice (top-down, region simplification off) | T3: one `idr::canonicalizer()` |
| C60 | same | budget | `maxNumRewrites` left at `kNoLimit`: a cycle of patterns loops inside one iteration (C08, c179ab2d) | T3: a bound in program units (k times the function's ops), never a failure |
| C61 | pinned `mlir/lib/Transforms/Canonicalizer.cpp:74-81` | upstream | Every loaded dialect's and registered op's canonicalization patterns are collected; `filter-dialects` (present at the pin) is unused | T3: name the dialects whose canonicalizations the pipeline relies on (owner NQ4) |
| C62 | pinned `Canonicalizer.cpp:84-90` | upstream | The canonicalizer never marks analyses preserved when it changed nothing (CSE does, `CSE.cpp:51`), so every no-op canonicalize drops every analysis and is verified | T3: `upstream/<bug>/` patch passing `&changed` and preserving when unchanged |
| C63 | pinned `GreedyPatternRewriteDriver.cpp` `addToWorklist` (patch 62) | upstream | A change requeues every ancestor; our six match patterns are named in the report as what makes it quadratic | carried; the cost per revisit falls with T4 |
| C64 | `Transforms/Narrow/Narrow.cpp:126-128` | upstream | The greedy driver with an empty pattern set as a folder and dead-code eraser of a list of ops | lane 11 (`OperationFolder` or the walk driver plus `isOpTriviallyDead`) |
| C65 | `Transforms/Defunctionalize/Patterns.cpp:268-284`; `tools/idris-mlir-reduce.cpp:57-63` | list | `RetypePattern` and `PoisonResults` copied per registered operation, with a hand list (`handled[]`) of the nine ops that have patterns of their own | lanes 06, 13: the any-op root is essential for a type conversion over an open set (tried at illegal ops only); the hand list goes either way |
| C66 | `Transforms/Narrow/Ops.cpp:226` (`addNarrowWords<MatchLitOp, CheckNonzeroOp, DupOp, DropOp, GET_BIG_TO_WORD_LIST>`) | list | Four roots by hand beside a generated list | lane 11 |

*Measured counts behind the table*: `grep -n -E "isa<|isa_and_nonnull<|isa_and_present<|IsaPred<|hasTrait<"` over this lane's files: 35 lines (C02, C04, C11, C20, C26-C28, C34, C36, C43 cover the ones that classify ops or attributes; the rest are upstream traits or single types). Folders read off the ABI table (C40): every `fold::runtime<Op>` call whose body is attribute-in, runtime, attribute-out with at most a guard: 37 of the 47 in `lib/IR/Fold/` (*read*, one by one; the ten others (`big.add`, `shl`, `shr`, `pred`, `nat_to_big`, `small`, `to_int`; `str.head`, `pack`, `concat`) carry an identity, a size policy, a zero check, another op's function, a cons shortcut, a round trip or a list walk).
## 5. Target design

All *conjecture* until built; each change carries the skill's one line.
The changes are ordered by leverage; the cutover order is at the end.

**T1. One runtime fold, read off the ABI table.** A trait
`Idr_RuntimeFolds` (placeholder name), a `NativeOpTrait` whose static
`foldTrait` (run by `Op::foldHook` after an op's own folder, §5.2 B2)
reads `Abi<ConcreteOp>`: each constant operand converted by its
`OperandKind` (`Signed` sign-extends, `Unsigned` zero-extends, `Int32`,
`Int64`, `Double`, `Str`, `Big`), the op's guard asked first where the op
is `GuardedOp` (`Traits.h:162`), the C function called in one
`fold::Scope`, the result converted by its `ResultKind` and the op's
result type (`Wrapped` by `wrapped`, `Order` by `compared` with the op's
predicate, `Str`, `Big`, `Double`). It is one template over the
function's C signature, constrained by a concept that reads the
`Abi` specialization (cxx26 D1: typed code below the dispatch, reading
ODS, never listing ops), bundled into `Idr_Runtime<sym>` for the ops that
are pure. The ops keep `hasFolder` only for what is theirs (`big.add`'s
zero, the shift's size policy, `big.pred`'s zero, `str.head` of a cons,
`big.to_int`'s round trip, `str.pack`/`concat`'s list walk). The same
move for constructors: `Idr_FoldsToConstant<Attr>` with one `foldTrait`
for `con`, `closure`, `suspend` (C05). `Scope::big` passes the text to
the runtime without a `StringAttr` (C41).
- Deletes: 37 folder bodies in `lib/IR/Fold/{Bigs,Strings}.cpp`,
  `strUnary`, `strBinary`, `bigUnary`, `bigBinary`, `strAtOffset`, two of
  the three constant-folding loops, the `StringAttr` per big operand.
- **Made unrepresentable:** a folder whose conversion of an operand
  disagrees with the lowering's call of the same function (both read
  one `Abi<Op>` row); a pure `Idr_Runtime` op that does not fold its
  constants.

**T2. `feeds` declared, the probe deleted.** An op interface on the
consumer (0003's `meets(OpOperand &, Value)`), declared per op in ODS:
output meets an empty string or a builder that writes in pieces; a
field, a tag, a match meet a known constructor; a call meets a closure
type; its default is "every other operand is constant and the op is
`Idr_RuntimeFolds` or `Idr_FoldsToConstant`" (T1's fact, which needs no
fold run). Upstream ops (arith) get it by an external model (§5.2 C3)
whose body, for them alone, keeps the probe on a copy: the one place
where "would upstream's folder fold this" is asked.
- Deletes: the nine-arm ladder (C11), the per-query clone for every op
  of ours (C12), `closedWith`.
- **Branch deleted:** `feeds`' switch on op classes; **check moved to a
  boundary:** what folds is declared once per op, not tested per query.

**T3. The greedy driver configured once, bounded, and preserving.** One
`idr::canonicalizer()` (C59) for the pipeline and idr-optimize's inner
pipeline: top-down, region simplification off (CSE beside it),
`filter-dialects` naming the dialects whose canonicalizations the
pipeline relies on (C61, owner NQ4), and `maxNumRewrites` set per run to
a multiple of the function's op count, a budget in the program's units
that leaves a function less canonical and never fails (AGENTS.md; §5.11
C7; owner NQ2). An `upstream/<bug>/` patch makes the canonicalizer pass
`&changed` and mark all analyses preserved when nothing changed, as CSE
does (C62), with its report, reproducer, test and plan. Patch 62 stays
carried.
- Deletes: the second configuration (`Optimize.cpp:64-66`); the
  verifier run and the analyses dropped after every canonicalize that
  changed nothing.
- **Made unrepresentable:** a hang from a cycle of patterns (C08, C60):
  the run stops at the bound, and `test-convergence=true` in the canon
  tests keeps reporting the cycle as a test failure.

**T4. One canonicalization of a match per visit, over one view.** The
six patterns of ours on a match (§3.2) become one
`OpInterfaceRewritePattern<MatchOpInterface>` that builds, once per
visit, a `MatchView`: for each region its end (yield, `ub.unreachable`,
empty), the value each region yields as each result and that value's
defining op, its shape hash; for each result its uses; for the values
before the match in its block, the regions their users sit in. Then it
tries, in a fixed, written order, the rewrites the six patterns make
today (merge, end after no yield, yield fields, the known static case,
case-of-case, sinking), each reading the view. Like MLton's shrinker
(§5.9 E2), the facts are computed before the rewrite, not per question;
unlike it, the visit stays inside upstream's driver, so upstream's region
patterns and every fold still run beside it.
- Deletes: five of six O(N) rescans per visit (C06, C13, C21, C23, C25,
  C37, C38), the string roots and `populate(..., root)` (C19), `addMerge`,
  `addCaseOfCase`, `addSink`, `addStaticForcePatterns` as separate
  entries, the public canon-internal declarations (C58).
- **Check moved to a boundary:** what a match's regions yield is read
  once per visit, at the root, and handed to every rewrite.
- *Owner-dependent*: under §5.9 Design 2 (a case terminator, Q-O1) this
  view is the terminator's successor list and the merge is upstream's
  `mergeIdenticalBlocks`; T4 is then rewritten for the CFG form. Under
  §5.9 Design 5 (owner NQ5) the same view drives a per-function
  normalizer on the walk driver that each pass calls on what it rewrote.

**T5. `retryBetween`'s class declared.** A trait (placeholder
`Idr_AsksAcross`) on the ops whose canonicalization asks about the ops
between it and a partner (the match ops, `array.set`), read by
`hasTrait`; the requeue stays, documented as essential while crashes and
divergence are ordered by position (owner ods-Q1, ods-Q3, DD-Q3).
- Deletes: the `isa<MatchOpInterface, ArraySetOp>` ladder (C02), the file
  named for a deleted class (C03).
- **Branch deleted:** the ladder; essential part kept: the requeue, since
  the greedy driver tells only changed ops (pinned driver,
  `addToWorklist`).

**T6. One answer to "what is this value here".** One
`knownConstructor(Value, Operation *at)` for record eta, `FieldOp`'s
canonicalization, `TagOp::fold` and the match's `takenFromEnclosing`
(C10, C54), on one identity rule; `BigToIntOp::fold`'s walk on
`definitionChain` (C14).
- Deletes: two of three enclosing-match walks; the guardless walk.
- **Made unrepresentable** (if QL2/§5.7 L1 is adopted): the walk itself,
  since a case region would bind the refined scrutinee and the answer is
  a block argument.

**T7. A pattern's phase is the pass's, not the pattern's.** `YieldFields`
reads the program's stage (C22). In the pipeline no `idr.func`
canonicalization runs after idr-rc (`Pipeline.cpp:91-118` against
`addRc` at `:128`), so the check guards only fixtures; the pattern is
populated by the canonicalizer that runs before the grades and the stage
read goes.
- **Branch deleted:** the stage test inside the pattern.

**T8. Pre-defunctionalization canonical forms: decided, not left
unreached.** `ForceOfOneUse`, `ForceInOneCase`, the `closure`, `suspend`
and `force` folds, and the closure, suspension and force arms of `feeds`
and `Sink` (C15, C36, C51-C53) are reached only by fixtures run with
`--canonicalize` before defunctionalization. Either the pipeline gains a
canonicalization before `idr-defunctionalize` (where these forms would
shrink what the label solve sees) or they and their fixtures go (owner
NQ1).
- **Branch deleted** (second option): every arm for an op that the
  conversion target makes illegal (`Defunctionalize/Pass.cpp:64-65`).

**T9. Output's forms.** `StrBuilderOpInterface`'s `bool`-plus-partial
pairs become total: `knowsFirstChar` an interface only the five ops that
know it implement, `writePieces` returning `FailureOr<Value>` (C31), or
DRR patterns (§6, ods-Q4); the head of a cons stated once, in the fold
(C47); the list's cons read from a typed view of its data type (C33,
lane 01). Which direction is canonical for output (fuse, as now, or
compose and fuse at lowering, §5.8 O5) is owner NQ3 (C32).
- Deletes: five `unasked` stubs, `HeadOfBuilder`'s cons case, the role
  `switch` in `listElements`.
- **Made unrepresentable:** asking a builder for a piece it cannot
  give.

**Kept, and why.** The greedy driver for canonicalization (upstream's,
§4's first preference; the fixpoint is what folds feeding folds need);
`kSinkDuplicationLimit` and `constantBytes` (budgets in program units
that never fail); upstream's region patterns and their `std::function`
callbacks (cold hooks at an upstream API, §5.3 B5); `MatchOp::rebuild`'s
O(N) per rewrite (MLIR's fixed result list, C39); `put_str` against
`put_char` (two runtime functions, C34); `big.add`'s type check (the
grade is in the type, C46).

**The Idris side.** Nothing in this lane has an Idris counterpart
(*measured*: `grep -rl -i canonicali compiler/src` finds nothing); the
frontend emits the forms canon rewrites, and two of the changes reach it.
If non-emptiness moves into the string type (C24), the generated mirror
of the dialect (lane 14) carries the new type and Emit builds it where a
string is made by a cons, a character or a number: in the type-driven
reading, a string builder's result type is indexed by what it is known
to be, so the empty-string case cannot be written for it. If output
composes (NQ3), Emit stops choosing among `put_sint`, `put_uint`,
`put_double` and emits a `show` and one write (lanes 14, 15). The guard
Emit puts before a head is already generated from the guarded op's ODS
facts (`compiler/src/IdrisMLIR/Emit/Operations.idr:76`), so T1 changes
nothing there.

**Order inside the lane, and dependencies.**
1. T3 first: it removes the hang (C60) and a verifier run per no-op
   canonicalize (C62); it touches only the two call sites and an
   upstream patch. Depends on lane 13 (pipeline) for the call sites.
2. T1, with lane 03 (the ops' `hasFolder` lines, `big.small`, C45) and
   lane 14 (`idris-mlir-tblgen`'s `Abi` table is the input; if Q-llvm-5
   moves the backend onto `MlirTblgenMain`, the table must still be
   generated with the same rows).
3. T2 after T1 (its default reads T1's trait).
4. T6 with lanes 01 and 03 (the identity rule, `Grades.h`'s chain step;
   QL2 decides whether the walk survives at all).
5. T4 and T5 together, after T2 and T6, and after the owner's Q-O1
   (CFG or regions) and NQ5 (driver or normalizer).
6. T7, T8, T9 on the owner's NQ1, NQ3 and ods-Q4.
7. Lane 02 owns the effect questions canon asks (C16, C26-C29, C50);
   canon follows its one classifier and its resource tree. Lane 19 owns
   the canon fixtures that T8 keeps or deletes.

## 6. Evidence for the owner's questions

**ods-Q4. DRR allowed, PDLL refused?** What our code says:
- Our tree has no DRR and no PDLL (*measured*: no `Pat<` in any `.td`, no
  `.pdll`).
- Of our 19 canonicalization pattern classes (§2.2, with
  `FieldOp::canonicalize` and `GiveBack`), five are DAG rewrites rooted
  at one op name that DRR can state (*read*, each):
  `PutListOfConstant` (one `Pat` with a `NativeCodeCall` to
  `stringOfList`), `PutListOfCons` (two `Pat`s, one per element type,
  with a one-use constraint and a native constraint for the cons: this
  deletes the `isa<StrType>` choice, C34), `PutStrOfBuilder` (one `Pat`
  per builder op that writes in pieces: eight, `pack` and `concat` with
  `HasOneUse`), `HeadOfBuilder` (one per op that knows its head: five,
  since `check.nonempty` already folds away on such a builder,
  `OpsChecks.cpp:98-100`), `ForceOfOneUse` (one `Pat`; dead in the
  pipeline, C51). About 16 `Pat`s in all, and they would delete
  `StrBuilderOpInterface`'s `writesInPieces`/`writePieces`/
  `knowsFirstChar`/`firstChar` and its five `unasked` stubs (C31): the
  facts move from C++ methods into ODS records, one per op, which is the
  same count of facts in a declarative place.
- The other fourteen cannot be DRR: they read or write regions
  (`SinkConsumer`, `SinkIntoRegions`, `MergeIdenticalRegions`,
  `EndAfterNoYield`, `YieldFields`, `DropEmptyStringCase`, `StaticCase`,
  `ForceByName`, `MoveOut` twice, `WorldUnused`), walk enclosing regions
  (`FieldOp::canonicalize`), read several uses at once
  (`ForceInOneCase`), or read a pass's summary (`GiveBack`); so do
  upstream's four region-branch patterns we add. Every pattern that
  costs on a large match (§3.2) is on this side. PDLL would not change
  that count (*recalled*: PDL matches operation DAGs, not region
  contents; to check against `mlir/include/mlir/Dialect/PDL/IR/PDLOps.td`).
- Five of our folds are DAG identities DRR could also state
  (`lin.use(lin.enter x)`, `lin.enter(lin.use x)` with one use,
  `tie_shape(tie_shape x)`, `transpose(transpose x)`,
  `big.to_int(big.from_sint x)`: `OpsScalars.cpp:94-109`,
  `OpsArrays.cpp:288-294`, `OpsGenerating.cpp:126-135`,
  `Fold/Bigs.cpp:172-183`); as folds they run before any pattern and make
  no op, which a `Pat` would not improve.
- Production precedent besides arith: CIRCT's FIRRTL canonicalizes with
  DRR (§5.8 E5, `FIRRTLCanonicalization.td:669-672`).

**ods-Q1 / DD-Q2 (dead crash or divergence).** Canon today treats a
crash and a possible loop as effects to keep, on every path and in
order: a value that may crash or not return moves into a match only
when every region uses it and nothing between does more than compute
(`Sink.cpp:15-19, 70-82`); case-of-case moves a consumer past only ops
that compute (`CaseOfCase.cpp:5-7, 101-120`). Because a guard carries a
crash effect, CSE cannot merge two identical guards, and
`checkedBefore` does it inside the guard's fold (`OpsChecks.cpp:70-84`,
C55): under upstream's model (a guard `NoMemoryEffect` and not
speculatable) that fold goes to CSE. `MoveOut` counts
`ub.unreachable` as computing (`MoveOut.cpp:68-70, 85-86`), and
`EndAfterNoYield` erases ops after a match that never completes because
control never reaches them (`MatchPatterns.cpp:58-97`), not by an effect.

**Q-O1 (structured match past defunctionalization).** Ten patterns try
each visit of a match, six ours and four upstream's, and each reads all
N regions (§3.2); three of ours change the match's results and so
rebuild it, moving every region (C39). In a CFG form, merging identical
cases is upstream's `mergeIdenticalBlocks` (C25), changing what a case
yields is an edit of successor operands in place, and the per-region
yield table of T4 is the terminator's operand list (*conjecture* for the
last two).

**QL5 (equality saturation out of P0).** One canon bug was a
phase-ordering cycle between two canonicalizations (c179ab2d:
case-of-case and yield-fields moving one closure for ever), fixed by a
combined rewrite; the profitability test of case-of-case and sinking is
a simulated fold (C12). No §3 wall came from either: the 75 million
attempts were roots (3a96c407), the six hours a relinked use list
(1b2e31da).

**Q-llvm-2 / Q-E3 / oom-2 (budgets).** Canon's budgets
(§3.3 W-E5): `kSinkDuplicationLimit` (64 ops) and `constantBytes` count
in the program's units and never fail; `maxIterations` (10) never fails;
`maxNumRewrites` is unset, so a cycle hangs instead of stopping (C60).

**ods-Q6 / Q-M2 / Q-O5 (verification after every pass).** idr-optimize
runs its inner pipeline with `runPipeline` so that "the verifier and the
manager's instrumentation run on each function as they would under a
nest" (`Optimize.cpp:10-13`); upstream's canonicalizer never preserves
analyses (C62), so the verifier runs after every canonicalize, in the
inner pipeline and at the four pipeline points, whether or not it
changed anything.

**DD-Q4 (signedness).** Our folds already read signedness from the op:
the division and shift folds take `isSigned` from ODS constants
(`IdrScalarOps.td:31-34, 66-69`, read by the concepts at `Ops.cpp:225-296`),
and the runtime folds from the ABI's `Signed`/`Unsigned` operand kinds
(`idris-mlir-tblgen.cpp:738-741`). T1 keeps it there under either school.

**DD-Q5 (one op, several runtime functions).** `Abi<OpT>` has exactly one
specialization per op (`idris-mlir-tblgen.cpp:2976-2986`), and both the
folders and the lowering index it by op class; one op with an enum over
several functions would key it by (op, case), and T1's generic fold would
dispatch on the case once.

**Q-O3 (facts into types).** Non-emptiness of a string is searched for
per question (C24) by a pattern and a fold; in the type, the empty-string
case would be unreachable by the match's own taken-region rule.

**QL2 (one value per ownership state).** Three walks up enclosing
matches recover what a case region knows (C10); `readField` walks the
scrutinee's linear positions to find what to read fields from
(`MatchPatterns.cpp:218-243`). A case region binding the refined
scrutinee makes both a block-argument read.

**New questions for the owner.**
- **NQ1. Pre-defunctionalization canonical forms.** No canonicalizer
  runs before `idr-defunctionalize`, so the force, suspension and
  closure canonicalizations (two patterns, three folds, arms in `feeds`
  and `Sink`) are reached only by their fixtures (C15, C36, C51-C53).
  Add a canonicalization before defunctionalization, where they would
  shrink the closure sets the label solve sees, or delete them with
  their fixtures?
- **NQ2. A rewrite budget for canonicalization.** `maxNumRewrites` is
  unset, so a cycle of patterns hangs inside one iteration
  (c179ab2d). Set it per run to a multiple of the function's op count:
  a budget in the program's units that leaves a function less canonical
  and never fails (AGENTS.md's "may stop at a budget"), with
  `test-convergence=true` in the tests still reporting the cycle?
- **NQ3. Output's canonical direction.** Canon fuses (`put_str(show_sint
  x)` to `put_sint x`, `Output.cpp:107-133`); §5.8 O5 composes (a pure
  `show` and one write, fused at lowering). Which is the canonical form?
- **NQ4. Which dialects' canonicalizations.** The canonicalizer collects
  every loaded dialect's and every registered op's patterns; the pin's
  `filter-dialects` can name them. Name them (idr, arith, ub, and those
  each pipeline point needs)?
- **NQ5. Canonicalization's place.** Keep it a pass at four pipeline
  points and in idr-optimize's inner pipeline, on upstream's greedy
  driver (T3, T4), or move to MLton's shape: one per-function normalizer
  each pass calls on what it rewrote, on the walk driver, with the
  greedy driver kept only for upstream's folds and patterns (§5.9
  Design 5)?

## 7. Deletion list

By file and symbol; each goes in the change that makes it dead (§5).

- `include/idr/IR/Fold.h`: `strUnary`, `strBinary`, `bigUnary`,
  `bigBinary` (T1); `Scope` stays, used by the one generic fold, the
  guards and the lowering's static bytes.
- `lib/IR/Fold/Strings.cpp`: the `fold` bodies of `StrAppendOp`,
  `StrConsOp`, `StrFromCharOp`, `StrShowSIntOp`, `StrShowUIntOp`,
  `StrShowDoubleOp`, `StrSubstrOp`, `StrReverseOp`, `StrTailOp`,
  `StrLengthOp`, `StrBytesLengthOp`, `StrScalarAtOp`, `StrDropBytesOp`,
  `StrScalarBytesOp`, `StrIndexOp`, `StrCmpOp`, `StrToIntOp`,
  `StrToDoubleOp`, `DoubleHeadOp`, `IntHeadSOp`, `IntHeadUOp`;
  `strAtOffset`; `StrHeadOp::fold` keeps only its cons case (T1).
- `lib/IR/Fold/Bigs.cpp`: the `fold` bodies of `BigSubOp`, `BigMulOp`,
  `BigAndOp`, `BigOrOp`, `BigXorOp`, `BigDivOp`, `BigModOp`, `BigNegOp`,
  `NatFromBigOp`, `BigCmpOp`, `BigFromSIntOp`, `BigFromUIntOp`,
  `BigFromDoubleOp`, `BigToDoubleOp`, `BigShowOp`, `BigFromStrOp`; the
  constant half of `BigAddOp`, `BigShlOp`, `BigShrOp`, `BigPredOp`,
  `BigToIntOp` (their identities and policies stay); `BigToIntOp`'s
  guardless walk (T1, T6).
- `lib/IR/Fold/Values.cpp`: `listElements`' role `switch` (T9, with lane
  01's typed body).
- `lib/IR/Fold/Scope.cpp`: the `StringAttr` in `Scope::big` (T1).
- `lib/IR/OpsCon.cpp`, `lib/IR/OpsClosures.cpp`: the three
  constant-folding loops (T1's `Idr_FoldsToConstant`); under NQ1's second
  option `ClosureOp::fold`, `SuspendOp::fold`, `ForceOp::fold`,
  `ForceOfOneUse`, `ForceInOneCase`, `ForceOp::getCanonicalizationPatterns`
  (T8).
- `lib/IR/Canon/Feeds.cpp`: `feeds`' ladder, `foldsWith` for ops of ours,
  `closedWith`, `someYield`, `yieldsFeeding`, `reader` (T2, T4, T6).
- `lib/IR/Canon/Callees.cpp`: the file (T5; `retryBetween` moves into
  canon's one match canonicalization).
- `lib/IR/Canon/Merge.cpp`, `MatchPatterns.cpp`, `CaseOfCase.cpp`,
  `Sink.cpp`, `Force.cpp` (`StaticCase`): `MergeIdenticalRegions`,
  `EndAfterNoYield`, `YieldFields`, `SinkConsumer`, `SinkIntoRegions`,
  `StaticCase` as separate patterns; `populate(..., StringRef root)`;
  `firstRepeated`'s per-visit map; `usersIn`, `movesInto`'s region count,
  `nearestSinkable`'s re-scan (T4); `YieldFields`' stage read (T7);
  `Sink.cpp:114`'s ladder (T8 and the trait).
- `lib/IR/Canon/MatchPatterns.cpp`: `DropEmptyStringCase`, and
  `knownNonEmpty` in `lib/IR/Crashes.cpp`, once non-emptiness is in the
  type (C24, owner Q-O3).
- `lib/IR/Canon/MoveOut.cpp`: its `Does`, `doesOf`, `usesWorld` (lane 02's
  one classifier); possibly `MoveOut<ArrayGetOp>` (C30, to be checked).
- `lib/IR/Canon/Output.cpp`: the five `unasked` stubs, `unasked` itself,
  `HeadOfBuilder`'s cons path (T9).
- `lib/IR/Canon/Eta.cpp` `knownFromMatch`, `lib/IR/OpsConReads.cpp`
  `FieldOp::canonicalize`'s walk, `OpsMatch.cpp` `takenFromEnclosing`:
  two of the three walks (T6), all three under QL2.
- `include/idr/IR/Canon.h`: the stale comments (C01) and the
  canon-internal declarations (C58).
- `lib/Transforms/Optimize/Optimize.cpp:64-66`: the second canonicalizer
  configuration (T3).
- `lib/IR/Canon/Captures.cpp`: `buildable` moves to the constant's
  definition (C04, lanes 01/03).

## 8. Risks, unknowns, measurements needed

**Risks.**
- *T4 changes the order in which rewrites meet.* Today the order among
  the six match patterns is the driver's (benefit 1 each, then the order
  added), and the canon tests pin results that depend on it ("whichever
  the driver reaches first", `OpsClosures.cpp:33-38`; c179ab2d). T4
  writes one order down; a fixture whose result rested on the old order
  shows it, and the right response is to make the pair confluent, not to
  copy the order.
- *T3's budget is deterministic only if the driver's order is.* The
  greedy driver is deterministic per function on one thread; the bound
  counts rewrites, never time or bytes (§5.11 C7). It must be large
  enough that no program the tests compile reaches it (measure the
  largest rewrite count per op on the stage-1 module first).
- *T1 must match every folder bit for bit.* Sign and zero extension,
  wrapping, the `Order` comparison and the guard are the places a generic
  fold can differ from today's hand bodies; `folds-balanced` and the
  canon and fold fixtures are the check, and the ABI table's rows are
  already the lowering's, so a mismatch is a bug in one of two readers of
  one row.
- *Lane 02's effect redesign can switch off known-case inlining.*
  `InlineRegionBranchOp` refuses an op without
  `HasRecursiveMemoryEffects` (C50); explicit effects on matches need an
  upstream change of that precondition or the trait kept.
- *Design 2 (Q-O1) or Design 5 (NQ5) rewrites T4.* T4 is written for the
  structured match and the greedy driver; either owner answer changes its
  shape, so T4 waits for both.

**Unknowns.**
- Whether `MoveOut<ArrayGetOp>` is redundant (C30): replacing the read
  requeues its users, but the read can change without being replaced (an
  op between it and the write moves away); `tests/canon-array-moves` is
  the check.
- Which pipeline points need which dialects' canonicalizations (NQ4):
  read off the ops present at each point.
- How many of upstream's arith folders the `meets` external model can
  declare without the probe (T2).

**Measurements needed** (none can run here: no built compiler; each on
the stage-1 module with a release `idris-mlir`, owner's Q4):
- Visits per match and time per visit in canonicalize, by pipeline point
  and inside idr-optimize (an action per pattern application already
  exists for the tagged transforms, `Support/Actions.h`;
  `--profile-actions-to`).
- The largest match's N at each canonicalize point, and the share of
  canonicalize's time in the six match patterns against upstream's four
  region patterns (§3.2).
- Rewrites per function per canonicalize run, max over functions, to set
  T3's multiple.
- The number of `foldsWith` clones per run (T2's saving).
- The number of canonicalize runs that change nothing, and the verifier
  time they cost (C62).
- `StringAttr`s created by `Scope::big` per run (C41).
- Commands for this document's counts are in §2.2, §4's footnote and
  §9.

## 9. Sources read

**Documents, in full**: `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0000-mlir-native.md` (all 11,141 lines, in
chunks: §0-§4, every lane of §5, §6-§9); `proposals/0003-facts-once.md`;
`audits/p0/README.md`; the heads of `audits/p0/01-ods-types.md`,
`02-ods-effects.md`, `03-ods-ops.md` (grep for overlap).

**This lane's files, line by line**: `foreign/idr/include/idr/IR/Canon.h`,
`Fold.h`; `foreign/idr/lib/IR/Canon/{Callees,Captures,CaseOfCase,Eta,Feeds,Force,MatchPatterns,Merge,MoveOut,Output,PutList,Rebuild,Sink}.cpp`;
`foreign/idr/lib/IR/Fold/{Bigs,Scope,Strings,Values}.cpp`;
`foreign/idr/lib/Transforms/Identity/Identity.cpp`.

**Fold hooks and canonicalization hooks elsewhere** (read at the cited
lines): `lib/IR/OpsScalars.cpp:1-109`, `OpsChecks.cpp:1-140`,
`OpsClosures.cpp:1-200`, `OpsConReads.cpp:1-200`, `OpsCon.cpp:90-130`,
`Constants.cpp:130-175`, `OpsArrays.cpp:140-150, 240-300`,
`OpsGenerating.cpp:115-140`, `OpsPlatform.cpp:1-60`, `Ops.cpp:225-320`,
`OpsMatch.cpp:175-260`, `OpsStrings.cpp:30-50`, `OpsTabulate.cpp:240-280`,
`Dialect.cpp:30-70`; `include/idr/IR/IdrScalarOps.td:1-140`,
`IdrMatchOps.td:1-60`, `IdrBase.td:40-60, 280-300`,
`IdrInterfaces.td:147-210, 274-340`; `include/idr/IR/Flow.h:75-110`;
`lib/IR/Grades.cpp:170-200`; `lib/IR/Symbols.cpp:30-60`;
`lib/IR/Crashes.cpp:1-45`; `lib/Transforms/Expect/Folds.cpp`;
`tools/idris-mlir-tblgen.cpp:725-790, 2945-3000`.

**The rest of the rewrite layer** (read at the cited lines):
`lib/Transforms/Pipeline.cpp` (whole);
`lib/Transforms/Optimize/Optimize.cpp:1-120`;
`include/idr/Transforms/InnerPasses.td` (whole);
`lib/Transforms/Narrow/Narrow.cpp:70-160`, `Copy.cpp:90-140`;
`lib/Transforms/Defunctionalize/Pass.cpp:55-70`;
`lib/Transforms/Effects/Constants.cpp:60-175`;
`lib/Transforms/Tail/WhileDo.cpp:290-305`;
`include/idr/Conversion/IdrPattern.h`; the pattern lists of
`lib/Conversion/*.cpp` (grep); `tools/idris-mlir-reduce.cpp` (through
7987388b's diff).

**Commits** (`git log --oneline -- <this lane's paths>`, 16 commits;
`git show` of): 3a96c407, 7987388b, c179ab2d, 1b2e31da; the old
`Callees.cpp` at d06ed15c and 2c042728.

**Upstream reports**: `upstream/62-greedy-multi-region-ancestors/README.md`
(whole), `upstream/17-sccp-revert-unset-property/README.md` (head; it
cites `foldsWith` at `foreign/idr/lib/Canon/Feeds.cppm`, a path gone since
the dialect moved to `lib/IR/Canon/Feeds.cpp`: lane 20's).

**Pinned tree** (`.toolchain/llvm-project/mlir` at 7208ba24):
`lib/Transforms/Canonicalizer.cpp` (whole);
`include/mlir/Transforms/Passes.td:25-60`;
`include/mlir/Transforms/GreedyPatternRewriteDriver.h:120-200`;
`lib/Transforms/Utils/GreedyPatternRewriteDriver.cpp` (grep of the
worklist loop, `:463-466, 486-629, 641, 843-930`);
`include/mlir/Transforms/WalkPatternRewriteDriver.h`;
`include/mlir/Interfaces/ControlFlowInterfaces.h:320-385`;
`lib/Interfaces/ControlFlowInterfaces.cpp:718, 855-880, 1006, 1200-1240,
1310-1330`; `lib/Interfaces/SideEffectInterfaces.cpp:35-37`;
`lib/Transforms/CSE.cpp:51-56`; `lib/Dialect/SCF/IR/SCF.cpp` (grep).

**Tests** (listing and heads): `tests/canon-*` (24 directories);
`canon-force-of-choice`, `canon-evaluated-suspension`,
`canon-force-of-own-constant`, `canon-shared-action`,
`canon-sink-probe-fold`, `canon-upstream-passes`.

**Commands for the counts** (all from `foreign/idr/` unless marked):
- `wc -l lib/IR/Canon/* lib/IR/Fold/* include/idr/IR/Canon.h include/idr/IR/Fold.h lib/Transforms/Identity/*` (2,830).
- `grep -rn MatchAnyOpTypeTag lib include tools unittests` (none).
- `grep -rc matchAndRewrite lib include tools unittests | grep -v ':0'`.
- `grep -h "hasFolder = 1" include/idr/IR/*.td | wc -l` (48);
  `grep -rn "hasCanonicalizer\b\|hasCanonicalizeMethod" include` (9, 1).
- `grep -c '^OpFoldResult [A-Za-z]*Op::fold' lib/IR/Fold/Strings.cpp lib/IR/Fold/Bigs.cpp` (24, 23);
  `grep -rn "::fold(" lib include` for the rest.
- `grep -rn "Pat<\|\.pdll" include lib` and `find . -name '*.pdll'` (none).
- `grep -rn "Commutative\|Idempotent\|Involution" include lib` (none).
- `grep -rn "canon::" lib include tools unittests | grep -v '^lib/IR/Canon/'` (readers, C58).
- `grep -rn -E "applyPatternsGreedily|applyOpPatternsGreedily|GreedyRewriteConfig|walkAndApplyPatterns|applyPartialConversion|applyFullConversion|createCanonicalizerPass|OperationFolder|eliminateTriviallyDeadOps" lib include tools unittests` (drivers, §2.2).
- `grep -n -E "isa<|isa_and_nonnull<|isa_and_present<|IsaPred<|hasTrait<"` over this lane's files (35 lines).
