# U11 — Narrowing as `IdrNarrow`: `idr-narrow` versions on the module and rewrites per function, `idr-narrow-lanes` runs per `func.func`

Mandatory findings: none

## Permitted outcome

1. **The library `IdrNarrow`.** `IDR/Transforms/Narrow/*.cpp` and
   `INC/Transforms/Narrow.h`, plain C++ in the layout of C1.1, with every
   unit of `IDR/Narrow` deleted. Mandatory.
2. **`idr-narrow` as a `ModuleOp` pass of two steps.** It versions every
   loop whose natural only descends, across the module, then runs the
   word rewrite on each `idr.func` through `runPipeline` on a nested
   manager, so that functions are rewritten in parallel and each is
   verified on its own (C1.3, C4). Mandatory.
3. **One range analysis per pass run.** The seeded integer range analysis
   of today's `Naturals.cppm` becomes `idr::narrow::Ranges`, an analysis
   under the pass manager computed on the module and read by the nested
   function passes through `getCachedParentAnalysis` (C2.0). It is
   solved once when no loop was versioned and twice when one was, where
   today it is always solved twice. Mandatory.
4. **`idr-narrow-lanes` as a `func::FuncOp` pass.** The versioning of a
   vectorized loop on 32-bit lanes runs per function after lowering, its
   trial copy still in a scratch module the pass invocation owns, its
   narrowing still upstream's `arith-int-range-narrowing` patterns.
   Mandatory.
5. **Every rewrite is a pattern.** The versioning, the joints, the ops and
   the lanes are `RewritePattern`s applied by `walkAndApplyPatterns`; the
   cleanup of conversions is the greedy driver; no pass walks to rewrite
   (C2.0). Mandatory.

Consumer adaptations: none outside the lane. `idr-in-bounds` (U12) and
`idr-expect` (U15) read declarations this lane supplies (Outputs); they
adapt in their own lanes.

## Owner / exclusive writes

- `INC/Analysis/Ranges.h` (new; given to this lane by the rulings: `contracts.md` is authoritative for its content)
- `IDR/Transforms/Narrow` (new): `NaturalRanges.cpp`, `Facts.cpp`,
  `Carried.cpp`, `Ops.cpp`, `Versions.cpp`, `Narrow.cpp`, `Widths.cpp`,
  `Copy.cpp`, `Lanes.cpp`.
- `INC/Transforms/Narrow.h` (new): the one header of the library.
- `IDR/Narrow` (deleted): `Narrow.cppm`, `Pass.cc`, `Words.cppm`,
  `Naturals.cppm`, `Facts.cppm`, `Ops.cppm`, `Carried.cppm`,
  `Versions.cppm`, `Lanes.cppm`, `Copy.cppm`, `Widths.cppm`,
  `Lanes/Pass.cc`. `IDR/Narrow/CMakeLists.txt` is the coordinator's and
  goes with the directory.

**Excluded:**

- `INC/Transforms/Passes.td` and `IDR/Transforms/Narrow/CMakeLists.txt`:
  the coordinator's. The anchor, statistics and dialect changes below are
  reported as hub text.
- `IDR/IR/Ranges.cpp`, `INC/IR/Ranges.h`, `IDR/IR/OpsBigs.cpp`: the
  dialect's range hooks and the `Bounds` arithmetic, U01's (today
  `IDR/Ranges/*` and `IDR/Dialect/Ops/Bigs.cc:20-135`).
- `INC/Transforms/Ownership.h`, `IDR/Transforms/Ownership`: U08's, where
  `inOwnedStage` and `isStatic` live (today
  `IDR/Ownership/InOwnedStage.cppm:16-29`, `IsStatic.cppm:14-21`).
- `IDR/Analysis`, `INC/Analysis`: no file there is this lane's.
- `IDR/Transforms/InBounds` (U12), `IDR/Transforms/Expect` (U15),
  `IDR/Transforms/Vectorize` (U16), `IDR/Transforms/Pipeline.cpp` (U14).
- Every test: U21 writes `T/idr/narrow` and `T/idr/vectorize`; U22
  writes `T/programs/nat` and `T/programs/arrays`.

## Read first

- `contracts.md` C0, C1.1, C1.3, C1.4, C2.0, C2.1, C4, C9.1, C9.2, C10.
- `findings.md` F-pass-1, F-pass-4, F-state-4 (the evidence this lane
  answers without owning a finding).
