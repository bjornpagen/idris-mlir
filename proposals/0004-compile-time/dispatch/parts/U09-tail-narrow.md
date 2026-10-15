# U09 — Tail calls and narrowing on the new IR; the guard prover and the vectorize pass deleted

## Permitted outcome
1. Mandatory. The guard prover is gone: `IDR/Transforms/InBounds` (14 files)
   and `INC/Transforms/InBounds.h` are deleted whole. Nothing replaces
   them: a typed access has no guard (0003 D4), and the guards of
   world-ordered arrays and strings stay, checked at run time (0003 §13).
2. Mandatory. The vectorize pass is gone: `IDR/Transforms/Vectorize` and
   `INC/Transforms/Vectorize.h` are deleted whole. Vectorization is the
   transform schedule of C13, run by `transform-interpreter` in the
   lowered `func.func` group C12 orders.
3. Mandatory. The copies idr-accumulate and idr-trmc make are named from
   content through C21's `idr::contentName` (D18): the owner's symbol,
   the kind, an empty key.
   A name already taken is an internal error; the pass never renames.
   Two runs over one module, in any order of its functions, give the same
   names.
4. Mandatory. idr-tail-loops and idr-trmc read data types from the
   identified type (C01, D29): `WhileDo` takes a case's tag and a field's
   type from the scrutinee's type, with no symbol lookup and no failure
   path for a missing declaration; idr-trmc passes the constructor
   reference of the cell it builds, a `FlatSymbolRefAttr` (C02 §1), to
   `idr.dest.of`.
5. Mandatory. The tests of `idr.func`'s `isExternal()` in these passes are
   deleted (D7, C03: every `idr.func` has a body).
6. Mandatory. idr-narrow-lanes works on the loops C13's vectorization
   schedule leaves, whose coordinates are `index` from the start (0003
   D4), and leaves a vector accumulator out of the lanes it narrows, as
   C24's `narrowed-lanes` counts them; its search, remarks and statistics
   are unchanged.
7. Mandatory. `INC/Analysis/Ranges.h` says idr-narrow is its one reader.
8. Mandatory. A copy carries no fact that names another function's
   identity: no specialization key (C02), no discardable attribute.

