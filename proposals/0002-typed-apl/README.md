# 0002: a typed array language, MLIR first

**Status:** decided, 2026-10-12: the MLIR-first revision, to be
executed as one hard cutover with no compatibility owed, right after
`make self` is green and ahead of sharding. It replaces the earlier
README and its two companions, `compiler.md` and `types.md`, which were
three drafts of one design and disagreed on reductions, grades,
constants and shapes; this file is the one design. The fork's
`Libraries/Data/Table.idr` (a growable `Linear.Array`),
`Core/Context/Context.idr` (`Data.IORef`) and `Libraries/Utils/Binary.idr`
with `Core/Binary/Prims.idr` (`Data.Buffer`) are ported in the same
change (read: their imports). Every decision below is decided; the rulings that stand behind the
design are the owner's:
pure array programs are tensors, rank has no ceiling, and arrays are
redone "MLIR first", Idris's dependent types mapping onto MLIR's own
concepts and the optimizations MLIR runs on them, not onto layers of our
own. Claims are marked: read (the path given), measured, recalled,
conjecture, decision. `M/` below is the pinned MLIR,
`.toolchain/build/llvm-project/mlir/` (llvm main 7208ba24).

The array style is the compiler's organizing principle, not one feature
among others. The frontend's tables (0007), the layouts of their columns
(0008), the relations of the relational core (0011) and the kernels of
the array interpreter (0006) are programs in this language, compiled by
this lowering. The compiler is its own heaviest user.

**The ruling, in one sentence.** Every fact Idris proves about an array
has exactly one image in MLIR, the one upstream already optimizes on: a
shape is a ranked tensor type, a size fixed by the program is a static
dimension, a typed index is an access with no guard, a linear thread of
writes is a destination-passing chain One-Shot Bufferize puts in place,
an unordered combine is a structured reduction, a sparse format is a
`#sparse_tensor.encoding`. An op, type or pass of ours exists only where
upstream has none, and each one names the upstream gap it fills (§20).

## What it changes

- **Sizes are in the type, and the type is MLIR's.** Today no array of
  the shipped library has a size in its type; the compiler re-derives the
  relations Idris could have proved with about 3,000 lines of Presburger
  analysis, and every dimension prints as `?` because the Idris-side
  syntax cannot write a static one (§1). Here `Array : (0 s : Shape) ->
  Type -> Type`, and its MLIR image is `tensor<d0 x ... x E>` with a
  static `di` wherever the program fixes the extent (§2).
- **A typed access has no guard, and no pass has to remove one.**
  `idr-in-bounds` is deleted, not improved (§2, §15).
- **Arrays are values until bufferization, and bufferization is
  upstream's.** One-Shot Bufferize decides every in-place write, once;
  a linear thread is a chain it puts in place by its own exact analysis;
  `--demand-in-place` turns a remaining copy into a refusal through the
  analysis's own failure (§8).
- **Loops are upstream ops from the start.** The frontend writes each
  array loop's sequential meaning in `scf` and `tensor`; a body without
  effects is raised to `linalg`, where upstream fuses, tiles and
  vectorizes it (§4, §5). Our own loop ops on memrefs go.
- **Order is a fact of the representation.** A `linalg` reduction means
  any order; an ordered fold is an `scf.for` (§6). The one-lane rule
  that today keeps float sums in order goes.
- **Sparse arrays and relations are the same tensors with an encoding**
  (§9, §10), and the compiler's semiring analyses are sparse array
  programs (§11).

## 1. What exists

The inventory of 2026-10-12, against the working tree of the cutover
(read: the paths given; line counts measured with `wc -l`).

**The library.** `libs/mlir-linear/Linear/Array.idr` (289 lines) gives
`Array a = MkArray Int (ArrayData a)` (linear, the size a runtime `Int`
beside a backing whose length is the capacity) and `IArray a = MkIArray
(ArrayData a)` (frozen). Neither has a size index. Every read calls
`prim__index i n`, a `%foreign "scheme:..."` bounds check, and the two
primitives the library declares, `prim__arraySize` and `prim__index`,
are Scheme specs kept so that `bench/` can run these programs on Chez
(read: `Array.idr:35-49, 94-102, 157, 165`). Base's `Data.IOArray` is a
record of `maxSize : Int` and `ArrayData (Maybe elem)` that checks every
index in Idris before calling the primitive. `Data.Vect` compiles as a
cons list with `n` erased, and `Fin n` becomes `!idr.nat`, its bound
gone (read: `Translate/Types.idr:233`).

**The frontend** (about 320 lines about arrays, estimated from the
ranges). `Registry/Primitives.idr:412-503` maps `ArrayData` to a rank-1
array, IORef's `Mut` to rank 0, `Buffer` to rank 1 of bytes, and the
library's two primitives by their Scheme spec strings, byte for byte.
`Registry/Recognized.idr:87-110` finds `prim__generate` and
`prim__foldl` by name. `Translate/Terms.idr:940-1021` emits the region
loop only when every type is a machine word, and calls the library
otherwise. `Types.idr:78-94` has `data Rank = Rank0 | Rank1`, and
`MLIR.idr:45` prints a memref of rank `n` as `"?x"` repeated: no
static dimension can be written. `Emit/Operations.idr:180-212` puts an
`idr.check.in_bounds` against `memref.dim` on every rank-1 `get` and
`set`.

**The dialect.** No array type of ours: an array is a builtin
`memref<?xE>` or `memref<E>`, and the idr types implement
`MemRefElementTypeInterface` (read: `IdrArrayOps.td:15-27`,
`IdrTypes.td:17-23`). The ops are `idr.array.new`, `get`, `set`, and the
loops `idr.array.generate` (element 0 is the fill, the body runs from 1)
and `idr.array.fold`, rank 1, words only, threading the world
(`IdrArrayOps.td`, 185 lines; `lib/IR/OpsArrays.cpp`, 295). `new` and
`generate` implement `ReifyRankedShapedTypeOpInterface`, so upstream's
resolve-dims patterns fold `memref.dim`. Every array op reads and writes
the one global `IOResource` (read: `IR/Effects.cpp:54-61`).

**The passes.**

| piece | lines | what it does |
|---|---:|---|
| `Transforms/InBounds/*` | 3057 | proves guards away with `IntegerPolyhedron` systems: paths, ranges, induction over `scf.while`, the length-size relation through record fields |
| `Conversion/ArrayLoops.cpp`, `ArrayLoopReads.cpp` | 431 | generate to a parallel `linalg.generic` from element 1, fold to a reduction into a 0-d alloca, reads at the loop index to inputs behind an entry test and a second copy of the loop |
| `Conversion/Arrays.cpp`, `ArrayView.cpp`, `Buffers.cpp` | 380 | `new` to the runtime's allocator and an `scf.for` fill, get and set to loads and stores or slot GEPs, the descriptor built by hand over the cell |
| `Transforms/Vectorize` | 217 | a driver over `scf::tileUsingSCF`, `peelForLoopAndSimplifyBounds` and `linalg::vectorize`, with `vectorizeNDExtract=false` |
| `Narrow/{Lanes,Copy,Widths}.cpp` | 442 | versions a vectorized loop under a bound it searches for, then upstream's `arith-int-range-narrowing` and `ValueBoundsConstraintSet` |
| `Expect` (array properties) | 360 | `PureArrayLoops`, `InBounds`, `Vectorized`, `NarrowedLanes`, `MovesOut` |
| `Canon/MoveOut.cpp`, `Verify/Knots.cpp` | 187 | a get that moves a counted element out ahead of a set; no array reaches itself |

**The runtime.** `runtime/Alloc/Arrays.cpp` (30 lines) allocates a
cell, a header and a `uint64_t length` then the elements
(`idris_rt.h:160-163`); `Io/Buffer.cpp` (36) is the buffer's side. The
descriptor's allocated pointer is the cell and its aligned pointer the
first element (read: `Conversion/ArrayView.cpp`).

**The tests.** `tests/programs/arrays`: 40 tests, 2766 lines.
`tests/idr`: 36 files that touch `idr.array` or `memref<`, 5456 lines,
of which `in-bounds/` is 26 files and 2694 lines. Bench programs on
`Linear.Array`: fannkuch-linear, qsort, spectral-norm-linear, unionfind,
k-nucleotide; on `Data.IOArray`: fannkuch-redux; on `Data.Buffer`:
fasta, fasta-redux, mandelbrot-pbm, reverse-complement, k-nucleotide.

**Where a fact Idris could prove is dropped or re-derived.**
1. Never stated: `Array a` has no size, so a read's index is an `Int`
   checked at run time, and `InBounds/Relation.cpp` exists to relate the
   separate size field to the backing.
2. `Fin n` loses its bound, `Vect n` its length.
3. Every dimension is dynamic, even a literal one: static shapes never
   reach linalg or the vectorizer.
4. Base's `IOArray` checks an index in Idris, Emit adds the access's own
   guard, and InBounds re-proves the second from the first through the
   record's fields.
5. The length is held twice: the SSA length component beside the cell
   and the cell header's `length` (`Arrays.cpp:1-4, 28`).
6. "Frozen means immutable" is not in the IR: `IArray` is the same
   memref, and every read writes the global IO resource, so no CSE,
   hoisting or alias reasoning applies until lowering.
7. Linearity is not used: updates are in place because every op is IO
   on the world (`Array.idr:118-120`).

Measured (`bench/runs/2026-10-07-f5a4dff9-darwin-arm64/results.md`, Apple
M2 Max, best of 5; before the cutover):

| benchmark | this compiler | clang -O2 | clang / this |
|---|---:|---:|---:|
| spectral-norm-linear 5500 | 0.596 s | 1.108 s | 1.86x |
| spectral-norm (lists) 5500 | 1.515 s | 1.126 s | 0.74x |
| fannkuch-linear 12 | 24.155 s | 25.711 s | 1.06x |
| nbody 50000000 | 1.655 s | 1.924 s | 1.16x |
| mandelbrot 2000 | 0.229 s | 0.231 s | 1.01x |