- `IDR/Narrow/Narrow.cppm:1-8` (what the library is), `Pass.cc:16-27`
  and `Lanes/Pass.cc:15-25` (the two passes' glue and statistics).
- `IDR/Narrow/Words.cppm:39-90`: the two solver runs (:45-47, :59-62),
  the versioning walk (:50-56), the joints-then-ops order (:63-77), the
  greedy fold of conversions (:80-82) and the dead-conversion walk
  (:85-88).
- `IDR/Narrow/Naturals.cppm:17-45` (`NaturalRanges`: the TypeID static at
  :20-23, the seeding at :26-33, poison at :39-44), `:48-53` (the solver
  with `DeadCodeAnalysis` and `SparseConstantPropagation`), `:59-64`
  (`rangeOf`, the one read of the lattice).
- `IDR/Narrow/Facts.cppm:19-111`: `isBig`, `ownedBig`, `Facts` (`of`
  with the natural's floor at :54-55, `word` at :71-92 with the poison
  at :73-79, `big` at :96-101, `converted` at :104).
- `IDR/Narrow/Ops.cppm:18-37` (flags and predicates), `:48-66`
  (`narrowMatch`), `:69-164` (`narrowOp`, every case).
- `IDR/Narrow/Carried.cppm:19-49` (the retyping and `passWord`, with the
  direct `setType` at :22 and :32), `:53-115` (`narrowCarried`).
- `IDR/Narrow/Versions.cppm:21-57` (`descends`), `:61-74`
  (`descendingArgument`, the borrowed refusal at :65-66), `:79-108`
  (`version`: the test at :85-90, the mask at :93-96, the clone at
  :101-103, the move at :105-107).
- `IDR/Narrow/Lanes.cppm:1-31` (why 32-bit lanes and how the bound is
  found), `:45-48` (the exponents), `:61-129` (`versionLanes`),
  `:136-151` (the pre-order walk for outermost vectorized loops).
- `IDR/Narrow/Copy.cppm:18-149`: the scratch module (:20), the stand-ins
  (:38-43), `analyse` (:55-65, upstream's stock range analysis, not
  interprocedural), `fits` (:72-87), `narrow` (:96-127: the listener,
  upstream's patterns at `{32}` at :107, the driver's configuration at
  :108-113, the `nneg` mark at :121-125), `cloneInto` (:131-140).
- `IDR/Narrow/Widths.cppm:18-87` (`isVectorized`, `inputsOf`, `testable`,
  `fits32`, `widthOf`, `computesWideLanes`).
- `IDR/Graph/Trips.cppm:14-26` (`runsAtMostOnce`, which moves into this
  lane), and its other reader `IDR/Expect/NarrowedLanes.cppm:66`.
- `IDR/InBounds/Prove.cppm:107,147` and `IDR/InBounds/System.cppm:136`:
  how `idr-in-bounds` reads the seeded solver today.
- `IDR/Expect/Words.cppm:22-49` (`word-loop`) and
  `IDR/Expect/NarrowedLanes.cppm` (`narrowed-lanes`): the properties
  the tests state.
- `IDR/Ranges/Bounds.cppm:16-49`, `BoundsOf.cppm:12-16`,
  `RangeOf.cppm:15-19`: the `Bounds` the lane consumes from U01.
- `IDR/Ownership/InOwnedStage.cppm:16-29`, `IsStatic.cppm:14-21`,
  `ReadFrom.cppm:13-22`; `IDR/Dialect/Grades/IsOwned.cc:9-12`,
  `Unrestricted.cc:8-11`.
- `INC/Passes.td:371-393` (`IdrNarrow`: dialects at :386, statistics at
  :387-391), `:643-672` (`IdrNarrowLanes`), `:743-749` (the
  `narrowed-lanes` property).
- `IDR/Dialect/Registration/PipelineSteps.cc:35-40, 48-51`: where the
  two passes sit and why.
- `PINS.md` `int-range-narrowing-exactness` (:437-464) and
  `upstream/09-int-range-narrowing-exactness/README.md`: the limit of
  upstream's narrowing and the carried patch.
- `bench/README.md:48-54` (what the 32-bit lanes bought), `:101-104`
  (the 15% spread), `:248-265` (spectral-norm-linear).
- The 2026-10-02 survey, `git show f2d6df36:findings/mlir-survey.md`,
  item 4 (:217-245, the two upstream passes) and item 9 (:353-378, why
  an `scf.while` counter never narrows).
- `sources/code/mlir/include/mlir/Analysis/DataFlow/IntegerRangeAnalysis.h`:
  the widening of loop-carried ranges (:28-45), the dependence on
  `DeadCodeAnalysis` (:66-67), the entry state (:73-77),
  `staticallyNonNegative` (:97-107).
- `sources/docs/mlir/docs/PassManagement.md` "Analysis Management"
  (:214-310: `isInvalidated`, `getCachedParentAnalysis`) and "Dynamic
  Pass Pipelines" (:459-495: `runPipeline`, and that a dynamic pipeline
  is integrated with analyses and instrumentation).
- `sources/docs/mlir/docs/PatternRewriter.md` "Walk Pattern Rewrite
  Driver" (:320-345): no revisits, erasure only of the matched op and
  its descendants, every change through the rewriter.
- The pinned `mlir/include/mlir/Pass/Pass.h` (`runPipeline`,
  `getCachedParentAnalysis`, `PassWrapper`),
  `mlir/include/mlir/Pass/AnalysisManager.h` (`PreservedAnalyses`,
  `AnalysisManager::invalidate`),
  `mlir/include/mlir/Transforms/WalkPatternRewriteDriver.h`,
  `mlir/include/mlir/Interfaces/ValueBoundsOpInterface.h`
  (`computeConstantBound`). Recalled, not read at 25890d32 (the pinned
  tree is not checked out on the authoring machine):
  `mlir/include/mlir/Dialect/Arith/Transforms/Passes.td`, where
  `arith-int-range-narrowing` takes `int-bitwidths-supported` and
  `arith-unsigned-when-equivalent` takes nothing, and `Passes.h`, where
  `populateIntRangeNarrowingPatterns(RewritePatternSet &, DataFlowSolver &, ArrayRef<unsigned>)`
  and `populateUnsignedWhenEquivalentPatterns(RewritePatternSet &, DataFlowSolver &)`
  are declared. Confirm both at the pin before use.