Consumer adaptations this lane makes, all inside its writes: to C01 and
C02 (identified types, constructor references, `idr.func`'s properties),
to C03 (bodies always present), to C12 (the pass records U09's passes are
generated from) and to C21 (the name helper).

## Owner / exclusive writes
Kept and changed:
- `IDR/Transforms/Tail` (`foreign/idr/lib/Transforms/Tail/`): `Accumulate.cpp`,
  `AccumulatorPlan.cpp`, `Trmc.cpp`, `TailLoops.cpp`, `WhileDo.cpp`
  change; `Loop.cpp`, `Returned.cpp`, `ReturnedArguments.cpp` stay as
  they are unless a C01 or C02 accessor they call is renamed.
- `INC/Transforms/Tail.h`
- `IDR/Analysis/Tail.cpp`, `INC/Analysis/Tail.h` (the API stays; only C01
  or C02 accessor renames reach them)
- `IDR/Transforms/Narrow` (`foreign/idr/lib/Transforms/Narrow/`): the
  accumulations in `Widths.cpp` and `Copy.cpp`, comments in `Lanes.cpp`
  and `Widths.cpp`; the other five files stay.
- `INC/Transforms/Narrow.h` (one declaration added)
- `IDR/Analysis/Ranges.cpp`, `INC/Analysis/Ranges.h` (the comment)

Deleted:
- `IDR/Transforms/InBounds` (`Clamps.cpp`, `Empty.cpp`, `Guards.cpp`,
  `InBounds.cpp`, `Induction.cpp`, `Joins.cpp`, `Lengths.cpp`,
  `Masks.cpp`, `Paths.cpp`, `Prove.cpp`, `Quotients.cpp`,
  `Relation.cpp`, `Returned.cpp`, `System.cpp`) and the directory
- `INC/Transforms/InBounds.h`
- `IDR/Transforms/Vectorize` (`Vectorize.cpp`) and the directory
- `INC/Transforms/Vectorize.h`

Nothing new.

**Excluded:**
- `INC/Transforms/Passes.td`, `IDR/Transforms/Pipeline.cpp`,
  `INC/Transforms/Pipeline.h` (its includes of `InBounds.h` and
  `Vectorize.h`): U06, through C12.
- `IDR/Transforms/CMakeLists.txt` (the `IdrInBounds` and `IdrVectorize`
  libraries and their link lines), `IDR/Analysis/CMakeLists.txt`: the
  coordinator.
- `INC/Target/Target.h` and `IDR/Target/Target.cpp` (`vectorBits`),
  `IDR/Target/Schedules.cpp` (the vectorization schedule): U07.
- `IDR/Transforms/Expect` (`InBounds.cpp`, `NarrowedLanes.cpp`,
  `Vectorized.cpp`, `Words.cpp`) and `tests/idr` (the in-bounds,
  vectorize, tail and narrow fixtures): U17.
- `IDR/Conversion` (`TailCalls.cpp`, `TailCallPlan.cpp`,
  `TailPosition.cpp`): U10.
- `IDR/Transforms/Ownership/Specialize.cpp` (the `.excl` copies) and
  `IDR/Analysis/Ownership/Borrows.cpp`, `IDR/Analysis/Escapes.cpp`,
  `IDR/Analysis/EscapesCycles.cpp` (readers of `Analysis/Tail.h`): U08.
- `INC/IR/*`, `IDR/IR/*` (`Symbols.h`, `IdrOps.td`, the comments in
  `IdrCheckOps.td:57` and `OpsChecks.cpp:99`), C21's C++ helper: U01.
- `IDR/Transforms/Simplify/Round.cpp:64` (a comment naming the prover):
  U03.
- `upstream/` (the Presburger patch 0004 §7 item 3 planned for
  `Empty.cpp`): U16.
- `tests/programs`, `tests/determinism`, `tests/spec`, `tests/lib`: U18.

## Read first
- `contracts.md`: C01, C02, C03, C12, C13 (the vectorization schedule
  and the loops it leaves), C21, C24 (`narrowed-lanes`, the accumulator
  rule).
- 0004 (`proposals/0004-compile-time/README.md`): §4 stages 11 and 12
  (lines 981-998); §5.3 item 4 (lines 1140-1152, tail calls stay inside
  a unit); §6 rows "lookup-dodging branches" (line 1262), "Names from
  counters" (line 1265), "`InBounds/Empty.cpp`" (line 1269); D7, D18,
  D29, D38 (lines 1545-1548, 1581-1588, 1661-1672, 1732-1743).
- 0006 §4.5 (`proposals/0006-sharded-whole-program-compiler.md:447-470`):
  the name's width and the collision rule.
- 0003 (`proposals/0003-typed-apl/README.md`): §1's table (lines
  145-153); §2's table (lines 237-255) and D4 (line 1796); §6 (lines
  896-954); §7 and §7.1 (lines 957-1101); §13 (lines 1463-1480); §15
  (lines 1506-1530); §18's rejection of keeping the prover (lines
  1744-1746).
- The lane's sources:
  - `IDR/Transforms/Tail/Accumulate.cpp:43-146` (naming and insertion at
    `:118-124`); `Trmc.cpp:54-107, 145-183` (naming at `:166-170`);
    `AccumulatorPlan.cpp:156-222`; `TailLoops.cpp:115-141`;
    `WhileDo.cpp:39-75, 125-204`; `Loop.cpp`; `Returned.cpp:145-162`;
    `ReturnedArguments.cpp`.
  - `INC/Transforms/Tail.h`; `INC/Analysis/Tail.h`; `IDR/Analysis/Tail.cpp`.
  - `INC/Transforms/Narrow.h`; `IDR/Transforms/Narrow/Lanes.cpp:1-65,
    99-204`; `Widths.cpp:23-110`; `Copy.cpp`; `Narrow.cpp:104-142`.
  - `INC/Analysis/Ranges.h`; `IDR/Analysis/Ranges.cpp`.
  - `INC/Transforms/InBounds.h:1-8, 389-396`; `IDR/Transforms/Vectorize/
    Vectorize.cpp:1-23, 191`.