**What survives** (read, each above): builtin memref and tensor with idr
element types and no array type of ours; `ReifyRankedShapedTypeOpInterface`
with upstream's resolve-dims; loops declared through
`RegionBranchOpInterface`; guards as SSA values, a proof being the
guard's absence; the Idris-side dialect generated from ODS; float
reductions in program order; `scf::upliftWhileToForLoop`; the Expect
property checks; the 30-line allocator; `MoveOut` and `Knots`, since
counted elements have no upstream counterpart; NarrowLanes' loop
versioning, since upstream has no versioning pass (recalled).

## 2. The correspondence

One row per thing Idris proves or the program states. The middle column
is its one image in MLIR; the last is what checks or uses it, upstream's
mechanism wherever there is one. This table is the design; every later
section is a row worked out.

| Idris | MLIR | checked or used by |
|---|---|---|
| `Array s a`, the rank of `s`'s form | `tensor<d0 x ... x E>`, one dimension per `:<` of the form | the tensor type's verifier; linalg's indexing maps |
| an extent the program fixes (a literal, or one specialization or normalization makes constant) | a static dimension `N` | `tensor.dim` folds to the constant; static vectorization; `tensor.cast` folding (`M/lib/Dialect/Tensor/IR/TensorOps.cpp:947-1003`) |
| an extent at quantity 0 | a dynamic dimension `?`, read back with `tensor.dim` from the value | `DimOfDestStyleOp`, `FoldEmptyTensorWithDimOp` and `reifyResultShapes` fold it to the value that made it (`TensorOps.cpp:1024, 1178`) |
| an extent at quantity many (`Extents s`, `{n : Nat}`) | an `index` value, the operand of `tensor.empty` and `linalg` destinations | `ValueBoundsOpInterface` relates it to every `tensor.dim` of the arrays built from it (`M/include/mlir/Interfaces/ValueBoundsOpInterface.h:281-292`) |
| two arrays indexed by one size variable | their dynamic dimensions tied to one `index` value by `idr.tie_shape` at the function's entry | `ValueBoundsConstraintSet::areEqual` across calls, through the op's `populateBoundsForShapedValueDim` (§4.3) |
| `n + m`, `n * m` in a shape | `arith.addi`, `arith.muli` with `nsw nuw` on `index`, or `affine.apply`; `n * m` kept as two dimensions where the type has two | value bounds' arith and affine models; never the `index` dialect, which has no model (`M/lib/Dialect/Index/IR/`) |
| `Index s`, a coordinate of an array of shape `s` | an `index` per axis at the access; inside a structured op, `linalg.index` | no guard; `linalg.index` carries `0 <= i < dim` (`M/lib/Dialect/Linalg/IR/ValueBoundsOpInterfaceImpl.cpp:20-48`); transfers get `in_bounds = [true]` |
| a bare `Fin n` with no array | a natural, narrowed where proved, as every `Nat`-shaped value | `idr-narrow` |
| `x !! i` | `tensor.extract %x[%i...]` | the load's in-bounds precondition, which `memref.load` lowering already assumes (`inbounds` GEP, `MemRefToLLVM.cpp:40-53`) |
| `update x i v`, a write | `tensor.insert %v into %x[%i...]` | One-Shot Bufferize's in-place analysis |
| a linear thread of writes (`LArray s a` at quantity 1) | `!idr.lin<tensor<...>>`, unwrapped by `idr.lin.use` into a destination-passing chain | One-Shot's analysis puts it in place; under `--demand-in-place`, `mustBufferizeInPlace` makes a copy a failure (§8) |
| an element type that is a word or float | the builtin element type | vectorization (`VectorElementTypeInterface` on builtin types) |
| an element type of ours (a box, a string, a natural) | `tensor<?x!idr.T>`, legal since a tensor takes any non-builtin element (`M/lib/IR/BuiltinTypes.cpp:435`) | tiling, fusion and bufferization, through `MemRefElementTypeInterface`; never vectorized (§4.5) |
| a record element | one tensor per field, by one-to-N type conversion | multi-result `linalg.generic`; the one representation of columns (§4.5, 0008) |
| an array of arrays of one cell shape | one tensor, the dimensions concatenated | `expand_shape`, `collapse_shape` |
| a shape whose rank no analysis fixes (a recursion that builds it deeper) | nothing: `unsupported (polymorphism)` naming the site | the frontend's growing-skeleton refusal, which exists (read: `Translate/Instances.idr`, `growing`) |
| a combine whose order is unobservable | a `linalg` reduction iterator | upstream's tiling, split-reduction and vectorization, which reassociate it |
| a combine whose order is observable | `scf.for` with `iter_args` | nothing reorders a loop-carried value |
| a body that can crash, diverge or touch the world | `scf.for` | `MemoryEffectOpInterface` on its ops, read by the raising (§5) |
| a pure body | `linalg.generic` (named op where it specializes) | elementwise fusion, tile-and-fuse, vectorization |
| `SArray fmt s a` | `tensor<..., #sparse_tensor.encoding<{map = ...}>>` | the sparsifier, codegen mode (§9) |
| a relation | an `i8` sparse tensor with `explicitVal = 1` | co-iteration (§10) |
| a semiring element | `i8` (or wider), the semiring's zero encoded as 0 | `sparse_tensor.binary`, `unary`, `reduce` regions (§9) |
| a literal array, a normalized result | `arith.constant dense<...>`, bufferized to an immortal `memref.global` | constant folding; copy on write (§12) |
| an array a world orders (`IOArray`, `IORef`, `Buffer`) | `memref`, threaded by the world, with `MemRead`/`MemWrite` on that memref | upstream's alias and effect reasoning (§13) |

Two rows are deliberately not here. **Erased does not mean constant**:
an extent at quantity 0 is a dynamic dimension unless the program fixes
it, and its runtime value is the tensor's own, read with `tensor.dim`,
never assumed. **Indexed vectors do not imply contiguous storage**:
`Vect n a` stays a list; contiguity is `Array`'s, by the library's
construction.

## 3. The language

`libs/mlir-array`, in plain Idris over base's primitives and
`mlir-linear`, a trusted library as `mlir-linear` is (**decision**,
D1). Read as written, every definition is the meaning; the
compiler knows a generating set by name and lowers it to upstream ops
with the same meaning (§4). Modules: `Array` (types, generating set,
vocabulary, interfaces), `Array.IndexSet`, `Array.Shape` (lemmas, views,
the solver of §3.7), `Array.Ragged`, `Array.Sparse` (§9), `Array.Display`.

The examples type-check against a mock of this library with the same
types (measured: the pinned Idris 2, 0.8.0-1c630e67c, by the earlier
draft's research probes; stage 1 commits them as tests).

### 3.1 Arrays, shapes, frames and cells

```idris
Shape : Type
Shape = SnocList Nat              -- the axes' lengths, outermost first

export
data Array : (0 s : Shape) -> Type -> Type   -- abstract; row-major

Scalar : Type -> Type             -- Array [<]
Vector : Nat -> Type -> Type      -- Vector n = Array [<n]
Matrix : Nat -> Nat -> Type -> Type
```

An array is a shape and an element at every index of it, row-major:
APL's model (read: `sources/papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm`,
II.A). Its rank is the length of its shape. A function from cells of
shape `c` to cells of shape `d`, applied to an array of shape `f ++ c`,
applies to each cell, and `f` is the frame (read:
`sources/papers/bernecky-1983-satn45-rank-operator/satn45a.htm`).

**decision** (D2) Shapes are snoc lists, outer axis first.
Base's `SnocList.(++)` recurses on its right argument (read:
`third_party/Idris2/libs/prelude/Prelude/Types.idr:424-427`), so `f ++
[<n]` reduces to `f :< n`, and unification finds a frame from the
argument alone: `Array (f :< n) a -> Array f b` applied to `Array [<3, 4,
5] Int` solves `f = [<3, 4]` (measured; the cons-list twin fails with
"Can't solve constraint between: [3, 4, 5] and ?s ++ [?n]"). The cell is
what a function's type states, the frame what unification finds:
Remora's division (read: `sources/papers/slepak-2018-constraint/paper.pdf`,
§3), done by Idris's own unifier.

**decision** (D3) A primitive acts on its trailing cells, and
the frame is iterated; the leading axis is reached through `transpose`,
which is an indexing map and costs nothing. Agreement between shapes is
prefix agreement (§3.4).

### 3.2 Indices and extents

```idris
namespace Extents                 -- a shape at run time
  data Extents : Shape -> Type where
    Lin  : Extents [<]
    (:<) : Extents s -> (n : Nat) -> Extents (s :< n)

namespace Index                   -- a position in a shape
  data Index : Shape -> Type where
    Lin  : Index [<]
    (:<) : Index s -> Fin n -> Index (s :< n)

shape    : Array s a -> Extents s
tabulate : Extents s -> (Index s -> a) -> Array s a
(!!)     : Array s a -> Index s -> a          -- infixl 10
```

`Extents s` is a singleton: its sizes are its index's, so a value of it
is the shape at run time. `Index s` holds a `Fin` per axis, so every
index is within its array by type, and `(!!)` has no runtime check. An
index computed from integers goes through `(!?) : Array s a -> SnocList
Integer -> Maybe a`, whose test is the program's comparison, not a
guard. `!` alone is Idris's bang notation, and the Prelude's `*` is
`infixl 9` (read: `Parser/Lexer/Source.idr:244-247`,
`Prelude/Ops.idr:6`), so indexing is `!!` at 10: `a !! [<i, p] * b !!
[<p, j]` is two reads multiplied (measured).

```idris
matmul : {m, k, n : Nat} -> Matrix m k Double -> Matrix k n Double -> Matrix m n Double
matmul a b = tabulate [<m, n] (\[<i, j] => sum (tabulate [<k] (\[<p] => a !! [<i, p] * b !! [<p, j])))
```

Dex's product, `for i j. sum (for k. x.i.k * y.k.j)` (read:
`sources/papers/paszke-2021-dex/main.tex:320-343`). Its point-free twin
is `contract (+) 0 (*) a (transpose b)`; both become one `linalg`
contraction whose reads are indexing maps (§4.2). `{m, k, n : Nat}`
binds the sizes at quantity many, so they are `index` values; a function
whose sizes are erased reads them off its arguments with `shape`, which
is `tensor.dim`.

### 3.3 Arithmetic and the interfaces

**decision** (D5) Arrays are `Num`, `Neg`, `Fractional` and
`Applicative` at one shape, the extents found by search:

