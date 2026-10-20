<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0009: a typed array language, MLIR first

**Status (2026-10-19, read at 77eaa5b1):** open. Stage 1 is built (the
pipeline cutover c7aa7b62 and 5d5f3312, reshaped by the representation
waves bfdcac70 and 2c042728; their last texts at 484d6403) and has run
in every suite on arm64 macOS since 2026-10-18. Its open failures are
audits/bugs.md's arrays lane, not this file's. What remains: two walls
recorded at `make self` (SELF-HOST, no gate), stage 1's bench margins
with 0006's G1, and stages 2 to 8, all **AFTER-SELF**, queued after
sharding (0007's P1, P2 and P4, with 0008's S-stages); stage 8 also
needs 0007's P4. **First step: stage 2** (static extents, buffers in
data-type bodies), taken when the queue reaches it; it waits on nothing
unbuilt. A stage is done only when it passes on every target. Where the
cutover's design governs a topic (pipeline order, promises as facts of
library types, names from content, refusals as data, budgets that never
reject, measurement, the upstream queue), this file states only what
arrays add. Claims are marked read, measured, recalled, conjecture or
decision. `M/` is the pinned MLIR source, `.toolchain/llvm-project/mlir/`,
and `L/` is LLVM beside it; line numbers are the pin's, and a toolchain
bump moves them.

**The ruling.** Every fact Idris proves about an array has exactly one
image in MLIR, the one upstream already optimizes on:

- a shape is a ranked tensor type;
- a size the program fixes is a static dimension;
- a typed index is an access with no guard;
- a linear thread of writes is a destination-passing chain that One-Shot
  Bufferize puts in place;
- an unordered combine is a structured reduction;
- a sparse format is a `#sparse_tensor.encoding`.

An op, type or pass of ours exists only where upstream has none, and
each names the gap it fills (§19). The array style is the compiler's
organizing principle, but the compiler's own Idris also runs on the stock
host, so it never reaches the `%extern` generating set. The frontend's
and the fork's kernels (0010's, 0011's O6) use the library's plain-Idris
layer (D45), and 0011's tables and 0015's joins are plain Idris over
base. Only programs, 0012's layouts among them, compile through the ops
directly.

## What remains

| item | depends on | when |
|---|---|---|
| The arrays stage's wall and the price of the IOArray double check, both on the self-compile (§7, §13) | `make self` | **SELF-HOST** (recorded, no gate) |
| Stage 1's bench margins: array programs, an array of boxes, the IOArray programs (§16) | 0006's G1 | AFTER-SELF |
| Stage 2: static extents, buffers in data-type bodies, dependent rewrites | nothing unbuilt | AFTER-SELF, the first step |
| Stage 3: fusion and schedules, plus the library vocabulary its proofs use | stage 1 (stage 2 for unmasked vectors) | AFTER-SELF |
| Stage 4: order | stage 3 | AFTER-SELF |
| Stage 5: index sets, data-dependent shapes, shape arithmetic, D12 | stage 1 | AFTER-SELF |
| Stage 6: sparse | stage 3, U2 | AFTER-SELF |
| Stage 7: relations, the compiler's consumers, and the plain-Idris layer they use (D45) | stage 6; 0011's typed ids; 0015's boundary | AFTER-SELF |
| Stage 8: multicore | stage 3; 0007's P4 | AFTER-SELF |

## 1. Stage 1, built