- Their consumers, read only: `IDR/Analysis/Ownership/Borrows.cpp:244`,
  `IDR/Analysis/Escapes.cpp:325`, `IDR/Analysis/EscapesCycles.cpp:49`
  (`tail::inTailPosition`, `tail::inTailPositionModuloConstructor`);
  `IDR/Transforms/Expect/NarrowedLanes.cpp:79` (`narrow::runsAtMostOnce`);
  `IDR/Transforms/Expect/Words.cpp:35-38` (`narrow::isBig`);
  `IDR/Transforms/Expect/InBounds.cpp:11, 37` (the prover's last reader,
  which U17 deletes); `INC/Transforms/Pipeline.h:19-28`;
  `IDR/Transforms/Pipeline.cpp:107-172` (today's order).
- Today's pass records: `INC/Transforms/Passes.td:385-528, 556-574,
  700-764`; the build lists `IDR/Transforms/CMakeLists.txt:204-246,
  279-345, 370, 396-397, 436-440`.
- Today's IR the contracts replace: `INC/IR/IdrOps.td:18-54` (the
  function's properties), `:203-300` (`idr.con`, `idr.field`, `idr.tag`,
  `idr.dest.of`); `INC/IR/IdrAttrs.td:231-243` (the clone fact);
  `INC/IR/Symbols.h:20-42` (the lookups D29 deletes).
- Upstream, under `.toolchain/build/llvm-project` (`M` is `mlir`, `L` is
  `llvm`): `M/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:
  336-345` (index operands narrowed through `arith.index_cast`),
  `:380-470` (the elementwise narrowing and the ops it leaves wide),
  `:813-823`; `M/include/mlir/IR/SymbolTable.h:52-57` (`insert` renames
  on a collision); `M/include/mlir/Interfaces/ValueBoundsOpInterface.h`
  (`computeConstantBound`, read by `runsAtMostOnce`);
  `L/include/llvm/Support/xxhash.h:58-70` (the hash C21 wraps).

## Fixed decisions
1. **The prover goes whole.** Every file under `IDR/Transforms/InBounds`
   goes, `Empty.cpp` included, with `INC/Transforms/InBounds.h`. No file
   of this lane calls a Presburger API afterwards; the integer emptiness
   0004 §7 item 3 planned to carry upstream then has no site in the tree,
   which is U16's to record. `INC/Analysis/Ranges.h:3-6` becomes: the
   ranges of the module's integers, bigs and naturals, solved once across
   calls; idr-narrow reads them; nothing else solves them.
2. **The vectorize pass goes whole.** No lane width, tile size or
   vectorization call moves into another file of this lane.
3. **idr-narrow-lanes on the new form.** It runs on `func.func` after
   C13's vectorization schedule, in the group C12 orders. It recognizes a
   vectorized loop by its ops (`isVectorized`, `Widths.cpp:29-45`: an
   `scf.for` without results holding vector ops, the loops of its tiles
   and ops with neither effects nor regions; a `vector.mask` is a vector
   op). Lanes of `index` are wide (`ConstantIntRanges::getStorageBitwidth`
   gives 64), and upstream's narrowing narrows them through index casts
   (`IntRangeOptimizations.cpp:336-345`), so coordinates that are `index`
   from the start need no code of their own. An integer sum now has lanes
   (0003 D15 case 1), and its accumulator fits under no bound. C24 counts
   no accumulator as a wide lane and asks every other loop with wide
   lanes to be versioned, so the pass leaves accumulations out of what it
   narrows: `accumulations(root)` (new in `Narrow.h`, in `Widths.cpp`) is,
   for each `scf.for` in `root` and each iteration argument of vector
   type, the greatest set of elementwise ops the argument reaches whose
   results go only to one another and to the yield operand that carries
   the argument (an op with no use is in no such set). `vector.reduction`
   and `vector.multi_reduction` are not elementwise, so `widthOf` already
   passes them by. `computesWideLanes` and `Copy::fits` skip the
   accumulations. The set does not depend on the bound, so the search
   over the exponents of `Lanes.cpp:62-65` stays a binary search over a
   monotone predicate. The remark category `idr-narrow-lanes`, the remark
   names `Narrowed` and `Wide`, and the statistics `numNarrowed`,
   `numWide` stay. `Lanes.cpp:3-38` and `Widths.cpp:23-31` say the loops
   come from the vectorization schedule, that a loop over an array
   computes on `index` coordinates and the program's words, and what an
   accumulation is.
4. **Names from content.** A copy is named `idr::contentName(owner,
   kind, "")` (C21, `INC/IR/Symbols.h`): the owner the original's symbol
   name, the kind `acc` for idr-accumulate's copy and `trmc` for
   idr-trmc's, the key empty. A function has at most one copy of each
   kind and both are already in the name, so the copy is a function of
   nothing else. One helper in `INC/Transforms/Tail.h`,
   `mlir::FailureOr<mlir::StringAttr> copyName(FuncOp fn, llvm::StringRef
   kind, mlir::SymbolTable &symbols)`, defined in `TailLoops.cpp` beside
   the other shared helpers, makes the name and looks it up in the pass's
   `SymbolTable`; a hit is something else (a second run finds no
   accumulator or destination site in a function it already rewrote), so
   it emits `internal error: the name <name> of the <kind> copy of
   @<owner> is taken` at the original and the pass fails. Otherwise the
   copy goes right after the original, as today, where
   `SymbolTable::insert` has nothing to rename. No counter, suffix literal
   or retry is written.
5. **What a copy carries.** A copy is made with `FuncOp::clone` and keeps
   every property of its original: C02 leaves `total`, `no_inline`,
   `effects` and `instance`, and deletes the clone key, so the
   `removeCloneAttr()` calls (`Accumulate.cpp:121`, `Trmc.cpp:169`) go.
   The copy keeps its location, which C24's `named` reads. Every call to
   a copy writes the copy's `effects` (C02 §4, D38: a pass that makes a
   call writes its callee's).
6. **Identified types.** `WhileDo` reads the match itself, which reads
   its scrutinee's identified type (C01, C02 §1): `continues()` tests
   `MatchOp::getCaseTag(0)`, the case's constructor's position in the
   type's body; `inlineRegion()` reads each field's type from
   `getDataType().getCtor(tag).fields`; `WhileDo::build()` loses the
   `declarationOf` call and its `return failure()` (`WhileDo.cpp:200-204`).
   `Trmc.cpp:54-58`'s `ctorOf` returns the built op's `getCtorAttr()`, a
   `FlatSymbolRefAttr`, and `passDestination` hands it to `idr.dest.of`
   unchanged.
7. **D7.** The `idr.func` tests `fn.isExternal()` at
   `AccumulatorPlan.cpp:159, 207`, `TailLoops.cpp:118` and `Trmc.cpp:153`
   go. `Returned.cpp:154` tests a `func.func`, which C03 does not
   constrain and where a declaration is a form of the op; it stays.
8. **Kept APIs.** `INC/Analysis/Tail.h` keeps every declaration (U08
   reads `inTailPosition` and `inTailPositionModuloConstructor`).
   `INC/Transforms/Narrow.h` keeps `isBig`, `isVectorized`,
   `runsAtMostOnce`, `computesWideLanes`, `widthOf` and `Copy` (U17 reads
   the first and third) and adds `accumulations`.
   `INC/Transforms/Tail.h` keeps its declarations.
9. **Passes.** idr-accumulate, idr-trmc, idr-narrow and
   idr-returned-arguments stay `ModuleOp` passes; idr-tail-loops stays on
   `idr::FuncOp`; idr-narrow-lanes stays on `func::FuncOp`. Each keeps
   its argument, its statistics and no option; each is defined by the
   generated `GEN_PASS_DEF_*` of its C12 record and declared by
   `GEN_PASS_DECL_*` in its header, as today. Where they run is C12's.

## Inputs
- C01: `idr::DataType` (`INC/IR/IdrDialect.h`, generated types):
  `getCtor(unsigned tag)` giving an `idr::Ctor` whose `fields` are the
  field types in order; `dataTypeOf(Type)` (`INC/IR/Symbols.h`) behind
  the ops' accessors.
- C02: every op names a constructor by a `FlatSymbolRefAttr` within its
  value's data type (`idr.con` and `idr.reuse` `getCtorAttr()`,
  `idr.field` and `idr.dest.of` built with one, `idr.match` cases);
  `MatchOp::getDataType()` and `getCaseTag(unsigned)`; `idr.func`'s
  properties `total`, `no_inline`, `effects`, `instance`, with no clone
  key; a call writes its callee's `effects`, checked equal (D38).
- C03: every `idr.func` has a body; the function verifier refuses one
  without.
- C12: the records of the six kept passes in `Passes.td` (arguments,
  anchors, statistics, generated names) and their positions; no record
  for the prover or the vectorize pass.
- C13: the vectorization schedule and the loop form it leaves on
  `func.func` (`scf.for` tile loops from `tile_using_for`, a peeled or
  masked last tile, vector ops inside).
- C21: `std::string idr::contentName(llvm::StringRef owner,
  llvm::StringRef kind, llvm::StringRef key)` (`INC/IR/Symbols.h`), giving
  `<owner>.<kind>.<16 hex digits>`; the kinds `acc` and `trmc` are
  U09's.
- C24: `narrowed-lanes` counts no vector accumulator (the lanes of
  `vector.reduction`, `vector.multi_reduction`, and an `scf.for`
  iteration argument of vector type with the ops that only combine into
  it) as a wide lane; every other loop with wide integer lanes that may
  run more than once is the 64-bit version beside a 32-bit one.

## Outputs
This lane produces no contract. It supplies, unchanged in name and shape:
- the generated constructors of idr-accumulate, idr-trmc, idr-tail-loops,
  idr-narrow, idr-narrow-lanes and idr-returned-arguments, which U06's
  pipeline calls;
- `idr::tail::inTailPosition`, `passesOnPrevious`, `isTailMatch`,
  `tailMatch`, `isSelfCall`, `Modulo`, `moduloAt`,
  `inTailPositionModuloConstructor` (`INC/Analysis/Tail.h`), which U08's
  borrow inference and escape analysis read;
- `idr::narrow::isBig` and `runsAtMostOnce` (`INC/Transforms/Narrow.h`),
  which U17's `words` and `narrowed-lanes` properties read, and
  `idr::narrow::accumulations(mlir::Operation *)`, the accumulator rule
  held once, which U17's `narrowed-lanes` may read instead of restating
  it;
- `idr::Ranges` (`INC/Analysis/Ranges.h`), read by idr-narrow alone.
It removes `INC/Transforms/InBounds.h` and `INC/Transforms/Vectorize.h`,
whose includes U06 drops from `Pipeline.h` and whose last reader U17
deletes (`Expect/InBounds.cpp`).

## Implement
- **`Tail.h`, `TailLoops.cpp`.** `copyName` (fixed decision 4), declared
  under a "Copies" heading and defined after `reachesTailCall`.
- **`Accumulate.cpp`.** In `Accumulate::runOnOperation`, for a function
  with accumulator sites: `copyName(fn, "acc", symbols)`; on failure,
  `signalPassFailure()` and return. Clone, `setSymNameAttr`,
  `setPrivate()`, append the carried argument, `symbols.insert(clone,
  std::next(fn->getIterator()))`. `retarget` and the seed call write
  `clone.getEffectsAttr()`. The file comment says the copy is named from
  its owner and its kind.
- **`Trmc.cpp`.** The same in `Trmc::runOnOperation` with kind `trmc`;
  `callClone` writes `clone.getEffectsAttr()`. Delete `fn.isExternal()
  ||` at `:153`. `ctorOf` returns the built op's `getCtorAttr()`, a
  `FlatSymbolRefAttr` (C02 §1), and `passDestination` hands it to
  `idr.dest.of` unchanged.
- **`AccumulatorPlan.cpp`.** Delete the `fn.isExternal() ||` terms at
  `:159` and `:207`.
- **`TailLoops.cpp`.** Delete `fn.isExternal() ||` at `:118`. The file
  comment's "nothing else but the declaration of a scrutinee's type"
  (`:25-27`) becomes: the function's own ops, its scrutinees' types
  included.
- **`WhileDo.cpp`.** Delete the `DataOp data` member; `continues()`
  tests `MatchOp::getCaseTag(0)` (C02 §1); `inlineRegion()` reads a
  field's type from `sum.getDataType().getCtor(sum.getCaseTag(index))
  .fields` (C01 §3) and builds `idr.field` with the case's
  `FlatSymbolRefAttr`; `build()` drops `:200-204`; the include of
  `idr/IR/Symbols.h` goes. `TailLoops.cpp:25-27` says the pass reads its
  own function alone, a scrutinee's type carrying its constructors.
- **`Loop.cpp`, `Returned.cpp`, `ReturnedArguments.cpp`,
  `Analysis/Tail.cpp`, `Narrow/Carried.cpp`, `Facts.cpp`, `Ops.cpp`,
  `Versions.cpp`, `Narrow.cpp`, `Analysis/Ranges.cpp`.**
  Unchanged, except where a C01 or C02 accessor they call is renamed;
  the analyses each pass marks preserved (`Holds`, `TypeGraph`,
  `Layouts`, `SymbolTable`) follow the classes C01 and U03 keep: a class
  that no longer exists leaves the list.
- **`Narrow/Widths.cpp`, `Copy.cpp`, `Lanes.cpp`, `Narrow.h`.**
  `accumulations` and its two readers (fixed decision 3); comments.
- **`Analysis/Ranges.h`.** The comment of fixed decision 1.
- **Deletions.** Remove the files and directories of the Delete section.
- **Failure paths.** A taken name is an internal error at the original
  function; the analysis and narrowing failures of idr-narrow and
  idr-narrow-lanes stay internal errors as today; no path refuses a
  program.
- **For the coordinator and U06, in the handoff:** the build lines to
  drop (the `IdrInBounds` and `IdrVectorize` libraries, their
  `MLIRPresburger` and vectorize link lines and their entries in the
  pipeline's link list, `IDR/Transforms/CMakeLists.txt:279-345, 396,
  438, 440`), the link line `IdrTail` needs for C21's helper, and the
  `Passes.td` text that names the deleted passes (`:7`, `:479-528`,
  `:700-732`, and "After idr-..." at `:737`).

## Delete
- `IDR/Transforms/InBounds/` whole: `Clamps.cpp`, `Empty.cpp`,
  `Guards.cpp`, `InBounds.cpp`, `Induction.cpp`, `Joins.cpp`,
  `Lengths.cpp`, `Masks.cpp`, `Paths.cpp`, `Prove.cpp`, `Quotients.cpp`,
  `Relation.cpp`, `Returned.cpp`, `System.cpp`; and
  `INC/Transforms/InBounds.h` with everything in it: the pass
  `idr-in-bounds` and its nested `idr-in-bounds-prove`
  (`createProveInBoundsPass`), `idr::inbounds::Linear`, `System`,
  `Induction`, `Lengths`, `Lengths::Local`, `Component`, `InterfaceKey`,
  `Join`, `Proj`, `Origin`, `GivenBack`, `knownAt`, `pathFacts`,
  `relateQuotients`, `componentOf`, `dimensionOf`, `clampOf`, `measured`,
  `positionIn`, `joinOf`, `returnedOrigins`, `accessedArray`,
  `guardedArray`, the integer emptiness of `Empty.cpp` and its branch
  budget.
- `IDR/Transforms/Vectorize/Vectorize.cpp` and `INC/Transforms/Vectorize.h`:
  the pass `idr-vectorize`, its sizes from `idr::target::vectorBits`, its
  one-lane rule for reduction dimensions, its decide-before-tiling rule,
  its `Vectorized` and `Scalar` remarks.
- The names `<owner>.acc` (`Accumulate.cpp:119`) and `<owner>.trmc`
  (`Trmc.cpp:167`) and the renaming `SymbolTable::insert` did on their
  collisions.
- The `idr.func` tests of `isExternal()` at `AccumulatorPlan.cpp:159,
  207`, `TailLoops.cpp:118`, `Trmc.cpp:153`.
- `WhileDo`'s `DataOp data` member, its `declarationOf` and `lookupCtor`
  calls (`WhileDo.cpp:159, 180, 201`) and the failure path for a missing
  declaration (`:202-203`).
- The copies' `removeCloneAttr()` calls (`Accumulate.cpp:121`,
  `Trmc.cpp:169`), with the self-referencing `CloneAttr` C02 deletes.
- Every comment of this lane that names idr-in-bounds or idr-vectorize
  (`INC/Analysis/Ranges.h:5`, `Lanes.cpp:5-6`).

## NOT TO DO
- Do not edit `Passes.td`, `Pipeline.cpp` or `Pipeline.h` (U06), any
  `CMakeLists.txt` (the coordinator), `IDR/Transforms/Expect` or
  `tests/` (U17, U18), `IDR/Target` (U07), `IDR/Conversion`, the tail-call
  plan included (U10), `Ownership/Specialize.cpp` and its `.excl` names
  (U08), `INC/IR` or `IDR/IR` (U01), `upstream/` or `PINS.md` (U16).
  Report what they need.
- Do not write a hash, a hex printer or a name format of your own: the
  helper is C21's, written by U01.
- Do not keep any part of idr-in-bounds alive: no stub pass, no kept
  header for `Expect/InBounds.cpp`, no port of its proofs onto value
  bounds, no local pattern for the guards of `IOArray` or strings (0003
  §13 makes that a later measurement, not this cutover's work).
- Do not move idr-vectorize's lane width, tiling or peeling into
  idr-narrow-lanes or anywhere else in this lane.
- Do not change idr-narrow's analysis or rewrite, idr-returned-arguments'
  fixpoint, or idr-tail-loops' loop shapes beyond the type reads.
- Do not add a pass, an option, a statistic, a remark, a flag or a
  discardable attribute.

## Tempting partial solutions
- *Keep `fn.getSymName() + ".acc"` and let `SymbolTable::insert` rename on
  a collision.* Rejected: insertion order then reaches the output (the
  §6 row). Acceptance: no suffix literal in `IDR/Transforms/Tail`, and a
  module that already holds the copy's name is refused with the internal
  error, not renamed.
- *Retry with a counter or a widened hash when the name is taken.*
  Rejected by D18 and 0006 §4.5: a collision is an internal error, never
  a widened name.
- *Make the key the owner's body, or its printed form, "to be safe".*
  Rejected: the owner and the kind are already in the name, and a
  function has at most one copy of each kind; a body in the key makes the
  name move with every edit, against 0006's name stability.
- *Keep a `declarationOf` fallback in `WhileDo` for a type without a body.*
  Rejected: an identified type without a body is refused by the verifier
  (C01, D29). Acceptance: no `declarationOf`, `lookupCtor`, `DataOp` or
  `CtorOp` in `IDR/Transforms/Tail` or `IDR/Analysis/Tail.cpp`.
- *Keep `fn.isExternal()` as a cheap defensive test.* Rejected by D7 and
  C03. Acceptance: `isExternal` appears only at `Returned.cpp:154`.
- *Keep `InBounds.h` so `Expect/InBounds.cpp` still compiles.* Rejected:
  U17 deletes that property (0003 §15). Acceptance: the header does not
  exist.
- *Let idr-narrow-lanes version a loop when some of its wide ops fit,
  whichever they are.* Rejected: the set of ops then depends on the
  bound, the predicate is no longer monotone, and the binary search
  answers nothing. Only the accumulations, a set fixed by the loop's
  structure, are left out. Acceptance: `Copy::fits` skips exactly
  `accumulations(copy)`, and the search in `VersionLanes` is unchanged.
- *Mark accumulator ops with an attribute when the schedule makes them.*
  Rejected: a fact in a discardable attribute; the structure says it.

## Acceptance
- The paths `IDR/Transforms/InBounds`, `INC/Transforms/InBounds.h`,
  `IDR/Transforms/Vectorize` and `INC/Transforms/Vectorize.h` do not exist.
- `grep -rn 'inbounds::\|InBounds.h\|Vectorize.h\|vectorBits'
  foreign/idr/lib/Transforms/Tail foreign/idr/lib/Transforms/Narrow
  foreign/idr/lib/Analysis/Ranges.cpp foreign/idr/lib/Analysis/Tail.cpp
  foreign/idr/include/idr/Transforms/Tail.h
  foreign/idr/include/idr/Transforms/Narrow.h
  foreign/idr/include/idr/Analysis` finds nothing.
- `grep -n '"\.acc"\|"\.trmc"\|\.acc"\|\.trmc"' foreign/idr/lib/Transforms/Tail/*.cpp`
  finds nothing; both copies are named by C21's helper.
- `grep -n 'isExternal' foreign/idr/lib/Transforms/Tail/*.cpp` finds only
  `Returned.cpp`'s.
- `grep -n 'declarationOf\|lookupCtor\|DataOp\|CtorOp'
  foreign/idr/lib/Transforms/Tail foreign/idr/lib/Analysis/Tail.cpp`
  finds nothing.
- The comments of `INC/Analysis/Ranges.h`, `Lanes.cpp` and `Widths.cpp`
  name no deleted pass.
- `grep -n 'accumulations' foreign/idr/lib/Transforms/Narrow/*.cpp` shows
  its definition in `Widths.cpp` and its readers `computesWideLanes` and
  `Copy::fits`, nothing else.
- `python3 proposals/0004-compile-time/check-units.py` over the 18
  `.cpp` files of `IDR/Transforms/Tail`, `IDR/Transforms/Narrow`,
  `IDR/Analysis/Ranges.cpp` and `IDR/Analysis/Tail.cpp` passes, or fails
  only where a C01, C02, C12 or C21 declaration does not exist yet in the
  tree; each such failure is listed with the declaration it lacks.
- On the owner's machine (U17's fixtures, not this lane's): the
  accumulator and destination-passing fixtures give the same module at 1,
  2 and 8 threads and in either order of two functions; a module that
  already holds the copy's name reports the internal error; idr-tail-loops
  turns a match on an identified type into a while-do loop; the
  narrowed-lanes fixtures still narrow after the vectorization schedule,
  and a loop whose only wide lanes are a vector accumulator gets no
  version and no remark.

## Stop and return
Stop when the deletions are made, the five changed files of
`IDR/Transforms/Tail` and the comments are written, and check-units.py
has run over the lane's 18 `.cpp` files. Return the handoff with: the
seams where a C01, C02, C12, C13 or C21 declaration is missing or differs
from what this part assumes (file, line, what is missing, which
contract); the build lines and `Passes.td` text for the coordinator and
U06; the readers of the deleted headers outside the lane
(`Pipeline.h:19, 28`; `Expect/InBounds.cpp:11, 37`); and every comment
outside the lane that still names a deleted pass (`IdrCheckOps.td:57`,
`IdrArrayOps.td:64`, `OpsChecks.cpp:99`, `Target.h:45`,
`Expect/Vectorized.cpp:3, 34`, `Simplify/Round.cpp:64`), for their owners.
