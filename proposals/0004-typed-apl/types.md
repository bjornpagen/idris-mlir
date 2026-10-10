# 0004 companion — types: the type theory in depth

A companion to `README.md`, written independently as a full draft from the types side. Where it disagrees with the README, the README decides (see the README's layout note).

(Its original title: 0004: typed arrays, lowered to tensors)

**Status:** proposed, 2026-10-09. This replaces the whole proposal. Its
premise is the user's ruling of 2026-10-09, kept: pure array programs are
tensors until bufferization ("tensors should definitely be tensors, pure
array programs is one of the heavy hitting features of mlir and we cannot
lose this"). The user's request of the same day binds the rest: fix
"the timidity of the rank above 1 decision. no ceiling, lower to mlir,
don't be scared", so no rank works "only when a literal". Every decision
is taken here, with its reason or the
measurement that settles it (Decisions). Claims are marked: read (the
path given; a `sources/` path is the library's copy, staged by the
research of 2026-10-09 at the same relative path), measured (what was
run, on what), conjecture, decision. Nothing here is built.

The proposal makes Idris 2 on this compiler a typed APL. An array's shape
is an erased index. Rank polymorphism is computation over shape lists in
types: a function states its cells, and its frame is found. Coordinates
are in bounds by type. Structural operations are typed by equations, and
the elaborator decides those equations, so that `n * m` against `m * n`
never blocks a program. Every array of every rank and every element type
is a ranked tensor in MLIR until bufferization. This proposal owns dense
and typed arrays; the shard runtime is 0005's and Rust is 0001's, cited
where they meet.

## What it changes

Each move names the representation that changes and the branches it
deletes.

- **A shape is an erased index; its extents are a singleton** (§3.1).
  Data: `Shape = SnocList Nat` at quantity 0 in every array type, and
  `Ext s`, the one runtime value of each shape, at quantity ω wherever a
  size is needed. Deleted: the rank literal of the first version's §3.7
  (`IArray : Nat -> Type -> Type` with a `Vect rank Int` beside the
  backing), its condition "when the rank is a literal after
  monomorphisation", and the empty-frame case of every lifted operation:
  a result's extents come from a singleton, never from a cell.
- **Rank is the length of a shape's canonical form** (§5.1, §5.2). Data:
  the frontend's `ArrayT Rank0|Rank1` is joined by `TensorT k` for value
  arrays, k the number of components of the shape's canonical form, any
  k; a component the type leaves opaque is one dimension with its
  extents carried beside the tensor. Deleted: the fallback "the
  library's definition compiles as written" for any rank, and the words
  restriction of the loop ops for value arrays.
- **A nested array of uniform shape is one tensor** (§5.2). Data:
  `Array f (Array c a)` has the representation of `Array (f ++ c) a`.
  Deleted: the first version's rejection of nested arrays as "a cell
  per row"; the
  cells view and its inverse cost nothing; batching is not an operation
  of its own but a consequence of the representation.
- **An array of records of words is a record of tensors** (§5.2).
  Deleted: the words-only element rule; an array of any other element is
  a tensor of counted elements, so no element type leaves the tensor
  path.
- **A coordinate is a `Fin` per axis** (§3.6). Deleted: the bounds
  guard of every typed access. A guard exists only where a program turns
  an integer into a coordinate, and `idr-in-bounds` proves it there as
  today.
- **Shape arithmetic is definitional** (§4). Data: the fork's evaluator
  gains three arithmetic clauses and a unit clause per append, its
  conversion compares stuck arithmetic and
  append spines by canonical forms, and its unifier solves modulo that
  theory where the solution is unique. Deleted: `rewrite` by arithmetic
  lemmas in array code, the failed match on `Refl : n * m = m * n`, and
  the unchecked motive of `rewrite`.
- **A reduction's laws are in its type** (§3.7). Data: a combiner proved
  a commutative monoid, or an integer primitive by the runtime's meaning,
  selects the unordered reduction op. Deleted: the one-lane rule for
  every reduction whose order is not its meaning.

## 1. What exists

### 1.1 Arrays in the dialect

(read: `foreign/idr/include/idr/IdrOps.td`, "Arrays", lines 1788-1959)

- **The type.** An array is a builtin `memref` of rank 0 or 1, every
  dimension dynamic, over a field type: `memref<?xE>` holds base's
  `ArrayData` (so `IOArray`) and `Buffer`, `memref<E>` an `IORef`'s
  cell. The cell is counted like a constructor's.
- **The ops.** `idr.array.new`, `get` and `set` take one size or index
  per dimension and the world: every array op is IO. Each access carries
  `idr.check.in_bounds`, and "a proof is the guard's absence":
  `idr-in-bounds` erases each guard it proves, as a Presburger system
  (read: IdrOps.td:1835-1841; `foreign/idr/include/idr/Passes.td`:443-493).
- **Two loop ops.** `idr.array.generate` and `idr.array.fold` are rank 1,
  their elements machine words, emitted for `Linear.Array`'s
  `prim__generate` and `prim__foldl` at word instances only (read:
  IdrOps.td:1889-1959; `compiler/src/IdrisMLIR/Registry/Recognized.idr`:87-110).
  Lowering makes each a `linalg.generic` on memrefs: a generate whose
  body is a fold over an outside array is one generic of two dimensions,
  and reads of outside arrays at the loop's index become inputs under
  one test on entry (read: `foreign/idr/lib/Lower/Loops.cppm`:1-41).
- **`idr-vectorize`** tiles each generic with a parallel dimension by the
  target's lanes and gives a reduction one lane, so a float accumulator
  adds in program order; **`idr-narrow-lanes`** versions integer lanes to
  32 bits under a bound (read: Passes.td:663-720).

### 1.2 The library and how the compiler recognizes it

- **`Linear.Array`** is a size beside base's `ArrayData`, threaded at
  quantity 1, every operation an `unsafePerformIO` over base's primitives;
  `freeze` gives an `IArray`, read-only and shared (read:
  `libs/mlir-linear/Linear/Array.idr`).
- **The registry** is the compiler's only knowledge of Idris names (read:
  `tests/registry/registry-only/run`). A recognized definition is a
  hook of one of two kinds: a faster lowering of the same meaning, or a
  stricter rejection, so that "removing one may change speed or which
  programs are rejected, never a program's result" (read:
  `compiler/src/IdrisMLIR/Registry/Recognized.idr`:1-5;
  `compiler/src/IdrisMLIR/Registry/Entry.idr`:286-310).

### 1.3 How the frontend chooses representations

(read: `compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`)

- An instance is keyed by its type parameters and implementations, and by
  the shape of a runtime argument when the rest of the type must reduce
  on it (`neededShape`, lines 154-176). An erased parameter keys nothing
  (lines 211-214): "`(n : Nat) -> Vect n Int -> Int` only indexes a vector
  by `n`, so one instance serves every argument".
- A recursion that builds such a shape deeper at each call is refused as
  polymorphic recursion (`growing`, lines 58-90); a definition has at
  most 4096 instances (lines 35-36).
- The frontend's array type is `ArrayT Rank Ty` with
  `Rank = Rank0 | Rank1` (read: `compiler/src/IdrisMLIR/Types.idr`:86-121).
  `Fin`, shaped like `Nat`, is a natural: a big at run time, never
  negative (read: IdrOps.td:175-184).
- The Idris side writes ops through builders generated from the ODS of
  arith, builtin, func, idr, math, memref and ub (read:
  `compiler/src/IdrisMLIR/Dialect/`).

### 1.4 How the elaborator decides equality

The fork in `compiler/idris` is this repository's own code and already
departs from upstream where the compiler needs it (read:
`compiler/idris/README.md`, "Ours").

- **Conversion** is untyped and syntactic on stuck terms: two neutral
  applications convert when their heads and their arguments do (two case
  blocks also when they come from one place), and two different stuck
  spines do not (read: `compiler/idris/src/Core/Normalise/Convert.idr`:253-300, 366-427).
  `plus` and `mult` are ordinary clauses that recurse on their first
  argument (read: `third_party/Idris2/libs/prelude/Prelude/Types.idr`:48-64),
  so `n + 0`, `n * m` against `m * n`, and `(a + b) + c` against
  `a + (b + c)` are stuck and differ.
- **Unification** postpones what it cannot solve and reports what is
  left at the end (read: `Core/Unify.idr`:211-260, 623-636). It has the
  three outcomes Cockx names: success, refutation, and failure "because
  there is no unification rule that applies", unavoidable in general
  (read: `sources/papers/cockx-2016-unifiers-as-equivalences/paper.pdf`, §2, p. 3).
- **`rewrite`** abstracts every subterm of the goal's normal form that
  converts with the left side (read: `Core/Normalise.idr`:243-307) and
  builds the predicate without checking it (read:
  `TTImp/Elab/Rewrite.idr`:65-100). Measured below, it accepts an
  ill-typed motive.
- **`with`** generalises the part of the context the scrutinee does not
  need (`bindNotReq`, read: `TTImp/Elab/Utils.idr`:87;
  `TTImp/ProcessDef.idr`:445-523).
- **Auto search** raises `AmbiguousSearch` when a group finds more than
  one solution (read: `Core/AutoSearch.idr`:168-188).

### 1.5 What stock Idris accepts and refuses

(measured: the repository's Idris 2, `0.8.0-1c630e67c` in
`.toolchain/idris2`, `--check`, on the probes in the research scratchpad,
`selfhost/apl/types-probe/` and `selfhost/apl/idris-probe/`, which become
the fixtures of stage T1)

| Obligation | Probe | Stock Idris |
| --- | --- | --- |
| frame found from the argument, cell of known rank: `rowSums : Array [<3,4,n] Double -> Array [<3,4] Double` | `Core.idr` | accepted |
| the rank operator over any frame: a matrix product lifted over `f :< n :< k` | `Core.idr` (`batched`) | accepted |
| rank recursion on the extents, total, at any rank | `Core2.idr` (`sumAll`) | accepted |
| the same frame with cons-list shapes: `[3,4,5]` against `?s ++ [?n]` | `Probe5.idr` | refused |
| the frame known from the result type, the cell a variable: `[<3] ++ ?c` against `[<3, 4, 5]` | `Probe3.idr` (with `{c = [<4, 5]}` written: `Probe.idr`) | refused (accepted when written) |
| `size [<n, m] = size [<n * m]` (a flattened matrix) | `F1Flatten.idr` | refused |
| `Array [<n * m] a` used at `Array [<m * n] a` | `F2Comm.idr` | refused: `Mismatch between: m and n` |
| `append (append x y) z` at `[<a + (b + c)]` | `F3Assoc.idr` | refused |
| `lastV : Vect (n + 1) a -> a; lastV (x :: xs) = x` | `F4Snoc.idr` | refused: `S ?len` against `plus ?_ 1` |
| `take 3` of `Array [<m] e`, `m` a variable | `F5Take.idr` | refused: `m` against `S (plus 2 ?n)` |
| a match on `Refl : n = k * m`, one side a variable | `W1Subst.idr` | accepted |
| a match on `Refl : n * m = m * n` | `W3Both.idr` | refused: the unifier's third outcome |
| `rewrite multCommutative n m` in a goal over `index i v`, `i : Fin (n * m)` | `F6Motive.idr` | accepted with the predicate `\rwarg => index {len = rwarg} i v = ...`, ill-typed (logged with `--log elab.rewrite:5`) |
| `Prefix f (f ++ g)` found by search, `g` a variable | `F7Ext.idr`, `Probe10.idr` | refused |
| `(a ++ b) ++ c` against `a ++ (b ++ c)` on shapes | `ProbeAssoc.idr` | refused |

Gibbons reports that "the existing traditional unification algorithm
suffices" for size constraints (read:
`sources/papers/gibbons-2017-naperian/aplicative.pdf`, §9, p. 24); it
does while sizes are compared and concrete. Idris programs carry sizes
as variables, and every refusal above is an equation on variables.

### 1.6 Measured performance

(measured: `bench/runs/2026-10-07-f5a4dff9-darwin-arm64/results.md`,
Apple M2 Max, best of 5)

