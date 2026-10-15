<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0003: a typed array language, MLIR first

**Status:** decided by the owner 2026-10-12 (§18, §20), reconciled
2026-10-14 with the pipeline cutover (c7aa7b62, 5d5f3312; its proposal
at 484d6403). Stage 1 is done: it landed as one hard cutover in the
cutover's swarm wave, and the representation wave (bfdcac70; its
proposal at 484d6403) reshaped it on top, as §1 says. Its proof, like
theirs, is owed on the owner's machine, in the qualification after
0004 (HANDOFF.md); x86_64 Linux is NotRun, and a stage is done only
when it passes on both targets. Stages 2 to 8 follow sharding, in
order. Where the cutover's design governs a topic (the pipeline's
order and how a function is cleaned, promises as facts of the
library's types, names from content, refusals as structured data,
budgets that never reject, measurement, the upstream queue), this file
states only what arrays add.

This file replaced the earlier README and its two companions,
`compiler.md` and `types.md`, which were three drafts of one design and
disagreed on reductions, grades, constants and shapes; this file is the
one design. Every decision below is decided; the rulings that stand
behind the design are the owner's: pure array programs are tensors, rank
has no ceiling, and arrays are redone "MLIR first", Idris's dependent
types mapping onto MLIR's own concepts and the optimizations MLIR runs
on them, not onto layers of our own. Claims are marked: read (the path
given), measured, recalled, conjecture, decision. `M/` below is the
pinned MLIR, `.toolchain/build/llvm-project/mlir/`, and `L/` the pinned
LLVM beside it (llvm main 7208ba24).

The array style is the compiler's organizing principle, not one feature
among others. The frontend's tables (0008), the layouts of their columns
(0009), the relations of the relational core (0012) and the kernels of
the array interpreter (0007) are programs in this language, compiled by
this lowering. The compiler is its own heaviest user.

**The ruling, in one sentence.** Every fact Idris proves about an array
has exactly one image in MLIR, the one upstream already optimizes on: a
shape is a ranked tensor type, a size fixed by the program is a static
dimension, a typed index is an access with no guard, a linear thread of
writes is a destination-passing chain One-Shot Bufferize puts in place,
an unordered combine is a structured reduction, a sparse format is a
`#sparse_tensor.encoding`. An op, type or pass of ours exists only where
upstream has none, and each one names the upstream gap it fills (§19).

## What it changes

- **Sizes are in the type, and the type is MLIR's.**
  `Array : (0 s : Shape) -> Type -> Type`, and its MLIR image is
  `tensor<d0 x ... x E>` with a static `di` wherever the program fixes
  the extent (§2), where the compiler once re-derived, with about 3,000
  lines of Presburger analysis, relations Idris could have proved.
- **A typed access has no guard, and no pass has to remove one** (§2).
- **Arrays are values until bufferization, and bufferization is
  upstream's.** One-Shot Bufferize decides every in-place write, once;
  a linear thread is a chain it puts in place by its own exact analysis.
  The in-place promise is a fact of `LArray`'s type, as the cutover made
  every promise a fact of the library's types: each link of a thread
  must bufferize in place, by the analysis's own check, every time (§8).
- **Loops are upstream ops once effects are final.** The frontend writes
  each generating function as one op of ours on tensors (`idr.tabulate`,
  `fold_last`, `scan_last`, `tabulate_io`, with its region), and
  `idr-structure-loops` lowers each one to one: a body without effects
  becomes `linalg`, where upstream fuses, tiles and vectorizes it, any
  other an ordered `scf.for` nest (the representation wave's D6, which
  reversed this design's first form, `scf` from the frontend; §4, §5).
- **Order is a fact of the representation.** A `linalg` reduction means
  any order; an ordered fold is an `scf.for` (§6), so no rule of the
  vectorizer has to keep float sums in order.
- **Sparse arrays and relations are the same tensors with an encoding**
  (§9, §10), and the compiler's semiring analyses are sparse array
  programs (§11).

## 1. What stage 1 built

Stage 1 purged the array stack the tree had before it and rebuilt it in
one hard cutover, in the pipeline cutover's swarm wave (c7aa7b62,
5d5f3312), and the representation wave reshaped it (bfdcac70). It
deleted about 6,300 lines: `Linear.Array` with its Scheme specs and
`IArray`, the frontend's rank-0-or-1 memrefs and its guard on every
access, the `idr.array` loops and their conversions to `linalg`,
`idr-in-bounds` with its Presburger proofs and its 26 dialect tests,
`idr-vectorize` and its per-triple lane width. In their place stand
`libs/mlir-array` (`Array`, `Extents`, `Index`, `LArray`,
`Linear.Vec`), whose generating set is bodiless `%extern`s in
`Array.Core`; ranked tensor types, static wherever an extent's normal
form is a literal; the frontend's array ops (`idr.tabulate`,
`tabulate_io`, `fold_last`, `scan_last`, `transpose`), which
`idr-structure-loops` lowers one to one once effects are final;
`idr.tie_shape` (§4.3); `idr-columns`, which splits a tensor of records
into one tensor per field right after the optimizer (§4.5); One-Shot
Bufferize on `idr.func` through patch 24 (U1, §19), with the release
model, the links as `mustBufferizeInPlace` and the wrapper's one type
conversion (§8); immortal constants (§12); the world-ordered arrays as
memrefs in their own memory space, `#idr.world` (§13); the
vectorization schedule, read per target from the module's DLTI (§7.1);
NarrowLanes, rebuilt on the new form; and the fork's `Table` on base's
`Data.IOArray`, its dependency on `mlir-linear` gone (D38). Its proof
(every array program's expected output unchanged, the
`structured-loops`, `typed-reads` and `in-place` properties, the array
programs of the bench within D35's 2% of the 2026-10-13 record, the
walls of the arrays stage and of the self-compile recorded) is owed in
the qualification on the owner's machine (HANDOFF.md); nothing of it
has been built or run.

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
| an extent at quantity many (`Extents s`, `{n : Nat}`) | a natural, narrowed to an `index` value where it sizes an allocation (guarded there, §4.3): the operand of `tensor.empty` and `linalg` destinations | `ValueBoundsOpInterface` relates it to every `tensor.dim` of the arrays built from it (`M/include/mlir/Interfaces/ValueBoundsOpInterface.h:281-292`) |
| two arrays indexed by one size variable | their dynamic dimensions tied to one `index` value by `idr.tie_shape` at the function's entry | `ValueBoundsConstraintSet::areEqual` across calls, through the op's `populateBoundsForShapedValueDim` (§4.3) |
| `n + m`, `n * m` in a shape | `arith.addi`, `arith.muli` with `nsw nuw` on `index`, or `affine.apply`; `n * m` kept as two dimensions where the type has two | value bounds' arith and affine models; never the `index` dialect, which has no model (`M/lib/Dialect/Index/IR/`) |
| `Index s`, a coordinate of an array of shape `s` | an `index` per axis at the access; inside a structured op, `linalg.index` | no guard; `linalg.index` carries `0 <= i < dim` (`M/lib/Dialect/Linalg/IR/ValueBoundsOpInterfaceImpl.cpp:20-48`); transfers get `in_bounds = [true]` |
| a bare `Fin n` with no array | a natural, narrowed where proved, as every `Nat`-shaped value | `idr-narrow` |
| `x !! i` | `tensor.extract %x[%i...]` | the load's in-bounds precondition, which `memref.load` lowering already assumes (`inbounds` GEP, `MemRefToLLVM.cpp:40-53`) |
| `update x i v`, a write | `tensor.insert %v into %x[%i...]` | One-Shot Bufferize's in-place analysis |
| a linear thread of writes (`LArray s a` at quantity 1) | `!idr.lin<tensor<...>>`, unwrapped by `idr.lin.use` into a destination-passing chain | One-Shot's analysis puts it in place; each link of the thread is `mustBufferizeInPlace`, always, so a copy there fails One-Shot's own check (§8) |
| an element type that is a word or float | the builtin element type | vectorization (`VectorElementTypeInterface` on builtin types) |
| an element type of ours (a box, a string, a natural) | `tensor<?x!idr.T>`, legal since a tensor takes any non-builtin element (`M/lib/IR/BuiltinTypes.cpp:435`) | tiling, fusion and bufferization, through `MemRefElementTypeInterface`; never vectorized (§4.5) |
| a record element | one tensor per field, by one-to-N type conversion | multi-result `linalg.generic`; the one representation of columns (§4.5, 0009) |
| an array of arrays of one cell shape | one tensor, the dimensions concatenated | `expand_shape`, `collapse_shape` |
| a shape whose rank no analysis fixes (a recursion that builds it deeper) | nothing: `unsupported (polymorphism)` naming the site | the frontend's growing-skeleton refusal, which exists (read: `Translate/Instances.idr`, `growing`) |
| a combine whose order is unobservable | a `linalg` reduction iterator, structured from a loop whose combiner is one integer op, or from the frontend's `scf.parallel` where the instance proves the laws (§6) | upstream's tiling, split-reduction and vectorization, which reassociate it |
| a combine whose order is observable | `scf.for` with `iter_args` | nothing reorders a loop-carried value |
| a body that can crash, diverge or touch the world | `scf.for` | `MemoryEffectOpInterface` on its ops, read by the structuring (§5) |
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
`mlir-linear`, a trusted library as `mlir-linear` is (**decision**, D1).
Read as written, every definition is the meaning; the compiler knows a
generating set by name and lowers it to upstream ops with the same
meaning (§4). *Since the representation wave's D5,* the generating set,
`LArray`'s operations among it, is bodiless `%extern` declarations in
`Array.Core`, as `mlir-linear`'s primitives are, `Array` and `LArray`
are exported without constructors, and the rest of the library is plain
Idris over them; the registry reads each entry's arity, quantities and
erasure from the declaration's own type, and no Idris body or evaluator
restates them. Modules: `Array` (types, generating set, vocabulary,
interfaces), `Array.IndexSet`, `Array.Shape` (lemmas, views, the solver
of §3.7), `Array.Ragged`, `Array.Sparse` (§9), `Array.Display`.