`libs/mlir-array` (`Array/Core.idr`'s bodiless generating set,
`Array.idr`, `Linear/Vec.idr`); the generating ops
(`foreign/idr/include/idr/IR/IdrArrayOps.td`, emitted by
`compiler/src/IdrisMLIR/Emit/Tensors.idr`); `idr-structure-loops`,
`idr-columns`, `idr-bufferize` through patch 24, immortal constants,
world-ordered memrefs, the vectorization schedule and `idr-narrow-lanes`
(`foreign/idr/lib/Transforms/` and `lib/Conversion/Arrays.cpp`); the
fork's `Table` on base's `Data.IOArray` (D38); the properties
`structured-loops`, `typed-reads`, `in-place` and `fused`
(`lib/Transforms/Expect/`). §8's release model holds on the suites
(k-nucleotide's table is written in place, cd40ab41).

## 2. The correspondence

There is one row per thing Idris proves or the program states. The
middle column is its one image in MLIR. The last column is what checks
or uses it, upstream's mechanism wherever there is one. Every later
section works out one or more rows.

| Idris | MLIR | checked or used by |
|---|---|---|
| `Array s a`, the rank of `s`'s form | `tensor<d0 x ... x E>`, one dimension per `:<` | the tensor verifier; linalg's indexing maps |
| an extent the program fixes | a static dimension | `tensor.dim` and `tensor.cast` folding; static vectorization |
| an extent at quantity 0 | a dynamic dimension, read back with `tensor.dim` | `reifyResultShapes` and the dim folds |
| an extent at quantity many (`Extents s`, `{n : Nat}`) | a natural, narrowed to `index` where it sizes an allocation (guarded) | `ValueBoundsOpInterface` |
| two arrays indexed by one size variable | dimensions tied by `idr.tie_shape` at the function's entry | `ValueBoundsConstraintSet::areEqual` across calls (§4.3) |
| `n + m`, `n * m` in a shape | `arith` with `nsw nuw` on `index`, or `affine.apply`; `n * m` kept as two dimensions where the type has two | value bounds; never the `index` dialect, which it does not model |
| `Index s` | an `index` per axis at the access; `linalg.index` inside a structured op | no guard; transfers `in_bounds = [true]` |
| a bare `Fin n` with no array | a natural | `idr-narrow` |
| `x !! i`, `update x i v` | `tensor.extract`, `tensor.insert` | One-Shot's in-place analysis |
| a linear thread (`LArray s a` at quantity 1) | `!idr.lin<tensor<...>>`, a destination-passing chain | One-Shot; each link `mustBufferizeInPlace` (§8) |
| a word or float element | the builtin element type | vectorization |
| an element of ours (box, string, natural, sum) | `tensor<?x!idr.T>` | tiling, fusion, bufferization; never vectorized (§4.5) |
| a record element | one tensor per field | multi-result `linalg.generic` (§4.5, 0012) |
| an array of arrays of one cell shape | one tensor, the dimensions concatenated | `expand_shape`, `collapse_shape` |
| a rank no analysis fixes | nothing: `unsupported (polymorphism)` naming the site | the request relation on data instances (`Frontend/Translate/Types.idr`, `Refusal`) |
| a combine whose order is unobservable | a `linalg` reduction iterator (§6) | upstream's tiling, split-reduction and vectorization |
| a combine whose order is observable, or a body with effects | an ordered loop (`scf.for`) | nothing reorders a loop-carried value |
| a pure body | `linalg.generic` (named op where it specializes) | fusion, tile-and-fuse, vectorization |
| `SArray fmt s a` | `tensor<..., #sparse_tensor.encoding<...>>` | the sparsifier, codegen mode (§9) |
| a relation | an `i8` sparse tensor with `explicitVal = 1` | co-iteration (§10) |
| a semiring element | `i8` (or wider), the zero at 0 | `sparse_tensor` regions (§9) |
| a literal array, a normalized result | `arith.constant dense`, an immortal `memref.global` | constant folding; copy on write (§12) |
| an array a world orders (`IOArray`, `IORef`, `Buffer`) | a `memref` in `#idr.world`, threaded by the world | effects on that memref (§13) |

Erased does not mean constant. An extent at quantity 0 is dynamic unless
the program fixes it. Indexed vectors do not imply contiguous storage:
`Vect n a` stays a list, and contiguity belongs to `Array`.

## 3. The language

`libs/mlir-array` is a trusted library over base and `mlir-linear`
(D1). Its generating set is the only set of functions the compiler
knows by name (D7). The registry reads each one's arity, quantities and
erasure from its declaration. Everything else is plain Idris over the
generating set, and its lowering is what its definition becomes. A
program that reaches the generating set runs under idris-mlir only
(AGENTS.md's two hosts). Code the stock host runs uses the plain-Idris layer of
D45 instead.

### 3.1 Arrays, shapes, frames and cells

Built (`Array/Core.idr`). `Shape = SnocList Nat`, outermost axis first
(D2). The array type is `Array : (0 s : Shape) -> Type -> Type`,
abstract and row-major.

A function on cells of shape `c`, applied to an array of shape
`f ++ c`, is iterated over the frame `f`. Base's `SnocList.(++)`
recurses on its right argument, so Idris's own unifier finds the frame
from the argument alone: this is Remora's division
(`sources/papers/slepak-2018-constraint/paper.pdf`, §3). A primitive
acts on its trailing cells, and the leading axis is reached through
`transpose`, which is an indexing map (D3).

### 3.2 Indices and extents

Built:

- `Extents s` is a singleton: the shape at run time.
- `Index s` holds a `Fin` per axis, so `(!!)` has no runtime check.
- An index computed from integers goes through `(!?)`. Its test is the
  program's own comparison, not a guard.
- Indexing is `!!` at `infixl 10`, which binds tighter than the
  Prelude's `*`.
- Sizes bound at quantity many are runtime values. A function whose
  sizes are erased reads them with `shape`, which becomes `tensor.dim`.

### 3.3 Arithmetic and the interfaces

What remains is **D5**: `Num`, `Neg`, `Fractional` and `Applicative` at
one shape, with the extents found by search
(`%hint arrayNum : Num a => {auto ext : Extents s} -> Num (Array s a)`),
and `Traversable` and `Show`. Overloading across shapes makes
`printLn (1 + 2)` ambiguous (measured), so different shapes meet by a
named function (§3.4). The built `foldMap` is the left fold in index
order, so `sum` adds as `reduce` does. The vocabulary uses names, not
glyphs (D9). Stage 3 writes the parts its proofs use; the rest comes
with stage 5.

### 3.4 The rank operator and agreement

`nest` and `merge` are built. What remains is `over`, `over2` and
`agree`:

- Rank is merge after each after nest. The empty frame is settled by a
  shape calculator `Extents c -> Extents d` that search finds, never by
  running the function on fills (D6).
- Agreement is prefix agreement, read off evidence, never computed from
  lengths. In MLIR the reuse is an indexing map that drops trailing
  dimensions, so nothing is materialized.
- There is no NumPy broadcasting and no size-1 stretching.

### 3.5 The vocabulary

The generating set is built (`Array/Core.idr`): `shape`, `tabulate`,
`(!!)`, `foldLast`, `scanLast`, `nest`, `merge`, `reshape`,
`transpose`, `take`, `drop`, `(++)`, `pad`, `update`, `tabulateIO`, and
`LArray`'s `withArray`, `read`, `write`, `freeze`, `thaw`, `shape` and
`grow`. What remains:

- `accumulate : (b -> a -> b) -> Array t b -> Array s (Index t) ->
  Array s a -> Array t b`, the one generating function left (stage 5).
- The library code over the generating set, each item with the form its
  definition lowers to:
  - idiom brackets (`linalg.map`);
  - `agree`, `over`, `over2` (indexing maps);
  - `scan`;
  - `outer` and `contract` (a generic with a product map, specialized to
    `linalg.matmul` or `linalg.contract`);
  - `permute`;
  - `reverse`, `rotate`, `shift`, `windows` (affine reads);
  - `iota` (`linalg.index`);
  - `ravel` (`collapse_shape`);
  - `filter` and `select` (§4.4);
  - `sort` and `grade` (the library's merge sort on `LArray`);
  - `iterate`;
  - `reduceBlocked` (§6).
- **Under**, which is structural only: a closed set of selections, each
  a lens whose image is `extract_slice` then `insert_slice`. A ragged
  result is `Ragged`, never padded.

### 3.6 Index sets as types (stage 5)

```idris
interface IndexSet ix where
  0 axes    : Shape
  extentsOf : Extents axes
  toIndex   : ix -> Index axes
  fromIndex : Index axes -> ix

data Table : (0 ix : Type) -> Type -> Type where
  MkTable : IndexSet ix => Array (axes {ix}) a -> Table ix a
```

These are Dex's index sets (`sources/papers/paszke-2021-dex/main.tex`,
782-831). The interface takes one parameter and `Table` is a data type
(D8): a two-parameter interface never resolves a product, and a synonym
loses `ix` (measured). A table is an array, so in MLIR an index set is
nothing at all.

### 3.7 Shapes that depend on data, and shape arithmetic (stage 5)

- **Data-dependent sizes.** A size the data decides belongs to the
  array: `filter p xs : Exists (\m => Vector m a)`, held once, in the
  tensor's dimension.
- **Ragged arrays.** `Ragged f a` is a flat vector with an offset per
  row, which is a compressed sparse level's positions array and is
  lowered as one (§9).
- **Unprovable equalities.** An equality the program cannot prove is a
  checked conversion, `resize : (n : Nat) -> Vector m a -> Maybe
  (Vector n a)`.

Most shape facts are concatenation, which reduces. The rest:

1. **Literal shapes** need nothing. Search proves them by computation
   (measured).
2. **Symbolic shapes** are the library's tactic, `Array.Shape.solve`. It
   works by elaborator reflection over a canonical form (concatenation
   flattened, sizes as sums of sorted monomials), with the proof at
   quantity 0. Frex is the precedent
   (`sources/papers/allais-2025-frex/evaluation.tex`). **Decision:** the
   threshold is 1 s per obligation on the corpus's largest shape term.
3. **Views** cover arithmetic patterns, for example `MkSplit : (q, r :
   Nat) -> Split d (q * d + r)`.

Idris's equality is unchanged (D11). The fork's conversion does no
normalization of shape arithmetic, and there is no solver beside the
toolchain. Carrying a `rewrite`'s equality into MLIR starts at stage 2
(§16); its data-dependent part comes here.

### 3.8 Linear arrays (record)

Built (`Array/Core.idr`, `namespace LArray`). A continuation is linear
and returns `!* b`, so a program can hold several linear arrays at once
(measured). Linearity is not ownership. The library supplies the past:
an `LArray` is born fresh (`withArray`, or `thaw`, which copies unless
its argument is dead) and leaves only by `freeze`. `Linear.Vec n a` is
an `LArray [<cap] a` with its size `n`, `LTE n cap`, and
doubling growth (D19). `LArray`'s operations are bodiless `%extern`s
(D37, superseded by the representation wave's D5). The fork's table is
an `IOArray` (D38).

### 3.9 Errors

Shape errors are Idris type errors at the user's line, and the library
names its evidence for the rule (`Agree`, `LTE`, `count`). What remains
is **D12**, with stage 5 (AFTER-SELF): Idris reports a mismatch of two
literal sizes as their unary forms. The fix goes in the fork's unifier
error as the fork's own code, recorded in `PINS.md`, with the diff in
`upstream/<bug>/pull-request.diff`. It is never sent upstream. Nothing
in the tree yet (`upstream/fork-*` has no such entry).

## 4. The generating set, as upstream ops

### 4.1 What the frontend emits (record)

The frontend writes each generating function as its own op, with a
region and an `Iteration` per dimension (`Parallel` or `Ordered`,
`IdrArrayOps.td`). The rest is `tensor` ops: `extract`, `insert`,
`extract_slice`, `insert_slice` (`(++)` is `tensor.empty(n + m)` and two
insert slices), `collapse_shape`/`expand_shape`, and `pad` (D13,
reversed by the representation wave's D6). `tensor.generate` and
`tensor.concat` are not used, because neither has a destination and
both always allocate.

### 4.2 Reads become indexing maps

Built: a read at a projected permutation of the induction variables
becomes an input with that map (`StructureLoops/Forms.cpp`, `readsOf`).
What remains (stage 3):

- **Affine offsets.** Reads at affine offsets, such as `x !! [<i + 1]`
  in `heat`'s stencil or `shift`'s and `windows`' reads.
- **Materialized maps.** `linalg-fold-into-elementwise` and
  `linalg-morph-ops` absorb an explicit transpose or broadcast into the
  consumer's maps.

A read at a computed index stays a `tensor.extract` in the body (§4.4).

### 4.3 Dimensions across calls, and static extents

`idr.tie_shape` is built (D14). It implements `ValueBoundsOpInterface`
and `ReifyRankedShapedTypeOpInterface`, it bufferizes to the same op on
the memref, and `idr-lower` drops it. Narrowing is built too (D4): a
coordinate becomes an exact `index` at its access, and an extent enters
`index` at allocation through `idr.nat.to_extent`, which may crash.

**Static extents through specialization (stage 2, D39).** Where a
caller's tensor is more static than the callee's parameter, the
frontend writes a `tensor.cast` at the call. The cast's source type is
the argument's static pattern, under the binding-time rules. Today's
keys cannot take it yet (read: `lib/Transforms/Specialize/Keys.cpp`):

- "a pattern's type is its position's, so the key holds none";
- "a lone scalar is never a key position".

So a constant `{n : Nat}` never keys, and stage 2 adds a pattern that
holds a tensor type refined toward static. The clone's entry casts to
the static type, and upstream's cast folds carry it into the
destination-style ops (how far through ours is measured, conjecture). A
node the request-chain rule does not make leaves the extent dynamic:
the same program, less optimized.

### 4.4 Gathers, scatters, filters and scans (stages 4 and 5)

Upstream has the dense, regular part and not these, so ops of ours are
allowed here, each naming its gap (D16):

- **Gather** (`select`): a generic whose body does `tensor.extract` at
  the computed index. It needs no op of ours. The vectorizer's n-D
  extract makes it a gather or a contiguous load. `vectorizeNDExtract`
  is off today (`lib/Target/Schedules.cpp`) and is turned on at stage 2.
- **Scatter with a reassociable combiner** (`accumulate`):
  `idr.scatter`, destination-passing, with `TilingInterface` and
  `BufferizableOpInterface`. Gap: `tensor.scatter` has no combiner and
  no bufferization model.
- **Scan with a reassociable combiner**: `idr.scan`, tiled with the
  carry passed between tiles and lowered by the two-pass method. Gap:
  there is no `linalg` scan, and `vector.scan` takes a fixed kind on
  static vectors.
- **Filter and compress**: flags, an exclusive `addi` scan, and a
  scatter without a combiner. Fusion stops there.
- **Sort**: the library's merge sort, never a runtime primitive.

The structuring makes them, never the frontend. It does so only for a
combiner of §6's case 1, or for `filter`'s scatter, whose positions are
distinct by construction. Every other scan or scatter stays ordered.

**Open at stage 4 (representation first):** with the generating ops,
`idr.scan` beside `scan_last` (and `idr.scatter` beside `accumulate`'s
op) is one scan in two ops. Stage 4 first tries giving the generating op
the tiling and destination models itself, with an iteration that
admits any association (the same case as D32's, §6). It adds a second
op only if that fails.

### 4.5 Elements (record)

Built:

- Words and floats are builtin element types and the only ones that
  vectorize.
- Our types tile, fuse and bufferize, through
  `MemRefElementTypeInterface`.
- A closure or suspension is a dispatch sum before any array pass:
  defunctionalization runs first. Its flow uses the element anchor of
  its type, one rule over `ShapedType` (D28). The array ops implement
  `RegionBranchOpInterface`, from which forwarding is derived (D41,
  superseded by the representation wave's D6 and D7).
- A counted element is a tensor element with one path. `memref.copy`
  is the runtime's counted copy (D17).
- A record element is one tensor per field, by upstream's one-to-N
  conversion in `idr-columns` (D44). This is the one representation of
  columns.

What remains is the sum element, which is 0012's to decide (a tag
tensor and one tensor per field slot, or boxes; its F2).

## 5. Effects, order and the structuring (record)

`idr-structure-loops` runs once per function, in parallel, after the
optimizer, on final bodies (D26). A call holds no effects, so the
structuring reads the callee's summary.

- An op whose region does no more than compute and crash, over word
  elements, keeps its parallel dimensions parallel as `linalg`.
- A fold becomes a reduction only for §6's case 1.
- Anything else is an ordered nest (`Forms.cpp`, `formOf`; D10).

The name follows D27. A `linalg` op comes only from a region that
computes and crashes over words, so nothing in one counts. 0007's
lowering of `scf.forall` relies on this (§14). Named ops are recovered
after fusion (`linalg-specialize-generic-ops`, stage 3).

## 6. Reductions

**D15.** Every reduction and scan means its left fold in index order. A
`linalg` reduction iterator means any order, so a fold becomes one in
only three cases:

1. **The combiner is one associative and commutative integer op**,
   without `nsw` or `nuw`. This case is built (`Forms.cpp`,
   `reassociates`).
2. **The combiner is a finite semiring's whose laws the fork proves**
   (`compiler/idris/src/Algebra/`, exhaustively with `Refl`). The fact
   lives in Idris, so the frontend states it (**D32**). D32's first
   image, an `scf.parallel` with an `scf.reduce`, was superseded by the
   representation wave's D6: the frontend writes no `scf`. Its image is
   decided at stage 4. **Default:** a third `Idr_Iteration` case on
   `fold_last`'s last dimension, held by the op itself, which the
   structuring reads as a reduction. It is neither an attribute beside
   the op nor a second op.
3. **The program asks for an order of its own**: `reduceBlocked k`,
   meaning `k` interleaved left folds combined in order. This needs no
   image of its own. It is library code: `reshape` to `[<q, k]`, then
   `transpose`, then a `foldLast` whose frame of `k` is parallel, then
   an ordered fold of the `k`. The structuring already gives the frame
   to the vectorizer.

Every other fold, float sums included, is ordered, so a float result is
the same on every target, lane count and core count. The schedule still
gives a reduction dimension one lane (`Schedules.cpp`), which holds the
order fact a second time. Stage 4 deletes that rule, so integer
reductions get lanes and the iterator is the one place the fact lives.

## 7. The pipeline

The arrays stage is built (`foreign/idr/lib/Transforms/Pipeline.cpp`):

1. after `idr-columns`, then canonicalize and cse, then
   `remove-dead-values` and `symbol-dce`: `idr-structure-loops` per
   function;
2. `idr-bufferize` on the whole program, which eliminates empty tensors
   itself;
3. canonicalize and cse;
4. then the memory passes.

The vectorization schedule and `idr-narrow-lanes` run after `idr-entry`,
before `convert-linalg-to-loops`.

The stage sits where D26 puts it, for these reasons:

- tiling must follow every inlining;
- structuring reads final effects;
- `remove-dead-values` must see `scf` loops before structuring hides
  them;
- the inner per-function pipeline stays its fixed list.

What remains:

- **Stage 3**, between structuring and bufferization, per function:
  `linalg-generalize-named-ops`, `linalg-fuse-elementwise-ops`, the
  tile-and-fuse `transform-interpreter`, and
  `linalg-specialize-generic-ops`.
- **Stage 6**: `sparsification-and-bufferization` replaces
  `idr-bufferize`'s driver for every module. The stage of the plan
  decides which bufferization runs, never the module's content (D30).
- **SELF-HOST measurement.** One-Shot's module analysis is
  whole-program and serial (with patch 24, cycles to a fixpoint), and
  the buffers retype walks every function. Their wall on the self-host
  module is recorded at `make self` and held to D35's compile-time
  threshold from then on (conjecture: a function without a tensor costs
  one walk). The frontend imports no `mlir-array`, so the stage runs
  there on world-ordered memrefs alone.

### 7.1 Schedules are IR

Schedules are transform scripts in one library of ours, loaded once per
context and interpreted per function in parallel. They read the
target's facts from the module's DLTI (D20, D29). The vectorization
schedule is built, reading `max_vector_op_width`, which `idr-target`
writes from LLVM's answer for the entry's CPU (`lib/Target/Schedules.cpp`,
`include/idr/Target/ScheduleOps.td`, `Target.h`). Its one op,
`transform.idr.vectorize_lanes`, fills a gap: a transform param admits
no arithmetic, so no script can compute `W / widest` (§19).

What remains (stage 3):

- **The tile-and-fuse schedule**: `tile_using_for` or
  `tile_using_forall`, `fuse`, `fuse_into_containing_op`, with tile
  sizes from `L1_cache_size_in_bytes`.
- **The L1 size as a fact of each target's entry in `CMakeLists.txt`**,
  beside the page size, because LLVM answers it for x86 only: 32 KiB for
  `x86-64-v3` (LLVM's answer) and 128 KiB for `apple-m1` (recalled).
  Stage 3's parity rule is what changes them.

That one shared library is safe under parallel interpretation is a
conjecture, checked with 0006's G1 by the determinism check
(`harness/lib/determinism.sh`) and a ThreadSanitizer run. A race there is upstream's to fix.

### 7.2 Fusion (stage 3)

Fusion is upstream's elementwise fusion with its default control (fuse
a producer with one use, duplicate nothing), plus producer-consumer
fusion through the tile-and-fuse schedule. The `fused=@f` property is
built (`lib/Transforms/Expect/Fused.cpp`). The proofs, in order:

1. `map f (map g x)` is one generic;
2. then `softmax` and `matmul`;
3. then a producer with two consumers is not duplicated.

## 8. Bufferization and grades (record)

Built (`lib/Transforms/Bufferize/`; D18):

- **The module driver.** One-Shot runs on `idr.func` before counting,
  through patch 24 (U1, U4, §19). Upstream's own function models are
  attached to `idr.func`, `idr.call` and `idr.return`. Allocation is the
  runtime's cell and `memref.copy` the counted copy. There is no
  ownership-based deallocation.
- **Linear values.** The grade is the wrapper `!idr.lin<tensor<...>>`,
  never the tensor's encoding, which sparse needs.
  - `idr.lin.enter` is a release: it copies exactly when its buffer is
    read again or is not writable.
  - `idr.lin.use` is a writable root.
  - A link, an enter whose buffer a use began, is
    `mustBufferizeInPlace`, so a copy there is an internal error, never
    `unsupported` (D33, `Linear.cpp`).
  - A linear array read from a cell is a writable root, because the
    store was its release (`Data.cpp`).
  - The canonicalizer's enter/use folds hold for every linear value, so
    links survive only at a thread's boundaries (D43,
    `lib/IR/OpsScalars.cpp`).
- **After the rewrite.** Every remaining tensor inside a wrapper, body
  or signature becomes its cell's buffer in one retype (D42,
  `Bufferize.cpp`, `DataRemap` kind `buffers`).

What remains is stage 2's buffers-in-bodies design (§16), which deletes
D42's retype and the reason the release and link models exist.

## 9. Sparse arrays and semirings (stage 6)

A sparse array is the dense type with an encoding, not a second kind of
array (D21):

```idris
data Level = Dense | Compressed | Singleton | LooseCompressed
record Format (s : Shape) where
  levels : Vect (rank s) Level
  order  : Permutation (rank s)

export
data SArray : (0 fmt : Format s) -> (0 s : Shape) -> Type -> Type
interface SparseElement a
```

`fmt` is erased and monomorphised into the tensor's encoding, so CSR,
DCSR, COO and CSF are formats of one type, and the sparsifier decides
the loops.

- **Meaning.** It is the dense array with the semiring's zeros. The
  library gives each lifted function its absent cases (`f 0 0`,
  `f x 0`, `f 0 y`) as the regions of `sparse_tensor.binary` and
  `unary`.
- **Codegen only.** `enable-runtime-library=false`. The library never
  emits `sparse_tensor.new`, `out` or `print`, which call the C runtime;
  the module verifier refuses one as an internal error. Storage growth
  is `memref.realloc` on the runtime's allocator.
- **Elements.** A sparse element must be a primary type
  (`isValidPrimaryType`; `i1` is not one). Every function that makes an
  `SArray` asks for `SparseElement a`, so another element is an Idris
  type error at the user's line, never `unsupported` (D31).
- **Semirings as `i8`.** The additive zero is at 0, because
  `implicitVal` supports only 0. The encoding comes from the `Semiring`
  instance, not from tag order (`SizeChange`'s `plusNeutral` is
  `Unknown`).

| semiring | encoding | plus | times |
|---|---|---|---|
| `ZeroOneOmega` | `Rig0 = 0`, `Rig1 = 1`, `RigW = 2` | `minui(addi(a, b), 2)` | `minui(muli(a, b), 2)` |
| `SizeChange` | `Unknown = 0`, `Same = 1`, `Smaller = 2` | `maxui(a, b)` | `minui(muli(a, b), 2)` |
| Boolean | `0`, `1` | `ori` | `andi` |
| counting | the integer | `addi` | `muli` |
| min-plus | `i64`, dense (its zero is infinity) | `minsi` | `addi` |

**Storage.** Value arrays live in a library record. Use is
`sparse_tensor.assemble`, which checks nothing, so the library's
constructors prove its invariants; results are `disassemble`d into
fresh cells. **Measurement:** if `disassemble`'s copies exceed 5% of
spmv's time, U3. A linear sparse array is not offered.

## 10. Relations as sparse arrays (stage 7)

A relation is a sparse array of Booleans (`explicitVal = 1`, so only
coordinates), and a conjunctive query is an einsum.

| relational | sparse array |
|---|---|
| an index | a format (CSR is a two-level trie) |
| a join | co-iteration on the shared variable |
| an aggregate | a contraction in the matching semiring |
| a selection | `sparse_tensor.select` |
| a semi-naive delta | `binary` with an empty overlap |
| a recursive query | the delta's fixpoint, an `scf.while` |

Coordinates are dense integers, so 0011's typed ids are this section's
precondition. The subset is plans fixed at compile time. Co-iteration is
linear in the sum of the two sizes, so it is not worst-case optimal.
**The boundary** (D22): a plan that fits is a sparse array program.
Everything else is 0015's: lazy or hash tries, Free Join, galloping,
statistics, plan variants, the database. 0015's interpreter never
offers a second route for a plan that fits.

## 11. The compiler's own consumers (stage 7)

The frontend and the fork run on both hosts, so each kernel below is a
D45 plain-Idris definition, and the array op is idris-mlir's faster
lowering of it:

- **0011's multiplicity check** is a fold in the 0/1/ω semiring over
  occurrences grouped by binder, a CSR level. Its op is
  `sparse_tensor.reduce` over `i8` (§6's case 2).
- **Size-change composition** is a semiring product over DCSR. The
  fork's `Libraries/Data/SparseMatrix.idr` is already DCSR in lists and
  is the layer's starting point. The closure `loopsTerminate` keeps only
  the weakest graphs per function, so it is a relational fixpoint with
  subsumption, which is 0015's (its D9). The elaborator's
  `calcTerminating` triple closure, a second copy of the analysis, is
  deleted for it (0013 D13, 0011's O6 and D11).
- **0010's kernels** are gathers, scatters, filters and `addi` scans
  (§4.4), with no whole-array runtime primitive. They extend the layer
  with what they use, in 0010's stage.

0011's tables are plain Idris over base (0011 §1), as the fork's `Table`
is (D38). **0012's layouts** serve programs: arrays of records and of
sums are columns by representation (0012 D3, D6, D12).

## 12. Constants and static normalization (record)

Built (D23, D40): a literal array of word or float elements is
`arith.constant dense`. It bufferizes to a non-writable `memref.global`
named from its content, with a persistent cell header in front of the
data. An array's lowered value is one pointer, its cell, so a constant
is a cell like any other and a write copies it
(`lib/Conversion/Arrays.cpp`, `LowerGetGlobal`). A constant of any other
element is built at startup.

0010's static normalization is the later producer of closed array
results. It runs as this lowering compiles them, never as a second
implementation.

## 13. Arrays a world orders (record)

Built (D24): `IOArray`, `IORef` and `Buffer` are memrefs in `#idr.world`,
threaded by the world. Each op declares its effects on its array, not on
the IO resource (`IdrArrayOps.td`, `Idr_ArrayOp`). Their accesses keep
the primitive's guard.

With `idr-in-bounds` gone, base's `IOArray` checks an index and the
primitive checks it again. Two measurements remain:

- **SELF-HOST, recorded:** the self-compile's wall at `make self` prices
  the double check on the fork's context table.
- **AFTER-SELF, with G1:** fannkuch-redux and the `Buffer` programs
  within D35's 2% of the 2026-10-13 record. If they miss it, the fix is
  a local pattern relating `newArray`'s size to `memref.dim` for value
  bounds, never the Presburger engine.

## 14. Multicore, and devices later (stage 8)

After 0007's P4, the tile-and-fuse schedule tiles a parallel dimension
of a structured generic with `scf.forall`, and only 0007 §8 lowers it
(a fork per shard and a join). `shard.grid` supplies only the grid and
the running index (0007 §7.3). `sharding-propagation` and
`shard-partition` come in only through 0007's P5, replacing that
lowering whole. A reduction across shards is legal exactly when §6 says
its order is not observed. Devices are a later target entry through the
same tensor level.

## 15. Rules of AGENTS.md it keeps

- **Idris does types; MLIR does programs.** The frontend chooses ranked
  types and writes each primitive's meaning. Parallelism, fusion and
  in-place writes are decided in MLIR.
- **One thing, one representation.** One array type, one loop meaning
  (the generating op, structured where pure), one in-place analysis, one
  representation of columns, one answer for constants, one reduction
  policy, one schedule library.
- **No fact in a discardable attribute.** `bufferization.writable` is
  derived just before the pass that reads it.
- **A megamorphic rank is `unsupported`.** A case the types rule out is
  a type error, and a state no program reaches is an internal error.
- **Every target.** Nothing per target outside the entry, and there is
  no sparse runtime library, `library_call`, OpenMP or async runtime.
- **An upstream gap is fixed upstream** (§19).

## 16. Staged plan

Every stage passes `make check`, `make build`, `make test`, `make
test-idr` and `make test-mlir-tools` on every target, with the
determinism check (`harness/lib/determinism.sh`).

**Stage 1's measurements**, AFTER-SELF, with 0006's G1 (its suites run;
their failures are audits/bugs.md's):

- the array programs of `bench/` within D35's 2% of the 2026-10-13
  record;
- an array of boxes priced, to settle §20 item 1;
- §13's IOArray programs.

**Measurement** (D35, D36) is the cutover's rule: binary against binary,
the commit before the stage as baseline, run beside each other on each
target. No runtime regression over 2%, no compile-time regression over
5%, and parity with C means this compiler's best of five at most 2%
above the C's. A stage that misses is reworked or reverted whole. New
benchmarks get a C counterpart, their `main.c`, and no Chez column; none
exists yet:

- `matmul` (1024, f64, `ikj`);
- `heat` (a 2-D five-point Jacobi step, 2048², 100 steps);
- `spectral-norm-dense`;
- `prefix-sum` (10^8 i64);
- `histogram` (10^8 bytes into 256 bins);
- `spmv` (CSR, a SuiteSparse matrix vendored under `sources/`).

The stages, each AFTER-SELF:

2. **Static extents** (§4.3, D39), with two designs moved here from
   the total wave's proposal (its full text at b843d8b5, §5 item 7).
   The work:
   - the key's typed pattern;
   - `vectorizeNDExtract` on;
   - the cast propagation measured;
   - **Buffers in data-type bodies.** Today a field that holds an array
     is `tensor<…>` or `!idr.lin<tensor<…>>` in its data type's body.
     A body is set once, so after One-Shot, `idr-bufferize` remakes
     every data type whose body holds a tensor, and every type holding
     one of those (`DataRemap` kind `buffers`), then retypes every
     function. The target is that no body holds a tensor:
     - from the frontend on, a field of array type is the array's cell
       buffer at its grade;
     - `idr.con` takes the tensor and `idr.field` gives one, each the
       bufferization boundary `to_buffer`/`to_tensor restrict` is (the
       store a release, the read not writable);
     - the data-type verifier refuses a tensor in a body;
     - the world stays no tensor, and a suspension's value follows the
       rule of a field.

     It changes Emit's array fields, the verifier, `idr.con` and
     `idr.field`'s operand and result rules, and the store and heap-read
     models. `!idr.lin<T>` then becomes tensor-like where `T` is
     (submission 27's `tensorAllocationFn`,
     `upstream/27-one-shot-tensor-like-copy`, and a per-instance
     `extraClassOf` on `TensorLikeType`/`BufferLikeType`), and One-Shot
     bufferizes signatures and linear wrappers itself. It deletes the
     remap pass, its `toBuffer` leaf, `heldType`, the retyping loop
     (D42), and the reason the release and link models exist (§8).
     **Stage-2 decision to take:** it reverses §8's reason for keeping
     `QType` off `TensorLikeType`, that an interface belongs to the
     class, since `extraClassOf` makes it per instance. It also turns
     §20 item 2's fallback around.
   - **Dependent rewrites.** A `rewrite`'s equality is carried into
     MLIR, so that shape facts survive specialization. The
     data-dependent part waits for stage 5.

   Proof:
   - a fixture with static dimensions through a specialization node;
   - `vectorized` without masks on static programs;
   - `spectral-norm-dense` at spectral-norm-linear's ratio to C;
   - a dialect fixture for stage 1's immortal-constant lowering, which
     has none yet;
   - for the buffers design, no body holding a tensor after the
     frontend, and the suites unchanged.
3. **Fusion and schedules** (§7, §7.1, §7.2, §4.2). Generalization,
   elementwise fusion, tile-and-fuse, specialization of generics, the L1
   fact in each entry, affine-offset reads, and the vocabulary these
   proofs use (`Num` at one shape, `agree`, `over`, `outer`,
   `contract`). Proof:
   - `fused` on `map f (map g x)`, then `softmax` and `matmul`;
   - a producer with two consumers not duplicated;
   - `matmul` and `heat` at parity with C.
4. **Order** (§4.4, §6). `idr.scan` and `idr.scatter`, or the
   generating ops carrying their models; D32's image; the schedule's
   one-lane rule deleted. Proof:
   - integer reductions and scans vectorized across lanes;
   - float reductions bit-equal to the in-order meaning;
   - `prefix-sum` and `histogram` at parity;
   - producer fusion into an ordered fold measured on spectral-norm.
5. **Index sets, data-dependent shapes, shape arithmetic** (§3.3 to
   §3.7, §3.9). `Table`, `filter`, `Ragged`, `accumulate`, `resize`,
   `Array.Shape.solve`, the views, the rest of the vocabulary, and D12.
   Proof: tests, and the tactic within its threshold.
6. **Sparse** (§9). `SArray`, codegen only, U2,
   `sparsification-and-bufferization` for every module, `i8` semirings.
   Proof:
   - `spmv` within 1.5x of its C (decision);
   - no sparse-runtime symbol in any linked program;
   - the dense benchmarks unchanged;
   - the semiring laws as type-level tests;
   - a type-error fixture for a `String` element.
7. **Relations and consumers** (§10, §11, D45). The plain-Idris layer
   for the operations O6 uses, with their `Faster` hooks; the
   multiplicity check and size-change composition run behind the fork's
   existing results; `calcTerminating`'s triple closure is deleted.
   Proof:
   - identical verdicts and messages on base and the corpus, under both
     hosts;
   - the same results with the hooks removed;
   - D22 applied to the first relational consumer.
8. **Multicore** (§14), after 0007's P4. Proof: 0007's rules; `heat` and
   `matmul` give identical output on one shard and on all.

## 17. Rejected alternatives

- **A segment or collapsed dimension for a growing shape, or an unranked
  tensor**: a uniform form for a megamorphic construct; linalg takes
  ranked operands only.
- **Emitting `linalg` from the frontend**: whether a body may crash is
  known only after defunctionalization and inlining.
- **Structuring, fusion or tiling inside the inner per-function
  pipeline**: tiles made before a caller's inlining cannot fuse with
  what is inlined around them.
- **Schedules written into every module**: one copy per module, and an
  interpreter that would have to run serially over the whole module.
- **Choosing the bufferization pass by whether a module holds a sparse
  tensor**: a branch on content where the plan's stage decides.
- **`unsupported (sparse element)`**: a refusal for a case the types
  rule out.
- **The grade as the tensor's encoding**: it takes the slot sparse
  needs.
- **`tensor.generate`, `concat`, `gather`, `scatter`**: no destination,
  or no bufferization model.
- **Ownership-based deallocation**: a second ownership system.
- **A whole-array runtime primitive per vocabulary function**: a second
  implementation of library code.
- **Reassociating float reductions, or any user monoid on a proof
  alone**: floats do not associate. Finite semirings, decided
  exhaustively, are the one proof-licensed case.
- **Shape arithmetic in Idris's conversion, an SMT or word-equation
  solver, or a shape index language of our own**: programs accepted here
  that upstream refuses, or a solver beside the toolchain.
- **NumPy broadcasting, size-1 stretching, leading-axis primitives,
  implicit lifting, a glyph module, and arithmetic overloaded across
  shapes**: the earlier README's reasons, kept (§3).
- **The sparse runtime library, `library_call`, `ShardToMPI`, OpenMP or
  the async runtime**: C runtimes or shared libraries.
- **Autotuned thresholds and user-visible schedules**: non-reproducible
  builds and a second program beside the program.

## 18. Decisions

**Built** with stage 1, the code their record: D1, D2, D4, D7, D10,
D14, D17, D18, D19, D23 to D28, D33, D34, D38, D40, D42 (which stage 2
deletes), D43, D44. **Superseded** by the representation wave: D13, D37,
D41 and D32's first image (§6).

**Taken, not yet built**, each governing the stage named:

- **D3.** Primitives act on trailing cells; agreement is prefix
  agreement, as an indexing map (§3.4, stage 3).
- **D5.** Arithmetic at one shape, extents by search (§3.3, stages 3
  and 5).
- **D6.** Rank is `merge . map . nest`, the empty frame settled by a
  calculator (§3.4, stage 3).
- **D8.** Index sets are a one-parameter interface; `Table` is a data
  type (§3.6, stage 5).
- **D9.** Names, not glyphs.
- **D11.** Idris's equality is unchanged; shape arithmetic is the
  library's tactic (§3.7, stage 5).
- **D12.** Literal size mismatches are reported as the literals, by a
  fork fix (§3.9, stage 5).
- **D15.** Reductions mean their left fold; `linalg` reductions only in
  §6's three cases. Case 1 is built; the rest come at stage 4.
- **D16.** `idr.scan` and `idr.scatter` until upstream has them, made by
  the structuring for one-integer-op combiners (§4.4, stage 4).
- **D20, D29.** Schedules are one transform library read per target
  from DLTI. The tile-and-fuse schedule and the L1 fact remain
  (§7.1, stage 3).
- **D21.** A sparse array is the dense type with an encoding, codegen
  only, semirings as `i8` (§9, stage 6).
- **D22.** A plan that fits the sparse subset is a sparse array
  program; the rest is 0015's (§10, stage 7).
- **D30.** The bufferization pass is chosen by the plan's stage, never
  by content (§7, stage 6).
- **D31.** `SparseElement` makes another element a type error (§9,
  stage 6).
- **D32.** A fold over a semiring whose laws are proved is unordered,
  stated by the frontend. Its image is decided at stage 4; the default
  is in §6.
- **D35, D36.** Measurement and parity (§16).
- **D39.** An array argument's static pattern is the source type of the
  call's `tensor.cast`. The key gains a typed pattern (§4.3, stage 2).
- **D45 (AFTER-SELF, stage 7).** Code the stock host runs (the
  frontend, the fork, the runner, Gen) reaches no `%extern` of
  `mlir-array`.
  - **Declared once** (ruled 2026-10-15, representation first). An
    operation the frontend or the fork uses is a definition with a body
    over base's primitives (`Data.IOArray`, `Data.Buffer`), which both
    hosts implement. That body is its one meaning, and it has no
    `%extern` twin.
  - **The hook.** idris-mlir lowers such a definition to its array op
    through a `Faster` hook (`Registry/Entry.idr`, `Kind`), as it does
    `Linear.String.Iterator.scalarBytes`. Removing the hook leaves the
    result unchanged.
  - **Programs only.** An operation only programs use may stay a
    bodiless `%extern` of the generating set. When the frontend comes to
    use one, its `%extern` becomes a definition with a body in the same
    change.
  - **Who builds it.** Stage 7 builds the definitions its first
    consumer uses (0011's O6, §11). Each later frontend consumer
    (0010's kernels) adds what it uses, in its own stage.

  Reason: the two-host rule. A body is the meaning both hosts can run,
  and a hook over it is speed, not a second meaning.

## 19. Upstream used, and the patches it needs

Upstream used: `tensor`, `scf`, `linalg` and its generalize,
specialize, fuse, fold and morph passes; `TilingInterface`,
tile-and-fuse, `transform.structured.*`, `transform-interpreter`,
`transform.dlti.query`, `loadIntoLibraryModule`, `linalg::vectorize`;
value bounds and `ReifyRankedShapedTypeOpInterface`; One-Shot, its
function models, `eliminate-empty-tensors` and one-to-N conversion;
`sparse_tensor` codegen; `arith.constant dense` and `memref.global`;
`shard.grid` (§14).

**Gaps filled by ours**, each to go when upstream fills it:

- built: `transform.idr.vectorize_lanes` (a transform param admits no
  arithmetic, so no script computes `W / widest`), `idr.tie_shape`,
  `idr-structure-loops`, the `memref.get_global` lowering, and the
  external flow models;
- to come at stage 4: `idr.scan` and `idr.scatter`.

**Patches** share the cutover's queue (`upstream/README.md`):

- **U1 and U4.** Carried as
  `upstream/24-one-shot-module-function-interface` (`PINS.md`), four
  pull requests in one diff:
  - the reland of llvm-project #110322 (reverted by #113124) on
    `FunctionOpInterface`, `CallOpInterface` and `ReturnLike`;
  - each cycle of calls analyzed to a fixpoint;
  - non-writable call results, with a definite alias writable on its own;
  - the nearest symbol table.

  It is not filed; its plan is in its README.
- **U2.** The sparse passes on `FunctionOpInterface`. They are anchored
  on `func::FuncOp` at the pin. Needed by stage 6.
- **U3.** Sparse codegen's allocations through `allocationFn`, if §9's
  measurement asks for it.

## 20. What the owner settled

1. **One path for counted elements** (D17). A regression that stage 1's
   qualification measures is a reason to make the counted copy faster,
   not to keep a second path.
2. **The release model of §8 is the design**, and One-Shot accepts it
   on the suites (§1). Had it not, the design would have changed whole
   to the grade carried as the tensor's encoding, with linear sparse
   arrays refused; never both in the tree. Stage 2's
   buffers-in-bodies design goes the other way, making the wrapper
   tensor-like. Taking it is a decision for stage 2.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- The generating ops destination-style and tileable: `outs` and inits,
  `DstBufferizableOpInterfaceExternalModel`, `TilingInterface` in place of
  `GeneratingOpInterface` (`IdrInterfaces.td`), the ordered form through
  `lowerToLoopsUsingSCFForOp` after bufferization, `accumulate`'s op the one
  scatter; then the nest builder (`StructureLoops/Nests.cpp`) and the
  planned `idr.scan` and `idr.scatter` go. §4.4's "open at stage 4" already
  tries this first; D16 and the stage-4 plan change with it.
- `Idr_Iteration` spelled as upstream's `IteratorType`, with reduction and
  `PartialReductionOpInterface` for "any association"; only Ordered stays
  ours (D32 plans no third case).
- `!idr.lin<T>` tensor-like is the design now (§16's stage-2 decision);
  §8 and §20 item 2 are reconciled with it, and `DataRemap`'s "buffers"
  kind (`Bufferize.cpp`) and `heldType` go when it lands.
- One counting protocol per element access: idr-rc lowers `array.get` to
  `memref.load` and `idr.dup`, and `array.set` to `idr.own.give` and
  `memref.store`; `LowerArrayGet` and `LowerArraySet` stop counting
  (`Conversion/Arrays.cpp`). `array.get` already carries
  `Idr_TakesReference`, so the owned verifier sees it.