| benchmark | this compiler | clang -O2 | clang / this |
|---|---:|---:|---:|
| spectral-norm-linear 5500 | 0.596 s | 1.108 s | 1.86x |
| spectral-norm 5500 (lists) | 1.515 s | 1.126 s | 0.74x |
| fannkuch-linear 12 | 24.155 s | 25.711 s | 1.06x |
| nbody 50000000 | 1.655 s | 1.924 s | 1.16x |
| mandelbrot 2000 | 0.229 s | 0.231 s | 1.01x |

The byte and string programs (fasta, k-nucleotide, regex-redux,
reverse-complement) are IO over buffers and strings; their gap is the
object model's, and this proposal does not change them.

### 1.7 Missing

Rank above 1; loops over any element but words; nested arrays; any
arithmetic on sizes in types; fusion; tiling for the cache; in-place
decisions over a function; parallelism over cores.

## 2. The decision this design serves

**What.** An array that no world orders is a value, and in MLIR a value
array is a `tensor`: built, read, sliced and combined by `tensor` and
`linalg` ops until One-Shot Bufferize turns it into memrefs. Arrays the
program mutates in its world's order (base's `IOArray`, `Buffer`,
`IORef`) stay memrefs from birth. The typed arrays of §3 are tensors
from their birth in the frontend; the rank-1 arrays of `Linear.Array`
become tensors where the raise of §5.4 finds them pure.

**Why.** Upstream's array machinery works on tensors: fusion and tiling
of `linalg`; bufferization in destination-passing style "with aggressive
in-place bufferization", which decides in-place updates over a whole
function (read: `sources/docs/mlir/docs/Bufferization.md`); and SPMD
partitioning, whose sharding is a property of a tensor's dimensions
(read: `.toolchain/llvm-project/mlir/include/mlir/Dialect/Shard/IR/ShardOps.td`).
They are single-thread wins first and the multicore path second:
single-thread performance wins the tie (`proposals/0005-shards.md`,
"Rules it keeps").

**What the user's request adds.** Every rank, whether the program
fixes it at compile time or computes it at run time; every element type;
everything lowered to MLIR. The types carry what the lowering needs (the
rank, the uniformity of nested arrays, the bounds of coordinates, the
laws of reductions), so that MLIR re-decides nothing a type already says.

## 3. The language

The library is `libs/mlir-array`, in plain Idris over base's primitives
as `mlir-linear` is, built by this compiler (§4.10). Its modules:
`Array.Shape` (shapes, extents, coordinates, views), `Array.Core` (the
array type and its core), `Array.Rank` (frames, cells, lifting),
`Array.Struct` (structural operations), `Array.Reduce` (reductions,
scans, laws) and `Array.Linear` (linear arrays). Signatures below are the
library's; a body is given where it is the point.

### 3.1 Shapes, extents and coordinates

Remora's type erasure turns an array type into its shape and keeps
exactly the index binders whose indices change what the program does,
because an empty frame has no cell to read a shape from (read:
`sources/papers/slepak-2019-semantics/type_erasure.tex`:68-123).
Quantitative type theory says the same with a quantity: a shape is a
type index at 0, "not used at run time" (read:
`sources/papers/brady-2021-idris2-qtt/erasure.tex`:12-16), and what the
running program needs of a shape is a value of a singleton type at ω.

```idris
||| The extents of the axes, outermost first. A frame is a prefix of a
||| shape and a cell a suffix.
public export
Shape : Type
Shape = SnocList Nat

||| A shape's extents at run time: one value per shape, so a value of
||| `Ext s` is `s`.
public export
data Ext : Shape -> Type where
  Lin  : Ext [<]
  (:<) : Ext s -> (n : Nat) -> Ext (s :< n)

||| A coordinate: one `Fin` per axis, outermost first.
public export
data Index : Shape -> Type where
  Here : Index [<]
  At   : Index s -> Fin n -> Index (s :< n)

public export
size : Shape -> Nat          -- the number of elements
size [<] = 1
size (s :< n) = size s * n

public export
rank : Shape -> Nat
rank [<] = 0
rank (s :< _) = S (rank s)
```

- **Why a snoc list.** `SnocList`'s `++` recurses on its right argument
  (read: `third_party/Idris2/libs/prelude/Prelude/Types.idr`:424-427), so
  `f ++ [<n]` evaluates to `f :< n`, and unification finds the frame `f`
  of an argument of shape `[<3, 4, n]` from the argument alone. With cons
  lists `f ++ [n]` is stuck and the same call is refused (measured: §1.5,
  `Probe5.idr`). After §4 both orientations unify; the snoc list keeps
  the common case, a cell of known rank under an unknown frame,
  definitional without the solver.
- **Why a singleton.** A `Shape` at run time would be a list of bigs; the
  singleton has the same values, and its type says which shape they are,
  so a function that needs extents asks for `Ext s` and cannot be handed
  another shape's. It is also the honest reading of "erased does not
  mean constant" (AGENTS.md): the index at 0 is never read as a value;
  where its values are needed they are an argument at ω; and where the
  index is a literal, `[<3, 4]`, the singleton's one value is `[<3, 4]`,
  so a static extent is a fact Idris proved, not an assumption about an
  erased value (decision D1).
- **Sizes read off arrays.** Futhark's size types let a size be read off
  the array that witnesses it, so an existential size is never a
  separate value (read: `sources/papers/bailly-2023-size-dependent/paper.pdf`,
  §2.1). Here `extents : Array s a -> Ext s` gives an array's shape
  back, and an existential shape is `Exists (\s => Array s a)`, its
  witness erased. That answers Bailly's complaint that in Idris
  `length (filter p xs)` "is ill-typed" until a dependent pair is
  unpacked (§1): nothing is unpacked, and `extents` gives the size.
- **Index sets.** `Index s` is Dex's product of index sets (read:
  `sources/papers/paszke-2021-dex/main.tex`:782-831), whose row-major
  ordinal is the layout. Dex flattens `n=>m=>a` to `(n&m)=>a` "while
  both preserving static information about array sizes, and not
  requiring the type system to solve systems of Diophantine equations";
  here `Index (f ++ c)` and `(Index f, Index c)` convert by structural
  functions over `Ext c` (measured: `joinIndex`, `splitIndex` in
  `Core2.idr`). Other finite index sets (an enumeration, a range, a
  triangle) are tables over an `IndexSet` interface (`size`, `ordinal`,
  `fromOrdinal`) whose representation is one axis through the ordinal; a
  library type, not a compiler feature.

### 3.2 The array: a memoised function

```idris
export
data Array : (0 s : Shape) -> Type -> Type     -- immutable, row-major

export tabulate : Ext s -> (Index s -> a) -> Array s a
export index    : Array s a -> Index s -> a
export extents  : Array s a -> Ext s
```

- **Naperian.** A dimension is a functor of fixed shape with a type of
  positions, `lookup` and `tabulate` its two directions, which makes
  transposition total (read:
  `sources/papers/gibbons-2017-naperian/aplicative.pdf`, §3, pp. 9-10).
  An array is "a representation for a fully memoized function" (read:
  `paszke-2021-dex/main.tex`:747-781): `Array s a ≅ Index s -> a`, with
  `index (tabulate e f) i = f i` and `tabulate (extents x) (index x) = x`
  the meaning of the core, stated in the library and checked by its
  tests.
- **A small core.** The core is these three, the operations that carry
  state across positions (reductions, scans, folds: §3.7), the reshaping
  views and concatenation (§3.5), and the linear operations (§3.8).
  Every other operation is a library definition over the core: a
  `tabulate` whose body indexes its arguments at functions of the
  coordinates. `map`, `zipWith`, `transpose`, `reverse`, `rotate`,
  `take`, `drop`, replication, windows, outer and inner products are all
  of that form. Dex reduces fusion to inlining of index-defined
  producers (main.tex:1813-1850) and SaC folds a with-loop read at an
  affine index into its producer (read: `sources/papers/grelck-2006-sac/paper.pdf`,
  §3.2); §5.3 turns such bodies into indexing maps, so a small core
  loses no structure (decision D4).
- **Empty arrays.** Gibbons rules out empty structures, "insisting that
  the type Log f should always be inhabited" (aplicative.pdf §3, p. 10).
  Here an extent may be 0, and nothing ever needs an element to learn a
  shape (§3.3).
- **The plain definitions.** `MkArray : Ext s -> ArrayData a -> Array s a`,
  row-major, every operation an `unsafePerformIO` over base's primitives
  as in `Linear.Array`. The compiler's representation (§5.2) replaces the
  type whole at every instance, and the plain definitions are the
  meaning, run by the tests with the hooks off (§5.6).

### 3.3 Frames, cells and the rank operator

Remora types application by subtraction and a join: each argument's
frame is its shape minus the cell shape the function declares, the
principal frame is the join of all frames in the prefix order, and the
result is the principal frame followed by the result cell (read:
`slepak-2019-semantics/figs.tex`:328-347). In canonical form the
subtraction is syntactic and the join, when it exists, is one of the
frames (read: `formalism.tex`:486-542). In Idris the rule is a type:

```idris
||| The frame of cells: a view. (`frameOf` and `joinIndex` recurse on
||| `Ext c`; they are in the probe `Core2.idr`.)
cells : Ext c -> Array (f ++ c) a -> Array f (Array c a)
cells c x = tabulate (frameOf c (extents x)) (\i => tabulate c (\j => index x (joinIndex c i j)))

||| Cells of one shape merged into the frame: total, because c is in the type.
merge : Ext c -> Array f (Array c a) -> Array (f ++ c) a

||| The rank operator: a function on cells, over any frame.
lift : Ext c -> Ext d -> (Array c a -> Array d b) -> Array (f ++ c) a -> Array (f ++ d) b
lift c d g = merge d . map g . cells c
```

`lift` is BQN's identity `F⎉k x ←→ >F¨<⎉k x` (read:
`sources/docs/bqn/doc/rank.md`:150-154), with the cell's shape in place
of a cell rank, so that there are no negative ranks to clamp and no
"negative zero" (BQN's own complaint, read:
`sources/docs/bqn/commentary/problems.md`:131-132). The
definitions check in stock Idris (measured: `Core.idr`, `Core2.idr`).

- **Cells declared, frames found.** `rowSums : Array [<3, 4, n] Double ->
  Array [<3, 4] Double` is `lift [<n] [<] sumRow`, and unification finds
  `f = [<3, 4]`; `rowSumsAny : Array (f :< n) Double -> Array f Double`
  is the same body for every frame (measured: `Core.idr`). Remora's
  inference only instantiates, since rank-polymorphic types have no
  principal types (read: `slepak-2020-dissertation/Dissertation.pdf`,
  ch. 6, pp. 73-74), which is Idris's own discipline. A cell that is a
  shape variable, under a frame nothing else fixes, leaves two unknowns:
  `f ++ c` against `[<3, 4, 5]` has four solutions, and the program
  states the cell, as Remora's convention fixes a scalar frame for
  cell-polymorphic functions (read:
  `sources/papers/slepak-2018-constraint/paper.pdf`, §4). Where the
  result type fixes the frame, one unknown is left, `[<3] ++ ?c` against
  `[<3, 4, 5]`: stock Idris refuses it (measured: the research probe
  `Probe3.idr`; with `{c = [<4, 5]}` written, `Probe.idr` is accepted),
  and §4.4 solves it by cancelling the prefix.
- **The empty frame.** The result cells' extents are the argument
  `d : Ext d`; the frame's are the argument array's. No cell is ever
  needed to learn a shape, so the dynamic languages' devices have no
  counterpart: SATN-45's "by convention, if the frame is empty ..., then
  the empty vector is used as the result cell shape" (read:
  `sources/papers/bernecky-1983-satn45-rank-operator/satn45a.htm`:199-201),
  J's "the verb is applied to a cell of fills" (read:
  `sources/docs/j/help/dictionary/dictb.htm`:110-114), BQN's first-listed
  problem, "Empty arrays lose type information" (read:
  `sources/docs/bqn/commentary/problems.md`:11-13).
- **Shape calculators.** Hui calls a verb uniform when "the result shape
  depends only on the argument shape(s)", with a shape calculator `vs`
  (read: `sources/papers/hui-1995-rank-uniformity/rank1.htm` §2,
  lines 390-400). Here a calculator is any function `Ext c -> Ext d`,
  and since `Ext d` has one value, every calculator is correct: a
  function on rows that keeps their length reads `d` off its argument's
  extents, and auto search builds a literal `d`.