```idris
%hint arrayNum : Num a => {auto ext : Extents s} -> Num (Array s a)
```

`2 * m + 1` is a matrix, `printLn (1 + 2)` still means what it meant, and
a mismatch of shapes is a type error (measured). Overloading across
shapes under the Prelude's names makes `printLn (1 + 2)` ambiguous in
every module that imports the library (measured), so different shapes
meet by a named function (§3.4). `Functor`, `Foldable`, `Traversable`,
`Zippable` and `Show` are base's; **decision** the array's `foldMap` is
the left fold in index order, so `sum x` adds as `reduce` does (§6),
where the method's default, a right fold, would add a float array
backwards (read: `Prelude/Interfaces.idr:273-315`). Idiom brackets apply
any function elementwise: `[| min m 10 |]`. **decision** (D9)
names, not glyphs: a glyph gives APL's look without its grammar, and two
spellings is two names for one thing in every message.

### 3.4 The rank operator and agreement

```idris
namespace Cell                    -- a cell's form, sizes left to unification
  data Cell : Shape -> Type where
    Lin  : Cell [<]
    (:<) : Cell s -> (0 n : Nat) -> Cell (s :< n)

nest  : Cell c -> Array (f ++ c) a -> Array f (Array c a)
merge : Extents c -> Array f (Array c a) -> Array (f ++ c) a

over  : Cell c -> {auto calc : Extents c -> Extents d}
     -> (Array c a -> Array d b) -> Array (f ++ c) a -> Array (f ++ d) b
over c g x = merge (calc (cellExtents c x)) (map g (nest c x))
```

Rank is merge after each after nest, BQN's identity (read:
`sources/docs/bqn/doc/rank.md`). **decision** (D6) the empty
frame is settled by a shape calculator, a value `Extents c -> Extents
d` that search finds in the common cases (measured), never by running
the function on a cell of fills (read:
`sources/papers/hui-1995-rank-uniformity/rank1.htm`, §2). A nested array
of one cell shape is the flat tensor (§2), so nesting costs nothing.

Different shapes meet by prefix agreement: one shape is a prefix of the
other, and the shorter array's elements are reused along the longer's
trailing axes (read: `sources/docs/j/help/dictionary/dictb.htm`;
`sources/docs/bqn/doc/leading.md`). The principal frame is read off
evidence, never computed from lengths (measured: the probe that compares
lengths gets stuck). In MLIR the reuse is an indexing map that drops the
trailing dimensions, so `agree (-) m rowMeans` is one generic with a
broadcasting map and nothing materialized (read:
`sources/docs/mlir/docs/Dialects/Linalg/_index.md`, Property 2).
**decision** no NumPy broadcasting and no size-1 stretching: a second
agreement rule that consults runtime sizes.

### 3.5 The vocabulary

The generating set is the only set of functions the compiler knows by
name (**decision**, D7); everything else is library code over
it, and its lowering is what its definition becomes. §4 gives each its
upstream image.

| Idris | type | APL, J, BQN |
|---|---|---|
| `shape` | `Array s a -> Extents s` | `⍴`, `$`, `≢` |
| `tabulate` | `Extents s -> (Index s -> a) -> Array s a` | `f¨⍳` |
| `(!!)` | `Array s a -> Index s -> a` | `⌷`, `{`, `⊑` |
| `foldLast` | `(b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b` | `f/` on the last axis |
| `scanLast` | `(b -> a -> b) -> Array f b -> Array (f :< n) a -> Array (f :< n) b` | `f\` |
| `nest`, `merge` | §3.4 | `<⎉k`, `>` |
| `reshape` | `Extents t -> {auto 0 _ : count s = count t} -> Array s a -> Array t a` | `⍴`, `$`, `⥊` |
| `take`, `drop` | `(k : Nat) -> {auto 0 _ : LTE k n} -> Array (f :< n) a -> Array (f :< k) a` | `↑`, `↓` |
| `(++)` | `Array (f :< n) a -> Array (f :< m) a -> Array (f :< n + m) a` | `,` |
| `pad` | `(lo, hi : Nat) -> a -> Array (f :< n) a -> Array (f :< lo + n + hi) a` | `»`, `«` with fill |
| `update` | `Array s a -> Index s -> a -> Array s a` | `@`, `}` |
| `accumulate` | `(b -> a -> b) -> Array t b -> Array s (Index t) -> Array s a -> Array t b` | `⌸`, `/.`, `⊔` |

Library code over it, each with the form its definition lowers to: `map`,
`zipWith` and idiom brackets (`linalg.map`); `agree`, `over`, `over2`
(indexing maps); `reduce` and `scan` (`foldLast`, `scanLast`); `outer`
and `contract` (a generic with a product map, specialized to
`linalg.matmul` or `linalg.contract` where it matches); `transpose` and
`permute` (an indexing map, or `linalg.transpose` where it must be
materialized); `reverse`, `rotate`, `shift`, `windows` (affine reads);
`iota`, `fill` (`linalg.index`, `linalg.fill`); `ravel` (`collapse_shape`);
`filter` (§4.4); `select` (a gather, §4.4); `sort` and `grade` (the
library's merge sort on `LArray`); `iterate`.

**Under** is structural only: a `View s t` is one of a closed set of
selections (a row, a column, the diagonal, a window, a swap of the last
two axes), each a lens (read: `sources/docs/bqn/doc/under.md`), and its
image is `extract_slice` then `insert_slice`. Fill elements, the
zero-frame probe and permissive assembly are replaced by types: a ragged
result is `Ragged`, never padded.

### 3.6 Index sets as types

```idris
interface IndexSet ix where
  0 axes    : Shape
  extentsOf : Extents axes
  toIndex   : ix -> Index axes
  fromIndex : Index axes -> ix

data Table : (0 ix : Type) -> Type -> Type where
  MkTable : IndexSet ix => Array (axes {ix}) a -> Table ix a
```

Dex's index sets (read: `main.tex:782-831`) as an interface whose shape
is an erased method: `Table (Fin 2, Fin 3, Channel) Int` holds an
`Array [<2, 3, 3] Int`, and `img !@ (1, 2, G)` types its literals from
the table (measured). **decision** (D8) a one-parameter
interface and a data type: a two-parameter one never resolves a product,
and a synonym loses `ix` (measured). A table is an array, so index sets
add no second representation, and in MLIR they are nothing at all: the
tensor of `axes`.

### 3.7 Shapes that depend on data, and shape arithmetic

A size the data decides is the array's own: `filter p xs : Exists (\m =>
Vector m a)`, its witness erased (read: `Data/DPair.idr:77-80`), and
`shape ys` gives the length, held once, in the tensor's dimension. A
ragged array is `Ragged f a`, a flat vector and an offset per row (read:
`sources/papers/hsu-2019-data-parallel-compiler/`), which is a compressed
sparse level's positions array and is lowered as one (§9). An equality
the program cannot prove is a checked conversion, `resize : (n : Nat) ->
Vector m a -> Maybe (Vector n a)`.

Most shape facts are concatenation, which reduces. The rest:
1. **Literal shapes need nothing:** search proves `LTE 3 5` and `count
   [<24] = count [<2, 3, 4]` by computation (measured), and a failure
   names the rule ("Can't find an implementation for LTE 5 4").
2. **Symbolic ones are the library's tactic**, `Array.Shape.solve`, by
   elaborator reflection over a canonical form (concatenation flattened,
   sizes as sums of sorted monomials), the proof at quantity 0. Frex is
   the Idris-native precedent, under 1 s up to terms of size 30 (read:
   `sources/papers/allais-2025-frex/evaluation.tex`). **decision**
   threshold 1 s per obligation on the corpus's largest shape term.
3. **Views** for arithmetic patterns: `MkSplit : (q, r : Nat) -> Split d
   (q * d + r)` (read: `sources/papers/mcbride-2004-view-from-left/view.ps`,
   §6).

**decision** (D11) Idris's equality is unchanged: no
normalization of shape arithmetic in the fork's conversion, which would
accept programs upstream Idris rejects, and no solver beside the
toolchain. The earlier `types.md`'s definitional arithmetic is deleted
for that reason.

### 3.8 Linear arrays and in-place updates

```idris
export
data LArray : (0 s : Shape) -> Type -> Type

