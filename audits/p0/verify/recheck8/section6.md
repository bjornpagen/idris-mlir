<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 8: §6 (what goes) against HEAD

HEAD at start b8a6177f7, at finish 0c05843ef (a queue-only commit).
Everything here is by reading and `git grep … HEAD` over the committed
tree. Nothing was built, generated or run. The checkout's uncommitted
edits (K16's checker, the running lanes) were not counted.

Search: `git grep -n [-w] <symbol> HEAD`, leaving out `audits/`,
`proposals/`, `sources/`, `third_party/`, `.claude/`, `bench/records/`
and `AGENTS.md` (script: `/tmp/r8/scripts/g.sh`). A symbol is GONE when
no definition or use of it is left in code, tests' expected behaviour,
generated files, CMake, the specification or current documentation
(C251). §6's own items and the lane lists it points at (each lane
document's deletion section) were both checked; recheck 6's symbol lists
were rerun whole. Owners from `ownership.json`. Running lanes from the
queue's last two sections.

## Counts

| | §6's parts (110) | recheck 6's rows (106: §6 and the lane lists) |
|---|---|---|
| GONE | 107 | 101 (N9 and R1 newly) |
| REMAINS | 1: `Finite.heightWithin` and kin (N7) | 4: N5, N6, N7, N10 |
| HISTORY | 1: patches 06, 28, 63 (reports kept as submissions) | |
| SUPERSEDED | 1: the element take's test (C250, S1) | 1: S1 |

§6's parts are its comma- and semicolon-separated items by area
(effects 1, types and ops 20, analyses 11, counting 14, control flow 10,
lowering and runtime 11, simplification 4, frontend bugs 4, arrays 12,
Idris side and fork 15, process 8). Since recheck 6: N9 (Contracts'
length guard and hand `Relation` table) is gone by ae3827e27 (L19ab:
records compared whatever their length, relations printed from
`ExpectProperties.inc`, `Contracts.cpp:64-87`); R1 (five prose
`expected-error`s) by d38f6bd49 (L19aa: each of the 95 `expected-error`
lines in `tests/` is `{{}}` or a property prefix, `{{expected <p>` or
`{{contract <r>`, measured). No regression.

## REMAINS

### L16 (`compiler/src`)

- **N7, §6 "Finite.heightWithin and kin" (L16 §2.6).** In flight: C281
  steps 2-6 delete it (L16et).
  - `Frontend/Finite.idr:171-172` (`unsound`, an `internal`),
    `:180-188` (`heightWithin`), `:190-216` (`sizedWithin` and its calls).
  - `Translate/Types.idr:604-609` (`boundsHold`), its use at `:959-960`.
  - `Translate/State.idr:2059` (`TS.bounds`), `:2063` (`TS.sizes`).
  - `Proof/Requests.idr:733-735` (`lteThrough`), `:745` (`climb`),
    `:759-763` (`fitsWithin`), `:1009` (`within`).
  - Recipe: the fold reads each request at its annotated node, and with
    the lemma over the model's walk these and the translation's own
    request computation go (C281 as amended, `handoffs/L16-fold-design.md`).
- **N10, the array externs' hand table (L12 §2.7, I12; C284's frontend
  half).** Not being deleted: L16ev holds `Registry/{Entry,Recognized}`
  and `Resolve` for R-META only. The specification half is done
  (`Spec/Arrays/Declarations.idr:343`, `ArrayMeaning`, 239094524).
  - `Registry/Entry.idr:210-239` (`ArrayPrim`, `generatedOperands`);
    readers `Registry/Faster.idr:69, 97`, `Registry/Recognized.idr:73, 115`,
    `Frontend/Resolve.idr:468, 568-571`.
  - `Translate/Terms.idr:2355-2690` (`arrayTerm`'s hand case: `AReshape`,
    `AMerge`, `AConcat`, `APad`, …), called at `:2712`.
  - Recipe: `Generating : ArrayMeaning -> Hook kd`, one walk over
    `Composed`; delete `ArrayPrim`, `generatedOperands` and `arrayTerm`
    with their readers; Emit writes `tensor.concat`/`tensor.pad` for
    words (today `Emit/Tensors.idr:361-380` joins words slice by slice);
    add the word-array program test. After L16ev (cull fold-in W03, fe 11).