- **Two arguments: prefix agreement.**

  ```idris
  lift2 : Ext c1 -> Ext c2 -> Ext d -> (Array c1 a -> Array c2 b -> Array d e)
       -> Array (f ++ c1) a -> Array (f ++ (g ++ c2)) b -> Array (f ++ (g ++ d)) e
  rep   : Ext g -> Ext c -> Array (f ++ c) a -> Array (f ++ (g ++ c)) a   -- a view
  ```

  The left argument's cells are reused over the excess frame `g`: J's
  "one frame must be a prefix of the other" (read: `dictb.htm`:94-98),
  BQN's leading-axis agreement (read: `sources/docs/bqn/doc/leading.md`:98-100),
  Remora's principal frame. `lift2` is a lift over `f` of a lift over
  `g` with the left cell captured; a mirror swaps the roles; callers
  that want neither name `Agree f1 f2`, found by auto search, the
  principal frame computed from the evidence (Gibbons's `Alignable`
  logic program, aplicative.pdf §6, pp. 17-19; measured: the research
  probe `Probe9.idr` accepts a matrix with a vector and a symbolic
  prefix, and `Probe7.idr` refuses a 2×3 matrix with a 3-vector, whose
  frames are not prefixes of each other). NumPy's trailing
  alignment with size-1 stretching is rejected: MLIR's `Broadcastable`
  trait gives it undefined behaviour when two dynamic sizes differ and
  neither is 1 (read: `sources/docs/mlir/docs/Traits/Broadcastable.md`:28-36),
  where prefix agreement never consults a size.
- **Batching is free.** `lift [<n, k] [<n, m] (\a => matmul a b)` is a
  matrix product over any frame (measured: `Core.idr`, `batched`),
  SATN-45's `⌹` on a stack of matrices "rather than by looping" (read:
  `satn45a.htm`:809). §5.3 lowers it to one
  generic with the frame's dimensions in front.
- **Operators from rank.** The outer product is `lift` with scalar
  cells on the left and whole arrays on the right; the inner product of
  any pair of functions (`+.×`, `∨.∧` for reachability, `⌊.+` for
  shortest paths) is a lift and a reduction (read:
  `sources/papers/hui-2009-rank-operator/app1.htm`, `app2.htm`;
  `sources/papers/iverson-1980-notation-tool-of-thought/tot1.htm` §1.3).
  Each is a library definition and each lowers to the generic of a
  matrix product with its own combiner and reducer.

### 3.4 Uniform and non-uniform functions

A uniform function's result shape is a function of its arguments'
shapes: in Idris, a dependent function type whose result index is
computed from its arguments' indices. A function whose result shape
depends on its arguments' values returns an existential. Hui's own
example: `i.` is not uniform, but `m&{.`, with its shape-determining
argument fixed, is (read: `rank1.htm` §2); fixing that argument in the
type is what makes `iota` uniform here.

```idris
iota     : (n : Nat) -> Array [<n] (Fin n)
filter   : (a -> Bool) -> Array [<n] a -> Exists (\m => Array [<m] a)
compress : Array [<n] Bool -> Array [<n] a -> Exists (\m => Array [<m] a)
```

An array of existentials is ragged: `Array s (Exists (\m => Array [<m] a))`
holds arrays of hidden shape, boxed and counted (§5.2), never flattened.
Futhark makes the same cut: instantiating an element type with one whose
size is not in scope is what makes an array irregular, and it forbids it
(read: `sources/papers/henriksen-2021-size-types/paper.pdf`, §4); Remora
boxes such elements (read: `formalism.tex`:108-217). A flat segmented
form (offsets beside one data array, Hsu's offset and parent vectors,
Futhark's `FlatMap`) is a library type of two arrays (read:
`sources/papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt`,
§3; `sources/code/futhark/src/Futhark/IR/SOACS/SOAC.hs`:81-146).

### 3.5 Structural operations, typed by equations

```idris
append    : Array ([<n] ++ c) a -> Array ([<m] ++ c) a -> Array ([<n + m] ++ c) a
take      : (k : Nat) -> Array ([<k + n] ++ c) a -> Array ([<k] ++ c) a
drop      : (k : Nat) -> Array ([<k + n] ++ c) a -> Array ([<n] ++ c) a
reverse   : Array ([<n] ++ c) a -> Array ([<n] ++ c) a
rotate    : Int -> Array ([<n] ++ c) a -> Array ([<n] ++ c) a
transpose : Array [<n, m] a -> Array [<m, n] a
swap      : Ext f -> Ext c -> Array (f ++ c) a -> Array (c ++ f) a
reshape   : Ext t -> {auto 0 _ : size s = size t} -> Array s a -> Array t a
ravel     : Array s a -> Array [<size s] a
tile      : (d : Nat) -> Array ([<q * d] ++ c) a -> Array ([<q, d] ++ c) a
windows   : (k : Nat) -> Array ([<k + n] ++ c) a -> Array [<S n] (Array ([<k] ++ c) a)
```

- **Leading axis.** Structural functions act on the leading axis, the
  major cells, and the rank operator reaches the others (read:
  `sources/docs/bqn/doc/leading.md`, "The leading axis convention"); so
  every structural type above has the form `[<n] ++ c`.
- **Products in types.** Remora keeps products out of its index
  language to stay in Presburger arithmetic, so its `ravel` returns a
  box (read: `formalism.tex`:320-330). Here `ravel` and `reshape` are
  typed by `size`, because §4 decides semiring equations by normal form:
  `reshape`'s proof is `Refl` wherever the two sizes are equal as
  polynomials, and auto search finds it.
- **No inequality in a type** (decision D10). A structural type states
  an equation the caller's shape must meet: `take 3` applies to
  `[<3 + n] ++ c`. A caller whose length is a variable `m` does not meet
  it, §4.9 says so, and the program decides it with a view, which base
  already has for this case:

  ```idris
  -- base's Data.Nat, McBride and McKinna's trichotomy as a view:
  data CmpNat : Nat -> Nat -> Type where
    CmpLT : (y : _) -> CmpNat x (x + S y)
    CmpEQ : CmpNat x x
    CmpGT : (x : _) -> CmpNat (y + S x) y
  cmp : (x, y : Nat) -> CmpNat x y

  ||| Tiling's view, in Array.Shape: a size as whole tiles and a remainder.
  data Split : (d : Nat) -> Nat -> Type where
    MkSplit : (q, r : Nat) -> (0 _ : LT r d) -> Split d (q * d + r)
  split : (d : Nat) -> {auto 0 _ : NonZero d} -> (n : Nat) -> Split d n
  ```

  Matching `cmp 3 m` puts `m` as `3 + S y` in one clause and as `3` in
  another, where `take 3` applies, and as smaller than 3 in the third (read: `third_party/Idris2/libs/base/Data/Nat.idr`:429-440;
  `sources/papers/mcbride-2004-view-from-left/view.ps`, §6, `N-Compare`).
  Or the program casts, checked: `cast : Ext t ->
  Array s a -> Maybe (Array t a)`. Futhark's benchmark suite of 12,000
  lines needed 66 such dynamic coercions, mostly in input handling
  (read: `henriksen-2021-size-types/paper.pdf`, §6). A coercion is
  always written; none is inserted.

### 3.6 Coordinates and bounds

- **Typed access has no guard.** `index : Array s a -> Index s -> a`
  indexes both by `s`, every `Fin` of the coordinate is below its axis's
  extent by its type, and the array's extents are `s` by the singleton.
  Xi and Pfenning made bounds checks a type obligation in Dependent ML
  and measured 12% to 79% less time with the checks gone (read:
  `sources/papers/xi-1998-dml-bounds/pldi98dml.pdf`, Tables 1-2,
  pp. 6-7); Dex elides the check for every index a `for` made (read:
  `main.tex`:1851-1870).
- **How the fact lives in MLIR.** As the guard's absence, the rule
  `idr-in-bounds` already follows: the frontend emits `tensor.extract`
  with no guard for a typed access, and a pass that builds a new access
  on an index nothing proved builds the guard too (read: IdrOps.td:1835-1841).
  Tiling, fusion and partitioning keep the fact by construction: a tile
  is within its domain.
- **Integers into coordinates.** `toFin : (n : Nat) -> Int -> Maybe (Fin n)`
  and `indexChecked : Array s a -> Vect (rank s) Int -> a` carry
  `idr.check.in_bounds` against the extent, which `idr-in-bounds` proves
  where it can, as Dependent ML keeps a checked `subCK` where a proof is
  too deep (read: `pldi98dml.pdf`, §2.4 and appendix A).
- **The representation of a `Fin`.** In a loop body the coordinates are
  the loop's own indices, words from the start (§5.3); elsewhere a `Fin`
  is a natural, which `idr-narrow` makes a word where it proves it
  small, as today.

### 3.7 Reductions, scans and their laws

```idris
interface Monoid a => LawfulMonoid a where
  0 assoc    : (x, y, z : a) -> x <+> (y <+> z) = (x <+> y) <+> z
  0 neutralL : (x : a) -> neutral <+> x = x
  0 neutralR : (x : a) -> x <+> neutral = x

interface LawfulMonoid a => CommutativeMonoid a where
  0 commute : (x, y : a) -> x <+> y = y <+> x

reduce      : Monoid m => Array (f :< n) m -> Array f m        -- the last axis, in index order
insert      : Monoid m => Array ([<n] ++ c) m -> Array c m     -- the leading axis
foldl       : (b -> a -> b) -> b -> Array [<n] a -> b           -- any accumulator, in order
scan        : Monoid m => Array (f :< n) m -> Array (f :< n) m -- inclusive, the last axis
treeSum     : Array [<n] Double -> Double                       -- blocks of 1024, a fixed tree over them
scatterWith : (a -> a -> a) -> Array f (Index s) -> Array f a -> (1 _ : LArray s a) -> LArray s a
```

- **Order is meaning.** `reduce` and `scan` combine in index order unless
  a law says the order does not matter. Iverson's partitioning
  identities are the licence: associativity splits a reduction into
  tiles, commutativity into any partition, and the identity element
  gives the empty tile (read: `tot1.htm` §4.2).
- **Which reductions are unordered** (decision D11). A monoid with a
  `CommutativeMonoid` instance, whose laws Idris proved, selects the
  unordered reduction op. A combiner whose region is one integer
  primitive (addition, multiplication, the bitwise and, or and xor, at
  every width, and minimum and maximum) is a commutative monoid by the
  runtime's meaning of the primitive, which is the one meaning a
  primitive has (AGENTS.md), so the compiler knows it from the region,
  with no proof and no instance (base has no `Monoid Int`; the library's
  `Sum` and `Product` wrappers become those regions after
  monomorphisation). A floating-point sum has no law
  and keeps program order on both targets, at any number of lanes and
  shards, so its result is one result. A program that wants a float
  reduction reassociated calls one whose meaning fixes another order,
  `treeSum`: the elements in blocks of 1024 by index, each block summed
  as eight partial sums (element `i` into partial `i mod 8`, the eight
  then added left to right), and the block sums combined by a balanced
  binary tree over the block index. The order depends on the length
  only: the vectorizer computes it on 2, 4 or 8 lanes (each divides 8),
  and shards take whole blocks and combine them by the same tree, so the
  result is one result on both targets and at any number of cores.
- **The kind is the op's.** Ordered and unordered are two ops, not a
  discardable attribute: making an unordered reduction ordered is always
  legal, the converse never, so no pass can lose the fact by dropping it.
- **Accumulators by index pattern.** Dex's `Accum` effect admits only
  `+=` and no read until its handler ends, and the accumulator's index
  pattern decides the loop: never indexed, a complete reduction; indexed
  by loop indices, a segmented one; indexed by data, a histogram (read:
  `main.tex`:383-470, 1781-1811). Here those are `reduce`, a `lift` of
  `reduce`, and `scatterWith` into a linear array, parallel when its
  combiner is a commutative monoid.
- **Scans.** Upstream has no structured scan: no `linalg` op at the pin,
  and `vector.scan` takes a fixed combining kind (read: the pinned
  `LinalgStructuredOps.td`; `sources/code/mlir/include/mlir/Dialect/Vector/IR/VectorOps.td`:3032).
  `idr.tensor.scan` is ours, a combiner region along one axis,
  implementing `TilingInterface`, shaped like Triton's `tt.scan` (read:
  `sources/code/triton/include/triton/Dialect/Triton/IR/TritonOps.td`:876-905).