withArray : Extents s -> a -> ((1 _ : LArray s a) -> Ur b) -> b
read      : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))
write     : (1 _ : LArray s a) -> Index s -> a -> LArray s a
freeze    : (1 _ : LArray s a) -> Ur (Array s a)
thaw      : Array s a -> ((1 _ : LArray s a) -> Ur b) -> b
```

**Linearity is not ownership.** A quantity-1 argument promises not to be
shared in the future, not that it was never shared (read:
`sources/papers/brady-2021-idris2-qtt/erasure.tex:34-38`), and AGENTS.md
says so. The library supplies the past: an `LArray` is born fresh
(`withArray`, and `thaw`, which copies unless its argument is dead) and
leaves only by `freeze`, so no `LArray` aliases a shared cell. Its writes
are a chain of `tensor.insert` on one SSA thread, which One-Shot
bufferizes in place by its own analysis; the type's part is that no old
version is read again, which is exactly the condition that analysis
checks (§8).

`Linear.Array` is rewritten on `LArray` (**decision**, D19):
`Linear.Vec a`, the growable array the fork's `Table` needs, is a record
of an `LArray [<cap] a` and a size `n` with `LTE n cap`, growing by a
fresh array of twice the capacity and one `insert_slice`. Its `%foreign
"scheme:..."` primitive specs go: they were kept so `bench/` could run
these programs on Chez, and AGENTS.md says not to shape a feature so
that Chez can run it. Its primitives become declared runtime primitives
of the registry, keyed by name, as base's `%extern` primitives are. The
Chez column of `bench/` loses the programs that used them.

### 3.9 Errors and the interactive loop

Shape errors are Idris type errors at the user's line (measured: "When
unifying: Array [<4] Int and: Array [<3, 4] Int"; "Can't find an
implementation for Agree [<3, 4] [<4]"). The library names its evidence
for the rule a reader recognizes (`Agree`, `LTE`, `count`). Idris
reports a mismatch of two literal sizes as their unary forms;
**decision** (D12) that message is fixed in the fork's
unifier error, as the fork's own code, recorded in `PINS.md` with a
pull request drafted under `upstream/`. There are no runtime shape
errors in typed code.

The interactive loop (`idris-mlir repl`, every line compiled and run as
a linked executable in a child, never on Idris's evaluator or Chez) is
the earlier draft's D13. It is parked here: it is not on the array
path, and it moves to 0006's stages once that interpreter exists.

## 4. The generating set, as upstream ops

### 4.1 What the frontend emits

**decision** (D13) The frontend writes each primitive's
sequential meaning in upstream ops, and nothing of ours but the grade
casts and `idr.tie_shape`:

| primitive | emitted |
|---|---|
| `shape` | `tensor.dim` per dynamic dimension, a constant per static one |
| `tabulate e f` | `tensor.empty(%dims)` and an `scf.for` nest whose body computes `f` and `tensor.insert`s it at the induction variables |
| `(!!)` | `tensor.extract` |
| `foldLast g z x` | an `scf.for` over the last axis carrying the accumulator in `iter_args` (the frame a loop nest around it, or a tensor of accumulators) |
| `scanLast g z x` | the same loop, inserting each accumulator into a destination |
| `nest`, `merge` | nothing: the same tensor (§2) |
| `reshape` | `tensor.collapse_shape` then `expand_shape`, with `output_shape` operands for dynamic dimensions |
| `take`, `drop` | `tensor.extract_slice` |
| `(++)` | `tensor.empty(n + m)` and two `tensor.insert_slice`s, which bufferize in place; `tensor.concat` always allocates (read: `M/lib/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.cpp:1094`) |
| `pad` | `tensor.pad` |
| `update` | `tensor.insert` |
| `accumulate` | an `scf.for` over the values that extracts at the computed index, combines and inserts (§4.4) |

`tensor.generate` is not used: it has no destination and always
allocates (read: `sources/docs/mlir/docs/Bufferization.md`,
"Destination-Passing Style"), where `tensor.empty` plus a loop is a
destination `eliminate-empty-tensors` can redirect into its consumer.

Every loop the frontend writes is the program's meaning, in its order.
Turning it into a structured op is the MLIR side's decision, made after
inlining and defunctionalization have shown what the body does (§5). The
frontend cannot make it: whether `f` may crash depends on code it has
not inlined. That is the earlier draft's reason for rejecting linalg
from the frontend, kept, and its own loop ops (`tabulate`, `fold`,
`scan`, `lift`, `rebase`, `thaw`, `constant`, `alloc`, `copy`, `sort`)
are deleted: the sequential meaning is already expressible in `scf` and
`tensor`, so a second spelling of it would be a second representation.

### 4.2 Reads become indexing maps

A pure body that reads another array at an affine function of the
induction variables (`x !! [<i]`, `a !! [<i, p]`, `x !! [<i + 1]`) is an
input of the raised generic with that function as its indexing map; a
read at the induction variables themselves is the identity map. This is
today's `ArrayLoopReads.cpp` without its entry test and its second copy
of the loop: those exist because an untyped read might be out of bounds,
and a typed one is not. A read at a computed index stays a
`tensor.extract` in the body (§4.4).

`transpose`, `agree`'s reuse and a column read are maps, not copies.
`linalg-fold-into-elementwise` and `linalg-morph-ops` absorb an
explicit transpose or broadcast into the consumer's maps where one was
materialized (read: `M/include/mlir/Dialect/Linalg/Transforms/Passes.td`).

### 4.3 Dimensions across calls: `idr.tie_shape`

Upstream reasons about a dynamic dimension only through the op that
made it (read: `ValueBoundsOpInterface.cpp`; `func.func` arguments and
call results have no model), and there is no upstream op that asserts
two dynamic dimensions equal: `tensor.cast` refines only toward static
(read: `TensorOps.td`). Idris proves such equalities everywhere: `zipWith
f x y` with `x, y : Vector n a` has one `n`.

**decision** (D14) One op of ours fills the gap:

```mlir
%y1 = idr.tie_shape %y dims(%n) : tensor<?xf64>
```

an identity that states its result's dynamic dimensions are the given
`index` values. It implements `ValueBoundsOpInterface`
(`populateBoundsForShapedValueDim`: dimension `k` equals operand `k`) and
`ReifyRankedShapedTypeOpInterface`, so `areEqual` and dimension folding
cross a call, and it is `Pure`. The frontend writes it at a function's
entry: the first array argument indexed by a size variable gives that
variable's value, `tensor.dim` of it, and every other array argument
indexed by the same variable is tied to that value. A result is tied at
the call to the caller's values. Folding it away loses an optimization,
never a meaning, since the equality is Idris's and holds whether or not
the op is there. IREE's `flow.tensor.tie_shape` is the precedent
(recalled).

Sizes are computed with `arith` (`addi`, `muli`, `subi` with `nsw nuw`)
or `affine.apply` on `index`, which value bounds models; never the
`index` dialect, which it does not (read: `M/lib/Dialect/Index/IR/`).
`n * m` is kept as two dimensions wherever the type has two, because
value bounds drops a product of two symbols as semi-affine (read:
`ValueBoundsOpInterface.cpp:236`, "Failed to add bound").

**Static extents.** An extent is static where the checked type's normal
form at that instance is a literal, and where `idr-specialize` clones a
callee for a constant `Extents` argument: the clone's entry casts its
array arguments to the static type with `tensor.cast`, and upstream's
cast-folding canonicalizations carry the static type into the
destination-style ops that consume it (read: `FoldTensorCastProducerOp`,
`TensorOps.cpp`). How far that propagation reaches through our ops is
measured in stage 2 (conjecture).

**Narrowing.** A size that is an array's extent fits `index` by
construction: the array exists. `Extents` values are naturals; the one
place a natural becomes an extent is allocation, where the conversion is
a guarded narrowing (an extent past the address space is the runtime's
allocation failure). A coordinate is converted at its access, where the
type says it is below an extent, so that conversion is exact and
unguarded; inside a loop the coordinates are the loop's induction
variables, `index` from the start.

### 4.4 Gathers, scatters, filters and scans

Upstream has the dense, regular part and not these, so this is where
ops of ours are allowed, each with its upstream gap named.

- **Gather** (`select`, a read at a computed index): a raised generic
  whose body does `tensor.extract` at the computed index. The
  vectorizer's n-D extract path makes it a gather or a contiguous load
  (read: `vectorizeNDExtract`, which `idr-vectorize` turns off today:
  `Vectorize.cpp:142`; here it is on). No op of ours.
- **Scatter with a combiner** (`accumulate` whose combiner is
  reassociable, §6): `idr.scatter`, a destination, indices, values and a
  combiner region, destination-passing, implementing `TilingInterface`
  (batch dimensions parallel) and `BufferizableOpInterface`. Gap:
  `tensor.scatter` has no combiner and no bufferization model (read:
  `TensorOps.td:1619`; `BufferizableOpInterfaceImpl.cpp:1190-1210`
  registers no model for it). An `accumulate` whose combiner is not
  reassociable stays the frontend's loop. IREE's LinalgExt `scatter` is
  the precedent (recalled).
- **Scan** (`scanLast` whose combiner is reassociable): `idr.scan`, a
  combiner region along one axis, destination-passing, `TilingInterface`
  with the scanned dimension tiled in order and its carry passed
  between tiles, lowered by the two-pass method. Gap: no `linalg` scan
  at the pin, and `vector.scan` takes a fixed combining kind on static
  vectors (read: `LinalgStructuredOps.td` has none;
  `M/include/mlir/Dialect/Vector/IR/VectorOps.td:3032`). An ordered scan
  stays the frontend's loop.
- **Filter and compress**: flags, an exclusive integer scan (`idr.scan`
  of `addi`), and an `idr.scatter` without a combiner into a tensor of
  the total's size. Fusion stops there, as it must at a size-changing
  primitive (read: `sources/docs/bqn/implementation/compile/fusion.md:9-11`).
- **Sort**: the library's merge sort on `LArray`; a runtime sort is a
  second meaning of a library function, which §11 forbids.

**decision** (D16) These two ops are ours until upstream has
a scatter with a combiner and a scan with a region combiner; then they
go.

### 4.5 Elements

- **Words and floats** are the builtin element types, the only ones
  that vectorize: `VectorElementTypeInterface` is for builtin types and
  upstream discourages implementing it downstream (read:
  `M/include/mlir/IR/BuiltinTypeInterfaces.td:23-40`).
- **Our types** (a box, a string, a natural, a closure) are legal tensor
  elements, and memref elements through `MemRefElementTypeInterface`,
  which they implement (read: `IdrTypes.td:23-97`). They tile, fuse and
  bufferize; they never vectorize.
- **A counted element** is a tensor element too, with one path, not two
  (**decision**, D17): bufferization's `memCpyFn` is the
  runtime's counted copy, which increments every element it copies, and
  `MoveOut` keeps moving an element out ahead of a write on the
  bufferized memref. The earlier draft kept counted elements on the
  memref path by a measurement; one representation is the stronger
  rule, and stage 2 measures the cost on an array of boxes.
- **A record element** is one tensor per field, by one-to-N type
  conversion (`ConversionPatternRewriter::replaceOpWithMultiple`, 1:N
  `TypeConverter`), and a loop over it is a multi-result
  `linalg.generic`. This is the one representation of columns: 0008's
  `!idr.columns<@T>` is replaced by it (0008 is updated). A record that
  holds an array holds its tensor, split into its fields before
  bufferization, so bufferization never sees through our records.
- **A sum element** is decided by 0008's layouts, in these terms: a tag
  tensor and one tensor per field slot, or a tensor of boxes.

## 5. Effects, order and the raising

**decision** (D10, kept from the earlier draft) A loop's form
is chosen by its body's effects. A body whose ops are all free of
effects by `MemoryEffectOpInterface` (no `idr.crash`, no world, no call
whose inherent `effects` say it may write, diverge or crash) is raised
from `scf.for` to `linalg.generic`, and its loop dimension becomes
`parallel` (a `tabulate`) or `reduction` (a fold whose combiner is
reassociable, §6). Any other body stays the frontend's `scf.for`, in
order. The `parallel` iterator is then the fact that order is
unobservable, true by representation, and every upstream transform that
reorders a parallel or reduction dimension is legal on it.

The raising is a pattern set of ours, `idr-raise`, run in the round's
nested function pipeline beside canonicalize, so it applies as soon as
inlining has made a body pure. Gap: upstream raises `scf.while` to
`scf.for` (`scf::upliftWhileToForLoop`) and memref loops to affine, but
has no raising of a tensor `scf.for` to `linalg` (recalled; to be read
against the pin in stage 2). The pattern recognizes exactly the shapes
the frontend writes (§4.1), so it is a small inverse of a small emitter,
not a general loop recognizer. It replaces `ArrayLoops.cpp` and
`ArrayLoopReads.cpp`.

After raising, a named op is recovered where one matches
(`linalg-specialize-generic-ops`), for the contractions upstream tiles
best, and generalized again where fusion needs a generic
(`linalg-generalize-named-ops`).

## 6. Reductions

**decision** (D15) One policy. The meaning of every reduction
and scan is its left fold in index order. A `linalg` reduction iterator
means any order, as upstream treats it (split-reduction, tiling and
vectorization reassociate it; recalled), so a fold is raised to one only
in three cases:

1. **The combiner is one associative and commutative integer op**:
   `addi`, `muli`, `andi`, `ori`, `xori`, `minsi`, `minui`, `maxsi`,
   `maxui` at any width. The law is the op's, by the runtime's meaning of
   the primitive, needing no proof (read: Iverson's partitioning
   identities, `sources/papers/iverson-1980-notation-tool-of-thought/tot1.htm`,
   §4.2).
2. **The combiner is a finite semiring's, whose laws the fork proves.**
   The fork's `Semiring` instances for `ZeroOneOmega` and `SizeChange`
   prove their laws case by case with `Refl` (read:
   `compiler/idris/src/Algebra/SizeChange.idr:59-109`); a finite carrier's
   laws are decided exhaustively (27 cases for three elements). The
   frontend raises a reduction over such a combiner only when the
   instance's law proofs exist, and the combiner is its `i8` form (§9).
   The fact is the instance Idris checked, and its image is the op the
   frontend chose; no attribute records it.
3. **The program asked for an order of its own**: `reduceBlocked k`, whose
   meaning is `k` interleaved left folds (element `i` into fold `i mod
   k`) combined in order, `k` a literal of the program. Its image is
   exact: an `scf.for` over the `q = n / k` rows of a `[<q, k]` reshape,
   carrying a `tensor<k x E>` updated by a `linalg.map`, then a fold of
   the `k` in order. The `k` lanes are a parallel dimension, so it
   vectorizes on every lane count that divides `k`, and it prints the
   same on both targets.

Every other fold, a float sum included, is the frontend's `scf.for`. A
float result is then one result on every target, lane width and core
count, by representation, and today's rule that gives a reduction
dimension one lane in `idr-vectorize` is deleted. Fusing a producer into
an ordered fold is `transform.structured.fuse_into_containing_op` on the
loop, which is measured on spectral-norm in stage 4 (conjecture: an
element tile is enough).

The earlier drafts had three policies (the README's ops-only list, a
compiler that never reassociates with library-fixed trees, and
`CommutativeMonoid` proofs selecting an unordered op); this one is the
README's with the semiring case added, and the others are struck.

## 7. The pipeline

Upstream passes wherever upstream has the pass; each of ours names its
gap. Against today's (read: `foreign/idr/lib/Transforms/Pipeline.cpp`):

```text
idr-isolate, idr-contify
the round (idr-simplify): ... nested idr.func(idr-identity, canonicalize, cse,
          idr-raise, idr-redirect) ..., idr-inline, idr-specialize, sccp, ...
