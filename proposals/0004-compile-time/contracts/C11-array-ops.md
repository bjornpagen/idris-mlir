## C11 Array ops, idr.tie_shape and idr-structure-loops

Producer: U11. Files: `foreign/idr/include/idr/IR/IdrArrayOps.td` (it
includes `IdrAttrs.td`, `IdrInterfaces.td`, `IdrBigOps.td`, `IdrFlow.td`
and `mlir/Interfaces/ValueBoundsOpInterface.td`),
`foreign/idr/lib/IR/OpsArrays.cpp`,
`foreign/idr/include/idr/Transforms/StructureLoops.h` (new),
`foreign/idr/lib/Transforms/StructureLoops/` (new: `StructureLoops.cpp`,
`Plans.cpp`, `Generics.cpp`). Paths below are under `foreign/idr/` unless
named; `M/` is the pinned MLIR, `.toolchain/build/llvm-project/mlir/`.
Line numbers are the tree at a3e61f3a. This is 0003's stage 1 only
(0003 §17 item 1): no `idr.scan`, `idr.scatter`, `reduceBlocked`, semiring
`scf.parallel` (stage 4, D16), static extents from specialization (stage
2, D39) or immortal constants (stage 2, D40).

### 1. What an array is

Three kinds, each its own type, so no type is two of them.