### 3.8 Linear arrays and in-place updates

```idris
export
data LArray : (0 s : Shape) -> Type -> Type

withArray  : Ext s -> a -> ((1 _ : LArray s a) -> Ur b) -> b
read       : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))
write      : (1 _ : LArray s a) -> Index s -> a -> LArray s a
modify     : (1 _ : LArray s a) -> Index s -> (a -> a) -> LArray s a
mapInPlace : (a -> a) -> (1 _ : LArray s a) -> LArray s a
freeze     : (1 _ : LArray s a) -> Ur (Array s a)
thaw       : Array s a -> ((1 _ : LArray s a) -> Ur b) -> b
```

(`Ur`, written `!*`, and `Res` are `mlir-linear`'s, read:
`libs/mlir-linear/Linear/Notation.idr`.)

- **Linearity is not ownership.** A function taking an argument at
  quantity 1 "promises that it will not share the argument in the
  future; there is no requirement that it has not been shared in the
  past" (read: `brady-2021-idris2-qtt/erasure.tex`:34-38), and AGENTS.md
  says so: a linear binder does not imply unique heap ownership. The
  library supplies the past: an `LArray` is born fresh (`withArray`, and
  `thaw`, which copies) and leaves only by `freeze`, so no `LArray`
  aliases a shared cell. In MLIR its writes are a chain of `tensor.insert`
  on `!idr.lin<tensor<...>>`, a thread One-Shot bufferizes in place: a
  thread Idris bound at quantity 1 never reads an old version after a
  new one (§5.4).
- **Checked twice.** Futhark checks uniqueness at the source and again
  on its core IR after every pass (read:
  `sources/papers/henriksen-2017-futhark-thesis/thesis.pdf`, §5.3;
  `sources/code/futhark/src/Futhark/IR/TypeCheck.hs`:187-252); here QTT
  checks the source and the verifier checks `!idr.lin` after every pass
  (AGENTS.md). Futhark measured k-means 8.3 times slower without
  in-place updates (thesis §10.1.5).
- **`thaw` on values.** On tensors `thaw` is the identity; One-Shot
  copies only when the frozen array is read again after the first write,
  so thawing an array at its last use copies nothing.
- **The in-place promise.** README.md promises in-place updates for
  quantity-1 values "with no runtime test"; every write to an `LArray`
  is in place, and under `--demand-in-place` a write that is not is
  `unsupported (uniqueness)` naming One-Shot's conflict (§5.4).

### 3.9 Totality and compile-time evaluation

- **Total by construction.** Every core operation is total when its
  function arguments are. Rank recursion is structural recursion on the
  singleton:

  ```idris
  sumAll : Ext s -> Array s Double -> Double
  sumAll Lin x = index x Here
  sumAll (e :< n) x = sumAll e (lift [<n] Lin (\v => tabulate Lin (\_ => sumRow v)) x)
  ```

  It is total at every rank, a shape variable's included (measured:
  `Core2.idr`).
- **Evaluated when closed.** Compile-time evaluation follows upstream
  Idris (AGENTS.md): every closed call of pure code is evaluated. A
  closed computation of an array of words becomes a dense constant,
  `arith.constant dense<...> : tensor<...>`, within idr-eval's budget
  and its 1 MiB limit on results (read: Passes.td:119-157) (decision
  D13).
- **Finitely many instances.** Rank recursion calls the instance of a
  shorter skeleton; a skeleton that grows at each call is collapsed
  (§5.1), never refused and never unrolled.

## 4. Shape arithmetic in the elaborator

Every refusal of §1.5 is an equation in one of two theories, or in both:
the commutative semiring of the naturals (extents) and the free monoid of
lists (shapes), linked by homomorphisms (`rank`, `size`). The remedies on
record fall in five families: generalise the goal so that the motive is
well-typed; eliminate equations by unification; make the equation
definitional; decide it by a normaliser or a solver; restrict the size
language so that it cannot arise. Futhark restricts: size equality is
syntactic, on purpose, since normalisation would let "the inference
algorithm's arbitrary choices" change results (read: `bailly-2023-size-dependent/paper.pdf`,
§4.2, the `tricky` example; the hazard is an arbitrary choice among
several solutions, and §4.4 never makes one: a problem with several
solutions stays stuck). Remora
decides by canonical forms (read: `formalism.tex`:464-524). GHC's plugins
normalise (`ghc-typelits-natnormalise`) or ask an SMT solver (Diatchki).
Agda adds rewrite rules; Lean and Rocq decide inside tactics.

(decision D7) The fork makes the theory definitional: three clauses in
the evaluator (4.2), canonical forms in conversion (4.3), unique
solutions in unification (4.4), refutations in coverage (4.5), each step
under a published soundness criterion, and nothing named.

### 4.1 The theory, recognised by its definitions

- **Naturals:** zero, successor, literals, addition, multiplication.
  Atoms are every other neutral of a natural type: variables,
  metavariables, and stuck applications such as `finToNat i`, or `size s`
  for an opaque `s`.
- **Lists:** nil, snoc or cons, append. Atoms are every other neutral of
  a list type.
- **Homomorphisms** from lists to naturals, `h nil = e` and
  `h (s :< x) = h s ⊕ g x` with ⊕ addition or multiplication and `e` its
  unit (`rank`, `size`, a sum of extents), and from lists to lists
  (`map`, which distributes over append: Allais et al.'s ν-rule
  `map f (xs ++ ys) = map f xs ++ map f ys`, read:
  `sources/papers/allais-2013-new-equations-neutral-terms/main.tex`:155-185).
- **Recognised by case tree, not by name.** A function is addition when
  its case tree is `f Z y = y; f (S k) y = S (f k y)` on a type shaped
  like the naturals (a nullary and a unary constructor: the shape the
  frontend already reads as a natural, IdrOps.td:175-184), multiplication
  when it is `f Z y = Z; f (S k) y = g y (f k y)` with `g` addition,
  append when it is the snoc list's, the list's or the vector's
  definition, and a homomorphism when it is the two clauses above. The
  Prelude's `plus`, `mult` and `(++)` are found that way (read:
  `Prelude/Types.idr`:48-64, 424-427), and so is any program's copy. The
  fork names no definition: the registry is the frontend's, and the
  theory needs none. Recognition is cached per definition for the
  session, so the formats of TTC files do not change.

### 4.2 Evaluation: three clauses

Cockx, Piessens and Devriese give `plus` four clauses, the definition's
two and `plus x zero = x`, `plus x (suc y) = suc (plus x y)`, read as
definitional equalities that apply in any order, and prove such a
definition confluent when every pair of clauses' patterns unifies,
positively or negatively, and the right sides of a positive pair join
(read: `sources/papers/cockx-2014-overlapping-patterns/paper.pdf`, §1
definition (5), p. 3; Proposition 2, p. 12). With them, commutativity of
`plus` has a two-line proof (p. 10).

(decision) Where a recognised function is stuck on its first argument,
the fork's evaluator applies:

| function | clause |
| --- | --- |
| addition | `x + Z ⟶ x` and `x + S y ⟶ S (x + y)` |
| multiplication | `x * Z ⟶ Z` |
| append on snoc lists | `[<] ++ s ⟶ s` |
| append on lists and vectors | `xs ++ [] ⟶ xs` |

- **Confluent.** Addition's four critical pairs join: `Z + Z` and
  `Z + S y` trivially, `S x + Z` to `S x`, and `S x + S y` to
  `S (S (x + y))` either way. `x * Z` against the definition's
  `S k * Z = Z + k * Z` joins at `Z`. The appends' new clause meets the
  definition's at `[<] ++ [<]` and `[<] ++ (t :< x)` and joins. Each new
  clause recurses on the second argument where the definition recurses
  on the first, so evaluation terminates by size change.
- **Why evaluation, not comparison.** Allais, McBride and Boutillier
  require that "ordinary evaluation is complete for uncovering
  constructor-headed terms": a term definitionally equal to a constructor
  form must evaluate to one, because a type checker exposes heads by
  evaluating (read: `allais-2013/main.tex`:1278-1300). If `n + 1` equalled
  `S n` only in comparison, `pred (n + 1)` would stay stuck while
  `pred (S n)` computes. With the clauses, a sum whose constant part is
  positive evaluates to a successor: `Vect (n + 1) a` matches `(::)` by
  ordinary unification (F4), and `size [<n, m]` evaluates to `n * m`
  (F1). (conjecture: every polynomial expression with a positive
  constant term evaluates to `S _`; stage T1 tests it on generated
  expressions.)
- **Not added.** `x * S y ⟶ x + x * y` would meet the definition's
  second clause in a pair that joins only up to commutativity of
  addition, which is comparison's work (4.3); and multiplication exposes
  no constructor that its operands do not.

### 4.3 Conversion: canonical forms of stuck spines

Allais et al.'s ν-rules identify neutral terms that have the same "nut"
after evaluation stops, and never emit constructors: their table holds
associativity of append, `map` fusion and `fold` over append (read:
`main.tex`:155-190). A ν-rule must hold by structural induction, its
critical pairs with evaluation and with the other rules must converge,
and the rules must terminate (main.tex:1329-1350). Canonical forms meet
the three by construction: they are computed, not rewritten.

(decision) When conversion compares two terms that do not convert by
the stock rules and one of them is a stuck arithmetic or append spine,
it compares their canonical forms:

- **A natural** is a sum of monomials with positive coefficients, each
  monomial a sorted multiset of atoms. Rocq's `ring` decides the
  commutative-semiring fragment by this normal form (read:
  `sources/docs/rocq/doc/sphinx/addendum/ring.rst`:27-45),
  `natnormalise` decides GHC's equalities on `Nat` by a sum of products
  compared syntactically (read:
  `sources/code/ghc-typelits-natnormalise/src/GHC/TypeLits/Normalise/SOP.hs`:1-77),
  and Remora's dimensions are its linear case (read:
  `formalism.tex`:464-485). Two polynomials that agree at every natural
  point are the same polynomial, so the comparison says "equal" exactly
  when the two terms are equal for every value of their atoms.
- **A list** is the sequence of its components, each one element or one
  opaque atom, nested appends flattened. Remora proves the form
  canonical for the universal fragment: two shapes that differ in it
  differ under some interpretation (read: `formalism.tex`:486-524), and
  the check takes linear time (read: `slepak-2018-constraint/paper.pdf`, §5).
- **A homomorphism** of a list is the fold of its operation over the
  components: `size ((f ++ g) :< n)` is `size f * size g * n`, with
  `size f` and `size g` atoms when `f` and `g` are opaque.
- **Atoms** are compared by conversion, recursively, and ordered by a
  fixed total order on their quoted forms. Two atoms that convert but
  quote differently sort apart: the comparison then answers "different",
  stock Idris's answer, so it can miss an equality and never invents one.
- **A budget.** A canonical form holds at most 4096 monomials; past it,
  the comparison answers "different" (decision D7, with its measurement).
- **Commutativity is a normal form, not a rule.** `m + n ⟶ n + m` loops
  and cannot be oriented; Agda's rewrite rules need a neutral left side
  and confluence (read: `sources/docs/agda/doc/user-manual/language/rewriting.lagda.rst`:295,
  329-350) and cannot express it. Sorting does (F2).

### 4.4 Unification modulo the theory