## Fixed decisions

**The units.** Nine `.cpp` under `IDR/Transforms/Narrow`, one header.

- `NaturalRanges.cpp`: `NaturalRanges`, the seeded range analysis, and
  `Ranges`, the analysis under the pass manager that owns the solver.
- `Facts.cpp`: `Facts`, `isBig`, `ownedBig`.
- `Carried.cpp`: the joints (loops and merges) made words, as a pattern.
- `Ops.cpp`: an op whose bigs all fit made an op on words, as a pattern.
- `Versions.cpp`: the descent test and the versioning of a loop, as a
  pattern.
- `Narrow.cpp`: the `idr-narrow` module pass and the nested `NarrowWords`
  function pass.
- `Widths.cpp`: what a vectorized loop computes on and reads;
  `runsAtMostOnce`.
- `Copy.cpp`: the trial copy of a vectorized loop in its scratch module.
- `Lanes.cpp`: the lanes versioning as a pattern, and the
  `idr-narrow-lanes` pass.

`INC/Transforms/Narrow.h` declares, in namespace `idr::narrow`, everything
two of these units share: `NaturalRanges`, `Ranges`, `Facts`, `isBig`,
`ownedBig`, `narrowCarried`, `narrowOp`, `descendingArgument`, `version`,
`populateVersionPatterns`, `populateJointPatterns`,
`populateWordPatterns`, `Copy`, `Width`, `widthOf`, `isVectorized`,
`inputsOf`, `testable`, `fits32`, `computesWideLanes`, `runsAtMostOnce`.
Nothing under `IDR/Transforms/Narrow` has a header beside it. Every
`.cpp` includes `idr/IR/IdrDialect.h` first among ours, then
`idr/Transforms/Narrow.h`, then the MLIR headers it uses by name.

**The split of `idr-narrow`.** `Narrow.cpp` defines two passes.

- `Narrow`, from `GEN_PASS_DEF_IDRNARROW`, on `ModuleOp`. Its
  `runOnOperation`:
  1. `Ranges &ranges = getAnalysis<Ranges>()`. If `!ranges.valid()`, emit
     `internal error: idr-narrow: the range analysis failed` at the
     module and `signalPassFailure()`.
  2. `Facts facts(ranges)` over the module; a local `Counts` struct
     (`versioned`); `walkAndApplyPatterns(module, versionPatterns)` with
     `populateVersionPatterns(patterns, facts, counts)`.
  3. If `counts.versioned != 0`:
     `getAnalysisManager().invalidate(AnalysisManager::PreservedAnalyses())`,
     then `ranges = getAnalysis<Ranges>()` again. A versioned loop's copy
     has values the first solve never saw; nothing else of the module is
     worth keeping across it. Otherwise the first solve is the second.
  4. `OpPassManager nested(ModuleOp::getOperationName()); nested.nest<idr::FuncOp>().addPass(std::make_unique<NarrowWords>()); if (failed(runPipeline(nested, module))) return signalPassFailure();`
  5. `numVersioned += counts.versioned; markAnalysesPreserved<SymbolTable>();`
     (the pass adds and removes no symbol; it marks nothing else).
- `NarrowWords`, a `PassWrapper<NarrowWords, OperationPass<idr::FuncOp>>`
  with `MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID`, no argument, not
  registered, never in `Passes.td`. Its `runOnOperation`:
  1. `auto ranges = getCachedParentAnalysis<Ranges>()`; if absent, emit
     `internal error: idr-narrow: the ranges of the module are not
     available to its functions` and `signalPassFailure()`.
  2. `Facts facts(*ranges)` for this function; a local `Counts`
     (`carried`, `narrowed`).
  3. `walkAndApplyPatterns(fn, jointPatterns)` then
     `walkAndApplyPatterns(fn, wordPatterns)`: the joints first, while
     every value is still the one analysed; then the ops, whose operands
     may by then be the bigs of words (today `Words.cppm:63-77`).
  4. The cleanup: collect, by a walk, every op `facts.converted()` lists
     and every `idr.big.small` and `idr.big.from_int` of the function;
     `applyOpPatternsGreedily(ops, FrozenRewritePatternSet(), config)`
     with `GreedyRewriteStrictness::ExistingAndNewOps`. The driver folds
     the pairs (a word made a big and back is the word, through U16's
     folders) and erases what is trivially dead, which covers the
     versioned loop's start once its copy took the word (today
     `Words.cppm:80-88`, where the second half was a walk that erased).
  5. If both counts are zero and the cleanup erased nothing:
     `markAllAnalysesPreserved()`. Otherwise mark nothing.

**`idr-narrow-lanes`.** `NarrowLanes`, from `GEN_PASS_DEF_IDRNARROWLANES`,
on `func::FuncOp`. `runOnOperation`: a local `Lanes` struct (`narrowed`,
`wide`, `failed`); `walkAndApplyPatterns(fn, lanesPatterns)` with the one
pattern of `Lanes.cpp`; on `failed`, `signalPassFailure()` (the pattern
already emitted the error); `numNarrowed += …; numWide += …`; when
`narrowed == 0`, `markAllAnalysesPreserved()`. The manager merges the
statistics of the instances it clones per thread.

