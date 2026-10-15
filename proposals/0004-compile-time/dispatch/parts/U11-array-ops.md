# U11 — Array ops MLIR-first: tensors, idr.tie_shape, structured loops

## Permitted outcome
1. Mandatory. `IdrArrayOps.td` declares exactly: the attribute
   `#idr.world`, the constraint `Idr_ArrayType` (world-ordered arrays),
   the world-ordered ops `idr.array.new`, `idr.array.get`,
   `idr.array.set` (kept, declaring C05's flow interface), and the new
   ops `idr.nat.to_extent` and `idr.tie_shape`, each as C11 sections 1,
   2, 4 and 5 write it. No `idr.array.generate`, no `idr.array.fold`, no
   region primitive, and no op that allocates or writes a value array's
   buffer (C11 section 5b).
2. Mandatory. `OpsArrays.cpp` implements those ops: the kept verifiers
   and canonicalization, per-memref effects (C11 section 5) in place of
   the IO resource, `idr.nat.to_extent`'s crash cause, folder and range,
   `idr.tie_shape`'s verifier, folds, `reifyResultShapes` and
   `populateBoundsForShapedValueDim`. Everything only the deleted loops
   needed is gone.
3. Mandatory. `idr-structure-loops` exists: `StructureLoops.h` with the
   pass declaration and `idr::structure::structurable`, and
   `lib/Transforms/StructureLoops/` with the pass (`StructureLoops.cpp`),
   the matching of nests and folds (`Plans.cpp`) and the building of the
   linalg ops (`Generics.cpp`), rewriting forms C, D, A and B of C11
   section 7 and nothing else.
4. Mandatory. C11 (`contracts/C11-array-ops.md`) is the declaration other
   lanes code against; where the live code forces a change to it, the
   lane reports the change instead of diverging.
5. Consumer adaptations: none outside the four owned paths. Every use of
   a deleted op in another lane's file is that lane's (C11 section 6
   names each).

## Owner / exclusive writes
- `INC/IR/IdrArrayOps.td` (`foreign/idr/include/idr/IR/IdrArrayOps.td`):
  rewritten.
- `IDR/IR/OpsArrays.cpp` (`foreign/idr/lib/IR/OpsArrays.cpp`): rewritten.
- `INC/Transforms/StructureLoops.h`
  (`foreign/idr/include/idr/Transforms/StructureLoops.h`): new.
- `IDR/Transforms/StructureLoops`
  (`foreign/idr/lib/Transforms/StructureLoops/`): new, with
  `StructureLoops.cpp`, `Plans.cpp`, `Generics.cpp`.

**Excluded:** `include/idr/IR/Grades.h`, `lib/IR/Grades.cpp` (the
predicates `isArray`, `isRank1Array`), `IdrBigOps.td`
(`Idr_ArrayValue`, `Idr_Rank1ArrayValue`), `IdrIOOps.td` and
`lib/IR/OpsPlatform.cpp` (the buffer ops and their effects),
`IdrMatchOps.td`, `IdrDialect.h`, `lib/IR/Regions.cpp`,
`lib/IR/Effects.cpp`, `lib/IR/Canon/MoveOut.cpp`, `lib/IR/Verify/`,
`lib/IR/TypeGraph.cpp`, `lib/IR/Types.cpp`, `tools/idris-mlir-tblgen.cpp`
and the generated `compiler/src/IdrisMLIR/Dialect/` (U01);
`include/idr/Transforms/Passes.td`, `lib/Transforms/Pipeline.cpp`,
`include/idr/Transforms/Pipeline.h` (U06); `lib/Transforms/Bufferize/`
(U12, the bufferization model of `idr.tie_shape`); `lib/Conversion/`
(U10); `lib/Analysis/Labels.cpp`, `lib/Transforms/Defunctionalize/` but
`ByName.cpp` (U02); `ByName.cpp` (U05); `lib/Transforms/Ownership/`,
`lib/Analysis/Ownership/` (U08); `lib/Transforms/Expect/`, `tests/idr`
(U17); every `CMakeLists.txt` (the coordinator).

## Read first
- `contracts/C11-array-ops.md`, whole; C12 section 2 (the
  `IdrStructureLoops` row) and section 3 (row 7); C24's
  `structured-loops` and `moves-out` rows; C05's flow interface; C15's
  model list (for `idr.tie_shape`).
- 0003: §2 (the correspondence), §4.1 to §4.3, §4.5, §5, §6, §13, §16,
  §17 item 1, §19 D4, D10, D13 to D16, D24 to D27, D39, D40.
- 0004: §2.2 (the flow interface's rule for shaped values), §2.5, §4
  stages 9 and 10.
- `foreign/idr/include/idr/IR/IdrArrayOps.td:1-187`;
  `foreign/idr/lib/IR/OpsArrays.cpp:1-297`.
- `lib/IR/Effects.cpp:15-111` (`consumes`, `ioEffects`, `does`,
  `onlyAllocates`, `performsIO`); `include/idr/IR/IdrDialect.h:70-200`
  (the effect helpers, the `MayCrash` trait); `lib/IR/Func/Call.cpp:76-96`
  (a call's effects); `include/idr/IR/IdrInterfaces.td:20-125`.
- `lib/IR/Grades.cpp:170-199`; `include/idr/IR/IdrBigOps.td:100-238`
  (the natural and big conversions, `Idr_ArrayValue`);
  `lib/IR/Fold/Bigs.cpp:120-160`; `lib/IR/OpsBigs.cpp:130-170`;
  `include/idr/IR/Ranges.h:1-60`.
- `lib/IR/Canon/MoveOut.cpp`, `lib/IR/Verify/Knots.cpp`,
  `lib/IR/TypeGraph.cpp:30-100` (what reads world-ordered arrays).
- The deleted loops' lowering, for the logic the structuring takes:
  `git show HEAD:foreign/idr/lib/Conversion/` and its two `ArrayLoop*`
  units (phase 1 of idr-lower for the loops).
- Upstream: `M/include/mlir/Interfaces/ValueBoundsOpInterface.h:135-292`
  and `.td`; `M/lib/Dialect/Tensor/IR/ValueBoundsOpInterfaceImpl.cpp:1-110`;
  `M/lib/Dialect/SCF/IR/ValueBoundsOpInterfaceImpl.cpp:47-120`;
  `M/include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td:150-180`
  (`linalg.generic`'s builders); `M/include/mlir/Dialect/SCF/IR/SCFOps.td:275-325`;
  `M/include/mlir/Transforms/WalkPatternRewriteDriver.h`;
  `M/lib/Dialect/MemRef/Transforms/ResolveShapedTypeResultDims.cpp:207-212`;
  `M/include/mlir/Interfaces/SideEffectInterfaces.h:200-290`.
- An existing nested pass as the model of shape:
  `lib/Transforms/Tail/TailLoops.cpp`, `include/idr/Transforms/Tail.h`.

## Fixed decisions
- The names, ops, types, folds, effects, forms and invariants of C11 are
  the decisions; this list adds only what is local to the files.
- `#idr.world` is declared in `IdrArrayOps.td`, beside the ops that take
  world-ordered arrays: an `AttrDef<Idr_Dialect, "WorldSpace">` with
  mnemonic `world` and no parameter.
- `Idr_ArrayType` stays the name of the constraint and stays in
  `IdrArrayOps.td`; its predicate is `::idr::isArray($_self)`.
- The world-ordered ops keep C++ `getEffects` (the `moves` property
  decides whether `get` writes), each built from
  `SideEffects::EffectInstance` on the op's `OpOperand` or `OpResult`
  with `SideEffects::DefaultResource`. They no longer call `ioEffects`.
- `idr.nat.to_extent`'s cause is the text `array too large`; its bound is
  `idr::ranges::smallMax` (`include/idr/IR/Ranges.h:24`); its folder
  reads the `idr::BigAttr`'s decimal digits.
- `idr.tie_shape` implements `ValueBoundsOpInterface` and
  `ReifyRankedShapedTypeOpInterface` in ODS, so the facts sit on the op.
  `IdrArrayOps.td` includes `mlir/Interfaces/ValueBoundsOpInterface.td`.
- `IdrArrayOps.td` no longer includes `IdrIOOps.td`.
- `structurable(op)` and the pattern share one matcher, in `Plans.cpp`:
  `std::optional<Plan> planAt(scf::ForOp)` returns the form and the
  values each form names (the loops, the destination, the fold, the
  lifted reads with their maps, the ops to clone); the pattern builds
  from the plan, `structurable` asks whether there is one.
- The pass runs `mlir::walkAndApplyPatterns` over the function with one
  `OpRewritePattern<scf::ForOp>`; counts are kept in a local struct the
  pattern holds by reference and added to the statistics after the walk.
- `areEqual` is `mlir::ValueBoundsConstraintSet::areEqual`; a failure is
  "not equal". Matching asks it only after the cheap structural checks.
- Payload ops are cloned with an `mlir::IRMapping`: each induction
  variable to `linalg.index d` made at the start of the body, each
  iter_arg to the destination (for its `tensor.dim` uses), the
  destination's element and F's iter_arg to the output block argument,
  each lifted read to its input block argument. A `linalg.index` left
  without uses is erased.

## Inputs
- C01: the identified data types, which are tensor elements and world
  array elements and nothing here inspects.
- C05: the flow interface the world-ordered ops declare (their element
  moves through the element anchor of the array's type): `Idr_FlowOpInterface`
  in `idr/IR/IdrFlow.td`, its bodies for the three ops in U02's `Flow.cpp`.
- C12: the `IdrStructureLoops` definition and its place in the pipeline.
- `idr::onlyAllocates`, `idr::isArray`, `idr::unrestricted`, `idr::view`,
  `idr::arrayRoot`, `canon::addMoveOutPatterns`, the `MayCrash` trait, as
  they are in the tree.

## Outputs
- C11, whole: `contracts/C11-array-ops.md`.
- `idr::WorldSpaceAttr`; `idr::NatToExtentOp`; `idr::TieShapeOp`;
  `idr::ArrayNewOp`, `idr::ArrayGetOp` (with `getMoves()`),
  `idr::ArraySetOp`; `idr::sameElement`, kept.
- `idr::createIdrStructureLoops()` (generated) and
  `bool idr::structure::structurable(mlir::Operation *loop)`.
- Consumers: C11 section 8.

## Implement
- **`IdrArrayOps.td`.** Header comment: the ops on arrays a world orders,
  the extent of an array to be made, and the tie of dimensions across a
  call. Includes `IdrAttrs.td`, `IdrInterfaces.td`, `IdrBigOps.td`,
  `idr/IR/IdrFlow.td` and `mlir/Interfaces/ValueBoundsOpInterface.td`.
  Then, in this order: `Idr_WorldSpaceAttr`; `Idr_ArrayType` with C11's
  description and a comment saying what a world-ordered array is and why
  its type names its memory; `Idr_ArrayOp` (today's traits and
  `DeclareOpInterfaceMethods<Idr_FlowOpInterface>`); `idr.array.new`,
  `get`, `set` with today's arguments, formats and builders and comments
  that say their effects are on their own array (the comment about the
  guard keeps "a proof is the guard's absence" without naming any pass);
  `Idr_NatToExtentOp`; `Idr_TieShapeOp`. Comments say why, never cite.
- **`OpsArrays.cpp`.** Header: the ops on world-ordered arrays, the
  extent, the tie. Keep `verifyCount`, `verifyElement`, `unguarded`,
  `sameIndex`, `idr::sameElement`, `ArrayNewOp::verify`,
  `ArrayGetOp::verify`, `ArraySetOp::verify`, the canonicalization,
  `ArrayNewOp::reifyResultShapes`. Rewrite the three `getEffects` per C11
  section 5. Add `NatToExtentOp::getCrashCause`, `fold` (a `BigAttr`
  whose digits parse as an `int64_t` in [0, smallMax] gives
  `IntegerAttr` of `index`), `inferResultRanges` (the operand's bounds
  through `idr::ranges::boundsOf`, clamped to [0, smallMax], as a signed
  64-bit range; none known gives [0, smallMax]). Add
  `TieShapeOp::verify`, `fold`, `reifyResultShapes`,
  `populateBoundsForShapedValueDim`, each as C11 section 4 writes it.
- **`StructureLoops.h`.** The C11 section 7 declaration, then, under
  `idr::structure`, what `Plans.cpp` and `Generics.cpp` share: `enum class
  Form { Parallel /*A*/, ReduceUnder /*C*/, Interchange /*D*/, Reduce /*B*/ }`;
  `struct Read { mlir::tensor::ExtractOp op; mlir::AffineMap map; }`;
  `struct Plan { Form form; llvm::SmallVector<mlir::scf::ForOp> nest;
  mlir::Value destination; mlir::scf::ForOp fold;
  mlir::tensor::ExtractOp element /*the destination's element, or null*/;
  llvm::SmallVector<Read> reads; llvm::SmallVector<mlir::Operation *> clones;
  llvm::SmallVector<mlir::Operation *> initClones /*what the fold's init needs*/; }`;
  `std::optional<Plan> planAt(mlir::scf::ForOp loop)`;
  `mlir::Value build(mlir::RewriterBase &, Plan &)` (the value that
  replaces the root loop's result).
- **`Plans.cpp`.** `planAt`: if the loop roots a nest, try C, then D,
  then A; else, if it is a fold, try B, refusing it where the loop is the
  inserted value of a nest that C or D takes (found by walking up to each
  enclosing `scf.for` and asking whether its nest takes the loop as C or
  D). Helpers:
  `unitLoop` (lower bound 0, step 1, no `unsignedCmp`, one iter_arg);
  `nestFrom` (the chain of loops and the checks of C11's nest);
  `foldOf` (C11's fold; the combiner when it is one integer op);
  `liftReads(block(s), dims, extents)` (the reads C11 lifts, deduplicated
  by tensor and indices); `neededOps` (the nest ops a set of ops uses,
  transitively, in program order); `written(nest)` (every dimension
  `areEqual` its extent). `structurable(op)` is
  `isa<scf::ForOp>(op) && planAt(...).has_value()`.
- **`Generics.cpp`.** `build`: per form, the inits generic where C11 asks
  for one, then the generic (or the `scf.for` of form D around it), the
  payload cloned through the mapping, `linalg.yield` of the mapped value.
  Iterator types `utils::IteratorType::parallel` and `reduction`; maps
  from `AffineMap::getMultiDimIdentityMap`, `AffineMap::get` and the
  lifted reads' maps; result types the destination's type (form A, C, D)
  or the 0-d tensor (form B).
- **`StructureLoops.cpp`.** `#define GEN_PASS_DEF_IDRSTRUCTURELOOPS`;
  the pattern (`planAt`, then `build`, then `replaceOp` of the root loop,
  counting the form); `runOnOperation` walks the function once and adds
  the counts; `structurable`.
- **Checks.** `check-units.py foreign/idr/lib/IR/OpsArrays.cpp` and the
  three new units (the script names a new unit not in the build; then
  check it by hand with the compile command of
  `lib/Transforms/Tail/TailLoops.cpp`, `-fsyntax-only`, writing nothing,
  against headers generated by `mlir-tblgen` into a directory under
  `/tmp/U11-gen` placed before the build's include directory).

## Delete
- `idr.array.generate`, `idr.array.fold`, `Idr_BodyRegion`, the comment
  block on the two loops (`IdrArrayOps.td:115-185`), and the include of
  `IdrIOOps.td`.
- In `OpsArrays.cpp`: `verifyWord`, `verifyLoopEnd`, `parseLoopBody`,
  `printLoopBody`, `ArrayGenerateOp::parse`, `print`, `verify`,
  `verifyRegions`, `reifyResultShapes`, `getEffects`, and the same of
  `ArrayFoldOp` (`OpsArrays.cpp:39-70, 173-297`); every call of
  `ioEffects`.
- The text that says a pass erases guards it proves
  (`IdrArrayOps.td:61-67`, which names idr-in-bounds's work).
- The value arrays of `Linear.Array` and `IArray` as memrefs: no op here
  takes an unordered array.

## NOT TO DO
- Do not edit `Grades.cpp`, `IdrBigOps.td`, `IdrIOOps.td`,
  `OpsPlatform.cpp`, `Effects.cpp`, `MoveOut.cpp`, `Regions.cpp`,
  `IdrMatchOps.td`, `IdrDialect.h` or the verifier, though section 5 and
  section 6 of C11 change what they must say: U01 owns them.
- Do not write `idr.scan`, `idr.scatter`, `reduceBlocked`'s form or the
  semiring `scf.parallel` structuring (0003 stage 4); no static extents
  or `tensor.cast` keys (stage 2, U04's keys); no immortal constants.
- Do not write the bufferization model of `idr.tie_shape` (U12) or its
  lowering (U10), nor delete `ArrayLoops.cpp` or `ArrayLoopReads.cpp`
  (U10).
- Do not touch `Passes.td` (U06): the pass definition is C12's. Report a
  description sentence the pass makes untrue.
- Do not add linalg generalization, fusion, specialization of generics,
  `eliminate-empty-tensors` or any transform schedule to the pass: they
  are pipeline steps of 0003 stage 3 or the coordinator's and U07's.
- Do not structure a loop by its element type, a size, a count or a
  budget: only its effects and its shape decide.
- No discardable attribute, no option, no name: the pass makes no symbol.
- Do not write the one-to-N conversion of record elements (0003 D44):
  it is the frontend's representation (U14).
- Do not declare an op that allocates or writes a value array's buffer
  (`idr.array.alloc`, `idr.array.put`, `idr.array.take`): the owned stage
  keeps upstream `memref.alloc` and `memref.store`, graded through U01's
  `idr.own.adopt` and `idr.own.give`.

## Tempting partial solutions
- Keeping `idr.array.generate` for words and adding tensors beside it:
  two spellings of one loop. Rejected by C11 section 6 and by the
  acceptance's search for `ArrayGenerateOp`.
- Leaving world-ordered arrays in the default memory space and telling
  a value buffer from an `IOArray` by where it came from: a fact outside
  the type, which the knot check and the lowering cannot read. Rejected
  by C11 section 1.
- Keeping the IO resource on the world-ordered ops "to be safe": D24
  says the memref, and the world operand already orders them. Rejected by
  the effects check in the acceptance.
- Structuring a float fold as a `linalg` reduction and relying on a
  one-lane schedule: the one-lane rule of idr-vectorize goes with it,
  and a reduction iterator means any order. Rejected: form B and C take
  integer combiners only.
- A greedy fixpoint driver over the function: it revisits what it made
  and folds as a second canonicalizer. Rejected: one walk.
- An `structurable` written beside the pattern instead of from the same
  plan: two tests of one rule that drift. Rejected: both call `planAt`.
- Lifting every read, offsets included, into indexing maps: a
  non-permutation map, or an input longer than the domain, changes the
  loop's range. Rejected: projected permutations whose dimensions
  `areEqual` the extents only.

## Acceptance
- `IdrArrayOps.td` declares `Idr_WorldSpaceAttr`, `Idr_ArrayType`,
  `Idr_ArrayNewOp`, `Idr_ArrayGetOp`, `Idr_ArraySetOp`,
  `Idr_NatToExtentOp`, `Idr_TieShapeOp` and nothing else; a search of
  the four owned paths finds no `ArrayGenerateOp`, `ArrayFoldOp`,
  `IOResource` or `ioEffects`.
- `mlir-tblgen -gen-op-decls`, `-gen-op-defs`, `-gen-attrdef-decls` and
  `-gen-attrdef-defs` on `IdrOps.td` succeed into `/tmp/U11-gen` (with
  the other lanes' ODS as it stands; a failure in another lane's file is
  reported, not fixed).
- `check-units.py foreign/idr/lib/IR/OpsArrays.cpp` is clean against
  those generated headers, or fails only on a declaration another lane
  owns (named in the handoff with its contract).
- The three new units compile `-fsyntax-only` with the dev warnings as
  errors against the same headers and a `Passes.h.inc` generated from
  the current `Passes.td`.
- Review: every form of C11 section 7 is built from one `Plan`;
  `structurable` and the pattern call the same `planAt`; no loop is
  rewritten whose ops do not all satisfy `idr::onlyAllocates`; no float
  accumulator is given a reduction iterator; no code reads a type's
  element to decide whether to structure.
- Fixtures are U17's; the lane writes `NEEDS-ACCEPTANCE` nowhere, since
  it owns no test.

## Stop and return
- Return when the four owned paths implement C11 and the checks above
  have run. List: changed paths mapped to outcomes 1 to 4; the
  declarations supplied; the checks with their last lines; every seam,
  among them: `IdrDialect.h` must include `ValueBoundsOpInterface.h`
  (U01); `isArray` must test `#idr.world` (U01); the yield's
  `ParentOneOf` and `Regions.cpp` still name the deleted loops (U01);
  the flow interface's shape for the world-ordered ops (C05, U02); the
  `IdrStructureLoops` description's missing sentence on form D (U06).
- Report, without stopping other work, any C11 declaration the live code
  cannot take as written, with the evidence and the change proposed.