The examples type-check against a mock of this library with the same
types (measured: the pinned Idris 2, 0.8.0-1c630e67c, by the earlier
draft's research probes).

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
binds the sizes at quantity many, so they are runtime values, each
narrowed to the `index` operand of the allocation it sizes (§4.3); a
function whose sizes are erased reads them off its arguments with
`shape`, which is `tensor.dim`.

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

withArray : Extents s -> a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b
read      : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))
write     : (1 _ : LArray s a) -> Index s -> a -> LArray s a
freeze    : (1 _ : LArray s a) -> !* (Array s a)
thaw      : Array s a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b
```

The continuation is linear and returns `!* b`, Linear Haskell's
`alloc :: Int -> a -> (Array a %1 -> Ur b) %1 -> Ur b`. Typechecking the
ports with the pinned Idris *measured* why: with an unrestricted
continuation returning a bare `b`, no program can hold two linear arrays
at once. A second `withArray` inside the first's continuation returns `b`
where `!* b` is needed, and an unrestricted continuation cannot capture
the first array. The only `!* b` a continuation can build is `MkBang`,
whose field is unrestricted, so no linear array leaves in it.

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
`Linear.Vec n a`, the growable linear array, is a record of an
`LArray [<cap] a` and its size `n` with `LTE n cap`, read and written at
a `Fin n` (so a position past the size cannot be written, and `pop` takes
a `Vec (S n) a`), growing by a fresh array of twice the capacity and one
`insert_slice`. Its `%foreign
"scheme:..."` primitive specs go: they were kept so `bench/` could run
these programs on Chez, and AGENTS.md says not to shape a feature so
that Chez can run it.

*Superseded by the representation wave's D5:* `LArray`'s operations
(`withArray`, `read`, `write`, `freeze`, `thaw`, `shape`, `grow`) are
bodiless `%extern`s whose one meaning is the compiler's lowering, so no
body over `Data.IOArray.Prims` is left and no Chez backend runs an array
program; the extents argument below stands. The first form follows, as
decided.

**No primitive of its own** (**decision**, D37). The earlier text made
the library's two primitives declared runtime primitives of the
registry; the typed design supersedes both. `prim__index`, the bounds
check, is what a typed index makes unnecessary (§3.2). `prim__arraySize`,
the backing's length, cannot give a shape of rank above one, whose
backing length is the product of its extents, so an `LArray` carries its
`Extents s`, a singleton of its shape that cannot drift from it, and its
MLIR image is the tensor's dimensions (`shape`, §4.1), held once. So
`LArray` is plain Idris over base's `Data.IOArray.Prims` (D1), its
writes updating the backing in place under the library's trust as
`Linear.Array`'s do today (read: `Array.idr:136, 144`), a meaning that
is right on every backend because no old version is read. The frontend
never emits that body: it knows the type and the operations by name and
writes §8's chain. Reason, beyond the rank: the frontend's host build
runs on Chez, AGENTS.md's one exception and stage 0 of `make self`
(read: `tools/self.sh:12-14`), and base's primitives are the ones Idris's
Chez backend and the runtime both implement, so nothing of ours needs a
Chez meaning and nothing is shaped for Chez. Whether the Chez column of
`bench/` keeps the programs rewritten on the library is incidental: it
keeps one only where Idris's Chez backend runs it as written
(conjecture: nothing in the library is Chez-specific; §20 item 3).

**The fork's table** (**decision**, D38). `Libraries/Data/Table.idr` is
a growable table the compiler's context holds in a `Ref`, an `IORef`
(read: `Core/Context/Context.idr:401`; `Core/Core.idr:1050-1058`), and
threads through it on every access (`threadRef`, `Core/Core.idr:1071-1077`).
An `LArray` cannot live there: none exists unrestricted (above), and
§8's `restrict writable` for a linear array read from a cell (D33) rests
on exactly that. Today's table gets its array unrestricted from
`mkArray` (read: `Table.idr`, `newTable`; `Array.idr:118-124`), the hole
the new library closes. Its meaning is mutation in program order of a
table the world orders, which is §13's case, so it moves onto base's
`Data.IOArray`, keeping the doubling growth that makes claiming `n`
slots copy fewer than `2n` entries. `Table.idr` is the fork's only
importer of `mlir-linear` (read: `Table.idr:10-12`; no other `import
Linear.` under `compiler/`), so the fork's `depends = mlir-linear`
(read: `compiler/idris/idris-compiler.ipkg:6`) goes in the same change,
and the fork's build no longer waits on our libraries installed for the
pinned Idris (read: `Makefile:186`, the fork's stamp on `host-libs`;
the bench's Chez baseline still installs them, `Makefile:230-236,
299`). A later fork module that
threads an `LArray` (0011's Levenshtein row, if its bench calls for it)
brings back a dependency on our libraries, and D37 is what lets the
host run it.

### 3.9 Errors and the interactive loop

Shape errors are Idris type errors at the user's line (measured: "When
unifying: Array [<4] Int and: Array [<3, 4] Int"; "Can't find an
implementation for Agree [<3, 4] [<4]"). The library names its evidence
for the rule a reader recognizes (`Agree`, `LTE`, `count`). Idris
reports a mismatch of two literal sizes as their unary forms;
**decision** (D12) that message is fixed in the fork's
unifier error, as the fork's own code, recorded in `PINS.md`, with the
change against the pin in `upstream/<bug>/pull-request.diff` for the
re-sync to read, never sent (AGENTS.md: Idris takes no contribution
written with a coding agent). There are no runtime shape
errors in typed code.

The interactive loop (`idris-mlir repl`, every line compiled and run as
a linked executable in a child, never on Idris's evaluator or Chez) is
the earlier draft's D13. It is not on the array path, and it has moved
to 0007 (§8 there), which owns it.

## 4. The generating set, as upstream ops

### 4.1 What the frontend emits

*Reversed by the representation wave's D6, which the tree now is:* the
frontend writes `idr.tabulate`, `idr.fold_last`, `idr.scan_last`,
`idr.tabulate_io` and `idr.transpose`
(`foreign/idr/include/idr/IR/IdrArrayOps.td`), each with its region,
iterator kinds and row-major order, and `idr-structure-loops` lowers
each one to one once effects are final; the table's `scf.for` rows are
that lowering's ordered form, no longer the frontend's output, and the
recognizer this section implies is deleted. The first form follows, as
decided.

**decision** (D13, reversed by the representation wave's D6; §18 says
why) The frontend writes each primitive's sequential meaning in upstream
ops, and nothing of ours but the grade casts and `idr.tie_shape`:

| primitive | emitted |
|---|---|
| `shape` | `tensor.dim` per dynamic dimension, a constant per static one |
| `tabulate e f` | `tensor.empty(%dims)` and an `scf.for` nest whose body computes `f` and `tensor.insert`s it at the induction variables |
| `(!!)` | `tensor.extract` |
| `foldLast g z x` | an `scf.for` over the last axis carrying the accumulator in `iter_args` (the frame a loop nest around it, or a tensor of accumulators); for a finite semiring whose laws the instance proves, `scf.parallel` with an `scf.reduce` instead (§6) |
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

Every loop the frontend writes is the program's meaning, in its order;
the one loop whose order the program leaves free, a fold over a finite
semiring whose laws Idris checked, is written as upstream's unordered
loop, `scf.parallel` (§6). Turning a loop into a structured op is the
MLIR side's decision, made after defunctionalization and the optimizer's
inlining (stages 4 to 10 of the cutover's §4) have shown what the body
does (§5). The frontend cannot make it: whether `f` may crash depends on
code it has not inlined. That is the earlier draft's reason for
rejecting linalg from the frontend, kept, and its own loop ops
(`tabulate`, `fold`, `scan`, `lift`, `rebase`, `thaw`, `constant`,
`alloc`, `copy`, `sort`) are deleted: the sequential meaning is already
expressible in `scf` and `tensor`, so a second spelling of it would be a
second representation.

### 4.2 Reads become indexing maps

A pure body that reads another array at an affine function of the
induction variables (`x !! [<i]`, `a !! [<i, p]`, `x !! [<i + 1]`) is an
input of the structured generic with that function as its indexing map; a
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
form at that instance is a literal, and where a call passes a constant
extent. The constant is part of the call's static pattern, so the clone
is a specialization node for (callee, pattern), made once, named from
its key and scheduled in the same ready set as every other function (the
cutover's §4.8). Today's keys already take a constant as its own key,
under the binding-time rules (read:
`lib/Transforms/Specialize/Keys.cpp:6-10, 39-60`; a plain constant is
its own key at `:47`). **decision** (D39) For an array argument the
static pattern is a type: where the caller's tensor is more static than
the callee's parameter, MLIR's call typing makes the frontend write a
`tensor.cast` to the parameter's type at the call, and the cast's source
type is the argument's pattern, under the same binding-time rules as any
static value. The fact is already in a type, so the key reads it and
nothing records it again. A clone specialization does not make leaves
the extent dynamic: the same program, less optimized, never a refusal
(the cutover's §2.5). What stopped it was the budget `kClonesPerOwner`,
which the cutover built as `kKeysPerOwner` and the representation wave's
D4 deleted for the request-chain rule over specialization keys: a new
key is not made when it embeds an ancestor key on its request chain;
inside a recursive component only a parameter passed on unchanged keys
(the representation wave's §11). The clone's entry casts its array
arguments to the static type with `tensor.cast`, and upstream's
cast-folding canonicalizations, run by the inner per-function pipeline,
carry the static type into the destination-style ops that consume it
(read: `FoldTensorCastProducerOp`, `TensorOps.cpp`; the one
configuration is upstream's canonicalizer,
`include/idr/Transforms/Canonicalize.h:33-44`, which collects every
loaded dialect's and registered op's patterns,
`M/lib/Transforms/Canonicalizer.cpp:75-80`). How far that propagation
reaches through our ops is measured in stage 2 (conjecture).

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

- **Gather** (`select`, a read at a computed index): a generic
  whose body does `tensor.extract` at the computed index. The
  vectorizer's n-D extract path makes it a gather or a contiguous load
  (read: `vectorizeNDExtract`, which `idr-vectorize` turns off today:
  `Vectorize.cpp:142` [143-144]; here it is on, from stage 2). No op of
  ours.
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

**decision** Like the generics, `idr.scan` and `idr.scatter` are made by
`idr-structure-loops` from the frontend's loops (§5; since the
representation wave's D6 those are its array ops, §4.1), never written by
the frontend (D13), and only for a combiner of §6's case 1, one integer
op, which the structuring reads off the body, or for the one scatter
without a combiner that `filter` writes: a write guarded by a flag, at
the flags' exclusive `addi` scan, whose positions are distinct by that
scan's construction. A scan or scatter over a
finite semiring stays the frontend's ordered loop: `scf.parallel` cannot
state it, since its iterations writing one destination would race
(read: `SCFOps.td:855-857`), and no consumer of §11 needs one (the
multiplicity check and size-change composition are reductions, filter
and histogram are `addi`). A measured consumer is what would give that
fact an image.

### 4.5 Elements

- **Words and floats** are the builtin element types, the only ones
  that vectorize: `VectorElementTypeInterface` is for builtin types and
  upstream discourages implementing it downstream (read:
  `M/include/mlir/IR/BuiltinTypeInterfaces.td:23-40`).
- **Our types** (a box, a string, a natural, a dispatch sum) are legal
  tensor elements, and memref elements through
  `MemRefElementTypeInterface`, which they implement (read:
  `IdrTypes.td:23-97`). They tile, fuse and bufferize; they never
  vectorize.
- **A closure or a suspension** is never an element by the time an array
  pass runs: defunctionalization runs before the optimizer, so every
  closure- or lazy-typed element is a dispatch sum (a sum element,
  below) before §5 sees it (the cutover's §2.7). Before that, the label
  solve follows an element through the anchor of its element type, one
  slot for every array of that type whatever its rank (read:
  `include/idr/Analysis/Labels.h:170-180`). That rule and the keys that
  convert array types are written once over `ShapedType`, so a tensor
  and a world-ordered memref share the one rule (**decision**, D28). The
  upstream ops the frontend writes that move one element in or out
  (`tensor.insert`'s scalar, `tensor.extract`'s result, `tensor.pad`'s
  yield) get the flow interface as external models, attached at
  registration as their bufferization models are, each declaring the
  anchor as its edge. An op that moves a whole tensor (`insert`'s
  destination, the slices, `cast`, the reshapes, `idr.tie_shape`, a
  loop-carried tensor) carries no label set of its own, since the
  anchor, not the tensor value, holds the labels. A closure carried by
  one of the frontend's loops (a fold whose accumulator has a function
  type) moves along `scf.for`'s region edges and `scf.yield`'s operands,
  which upstream declares through `RegionBranchOpInterface` (read:
  `M/include/mlir/Dialect/SCF/IR/SCFOps.td:167`, and `:1240`,
  `ReturnLike`) and the flow rule reads as it reads a match's (the
  cutover's §2.2), so the loops need no model of ours (**decision**,
  D41). Since the representation wave the frontend's loops are its array
  ops, which implement `RegionBranchOpInterface` themselves, and the
  forwarding is derived once from that interface (the representation
  wave's D6, D7). So the verifier, which refuses a closure- or
  lazy-typed operand on an op without the interface (the cutover's
  §2.2), accepts every array program, and closure flow is still held
  once.
- **A counted element** is a tensor element too, with one path, not two
  (**decision**, D17): bufferization's `memCpyFn` is the runtime's
  counted copy, which increments every element it copies; `MoveOut`
  moves an element of a world-ordered array out ahead of its write
  (`idr.array.update`), and on a value array's buffer an element that
  leaves its place moves out with the buffer's reference
  (`idr.element.update`, 0004: a vector's pop reads its last element and
  writes the fill behind it, with no increment and release). The earlier
  draft kept counted elements on the memref path by a measurement; one
  representation is the stronger rule, and the qualification of stage 1,
  which made counted elements tensor elements, measures the cost on an
  array of boxes (§20 item 1).
- **A record element** is one tensor per field, by one-to-N type
  conversion (`ConversionPatternRewriter::replaceOpWithMultiple`, 1:N
  `TypeConverter`), and a loop over it is a multi-result
  `linalg.generic`. This is the one representation of columns: 0009's
  `!idr.columns<@T>` is replaced by it (0009 is updated). The conversion
  is `idr-columns` (the representation wave's D20): the frontend writes
  a tensor of records (`tensor<…x!idr.data<r>>`, no columns type in its
  Core), and the pass splits it right after `idr-optimize`. A record
  that holds an array holds its tensor, split into its fields before
  bufferization, so bufferization never sees through our records.
- **A sum element** is decided by 0009's layouts, in these terms: a tag
  tensor and one tensor per field slot, or a tensor of boxes.

## 5. Effects, order and the structuring

**decision** (D10, kept from the earlier draft) A loop's form is chosen
by its body's effects. A body whose ops are all free of effects by
`MemoryEffectOpInterface` (no `idr.crash`, no world, no call whose
`effects` say it may write, diverge or crash) is turned from `scf.for`
into `linalg.generic`, and its loop dimension becomes `parallel` (a
`tabulate`) or `reduction` (a fold whose combiner is reassociable, §6).
Any other body stays the frontend's `scf.for`, in order. The `parallel`
iterator is then the fact that order is unobservable, true by
representation, and every upstream transform that reorders a parallel or
reduction dimension is legal on it. A call's `effects` are the verified
cache of its callee's summary, written once by the bottom-up summaries
(the cutover's §4.9; `IdrOps.td:59-75`), so the structuring reads a
fact, never an analysis of its own. *Since the representation wave:* the
structuring takes the frontend's array ops, not `scf.for`, and lowers
each one to one (a body with no effect beyond Crash over word elements
to `linalg.generic`, any other to an ordered `scf.for` nest; D6); and a
call holds no effects, so it reads the callee's summary through the
symbol table (D13). The recognizer described next is deleted.

The structuring is a pattern set of ours, `idr-structure-loops`, run
once per function, in parallel, in the arrays stage that follows the
optimizer (§7). By then defunctionalization has made every body
first-order, the optimizer has inlined what it will, and each remaining
call's effects are final, so one pass over each final body decides
every loop (**decision**, D26). Gap (read): no pass of the pinned MLIR
turns a tensor `scf.for` into `linalg`. `raise-scf-to-affine` raises to
affine loops only (`M/include/mlir/Conversion/Passes.td:1218-1244`),
`affine-raise-from-memref` rewrites memref accesses
(`M/include/mlir/Dialect/Affine/Transforms/Passes.td:400-408`),
`convert-elementwise-to-linalg` takes single elementwise ops on tensors
(`M/include/mlir/Dialect/Linalg/Passes.td:110-120`), and the linalg
form conversions go between linalg forms only (`Passes.td:88-103`).
Upstream also raises `scf.while` to `scf.for`
(`scf::upliftWhileToForLoop`). The pattern recognizes exactly the shapes
the frontend writes (§4.1), the `scf.parallel` of §6's case 2 included,
so it is a small inverse of a small emitter, not a general loop
recognizer. It replaces `ArrayLoops.cpp` and `ArrayLoopReads.cpp`.

Its name is not "raise" (**decision**, D27): the pipeline keeps that
word for the specializer's arity raising
(`lib/Transforms/Specialize/Raise.cpp`; the cutover's §2.7, §4.8), and
two passes called raising would be one name for two things. "Structured"
is linalg's own word for its ops, and `structured-loops` is the property
that checks this pass (§16).

The structuring makes generics, which is what fusion needs
(`linalg-generalize-named-ops` turns any named op back into one). Named
ops are recovered after fusion and the tile-and-fuse schedule
(`linalg-specialize-generic-ops`, §7), for the transforms and readers
that match them: `linalg-block-pack-matmul` takes `linalg.matmul` and
its variants (read: `Passes.td:194-210`).

## 6. Reductions

**decision** (D15) One policy. The meaning of every reduction
and scan is its left fold in index order. A `linalg` reduction iterator
means any order, as upstream treats it (split-reduction turns one
reduction dimension into a parallel one and a second reduction, read:
`M/include/mlir/Dialect/Linalg/Transforms/Transforms.h:1218-1266`;
tiling a reduction computes partial reductions in parallel and merges
them after the loop, read:
`M/include/mlir/Dialect/SCF/Transforms/TileUsingInterface.h:493-520`;
vectorization reassociates it too, recalled), so a fold is
structured as one only in three cases:

1. **The combiner is one associative and commutative integer op**:
   `addi`, `muli`, `andi`, `ori`, `xori`, `minsi`, `minui`, `maxsi`,
   `maxui` at any width. The law is the op's, by the runtime's meaning of
   the primitive, needing no proof (read: Iverson's partitioning
   identities, `sources/papers/iverson-1980-notation-tool-of-thought/tot1.htm`,
   §4.2).
2. **The combiner is a finite semiring's, whose laws the fork proves.**
   The fork's `Semiring` instances for `ZeroOneOmega` and `SizeChange`
   prove their laws case by case with `Refl` (read:
   `compiler/idris/src/Algebra/SizeChange.idr:59-109` [61-158]); a finite
   carrier's laws are decided exhaustively (27 cases for three elements).
   The fact lives in Idris, so the frontend states it (**decision**,
   D32): only when the instance's law proofs exist, it writes the fold as
   `scf.parallel` with an `scf.reduce` whose region is the combiner's
   `i8` form (§9), and the loop's body is only the read and the combine.
   `scf.parallel` is upstream's own statement that the iteration order is
   any and the reduction order unspecified (read:
   `M/include/mlir/Dialect/SCF/IR/SCFOps.td:855-857, 956-960`), so the
   frontend still writes nothing but `scf` and `tensor` (D13), and
   `idr-structure-loops` makes it a reduction iterator. The fact is the
   instance Idris checked, and its image is the op the frontend chose;
   no attribute records it. Case 1 stays the MLIR side's, because a
   combiner is one integer op only after inlining shows it.
3. **The program asked for an order of its own**: `reduceBlocked k`, whose
   meaning is `k` interleaved left folds (element `i` into fold `i mod
   k`) combined in order, `k` a literal of the program. Its image is
   exact: an `scf.for` over the `q = n / k` rows of a `[<q, k]` reshape,
   carrying a `tensor<k x E>` updated in each row by an inner loop over
   the `k` lanes, which `idr-structure-loops` makes a `linalg.map` when
   the combiner is pure (the frontend writes only `scf` and `tensor`,
   D13), then a fold of the `k` in order. The `k` lanes are a parallel
   dimension, so it
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
gap. The order is the cutover's (its §4), which this proposal does not
restate: it adds one stage, the arrays stage, between dead-value removal
(the cutover's stage 10) and the memory passes (its stage 11), and it
holds the vectorization schedule in the place the vectorization group
held inside the lowering tail, after `idr-entry` and before
`idr-returned-arguments` (read:
`foreign/idr/lib/Transforms/Pipeline.cpp:134-151`). Nothing here runs
inside the inner per-function pipeline, and nothing repeats: each step
below runs once. Each line of ours names the stage of §16 that adds it.

```text
the cutover's §4, stages 1 to 10; what arrays rely on there:
  defunctionalization, total, before the optimizer  (closure elements, §4.5)
  the ready set, each function cleaned once by the inner pipeline
  specialization nodes                    (a constant extent is static, §4.3)
  SCC summaries                           (each callee's effects, read by §5)
  idr-columns, then canonicalize, cse      (record tensors to columns, §4.5)
  remove-dead-values, symbol-dce, once
the arrays stage:
  nested idr.func, in parallel:
    idr-structure-loops            stage 1   each array op lowered one to one (§5)
    linalg-generalize-named-ops    stage 3
    linalg-fuse-elementwise-ops    stage 3   upstream's control function (§7.2)
    transform-interpreter          stage 3   the tile-and-fuse schedule (§7.1)
    linalg-specialize-generic-ops  stage 3
    eliminate-empty-tensors        stage 1
  one-shot-bufferize               stage 1   whole program, on idr.func (§8; U1)
    (sparsification-and-bufferization in its place from stage 6; §9, U2)
    ending with the wrapper's one type conversion (§8, D42)
  nested idr.func, in parallel:
    canonicalize, cse              stage 1   the one configuration
the cutover's §4, stage 11: idr-stack, idr-accumulate, idr-rc, idr-demand,
  idr-trmc, idr-tail-loops, idr-narrow
the cutover's §4, stage 12: idr-lower, idr-entry, then in the vectorization
  group's place, nested func.func, in parallel:
    transform-interpreter          stage 1   the vectorization schedule (§7.1)
    idr-narrow-lanes               stage 1   rebuilt on the new form
    convert-linalg-to-loops, canonicalize, cse
  then the rest of stage 12's lowering tail, from idr-returned-arguments
  to idr-tail-calls
the cutover's §4, stages 13 to 16
```

**Why a stage of its own, and why there** (**decision**, D26).
Structuring, fusion and tiling are decisions about final bodies. Tiling
makes `scf` loops of tiles, which nothing a caller inlines around them
afterwards can fuse with, so they follow every inlining. Structuring
reads each remaining call's effects, which the summaries write. And
dead-value removal trims a loop's dead carried values through
`RegionBranchOpInterface`, which `scf.for` implements and
`linalg.generic` does not (read:
`M/lib/Transforms/RemoveDeadValues.cpp:835-848`), so it runs while the
loops are still `scf`. None of this belongs in the inner per-function
pipeline, which cleans a function once its callees are final and is a
fixed list (the cutover's §4.6): the arrays stage is one pass over each
final body, in parallel, and leaves that list as it is. Bufferization
stays before counting, as before: `idr-stack`, `idr-rc` and everything
after them see memrefs, as they do today, and counting needs no tensor
model.

**Whole program, then per function.** One-Shot's module analysis is
whole-program, because which buffer a call may write in place is a
memory fact across calls, the kind decided once on the whole program
(the cutover's §1).
Upstream's driver orders the functions callee first by its own worklist
over the calls and analyzes and rewrites them serially (read:
`M/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:315-371,
479-529, 555-597`). Every other step of the stage runs per function in
parallel. A function without a tensor costs the analysis one walk
(conjecture); the stage's wall on the self-host module is recorded in
the qualification and held to the compile-time threshold of D35
(§16).

**One pipeline** (**decision**, D30). Which bufferization pass runs is
decided by the stage of this plan, never by what a module holds.
`sparsification-and-bufferization` runs One-Shot over everything that is
not sparse, through the same `insertTensorCopies` and `bufferizeModuleOp`
(read: `M/lib/Dialect/SparseTensor/Transforms/SparsificationAndBufferizationPass.cpp:98-124,
132-156`), so from stage 6 it replaces `one-shot-bufferize` for every
module, dense or not.

Deleted from it: `idr-in-bounds`, the array loops of `idr-lower`,
`idr-vectorize` as a pass, and the per-triple lane width
(`lib/Target/Target.cpp:78-87`, §7.1).

### 7.1 Schedules are IR

Tiling for the cache and vectorization are transform-dialect scripts,
not C++ drivers (**decision**, D20). There are two: the tile-and-fuse
schedule (`transform.structured.tile_using_for` or `tile_using_forall`,
`fuse`, `fuse_into_containing_op`, with tile sizes from DLTI's
`L1_cache_size_in_bytes`), and the vectorization schedule
(`transform.structured.vectorize` with vector sizes from the target's
lane width, masked for dynamic shapes, read:
`M/lib/Dialect/Linalg/Transforms/Vectorization.cpp:376-395`, then
`apply_patterns` for the lowering patterns). Today's `idr-vectorize`
(204 lines of C++ over the same upstream functions) becomes the second
script, at stage 1, since stage 1 deleted the pass and its benchmarks
must not lose their vectors; the first comes with fusion at stage 3.

**One library, read per target** (**decision**, D29). The scripts are
one source file of ours, built into the tools, written once for every
target: they read the target's facts from the payload's module with
`transform.dlti.query` (read:
`M/include/mlir/Dialect/DLTI/TransformOps/DLTITransformOps.td:18-45`),
`L1_cache_size_in_bytes` and `max_vector_op_width` from the module's
`dlti.target_system_spec` (read: `M/include/mlir/Dialect/DLTI/DLTIAttrs.td:180-190`).
So the schedule is held once, not written into every module, and the
facts are held once, in the module, from the target's entry. A reader
sees the schedule as the file and the facts it read printed with the
module.

**Where the facts come from** (**decision**, D29). `idr-target` already
writes the target's triple and CPU on the module and lets LLVM fill in
the CPU's features and the data layout (read:
`include/idr/Transforms/Passes.td:45-56`). It also writes the two facts
the scripts read. The lane width is LLVM's answer for the entry's CPU,
`TargetTransformInfo::getRegisterBitWidth` for fixed-width vectors
(read: `L/include/llvm/Analysis/TargetTransformInfo.h:1436`), as the
features already are; this deletes `vectorBits`, which tests the triple
for x86 and its AVX features and answers 128 otherwise
(`lib/Target/Target.cpp:78-87`, read), a per-target case outside the
entry. The L1 data cache's size is a fact of the target's entry in
CMakeLists.txt, beside the page size, because LLVM knows it for x86 only
(read: `L/lib/MC/MCSubtargetInfo.cpp:486-488` answers nothing;
`L/lib/Target/X86/X86TargetTransformInfo.cpp:114-127` answers 32 KiB).
The entries' values: 32 KiB for `x86-64-v3`, LLVM's own answer, and
128 KiB for `apple-m1`, the performance core's (recalled); stage 3's
parity rule is what changes them. Nothing about a target is decided
outside its entry, as AGENTS.md requires.

**Run per function** (**decision**, D29). The library is parsed once
when a tool creates its context and loaded into the transform dialect's
library module (`TransformDialect::loadIntoLibraryModule`, read:
`M/include/mlir/Dialect/Transform/IR/TransformDialect.td:94-101`).
`transform-interpreter` then runs nested on each function, in parallel:
it looks for its entry point in its anchor and then in the preloaded
library (read:
`M/lib/Dialect/Transform/Transforms/InterpreterPass.cpp:129-153`;
`TransformInterpreterUtils.cpp:198-215`), and an entry point inside the
library is applied without merging the library into the payload (read:
`TransformInterpreterUtils.cpp:285-293`). That the interpreter may run
over many functions at once against one shared library is a conjecture,
checked in the qualification by `tests/determinism` at 1, 2 and 8
threads and a ThreadSanitizer run; a race there is an upstream bug,
fixed upstream.

### 7.2 Fusion

Upstream's elementwise fusion as upstream ships it, with upstream's
default control function (fuse a producer with one use; duplicate
nothing), and producer-consumer fusion through the tile-and-fuse
schedule (`tileConsumerAndFuseProducersUsingSCF`, read:
`M/include/mlir/Dialect/SCF/Transforms/TileUsingInterface.h:444-518`).
Elementwise fusion needs generics (hence the generalization before it),
an all-parallel producer with pure tensor semantics, and a permutation
map on the consumer (read: `ElementwiseOpFusion.cpp:141-190`): exactly
what §5's structuring produces from pure bodies. The earlier
`compiler.md`'s `idr-fuse`, its control function and its horizontal
merge are deleted.

**The first proof** is `map f (map g x)`: one generic, no array
allocated between the two maps, checked by a new `idr-expect` property,
`fused=@f` (no `tensor.empty` or allocation between two loops of `@f`,
and every producer with one consumer fused). `@f` names the function the
programmer wrote and every copy the optimizer made of it, found as
`idr-expect` finds functions, by structure and facts rather than by a
generated name (the cutover's §6). Then `softmax` and `matmul`; then a
producer with two consumers, which is not duplicated (its loop runs
once).

## 8. Bufferization and grades

**decision** (D18) One-Shot Bufferize decides every in-place
write, once, on `idr.func`, before counting. Its options:
- `bufferizeFunctionBoundaries`, on `idr.func`, `idr.call` and
  `idr.return` through models of ours shaped like upstream's
  `FuncBufferizableOpInterfaceImpl.cpp`, which needs the module driver
  generalized from `func::FuncOp` (§19, U1).
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
(conjecture, settled by stage 1's tests when they first run; stage 1
gave the two ops, `include/idr/IR/IdrOwnershipOps.td`, their
bufferization models):
- `idr.lin.enter %t` (tensor into the wrapper) is a **release**: its
  model declares its operand read and written. One-Shot therefore puts
  a copy there exactly when `%t`'s buffer is read again after it, or is
  not writable (a constant, a buffer read from the heap). Past a
  release, the buffer belongs to the linear thread alone.
- `idr.lin.use %a` (wrapper to tensor) starts an alias set whose root is
  writable: the release that made `%a` already made its buffer the
  thread's. So the writes of a linear thread need no proof at a use.
- A wrapped function argument or result is not a tensor to the boundary
  analysis at all: our `idr.func` model converts `!idr.lin<tensor<...>>`
  to `!idr.lin<memref<...>>`, and the caller's release already happened.
  A recursive function threading a linear array is therefore in place,
  where upstream's boundary analysis, which skips recursive call graphs
  (read: `OneShotModuleBufferize.cpp:481, 525` [479-484, 524-528]),
  would assume every operand read and written; since 0004 patch 24
  analyzes a cycle of calls to a fixpoint (U4).
- A store of a tensor into a cell (a field, a capture, an element, a
  message of 0005) is a release too; a read from the heap is
  `bufferization.to_tensor ... restrict`, not writable, so a value
  operation that writes it copies. A linear array read back from a cell
  is `to_tensor ... restrict writable` (**decision**, D33): the store was its
  release, and no other reference can read it, because a record that
  holds an `LArray` is itself linear by the library's construction (no
  unrestricted `LArray` exists to build one from, §3.8).
- A wrapped tensor that crosses a block or region boundary (a branch
  that contification or a multi-block inlining made, a match's
  yield, a loop-carried value) is no tensor to the analysis either, so
  the analysis needs nothing there: the use beyond the boundary starts
  its own writable root, and the enter before it is a release. Only the
  rewrite must retype it, and One-Shot's own block-signature rewrite
  converts tensor-like arguments only (read:
  `M/lib/Dialect/Bufferization/Transforms/Bufferize.cpp:403-418`). So
  the bufferization step ends with one type conversion of ours, applied
  once to each function: `!idr.lin<T>` becomes `!idr.lin<B>`, where `B`
  is the buffer type One-Shot gave `T`, with the identity layout of the
  runtime's cell, on every block and region argument and op result that
  carries a wrapper (**decision**, D42). It is the conversion our
  `idr.func` model applies to signatures, so the wrapper's types change
  in one place, and the grade is kept, as the verifier checks after the
  step.

This keeps AGENTS.md's rule exactly: a linear binder does not imply
unique ownership, so exclusivity is One-Shot's conclusion at the
release, from every alias in tensor code, never the grade's assumption.
`LArray` is born fresh, so for a program on `LArray` the release copies
nothing (§3.8).

**The in-place promise** (**decision**, D33, amending D18 as the cutover
required). The cutover deleted `--demand-in-place`: a command line that
decides whether a program is rejected makes two languages, so a promise
is a fact of the library's types, emitted by the frontend and checked
every time (the cutover's §4.1, §6). For an array the type is `LArray`,
and its promise is that every write of a linear thread is in place. Its
image: a *link* of a thread, an `idr.lin.enter` whose operand's buffer
an `idr.lin.use` began (directly, or through the destinations of the
writes between them), has the model `mustBufferizeInPlace`, always. A
thread's *head*, an enter whose buffer no use began (`withArray`'s fresh
tensor, `thaw`'s argument), is a plain release, which copies when its
argument is still read, as `thaw`'s meaning says. One-Shot's
`verifyAnalysis` then fails on any copy at a link with its own conflict
("cannot avoid RaW conflict", read:
`M/lib/Dialect/Bufferization/Transforms/OneShotAnalysis.cpp:1540-1560`
[1545-1551]). No program can reach that failure: an `LArray` aliases
nothing by the library's construction (§3.8), and the release model
above leaves no read of a link's buffer after its release. So a failure
there is the compiler's broken invariant, an internal error that names
the write and the conflicting read, never `unsupported` (the cutover's
§2.5). A copy at a head from a buffer that is not writable (a constant
thawed) is the meaning, under every reading, and is allowed. The
analysis is the proof; no pass of ours re-derives it, and `idr-demand`
keeps checking only the promise of cells on the grades `idr-rc` wrote
(the cutover's §4.11): the two promises live on two representations,
tensors and cells, and neither is held twice.

**Where the links are** (**decision**, D43). The canonicalizer folds a
use of an enter, and an enter of a use read nowhere else, to the value
itself, for every linear value (read: `LinUseOp::fold`,
`LinEnterOp::fold`, `lib/IR/OpsScalars.cpp:130-145`), and it runs in
the inner pipeline before the arrays stage. So inside one function a
thread reaches One-Shot as a plain chain of destinations, which its
analysis puts in place because nothing reads an old version, and the
links left are at the thread's boundaries: a call's argument or result,
a block or region argument, a cell. The promise is checked there, every
time. The folds keep no tensor case: one rule for every linear value is
the representation, and an unfolded pair would be the value said twice.
Inside a function the in-place chain is One-Shot's conclusion, and
`in-place=@f` (§16) checks it on the suites' programs.

**`bufferization.writable`** on a plain tensor argument is derived from
the function's type immediately before the pass and never kept as a
fact between passes: the attribute is discardable (read:
`BufferizationBase.td:48,57`).

**Plain tensors across calls** use upstream's module analysis: a callee
may write its parameter in place, and each caller copies where it still
reads the argument. In a recursive call graph upstream assumes every
operand read and written, so each level of a recursion copied its
callee's result; patch 24 now analyzes each cycle of the call graph to a
fixpoint over its strongly connected components (`FuncBoundaryFacts`,
0004; §19, U4), and a copy One-Shot still makes at a call is reported as
a `missed` remark with its conflict (read:
`sources/docs/mlir/docs/Bufferization.md`, "Debugging Buffer Copies";
`BufferizationStatistics::numTensorOutOfPlace`, `Bufferize.h:35`).

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

interface SparseElement a         -- upstream's primary types, and the semiring encodings
```

`fmt` is erased and monomorphised into the tensor's
`#sparse_tensor.encoding<{map = (d0, d1) -> (d0 : dense, d1 : compressed)}>`,
so CSR, DCSR, COO and CSF are formats of one type, and the same
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
library never emits them; the module verifier refuses one as an internal
error, since no program can reach it (the cutover's §2.5). The pipeline
sets the codegen options once; no option of a tool selects them (the
cutover's §1).
Storage growth is `memref.realloc`, lowered through the generic
allocation functions the runtime provides.

**Elements.** A sparse element must be `f16`, `bf16`, `f32`, `f64`, `i8`,
`i16`, `i32`, `i64` or a complex float (read: `isValidPrimaryType`,
`M/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:922-930`); `i1`
is not one. **decision** (D31): every library function that makes an
`SArray fmt s a` asks for `SparseElement a`, whose instances are those
types' Idris images and the semiring encodings below, so another element
is an Idris type error at the user's line ("Can't find an implementation
for SparseElement String"), not an `unsupported` refusal after
emission. The case is made unexpressible rather than refused, and the
fact lives once, in the instances.

**Semirings as `i8`.** A finite semiring is encoded as small integers
with its additive zero at 0, because `implicitVal` supports only 0 (read:
`SparseTensorAttrDefs.td:218-222`, "For now, we only support `0`"). The
encoding comes from the `Semiring` instance, not from constructor order:
`SizeChange = Smaller | Same | Unknown` has `plusNeutral = Unknown`
(read: `Algebra/SizeChange.idr:8, 56` [10, 58]), so tag order would give the
wrong zero.

| semiring | encoding | plus | times |
|---|---|---|---|
| `ZeroOneOmega` (read: `Algebra/ZeroOneOmega.idr:9` [11]) | `Rig0 = 0`, `Rig1 = 1`, `RigW = 2` | `minui(addi(a, b), 2)` | `minui(muli(a, b), 2)` |
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
through the bufferization options' `allocationFn` (§19, U3).

**A linear sparse array** is not offered: in-place sparse updates are
the sparsifier's own insertion on fresh tensors, and the wrapper rule of
§8 applies unchanged if it is ever needed, because the encoding slot is
free.

## 10. Relations as sparse arrays

A relation is a sparse array of Booleans; a conjunctive query is an
einsum: `Q[a, b, c] = R[a, b] * S[b, c] * T[a, c]` (read: 0012 §5; recalled:
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
is interned first: 0008's typed ids are this section's precondition.

**What this subset is.** Plans fixed at compile time: the formats, the
variable order and the join order are the program's. **What it is not**
(read, from the sparsifier's loop emitter): co-iteration merges two
sorted levels with two pointers, linear in the sum of their sizes, not
in the smaller one, so a sparse join here is not worst-case optimal
(recalled: leapfrog triejoin's bound). There are no hash levels, no lazy
levels, no runtime choice of format or variable order, and no indexes
chosen from statistics.

**The boundary with 0012** (**decision**, D22). A plan that
fits this subset is emitted as a sparse array program and compiled by
this lowering. Everything else stays 0012's: COLT's lazy tries, hash
tries, the Free Join planner and its generic-join end, galloping
intersection for worst-case optimal joins, indexes chosen from
statistics, plan variants, e-graphs, and the database's storage, laws
and log shared with bumbledb. 0012's interpreter is specialized for a
plan that does not fit; it is never a second route for one that does.

## 11. The compiler's own consumers

Each consumer is assigned to dense, sparse or 0012, honestly.

- **0008's multiplicity check is a sparse reduction.** Occurrences
  grouped by binder are a compressed level; the check folds each group in
  the 0/1/ω semiring and compares the sum with the declared quantity.
  That is `sparse_tensor.reduce` over a CSR array of `i8`, reduction
  case 2 of §6.
- **Size-change termination is half array, half relation.** Composing
  two size-change matrices is a semiring matrix product in `SizeChange`,
  a sparse `linalg.matmul`-shaped generic over DCSR operands: the fork's
  `Libraries/Data/SparseMatrix.idr` is already DCSR in lists (read). The
  closure is not a sum: `loopsTerminate` keeps, per function reached,
  only the weakest graphs of the walks to it under `weaker` (read:
  `Core/Termination/SizeChange.idr:435, 486-580`), and summing them
  would merge walks whose verdicts differ. The elaborator's triple
  closure (`:77-85, 183-208`, used at `:565`), the second copy of the
  same analysis, goes for it (0010 D13, 0008's O6). The closure is a
  relational fixpoint with subsumption, 0012's (its D9).
- **0007's kernels are where linalg is weakest.** The wavefront machine's
  steps are a stable group by term kind (a sort or a counting scatter),
  gathers of children from the arena, compaction of finished rows, and
  scatters of results: gathers, scatters and filters, where fusion stops
  (§4.4). Its dense parts (per-kind arithmetic on a gathered batch) fuse
  as any map does. 0007's kernels are written as ordinary programs in
  this language, using `select`, `idr.scatter`, `idr.scan` and `filter`,
  every combiner one `addi` (the counting sort's histogram and exclusive
  scan, compaction's flags and scan; §4.4, D16); there is no
  whole-array primitive of the runtime for them, which would be a second
  implementation of library functions.
- **0008's tables** are dense arrays of interned ids, one tensor per
  column (§4.5).
- **0009's layouts**: arrays of records and of sums are columns by
  representation, through §4.5's one-to-N conversion (0009 D3, D6);
  0009's 1.3x measurements choose only for collections that are not
  arrays (0009 D12).

## 12. Constants and static normalization

**decision** (D23) One answer. A literal array, or the result of a
closed total computation that static normalization (0007) produces, is
`arith.constant dense<...> : tensor<...>` for word and float elements,
which bufferizes to a non-writable `memref.global` (read: the Arith
bufferization model). It is immortal: one global, named from its content
(`__idr.array.<hash>`), holds a static cell header of the runtime's
persistent kind (count 0, never freed; read: `runtime/idris_rt.h`) in
front of the data, where every array cell holds its header. So a
constant is a cell like any other, and an array's lowered value is one
pointer: its components are the cell, then the dynamic offset if the
memref is strided, the dynamic sizes, and the dynamic strides if
strided. The first element is always the cell plus the header, computed
where a use needs it and never carried, so no descriptor holds two
pointers that could disagree (amended in the pipeline cutover; the first
version put the header beside the data and carried both pointers).
Counting treats a constant as it treats every persistent cell, and a
write copies it, which is the value meaning. A constant of any other
element is built at startup. The earlier `idr.array.constant` op is
deleted. The `memref.get_global` lowering to the static cell
(`Conversion/Arrays.cpp`) is the one pattern of ours a constant needs.
**decision** (D40, amended in the cutover) Constants landed at stage 1.
A dense constant needs a static shape (read:
`DenseTypedElementsAttr::getRaw` asserts one,
`M/lib/IR/BuiltinAttributes.cpp:1219`), and stage 1 has them: an extent
whose normal form at the instance is a literal is a static dimension of
the type (the cutover's contract C20), since the fact is a type.
`tensor.from_elements` of constants folds to a dense constant (read:
`FromElementsOp::fold`, `M/lib/Dialect/Tensor/IR/TensorOps.cpp:1480`),
so a stage-1 program holds constants and the lowering has something to
lower. A literal extent that Idris's normaliser leaves unreduced stays
dynamic: correct, and optimized less. 0007's static normalization is the
later producer of closed array results; until it exists, any other
closed array result is built at startup, as a constant of any other
element is.

Static normalization itself is 0007's: no array operation runs at
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
`Buffer` programs within D35's 2% of the 2026-10-13 record, in the
qualification, else the replacement is a local pattern relating
`newArray`'s size operand to `memref.dim` where value bounds can read
it, never the Presburger engine again. The fork's context table is one
of these arrays (§3.8, D38), so the self-compile's wall, recorded at
`make self`, prices the double check on the compiler's own hottest
table.

`freeze` and `thaw` between an `LArray` and an `IOArray` are
`bufferization.to_tensor ... restrict` (not writable) and a release.

## 14. Multicore, and devices later

After 0005's P4 (this file's stage 8), a parallel dimension of a
structured generic is tiled with `scf.forall` by the tile-and-fuse
schedule and lowered by 0005 §8 alone, a fork per shard and a join;
`shard.grid` supplies only the grid and the running index (0005 §7.3;
read: the pinned `shard` dialect). `sharding-propagation` and
`shard-partition`, region SPMD, are not a second lowering beside it:
0005's P5 takes them only to replace that lowering whole, on its
measurement, naming what lowers their collectives, since `ShardToMPI`
is rejected (§17). A reduction
across shards is legal exactly when §6 says its order is not observed,
so outputs are identical on one shard and on all. Devices come later
through the same tensor level: nothing above tiling assumes a CPU, and
a device is a target entry. Static linking decides which devices are
possible; the earlier `compiler.md`'s analysis of that (AMD through
KFD on Linux, Metal through SPIR-V on macOS; recalled) is kept for when
the work starts, as is its note that forward-mode differentiation is a
record of two words and reverse mode a library over the generating set,
which is closed under transposition.

## 15. Rules of AGENTS.md it keeps

- **Idris does types; MLIR does programs.** Shapes, ranks, agreement and
  uniformity are Idris types, checked by Idris. The frontend reads forms
  to choose ranked tensor types and writes each loop's sequential
  meaning; which loops are parallel, what fuses and what is in place are
  decided in MLIR, by upstream's passes, from the ops.
- **One thing, one representation.** One array type (the tensor), one
  loop meaning (the frontend's `scf.for`, structured where pure), one
  index type, one in-place analysis (One-Shot's), one representation of
  columns (N tensors), one answer for constants, one reduction policy,
  one schedule library, one flow rule for elements of every shaped type.
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
  is `unsupported (polymorphism)` (§2), the frontend's refusal, carried
  as structured data (the cutover's §6). A case the types can rule out
  is a type error instead (a sparse element, §9), and a state no program
  can reach is an internal error, never `unsupported` (a copy at a link,
  §8; the cutover's §2.5).
- **No oracle**: expected files are the specification; nothing is
  shaped so that Chez can run it (§3.8). The frontend's host build on
  Chez, AGENTS.md's one exception, runs the fork through base's own
  primitives, since the library adds none (D37, D38).
- **Never miscompile silently**: an observable order is never
  reordered; a counted element keeps its counts; a narrowing is guarded
  unless the type proves it exact.
- **Both targets, nothing per target outside the entry**: tile sizes,
  lane widths and cache sizes come from the target's DLTI facts, which
  `idr-target` writes from the target's entry and from LLVM's answer for
  its CPU, and which one schedule library reads for every target (§7.1).
- **Static linking**: no sparse runtime library, no `library_call`, no
  OpenMP or async runtime.
- **The pipeline's shape of the work**: the whole program is the unit of
  meaning (One-Shot's boundary analysis), the function the unit of work
  (every other array step, in parallel), output byte-identical at every
  thread count; one pipeline, with no option, toggle or fallback that
  selects array behaviour (§7).
- **An upstream bug or gap is fixed upstream**: the patches of §19,
  each with its report, reproducer, `tests/upstream/` check, `PINS.md`
  entry and plan.

## 16. Staged plan

Every stage passes `make check`, `make build`, `make test`, `make
test-idr` and `make test-mlir-tools` on both targets, and
`tests/determinism` at 1, 2 and 8 threads, and runs `bench/` on both, on
the owner's machine, as the cutover's §10 laid out. Stage 1 is done
(§1). Stages 2 to 7 follow sharding (0005's P1, P2 and P4 with 0006's
S-stages), in order, and stage 8 needs 0005's P4.

**Measurement** (**decision**, D35), the rule of the cutover's §10
applied to arrays: old binary against new, two commits, two builds, run
beside each other under identical conditions on performance cores; no
stage adds an option to compare by. The baseline is the commit before
the stage, on each target. The latest `bench/runs/` record (today
2026-10-13 at 9a1b7b12, which predates the cutover) is the published
reference, and the stage's own run replaces it. The thresholds are the
cutover's: no bench program's runtime worse than the baseline by more
than 2%, nor its compile time by more than 5%. A margin, not a spread:
on the record's ten array programs the second-best of five runs is at
most 2.0% above the best (*measured*,
`bench/runs/2026-10-13-9a1b7b1-darwin-arm64/samples.tsv`:
reverse-complement 0.555 and 0.566 s, fannkuch-linear 49.205 and 50.132
s, the rest closer), while the spread of all five reaches 97%
(unionfind's first run, 0.190 s against 0.096 s), so a threshold written
as "the run-to-run spread", as the earlier text had it, would bound
nothing. The margin sits just above the noise of the best-of-five
statistic on the noisiest program. **Parity** with a C counterpart
(stages 3 and 4) is the same margin (**decision**, D36): this compiler's
best of five at most 2% above the C's, on each target. Reason: one
margin for every comparison. A stage that misses its threshold is
reworked or reverted whole, never kept beside the old form. New
benchmarks, each with a C counterpart in `bench/c/` and no Chez column:
`matmul` (1024, f64, the C an `ikj` triple loop), `heat` (a 2-D
five-point Jacobi step, 2048², 100 steps), `spectral-norm-dense`,
`prefix-sum` (an inclusive scan of 10^8 i64), `histogram` (10^8 bytes
into 256 bins), `spmv` (CSR, a SuiteSparse matrix vendored under
`sources/`).

2. **Static extents.** The specialized case of §4.3 with D39's key, the
   cast propagation measured, and `vectorizeNDExtract` on in the
   vectorization schedule. The literal case and the immortal constants of
   §12 are stage 1's (§1, D40).
   Proof: a fixture whose expected module has
   static dimensions through a specialization node; `vectorized` on the
   static programs without masks; `spectral-norm-dense` at least at
   spectral-norm-linear's ratio to C; a dialect fixture in which an
   `arith.constant dense` array bufferizes to a `memref.global` whose
   descriptor's allocated pointer is a persistent header, with no
   allocation for it, and a write to it copies (the frontend writes no
   constant tensor, §4.1; 0007's static normalization is the first
   producer of one).
3. **Fusion and schedules** (§7.1, §7.2): generalization, elementwise
   fusion, the tile-and-fuse schedule, specialization of generics, and
   the L1 size in each target's entry. Proof, in this order: `fused` on
   `map f (map g x)`, then `softmax` and `matmul`; a producer with two
   consumers not duplicated; `matmul` and `heat` at parity with their C
   on both targets, else the tile sizes are what the measurement
   changes.
4. **Order.** `idr.scan`, `idr.scatter`, `reduceBlocked`, the finite
   semiring case of §6 (the frontend's `scf.parallel`). Proof: integer
   reductions and scans vectorized
   across lanes; float reductions bit-equal to the in-order meaning;
   `prefix-sum` and `histogram` at parity with their C; producer fusion
   into an ordered fold measured on spectral-norm.
5. **Index sets, data-dependent shapes and shape arithmetic.** `Table`,
   `filter`, `Ragged`, `accumulate`, `resize`, `Array.Shape.solve`, the
   views. Proof: tests; the tactic within its threshold on the corpus.
6. **Sparse** (§9). `SArray` with `SparseElement`, codegen only, the U2
   patch, `sparsification-and-bufferization` in the arrays stage for
   every module, `i8` semirings. Proof: `spmv` within 1.5x of its C
   (decision; the CSR C loop is the bound), no symbol of the sparse
   runtime in any linked program (`tests/toolchain/static-linking`
   extended), the dense benchmarks unchanged by the pass's replacement,
   the semiring tables' laws as type-level tests, and a type-error
   fixture for a `String` element.
7. **Relations and the compiler's consumers** (§10, §11). The
   multiplicity check as a sparse reduction and size-change composition
   as a semiring product, behind the fork's existing results, and the
   elaborator's `calcTerminating` triple closure deleted for
   `loopsTerminate`, which carries the call path its message names (0010
   D13; 0008's O6): identical verdicts and messages on base and the
   corpus (0008's gate), and the 0012 boundary rule applied to the first
   relational consumer.
8. **Multicore** (§14), after 0005's P4. Proof: 0005's rules; `heat` and
   `matmul` outputs identical on one shard and on all.

## 17. Rejected alternatives

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
  parallel forms are `linalg`, structured from the loops.
- **Emitting `linalg` from the frontend**: whether a body may crash is
  known only after inlining and defunctionalization.
- **Structuring, fusion or tiling inside the inner per-function
  pipeline**: tiles made before a caller's inlining cannot fuse with
  what is inlined around them, and the inner pipeline is a fixed list
  for cleaning a function once (§7). **Structuring before dead-value
  removal**: it would hide loop-carried values from it.
- **Schedules written into every module by `idr-target`**: one copy of
  the schedule per module, and an interpreter that, run on a function,
  does not see a sequence in the module around it (read:
  `TransformInterpreterUtils.cpp:198-215`), so it would have to run once
  over the whole module, serially (§7.1).
- **Choosing the bufferization pass by whether the module holds a sparse
  tensor**: a branch on content where the stage of the plan decides
  (§7).
- **A promise of in-place writes selected on the command line**
  (`--demand-in-place`, the earlier text of §8): two languages; the
  cutover deleted the flag, and the promise is `LArray`'s type fact
  (§8).
- **`unsupported (sparse element)`**: a refusal after emission for a case
  the library's types rule out (§9).
- **The grade as the tensor's encoding during bufferization** (the
  earlier `compiler.md`): it takes the slot `#sparse_tensor.encoding`
  needs. **`idr::QType` as a `TensorLikeType`**: it makes the world a
  tensor to One-Shot.
- **Lowering `idr.func` to `func.func` before bufferization, to avoid
  U1**: counting, the stack pass and the tail passes would then run on
  `func.func`, and the function op would change meaning mid-pipeline,
  against 0002's one function op until lowering. **Bufferizing after
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
- **`LArray`'s size and check as runtime primitives of the registry**
  (the earlier text of §3.8): the size cannot give a shape of rank above
  one, the check is what a typed index removes, and the frontend's host
  build on Chez would have no meaning for either (D37).
- **The fork's table on `LArray`, or a linear cell to hold one in a
  `Ref`**: an unrestricted handle to a linear array is the alias D33's
  `restrict writable` rules out, and a table the world orders is
  already §13's `IOArray` (D38).
- **Keeping every link through the canonicalizer**, a tensor case in
  the folds of `idr.lin.enter` and `idr.lin.use`: a branch on the
  carrier in a rule that holds for every linear value (D43).

## 18. Decisions

Decided by the owner, 2026-10-12.

- **D1.** The library is `libs/mlir-array`, plain Idris over base and
  `mlir-linear`, trusted (§3). Its generating set is bodiless `%extern`s
  since the representation wave's D5.
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
  `MemoryEffectOpInterface`, by `idr-structure-loops` (named `idr-raise`
  until D27) (§5).
- **D11.** Idris's equality is unchanged; shape arithmetic is the
  library's tactic (§3.7).
- **D12.** Literal size mismatches are reported as the literals, by a
  fix in the fork recorded in `PINS.md` (§3.9).
- **D13.** The frontend writes each primitive's sequential meaning in
  upstream `scf` and `tensor` ops (§4.1). *Reversed by the
  representation wave's D6:* the frontend writes `idr.tabulate`,
  `idr.fold_last`, `idr.scan_last` and `idr.tabulate_io`, which
  `idr-structure-loops` lowers one to one once effects are final,
  because an `scf.for` nest that a recognizer then reads back as linalg
  holds each loop twice, the emitter's and its inverse's.
- **D14.** `idr.tie_shape` ties dynamic dimensions across calls through
  `ValueBoundsOpInterface`; sizes are `arith` or `affine` on `index`
  (§4.3).
- **D15.** Reductions mean their left fold; `linalg` reductions only for
  a single integer op, a finite semiring with proved laws (written by
  the frontend as `scf.parallel`, D32), or `reduceBlocked k` (§6).
- **D16.** `idr.scan` and `idr.scatter` are ours until upstream has a
  region-combiner scan and a combining scatter (§4.4). Added 2026-10-14:
  the structuring makes them, for a one-integer-op combiner only; a
  semiring scan or scatter stays an ordered loop until a measured
  consumer needs one.
- **D17.** Counted elements are tensor elements, with a counted
  `memCpyFn` (§4.5).
- **D18.** One-Shot Bufferize on `idr.func`, before counting, with the
  runtime's allocator and no ownership deallocation; the grade is the
  wrapper, `lin.enter` a release. Its last clause, "`--demand-in-place`
  is `mustBufferizeInPlace`", is superseded by D33, because the cutover
  (its D2, the owner's) deleted the flag (§8).
- **D19.** `Linear.Array` is rewritten on `LArray`; its Scheme specs go
  (§3.8).
- **D20.** Tiling and vectorization are transform scripts written from
  the target's facts (§7.1); how the scripts reach the facts is D29.
- **D21.** A sparse array is the dense type with an encoding, codegen
  only, semirings as `i8` with the zero at 0 (§9).
- **D22.** A relational plan that fits the sparse subset is a sparse
  array program; everything else is 0012's (§10).
- **D23.** Constants are `arith.constant dense`, an immortal
  `memref.global` with the header in front of the data, and an array's
  lowered value is one pointer, its cell (§12; amended in the pipeline
  cutover).
- **D24.** World-ordered arrays declare their effects on their memref
  (§13).
- **D25.** A rank no analysis fixes is refused; the segment scheme is
  deleted (§2, §17).

Taken 2026-10-14, reconciling this file with the cutover (each a
decision, with its reason):

- **D26.** The arrays stage is a stage of its own in the pipeline,
  after dead-value removal and before the memory passes: structuring,
  fusion and the tile-and-fuse schedule run there once per function, in
  parallel, then One-Shot on the whole program, then a per-function
  clean. Reason: tiling must follow every inlining, structuring reads
  the summaries' effects, dead-value removal sees `scf` loops, and
  the inner pipeline stays its fixed list (§7).
- **D27.** The structuring pass is `idr-structure-loops`, not
  `idr-raise`. Reason: the pipeline keeps "raising" for the
  specializer's arity raising; one name, one thing (§5).
- **D28.** A closure or lazy element flows through the element anchor of
  its type, one rule over `ShapedType`; the upstream ops that move one
  element get the flow interface as external models; defunctionalization
  turns every such element into a sum before any array pass. Reason: the
  verifier needs declared edges, and tensors and memrefs share one rule
  (§4.5).
- **D29.** The two schedules are one library of ours, loaded once per
  context and interpreted per function in parallel, reading
  `max_vector_op_width` (LLVM's answer for the entry's CPU) and
  `L1_cache_size_in_bytes` (the entry's fact) from the module's DLTI.
  The vectorization schedule lands at stage 1, the tile-and-fuse
  schedule at stage 3. Reason: one copy of the schedule, one copy of
  each fact, no per-target branch, work per function (§7.1).
- **D30.** The bufferization pass is chosen by the stage of the plan,
  never by the module's content: `one-shot-bufferize` until stage 6,
  `sparsification-and-bufferization` for every module after. Reason: one
  pipeline (§7).
- **D31.** `SparseElement` constrains every function that makes an
  `SArray`; another element is an Idris type error. Reason: a case the
  types can rule out is unexpressible, not refused (§9).
- **D32.** A fold over a finite semiring whose laws the instance proves
  is written by the frontend as `scf.parallel` with an `scf.reduce`.
  Reason: the fact lives in Idris, and upstream's unordered loop states
  it without an attribute or an op of ours (§6).
- **D33.** The in-place promise is `LArray`'s type fact: each link of a
  thread is `mustBufferizeInPlace`, always; a linear array read from a
  cell is `restrict writable`; a copy at a link is an internal error.
  Reason: the cutover deleted the flag, and an `LArray` aliases nothing
  by construction, so a failure is the compiler's (§8).
- **D34.** U1 relands upstream's own reverted generalization of module
  bufferization, with its failing test fixed and the function analysis
  state generalized with it; it is item 5 of the cutover's §7, carried
  as `upstream/24-one-shot-module-function-interface`. Reason: AGENTS.md
  prefers upstream's fix, backported, to one of ours (§19).
- **D35.** Measurement is the cutover's §10 rule: binary against binary,
  the commit before the stage as the baseline, run beside it on each
  target (the latest `bench/runs/` record the published reference the
  stage's run replaces); no runtime regression over 2% and no
  compile-time regression over 5%; determinism at 1, 2 and 8 threads.
  Amended 2026-10-14 from "the latest record as the baseline" and
  "within the run-to-run spread": a stored record is not a run under
  identical conditions, and the spread of five runs reaches 97% on the
  record while the best-to-second-best gap is at most 2.0% (§16).

Taken 2026-10-14 in the same reconciliation, each closing a case the
text had left open or got wrong:

- **D36.** Parity with a C counterpart is this compiler's best of five
  at most 2% above the C's, on each target. Reason: one margin for
  every comparison, the cutover's, and it sits above the statistic's
  noise on the record (§16).
- **D37.** `LArray` and `Linear.Vec` have no primitive of their own:
  plain Idris over base's `Data.IOArray.Prims`, the extents carried as
  `Extents s`, the bounds check gone with typed indices. Supersedes the
  earlier text's "declared runtime primitives of the registry". Reason:
  the backing's length cannot give a shape of rank above one, and the
  frontend's host build on Chez then needs no meaning of ours (§3.8).
  *Superseded in part by the representation wave's D5:* `LArray`'s
  operations are bodiless `%extern`s of `Array.Core` with no Idris body
  (the compiler's own Idris imports no `mlir-array`, so stage 0 is
  unaffected); `Linear.Vec` stays plain Idris over them, and the extents
  and typed indices stand.
- **D38.** The fork's `Table` moves onto base's `Data.IOArray` with its
  doubling growth, and the fork's `mlir-linear` dependency goes.
  Reason: the table lives in a `Ref`, no unrestricted `LArray` exists
  (D33 rests on that), and its meaning is mutation in program order,
  §13's case (§3.8).
- **D39.** The static pattern of an array argument is the source type of
  the `tensor.cast` the frontend writes at the call, under today's
  binding-time rules; a clone specialization does not make (by the
  request-chain rule of the representation wave's D4, which deleted the
  budget) leaves the extent dynamic. Reason: the fact is already a type,
  and a budget never rejects (§4.3; the cutover's §2.5).
- **D40.** The immortal-constant lowering lands at stage 1 (amended in
  the pipeline cutover; first decided for stage 2). Reason: a dense
  constant needs a static shape, and stage 1 makes an extent static
  wherever its normal form is a literal, because the fact belongs in the
  type. Folding `tensor.from_elements` then gives stage-1 programs
  constants (§12).
- **D41.** A closure carried by a frontend loop flows along `scf`'s
  region edges, read through upstream's `RegionBranchOpInterface` by
  the flow rule; no model of ours. Reason: upstream already declares
  those edges (§4.5).
- **D42.** The bufferization step ends with one type conversion of ours,
  `!idr.lin<T>` to `!idr.lin<B>` with `B` One-Shot's buffer type for `T`
  in the cell's identity layout, on every block and region argument and
  result that carries a wrapper. Reason: the wrapper is no tensor to
  One-Shot, whose block-signature rewrite converts tensor-like types
  only, so the analysis needs nothing and the rewrite needs this, in one
  place (§8).
- **D43.** The canonicalizer's folds of an enter and a use stay as they
  are for every linear value; the in-place promise is checked at the
  links that survive, the thread's boundaries. Reason: one fold rule for
  every linear value; inside a function the chain is One-Shot's
  conclusion, checked by `in-place=@f` (§8).
- **D44.** Record elements become one tensor per field, by the one-to-N
  type conversion of §4.5, at stage 1. Reason: §4.5 makes it the one
  representation of a record element, and stage 1 is the cutover that
  fixed the representation of every element kind (words, ours, counted,
  closures, records), so no array program is compiled one way at stage
  1 and another later; 0009's F2 (arrays of sums through `SumLayout`'s
  one-to-N) and 0008's tables then find it in place.

## 19. Upstream used, and the patches it needs

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
| `MemoryEffectOpInterface` | the structuring (§5); world-ordered arrays (§13) |
| `scf.parallel`, `scf.reduce` | the frontend's unordered fold (§6) |
| `transform.dlti.query`, `TransformDialect::loadIntoLibraryModule`, `dlti.target_system_spec` | schedules read per target, run per function (§7.1) |
| `sparsification-and-bufferization` | bufferization from stage 6 (§7, §9) |
| `shard.grid` | the grid and running index of 0005 §8's fork-and-join lowering of `scf.forall` (§14); `sharding-propagation` and `shard-partition` only if 0005's P5 replaces that lowering whole |

**Gaps filled by ours**, each to go when upstream fills it:
`transform.idr.vectorize_lanes`, the vectorization schedule's one op
(the pinned transform dialect cannot express it: a transform param
admits no arithmetic, so the lane count `W / widest` cannot be computed
from `transform.dlti.query`'s answer; `structured.vectorize` takes one
size param per dimension, not one per op's widest word; and
`dlti.query` stops at the data layout spec, not the target system spec's
`max_vector_op_width`; read for the cutover's contract C13, its §4),
`idr.tie_shape` (no op ties dynamic dimensions across calls),
`idr.scan` (no region-combiner scan), `idr.scatter` (no combining scatter
with a bufferization model), `idr-structure-loops` (no pass of the pin
turns a tensor loop into linalg, read, §5), the `memref.get_global`
lowering for immortal constants, and the external flow models on
`tensor.insert`, `extract` and `pad` (the flow interface is ours,
§4.5).

**Patches**, each an `upstream/NN-<bug>/` directory in that file's
layout (read: `upstream/README.md`): `llvm.patch` against the pinned
llvm-project, the report, `submission.md`, the `tests/upstream/` check,
the `PINS.md` entry and the upstreaming plan, sent under LLVM's AI tool
policy as `upstream/README.md` requires. They share one queue with
the pipeline's (the cutover's §7):
- **U1. One-Shot module bufferization on `FunctionOpInterface` and
  `CallOpInterface`** (item 5 of the cutover's §7). The pinned driver
  names `func::FuncOp` 29 times and `FunctionOpInterface` never (read,
  counted 2026-10-14:
  `M/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`),
  and the function analysis state the call and function models share is
  keyed by `func::FuncOp` too (read:
  `M/include/mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h:29-60`),
  while upstream's own deallocation passes already take
  `FunctionOpInterface` (read:
  `OwnershipBasedBufferDeallocation.cpp:168`). Upstream has its own fix,
  reverted: llvm-project pull request 110322, "[MLIR] Make
  `OneShotModuleBufferize` use `OpInterface`", landed and was reverted
  by pull request 113124 on 2024-10-22 for a failing staging buildbot;
  the bufferization maintainer wrote on 2025-10-31 that the failures
  "could be fixed" (read: the two pull requests and the LLVM Discourse
  thread "Is the bufferization of func.func able to be reused on other
  FunctionOpInterface", 2025-10). Plan (**decision**, D34): reland
  110322 on the pin with the failing test fixed and the analysis state
  generalized with it, a test-dialect function op in its test beside
  `test/Dialect/Bufferization/Transforms/one-shot-module-bufferize*.mlir`,
  sent to llvm-project's bufferization owners as a reland. Carried since
  stage 1 as `upstream/24-one-shot-module-function-interface`.
- **U2. The sparse passes on `FunctionOpInterface`.** `stage-sparse-ops`,
  `lower-sparse-foreach-to-scf`, `sparse-space-collapse` and
  `lower-sparse-iteration-to-scf` are anchored on `func::FuncOp` (read:
  `M/include/mlir/Dialect/SparseTensor/Transforms/Passes.td:196, 231,
  534, 546`), and `sparsification-and-bufferization` nests its steps on
  `func::FuncOp` and filters function signatures by it (read:
  `SparsificationAndBufferizationPass.cpp:106, 136, 175-184`). Plan:
  `InterfacePass<FunctionOpInterface>` and nesting by the interface, as
  other upstream passes have moved. Needed by stage 6.
- **U3. Sparse codegen's allocations through `allocationFn`**, by the
  measurement of §9.
- **U4. Boundary analysis of a recursive call graph to a fixpoint.**
  Carried since 0004 as patch 24's second pull request: each cycle's
  boundaries iterated to a fixpoint over the call graph's strongly
  connected components (`analyzeCallCycle`, one `FuncBoundaryFacts` per
  function), taken without waiting for §8's measurement, since a
  recursion's result was copied at every level. 24 also folded in the
  rule that a value definitely aliasing an operand is writable on its
  own, first carried as 26.

## 20. What the owner settled

1. **One path for counted elements** (D17). A regression stage 1's
   qualification measures is a reason to make the counted copy faster,
   not to keep a second path.
2. **The release model of §8** is the design. If One-Shot does not
   accept it, the design changes whole to the grade carried as the
   tensor's encoding inside the one pass, with linear sparse arrays
   refused; nothing else, and never both in the tree (the cutover's
   D2).
3. **The Chez column** of `bench/` loses the `Linear.Array` programs
   (D19). The C column is the comparison that matters. (Reconciled
   2026-10-14: with D37 the rewritten programs need nothing of ours on
   Chez, so the column keeps whichever Idris's Chez backend runs as
   written; nothing is shaped for it either way. The column is timing
   only: its output is never compared with the reference, since that
   would make Chez's meaning a gate, which AGENTS.md's no-oracle rule
   forbids; `bench/run.sh` no longer makes it.)
4. **U1 is a patch** to bufferization's module driver, generalized from
   `func.func` to `FunctionOpInterface` and `CallOpInterface`, carried
   under `upstream/` with its plan; no driver of ours.