**The lanes pattern** is `OpRewritePattern<scf::ForOp>`. It matches a loop
that `isVectorized`, `computesWideLanes`, and has no `scf.for` ancestor
that `isVectorized` (the walk driver visits inner loops first; today's
pre-order walk with `skip` at `Lanes.cppm:140-145` took the outermost, and
this test keeps that). Its body is today's `versionLanes`
(`Lanes.cppm:61-129`) with three changes: a decline (`runsAtMostOnce`, no
testable input, no bound fits) emits the `Wide` remark, counts, and
returns failure; an internal error emits the error, sets `failed` and
returns failure; the loop as it was is cloned into the else region and
the matched loop erased with `rewriter.eraseOp`, instead of moved
(`Lanes.cppm:124`), because the walk driver promises erasure of the
matched op and nothing about moving it.

**The scratch module stays.** `Copy` builds the trial copy as a `func.func
@copy` in a detached `ModuleOp` it creates in its constructor and erases
in its destructor (`Copy.cppm:20, 49`), owned by one `matchAndRewrite`.
A function pass may create and analyse IR that is nested under no op of
the module; what it may not do is read or write a sibling function, and
the scratch module is neither. The alternative, a clone in the
function's own `scf.if` analysed in place, is rejected: the copy's inputs
must be the analysis's entry values for the `arith.minui` stand-ins to
be the only bound it sees (`Lanes.cppm:17-31`), which a function
argument of `@copy` gives and a value defined above a clone does not;
and each of the five to six trials would solve the whole `func.func`
instead of one loop. The solver on the copy stays upstream's stock
`IntegerRangeAnalysis` with `loadBaselineAnalyses`, not interprocedural
(`Copy.cppm:59-61`): after lowering there is no `!idr.nat` to seed.