- **Strong rules.** Cockx's custom unification rules keep a definition's
  clauses definitional when each is a strong unifier, an equivalence of
  telescopes that computes, and contains no unsolved metavariables
  (read: `sources/papers/cockx-2017-dependent-pattern-matching-thesis/thesis.pdf`,
  Definition 3.45; §5.1, "Custom unification rules", printed pp. 129-130).
  (decision) The fork adds, after the stock rules fail:
  - *deletion modulo the theory*: equal canonical forms succeed with no
    substitution (W3);
  - *cancellation*: the common part of two canonical forms is removed,
    since addition on the naturals is cancellative, `(a + x ≡ a + y) ≃
    (x ≡ y)`;
  - *solving*: after cancellation, a side that is one metavariable with
    coefficient 1 is assigned the other side; a constant factor that
    divides every coefficient of the other side is divided out
    (`natnormalise`'s rules, `(2 + a) ~ 5 ⟹ a := 3` and `(i*a) ~ j ⟹
    a := j/i` when divisible, read: `Unify.hs`:410-485);
  - *successor*: `S p` against `q` whose constant is at least 1 reduces
    to `p` against `q - 1`; `Z` against `q` whose constant is at least 1
    is refuted;
  - *lists*: with one list metavariable among known components, the
    known prefix and suffix are cancelled (the free monoid is
    cancellative on both sides) and the metavariable takes the middle; a
    rigid opaque component cancels only against itself, since Remora's
    solver treats a universal shape variable as a generator that no
    boundary may split (read: `Dissertation.pdf`, §7.3, pp. 113-114);
    with the same kinds of component at each position (an element
    against an element, an opaque part against an opaque part) and no
    list metavariable, the components unify pairwise; an element against
    an opaque part is stuck, since a rigid shape may hold one element.
- **Unique solutions only.** A rule fires only when its solution is the
  only one, as `natnormalise` matches term by term "only when it yields a
  single unifier" (read: `Unify.hs`:620-646). Two list metavariables in
  one equation have several solutions; the problem stays postponed, and
  the program states one (Remora's convention, §3.3). Remora's inference
  needs Makanin's algorithm for the existential fragment of the free
  monoid, which is NP-hard (read: `slepak-2018-constraint/paper.pdf`,
  §5); "with one variable the algorithm degenerates to peeling generators
  off the ends" (read: `slepak-2020-dissertation/Dissertation.pdf`, §5.3,
  pp. 69-70). This design stops at one variable.
- **Three outcomes, kept.** Solved, refuted, stuck. Stuck at the end of
  elaboration is the error of 4.9.
- **Auto search** uses the same unifier, so the hint `prefixAppend :
  Prefix f (f ++ g)` matches the goal `Prefix f (f ++ g)` once `?f := f`
  cancels against the common prefix. (conjecture: F7 and `Probe10.idr`
  are accepted; stage T1 tests them.)

### 4.5 Coverage

A clause is impossible when its patterns' index unification is
refuted. The theory refutes more: a constant left after cancellation
(`Z` against `n + 1`), lists of different lengths with no opaque
component, two different literal extents at one position. Only a
refutation removes a clause: a stuck problem keeps it, as Goguen, McBride
and McKinna's specialisation by unification has three outcomes and only
the negative one excludes a case (read:
`sources/papers/goguen-2006-eliminating-dependent-pattern-matching/paper.pdf`,
Definition 19, p. 16).

### 4.6 `rewrite` and `with`

After 4.2 to 4.4, array code needs no rewrite by an arithmetic or append
lemma. Programs still rewrite by lemmas about their own functions, and
five changes make that robust (decision D8):

1. **A rewrite whose sides already convert is the identity.** The body
   is checked against the goal and no predicate is built. Without this
   rule, a rewrite by `plusZeroRightNeutral n` in base would abstract
   every `n` of the goal, since every `n` now converts with `n + 0`.
2. **Keyed abstraction on the goal as written.** The occurrences are the
   subterms of the goal before normalisation whose head and arity are
   the left side's and which convert with it: Lean's `kabstract` (read:
   `sources/code/lean4/src/Lean/Meta/KAbstract.lean`:30-52). Only when
   that finds none does the rewrite abstract the normal form, as today,
   so every rewrite that works today finds what it finds today.
3. **The motive is checked.** McBride warns that the abstracted goal
   "may not be well-typed" (read:
   `sources/papers/mcbride-2000-elimination-motive/elim.ps`, §8); McBride
   and McKinna's `with` rule says the abstractions "must be typechecked
   again, to ensure that replacing the elaborated term s by a variable
   has not compromised validity" (read: `view.ps`, §5.1, Fig. 12); Lean
   checks and reports "motive is not type correct" (read:
   `src/Lean/Meta/Tactic/Rewrite.lean`:57-73). Idris builds the predicate
   unchecked and accepts an ill-typed one (§1.5, F6).
4. **Dependents generalised, or the variable substituted.** When the
   motive fails, the hypotheses whose types mention the left side, and
   those that depend on them, are generalised with it: Agda partitions
   the context into the smallest part the scrutinee needs and the rest,
   generalises the rest, and checks that the result "is type correct"
   (read: `sources/docs/agda/doc/user-manual/language/with-abstraction.lagda.rst`:909-936);
   Idris's `bindNotReq` already makes that partition for `with`
   (`TTImp/Elab/Utils.idr`:87). When one side is a local variable that
   does not occur in the other, the rewrite is a match on `Refl`, which
   substitutes the variable everywhere and builds no motive at all:
   Lean's `subst` reverts the variable and its dependents and eliminates
   (read: `src/Lean/Meta/Tactic/Subst.lean`:25-40), and the match works
   in Idris today (§1.5, W1). When neither succeeds, the error names the
   subterm whose type mentions the left side, not an unrelated
   unification failure.
5. **Motive search.** When an occurrence sits inside an argument that
   cannot be generalised (its type mentions the left side and it is not
   a local variable), that occurrence is left as it is written and the
   motive is checked again: the predicate may mention the left side
   freely, so dropping an occurrence never makes the rewrite wrong, only
   weaker. The search removes one such occurrence per check, so it is
   linear in the occurrences; when none is left to abstract, the rewrite
   reports that it changes nothing, as `RewriteNoChange` does today. This
   is Lean's `occs` option chosen by the elaborator instead of the user
   (read: `Rewrite.lean`:62-73, which suggests it).

`with` shares 2 to 5: its abstraction and its generalisation are the
same code.

### 4.7 Partial unification

When a pattern's index unification is stuck, Idris refuses the clause.
Cockx proposes handing the user the partial unifier and binding the
stuck equations, `f m (cons[e₂] n x xs)` with `e₂ : l m ≡ suc n` (read:
`thesis.pdf`, §5.1, "Partial unification", Example 5.1). McBride's
BasicElim makes the same move: generalise the instantiated index and
constrain it by an equation, a technique he learned from McKinna (read:
`elim.ps`, §2).

(decision D9) The fork generalises a stuck index and binds each residual
equation as an erased hypothesis of the clause, visible in holes and to
auto search. Coverage then needs every clause whose equations are not
refuted.

```idris
halves : Vect (n * 2) a -> ...
halves []        = ...   -- with 0 _ : n * 2 = 0
halves (x :: xs) = ...   -- with 0 _ : n * 2 = S len, xs : Vect len a
```

The equations are at quantity 0 and cost nothing at run time.

### 4.8 What types do not decide

- **Inequalities.** A bound is a `Fin` (§3.6), an equation `k + n` in a
  structural type (§3.5), or a test at run time whose proof is erased
  (decision D10). Remora keeps products out of its index language to
  stay in Presburger arithmetic (read: `formalism.tex`:320-330); this
  design admits products in equations, which the semiring normal form
  decides, and keeps them out of inequalities, where nonlinear
  arithmetic over the naturals is undecidable. The linear bounds a
  program checks at run time are what `idr-in-bounds` already decides as
  Presburger systems in MLIR (read: Passes.td:443-493), the fragment
  that Rocq's `lia` decides inside proofs, by "a complete proof
  principle for integer linear arithmetic", and that Lean's `omega`
  handles, by its own account "not yet a full decision procedure"
  (read: `sources/docs/rocq/doc/sphinx/addendum/micromega.rst`:184-231;
  `sources/code/lean4/src/Init/Tactics.lean`:1541-1546).
- **No external solver.** Diatchki's plugin hands `Nat` constraints to
  an SMT solver and returns no evidence beyond its answer (read:
  `sources/papers/diatchki-2015-smt/paper.tex`:1065-1080). This compiler
  runs no tool at compile time but its own, and every equality the fork
  accepts is one its canonical forms prove.
- **No library tactic as the main path.** Frex is a proof-producing
  solver for monoids and commutative monoids written in Idris 2, but its
  proofs are type-checked by Idris's evaluator: under 0.1 s for terms of
  size 6 with the commutative solver, past 10 s for some of size 45
  (read: `sources/papers/allais-2025-frex/evaluation.tex`:34-53). And
  Idris's reflection hands the solver the normalised goal, where `1 + y`
  has become `S y`, an atom the monoid solver misreads (read:
  `reflection.tex`:125-145). The size of a rank-8 reshape is already a
  term of that order. Frex stays available to programs for theories the
  fork does not decide.

### 4.9 Diagnostics

- **Stuck** equations are printed in canonical form with what is known
  of their atoms: "Can't solve `m = 3 + ?n`: `m` is not known to be at
  least 3; `cmp 3 m` decides it, or a checked `cast`" (F5).
- **Refuted** identities come with a counterexample. The canonical forms
  differ as polynomials, so a point of a small grid separates them, and
  the fork tries the grid's points in order: "`n * m = n` is false at
  n = 1, m = 0". Qube reports concrete index values from its solver's
  model the same way (read: `sources/papers/trojahner-2009-qube/paper.pdf`,
  §8).
- **Origins.** Futhark keeps the origin of every size name it generates
  for its errors (read: `henriksen-2021-size-types/paper.pdf`, §5); a
  generalised index (4.7) is named after the pattern it came from.

### 4.10 Soundness, and what stays Idris 2

- **Consistent.** Every identification holds in the standard model, the
  naturals and finite sequences, so no two distinct values become equal
  and `Z = S Z` stays empty.
- **Decidable.** Evaluation terminates (4.2); canonical forms are finite
  and budgeted (4.3); each unification rule shrinks its problem (4.4).
- **Confluent.** The new clauses join with the definitions (4.2), and
  comparison never reduces anything.
- **No new term.** Every new equality is definitional, so the checked TT
  the frontend reads holds no proof term it did not hold before, and
  nothing is erased that was not.
- **A superset of Idris 2.** The new unification rules run where the
  stock unifier has postponed a problem for the last time, the point at
  which Idris reports it; a program whose unification Idris completes
  meets none of them. Conversion answers "equal" more often, and one
  class of program can change with it: where stock Idris rejected an
  overloaded alternative or an auto search hint because two arithmetic
  terms differed, it may now succeed. Overloading and auto search each
  report two successes as an ambiguity (`exactlyOne`, read:
  `TTImp/Elab/Check.idr`:608-673; `Core/AutoSearch.idr`:168-188), a
  visible error; only the alternatives tried first-success (`anyOne`,
  `Check.idr`:675-692, `AutoSearch.idr`:153-166) could choose another.
  Decision D7 measures both on prelude, base, the fork, every test and
  Idris's own suite.
- **Who uses it.** The fork is built by stock Idris at stage 0 and by
  itself after; neither its source nor `libs/mlir-linear`, on which it
  depends, uses the extension, so both still build with stock Idris.
  `libs/mlir-array` uses it and is built only by this compiler, whose TTC
  files nothing else reads (read: `compiler/idris/README.md`).

### 4.11 Where in the fork

| Module (`compiler/idris/src/`) | Change |
| --- | --- |
| a new `Core/Arith.idr` | recognition by case tree; canonical forms of naturals and lists; homomorphisms; the budget; the skeleton the frontend reads (§5.1) |
| `Core/Normalise/Eval.idr` | the three arithmetic clauses and the appends' unit clauses, applied where a recognised function is stuck (4.2) |
| `Core/Normalise/Convert.idr` | canonical-form comparison where the stock cases answer "different" on a stuck spine (4.3; the cases at lines 366-427) |
| `Core/Unify.idr` | the rules of 4.4, run at the last postponement (lines 211-260, 623-636) |
| `Core/Coverage.idr`, `Core/Case/CaseBuilder.idr` | refutation modulo the theory (4.5) |
| `TTImp/Elab/Rewrite.idr`, `Core/Normalise.idr` (`replace`) | the identity case, keyed abstraction, the motive check, generalisation, substitution, motive search (4.6) |
| `TTImp/ProcessDef.idr`, `TTImp/WithClause.idr`, `TTImp/Elab/Utils.idr` | `with` sharing that code; the residual equations of a stuck pattern bound as erased hypotheses (4.6, 4.7) |
| `Idris/Error.idr` | stuck equations in canonical form, counterexamples, origins (4.9) |

`compiler/idris/README.md` records each under "Ours", as it records the
fork's other departures.

## 5. From types to MLIR

### 5.1 The skeleton keys the instance

- **The skeleton** of a shape is its canonical form (4.3) with every
  extent forgotten: a sequence of components, each an axis or an opaque
  part. Its length is the rank of the tensor. The fork's function that
  conversion uses computes it, and the frontend calls the same function:
  one definition of what a shape's components are.
- **Keyed by skeleton** (decision D3). An erased parameter whose value
  is the shape of a recognised array type in the rest of the type keys
  the instance by its skeleton at the call. This extends the frontend's
  rule that keys the shape of a runtime argument "when the rest of the
  type must reduce on it" (Instances.idr:154-176, 230-256): the rest of
  the type's representation needs the skeleton. `rowSumsAny` called with
  `f = [<3, 4]` and with `f = [<2]` is two instances, of ranks 3 and 2.
  The same rule keys a data instance: a field of an array type whose
  shape is an index of the data type makes that index's skeleton part
  of the instance (`MkLayer : Array s Double -> Layer s`), and an
  existential shape (`Exists (\s => Array s a)`) is an opaque component.
- **Extents are never keyed.** They are runtime values, and
  idr-specialize already clones a callee for a static argument (read:
  Passes.td:179-211), which makes an extent a constant where the program
  gives a literal; `tensor.dim` then folds, and canonicalisation turns
  the tensor's type static.
- **Collapsed where not static.** Where the skeleton is not static at the
  call (it depends on a runtime value, or a recursion grows it), the
  part that is not static is one opaque component: one dimension of the
  tensor, whose extent is the product of the part's extents, with the
  part's own `Ext` carried beside the tensor. Remora's compilation plan
  says the same: a flat buffer, with "cell-polymorphic functions taking
  their shape arguments as products of dimensions", the exceptions being
  "when shape information is meant to move from the index level to the
  term level and when data leaves the program" (read:
  `slepak-2020-dissertation/Dissertation.pdf`, §11.2, p. 165). For array
  shapes the frontend's `growing` rule collapses the part that grows
  instead of refusing the instance.

### 5.2 Representations

| Idris type, at a skeleton of k components | Frontend `Ty` | MLIR |
| --- | --- | --- |
| `Array s E`, E a word | `TensorT k E` | `tensor<?x…xE>`, k dimensions, and the `Ext` of each opaque component beside it |
| `Array s (Array c E)` | as `Array (s ++ c) E` | one tensor of k + rank(c) dimensions |
| `Array s R`, R a record of words | a record of one `TensorT k` per field | a tensor per field |
| `Array s V`, V any other value | `TensorT k V` | a tensor of `!idr.box<…>`, `!idr.str` and the like: counted elements |
| `Array s (Exists (\m => Array [<m] E))` | `TensorT k` of the existential | a tensor of boxed arrays (ragged) |
| `LArray s E` | `TensorT k E` at quantity 1 | `!idr.lin<tensor<…>>` |
| `Ext s` | a record: a natural per axis, an `Ext` per opaque component | `index` values where they meet a tensor |
| `Index s` | the same record, a `Fin` per axis | in a loop body, the loop's own indices |

- **Nested arrays flattened.** This is forced by the representation,
  not chosen by a heuristic: a nested array of uniform shape has no
  other representation. Futhark's arrays of arrays are regular by their
  size types (read: `henriksen-2021-size-types/paper.pdf`, §4), Dex
  lowers a nested array type to "a single flat memory buffer that holds
  unboxed values" (read: `paszke-2021-dex/main.tex`:1859-1860), and SaC
  scalarises nested with-loops into one over the concatenated index
  space (read: `grelck-2006-sac/paper.pdf`, §3.4).
- **Records as several tensors.** Futhark transforms arrays of tuples
  into tuples of arrays before it flattens (read:
  `sources/papers/henriksen-2019-incremental-flattening/paper.pdf`, §2
  and §4); Dex converts arrays of structures into structures of arrays
  (main.tex:1859). A `linalg.generic` has several results, so a
  tabulate of records is one generic with one output per field, and the
  vectorizer sees words.
- **Counted elements.** A tensor's element may be any value type of the
  dialect: each implements `MemRefElementTypeInterface` (read:
  IdrOps.td:110-171). A generic's body reads an element as a view and
  yields an owned one, and idr-rc places the counts once `isArrayLoop`
  answers for `linalg` structured ops (read:
  `foreign/idr/lib/Ownership/ArrayLoop.cppm`). Bufferization copies such
  a tensor with a reference taken per element: One-Shot's allocation and
  copy are the client's hooks (`allocationFn`, `memCpyFn`, read:
  `sources/code/mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h`:252-372),
  and ours builds `idr.array.copy`, whose counting idr-rc knows as it
  knows `idr.array.new`'s fill. The vectorizer leaves such loops scalar,
  as it leaves any loop it refuses (read: Passes.td:663-689).
- **`Ext` and `Index` as records.** Their constructors are determined by
  the skeleton (`Lin` and `Here` for no component, `:<` and `At` for an
  axis), so at a static skeleton a value is the record of its fields
  along that spine, and a match on it is a projection; at an opaque
  component the value is the inductive one. This is the registry's
  representation hook for the library's two families. `Vect` does not
  get it: its length keys no instance and it stays a list (AGENTS.md:
  indexed vectors do not imply contiguous storage).
- **Extents into MLIR.** Extents are naturals in Idris and `index`
  values in a tensor's type; they cross at `tensor.empty`, through the
  check that each fits, so an extent past the address space ends the
  program where the allocation would.

### 5.3 The core and its lowering

The frontend emits pure ops on tensors from an array's birth. The Idris
side's generated contract gains the `tensor` dialect, as arith and
memref are generated today, so the frontend writes upstream's ops and no
op of ours mirrors one (decision D6). Ops of ours exist only where a
region holds Idris code that defunctionalisation and the simplify loop
must see before it is a `linalg` body, as `idr.array.generate` exists
today.

| Core operation | The frontend emits | After the raise (§5.4) |
| --- | --- | --- |
| `tabulate e f` | `idr.tensor.tabulate`: k extents, a region of k indices yielding an element | `linalg.generic` with k parallel dimensions into `tensor.empty` |
| `tabulate e f`, `f` yielding a cell | the same op, its region yielding a tensor of the cell's shape | one generic over frame and cell when the cell is itself a tabulate (scalarised); else `scf.forall` over the frame with `tensor.parallel_insert_slice` |
| `index x i` | `tensor.extract`, no guard | |
| `index x i`, the element an array | `tensor.extract_slice`, rank-reducing: a view | |
| `extents x` | `tensor.dim` per axis, the carried `Ext` per opaque component | |
| `reshape`, `ravel`, `tile` | `tensor.collapse_shape`, then `tensor.expand_shape`; the reassociations from the two canonical forms, the output extents from `Ext t` | |
| `append` | `tensor.concat` | |
| `reduce`, `insert` | `idr.tensor.reduce`, or `idr.tensor.reduce_unordered` (§3.7) | `linalg.reduce`, or a generic with reduction dimensions; one lane, one shard when ordered |
| `foldl` | `idr.tensor.fold` | `scf.for` |
| `scan` | `idr.tensor.scan` | `scf.for`; two passes over tiles when unordered |
| `write`, `read` on an `LArray` | `tensor.insert`, `tensor.extract` on `!idr.lin<tensor<…>>` | |
| `freeze`, `thaw` | the tensor itself | One-Shot copies where a read follows a write |

- **Affine reads are indexing maps.** A tabulate's body that reads an
  outside array at affine functions of its coordinates (with the extents
  as symbols) takes that array as an input of the generic with that
  indexing map. This generalises `Loops.cppm`'s rule for reads at the
  loop's own index under a test on entry (read: `Loops.cppm`:33-41,
  `readAtIndex`) to k indices and affine maps. `map`, `zipWith`,
  `transpose`, `reverse`, `take`, `drop`, replication and windows reach
  `linalg` as generics with projected or permuted maps, so a small core
  loses no structure: Hui's "integrated rank support", never building the
  cells and striding through the argument instead, measured up to 157
  times faster in J (read: `rank1.htm` §1), is what an indexing map is.
- **A fold inside a tabulate is a reduction dimension.** A tabulate whose
  body folds over outside arrays at its coordinates is one generic with
  reduction dimensions: `Loops.cppm`'s generate-of-fold rule (read:
  lines 22-31, `reducedBy`) at any rank. A matrix product is one generic
  of three dimensions; lifted over a frame of two, one of five.
- **Coordinates of an opaque component** are delinearised from the
  collapsed index with the component's carried `Ext` only where a body
  uses them (`affine.delinearize_index` at the pin, read:
  `.toolchain/llvm-project/mlir/include/mlir/Dialect/Affine/IR/AffineOps.td`:1109);
  a body that ignores them (`map`, `zipWith`, a reduction over whole
  components) costs what it costs at a static skeleton.
- **No guard where the type proved it.** Typed reads have none; reads
  that the test on entry covers lose theirs as today.

### 5.4 Tensors until bufferization

Kept from this proposal's first version (its §3.1 to §3.6), with the
changes the types bring.

- **Which arrays are tensors** (decision D2). Typed arrays, from birth.
  A rank-1 `Linear.Array` thread, by the raise, when no world of the
  program orders it, every loop result is a tensor, and the thread is
  linear in effect: it starts at a new array, runs through SSA, and
  One-Shot's analysis of the raised thread puts every write in place; a
  thread whose writes conflict keeps its memref ops and its one-object
  meaning, and a thread that starts at a value read out of a box is not
  raised. The first version's first condition, that the elements are
  words, is gone (§5.2).
- **`idr-tensorize`**, after idr-defunctionalize and canonicalize, when
  no closure is left in a loop body, turns `idr.tensor.*` and the rank-1
  loop ops into `linalg` on tensors. For the rank-1 ops: a generate is
  `linalg.fill` of its fill into `tensor.empty`, then a parallel generic
  whose output is the slice from element 1 on; a fold is a reduction
  generic into a 0-d tensor; a generate whose body folds over an outside
  array is one generic of two dimensions; reads of outside arrays at the
  loop's index are inputs under the test on entry; a raised thread's
  `new`, `set` and `get` are `linalg.fill`, `tensor.insert` and
  `tensor.extract`, and its `freeze` is `tensor.extract_slice` to the
  size, a view. `tensor.generate` is not used: it has no destination and
  always allocates (read: `sources/docs/mlir/docs/Bufferization.md`,
  "Destination-Passing Style").
- **The grade survives bufferization.** A linear array is
  `!idr.lin<tensor<…>>` before and `!idr.lin<memref<…>>` after:
  `idr::QType` implements upstream's `TensorLikeType` over a tensor
  carrier and `BufferLikeType` over a memref one (read: the pinned
  `mlir/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td`:18-50),
  and `idr.lin.enter` and `idr.lin.use` implement
  `BufferizableOpInterface` as equivalent to their operand.
- **Fusion and tiling.** `linalg-fuse-elementwise-ops` on tensors folds a
  producer read only by its consumer into the consumer's body;
  `transform.structured.fuse` tiles generics of two or more dimensions to
  the L1 data cache that the module's DLTI target spec records from the
  target's entry in CMakeLists.txt, and no other pass reads a cache size.
  Vectorization stays where it is: tiles bufferize to memref generics,
  which `idr-vectorize` and `idr-narrow-lanes` treat as today.
- **`idr-bufferize`** is One-Shot through `runOneShotModuleBufferize`,
  with function boundaries at the identity layout, `allocationFn`
  building `idr.array.alloc` (a new cell whose elements are unspecified
  until written, as `tensor.empty`'s are), `memCpyFn` building
  `idr.array.copy`, and no deallocation pass: every buffer is a cell,
  and counting frees it.
- **Recursion.** One-Shot treats a call between functions that call each
  other as reading and writing its operands (read:
  `OneShotModuleBufferize.cpp`, "functions that call each other
  circularly"). Measurement rule: the raise reports each thread it does
  not raise as a `missed` remark with One-Shot's conflict; a program of
  `bench/` whose thread stays a memref only because of a recursive
  boundary is the threshold for extending the module analysis upstream,
  as a patch under `upstream/`, not as an analysis of ours.
- **No overlap with idr-rc.** One-Shot decides in place over SSA before
  counting; after bufferization every buffer is a cell, which idr-rc
  grades as any array. No pass consults a grade to decide a copy, and no
  runtime uniqueness test exists.
- **The in-place promise.** Every write whose array came out of a
  quantity-1 binder, an `LArray`'s included, is in a raised thread; a
  write that is not, because One-Shot found a conflict, is
  `unsupported (uniqueness)`, naming the write and the conflicting read,
  under `--demand-in-place`.
- **Readers that change with it.** `isArrayLoop` answers for every
  `linalg` structured op; `pure-array-loops` states its property of the
  generics.
- **Order.** The frontend's tensors, the simplify loop (idr-eval lowers a
  closed array call through idr-tensorize and idr-bufferize in its own
  pipeline), idr-defunctionalize, idr-tensorize, fusion, sharding and
  partition, tiling, idr-bufferize, idr-rc, idr-tail-loops, idr-stack,
  idr-lower, idr-vectorize.

### 5.5 Multicore

0004 owns the partitioning of tensor programs; 0005 owns the runtime they
run on and the parallel loops before them (`proposals/0005-shards.md`,
§8 and stage P5). Kept from the first version's §3.8:

- The grid is `shard.grid @cores(shape = ?)`, its size a runtime value,
  and `shard.process_linear_index` the running shard. A region of
  generics over a parallel dimension is outlined, its tensors annotated
  with `shard.shard`, and `sharding-propagation` and `shard-partition`
  make it SPMD through upstream's `ShardingInterface` models of `linalg`
  and `tensor` (read: the pinned
  `mlir/lib/Dialect/Linalg/Transforms/ShardingInterfaceImpl.cpp`).
- **Reductions by their laws** (§3.7). Parallel dimensions are sharded.
  A reduction dimension is sharded only when the reduction is unordered,
  its combine an `all_reduce` at the join; an ordered reduction stays on
  one shard, as it stays on one lane; `treeSum` shards whole blocks and
  combines them by its tree. A result is the same on any number of
  cores.
- The launch and the collectives are 0005's runtime: the result is
  allocated whole and each shard writes its slice as its destination; the
  arrays reach every shard by pointer for the join, which is sound
  because a partitioned body only loads and stores words in its own
  slice. That is the `counts-nothing` property, an `idr-expect` check
  today and the partitioning's precondition here: a region over counted
  elements touches counts, which only their shard may (0005, D1), and
  stays on one shard.
- **When.** 0005's P4 lowers a loop that counts nothing to a fork per
  shard and a join; SPMD replaces that lowering for tensor programs by
  0005's own rule, when it runs spectral-norm faster than P4 beyond the
  run-to-run spread. A partitioned region has a sequential version below
  a bound on its parallel extent, the extent at which the partitioned
  spectral-norm row loop breaks even, measured per target, rounded up to
  a power of two, and kept in the target's entry.

### 5.6 The meaning, tested

The library's plain definitions are the meaning of the array type and
its core; the compiler's representation is a faster lowering of that
meaning, the registry's rule for every hook. (decision D5) Every test of
the array library runs three ways against one set of expected files:
with compile-time evaluation and without it, as every program test runs
(read: `tests/README.md`), and with the registry's array hooks off, so
that the plain definitions run. "Faster, never different" is then a test.
No other implementation is asked.

## 6. Rules of AGENTS.md it keeps

- **Two targets, one design.** Nothing here is per target but what the
  target's entry holds: the L1 size tiling reads and the partition
  bound. A float reduction's order depends on the array's length only
  (§3.7), so expected files are one file for both targets.
- **Static linking, no C.** No new runtime is loaded: no OpenMP, no
  async runtime, no MPI, no `sparse_tensor` runtime library, no
  `library_call`.
- **Idris does types; MLIR does programs.** Shapes, the equations
  between them, bounds, laws and linearity are Idris's; whether an array
  is a tensor, where it is written in place, what fuses, how it tiles
  and how it is partitioned are MLIR's.
- **One thing, one representation.** A shape's components are computed
  by one function, the fork's, which conversion, unification and the
  frontend's instance keys share. A tensor's dimensions are its extents,
  with no shape vector beside them. The frontend writes upstream's
  `tensor` ops and no op of ours mirrors one. Ordered and unordered
  reductions are two ops, not one op and a flag.
- **Checked TT in.** The frontend reads shape indices from checked TT,
  where they are present as erased arguments, and computes skeletons from
  them; nothing comes from CExp.
- **No primitive in Idris.** The library is not a primitive: its plain
  definitions are the meaning of its types and the compiler's
  representation a faster lowering of it, the registry's rule (§5.6).
- **Idris 2, fully.** The fork accepts the programs stock Idris
  accepts, up to the class of ambiguities §4.10 names, which decision D7
  measures against Idris's own suite (`tests/upstream-idris`).
  `third_party/Idris2` is not touched: the change is the fork's.
- **No oracle.** Expected files are the specification; the hooks-off
  run of §5.6 runs this repository's own definitions against the same
  files, and asks no other implementation.
- **No `%foreign`.** Nothing here declares or calls a C symbol.
- **Reject, never miscompile.** A program the theory cannot decide is a
  type error naming the equation (§4.9); a write that breaks the in-place
  promise is `unsupported (uniqueness)`. A rank the program computes at
  run time compiles (§5.1); nothing is refused for its rank.
- **No pass drops what Idris proved.** Quantity 1 stays in the type
  across bufferization; proofs of equalities are definitional and leave
  no term to drop; a bound proved by a type is the absence of its guard;
  a law is the kind of a reduction op. No fact sits in a discardable
  attribute.
- **Erased does not mean constant.** An extent is a runtime value. The
  static part of a shape is its form, the skeleton, which the type fixes
  at each instance; a literal extent is static because its singleton has
  one value, which Idris proves.
- **A linear binder does not imply unique ownership.** An `LArray` is
  in place because the library creates it fresh and only `freeze` ends
  it; One-Shot proves each thread on SSA.
- **Indexed vectors do not imply contiguous storage.** `Vect` keeps its
  representation; an `Array` is contiguous because the library makes it
  so, not because of its index.
- **Upstream bugs upstream.** A thread kept a memref by a recursive
  boundary is the measured threshold for a patch to One-Shot under
  `upstream/` (§5.4).
- **Tests check behaviour.** Properties are `idr-expect` checks
  (`in-bounds`, `vectorized`, `pure-array-loops`, and the new
  `full-rank`, `fused`, `in-place-thread`, `unordered-reduction`), never
  op sequences.

## 7. Staged plan

Every stage passes `make check`, `make build`, `make test`,
`make test-idr` and `make test-mlir-tools` on both targets and runs
`bench/` on both. T1 and A1 start at once; T2 follows T1; A2 follows A1;
L follows T1; C1 follows A1 and L; C2 and C3 follow C1; C4 follows C3
and 0005's P4.

**T1. Shape arithmetic in the fork** (§4.1-4.5, §4.9).

- Change: recognition by case tree; the three clauses; canonical forms
  in conversion; unification modulo the theory; refutation in coverage;
  the diagnostics with counterexamples.
- Proof:
  - a new pool, `tests/elab/`, with one fixture per row of §1.5: the
    accepted rows stay accepted; F1, F2, F3, F4, W3, `Probe3.idr` and
    `ProbeAssoc.idr` are accepted; F5 is refused with §4.9's message;
    F7 and `Probe10.idr` test 4.4's conjecture, and neither outcome
    changes the design, since the explicit lemma works today
    (`Probe11.idr`);
  - generated pairs of polynomial expressions, 10,000 of them, in at
    most four atoms of degree at most three in each: conversion says
    "equal" exactly when the two agree at every point of `{0..4}⁴` (a
    polynomial of degree at most 3 in each variable that vanishes on a
    grid of 5 points per variable is zero, so the test is exact); and
    every generated expression with a positive constant evaluates to a
    successor (§4.2's conjecture);
  - D7's measurement.

**T2. `rewrite`, `with` and partial unification** (§4.6-4.7).

- Change: the five rewrite changes, shared with `with`; residual
  equations as erased hypotheses.
- Proof: fixtures in `tests/elab/`: F6's rewrite with its motive checked
  and `i` and `v` generalised; a rewrite whose motive needs a hypothesis
  generalised, accepted; a rewrite by a lemma whose sides convert,
  elaborated as the identity; a rewrite substituting a variable side;
  `halves` with both clauses; an ill-typed motive that no
  generalisation repairs, refused with the subterm named; prelude and
  base, which hold many rewrites, elaborate; `tests/upstream-idris`
  loses no passing test.

**A1. Loops as tensors** (the first version's stage 1, kept).

- Change: `idr-tensorize` for `idr.array.generate` and `fold`,
  `idr-bufferize`, `idr.array.alloc`, `idr.array.copy`, `isArrayLoop`
  over `linalg`; the memref half of `Lower/Loops.cppm` goes.
- Proof: the existing tests pass with their expected files unchanged;
  `vectorized` and `pure-array-loops` hold where they held;
  spectral-norm-linear within 3% of its record (0.596 s on arm64, best
  of 5) or faster, and the same on x86_64 against its record.

**A2. Threads of writes** (the first version's stage 2, kept).

- Change: raised threads; the grade over the tensor carrier; the
  in-place clause.
- Proof: `in-place-thread=@f` holds on a `Linear.Array` program; an
  unrestricted `mkArray` written and read again keeps its one-object
  output; a fixture under `--demand-in-place` expects the rejection;
  fannkuch-linear stays at parity with clang.

**L. The library** (§3).

- Change: `libs/mlir-array`, in plain Idris over base's primitives,
  built by this compiler into its prefix; no hook yet.
- Proof: a new topic, `tests/programs/typed-arrays/`, against committed
  expected files: the core's laws on examples; `cells` and `merge`
  round trips; `lift` at ranks 0 to 6 and at a rank read from input;
  every structural operation, at empty extents too; ordered reductions
  and scans; `filter` and `iota`; the views; `LArray` writes, `freeze`,
  `thaw`, `scatterWith`. They run through today's compiler, slowly, as
  plain Idris.

**C1. Types to tensors** (§5.1-5.3).

- Change: skeleton keys; `TensorT k`; `Ext` and `Index` as records; the
  `tensor` dialect in the generated contract; `idr.tensor.tabulate`,
  `fold` and ordered `reduce`; flattening, records as several tensors,
  counted elements; `idr-tensorize` reading affine reads as indexing
  maps, scalarising cell-valued tabulates, and turning folds in bodies
  into reduction dimensions.
- Proof:
  - L's tests pass three ways against the same expected files (§5.6);
  - `in-bounds=@f` on every typed-indexing fixture;
  - `full-rank=@f`, a new property: every structured op in @f iterates
    one dimension per component of its operands' canonical forms, none
    collapsed, where @f's skeletons are static; on fixtures of rank 3
    and 5;
  - `vectorized=@f` on a rank-3 tabulate of words;
  - a fixture at a rank read from input: `map` over it is one collapsed
    loop, vectorized; a body that uses coordinates delinearises them.
- Benchmarks, each new in `bench/` with its C at `-O2`:
  - `spectral-norm-typed`, the same algorithm on `Array`: within 3% of
    spectral-norm-linear or faster, on both targets;
  - `rank-mean`, the mean over the last axis of arrays of ranks 1 to 6
    with one element count: time per element within 10% across the
    ranks, which shows no rank costs anything;
  - `batched-matmul`, 64 matrices of 128 × 128 lifted: within 10% of 64
    calls of the unlifted product, which shows batching is free;
  - `matmul`, f64, 1024 × 1024: recorded, its threshold in C3.

**C2. Laws and scans** (§3.7).

- Change: `LawfulMonoid` and `CommutativeMonoid`; unordered reductions;
  the integer primitives' laws; `treeSum`; `idr.tensor.scan`;
  `scatterWith` in parallel for commutative monoids.
- Proof: `unordered-reduction=@f`, a new property (every reduction in @f
  is unordered, and one computes on more than one lane), on an integer
  sum; a float sum's expected output is one file on both targets;
  `treeSum`'s output equals its definition's with the hooks off;
  `histogram`, a scatter into a linear array, against its C.

**C3. Fusion and tiling** (the first version's stage 3, kept, at any
rank).

- Proof: `fused=@f` (no array allocated between two loops of @f) on
  `map f (map g xs)` and on a chain of rank-3 operations; tiling stays
  on only if a benchmark it changes gets faster on both targets and
  none gets slower beyond noise; `matmul` faster than its C, a naive
  loop at `-O2`, on both targets; `jacobi2d`, a stencil written with
  `windows`, against its C.

**C4. Multicore** (the first version's stage 5, kept). After 0005's P4.

- Proof: spectral-norm-typed's output identical on one shard and on all;
  faster than under P4's lowering beyond the run-to-run spread on both
  targets; `treeSum`'s output identical at any shard count; no benchmark
  slower beyond noise.

## 8. Rejected alternatives

- **Rank above 1 only when a literal** (the first version's §3.7). It
  was the ceiling the user removed: a rank that is not a literal after
  monomorphisation compiled the library as written. Skeleton keys give
  every static rank its tensor, and collapse gives a runtime rank one.
- **Shapes as `Vect r Nat`, a rank index beside the shape.** The rank is
  `length s`; a second index restates it, and the two can disagree.
- **Shapes as cons lists.** Their append recurses on the left, so a
  frame under a cell of known rank is stuck without the solver
  (`Probe5.idr`); the snoc list keeps that case definitional.
- **Shapes at quantity ω.** A runtime list of bigs per array, and a
  value its type does not tie to the index; the singleton is the same
  values, tied.
- **A separate index language** (Dependent ML, Remora, Qube). Idris's
  naturals and lists are the index language; a second one would mirror
  them. Dex's authors name it as Remora's "notable limitation" that "the
  language of array bounds is separate from the run-time values" (read:
  `paszke-2021-dex/main.tex`:2026-2031).
- **Coordinates as a type-level product.** `Index (s :< n) = (Index s,
  Fin n)` is stuck at an opaque shape, which the frontend cannot
  represent; the inductive family matches at any rank (measured:
  `Core2.idr`) and is a record at a static one (§5.2).
- **Index sets as the only array type**, `Table ix a` keyed by the index
  type. A dynamic rank would be a stuck type; rectangular arrays need
  the shape as an index. Kept as a library type for index sets that are
  not rectangular (§3.1).
- **Trailing-axis broadcasting** (NumPy, MLIR's `Broadcastable`, TOSA).
  Undefined behaviour when two dynamic sizes differ and neither is 1
  (§3.3), and a second agreement rule beside prefix agreement.
- **Maps and replications inferred at call sites** (AUTOMAP). It removes
  54% of the explicit maps in Futhark's benchmarks at 2.5 times the type
  checking time, by an integer linear program in the type checker (read:
  `sources/papers/schenck-2024-automap/paper.pdf`, §1). `lift` states
  the cell and finds the frame by unification, with no search.
- **Fills, surrogate cells and padded assembly.** Each guesses a shape
  the type gives.
- **Products kept out of types** (Remora). The semiring normal form
  decides products; `ravel` needs no box.
- **Syntactic size equality** (Futhark). It refuses every equation of
  §1.5.
- **A library tactic as the way to decide shapes** (Frex). Idris's
  evaluator makes it slow at the sizes array programs reach, and its
  reflection hands it normalised goals it misreads (§4.8).
- **An SMT solver in the elaborator** (Diatchki). No evidence, an
  external process, and a run that depends on the solver's version.
- **User rewrite rules** (Agda's `REWRITE`). They change definitional
  equality module by module, their confluence is checked only locally if
  at all, and commutativity cannot be one (§4.3).
- **Transports with proofs inserted by the elaborator.** A cast does not
  make `Vect (n + 1) a` match `(::)`, which needs the unifier (F4), and
  every proof term in TT is checked by Idris's evaluator, which Frex's
  authors name as the likely cause of their slowest checks (read:
  `allais-2025-frex/evaluation.tex`:46-53). The definitional theory is
  justified once.
- **The theory opt-in per module** (`%language`). Two conversion
  relations in one elaborator, and a type from one module compared in
  another by other rules.
- **Recognising `plus`, `mult` and append by name in the fork.** A name
  says nothing a case tree does not, and every copy of the definitions
  is found by its tree.
- **Inequalities decided in the elaborator** (Fourier-Motzkin, `omega`).
  The bounds programs need are `Fin`s by construction or runtime tests
  that `idr-in-bounds` proves; types carry equations (§4.8).
- **Nested arrays as a cell per row** (the first version). A nested
  array of uniform shape has one representation, flat (§5.2).
- **Tensors of words only** (the first version's first criterion).
  Bufferization's copy is a hook, and ours counts (§5.2).
- **A runtime uniqueness test before a write** (Lean's way). README.md
  promises in place "with no runtime test" for quantity 1.
- **Our own fusion and in-place analysis on memrefs.** It would
  duplicate upstream's on a representation upstream's transforms do not
  take.
- **Every array a tensor.** An array the world orders is one object whose
  writes a later read sees; a tensor has no identity to see.
- **Bufferizing after idr-rc, with `excl` as One-Shot's analysis
  state.** A grade speaks of cells and a tensor has none until it is
  bufferized.
- **Ownership-based buffer deallocation.** Counting frees cells.
- **MPI for collectives** (`ShardToMPI`). Shards are threads of one
  process, and a collective over one buffer is a slice.
- **A scheduling language for users** (Halide, TVM, ELEVATE). The
  compiler decides schedules from the op and the target entry; a user
  writes Idris.
- **Float reductions reassociated by lanes or shards.** Their results
  would differ by target and by core count; `treeSum` fixes an order
  that does not.
- **`Vect` unboxed to a tuple at a literal length.** `Vect` is a list,
  shared by its tails, and its length keys no instance (AGENTS.md).
- **Arrays of functions as a feature of their own** (Remora's
  application of arrays of functions). Defunctionalisation already makes
  a closure a sum, so an array of functions is an array of sums.

## 9. Decisions

### D1. Shapes, extents and coordinates

A shape is `SnocList Nat` at quantity 0; extents are the singleton
`Ext s` at quantity ω; a coordinate is `Index s`, an inductive family of
`Fin`s. Reason: frames are found by stock unification under cells of
known rank (measured: `Core.idr`); the singleton gives a lifted
operation its result's extents with no cell (Remora's erasure keeps
exactly these binders, read: `type_erasure.tex`:68-123); a literal
extent is static because its singleton has one value; `Fin`s make typed
access total; the inductive family matches at every rank (measured:
`Core2.idr`).

### D2. Which arrays are tensors

Typed arrays from birth, and rank-1 `Linear.Array` threads where the raise
finds them pure and linear in effect (§5.4); arrays the world orders stay
memrefs. The first version's condition that elements be words is
dropped. Reason: the user's ruling (§2); an element type is a
representation question §5.2 answers for every type.

### D3. Instances keyed by skeleton; collapse where it is not static

Reason: tiling, fusion and vectorization see a generic's full rank only
if the instance has it; a polymorphic function meets few ranks in one
program; a runtime rank still compiles (Remora's products, read:
Dissertation §11.2). Measurement: the compile times `bench/` reports;
while no program compiles more than 10% slower than with every array
shape parameter collapsed, the rule stands; past that, a definition's
skeletons beyond its fourth in one program are collapsed.

### D4. A small recognised core

Recognised operations are those that cannot be written as a tabulate
whose body reads its arguments at affine functions of the coordinates:
`tabulate`, `index`, `extents`, the reshaping views, `append`, the
reductions, scans and folds, and the linear operations. Everything else
is a library definition, whose structure the raise recovers as indexing
maps (§5.3). Reason: each recognised operation is a lowering that must
mean what its definition means and a branch in the frontend; an indexing
map is the structure itself.

### D5. The meaning, tested three ways

Every typed-array test runs with and without compile-time evaluation
and with the array hooks off, against one set of expected files (§5.6).
Reason: the registry's rule, "faster, never different", becomes a
checked property, with no implementation but this repository's.

### D6. Upstream's `tensor` ops from the frontend

The generated contract gains the `tensor` dialect; ops of ours exist
only for regions holding Idris code (`idr.tensor.tabulate`, `fold`,
`reduce`, `reduce_unordered`, `scan`). Reason: one representation; the
regions must meet
defunctionalisation and the simplify loop before they are `linalg`
bodies, as `idr.array.generate` does today.

### D7. Shape arithmetic is definitional in the fork

The fork recognises addition, multiplication, append and homomorphisms
by their case trees; adds three evaluation clauses and the appends'
units; compares stuck spines by canonical forms within a budget of 4096
monomials; unifies modulo the theory where the solution is unique; and
refutes in coverage. Reason: §1.5's refusals are equations on variables,
which Idris programs have and Gibbons's concrete sizes do not; each step
meets a published criterion (Cockx 2014's confluence, Allais et al.'s
ν-rule conditions, Cockx's strong unification rules); the result is a
superset of Idris 2. Measurement, for landing T1:

- prelude, base, `mlir-linear`, the fork and every program of `tests/`
  elaborate with no new error, and every test passes with its expected
  files unchanged;
- `tests/upstream-idris` loses no test that passed before;
- the fork's self-build elaborates within 5% of its time before, best
  of 3; if not, the comparison is made cheaper before it lands;
- the budget stays at least 16 times the largest canonical form any
  program of `tests/` or `bench/` builds, which the fork's statistics
  report.

### D8. `rewrite` and `with`

Identity when the sides convert; keyed abstraction on the goal as
written, then the normal form; the motive checked; dependents
generalised, or a variable side substituted by a match on `Refl`;
occurrences that cannot be generalised left out, one at a time, until
the motive checks.
Reason: Idris accepts an ill-typed motive today (measured: F6); every
other system on record checks it (read: Lean `Rewrite.lean`:57-73;
Agda `with-abstraction.lagda.rst`:935-936; McBride and McKinna's
Fig. 12).

### D9. Partial unification

A stuck index's residual equations are erased hypotheses of the clause.
Reason: a stuck equation is otherwise a refused clause, and the
equation, at quantity 0, costs nothing (read: Cockx's thesis §5.1,
Example 5.1; McBride's constraint by equation, `elim.ps` §2).

### D10. No inequality in a type

Structural types state equations; bounds are `Fin`s or runtime tests;
views and checked casts decide sizes at run time. Reason: nonlinear
inequalities over the naturals are undecidable, the linear ones a
program checks at run time are what `idr-in-bounds` already decides,
and Futhark's suite needed 66 explicit coercions in 12,000 lines (read:
`henriksen-2021-size-types/paper.pdf`, §6).

### D11. Laws decide reductions

A `CommutativeMonoid` instance, or a combiner region that is one integer
primitive (by the runtime's meaning), selects the unordered reduction; a
float sum keeps
program order; `treeSum` fixes an order that depends on the length
only. Reason: a reduction's order is its meaning unless a law says
otherwise (Iverson's partitioning identities, read: `tot1.htm` §4.2),
and a result must not depend on the target or the core count.

### D12. Every element type

Nested uniform arrays are flattened; records of words are several
tensors; any other value is a counted element; an existential element
is boxed. Reason: §5.2; Futhark, Dex and SaC make the first two moves
(read: §5.2's sources), and counting through bufferization's copy hook
keeps every other element on the tensor path.

### D13. Closed arrays are constants

A closed computation of an array of words is evaluated at compile time
into a dense tensor constant, within idr-eval's budget and its 1 MiB
limit on results. Reason: AGENTS.md's compile-time evaluation applies to
every closed call of pure code; a dense constant is what `linalg`
consumers fold.

## 10. Upstream used

| Mechanism | For |
| --- | --- |
| `tensor` ops (`extract`, `extract_slice`, `insert`, `dim`, `collapse_shape`, `expand_shape`, `concat`, `empty`), written by the frontend | the core's lowering (§5.3) |
| `linalg.generic`, `linalg.reduce`, multi-result generics, `DestinationStyleOpInterface` | the raise (§5.3, §5.4) |
| `affine.delinearize_index` | coordinates of an opaque component (§5.3) |
| `scf.forall`, `tensor.parallel_insert_slice` | lifting a cell function that is not structured (§5.3) |
| `TensorLikeType`, `BufferLikeType`, `BufferizableOpInterface` | the grade across bufferization (§5.4) |
| `runOneShotModuleBufferize`, `bufferize-function-boundaries`, `allocationFn`, `memCpyFn` | bufferization (§5.4) |
| `linalg-fuse-elementwise-ops`, `transform.structured.fuse`, DLTI `L1_cache_size_in_bytes` | fusion and tiling (§5.4) |
| `shard.grid`, `shard.process_linear_index`, `shard.shard`, `sharding-propagation`, `shard-partition`, `ShardingInterface` models | multicore (§5.5) |
| `outlineSingleBlockRegion` | the partitioned region (§5.5) |