idr-defunctionalize
nested idr.func:
  idr-raise                                  final raising, on defunctionalized bodies
  linalg-generalize-named-ops
  linalg-fuse-elementwise-ops                upstream's control function
  transform-interpreter                      the target's schedule (§7.1)
  linalg-specialize-generic-ops
  eliminate-empty-tensors
one-shot-bufferize, or sparsification-and-bufferization when the module
  holds a sparse tensor                      on idr.func (§8, §20 patch U1, U2)
nested idr.func(canonicalize, cse)
idr-stack, idr-accumulate, idr-rc, idr-demand, idr-trmc, idr-tail-loops
idr-narrow
idr-lower, idr-entry
nested func.func:
  transform-interpreter                      vectorization (§7.1)
  idr-narrow-lanes
  convert-linalg-to-loops, canonicalize, cse
idr-returned-arguments
... as today to LLVM
```

Deleted from it: `idr-in-bounds`, the array loops of `idr-lower`, and
`idr-vectorize` as a pass. Bufferization runs once, before counting,
so `idr-stack`, `idr-rc` and everything after them see memrefs, as they
do today, and counting needs no tensor model.

### 7.1 Schedules are IR

Tiling for the cache and vectorization are transform-dialect scripts,
not C++ drivers (**decision**, D20). `idr-target` already
writes the target's facts into the module; it also writes two named
sequences built from them: the tile-and-fuse schedule
(`transform.structured.tile_using_for` or `tile_using_forall`, `fuse`,
`fuse_into_containing_op`, with tile sizes from DLTI's
`L1_cache_size_in_bytes`, read: `M/include/mlir/Dialect/DLTI/`), and the
vectorization schedule (`transform.structured.vectorize` with vector
sizes from the target's lane width, masked for dynamic shapes, read:
`M/lib/Dialect/Linalg/Transforms/Vectorization.cpp:376-395`, then
`apply_patterns` for the lowering patterns). `transform-interpreter`
runs them. Today's `idr-vectorize` (217 lines of C++ over the same
upstream functions) becomes the second script; a schedule a reader
wants to see is printed with the module. Nothing about a target is
decided outside its entry, as AGENTS.md requires.

### 7.2 Fusion

Upstream's elementwise fusion as upstream ships it, with upstream's
default control function (fuse a producer with one use; duplicate
nothing), and producer-consumer fusion through the tile-and-fuse
schedule (`tileConsumerAndFuseProducersUsingSCF`, read:
`M/include/mlir/Dialect/SCF/Transforms/TileUsingInterface.h:444-518`).
Elementwise fusion needs generics (hence the generalization before it),
an all-parallel producer with pure tensor semantics, and a permutation
map on the consumer (read: `ElementwiseOpFusion.cpp:141-190`): exactly
what §5's raising produces from pure bodies. The earlier `compiler.md`'s
`idr-fuse`, its control function and its horizontal merge are deleted.

**The first proof** is `map f (map g x)`: one generic, no array
allocated between the two maps, checked by `idr-expect`'s `fused=@f`
property (no `tensor.empty` or allocation between two loops of `@f`, and
every producer with one consumer fused). Then `softmax` and `matmul`;
then a producer with two consumers, which is not duplicated (its loop
runs once).

## 8. Bufferization and grades

**decision** (D18) One-Shot Bufferize decides every in-place
write, once, on `idr.func`, before counting. Its options:
- `bufferizeFunctionBoundaries`, on `idr.func`, `idr.call` and
  `idr.return` through models of ours shaped like upstream's
  `FuncBufferizableOpInterfaceImpl.cpp`, which needs the module driver
  generalized from `func::FuncOp` (§20, U1).
- `allocationFn` is the runtime's cell allocator, so a buffer is a cell
  whose descriptor's allocated pointer is the cell (as today's
  `ArrayView.cpp`); `memCpyFn` is the runtime's copy, counted for
  counted elements (§4.5).
- No ownership-based deallocation: counting frees cells, and that
  scheme forbids returning a memref that aliases an argument (read:
  `M/docs/OwnershipBasedBufferDeallocation.md:55-70`), which an in-place
  thread through a function does. One ownership system, not two.

**The grade is the wrapper.** A linear array is `!idr.lin<tensor<...>>`,
the grade around the carrier as for every other value, and the verifier
checks it after every pass. `idr::QType` does not implement
`TensorLikeType`: a type interface belongs to the class, so every graded
value, the world and a linear integer included, would become a tensor to
One-Shot (read: `M/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td:18-50`).
The tensor's encoding slot stays free, which `#sparse_tensor.encoding`
needs; the earlier `compiler.md`'s grade-as-encoding spelling is deleted
for that reason.