**The seeding of `!idr.nat`.** `NaturalRanges::setToEntryState` gives an
anchor whose type is `!idr.nat` the range
`idr::ranges::rangeOf(idr::ranges::natural())`, that is `[0, INT64_MAX]`
in the 64-bit signed form where the upper extreme stands for no bound,
and every other anchor upstream's entry state (`Naturals.cppm:26-33`;
`IntegerRangeAnalysis.h:73-77`). This reaches every value the analysis
cannot see computed and gives an entry state to: a block argument of a
`!idr.nat` (a function parameter, a case region's argument), and the
result of an op without the range interface. The test is on the type as
written, `isa<NatType>`, as today: a natural under a grade
(`!idr.q<…, !idr.nat>`) is not seeded by its type, and `Facts::of` keeps
today's floor at 0 for a `!idr.nat` (`Facts.cppm:54-55`). The `ub.poison`
rule stays (`Naturals.cppm:39-44`). `NaturalRanges` declares its TypeID
with `MLIR_DECLARE_EXPLICIT_TYPE_ID` in the header and
`MLIR_DEFINE_EXPLICIT_TYPE_ID` in `NaturalRanges.cpp`, upstream's way;
`resolveTypeID` and its static go.

**`Ranges`, the analysis.** Constructor `Ranges(Operation *)`: casts to
`ModuleOp`, builds a `DataFlowSolver(DataFlowConfig().setInterprocedural(true))`,
loads `DeadCodeAnalysis`, `SparseConstantPropagation`, `NaturalRanges`,
runs it, records `valid` from the result, and records
`counted = idr::ownership::inOwnedStage(module)` (one walk, as today
`Words.cppm:43`). `isInvalidated(pa)` returns `!pa.isPreserved<Ranges>()`.
Members: `bool valid() const`, `bool counted() const`,
`std::optional<ConstantIntRanges> rangeOf(Value) const` (today's
`Naturals.cppm:59-64`), `const DataFlowSolver &solver() const`. It
mutates no IR and holds no IR after the pass that computed it, since no
pass preserves it. Reading it from several function passes at once is
reading a map that none of them writes.

**`Facts`** takes `const Ranges &` and is one object per function (per
module during versioning). Everything else in it is today's
(`Facts.cppm:31-111`), `counted` read from `Ranges`.

**What upstream's two passes replace, and what stays.**

- `arith-int-range-narrowing` replaces nothing in `idr-narrow`. Its
  patterns rewrite `arith` ops on integer types; every rewrite of
  `idr-narrow` is of an op of the dialect on `!idr.big` or `!idr.nat`
  (`idr.big.add/sub/mul/pred/cmp`, `idr.nat.from_big`, `idr.nat.to_big`,
  `idr.big.to_int`, `idr.check.nonzero`, `idr.match_lit`, `idr.dup`,
  `idr.drop`: `Ops.cppm:69-164`) or of a joint whose carried values are
  bigs retyped to `i64` (`Carried.cppm:53-115`), which no upstream
  pattern can see. It is already the narrowing of the lanes copy
  (`Copy.cppm:107`, at `{32}`) and stays exactly that.
- `arith-unsigned-when-equivalent` replaces nothing. `idr-narrow` emits
  `nsw`, `nuw` where nothing is negative, and signed comparisons
  (`Ops.cppm:18-37`); it emits no signed division, remainder or shift
  that the unsigned pass would turn. Running it after `idr-narrow` would
  be a new pipeline step (survey item 4), which this packet does not add.
- Stays, re-housed and unchanged in meaning: the big-to-word web
  (`Facts`, `Ops`, `Carried`), the versioning (`Versions`), the lanes
  (`Widths`, `Copy`, `Lanes`), the seeding (`NaturalRanges`).
- The known limit is the exactness of upstream's narrowing
  (`PINS.md` `int-range-narrowing-exactness`): the carried patch
  `upstream/09-int-range-narrowing-exactness/llvm.patch` keeps a `remsi`
  that may see the narrow minimum by -1 and a `remui` of a negative word
  wide; the shift is fixed at the pin. The lanes copy relies on it and
  carries no second copy of that decision (`Copy.cppm:67-71`).

**Versioning as a pattern.** `OpRewritePattern<scf::WhileOp>`; match is
`descendingArgument(loop, facts)`; rewrite is today's `version`
(`Versions.cppm:79-108`) with the loop as it was cloned into the else
region and the matched loop replaced by the `scf.if`'s results
(`rewriter.replaceOp`), instead of moved (`Versions.cppm:105-107`). The
copy in the then region is new IR, which the walk driver does not visit,
so a loop is versioned once.

**The joint and word patterns** match any op (`MatchAnyOpTypeTag`); the
joint one applies `narrowCarried` to `scf.while`, `scf.for`, `scf.if`,
`scf.index_switch`, `idr.match` and `idr.match_lit` and fails on
everything else; the word one applies `narrowOp` to the ops of
`Words.cppm:69-70` and fails on everything else, and fails on any op that
`Facts` made (`facts.converted()` as a set): a conversion the joints made
is folded by the cleanup, not narrowed again. Type changes of a result
or a block argument (`Carried.cppm:22, 32`) go through
`rewriter.modifyOpInPlace` of the owning op, which is the matched op or
one of its descendants. Patterns announce every change to the rewriter.

**Counters** are a local struct of `runOnOperation`, held by reference in
the patterns; a pattern increments, the pass reads. No statistic lives
in `NarrowWords`: a dynamic pipeline's passes are not in the manager's
statistics tree, so `idr-narrow` reports `versioned` alone.

**`runsAtMostOnce`** moves from `IDR/Graph/Trips.cppm:14-26` into
`Widths.cpp`, declared in `Narrow.h`, unchanged: upstream's value bounds
on the span of the loop's bounds against its step.

**Internal errors** are diagnostics at the loop or module, prefixed
`internal error: idr-narrow:` or `internal error: idr-narrow-lanes:`,
followed by `signalPassFailure()`. No `assert` stands in for one.

## Inputs

- C1.3: `idr-narrow` on `ModuleOp`; `idr-narrow-lanes` on
  `::mlir::func::FuncOp`; both names unchanged. The generated
  `GEN_PASS_DEF_IDRNARROW` and `GEN_PASS_DEF_IDRNARROWLANES` from
  `idr/Transforms/Passes.h.inc`, whose base classes define
  `idr::createIdrNarrow()` and `idr::createIdrNarrowLanes()`.
- C1.4: the pipeline positions `idr-narrow` before `idr-in-bounds` and
  `func.func(idr-vectorize, idr-narrow-lanes)` after `idr-entry`.
- C2.0: `getCachedParentAnalysis`, `markAllAnalysesPreserved`,
  `markAnalysesPreserved<…>`, `walkAndApplyPatterns`, the greedy driver.
- C2.1: the shape of an analysis (constructor `(Operation *)`,
  `isInvalidated`).
- C1.2 and C2.5: `idr::FuncOp` (`INC/IR/Func.h`, U02) as the anchor of
  the nested pass; `func::FuncOp` after lowering.
- From U01's `INC/IR/IdrDialect.h` and `INC/IR/Grades.h`, by today's
  names: the ops and types above, `BigAttr`, `CmpPredicate`,
  `unrestricted(Type)` (`IDR/Dialect/Grades/Unrestricted.cc:8-11`),
  `isOwned(Type)` (`IsOwned.cc:9-12`).
- From U01's `INC/IR/Ranges.h`, by today's names: `idr::ranges::Bounds`,
  `bounded`, `natural`, `boundsOf`, `rangeOf(Bounds)`, `smallMax`
  (`IDR/Ranges/Bounds.cppm:16-49`, `BoundsOf.cppm:12-16`,
  `RangeOf.cppm:15-19`).
- From U08's `INC/Transforms/Ownership.h`, by today's names:
  `idr::ownership::inOwnedStage(ModuleOp)`,
  `idr::ownership::isStatic(Value)`.
- From U16's folders in `IdrIR`: `idr.big.to_int` of `idr.big.small` is
  the word, and the symmetric fold, which the cleanup relies on as today.
- Upstream: `mlir::dataflow::{DataFlowSolver, DeadCodeAnalysis, SparseConstantPropagation, IntegerRangeAnalysis, IntegerValueRangeLattice, loadBaselineAnalyses}`,
  `mlir::arith::populateIntRangeNarrowingPatterns`,
  `mlir::walkAndApplyPatterns`, `mlir::applyOpPatternsGreedily`,
  `mlir::applyPatternsGreedily`, `mlir::ValueBoundsConstraintSet`,
  `mlir::getUsedValuesDefinedAbove`, `mlir::remark::{missed, passed}`,
  `mlir::PassWrapper`, `mlir::OpPassManager`.

## Outputs

- The library `IdrNarrow`: the nine `.cpp` of Fixed decisions, reported
  to the coordinator for `IDR/Transforms/Narrow/CMakeLists.txt`.
- `INC/Transforms/Narrow.h`, with:
  - `idr::narrow::Ranges` and `idr::narrow::NaturalRanges`, which
    `idr-in-bounds` (U12) may compute with `getAnalysis<Ranges>()` and
    read with `rangeOf`, in place of today's `narrow::runSolver` and
    `narrow::rangeOf(solver, value)` (`IDR/InBounds/Prove.cppm:107, 147`,
    `System.cppm:136`), or duplicate in its own unit (binding rule 3);
  - `idr::narrow::runsAtMostOnce(scf::ForOp)`, which `idr-expect`'s
    `narrowed-lanes` (U15) may include in place of today's
    `idr::graph::runsAtMostOnce` (`IDR/Expect/NarrowedLanes.cppm:66`), or
    duplicate.
- The two passes under their contract names and anchors, created by the
  generated constructors U14's `Pipeline.cpp` calls.
- The remarks `Narrowed` and `Wide` in the category `idr-narrow-lanes`,
  unchanged in name and category (`Lanes.cppm:63-67, 125-126`).

## Implement

- **`NaturalRanges.cpp`.** Takes `Naturals.cppm:17-64`. `NaturalRanges`
  as today minus `resolveTypeID`, with the explicit TypeID macros.
  `Ranges` as Fixed decisions says: the solver, `valid`, `counted`,
  `rangeOf`. `runSolver` becomes the constructor's body; nothing else
  loads the three analyses.
- **`Facts.cpp`.** Takes `Facts.cppm:19-111`. `Facts(const Ranges &)`;
  `of` calls `ranges.rangeOf`; `owned` and `borrowed` read
  `ranges.counted()`. `converted()` also answers `made(Operation *)` for
  the word pattern's refusal.
- **`Carried.cpp`.** Takes `Carried.cppm:19-115`. `narrowArgument` and
  `narrowResult` wrap their `setType` in `modifyOpInPlace` of the owning
  op. `populateJointPatterns(RewritePatternSet &, Facts &, Counts &)`
  adds the one any-op pattern that dispatches to `narrowCarried` and adds
  its return to `counts.carried`.
- **`Ops.cpp`.** Takes `Ops.cppm:18-164`. `populateWordPatterns` adds the
  one any-op pattern: fail on an op `Facts` made, else `narrowOp`;
  success increments `counts.narrowed`.
- **`Versions.cpp`.** Takes `Versions.cppm:21-108`. `version` clones the
  loop into both regions and replaces it. `populateVersionPatterns`
  adds the `scf.while` pattern; success increments `counts.versioned`.
- **`Narrow.cpp`.** Takes `Pass.cc:16-27` and `Words.cppm:39-90`, as the
  two passes of Fixed decisions. The joints-then-ops order, the greedy
  cleanup's configuration (`Words.cppm:80-82`) and the statistics
  `numVersioned` are kept; the two solver runs become the analysis and
  its conditional recomputation.
- **`Widths.cpp`.** Takes `Widths.cppm:18-87` unchanged and
  `Graph/Trips.cppm:14-26` as `runsAtMostOnce`.
- **`Copy.cpp`.** Takes `Copy.cppm:18-149` unchanged.
- **`Lanes.cpp`.** Takes `Lanes.cppm:45-151` and `Lanes/Pass.cc:15-25`
  as the pattern and the pass of Fixed decisions; the exponents 8 and 31
  keep their values and comments.
- **Failure paths.** `Ranges` invalid: `idr-narrow` fails with the
  internal error at the module. Parent analysis absent in `NarrowWords`:
  internal error at the function, pass failure. A copy's analysis or
  narrowing fails: internal error at the loop (today `Lanes.cppm:69-71,
  86-87, 94-95, 102-105`), `failed` set, pass failure after the walk.
  Every other decline is a `Wide` remark, never an error.

## Delete

- `IDR/Narrow/Narrow.cppm`, `Pass.cc`, `Words.cppm`, `Naturals.cppm`,
  `Facts.cppm`, `Ops.cppm`, `Carried.cppm`, `Versions.cppm`,
  `Lanes.cppm`, `Copy.cppm`, `Widths.cppm`, `Lanes/Pass.cc`: the module
  `idr.narrow` (`export module idr.narrow` and its partitions `:carried`,
  `:copy`, `:facts`, `:lanes`, `:naturals`, `:ops`, `:versions`,
  `:widths`, `:words`), and every `import idr.mlir`, `import idr.dialect`,
  `import idr.ownership`, `import idr.ranges`, `import idr.graph` in them.
- `idr::narrow::narrow(ModuleOp)` and `idr::narrow::narrowLanes(ModuleOp)`,
  the module-wide entry points, and the structs `Narrowed` and `Lanes`
  as returned values.
- `idr::narrow::runSolver(DataFlowSolver &, Operation *)` and
  `idr::narrow::rangeOf(DataFlowSolver &, Value)` as free functions: they
  become `Ranges`'s constructor and member.
- `NaturalRanges::resolveTypeID()` and its `static SelfOwningTypeID`.
- The second unconditional solve (`Words.cppm:59-62`).
- The `IRRewriter` driving every rewrite (`Words.cppm:41`,
  `Lanes.cppm:146`), the collect-then-rewrite walks (`Words.cppm:50-77`,
  `Lanes.cppm:140-145`), and the dead-conversion walk (`Words.cppm:85-88`).
- `moveOpBefore` of the versioned loop (`Versions.cppm:107`,
  `Lanes.cppm:124`).
- The statistics `numNarrowed` and `numCarried` of `IdrNarrow` (hub text
  for the coordinator; the pass no longer increments them).
- The dependency on `idr.graph` for `runsAtMostOnce`
  (`IDR/Narrow/CMakeLists.txt:23`).

## NOT TO DO

- Do not edit `INC/Transforms/Passes.td`, any `CMakeLists.txt`, or
  `IDR/Transforms/Pipeline.cpp` (U14). Report hub text instead.
- Do not add `arith-unsigned-when-equivalent` or
  `arith-int-range-narrowing` as a pipeline step, and do not run either
  on the module inside `idr-narrow`: the survey's item 4 is a later
  measurement, not this packet.
- Do not give the nested word rewrite a registered pass name or a row in
  `Passes.td`; it is `idr-narrow`'s own step.
- Do not write under `IDR/Analysis` or `INC/Analysis`: no file there is
  this lane's. `Ranges` lives in `INC/Transforms/Narrow.h`.
- Do not change the dialect's range hooks (`IDR/IR/OpsBigs.cpp`,
  `IDR/IR/Ranges.cpp`, U01), `idr-in-bounds` (U12), `idr-expect`'s
  `word-loop` and `narrowed-lanes` (U15), or `idr-vectorize` (U16).