1. **A value array** (`Array s a`, and `LArray`'s carrier) is a builtin
   `RankedTensorType`: rank 0 or more, no encoding, its element a field
   type that is not the world, not graded and not shaped (a builtin
   `i8`, `i16`, `i32`, `i64`, `f64`, or an idr runtime type: data, box,
   str, big, nat, and before idr-defunctionalize fn and lazy). There is no
   array type of ours (0003 §2). In this wave every dimension the frontend
   writes is dynamic (0003 D40; static extents are stage 2); every op and
   pattern here accepts static dimensions too. An unranked tensor is never
   an array: a rank no analysis fixes is the frontend's refusal (D25, C20).
2. **A linear array** is `!idr.lin<tensor<...>>`, the grade around the
   carrier (0003 §8). It is the only grade a tensor carries: U01's
   `QType::verify` (`lib/IR/Types.cpp:14-30`) accepts a ranked tensor at
   (one, plain) and nowhere else. `idr.lin.use` unwraps it into a plain
   tensor, `idr.lin.enter` wraps one (U01's ops,
   `include/idr/IR/IdrOwnershipOps.td:180-202`; their bufferization models
   are C15's). No scf, tensor or linalg op takes or gives a graded tensor.
3. **A world-ordered array** (base's `IOArray`'s `ArrayData`, `Buffer`,
   `IORef`'s `Mut`) is a memref in the world's memory space:
   `memref<?xE, #idr.world>` (an `ArrayData` or a `Buffer`, E = `i8`), or
   `memref<E, #idr.world>` (a `Mut`). E is a field type at no grade, not
   the world, as today (`lib/IR/Grades.cpp:182-195`).

`#idr.world` is new, declared in `IdrArrayOps.td`:

```tablegen
def Idr_WorldSpaceAttr : AttrDef<Idr_Dialect, "WorldSpace"> {
  let mnemonic = "world";
  let summary = "the memory of an array a world orders";
}
```

C++ class `idr::WorldSpaceAttr` (generated into `IdrAttrs.h.inc` from
`IdrOps.td`, which includes `IdrArrayOps.td`; registered by the generated
attribute list, `lib/IR/Dialect.cpp:124-127`). No parameter. It is
written `#idr.world`. Reason: bufferization makes every value array a
memref in the default memory space (C15), and a value buffer and an
`IOArray` of one element type would otherwise be one type; then the type
graph would take a value buffer for a cell written after it is shared
(`lib/IR/Verify/Knots.cpp:3-10`, `lib/IR/TypeGraph.cpp:81-95`), and the
lowering could not tell an `IOArray`'s components (`lib/IR/Layout/Components.cpp:90-99`)
from a buffer's descriptor. The memory space is a fact of the type, not
an attribute a pass can drop.

**The predicates** (U01's `include/idr/IR/Grades.h:144-149`, bodies in
`lib/IR/Grades.cpp:188-199`, names and signatures unchanged):
- `bool idr::isArray(mlir::Type)`: a `MemRefType` of rank 0 or 1, every
  dimension dynamic, identity layout, memory space `isa<WorldSpaceAttr>`,
  element as above. Exactly a world-ordered array. Today's
  `!memref.getMemorySpace()` becomes the `WorldSpaceAttr` test; nothing
  else changes.
- `bool idr::isRank1Array(mlir::Type)`: `isArray` and rank 1.
- No predicate names a value array: `isa<RankedTensorType>` is the test,
  and a value buffer is a `MemRefType` whose memory space is not
  `#idr.world`.

The ODS constraints keep their names and change their descriptions only:
`Idr_ArrayType` (in `IdrArrayOps.td`, U11, "an array a world orders,
memref<?xE, #idr.world> or memref<E, #idr.world> of a field type E"),
`Idr_ArrayValue` and `Idr_Rank1ArrayValue` (in
`include/idr/IR/IdrBigOps.td:233-238`, U01, "an array a world orders ...
at any grade").

### 2. Coordinates and extents (0003 D4, §4.3)

- **A coordinate** is an `index` at its access, exact and unguarded: its
  type bounds it by an extent. No op of ours: a natural becomes a
  coordinate as `%w = idr.big.to_int %n : i64` (the natural's type
  printed by the op) then `%i = arith.index_castui %w : i64 to index`; an
  index becomes a natural as `%w = arith.index_castui %i : index to i64`
  then `%n = idr.big.small %w : !idr.nat`. `idr.big.small` is exact here:
  an extent of an array that exists is below 2^62 on both targets, the
  small range (`include/idr/IR/Ranges.h:22-24`). The two round trips fold
  away (`lib/IR/Fold/Bigs.cpp:146-155`; `M/lib/Dialect/Arith/IR/ArithOps.cpp:2435-2443`),
  so a coordinate made from an induction variable is the induction
  variable again after canonicalization, which the read lifting of
  section 6 needs.
- **An extent** enters `index` at an allocation, guarded, through the one
  new op, `idr.nat.to_extent` (in `IdrArrayOps.td`):

```tablegen
def Idr_NatToExtentOp : Idr_Op<"nat.to_extent", [Idr_MayCrash<>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "a natural as the extent of an array to be made";
  let arguments = (ins Idr_NatType:$natural);
  let results = (outs Index:$extent);
  let assemblyFormat = "$natural attr-dict";
  let hasFolder = 1;
}
```

  Meaning: the natural as an `index` when it is small (below 2^62); a
  natural that is not small is past every allocation either target can
  make, and is the allocation's failure, the crash `array too large`
  (`getCrashCause()` returns that text; the trait gives the effects and
  `NotSpeculatable`). Folds a constant natural (an `idr::BigAttr`) in
  [0, 2^62) to its `index` attribute. Its range is the natural's,
  clamped to [0, 2^62 - 1]. Lowering is C16's: the small word untagged,
  else the crash. Generated Idris builder `natToExtentOp`.
- **Sizes computed from sizes** use `arith.addi`, `subi`, `muli` with
  `#arith.overflow<nsw, nuw>` on `index`, or `affine.apply`, which value
  bounds models; never the `index` dialect (0003 §4.3). `n * m` stays two
  dimensions wherever the type has two. No index arithmetic on sizes may
  overflow: a sum of two sizes, each below 2^62 (an extent, or a
  dimension of an array that exists), is below 2^63. A size an op derives
  from three or more terms (`tensor.pad`'s low, length and high) is first
  converted whole: the frontend computes the total on naturals and passes
  it through `idr.nat.to_extent` before the op, whose result may go
  unused; the parts are then coordinates.

### 3. The generating set's image: what the frontend writes

C22 (U15) writes these, and idr-structure-loops recognizes exactly them
(0003 §4.1, D13). Every loop is `scf.for` from `arith.constant 0 : index`
to its bound by `arith.constant 1 : index`, without `unsignedCmp`, its
induction variable an `index` from the start.

| Primitive | Emitted |
| --- | --- |
| `shape x` | per dynamic dimension `tensor.dim %x, %cd`, per static one an `arith.constant`; each then made a natural (section 2) |
| `tabulate e f`, rank k ≥ 1 | `%t = tensor.empty(%e...)` (each dynamic size an extent), then a nest of k loops, loop d carrying exactly one iter_arg of the tensor's type, the first initialized with `%t`, each inner one with the iter_arg of the loop around it; the innermost body computes `f` at the coordinates (the induction variables made naturals), writes `tensor.insert %v into %a[%iv0, ..., %ivk-1]` with the induction variables in nest order, and yields it; each outer body yields its inner loop's result. Bounds are the extents or `tensor.dim` of the destination. |
| `tabulate e f`, rank 0 | `tensor.empty()` and one `tensor.insert` at `[]`; no loop |
| `x !! i` | `tensor.extract %x[%c...]`, coordinates as section 2 |
| `update x i v` | `tensor.insert %v into %x[%c...]` |
| `foldLast g z x`, no frame | one loop over the last axis carrying the accumulator, init `z`, body: the element `tensor.extract %x[%iv]` combined by `g`, yielded |
| `foldLast g z x`, frame of rank F | a nest of F loops over the frame carrying the destination `z`; the innermost body extracts the accumulator at the frame's induction variables from its own iter_arg, runs the fold loop above over the last axis of `x` from it, and inserts the result at the same indices |
| `scanLast g z x` | the fold's loops, the inner one also carrying a destination `tensor.empty` of the result's shape into which it inserts each accumulator |
| `nest`, `merge` | nothing: the same tensor |
| `reshape` | `tensor.collapse_shape` to rank 1 then `tensor.expand_shape` with `output_shape` operands for dynamic dimensions |
| `take`, `drop` | `tensor.extract_slice` |
| `x ++ y` | `tensor.empty(%n + %m)` (two dimensions, `addi nsw nuw`) and two `tensor.insert_slice`s |
| `pad lo hi v x` | `idr.nat.to_extent` of `lo + n + hi` on naturals, then `tensor.pad` |
| `withArray e v f` | the tabulation of the constant `v`, then `idr.lin.enter` (a thread's head, C15) |
| `read a i` | `idr.lin.use`, `tensor.extract`, `idr.lin.enter` of the same tensor, the pair `Res` |
| `write a i v` | `idr.lin.use`, `tensor.insert`, `idr.lin.enter` |
| `freeze a` | `idr.lin.use` |
| `thaw x f` | `idr.lin.enter` of `x` (a head: a copy where `x` is read after it) |

A body that never returns ends in its crash and yields `ub.poison` of each
iter type (`scf.yield` must end an `scf.for` body). `tensor.generate` and
`tensor.concat` are never written (0003 §4.1). The recognized names and
their arguments are C20's; the library's types C19's.

**Ties** (0003 §4.3, D14). At a function's entry, for each size variable
that indexes two or more array parameters at quantity many, the first
such parameter's dimension gives the variable's value (`tensor.dim`), and
every other parameter indexed by it is replaced by `idr.tie_shape` of it
with that value at that dimension; a size passed as a runtime natural
gives its value through `idr.nat.to_extent` where no parameter has it. A
call's result indexed by the caller's size variables is tied at the call
to the caller's values. A linear parameter is tied after its
`idr.lin.use`.

### 4. `idr.tie_shape`

```tablegen
def Idr_TieShapeOp : Idr_Op<"tie_shape", [Pure, AllTypesMatch<["value", "result"]>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>,
    DeclareOpInterfaceMethods<ValueBoundsOpInterface, ["populateBoundsForShapedValueDim"]>]> {
  let summary = "an array whose dynamic dimensions are the given sizes";
  let arguments = (ins AnyTypeOf<[AnyRankedTensor, AnyMemRef]>:$value, Variadic<Index>:$dims);
  let results = (outs AnyTypeOf<[AnyRankedTensor, AnyMemRef]>:$result);
  let assemblyFormat = "$value `dims` `(` $dims `)` attr-dict `:` type($value)";
  let hasVerifier = 1;
  let hasFolder = 1;
}
```

Written `%y1 = idr.tie_shape %y dims(%n) : tensor<?xf64>`. The identity,
stating that its result's dynamic dimensions are `dims` in order.
- **Verifier:** `dims` has one operand per dynamic dimension of the
  type; a memref operand is not a world-ordered array (its memory space
  is not `#idr.world`).
- **Folds:** with no dims, to `value`; of a `tie_shape` with the same
  dims, to that `tie_shape`.
- **`reifyResultShapes`:** a static dimension's size, a dynamic one's
  operand. So `tensor.dim` and `memref.dim` of the result fold through the
  dialect's canonicalization patterns (`lib/IR/Dialect.cpp:115-117`,
  `memref::populateResolveRankedShapedTypeResultDimsPatterns`, which
  covers both, `M/lib/Dialect/MemRef/Transforms/ResolveShapedTypeResultDims.cpp:207-212`).
- **`populateBoundsForShapedValueDim(value, dim, cstr)`:**
  `cstr.bound(value)[dim] == ` the dimension's operand (dynamic) or size
  (static), and `cstr.bound(value)[dim] == cstr.getExpr(getValue(), dim)`,
  as upstream's `tensor.empty` and `tensor.cast` models do
  (`M/lib/Dialect/Tensor/IR/ValueBoundsOpInterfaceImpl.cpp:21-33, 97-106`).
  So `ValueBoundsConstraintSet::areEqual` relates two arrays tied to one
  value across a call.
- **Bufferization** (C15's model): reads and writes nothing, its result
  equivalent to its operand; it bufferizes to `idr.tie_shape` of the
  buffer with the same dims.
- **Lowering** (C16): dropped, the result replaced by its operand.
- Generated Idris builder `tieShapeOp`. Not a primitive.

Needs, in U01's files: `include/idr/IR/IdrDialect.h` includes
`mlir/Interfaces/ValueBoundsOpInterface.h` before the generated ops
(beside `InferTypeOpInterface.h`, `IdrDialect.h:23`); the coordinator's
`lib/IR/CMakeLists.txt` links `MLIRValueBoundsOpInterface` into IdrIR.

### 5. The world-ordered ops

Kept, with their mnemonics, assembly formats, operands (`i64` sizes and
indices, the world in and out), `Idr_Primitive` (Idris constructors
`ArrayNew`, `ArrayGet`, `ArraySet`) and `Idr_PerformsIO`, and declaring
C05's `Idr_FlowOpInterface` (the class `Idr_ArrayOp` lists
`DeclareOpInterfaceMethods<Idr_FlowOpInterface>`; `IdrArrayOps.td`
includes `idr/IR/IdrFlow.td`; the `getFlowEdges` bodies are U02's, in
`lib/IR/Flow.cpp`, C05's table):
`idr.array.new`, `idr.array.get` (with its `moves` property),
`idr.array.set` (`IdrArrayOps.td:45-113`). Their verifiers, `sameElement`
(`include/idr/IR/Canon.h`), the move-out canonicalization
(`ArraySetOp::getCanonicalizationPatterns`, `canon::addMoveOutPatterns`)
and `idr.array.new`'s `reifyResultShapes` are kept. Their types are
`Idr_ArrayType` / `Idr_ArrayValue`: world-ordered arrays only. An access
keeps its primitive's `idr.check.in_bounds` (0003 §13): the runtime's
meaning of an access outside the array.

**Effects** (0003 D24), on the op's own memref, never on the IO resource:

| Op | Effects (`SideEffects::DefaultResource`) |
| --- | --- |
| `idr.array.new` | `Allocate` and `Write` on its `array` result |
| `idr.array.get` | `Read` on its `array` operand; with `moves`, also `Write` on it (the place is emptied) |
| `idr.array.set` | `Read` and `Write` on its `array` operand (the old element is read to release it) |

The world operand keeps their order with every other effect. The same
rule binds the other ops on world-ordered arrays, U01's
(`include/idr/IR/IdrIOOps.td`, `lib/IR/OpsPlatform.cpp:66-95`):
`io.buffer_load` `Read` on `buffer`; `io.buffer_store` and
`io.buffer_set_string` `Write` on `buffer`; `io.buffer_copy` `Read` on
`src`, `Write` on `dst`; `io.buffer_get_string` `Read` on `buffer` and
`Allocate` on `str`; `io.write_bytes` and `io.read_bytes` keep `Read` and
`Write` on the IO resource (they transfer to a handle) and add `Read`
(write_bytes) or `Write` (read_bytes) on `buffer`. After this, no op
calls `idr::ioEffects` (`lib/IR/Effects.cpp:58-65`), which goes (U01).

Consequences the readers of effects take (U01's files):
- `idr::performsIO` (`lib/IR/Effects.cpp:71-111`) is false for these
  ops and `idr::onlyAllocates` stays false: a world-ordered access is
  something, not IO and not free.
- The move-out (`lib/IR/Canon/MoveOut.cpp:36-44`) asks whether an op
  between the read and the write may read the array: an effect `Read`
  on the IO resource (an IO op or call may reach any cell it is given),
  or a `Read` or `Write` on a value whose type is the array's type, or
  effects it cannot know, or a force inside.

### 5b. No buffer op of ours

No array op of this dialect allocates or writes a value array's buffer:
the owned stage keeps upstream `memref.alloc` and `memref.store`, graded
through U01's ownership ops (C14). There is no `idr.array.alloc`,
`idr.array.put` or `idr.array.take`.

### 6. Deleted

`idr.array.generate`, `idr.array.fold` (`IdrArrayOps.td:115-185`), the
class `Idr_BodyRegion`, and in `OpsArrays.cpp` everything only they need:
`verifyWord`, `verifyLoopEnd`, `parseLoopBody`, `printLoopBody`, their
parse, print, verifiers, `reifyResultShapes` and effects
(`OpsArrays.cpp:39-70, 173-297`). No primitive of the dialect has a region
after this, so the generated Idris module has no `IdrRegionPrim`,
`regionArity`, `regionOp`, `ArrayGenerate` or `ArrayFold`
(`compiler/src/IdrisMLIR/Dialect/Idr.idr:2028-2045`). The include of
`IdrIOOps.td` in `IdrArrayOps.td` goes (nothing there uses it).

Uses of the deleted ops their owners delete: `lib/IR/Regions.cpp:48-55,
118-158, 175-186` and `include/idr/IR/IdrMatchOps.td:63-73` (the yield's
`ParentOneOf` and comment) (U01); `lib/IR/Verify/Uses.cpp:106-116`,
`include/idr/IR/Ownership.h` `isArrayLoop`, `lib/IR/Verify/OwnedRegions.cpp:55-96`,
`include/idr/IR/Verify.h` `walkArrayLoop` (U01); the callers of
`isArrayLoop` in `lib/Analysis/Ownership/` and `lib/Transforms/Ownership/`
(U08); `lib/Analysis/Labels.cpp:199-221`, `lib/Transforms/Defunctionalize/Moves.cpp:40-66`,
`Keys.cpp:250` (U02); `Defunctionalize/ByName.cpp` (U05);
`lib/Conversion/ArrayLoops.cpp`, `ArrayLoopReads.cpp` (U10);
`lib/Transforms/Expect/PureArrayLoops.cpp` (U17); the registry's
`ArrayLoop` (U14).

### 7. idr-structure-loops

The pass is C12's `IdrStructureLoops` (`idr-structure-loops`, anchored on
`::idr::FuncOp`, statistics `numParallel "parallel"` and `numReductions
"reductions"`, dependent dialects linalg, tensor, arith), row 7 of the
pipeline: nested on each `idr.func`, after symbol-dce, before empty-tensor
elimination and bufferization.

`include/idr/Transforms/StructureLoops.h`:

```cpp
namespace idr {
#define GEN_PASS_DECL_IDRSTRUCTURELOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::structure {

// Whether idr-structure-loops rewrites `loop`, an scf.for: a nest it makes
// one linalg op, or a fold it makes a reduction. False for any other op.
bool structurable(mlir::Operation *loop);

} // namespace idr::structure
```

`idr::structure::structurable` is the one test: the pass rewrites exactly
the loops it answers true for, and C24's `structured-loops` asks it. The
generated constructor is `idr::createIdrStructureLoops()`.

**The driver.** One `mlir::walkAndApplyPatterns` over the function
(post-order, no fixpoint, no folding, new ops not revisited), one pattern
on `scf::ForOp`. Each loop is decided once (0003 D26). The pass never
refuses and never fails: a loop no form matches stays as it is.

**Only computes** is `idr::onlyAllocates(op)` (`include/idr/IR/IdrDialect.h:84-87`):
every op it walks has no effects or only allocates its results; a call
only computes when its `effects` are present and none (`lib/IR/Func/Call.cpp:76-96`).
A crash, a guard, the world, an `idr.force` or a call that may do
anything is not.

**A nest** of depth k ≥ 1 rooted at `scf.for` L0: loops L0 ... Lk-1, each
from constant 0 by constant 1 without `unsignedCmp`, each with exactly
one iter_arg, all of one `RankedTensorType` T of rank k; L0's init is the
nest's destination D; Ld+1's init is Ld's iter_arg and Ld's body ends in
Ld+1 then `scf.yield` of its result; Lk-1's body ends in
`%n = tensor.insert %v into %a[%iv0, ..., %ivk-1]` (the induction
variables in nest order) then `scf.yield %n`. An iter_arg's other uses
are only `tensor.dim` and, in the innermost body, `tensor.extract` of it
at exactly the insert's indices (the destination's element). Every op of
the nest's bodies only computes; an op between two loops also holds no
region and gives no shaped value. Every dimension is written:
`ValueBoundsConstraintSet::areEqual(ub_d, {D, d})` holds for each d.

**A fold** is `scf.for` F from constant 0 by constant 1 without
`unsignedCmp` with exactly one iter_arg whose type is a builtin integer or
float; its body only computes. Its combiner is **one integer op** when
the iter_arg's type is an integer, the yield is `arith.addi`, `muli`,
`andi`, `ori`, `xori`, `minsi`, `minui`, `maxsi` or `maxui` of the
iter_arg and another value (either order), without overflow flags (an
op marked `nsw` or `nuw`, reassociated, could overflow where the program
did not), and that op is the iter_arg's only use (0003 §6 case 1, D15).

**Lifted reads.** A `tensor.extract %x[%e...]` directly in the body that
is cloned, `%x` defined above L0 (or above F for B), every index a
distinct dimension of the op being made, and each indexed dimension of
`%x` equal (`areEqual`) to that dimension's extent, becomes an input with
the map `(d...) -> (e...)` (a projected permutation; 0003 §4.2). Any other
read stays a `tensor.extract` in the body, a gather. Offset reads
(`x !! [<i + 1]`) stay gathers in this wave.

The forms, tried at a loop in this order:

| Form | Matches | Becomes |
| --- | --- | --- |
| C | a nest whose inserted value is a fold F in the innermost body with a one-integer-op combiner, F's bound defined above L0, and a lifted read indexed by F's induction variable whose dimension equals F's bound | the inits (D itself when F's init is the destination's element, else a parallel `linalg.generic` into D computing F's init per element), then one `linalg.generic` over [parallel × k, reduction] with the inits as `outs` (map `(d0..dk) -> (d0..dk-1)`), its body the needed nest ops, F's body with F's iter_arg the output element and F's induction variable `linalg.index k` |
| D | a nest that C does not take whose inserted value is a fold F in the innermost body, F's bound defined above L0 | the inits as for C, then `scf.for %j` over F's bound carrying them, its body one parallel `linalg.generic` over the frame (`outs` the carried tensor) whose body is the needed nest ops and F's body with F's iter_arg the output element and F's induction variable `%j` |
| A | any other nest | one parallel `linalg.generic`, `outs` D (identity map), its body the needed nest ops and the innermost ops but the insert, the destination's element the output element, each induction variable `linalg.index d` |
| B | a fold F with a one-integer-op combiner and a lifted read indexed by its induction variable whose dimension equals its bound, unless F is the inserted value of a nest that C or D takes | `tensor.from_elements` of F's init, one `linalg.generic` over [reduction] into it (map `(d0) -> ()`), `tensor.extract` of its result at `[]` |

In C and D the nest's ops that F's body or F's init need hold no region
and give no shaped value, the destination's element is read only as F's
init (the output element stands for the accumulator there), and F's init
is that element, a value defined above L0, an induction variable of the
nest, or the nest's scalar code (a read included, which the inits' op
reads in its body). D keeps each element's combine in index order
and only makes the frame parallel: it is legal because every body only
computes, and it is the form in which a fold over a frame computes on
lanes (spectral-norm-linear, 0003 §17 stage 1), which is why a fold's
iter_arg is a builtin integer or float, the vectorizable element types
(0003 §4.5). A float fold is never a reduction iterator.
Needed ops are cloned in program order; the rest, which only compute, go
with the loops. `numParallel` counts each loop rewritten as form A or D,
`numReductions` each rewritten as form B or C.

**Invariants.**
- After the pass, `structurable` is false for every loop in the function.
- The pass reads no other function, changes nothing outside its
  function, writes no attribute, and makes no name.
- It leaves every `scf.for` it does not match exactly as it was: scans,
  slice insertions (a tabulation of cells), accumulations, folds over a
  frame whose bound is not above the nest, loops with more than one
  iter_arg, and every loop whose body does more than compute.

### 8. Consumers

- **U01:** section 1's `isArray`, `isRank1Array` and the two constraint
  descriptions; `QType::verify` for tensors; section 4's include;
  section 5's effects on the IO and buffer ops, `ioEffects` deleted,
  `does()` and the move-out as stated; section 6's deletions in
  `Regions.cpp`, `IdrMatchOps.td`, `Verify/`; the type graph and knots
  on world-ordered arrays only; idris-mlir-tblgen generates
  `#idr.world`'s syntax and the two new builders and no region
  primitive.
- **U02:** the deleted ops gone from the label solve and the slots; the
  flow interface (C05) declared on `idr.array.new`, `get` and `set`,
  whose element moves through the element anchor of the array's type;
  `idr.tie_shape` and `idr.nat.to_extent` carry no closure.
- **U05:** `ByName.cpp` without the deleted ops.
- **U06:** row 7 of C12; `Pipeline.h` includes `StructureLoops.h`.
- **U07:** the vectorization schedule meets the generics of section 7:
  parallel ones (forms A, D, inits) and reductions over integers (B, C).
- **U08:** the callers of `isArrayLoop` gone; the memory passes meet
  `scf.for` over buffers and `linalg.generic` on buffers, of any element
  (C14, C15).
- **U10:** world-ordered arrays lowered as today, the memory space
  `#idr.world` among their type's facts; `idr.nat.to_extent` lowered;
  `idr.tie_shape` dropped; `ArrayLoops.cpp` and `ArrayLoopReads.cpp`
  deleted.
- **U12:** `idr.tie_shape`'s bufferization model; value arrays as
  section 1 says.
- **U14, U15:** section 3's image; section 1's types, `#idr.world` on
  every world-ordered memref; section 2's conversions; the ties; no
  `ArrayLoop` and no region primitive.
- **U17:** `structured-loops` asks `structurable`; `moves-out` reads
  `ArrayGetOp::getMoves()`; fixtures per form and for `idr.tie_shape`.
- **U18:** programs; nothing of this contract is an option.