**How One-Shot meets the wrapper**, with no change to its analysis
(conjecture, settled by stage 2's tests):
- `idr.lin.enter %t` (tensor into the wrapper) is a **release**: its
  model declares its operand read and written. One-Shot therefore puts
  a copy there exactly when `%t`'s buffer is read again after it, or is
  not writable (a constant, a buffer read from the heap). Past a
  release, the buffer belongs to the linear thread alone.
- `idr.lin.use %a` (wrapper to tensor) starts an alias set whose root is
  writable: the release that made `%a` already made its buffer the
  thread's. So the writes of a linear thread need no proof at a use.
- A wrapped function argument or result is not a tensor to the
  boundary analysis at all: our `idr.func` model converts
  `!idr.lin<tensor<...>>` to `!idr.lin<memref<...>>`, and the caller's
  release already happened. A recursive function threading a linear
  array is therefore in place, where upstream's boundary analysis, which
  skips recursive call graphs (read: `OneShotModuleBufferize.cpp:481,
  525`), would assume every operand read and written.
- A store of a tensor into a cell (a field, a capture, an element, a
  message of 0004) is a release too; a read from the heap is
  `bufferization.to_tensor ... restrict`, not writable, so a value
  operation that writes it copies.

This keeps AGENTS.md's rule exactly: a linear binder does not imply
unique ownership, so exclusivity is One-Shot's conclusion at the
release, from every alias in tensor code, never the grade's assumption.
`LArray` is born fresh, so for a program on `LArray` the release copies
nothing (§3.8).

**The in-place promise.** Under `--demand-in-place`, `idr.lin.enter`'s
model returns `mustBufferizeInPlace`, and One-Shot's `verifyAnalysis`
then rejects any program that would still copy there, with its own
conflict ("cannot avoid RaW conflict", read:
`M/lib/Dialect/Bufferization/Transforms/OneShotAnalysis.cpp:1540-1560`).
The driver reports it as `unsupported (uniqueness)` naming the write and
the conflicting read. A copy from a buffer that is not writable is a copy
under both meanings and is allowed. The analysis is the proof; no pass
of ours re-derives it.

**`bufferization.writable`** on a plain tensor argument is derived from
the function's type immediately before the pass and never kept as a
fact between passes: the attribute is discardable (read:
`BufferizationBase.td:48,57`).

**Plain tensors across calls** use upstream's module analysis: a callee
may write its parameter in place, and each caller copies where it still
reads the argument. In a recursive call graph upstream assumes every
operand read and written; the driver reports each copy One-Shot makes
at such a call as a `missed` remark with its conflict (read:
`sources/docs/mlir/docs/Bufferization.md`, "Debugging Buffer Copies";
`BufferizationStatistics::numTensorOutOfPlace`, `Bufferize.h:35`), and
the first `bench/` program with one in its hot path is the threshold for
an upstream change that analyzes a call graph cycle to a fixpoint (§20,
U4).

**`idr.tie_shape`** bufferizes to the same op on the memref, so value
bounds still relate dimensions after bufferization; `idr-lower` drops it.

## 9. Sparse arrays and semirings

**decision** (D21) A sparse array is a dense array's type with
an encoding, not a second kind of array.

```idris
data Level = Dense | Compressed | Singleton | LooseCompressed
record Format (s : Shape) where
  levels : Vect (rank s) Level
  order  : Permutation (rank s)

export
data SArray : (0 fmt : Format s) -> (0 s : Shape) -> Type -> Type
```

`fmt` is erased and monomorphised into the tensor's
`#sparse_tensor.encoding<{map = (d0, d1) -> (d0 : dense, d1 : compressed)}>`,
so CSR, DCSR, COO and CSF are formats of one type, and the same raised
generic lowers dense or sparse: the sparsifier decides the loops (read:
`sources/papers/bik-2022-sparse-mlir/mlir.tex:45-70`). Level types at the
pin: `dense`, `batch`, `compressed`, `loose_compressed`, `singleton`,
`structured[n, m]`, with `nonunique`, `nonordered` and `soa` properties
(read: `M/include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td:165-220`).

**The meaning is the dense array with zeros**, and "zero" is the
semiring's. The library gives each lifted function its absent cases as
its own values at zero (`f 0 0`, `f x 0`, `f 0 y`), which become the
regions of `sparse_tensor.binary` (overlap, left, right) and `unary`, so
the sparse result is the dense one exactly. Any op is admissible inside
those regions (read: `M/lib/Dialect/SparseTensor/Utils/Merger.cpp:1244-1270`);
upstream's own vocabulary already calls them semiring ops (read:
`Merger.h:107, 169, 193-194`).

**Codegen only.** `enable-runtime-library=false`, which is not the
default (read: `M/include/mlir/Dialect/SparseTensor/Pipelines/Passes.h:69`),
gives `sparse-tensor-codegen` and `sparse-buffer-rewrite`. Even then
`sparse_tensor.new`, `out` and `print` call the C runtime (read:
`SparseTensorCodegen.cpp:1531`, `SparseTensorRewriting.cpp:1563`), so the
library never emits them, and the verifier of the contract refuses them.
Storage growth is `memref.realloc`, lowered through the generic
allocation functions the runtime provides.

**Elements.** A sparse element must be `f16`, `bf16`, `f32`, `f64`, `i8`,
`i16`, `i32`, `i64` or a complex float (read: `isValidPrimaryType`,
`M/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:922-930`); `i1`
is not one. Any other element is `unsupported (sparse element)`.

**Semirings as `i8`.** A finite semiring is encoded as small integers
with its additive zero at 0, because `implicitVal` supports only 0 (read:
`SparseTensorAttrDefs.td:218-222`, "For now, we only support `0`"). The
encoding comes from the `Semiring` instance, not from constructor order:
`SizeChange = Smaller | Same | Unknown` has `plusNeutral = Unknown`
(read: `Algebra/SizeChange.idr:8, 56`), so tag order would give the
wrong zero.

| semiring | encoding | plus | times |
|---|---|---|---|
| `ZeroOneOmega` (read: `Algebra/ZeroOneOmega.idr:9`) | `Rig0 = 0`, `Rig1 = 1`, `RigW = 2` | `minui(addi(a, b), 2)` | `minui(muli(a, b), 2)` |
| `SizeChange`, plus `max` in information order, times `<+>` | `Unknown = 0`, `Same = 1`, `Smaller = 2` | `maxui(a, b)` | `minui(muli(a, b), 2)` |
| Boolean (existence) | `0`, `1` | `ori` | `andi` |
| counting | the integer | `addi` | `muli` |
| min-plus (shortest paths) | `i64`, with no implicit zero (dense) | `minsi` | `addi` |

Each is two ops at most, so `reduce` and `binary` regions hold them.
Their laws are decided exhaustively by the fork's own proofs, which is
reduction case 2 of §6. Min-plus's zero is infinity, not 0, so it stays
dense until upstream supports another implicit value.

**Storage.** Positions, coordinates and values are value arrays in a
library record; `sparse_tensor.assemble` at use, `disassemble` into
fresh cells at results. `assemble` "does not perform any sanity test"
(read: `SparseTensorOps.td:76-79`), so the library's constructors check
or prove its invariants. The sparsifier's temporaries are its own
`memref.alloc` with its own frees (read: `SparseTensorCodegen.cpp:139-142`).
**Measurement:** if `disassemble`'s copies take more than 5% of spmv's
time, an upstream change routes the sparse codegen's allocations
through the bufferization options' `allocationFn` (§20, U3).

**A linear sparse array** is not offered: in-place sparse updates are
the sparsifier's own insertion on fresh tensors, and the wrapper rule of
§8 applies unchanged if it is ever needed, because the encoding slot is
free.

## 10. Relations as sparse arrays

A relation is a sparse array of Booleans; a conjunctive query is an
einsum: `Q[a, b, c] = R[a, b] * S[b, c] * T[a, c]` (read: 0011 §5; recalled:
`sources/papers/kjolstad-2017-taco`). The pieces, all upstream:

| relational | sparse array | MLIR |
|---|---|---|
| a relation `R(a, b)` | `SArray fmt [<na, nb] I8`, `explicitVal = 1`: coordinates only, which is a trie | `#sparse_tensor.encoding<{..., explicitVal = 1 : i8}>` |
| an index | a format: CSR is a two-level trie, COO a list of tuples | level types |
| a natural join | a product, co-iterating on the shared variable | `linalg.generic` over sparse operands, or `sparse_tensor.coiterate` |
| `EXISTS`, `COUNT`, `SUM`, `MIN` | a contraction in the Boolean, counting, sum or min-plus semiring | `sparse_tensor.reduce` in a reduction |
| a selection | `sparse_tensor.select` | |
| set difference (a semi-naive delta) | `binary` with an empty overlap region | |
| a recursive query | the delta's fixpoint | `scf.while` around the round |

The coordinates of a relation are dense integers, so every name in it
is interned first: 0007's typed ids are this section's precondition.