- Do not seed a range for `!idr.big`, and do not widen the seeding to a
  natural under a grade: the condition is today's, by type as written.
- Do not reintroduce a per-op exactness check for the lanes copy (a
  shift's amount, a remainder's minimum, a negative word read unsigned):
  upstream's patterns with the carried patch decide it, and a second copy
  of that decision is what the patch removed (`upstream/09` README, "Our
  workaround").
- Do not move the lanes copy into the function. The scratch module is the
  decision.
- Do not hash the module or a function to learn whether anything changed;
  the counters say.
- Do not keep a solver, a `Facts`, a counter or a pattern set on a pass
  instance across runs. Pattern sets are built per run.
- Do not add a `std::mutex`, `std::atomic` or `thread_local` to count
  across the nested functions.
- Do not add a limit, budget or threshold: 8 and 31 and the `descends`
  depth of 64 (`Versions.cppm:23`) keep their values and comments.
- Do not write a test or a bench record. U21 and U22 write the fixtures;
  the coordinator runs `bench/run.sh`.
- Do not touch `third_party/`, `upstream/`, `PINS.md`.

## Stop and return

You are done when the nine `.cpp` and `INC/Transforms/Narrow.h` exist as
Fixed decisions says, every unit of `IDR/Narrow` but its
`CMakeLists.txt` is deleted, `idr-narrow` runs its word rewrite through
`runPipeline` on `idr.func`, and `idr-narrow-lanes` is anchored on
`func::FuncOp`. Return the changed paths mapped to the obligations, the
`.cpp` list for `IdrNarrow`, `Verification: NotRun (swarm policy)`, and
the hub text:

- `INC/Transforms/Passes.td`: `IdrNarrowLanes` anchored on
  `::mlir::func::FuncOp` (C1.3); `IdrNarrow`'s statistics reduced to
  `numVersioned` (its nested step cannot report through a dynamic
  pipeline); `IdrNarrow`'s `dependentDialects` gains
  `::mlir::ub::UBDialect`, since `Facts::word` creates `ub.poison`
  (`Facts.cppm:78`) and a dynamic pipeline's passes load no dialect of
  their own.
- `IDR/Transforms/Narrow/CMakeLists.txt`: `add_mlir_library(IdrNarrow …)`
  over the nine units, depending on `IdrPassesIncGen`, linking `IdrIR`,
  `IdrOwnership`, `MLIRAnalysis`, `MLIRArithDialect`,
  `MLIRArithTransforms`, `MLIRFuncDialect`, `MLIRSCFDialect`,
  `MLIRUBDialect`, `MLIRVectorDialect`, `MLIRTransformUtils`,
  `MLIRValueBoundsOpInterface`, `MLIRPass`.

Report as seams, without stopping: the names this lane consumed from U01
and U08 that the live headers spell otherwise; that `idr-in-bounds` and
`idr-expect` still name `narrow::runSolver`, `narrow::rangeOf` or
`graph::runsAtMostOnce` if their lanes have not yet taken the new
declarations; that a natural under a grade is not seeded, unchanged
here, for a later measurement; the evidence for `T/idr/narrow`,
`T/idr/vectorize` and `T/programs` that U21 and U22 should state
(Acceptance).

## Acceptance

- `T/idr/narrow/descending.mlir` (U21, on `idr.func`): after
  `--idr-tail-loops --idr-narrow`, `--idr-expect=holds=word-loop=@parity`
  holds; on the input without `idr-narrow` it fails with
  `expected word-loop: @parity computes on bigs in each of its loops`;
  `word-loop=@count` fails after `idr-narrow` with the same wording for
  `@count` (today `descending.mlir:1-13`).
- `T/idr/narrow/constants.mlir`: `--idr-narrow` and
  `--int-range-optimizations` each leave `idr.constant "x" : !idr.str`
  and the `idr.big.cmp lt` against a 24-digit natural as they are
  (`constants.mlir:1-9`).
- `T/idr/vectorize/lanes-loops.mlir`: `@vectorized` becomes an `scf.if`
  with `arith.muli … : vector<4xi32>` in its then region and
  `vector<4xi64>` in its else; `@mixed` and the last-tile loop get no
  version; in the version of the inexact loop the shift and the unsigned
  remainder stay on 64-bit lanes (`lanes-loops.mlir:1-22`).
- `T/idr/vectorize/lanes-x86-64.mlir`: `narrowed-lanes=@rows` and
  `narrowed-lanes=@squares` hold; `@eighth` fails with the `WIDE` text;
  `@inexact` fails with the `INEXACT` text; `--idr-target --idr-pipeline`
  reaches the LLVM dialect with 32-bit lanes (`lanes-x86-64.mlir:1-7`).
  `idris-mlir-opt --idr-narrow-lanes` on a module nests the pass under
  `func.func` implicitly, as `MlirOptMain` does (C5).
- `T/programs/nat/nat-large`, `nat-loop`, `nat-parity`, `nat-sum` (U22):
  stdout and exit status byte-identical to their `expected-stdout` and
  `expected`; `nat-parity`'s counted-down loop computes on words
  (`word-loop`), a hundred million steps within its budget.
- `T/programs/arrays/linarray-lanes-wide`, `linarray-lanes-narrow`,
  `linarray-spectral-norm`: `mlir.expect` `idr-narrow-lanes: narrowed-lanes`
  holds and the output is the 64-bit lanes' numbers either side of the
  bound; `linarray-lanes-exact` keeps 64-bit lanes and its output.
- `T/determinism/threads-*` (C9.2): byte-identical output and identical
  `--mlir-pass-statistics` under one thread and under many, with the word
  rewrite running per function in parallel.
- `bench/run.sh` on arm64 against `runs/2026-10-07-f5a4dff9-darwin-arm64`
  (the coordinator, README "Qualification"): `spectral-norm-linear` and
  `fannkuch-redux` within the 15% spread by ratio to C
  (`bench/README.md:101-104`); `spectral-norm-linear` keeps its 32-bit
  lane version (`bench/README.md:248-265`).
- Source conditions compilation does not establish: no `.cppm` and no
  header under `IDR/Transforms/Narrow`; no unit over 400 lines; no
  `thread_local`, `std::atomic`, `static` mutable object or
  `std::mutex`; no `SymbolTable` constructed; no `OperationFingerPrint`;
  no `IRRewriter` outside a pattern or the greedy driver; the nested pass
  fails with an internal error when its parent analysis is absent; the
  scratch module is erased on every path out of the lanes pattern.
- **Tempting partial:** running the word rewrite over the whole module
  inside the module pass, without `runPipeline`. Rejected: the
  function-level verifier and the parallel rewrite are what C1.3 and C4
  buy, and the module verifier would walk every function after it.
- **Tempting partial:** keeping both solves unconditional. Rejected: a
  program with no descending natural pays a second interprocedural solve
  for nothing.

## Escalate if

- `contracts.md` C2.1 names no range analysis and says its names are
  the only spellings, while U11's write set has no file under
  `INC/Analysis`; the seeded solver is read by `idr-in-bounds` as well
  (`IDR/InBounds/Prove.cppm:147`, `System.cppm:136`;
  `Naturals.cppm:47-58` says so). This lane puts `idr::narrow::Ranges` in
  `INC/Transforms/Narrow.h`. Report it so the contract names its home:
  there, or `IDR/Analysis/Ranges.cpp` under an owner.
- `INC/Transforms/Ownership.h` (U08) does not declare
  `idr::ownership::inOwnedStage` and `idr::ownership::isStatic`, or
  `INC/IR/Ranges.h` and `INC/IR/Grades.h` (U01) do not declare
  `idr::ranges::{Bounds, bounded, natural, boundsOf, rangeOf, smallMax}`,
  `isOwned`, `unrestricted`. Report the spellings you find; do not
  duplicate `isStatic`, whose `readFrom` is ownership's.
- `Pass::runPipeline` on the module with a `builtin.module(idr.func(…))`
  manager does not give the nested pass the module's analyses through
  `getCachedParentAnalysis<Ranges>()` at the pin. Report the failing
  lookup and the `AnalysisManager` code you read.
- `walkAndApplyPatterns` at the pin refuses something the joint rewrite
  does (an in-place type change of the matched op's block arguments, a
  new op inserted before the matched op). Report the assertion text and
  the pattern.
- The remark engine at the pin is not safe to call from function passes
  running in parallel (`mlir/lib/IR/Remarks.cpp`, `RemarkEngine::report`
  and the final policy's postponed remarks). `idr-narrow-lanes` emits
  `Narrowed` and `Wide` from a `func::FuncOp` pass, as `idr-vectorize`
  (U16) and the tail passes (U09) emit theirs. Report what you read; a
  bug there is upstream's to fix (AGENTS.md), not a mutex of ours.
- A fixture at 25890d32 reads `IdrNarrow`'s `narrowed` or `carried`
  statistic. None does (`grep -rn pass-statistics tests` finds
  `T/idr/obs/canonicalize.mlir` and `T/lib/determinism.sh:87-88`, which
  compares the listing with itself); report one if you find it.
- `populateIntRangeNarrowingPatterns` at the pin no longer takes a
  `DataFlowSolver &` and a width list, or the `upstream/09` patch no
  longer applies to the narrowing's cast kinds. Report the signature or
  the hunk.