- **N5, `Cases.instanceOf` (L16 §2.6, T2).** Not being deleted.
  - `Translate/Cases.idr:588-605`: the family from the Core type through
    `lookupFact (.dataFamilies)`, else `normaliseClosed` of the binder's
    Idris type at each match and `dataOf`.
  - Recipe: read the match's family once from the case tree's `scTy`
    (scoped since d093dbfb) and `TyConFacts.constructors` at the
    boundary; the registry's `HookShape` refusals read the same type. The
    file is free; C281's fold rewrites `Cases`' signatures, so land it
    with or after the fold.
- **N6's frontend half, `rootOf`'s climb (L16 §2.6, T6).** Not being
  deleted.
  - `Translate/Closed.idr:567-589` (`rootOf` climbs `Nested` by
    placement), `Translate/Boundary.idr:183` (`parentOf`'s `Nested` arm).
  - Recipe: after the checker half, `rootOf` reads the typed parent and
    the climb and the arm go.

### L17 (`compiler/checker`; K16 holds it)

- **N6's checker half.** `Core/Name.idr:43`: `Nested : (Int, Int) -> Name
  -> Name`, a session-local entry written to TTCs. D133 step 3 makes the
  entry a `Nat` but keeps it session-local (`handoffs/D133-design.md`
  O-4: "not this design's to fix"), so no running lane deletes it.
  - Recipe: a nested function's parent is a typed `Name` written to the
    TTC, as `CaseBlock (parent : Name)` (`:49-50`) already is. After K16
    and with or after D133 step 3.

## HISTORY (C251)

- Patches 06, 28 and 63 (§6 Process): `upstream/{06,28,63}-*/` hold a
  README, a `pull-request.diff` and reproducers, no `.patch`; reports
  kept as submissions (C35, upstream/README.md).
- `compiler/checker/README.md:81-113`: `mkRunTime`, `compileRunTime`,
  `PartialEval`, `partialEvalNS`, `processTTImpFile`, `delayDepth`
  (`:100`), `isWindows`, `Volume`, `dirSeparator`, `pathSeparator`,
  `pathLookup`: the account of the deletions.
- `upstream/*`: `nextIdxByScore` (105, 110), `delayDepth` (109's patch),
  `defunc-tag-limit` (63's README), `SymbolUserMap` (88),
  `remove-dead-values` (01, 06, 28, 63), `GreedyRewriteConfig` and
  `getCanonicalizationPatterns` (62's and 65's patches: upstream's code).
- Planted witnesses: `tests/no-fuel/witness/` (`GreedyRewriteConfig`),
  `tests/dialect-text/witness/` (`--canonicalize`),
  `tests/harness-cases/run:53` (`old/expected-crash`).
- `tests/upstream-dead-code-nested-symbol-use/run:11` runs upstream's
  `--remove-dead-values` to check patch 29; `PINS.md:38` names it as a
  site only if the qualification brings it back (C35).
- `tests/system-info/Main.idr:12`: a user program calling base's
  `isWindows`, not the checker's path model.
- `bench/records/*` (`ulimit -s`); AGENTS.md's "Never:" lines.

## GONE (0 hits outside history, unless noted)

- **Effects.** L02 §1.4's table: `bodyEffect`, `componentEffects`,
  `writeEffects`, `effectsCovered`, `appendEffect`, `effectInstances`,
  `solveEffects`, `observableRuns`, `LabelsRun`, `doesOf`, `usesWorld`,
  `onlyAllocates`, `performsIO`, `mayRunAt`, `anyEffect`, `Idr_Effect`,
  `Effect::none`, `bitEnumContains`, `IOResource`, `setEffects(`;
  `lib/Analysis/Effects.cpp`. The one `effects<` is the row's own spelling
  in a verifier message (`lib/IR/Func/Rows.cpp:182`).
- **Types and ops.** The grade's free enums and functions (`QType`,
  `Lifetime::Heap`, `fitsIn`, `holdsOwn`, `mayBeFrame`, `!idr.lin`,
  `!idr.own`, `!idr.qtype`); the kind and role table (`namespace role`,
  `emptyRole`, `TableCtor`, `TableMember`, `DataDefinition`, `isBoxed`);
  `ValueFacts`' hand answers (printed from the specification,
  `lib/IR/ValueFacts.cpp:3-12`); marker traits no reader needs; the hand
  `def`s (every `.td` of ours is under `IR/Generated/`, the rest are test
  witnesses); `own.adopt`/`own.give`'s def-use verifiers; the 38 hand
  folders (`ToIntOp` 0); `#idr.types`, `MutableType`, `DataRemap`,
  `Declarations` (the hits are other things), `DataBody.cpp`, `Fit.cpp`,
  `!idr.box`, `Idr_SumKind`, `Idr_CtorRole`; the `tag` attributes;
  `LifetimeVar`, `lifetimeVars`; today's grade and every spelling,
  `!idr.view<`, `view.make`, `idr.view`, `frame_lifetime`, `idr.share`.
- **Analyses.** `CallCycles`, `Scc.h`, `Scc.cpp`, `stronglyConnected`,
  `MonotoneWorklist`, `FiniteLattice`, `ReadySet`, `ReturnedAnalysis`,
  `ReturnedArguments`, `KnownLattice`, `[[maybe_unused]]`; `Recursion` is
  only the frontend's `Translate.Recursion` (C292's, in flight) and the
  checker's parser comments; `SymbolUserMap` only in upstream 88; no map
  keyed by name text or IR pointer in `foreign/idr` but
  `Conversion/StaticData.h:220`'s `StringMap` of static texts by content.
- **Counting.** `Classes`, `Reuses`, `TakenField`, `Positions.cpp`,
  `ownsReference`, `endsInCrash`, `rebindDefaults`, `takeReadSums`,
  `takeReadBoxes`, `rewriteSelects`, `sinkConsumers`, `Fields.h`,
  `Fields.cpp`, `IdrDemand`, `Demand.cpp`, `unknownFrom`,
  `givesExclusive`, `copyable`, `HoldingState`, `Sharing::Unknown`,
  `madeStatic`, `isStatic`, `Phantom`, `isCountedElement`,
  `idr-rc-stack`, `loopsInFrame`, `IDRIS_RT_STACK_CELL`, `Take.cpp`,
  `Owned*.cpp`, `lib/Analysis/Ownership/Uses.cpp` (the `Uses.cpp` left is
  `lib/IR/Verify/Uses.cpp`, structural positions). `DataFlowSolver` is
  used by Ranges and Narrow alone.
- **Control flow and tail calls.** `Contify`'s single-site rule,
  `Tail/Loop.cpp`, `Tail/WhileDo.cpp`, `WhileDo`, case-of-case's copy,
  `Eta.cpp`, `runningRegions`, the poison yields (none in
  `Conversion/Matches.cpp`), `!idr.cont`; `TailPosition.*`,
  `TailCallPlan.*`, `numFrameBound`, `endsTail`,
  `inTailPositionModuloContext`, `forTails`, `reachesTailCall`,
  `passesOnPrevious`, `tailMatch`, `inTailPosition`, `wayOf`,
  `repackedTailOf`; the cycle rule once (`Solver/Components.h`);
  `Frame.cpp`, `FramesPlan`, `FramesMade`, `memberCalled`,
  `closureLabels`, `madeInRest`, `caseCallee`, `stackTypeOf`,
  `answerTypeOf`, `fromAnswer`, `asAnswer`. (C294, in flight, replaces
  the `tail_kind` enum and `decideTails` beside it.)
- **Lowering and runtime.** Uniqueness branches (`LowerTake` takes only a
  value its type claims, `Lower/Counting.cpp:84-101`), `Fields`,
  per-site crash strings (`idris_rt_crash_str`), typed words instead of
  NULL and odd-bit tests (`runtime/Rc/Rc.h:35-70`), `LowerDrop` with no
  token branch (`Lower/Counting.cpp:73-82`), `RootKind::Status`, no
  `idris-mlir:` prefix, `heapRegion`, `MAP_NORESERVE`, the live-cell
  counter (`liveCells`, `idris_rt_live_cells`, `countFoldLeak`,
  `IDRIS_RT_LIVE`; `runtime/check-archive.sh` refuses one), the stack bit
  and its tests (none in `runtime/`), `stackSize`, `guardSize`,
  `alternateSize`, "stack exhausted".
- **Simplification.** `applyPatternsGreedily`,
  `applyOpPatternsGreedily`, `createCanonicalizerPass`, `createCSEPass`,
  `getCanonicalizationPatterns`, `hasCanonicalizer`, `Canon/`; no
  `canonicalize` or `cse` in `foreign/idr` or `compiler/spec` but prose.
- **Frontend representation bugs.** A `Nat` literal is one constant;
  a case binds its refined scrutinee; `array.read` gives back `$after`;
  `WithBounds` is a sum (`checker/src/Libraries/Text/Bounded.idr:76-78`).
- **Arrays.** `Nests.cpp`, `lowerOrdered`, `cloneRegion`, `emptyOf`,
  `structurable`, `GeneratingOpInterface`, `Idr_Iteration`,
  `getIterations`, `getExtentBound`, `reifyTabulated`,
  `reifyDimOfResult`, `boundTabulated`, `TabulateIOOp`,
  `TransposeColumns`, `ElementUpdateOp`, `StoreModel`, `HeapReadModel`,
  `MemoRunModel`, `MatchModel`, `EnterModel`, `UseModel`, `isLink`,
  `#idr.world`; `merge`'s identity entry. `TransposeOp` is upstream's
  `linalg.transpose`, admitted; `heldType` is two homonyms (the growth
  model's field, a tblgen helper).
- **Idris side.** `Forced.idr`, `erasedArgs`, `quantitiesOf`,
  `lastRuntime`, `elaboratedFile`, `mostUses`, `holdFor`, `quantityText`,
  `idr.refusals`, `Types.signed`, `Newtype`, `Facts.terminating`,
  `floatLiteral`, `DataShape`, `Profile.imports`; erasure from one source;
  `delayedLets` moves only the elaborator's `Delay`
  (`Translate/Closed.idr:282-285`); `Syntax/Idr.idr` gone. `Resolve.homeOf`
  survives as a reader of the search's record (`Resolve.idr:75-78`), not
  the deleted name-based guess. Fork: `ambigLimit` and the ambiguity
  depth family, `autoImplicitLimit`, `AutoImplicitDepth`, the timer
  (`startTimer` … `KwSearchTimeOut`), `foreignImpl` family,
  `caseTreeHeuristics`, `debugElabCheck`, `processTTImpFile`,
  `mkRunTime`, `compileRunTime`, `toCompileCase`, `canInlineCaseBlock`,
  `canInlineDef`, `PartialEval.idr`, `refersToRuntimeM`, `calcRefs`'s
  `Bool`, the path model's Windows forms.
- **Process.** The pipeline order once (`lib/Transforms/Pipeline.cpp`
  reads the specification's list); RUN lines name tool options only
  (`--idr-expect` 27, `--idr-pipeline` 7, `--idr-contracts` 6,
  `idr-pipeline` 43 in pipeline strings); `createRemoveDeadValues`;
  `bench/run.sh`'s `ulimit -s`; "1 MiB"; `tests/defunc-tag-limit`;
  `LLVM_ENABLE_ASSERTIONS=ON` (`tools/bootstrap.sh:926`), `NDEBUG`
  stripped for our units (`foreign/idr/CMakeLists.txt:21-45`), kept in
  the runtime's own profile as D115 says.

## 3. Missing from §6 (for the coordinator)

Deletions later decisions or the cull imply that §6 does not name.
Status at 0c05843ef.

### Deleted, gone (record as done)

- D132: idr-constants, `SummarizedConstantPropagation`, its summaries and
  hand folds (177aefcca; `idr-constants` 0).
- C285: `GuardOpInterface`'s `decide` method and the ops' `holds`
  (d378e120e; the interface keeps `getGuarded` and `getCause`).
- C286: `givenClaim`(s), placement's `forgetClaims`, `flowsLinearly`,
  `readsPart`, Emit's `plain` (f392a02e4).
- C279: the driver's own `addPass`, `moduleKindOf`'s second target check,
  `--idr-target` in tests (2d7ee52d).
- C271: the checker's `addTransform` and stored transforms (fc306c2c).
- C233: `compiler/idris`, `tools/extract-idris.sh`, `upstream/fork-*`
  (0a40aec1e). C229: `tools/check-units.py`. C246: `harness/lib/*.sh`
  but `harness.sh`, `tests/runtime-effects/*.awk` (f19fb4503).
  C131/C132/C134/C135: `run.sh`, `e2e.sh`, `differential.sh`,
  `actions.sh`, `lit.sh`, `profile.sh`, `Sem.maxCases`,
  `tests/actions-skip-programs`.
- C253 `!idr.token`; C239 `extentDim`; C235/D126 `Match.h`'s type fold,
  `DialectTypes`, `foldDialect`'s chain; C192 `ownAdoptOp`; C219
  `holdingOf`; C204 `index_switch` in the frontend; C165 patch 78; C144
  the undecided hold; C127/C296 `QuoteTooDeep` and its seven arms.
- C299 (U04, 675fd966d): the unreportable ending; C300 (U07 a8d860583,
  K15 08c59751e): `idr-lower-statics`, `idr-lower-runtime`.
- Cull K01-K09 and K15 (316b10a6e … e52203f62, 08c59751e): `tests/{file-size,
  build-preset, commands, bench-records, determinism-threads-rbtree,
  configure-gate, pin-sites}`, `bench/regex-dna`, `harness/templates`,
  `--trace-totals`/`--trace-units`, eleven `tests/upstream-*`;
  `tools/{upstream-idris, compile-times.sh, bisect.sh, lanes}`; ten Idris
  reports, patches 76 and 97, PIN markers, the licence machinery;
  `RuleScope`, `VerifyOrder`, `Struct`, `CustomParams`,
  `Declarations.tables`, `PassKind`, `SetOf`, `Typed`, four laws,
  `PowerOfTwo` (the spec field; the `…ByPowerOfTwo` meanings stay),
  `RootedAtUpstream`, `PerClass`, `AnyBlocks`, `OnAttribute`,
  `TakesBool`; the runtime's `inc_run_*`/`dec_run_*`, three cell kinds,
  `idris_rt_flush`; `hmap`, `cata`, `contentHash`, `contentName`,
  `--check`; `GatedCsr`, `layOutGuarded`, `SummarizeImpl`,
  `FunctionNames`, `Analysis/Inline.h`; `GraphNumbering`,
  `FunctionNumbering`, `Expect/CrashSites.cpp`, `@rejoins`; 87
  ownership paths. All 0.
- Rederivation U01-U14: `OpIndex.h.inc` and its generator, integer
  attributes' text fallbacks (U11); the schedule library parsed from text
  (U14); runtime calls told by name (U13); endings compared as text (U12);
  decimal bigs in the fold (U06); a static's global found by digest (U07);
  Narrow's per-function re-solve (U01); TRMC's second admission test
  (U10).

### Remaining references to deleted parts (stale, C251)

- `foreign/idr/include/idr/Conversion/Runtime.h:43-45` (L21): "a Bool
  parameter or result is zeroext", since K04 deleted the `Bool` operand
  kind (rt 8). Not being deleted. Recipe: say what the code does (a byte
  parameter and a truth result are zero-extended).
- `tests/harness-cases/run:4`, `tests/harness-near/run:4`,
  `tests/semantics/run:9` (L19): cite `lib/e2e.sh`, deleted by C246;
  `sem_case` and `near_neighbour` are now `harness/Programs.idr:278, 336`,
  and `e2e_cases` exists nowhere. Not being deleted. Recipe: cite the
  Programs.idr functions.
- `proposals/0000-mlir-native.md:6349` (coordinator): §5.5's "counts over
  runs of slots", run entries K07 deleted; the cull plan (§3, rt 3) says
  the coordinator strikes it. `:6325` names `idr.lifetime.reserve` (K11).

### In flight (record when each lands)

- C281 steps 2-6 (L16et): the translation's own request computation,
  `Undrawn` (`State.idr:1888`), with §6's "kin" above.
- C292 (L16, after L16ey): `Translate/Recursion.idr`'s `loopsOf` and its
  readers; the `cycle-divergence-kept` contract (cull's verifiers note).
- C293 (L18ac): C275's one reindex classifier.
- C294 (L10aa): the `tail_kind` enum, every pass's writing of it,
  `optimize::decideTails` (`Optimize/Tails.h:34`), `StageTails`/`tailsAt`.
- C302 (L14ad): the e-graph's choice by whether it holds the optimizer's
  callee table.
- D133 steps 3-8 (L17bh): `Idris/Host.idr:95-96` (`trusted`, the six
  applications at `:901, 2781, 2792, 2866, 2917`), `host = assert_total`
  (`:2983`), `Reduct`, `Irreducible`, `reachesNormalForm`,
  `probesUnresolved`, the small-step relation, `computedWithin`,
  `Proof/Markers`, the frontend's own head reduction, the four escape
  hatches (`Boundary.solutionAt`, `State.solutionIn`, two in
  `Growth/Template`).
- C297 (K22, after K16): `showError` and its duplicate arms
  (`checker/src/Core/Core.idr`, 97 hits).
- K10 (`idr.io.unsafe_run`, `WordOfBigOpInterface`, the show-head ops and
  runtime functions, `maxUI`'s admission), K11 (`idr.lifetime.reserve`,
  `OpensLifetimeOpInterface`, `Verify/Program.cpp`'s target and globals
  checks), K12 (`idr.lazy.delay`, six hook declarations, `isCellValue`,
  `tensor.splat`'s model), K13 (`#idr.given_back` and what keeps it in
  step), K14 (Idris copies of C++-only types, builtin encoders, unread
  traversals and enum helpers), K16 (checker chk 1-6, 8-14), K17-K22
  (`expect-table` into specgen, `--rules`; idr-deduplicate and contify's
  first run after M1/M2; the frame stack as a home lifetime after M3;
  patches 10, 104, 105 after M5/M6; D50's builders, QA).

### Open, no lane deleting them

- C295 (L12, L16): `Bufferize/Releases.cpp:226-236` writes `writable` on
  `to_tensor` where claims are raised; Emit casts a buffer field to the
  bare carrier before `to_tensor {restrict}` (`Emit/Bodies.idr:412-425`).
- C268 (L12, L16, L18): `tie_shape`'s `dims` tie every dynamic axis
  (`Spec/Arrays/Memory.idr:414-418`, `OpsArrayShapes.cpp:76-78`); Emit's
  `tie` reads an unstated axis off the array (`Emit/Tensors.idr:648-649`,
  `sizeAt` at `:116-118`).
- C228 (L16): `Emit/Tensors.idr:160-171` (`Mismatch`),
  `Emit/Monad.idr:55-74` (`Unfit`, `unfit`), `Emit.idr:65-76`
  (`EmitFailed`), `Frontend/Program.idr:83`; `Translate/Terms.idr:745`
  (`forcedType`) and `:1588` (`applied`), two `internal`s.
- C213/C217 (L16, rides C281's fold): the `RuntimeClosure` refusals of
  fixed sets, `Terms.idr:627, 720, 1142`, `Cases.idr:977`.
- N10's frontend half above (C284).