**What this subset is.** Plans fixed at compile time: the formats, the
variable order and the join order are the program's. **What it is not**
(read, from the sparsifier's loop emitter): co-iteration merges two
sorted levels with two pointers, linear in the sum of their sizes, not
in the smaller one, so a sparse join here is not worst-case optimal
(recalled: leapfrog triejoin's bound). There are no hash levels, no lazy
levels, no runtime choice of format or variable order, and no indexes
chosen from statistics.

**The boundary with 0011** (**decision**, D22). A plan that
fits this subset is emitted as a sparse array program and compiled by
this lowering. Everything else stays 0011's: COLT's lazy tries, hash
tries, the Free Join planner and its generic-join end, galloping
intersection for worst-case optimal joins, indexes chosen from
statistics, plan variants, e-graphs, and the database's storage, laws
and log shared with bumbledb. 0011's interpreter is specialized for a
plan that does not fit; it is never a second route for one that does.

## 11. The compiler's own consumers

Each consumer is assigned to dense, sparse or 0011, honestly.

- **0007's multiplicity check is a sparse reduction.** Occurrences
  grouped by binder are a compressed level; the check folds each group in
  the 0/1/ω semiring and compares the sum with the declared quantity.
  That is `sparse_tensor.reduce` over a CSR array of `i8`, reduction
  case 2 of §6.
- **Size-change termination is half array, half relation.** Composing
  two size-change matrices is a semiring matrix product in `SizeChange`,
  a sparse `linalg.matmul`-shaped generic over DCSR operands: the fork's
  `Libraries/Data/SparseMatrix.idr` is already DCSR in lists (read). The
  closure is not a sum: the checker keeps a set of `(f, h, matrix)`
  triples (read: `Core/Termination/SizeChange.idr:415-417`, its work
  list), and summing them would merge call paths that must stay apart.
  The closure is a relational fixpoint over that set, 0011's.
- **0006's kernels are where linalg is weakest.** The wavefront machine's
  steps are a stable group by term kind (a sort or a counting scatter),
  gathers of children from the arena, compaction of finished rows, and
  scatters of results: gathers, scatters and filters, where fusion stops
  (§4.4). Its dense parts (per-kind arithmetic on a gathered batch) fuse
  as any map does. 0006's kernels are written as ordinary programs in
  this language, using `select`, `idr.scatter` and `filter`; there is no
  whole-array primitive of the runtime for them, which would be a second
  implementation of library functions.
- **0007's tables** are dense arrays of interned ids, one tensor per
  column (§4.5).
- **0008's layouts** are §4.5's one-to-N conversion of records, chosen
  by 0008's measurements.

## 12. Constants and static normalization

**decision** (D23) One answer. A literal array, or the result
of a closed total computation that static normalization (0006) produces,
is `arith.constant dense<...> : tensor<...>` for word and float
elements, which bufferizes to a non-writable `memref.global` (read: the
Arith bufferization model). It is immortal: its descriptor's allocated
pointer is a static cell header of the runtime's persistent kind (count
0, never freed; read: `runtime/idris_rt.h`), placed beside the data and
not in front of it, and its aligned pointer the global's data. Counting
treats it as it treats every persistent cell, and a write copies it,
which is the value meaning. A constant of any other element is built at
startup. The earlier `idr.array.constant` op is deleted: the header
need not be in front of the data, because the runtime reads it through
the allocated pointer (read: `Conversion/ArrayView.cpp`, "The
descriptor's allocated pointer is the cell"). That `memref.get_global`
lowering, which sets the two pointers, is the one pattern of ours it
needs (conjecture, checked in stage 2).

Static normalization itself is 0006's: no array operation runs at
compile time until it exists, and then it runs as this lowering compiles
it, never as a second implementation.

## 13. Arrays a world orders

`IOArray`, `IORef` and `Buffer` are base's, unmodified, and stay memrefs
threaded by the world: their meaning is mutation in program order.
**decision** (D24) Each op declares `MemRead` or `MemWrite`
on its memref operand instead of on the one global `IOResource`, so
upstream's alias and effect reasoning separates two arrays, and reads of
a buffer no write reaches can be hoisted and CSE'd. The world operand
keeps the order with every other effect. Their accesses keep the
primitive's guard, the runtime's meaning of an access outside the array.
With `idr-in-bounds` gone, base's `IOArray` checks an index in Idris and
the primitive checks it again; **measurement**: fannkuch-redux and the
`Buffer` programs within the run-to-run spread of today's record, else
the replacement is a local pattern relating `newArray`'s size operand to
`memref.dim` where value bounds can read it, never the Presburger engine
again.

`freeze` and `thaw` between an `LArray` and an `IOArray` are
`bufferization.to_tensor ... restrict` (not writable) and a release.

## 14. Multicore, and devices later

After 0004's P4, a parallel dimension of a raised generic is tiled with
`scf.forall` and partitioned across shards by 0004's rule, with
`shard.grid`, `sharding-propagation` and `shard-partition` for region
SPMD where it applies (read: the pinned `shard` dialect). A reduction
across shards is legal exactly when §6 says its order is not observed,
so outputs are identical on one shard and on all. Devices come later
through the same tensor level: nothing above tiling assumes a CPU, and
a device is a target entry. Static linking decides which devices are
possible; the earlier `compiler.md`'s analysis of that (AMD through
KFD on Linux, Metal through SPIR-V on macOS; recalled) is kept for when
the work starts, as is its note that forward-mode differentiation is a
record of two words and reverse mode a library over the generating set,
which is closed under transposition.

## 15. What it deletes

Measured line counts from §1; what replaces each.

| layer | lines | deleted | replaced by |
|---|---:|---|---|
| library | 289 | `Linear/Array.idr`, its Scheme specs, `IArray` | `LArray`, `Linear.Vec`, `libs/mlir-array` (§3.8) |
| frontend | ~320 | `Rank0 \| Rank1`, the spec-string matches, `indexSpaces`, `arrayLoop`'s words-only rule, the per-access guard, `MLIR.idr`'s rank-only memref | ranked tensor types with static dimensions; the generating set's emission (§4.1) |
| dialect | ~707 | `idr.array.new`, `get`, `set`, `generate`, `fold` on unordered arrays, `OpsArrays.cpp` | upstream `tensor` ops; `idr.tie_shape`, `idr.scan`, `idr.scatter` (§4.3, §4.4) |
| conversion | 811 | `ArrayLoops`, `ArrayLoopReads`, `Arrays`, `ArrayView`, `Buffers` for unordered arrays | `idr-raise`; One-Shot with the runtime's allocator; the constant pattern (§12) |
| transforms | 4076 | `InBounds` (3057), `Vectorize` (217), the one-lane reduction rule, Expect's `InBounds` and `PureArrayLoops` | typed accesses; the vectorization script; §6's representation of order; `fused`, `structured-loops`, `in-place` properties |
| runtime | ~90 | the array-loop entry points | the allocator and copy as One-Shot's hooks |
| **code** | **~6,300** | | |

Kept and rebuilt on the new form: `MoveOut` and `Knots` (187 lines),
NarrowLanes' versioning (442), the Vectorize driver's logic as a script,
and the world-ordered half of `Arrays.cpp` and `Buffers.cpp` for
`IOArray`, `IORef` and `Buffer`. Tests: the 40 programs of
`tests/programs/arrays` keep their expected outputs where the program
still means the same (the purge changes their source to the new
library, not their output); the 26 `in-bounds/` dialect tests go with
the pass; the rest of the 36 dialect files are rewritten to the new
ops.

## 16. Rules of AGENTS.md it keeps

- **Idris does types; MLIR does programs.** Shapes, ranks, agreement and
  uniformity are Idris types, checked by Idris. The frontend reads forms
  to choose ranked tensor types and writes each loop's sequential
  meaning; which loops are parallel, what fuses and what is in place are
  decided in MLIR, by upstream's passes, from the ops.
- **One thing, one representation.** One array type (the tensor), one
  loop meaning (the frontend's `scf.for`, raised where pure), one index
  type, one in-place analysis (One-Shot's), one representation of
  columns (N tensors), one answer for constants, one reduction policy.
- **Facts in types.** Rank and static extents are the tensor type;
  quantity 1 wraps the tensor; in-bounds is the guard's absence; order is
  the choice between a loop and a structured op. No fact lives in a
  discardable attribute: `bufferization.writable` is derived just before
  the pass that reads it.
- **Erased does not mean constant**; **indexed vectors do not imply
  contiguous storage**; **a linear binder does not imply unique
  ownership** (§2, §8).
- **No primitive has an implementation in Idris**, and no library
  function has one in the runtime (§11).
- **A megamorphic construct is refused**: a rank that grows at each call
  is `unsupported (polymorphism)` (§2).
- **No oracle**: expected files are the specification; nothing is
  shaped so that Chez can run it (§3.8).
- **Never miscompile silently**: an observable order is never
  reordered; a counted element keeps its counts; a narrowing is guarded
  unless the type proves it exact.
- **Both targets, nothing per target outside the entry**: tile sizes,
  lane widths and cache sizes come from the target's DLTI facts, written
  by `idr-target` into the schedules (§7.1).
- **Static linking**: no sparse runtime library, no `library_call`, no
  OpenMP or async runtime.
- **An upstream bug or gap is fixed upstream**: the patches of §20,
  each with its report, reproducer, `tests/upstream/` check, `PINS.md`
  entry and plan.

## 17. Staged plan

Every stage passes `make check`, `make build`, `make test`, `make
test-idr` and `make test-mlir-tools` on both targets and runs `bench/` on
both. Stage 1 lands right after `make self`, ahead of sharding; the rest
follow in order. New benchmarks, each
with a C counterpart in `bench/c/` and no Chez column: `matmul` (1024,
f64, the C an `ikj` triple loop), `heat` (a 2-D five-point Jacobi step,
2048², 100 steps), `spectral-norm-dense`, `prefix-sum` (an inclusive scan
of 10^8 i64), `histogram` (10^8 bytes into 256 bins), `spmv` (CSR, a
SuiteSparse matrix vendored under `sources/`).

1. **The purge and the rebuild, as one cutover.** `libs/mlir-array`'s
   core (`Array`, `Extents`, `Index`, the generating set, `LArray`,
   `Linear.Vec`); the frontend's ranked tensor types and the emission of
   §4.1; `idr.tie_shape`; `idr-raise`; One-Shot on `idr.func` with the
   U1 patch, the release model of §8 and the runtime's allocator; per-
   memref effects on the world-ordered ops; every deletion of §15; the
   fork's `Table`, `IORef` and `Buffer` users ported in the same change.
   Proof: every array program's expected output unchanged; `make self`
   green and stage 2 equal to stage 3; new `idr-expect` properties
   `structured-loops=@f` (every pure array loop of `@f` is a linalg op),
   `typed-reads=@f` (no guard on a typed access) and `in-place=@f` (no
   copy of an array in `@f`), the last on fannkuch-linear and qsort; a
   reject fixture under `--demand-in-place` naming One-Shot's conflict;
   the eleven array benchmarks within the run-to-run spread of today's
   record or faster, spectral-norm-linear within that of 0.596 s on the
   Mac.
2. **Static extents.** The literal and specialized cases of §4.3, the
   cast propagation measured, `vectorizeNDExtract` on. Proof: a fixture
   whose expected module has static dimensions through a specialized
   call; `vectorized` on the static programs without masks;
   `spectral-norm-dense` at least at spectral-norm-linear's ratio to C.
3. **Fusion and schedules** (§7.1, §7.2). Proof, in this order: `fused` on
   `map f (map g x)`, then `softmax` and `matmul`; a producer with two
   consumers not duplicated; `matmul` and `heat` at parity with their C
   on both targets, else the tile sizes are what the measurement
   changes.
4. **Order.** `idr.scan`, `idr.scatter`, `reduceBlocked`, the finite
   semiring case of §6. Proof: integer reductions and scans vectorized
   across lanes; float reductions bit-equal to the in-order meaning;
   `prefix-sum` and `histogram` at parity with their C; producer fusion
   into an ordered fold measured on spectral-norm.
5. **Index sets, data-dependent shapes and shape arithmetic.** `Table`,
   `filter`, `Ragged`, `accumulate`, `resize`, `Array.Shape.solve`, the
   views. Proof: tests; the tactic within its threshold on the corpus.
6. **Sparse** (§9). `SArray`, codegen only, the U2 patch, `i8`
   semirings. Proof: `spmv` within 1.5x of its C (decision; the CSR C
   loop is the bound), no symbol of the sparse runtime in any linked
   program (`tests/toolchain/static-linking` extended), the semiring
   tables' laws as type-level tests.
7. **Relations and the compiler's consumers** (§10, §11). The
   multiplicity check as a sparse reduction and size-change composition
   as a semiring product, behind the fork's existing results: identical
   verdicts on base and the corpus (0007's gate), and the 0011 boundary
   rule applied to the first relational consumer.
8. **Multicore** (§14), after 0004's P4. Proof: 0004's rules; `heat` and
   `matmul` outputs identical on one shard and on all.

## 18. Rejected alternatives

- **The segment, or collapsed dimension, for a shape that grows** (the
  earlier companions): a uniform form for a megamorphic construct, which
  AGENTS.md refuses. Refused here, and only a shape variable passed
  through uninspected is ever dynamic.
- **An unranked tensor or a runtime-rank descriptor**: linalg takes
  ranked operands only, and reassociations are static.
- **Loop ops of ours on tensors** (`tabulate`, `fold`, `scan` with an
  effect-chosen lowering, the earlier README; `lift` and `idr-batch`, the
  earlier `compiler.md`): the sequential meaning is already `scf` and
  `tensor`, so a second spelling is a second representation. The
  parallel forms are `linalg`, raised.
- **Emitting `linalg` from the frontend**: whether a body may crash is
  known only after inlining and defunctionalization.
- **The grade as the tensor's encoding during bufferization** (the
  earlier `compiler.md`): it takes the slot `#sparse_tensor.encoding`
  needs. **`idr::QType` as a `TensorLikeType`**: it makes the world a
  tensor to One-Shot.
- **Lowering `idr.func` to `func.func` before bufferization, to avoid
  U1**: counting, the stack pass and the tail passes would then run on
  `func.func`, and the function op would change meaning mid-pipeline,
  against 0001's one function op until lowering. **Bufferizing after
  counting**: counting would need a model of tensors, and the cells it
  counts would not exist yet.
- **Keeping `idr-in-bounds`, or porting it onto value bounds**: its facts
  are Idris's, so the right image is no guard, not a proof of a guard
  away. What remains (world-ordered accesses) is measured (§13).
- **`tensor.generate`, `tensor.concat`, `tensor.gather`,
  `tensor.scatter`** (§4.1, §4.4): no destination, always allocating, no
  bufferization model.
- **Ownership-based buffer deallocation**: a second ownership system
  beside counting, which also refuses an in-place thread through a
  function.
- **A whole-array runtime primitive per vocabulary function** (for the
  interpreter, or for folding): a second implementation of library code.
- **`idr.array.constant` and a cell header in front of constant data**:
  `memref.global` with the header beside it is enough (§12).
- **Reassociating float reductions, or any user monoid on a proof
  alone**: floats do not associate, and a general monoid in a hot loop is
  the measurement that would add it. Finite semirings are decided
  exhaustively and are the one proof-licensed case.
- **Shape arithmetic in Idris's conversion** (the earlier `types.md`),
  a word-equation or SMT solver, a shape index language of its own:
  programs accepted here and refused upstream, or a solver beside the
  toolchain.
- **Trailing (NumPy) broadcasting and size-1 stretching**; **leading-axis
  primitives**; **implicit lifting** (Remora, AUTOMAP; read:
  `sources/papers/schenck-2024-automap/paper.pdf`, §1-2); **a glyph
  module**; **arithmetic overloaded across shapes**: the earlier README's
  reasons, kept (§3).
- **The sparse runtime library**, `linalg` `library_call`, `ShardToMPI`,
  OpenMP, the async runtime: C runtimes or shared libraries.
- **Autotuned thresholds and user-visible schedules**: non-reproducible
  builds and a second program beside the program. Schedules are the
  compiler's, from the target's facts, printed with the module.

## 19. Decisions

Decided by the owner, 2026-10-12.

- **D1.** The library is `libs/mlir-array`, plain Idris over base and
  `mlir-linear`, trusted (§3).
- **D2.** Shapes are snoc lists; rank is the form of the shape (§3.1).
- **D3.** Primitives act on trailing cells; agreement is prefix
  agreement, as an indexing map (§3.1, §3.4).
- **D4.** A coordinate is `index` at its access, unguarded because its
  type bounds it by an extent; a bare `Fin` stays a natural; an extent
  enters `index` at allocation, guarded (§2, §4.3).
- **D5.** Arithmetic at one shape, extents by search (§3.3).
- **D6.** Rank is `merge . map . nest`, the empty frame settled by a
  calculator (§3.4).
- **D7.** A generating set known by name; the vocabulary is library code
  (§3.5).
- **D8.** Index sets are a one-parameter interface; `Table` is a data
  type (§3.6).
- **D9.** Names, not glyphs (§3.3).
- **D10.** A loop's form is chosen by its body's effects, read through
  `MemoryEffectOpInterface`, by `idr-raise` (§5).
- **D11.** Idris's equality is unchanged; shape arithmetic is the
  library's tactic (§3.7).
- **D12.** Literal size mismatches are reported as the literals, by a
  fix in the fork recorded in `PINS.md` (§3.9).
- **D13.** The frontend writes each primitive's sequential meaning in
  upstream `scf` and `tensor` ops (§4.1).
- **D14.** `idr.tie_shape` ties dynamic dimensions across calls through
  `ValueBoundsOpInterface`; sizes are `arith` or `affine` on `index`
  (§4.3).
- **D15.** Reductions mean their left fold; `linalg` reductions only for
  a single integer op, a finite semiring with proved laws, or
  `reduceBlocked k` (§6).
- **D16.** `idr.scan` and `idr.scatter` are ours until upstream has a
  region-combiner scan and a combining scatter (§4.4).
- **D17.** Counted elements are tensor elements, with a counted
  `memCpyFn` (§4.5).
- **D18.** One-Shot Bufferize on `idr.func`, before counting, with the
  runtime's allocator and no ownership deallocation; the grade is the
  wrapper, `lin.enter` a release; `--demand-in-place` is
  `mustBufferizeInPlace` (§8).
- **D19.** `Linear.Array` is rewritten on `LArray`; its Scheme specs go
  (§3.8).
- **D20.** Tiling and vectorization are transform scripts written from
  the target's facts (§7.1).
- **D21.** A sparse array is the dense type with an encoding, codegen
  only, semirings as `i8` with the zero at 0 (§9).
- **D22.** A relational plan that fits the sparse subset is a sparse
  array program; everything else is 0011's (§10).
- **D23.** Constants are `arith.constant dense`, an immortal
  `memref.global` with the header beside it (§12).
- **D24.** World-ordered arrays declare their effects on their memref
  (§13).
- **D25.** A rank no analysis fixes is refused; the segment scheme is
  deleted (§2, §18).

## 20. Upstream used, and the patches it needs

| mechanism | for |
|---|---|
| `tensor` (`empty`, `extract`, `insert`, `dim`, `extract_slice`, `insert_slice`, `expand_shape`, `collapse_shape`, `pad`, `cast`) | values, reads, writes, views, reshapes (§4.1) |
| `scf.for`, `scf.forall`, `scf.while`, `scf::upliftWhileToForLoop` | ordered loops, tiles, fixpoints |
| `linalg.generic`, `map`, `reduce`, `fill`, `matmul`, `contract`, `transpose`, `broadcast` | structured loops (§5) |
| `linalg-generalize-named-ops`, `linalg-specialize-generic-ops`, `linalg-fuse-elementwise-ops`, `linalg-fold-into-elementwise`, `linalg-morph-ops` | fusion (§7.2) |
| `TilingInterface`, `tileConsumerAndFuseProducersUsingSCF`, `transform.structured.*`, `transform-interpreter`, DLTI | schedules (§7.1) |
| `linalg::vectorize` with masks and input vector sizes | lanes (§7.1) |
| `ValueBoundsOpInterface`, `ReifyRankedShapedTypeOpInterface`, resolve-dims, `IntegerRangeAnalysis` | dimensions and narrowing (§4.3) |
| One-Shot Bufferize, `BufferizableOpInterface`, `eliminate-empty-tensors`, `to_tensor restrict`, `allocationFn`, `memCpyFn`, `verifyAnalysis` | in place (§8) |
| one-to-N type conversion | record elements (§4.5) |
| `sparse_tensor` encodings, `binary`, `unary`, `reduce`, `select`, `coiterate`, `assemble`, `disassemble`, `sparse-tensor-codegen` | sparse arrays and relations (§9, §10) |
| `arith.constant dense`, `memref.global` | constants (§12) |
| `MemoryEffectOpInterface` | the raising (§5); world-ordered arrays (§13) |
| `shard.grid`, `sharding-propagation`, `shard-partition` | SPMD, by 0004's rule (§14) |

**Gaps filled by ours**, each to go when upstream fills it:
`idr.tie_shape` (no op ties dynamic dimensions across calls),
`idr.scan` (no region-combiner scan), `idr.scatter` (no combining scatter
with a bufferization model), `idr-raise` (no raising of tensor loops to
linalg; recalled, to be read against the pin), the `memref.get_global`
lowering for immortal constants.

**Patches**, each under `upstream/<bug>/mlir.patch` with its report,
reproducer, `tests/upstream/` check, `PINS.md` entry and plan:
- **U1. One-Shot module bufferization on `FunctionOpInterface` and
  `CallOpInterface`.** The pinned driver names `func::FuncOp` 29 times
  and `FunctionOpInterface` never (read:
  `M/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`),
  while upstream's own deallocation passes already take
  `FunctionOpInterface` (read: `OwnershipBasedBufferDeallocation.cpp:168`).
  Upstream has discussed generalizing it (recalled, not read: to be
  checked against llvm main before writing ours, and a backport
  preferred). Plan: the generalization with a test-dialect function op
  in its test, sent to llvm-project's bufferization owners. Needed by
  stage 1.
- **U2. The sparse passes on `FunctionOpInterface`.** `stage-sparse-ops`,
  `sparse-space-collapse` and `lower-sparse-iteration-to-scf` are anchored
  on `func::FuncOp` (read: `M/include/mlir/Dialect/SparseTensor/Transforms/Passes.td:196,
  534, 546`). Plan: `InterfacePass<FunctionOpInterface>`, as other
  upstream passes have moved. Needed by stage 6.
- **U3. Sparse codegen's allocations through `allocationFn`**, by the
  measurement of §9.
- **U4. Boundary analysis of a recursive call graph to a fixpoint**, by
  the measurement of §8.

## 21. What the owner settled

1. **The purge comes right after `make self`,** ahead of sharding.
   Today's arrays are deleted and the stack rebuilt in one cutover; the
   fork's `Table`, `IORef` and `Buffer` users are ported in it, and
   `make self` stays green across it.
2. **One path for counted elements** (D17). A regression stage 1
   measures is a reason to make the counted copy faster, not to keep a
   second path.
3. **The release model of §8** is the design. If One-Shot does not
   accept it, the fallback is the grade carried as the tensor's encoding
   inside the one pass, with linear sparse arrays refused; nothing else.
4. **The Chez column** of `bench/` loses the `Linear.Array` programs
   (D19). The C column is the comparison that matters.
5. **U1 is a patch** to bufferization's module driver, generalized from
   `func.func` to `FunctionOpInterface` and `CallOpInterface`, carried
   under `upstream/` with its plan; no driver of ours.
