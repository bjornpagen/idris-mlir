# 0004: a typed array language, lowered to tensors

**How this proposal is laid out.** This README is the proposal: the language
a programmer writes, how it lowers, the staged plan and the decisions. Two
companion files go deeper on one side each, and were written independently
of it:
- `compiler.md`: the lowering in depth (scheduling, bufferization meeting
  the grades, counting after bufferization, sparse arrays, GPU,
  differentiation, the performance suite and the Futhark baseline);
- `types.md`: the type theory in depth (shapes, extents and coordinates;
  shape arithmetic in the fork's elaborator; unification modulo the
  theory; `rewrite` and `with`).

Where a companion and this README disagree, this README decides. The first
step of stage 0 is to reconcile them: each companion decision either joins
this README's Decisions or is struck. It replaces the earlier
`0004-tensors.md`, and the sources it cites are under `sources/` (topic
"Array languages and typed array programming"), with reading notes in
`sources/notes/array-languages/`.

**Status:** proposed, 2026-10-09; replaces the earlier 0004 (dense array
programs as tensors). Two rulings of the user's stand behind it: pure
array programs are tensors ("tensors should definitely be tensors, pure
array programs is one of the heavy hitting features of mlir and we cannot
lose this"), and rank has no ceiling and is lowered to MLIR, not left to
the library when it is not a literal. Every other decision is taken here,
in its section or in Decisions, with its reason or the measurement rule
and threshold that settles it. Claims are marked: read (the path given),
measured, recalled, conjecture, decision. Paths under `sources/` are the
library's, including the papers and snapshots this proposal's research
added (their catalogue rows go to `sources/INDEX.md` with it).

The language is a typed APL hosted in Idris 2. An array's shape is its
type; a function is written on cells of a fixed shape and lifted over any
frame; the vocabulary is APL's, J's and BQN's, curated and typed; index
sets are types, as in Dex. The compiler reads the rank from the form of
the shape, which the checked type states, gives every array a ranked
tensor of that rank, and lowers the vocabulary to `tensor` and `linalg`,
where upstream fuses, tiles, vectorizes and bufferizes it.

## What it changes

Each move names the data that changes and the branches it deletes.

- **An array's shape is its type, and its rank is the form of that type.**
  Data: `Array : (0 s : Shape) -> Type -> Type` over `Shape = SnocList
  Nat`, and a tensor with one dimension per component of the shape's
  form (§3.1). Deleted: the ceiling of rank 1 on every array the program
  does not order (today each is a memref of rank 0 or 1), the earlier
  0004's "rank above 1 only when the rank is a literal" and its fallback
  for any other rank.
- **Indices are typed.** Data: `Index s`, one `Fin` per axis (§2.2).
  Deleted: the guard of every typed access, and the entry test and the
  second copy of each loop that `Lower/Loops.cppm` builds today to read
  outside arrays as inputs (§3.5): linalg's precondition that dynamic
  dimensions agree is what the shape types prove.
- **The vocabulary is library code over a generating set.** Data: about a
  dozen primitives the compiler knows by name (§2.5); every other
  function, `map`, `transpose`, `outer`, `contract` and the rest, is plain
  Idris over them. Deleted: any case in the compiler per vocabulary
  function, so a function added to the vocabulary adds none; today's two
  hooks (`prim__generate`, `prim__foldl`) become the generating set's.
- **One loop representation.** Data: `idr.array.tabulate`,
  `idr.array.fold` and `idr.array.scan` on tensors, of any rank, with no
  world (§3.4). Deleted: `idr.array.generate` and `idr.array.fold` on
  memrefs, the memref half of `Lower/Loops.cppm`, and the words-only
  condition on loops.
- **An array of records, sums or arrays is a structure of tensors.** Data:
  one tensor per slot of the element, and a nested array of one cell shape
  flat (§3.1). Deleted: the cell per element for those element types.
- **A record that holds an array holds a tensor until bufferization.**
  Data: records and sums of tensors replaced by their slots before
  One-Shot runs (§3.8). Deleted: any need for bufferization to see
  through our records.
- **`Linear.Array`'s frozen array is the dense array of rank 1.** Deleted:
  `IArray` and its loops (`ifoldl`, `imap`, `map`, `zipWith`, `sum`).
- **Associativity is read off a combiner's ops.** Deleted: any attribute,
  flag or proof plumbing that would license reassociation (§3.6).
- **The interactive loop runs the compiler's own code.** Deleted: any
  second evaluator of arrays (§2.13).

## 1. What exists

(read: `foreign/idr/include/idr/IdrOps.td`, "Arrays")

- **Arrays are memrefs from birth, of rank 0 or 1.** `Idr_ArrayValue` is
  "an array of rank 0 or 1 at any grade" (IdrOps.td:1579-1584); the type
  is a builtin `memref<?xE>` or `memref<E>`, no array type of our own
  (IdrOps.td:1791-1803). The frontend's `Ty` says the same: `ArrayT Rank
  Ty` with `Rank = Rank0 | Rank1` (`compiler/src/IdrisMLIR/Types.idr`).
  `idr.array.new`, `get` and `set` take one size or index per dimension
  and the world: every array op is IO.
- **Two loop ops, rank 1, words only.** `idr.array.generate` and
  `idr.array.fold` (IdrOps.td:1889-1959) run their body once per index in
  index order. The frontend emits them for `Linear.Array`'s
  `prim__generate` and `prim__foldl`, found by name in the registry
  (`compiler/src/IdrisMLIR/Registry/Recognized.idr`, `indexSpaces`),
  only when every element and accumulator is a machine word
  (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`, `arrayLoop`).
- **Lowering is to `linalg.generic` on memrefs**
  (`foreign/idr/lib/Lower/Loops.cppm`): a generate is a parallel generic
  from element 1 on, a fold a reduction into a frame slot, a generate of a
  fold one generic of two dimensions. A generate that reads outside arrays
  at its index gets a test on entry that every one is long enough, and a
  second copy of the generic that reads them as inputs.
- **`idr-vectorize`, `idr-narrow-lanes`, `idr-in-bounds`** (read:
  `foreign/idr/include/idr/Passes.td`): lanes along parallel dimensions,
  one lane along a reduction so a float sums in program order, 32-bit
  versions under a bound, guards erased by Presburger proofs.
- **The frontend instantiates by form.** A runtime argument whose value
  the rest of a type reduces on keys the instance by its skeleton, "the
  constructors it is built with as written, everything else erased"
  (read: `compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`,
  `classify`, `neededShape`; `Closed.idr`, `skeleton`); a recursion that
  deepens a skeleton is refused as `unsupported (polymorphism)`
  (`growing`), and a definition gets at most 4096 instances
  (`instanceBudget`). An erased argument keys nothing today.
- **The contract's dialects** are idr, builtin, arith, func, math, memref
  and ub, each with Idris builders generated from its ODS (read:
  `tools/dialects.sh`).
- **Compile-time evaluation** runs closed pure calls in a child process
  with ORC's LLJIT against the runtime linked into the compiler, and keeps
  results up to 1 MiB as constants (read: `Passes.td`, `idr-eval`;
  `foreign/idr/lib/Eval/Child.cppm`).
- **User code may not use `believe_me`**: it is `unsupported (escape
  hatch)` (read: `tests/reject/escape-hatch-believe-me`).

Measured (`bench/runs/2026-10-07-f5a4dff9-darwin-arm64/results.md`, Apple
M2 Max, best of 5):

| benchmark | this compiler | clang -O2 | clang / this |
|---|---:|---:|---:|
| spectral-norm-linear 5500 | 0.596 s | 1.108 s | 1.86x |
| spectral-norm (lists) 5500 | 1.515 s | 1.126 s | 0.74x |
| fannkuch-linear 12 | 24.155 s | 25.711 s | 1.06x |
| nbody 50000000 | 1.655 s | 1.924 s | 1.16x |
| mandelbrot 2000 | 0.229 s | 0.231 s | 1.01x |

Missing: rank above 1, array types of anything but words, fusion,
tiling for the cache, in-place decisions over a whole function,
parallelism, and any notation for array programs beyond rank-1 loops.

## 2. The language

`libs/mlir-array`, an in-house package in plain Idris over base's
primitives and `libs/mlir-linear`, as `mlir-linear` is over base's
(**decision**, D1). Read as written, every definition is the meaning;
the compiler knows a few by name and lowers them faster with the same
meaning (§2.5, §3.3). Its modules: `Array` (the types, the generating set,
the vocabulary, the interfaces), `Array.IndexSet` (§2.7), `Array.Shape`
(shape lemmas, views, the solver of §2.9), `Array.Ragged` (§2.8),
`Array.Display` (§2.13).

The examples of this section type-check (measured: the pinned Idris 2,
0.8.0-1c630e67c, against a mock of this library with the same types;
stage 1 commits them as tests).

### 2.1 Arrays, shapes, frames and cells

```idris
Shape : Type
Shape = SnocList Nat              -- the axes' lengths, outermost first

export
data Array : (0 s : Shape) -> Type -> Type   -- abstract; row-major

Scalar : Type -> Type             -- Array [<]
Vector : Nat -> Type -> Type      -- Vector n = Array [<n]
Matrix : Nat -> Nat -> Type -> Type
```

An array is a shape and an element at every index of it, laid out
row-major: APL's model (read:
`sources/papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm`, II.A;
`sources/docs/bqn/doc/array.md`, "Cells"). Its rank is the length of its
shape; a rank-0 array is a scalar. Nothing in the model bounds the rank,
and nothing in this design does.

**Frames and cells.** A function from arrays of shape `c` to arrays of
shape `d`, applied to an array of shape `f ++ c`, applies to each *cell*
of shape `c`; the leading axes `f` are the *frame*, and the results
assemble into an array of shape `f ++ d` (read:
`sources/papers/bernecky-1983-satn45-rank-operator/satn45a.htm`, "If a
function has rank r, then the subarrays along the last r axes of its
arguments are the cells"; `sources/docs/bqn/doc/rank.md`, "Frame and
Cells").

**decision** Shapes are snoc lists, outer axis first (D2). Base's
`SnocList.(++)` recurses on its right argument (read:
`third_party/Idris2/libs/prelude/Prelude/Types.idr:424-427`), so `f ++
[<n]` reduces to `f :< n`, and unification finds a frame from the
argument alone: a function of type `Array (f :< n) a -> Array f b`
applied to `Array [<3, 4, 5] Int` solves `f = [<3, 4]` (measured: the
research probes `Probe4`, which passes, and `Probe5`, its cons-list twin,
which fails with "Can't solve constraint between: [3, 4, 5] and ?s ++
[?n]"). The cell is what a function's type states; the frame is what
unification finds: Remora's division, "frames are computed, cells are
declared" (read: `sources/papers/slepak-2018-constraint/paper.pdf`, §3),
done by Idris's own unifier.

**decision** A primitive acts on its cells: one whose type takes `Array
(f :< n) a` acts on the trailing axis, and the frame `f` is iterated (D3).
That is the rank operator's own definition, so "a primitive acts on its
cells" and "the rank operator applies to cells" are one rule. The leading
axis is reached through `transpose`, which costs nothing (§3.5).

### 2.2 Indices, extents and the pointful style

```idris
namespace Extents                 -- a shape at runtime
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

`Extents s` is a singleton: its runtime sizes are its index's, so a
value of it is the shape at runtime and the type says so. `Index s` holds
a `Fin` per axis, so every index is within its array by type. Both use the
snoc-list syntax, in namespaces of their own (two `Lin` in one namespace
collide; measured), so one spelling serves the type, the extents and the
pattern:

```idris
m : Matrix 3 4 Double
m = tabulate [<3, 4] (\[<i, j] => cast (finToNat i * 4 + finToNat j))
```

`[<3, 4]` is the shape in the type and the extents in the term; `\[<i,
j] =>` binds the index. A match on extents binds the sizes at runtime:
`case shape x of e :< n => ...` gives `n`, equal to the index by type
(the library's `reverse` is written so, to call `Data.Fin.complement`).

**Indexing is total.** `(!!)` takes an `Index s`, so it has no runtime
check: the README's promise "no bounds check" (read: `README.md`), kept
by type. An index computed from integers goes through `(!?) : Array s a
-> SnocList Integer -> Maybe a`, `x !? [<2, 7]`, which is `Nothing`
outside the array: the test is the program's, a comparison, not a crash
(measured: the literal resolves to the integers). `!` alone is Idris's
bang notation and reserved (read:
`third_party/Idris2/src/Parser/Lexer/Source.idr:244-247`), and the
Prelude's `*` is `infixl 9` (read:
`third_party/Idris2/libs/prelude/Prelude/Ops.idr:6`), so indexing
is `!!` at 10: `a !! [<i, p] * b !! [<p, j]` reads as two reads
multiplied (measured: at 9 it parsed as `((a !! _) * b) !! _`).

**Pointful and point-free are one program.** Dex's matrix product, `for
i j. sum (for k. x.i.k * y.k.j)` (read:
`sources/papers/paszke-2021-dex/main.tex:320-343`), is

```idris
matmul : {m, k, n : Nat} -> Matrix m k Double -> Matrix k n Double -> Matrix m n Double
matmul a b = tabulate [<m, n] (\[<i, j] => sum (tabulate [<k] (\[<p] => a !! [<i, p] * b !! [<p, j])))
```

and its point-free twin is `contract (+) 0 (*) a (transpose b)` (§2.5).
Both lower to one structured op whose reads are indexing maps (§3.5):
a pointful body's affine reads are a point-free op's maps, which is where
the two styles meet (read: `sources/docs/mlir/docs/Dialects/Linalg/_index.md`,
Properties 2 and 4). `{m, k, n : Nat}` binds the sizes at quantity many,
so `[<m, n]` is built from them; a function whose sizes are erased reads
them off its arguments with `shape`.

### 2.3 Arithmetic and the interfaces

**decision** Arrays are `Num`, `Neg`, `Fractional` and `Applicative` at
one shape, with the extents found by search (D5):

```idris
%hint arrayNum : Num a => {auto ext : Extents s} -> Num (Array s a)
```

`(+)` and `(*)` are elementwise at one shape, and a literal is the
constant array of the shape the context expects, whose extents search
builds from the constructors when the shape is literal, or takes from
an `Extents s` in scope. So `2 * m + 1` is a matrix, `printLn (1 + 2)`
still means what it meant, and a mismatch of shapes is a type error
(measured, all three). In code polymorphic in its shape, a literal needs
the shape: `let ext = shape x in x * 2`, or `map (* 2) x`, which needs
none; without either, search reports "Can't find an implementation for
Num (Array s Int)" (measured).

The rejected alternative is overloading `(+)` across shapes under the
Prelude's names, with array literals: it makes `printLn (1 + 2)` an
"Ambiguous elaboration" in every module that imports the library
(measured: both with an array `fromInteger` beside the operators, and
with a `Num` instance for scalars only). Different shapes meet through
prefix agreement, named (§2.4).

The rest of the interfaces are base's: `Functor` (`map`, `<$>`: APL's
each), `Foldable` (`sum`, `foldr`, `all`, `elem`: every element in
row-major order, APL's `+/,`), `Traversable`, `Zippable` (`zipWith`,
`unzip`; read: `third_party/Idris2/libs/base/Data/Zippable.idr`), and
`Show`. The Prelude's `sum` is `foldMap` over the additive monoid, and
`foldMap` is a method of `Foldable` (read:
`third_party/Idris2/libs/prelude/Prelude/Interfaces.idr:273-315, 408-409`),
so **decision** the array's instance defines `foldMap` as the left fold
in index order: `sum x` adds as `reduce` does (§2.6), where the method's
default, a right fold, would add a float array backwards.

**Idiom brackets** apply any function elementwise:
`[| min m 10 |]` (measured); they desugar to `pure` and `<*>`, and a
namespace may supply its own (read: `third_party/Idris2/src/Idris/Desugar.idr:269-282`).
`Eq` compares whole arrays; elementwise comparison is `[| x == y |]`.

**decision** Names, not glyphs (D9). Idris accepts any character above
U+00A0 in an identifier (read:
`third_party/Idris2/src/Parser/Lexer/Common.idr:73-81`), so `⌽ = reverse`
is legal Idris (measured), and a user may write it. The library ships no
glyph module: operators are infix and binary in Idris, so a glyph gives
APL's look without its grammar (`+⌿` would lex as one operator token),
and two spellings of every primitive is two names for one thing in every
message and document. BQN's own author lists "glyphs are hard to type"
among its problems (read: `sources/docs/bqn/commentary/problems.md`).

**The operators**, all the library defines:

| operator | meaning | fixity |
|---|---|---|
| `x !! i` | the element at a typed index | `infixl 10` |
| `x !? [<i, j]` | the element at integers, `Maybe` | `infixl 10` |
| `t !@ ix` | the element of a table at an index value (§2.7) | `infixl 10` |
| `x ++ y` | catenation along the trailing axis | the Prelude's `infixr 7` |
| `+ - * /`, `negate` | `Num`, `Neg`, `Fractional` at one shape | the Prelude's |

Everything else is a name. Fixity in Idris belongs to the operator's
name, so `++` keeps the Prelude's, and the reads bind tighter than
arithmetic (`a !! i * b !! j`).

**Literals and display.** `vector : Vect n a -> Vector n a` and `matrix :
Vect m (Vect n a) -> Matrix m n a` take Idris's list literals, the
lengths giving the shape; `nested : Nested s a -> Array s a` does any
rank. **decision** `show` prints that literal syntax, so a shown array
reads back; `display` (`Array.Display`) prints the aligned grid, a blank
line between planes, which the interactive loop shows. The library does
not re-export `Data.Vect`: list literals in a comprehension became
ambiguous between `List` and `Vect` when it did (measured).

### 2.4 The rank operator and agreement

```idris
namespace Cell                    -- a cell's form, sizes left to unification
  data Cell : Shape -> Type where
    Lin  : Cell [<]
    (:<) : Cell s -> (0 n : Nat) -> Cell (s :< n)

nest  : Cell c -> Array (f ++ c) a -> Array f (Array c a)     -- BQN <⎉k
merge : Extents c -> Array f (Array c a) -> Array (f ++ c) a  -- BQN >

over  : Cell c -> {auto calc : Extents c -> Extents d}
     -> (Array c a -> Array d b) -> Array (f ++ c) a -> Array (f ++ d) b
over c g x = merge (calc (cellExtents c x)) (map g (nest c x))   -- the trailing c of shape x
```

`over [<_] f x` applies `f` to every rank-1 cell of `x`, the frame
inferred (measured: `over [<_] reverse`, `over [<_] softmax1` at any
rank). The cell is stated as a pattern because a function polymorphic in
its argument's shape leaves the split of `f ++ c` ambiguous (measured:
the research probe `Probe3`), Remora's rule that inference only
instantiates (read: `sources/papers/slepak-2020-dissertation/Dissertation.pdf`,
ch. 6). A cell pattern replaces APL's signed rank and BQN's "negative
zero" problem (read: `sources/docs/bqn/commentary/problems.md`, "Rank/Depth
negative zero"): a typed operator takes the cell's form, not a number.

**The definition is BQN's identity.** `F⎉k x ←→ >F¨<⎉k x` (read:
`sources/docs/bqn/doc/rank.md`): rank is merge after each after nest. In
a typed language each piece has a type, and only `merge` needs to know
the result cell's extents, because an empty frame has no cell to read
them from.

**decision** The empty frame is settled by a shape calculator, not by
running the function (D6). APL takes the empty vector as the result
cell's shape by convention (read: `satn45a.htm`, "By convention, if the
frame is empty"); J applies the function "to a cell of fills" (read:
`sources/docs/j/help/dictionary/dictb.htm`); BQN may try a cell of fills
and otherwise assumes `⟨⟩`, and lists "empty arrays lose type
information" as its first problem (read: `sources/docs/bqn/doc/fill.md`;
`commentary/problems.md`). Hui's uniform functions are the answer: a
function is uniform when "there is a shape calculator vs ... such that $v
y ↔ vs $y" (read: `sources/papers/hui-1995-rank-uniformity/rank1.htm`,
§2). Here the calculator is a value, `Extents c -> Extents d`, and search
finds it in the common cases: the identity when `d = c`, a literal axis
added (`Extents [<n] -> Extents [<n, 2]`), a literal cell (measured, all
three). Where search cannot build it (cells that take sizes from two
arguments, as a matrix product's do), the program either passes it or
keeps the frame of results nested:

```idris
batchedAny : Array (f :< m :< k) Double -> Array (f :< k :< n) Double
          -> Array f (Matrix m n Double)
batchedAny a b = zipWith matmul' (nest [<_, _] a) (nest [<_, _] b)
```

A nested array of one cell shape is the flat array in memory (§3.1), so
keeping it nested costs nothing, and its cells' extents are needed only
by a `merge`. A search that runs before the argument fixes a size can bind
it wrongly, and the result is a type error, not a miscompile (measured:
a cell function that ignores its argument; annotate the argument).

**Agreement.** Different shapes meet by prefix agreement: one shape must
be a prefix of the other, and the shorter array's elements are reused
along the longer's trailing axes (read: `dictb.htm`, "one frame must be a
prefix of the other"; `sources/docs/bqn/doc/leading.md`, "Leading axis
agreement"). The principal frame is one of the two, read off the
evidence, never computed from lengths (read:
`sources/papers/slepak-2019-semantics/formalism.tex`, the prefix
lattice; measured: the research probe `Probe9` infers it, `Probe8`, which
compares lengths, gets stuck). The evidence is a runtime value, because
`agree` takes the result's extents from the longer argument and must
know which it is; its form is the shapes' forms, so in an instance of
known form it is a constant (§3.2).

```idris
agree : {auto ok : Agree s t} -> (a -> b -> c) -> Array s a -> Array t b -> Array (principal ok) c
over2 : Cell c1 -> Cell c2 -> {auto ok : Agree f1 f2} -> {auto calc : ...}
     -> (Array c1 a -> Array c2 b -> Array d e)
     -> Array (f1 ++ c1) a -> Array (f2 ++ c2) b -> Array (principal ok ++ d) e
```

`agree (-) m rowMeans` subtracts each row's mean along its row; `over2
[<_, _] [<_, _] matmul'` multiplies a stack of matrices by a stack (or by
one matrix: an empty frame agrees with every frame, which is APL's scalar
extension); a matrix-vector product is `over2 [<_] [<_] dot m v`, frames
`[<3]` and `[<]` (measured, all). **decision** No trailing (NumPy)
broadcasting and no size-1 stretching (D3): it is a second agreement rule
whose meaning depends on runtime sizes (read:
`sources/docs/mlir/docs/Traits/Broadcastable.md`), where prefix agreement
never consults a size.

### 2.5 The vocabulary

`f`, `g` are frames, `s`, `t` shapes, `n`, `m`, `k` sizes. The first table
is the generating set, the only functions the compiler knows by name
(D7); the second is library code over it, whose lowering is what its
definition becomes (§3).
The glyph columns give each primitive's form on the trailing axis, where
J's and BQN's own act on the leading one and reach the last through rank.

| Idris | type | APL · J · BQN | lowers to |
|---|---|---|---|
| `shape` | `Array s a -> Extents s` | `⍴` · `$` · `≢` | `tensor.dim` per component |
| `tabulate` | `Extents s -> (Index s -> a) -> Array s a` | `f¨⍳` · `f"0 i.` · `𝔽¨↕` | `idr.array.tabulate` |
| `(!!)` | `Array s a -> Index s -> a` | `⌷` · `{` · `⊑` | `tensor.extract`; an input in a loop (§3.5) |
| `foldLast` | `(b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b` | `f/` · `f/"1` · `𝔽´˘` | `idr.array.fold` |
| `scanLast` | `(b -> a -> b) -> Array f b -> Array (f :< n) a -> Array (f :< n) b` | `f\` · `f/\"1` · `` 𝔽`˘ `` | `idr.array.scan` |
| `nest`, `merge` | §2.4 | `⊂⍤k`, `↑` · `<"k`, `>` · `<⎉k`, `>` | nothing (§3.1) |
| `reshape` | `Extents t -> {auto 0 _ : count s = count t} -> Array s a -> Array t a` | `⍴` · `$` · `⥊` | `tensor.collapse_shape`, `expand_shape` |
| `take`, `drop` | `(k : Nat) -> {auto 0 _ : LTE k n} -> Array (f :< n) a -> Array (f :< k) a` | `↑⍤1` `↓⍤1` · `{."1` `}."1` · `↑˘` `↓˘` | `tensor.extract_slice` |
| `(++)` | `Array (f :< n) a -> Array (f :< m) a -> Array (f :< n + m) a` | `,` · `,"1` · `∾˘` | `tensor.concat` |
| `update` | `Array s a -> Index s -> a -> Array s a` | `@` · `}` · `⌾(i⊸⊑)` | `tensor.insert` |
| `under` | `View s t -> (Array t a -> Array t a) -> Array s a -> Array s a` | — · `&.` · `⌾` | `extract_slice`, `insert_slice` |
| `accumulate` | `(b -> a -> b) -> Array t b -> Array s (Index t) -> Array s a -> Array t b` | `⌸` · `/.` · `⊔`; Dex's `+=` | `idr.array.fold` into an array |
| `freeze`, `thaw` | to and from `Linear.Array` | | `bufferization.to_tensor`, `to_buffer` |

| Idris | type | APL · J · BQN |
|---|---|---|
| `map`, `zipWith`, `[\| f x y \|]` | `Functor`, `Zippable`, `Applicative` at one shape | `¨` · `"0` · `¨`; scalar functions |
| `agree`, `over`, `over2` | §2.4 | scalar extension, `⍤` · `"` · `⎉` |
| `reduce` | `(a -> a -> a) -> a -> Array (f :< n) a -> Array f a` | `/` · `/"1` · `´˘` |
| `scan` | `(a -> a -> a) -> a -> Array (f :< n) a -> Array (f :< n) a` | `\` · `/\"1` · `` `˘ `` |
| `outer` | `(a -> b -> c) -> Array s a -> Array t b -> Array (s ++ t) c` | `∘.f` · `f/` dyad · `⌜` |
| `contract` | `(c -> c -> c) -> c -> (a -> b -> c) -> Array (f :< k) a -> Array (g :< k) b -> Array (f ++ g) c` | `f.g` · `f/ .g` · `𝔽˝∘𝔾⎉1‿∞` |
| `transpose`, `permute` | `Array (f :< n :< m) a -> Array (f :< m :< n) a`; any permutation of a known form | `⍉⍤2` · `\|:"2` · `⍉⎉2` |
| `reverse`, `rotate`, `shift` | trailing axis; `shift` fills | `⌽` · `\|."1` · `⌽˘`; `»˘` `«˘` |
| `windows` | `(k : Nat) -> {auto 0 _ : LTE k n} -> Array (f :< n) a -> Array (f :< S (minus n k) :< k) a` | `⌺` · `;._3` · `↕` dyad |
| `iota`, `fill` | `Extents s -> Array s (Index s)`; `Extents s -> a -> Array s a` | `⍳` · `i.` · `↕`; `⍴` |
| `ravel` | `Array s a -> Vector (count s) a` | `,` · `,` · `⥊` |
| `filter` | `(a -> Bool) -> Vector n a -> Exists (\m => Vector m a)` | `/` · `#` · `/` |
| `grade`, `sort` | over `Ord`, a merge sort on `Linear.Array` | `⍋` · `/:` · `⍋` |
| `select` | `Array s (Index t) -> Array t a -> Array s a` | `⌷` · `{` · `⊏` |
| `iterate` | `(k : Nat) -> (a -> a) -> a -> a` | `⍣` · `^:` · `⍟` |

What is left out, and why. APL's ambivalent symbols (one glyph, monad
and dyad meaning different things) are one name per function here; BQN
lists its incoherent pairs among its problems (read:
`commentary/problems.md`). Depth tests that change a primitive's
behaviour (read: `sources/docs/bqn/doc/depth.md`) are two functions, or a
type. Fill elements, the zero-frame probe and permissive assembly
(padding ragged results) are replaced by types: a ragged result is a
different type (§2.8), never padded (read: `rank1.htm`, §0, "permissive
assembly"; `sources/papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm`,
"assembly"). Trains and tacit composition are Idris's `.` and lambdas: the
rank of a composition is in its type, so J's `@` against `@:` (per cell
against whole) is `over c (g . f)` against `g . f`, two different types
(read: `sources/docs/j/help/dictionary/intro20.htm`).

**Under** is structural only: `View s t` is a closed set of selections
(a row, a column, the diagonal, a window, a swap of the last two axes),
each a lens whose put writes the selected cells back (read:
`sources/docs/bqn/doc/under.md`, "Structural Under is the same concept as
a (lawful) lens"). `under (Column 0) (map negate) m` negates the first
column (measured). Computational under (`f⌾g` with `g` invertible) is
composition with a named inverse, `inv . f . g`: a typed language takes
the inverse as a function, never guesses an obverse (read:
`sources/docs/j/help/dictionary/d202n.htm`).

### 2.6 Reductions, scans and their order

`reduce (+) 0 x` reduces the trailing axis from the left in index order,
one accumulator per frame cell: `reduce (+) 0 m` is the row sums,
`reduce (+) 0 (transpose m)` the column sums, `sum m` every element.
**decision** The meaning of every reduction and scan is its left fold in
index order (D15). A float result is then the same on every target, lane
width and core count, as today's one-lane rule keeps it (read:
`Passes.td`, `idr-vectorize`). A parallel float sum is a different
function with its own fixed order: `reduceBlocked k`, whose meaning is `k`
interleaved left folds (element `i` into fold `i mod k`) combined in
order, with `k` a literal of the program. Its order is its definition,
not a target's: any lane count that divides `k` implements it exactly
(16 is a multiple of every f64 lane count of 128, 256 and 512-bit
vectors; recalled), so it prints the same on both targets.

Which combiners the compiler may reassociate is read off their ops:
integer `+`, `*`, `and`, `or`, `xor`, `min` and `max`, whose definitions
associate and commute (§3.6). Iverson's partitioning identities are what
license the split (read:
`sources/papers/iverson-1980-notation-tool-of-thought/tot1.htm`, §4.2), and
for these the identity is a fact of the op, needing no proof.

`scan (+) 0 x` is the inclusive prefix sum along the trailing axis. A
segmented scan is a scan with a lifted combiner over (flag, value) pairs,
the standard construction, so it needs nothing of its own. Upstream has
no scan op of this generality (read: `.toolchain/llvm-project/mlir/include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td`
has none; `include/mlir/Dialect/Vector/IR/VectorOps.td:3032`,
`vector.scan`, takes a fixed combining kind); §3.6 adds one.

### 2.7 Index sets as types

Dex types an array by the set of its indices: `n=>a`, where `n` is any
type with a size and a bijection with `[0, size)`, and a tuple of index
sets is an index set, which "does not require the type system to solve
systems of Diophantine equations" to reshape (read:
`sources/papers/paszke-2021-dex/main.tex:782-831`). Here an index type
spans a shape:

```idris
interface IndexSet ix where
  0 axes    : Shape
  extentsOf : Extents axes
  toIndex   : ix -> Index axes
  fromIndex : Index axes -> ix

{n : Nat} -> IndexSet (Fin n)                        -- axes [<n]
IndexSet Bool                                        -- axes [<2]
(IndexSet a, IndexSet b) => IndexSet (a, b)          -- axes (axes a ++ axes b)

data Table : (0 ix : Type) -> Type -> Type where
  MkTable : IndexSet ix => Array (axes {ix}) a -> Table ix a

for  : IndexSet ix => (ix -> a) -> Table ix a
(!@) : Table ix a -> ix -> a
```

A product of index sets is the sum of their ranks: `Table (Fin 2, Fin 3,
Channel) Int` holds an `Array [<2, 3, 3] Int`, an enumeration
`Channel` an axis of its own, and `img !@ (1, 2, G)` types the literals
as `Fin 2` and `Fin 3` from the table (measured, with `for (\(y, x, c)
=> ...)` building it). So index sets add no second representation: a
table is an array, and the shape is computed by the instance.

```idris
grey : {h, w : Nat} -> Table (Fin h, Fin w, Channel) Double -> Table (Fin h, Fin w) Double
grey img = for (\(y, x) => 0.299 * img !@ (y, x, R) + 0.587 * img !@ (y, x, G) + 0.114 * img !@ (y, x, B))
```

**decision** The shape is an erased method of a one-parameter interface
(D8). A two-parameter interface `IndexSet ix s | ix` resolves `Fin n`
and `Bool` but never a product, whose head `s ++ t` unification cannot
match against a known shape (snoc append is stuck on an unknown right
side), with a determining parameter, an equation in the head or a hint
(measured, each). A `Table` is a data type, not a synonym, so that `ix`
stays in the type and drives the literals (measured: the synonym lost it,
and `(1, 2, G)` defaulted to `Integer`). Ranges and sums of index sets
(Dex's `RangeFrom`, `Either`) are instances whose axes are one flat axis
(`[<count s + count t]`), with the `Fin` arithmetic their `toIndex`
needs.

### 2.8 Shapes that depend on data

A size the data decides is the array's own (read:
`sources/papers/bailly-2023-size-dependent/paper.pdf`, §2.1, witnesses):
`filter p xs : Exists (\m => Vector m a)` (read:
`third_party/Idris2/libs/base/Data/DPair.idr:77-80`, `Exists`, whose
witness is erased), unpacked with `let Evidence _ ys = filter p xs in
...`, and `shape ys` gives the length, stored once, in the array.
Bailly et al. name the unpacking that Idris's `(p ** Vect p a)` forces as
Idris's gap (read: the same paper, §1); `Exists` keeps the unpacking but
not a second copy of the size.

A rank the data decides is the same: `readArray : IO (Exists (\s =>
Array s Double))` parses an array of any rank, and every function of the
library applies to it (§3.1 lowers its shape as one component).

A **ragged** array, cells of different shapes, is a different type:
`Ragged f a`, a frame of rows of different lengths, held as a flat
vector and an offset per row (Hsu's flat representation of nested data;
read: `sources/papers/hsu-2019-data-parallel-compiler/`, the parent and
offset vectors), with segmented scans and reductions (§2.6) over it. An
array of `Exists`-boxed rows is legal Idris and stays an array of boxes
(§3.1); `Ragged` is the dense form. Futhark's regularity rule, that no
array element has an existential size (read:
`sources/papers/henriksen-2021-size-types/paper.pdf`, §4), is the line
between `Array f (Array c a)` (one cell shape: flat) and `Ragged`.

A size equality the program cannot prove is an explicit, checked
conversion: `resize : (n : Nat) -> Vector m a -> Maybe (Vector n a)`.
Futhark's benchmark suite needed 66 such coercions in about 12,000 lines,
mostly where input is read (read: `henriksen-2021-size-types`, §6).

### 2.9 Shape arithmetic

Shapes are lists, so most shape facts are concatenation, which reduces:
`f ++ [<n]` is `f :< n` by computation. Arithmetic on sizes appears in a
few places: `take` and `slice` (`LTE`), `(++)` (`n + m`), `reshape` and
`ravel` (`count`, the number of elements of a shape, defined by its own
clauses so that a message names it), `windows` (`minus`). The library's
rules:

1. **Literal shapes need nothing.** Search proves `LTE 3 5` and `count
   [<24] = count [<2, 3, 4]` by computation, so the obligations are
   `auto` arguments a program never writes (measured: `reshape [<2, 3, 4]`
   of a 24-vector checks; `reshape [<2, 3, 5]` reports "Can't find an
   implementation for count [<24] = count [<2, 3, 5]", where base's
   `product`, a fold, printed as an unreduced `foldr` lambda; `take 5` of a
   length-4 axis reports "Can't find an implementation for LTE 5 4").
2. **Symbolic ones are a tactic of the library.** `Array.Shape.solve`, by
   elaborator reflection, normalizes both sides to a canonical form,
   concatenation flattened (Remora's canonical shapes; read:
   `sources/papers/slepak-2019-semantics/formalism.tex:464-524`) and sizes
   to sums of products with sorted monomials (read:
   `sources/docs/rocq/doc/sphinx/addendum/ring.rst`;
   `sources/code/ghc-typelits-natnormalise/src/GHC/TypeLits/Normalise/SOP.hs`),
   and returns the proof at quantity 0, so it costs nothing at run time.
   It reads `S k` as `1 + k`, because Idris's reflection hands the goal
   over normalized (read: `sources/papers/allais-2025-frex/reflection.tex`,
   the false equation `(x+1)+y = x+S y`). Frex is the Idris-native
   precedent: under 0.1 s for terms of size 6, under 1 s up to about 30,
   over 10 s past 45, the cost being the evaluator's (read:
   `allais-2025-frex/evaluation.tex`). **decision** The tactic's
   threshold: 1 s per obligation on the largest shape term of the test
   corpus (a rank-8 reshape is about size 30); past it, the normaliser
   moves from the evaluator into reflection that builds the proof once.
3. **Views for arithmetic patterns.** `Split d n` with the one constructor
   `MkSplit : (q, r : Nat) -> Split d (q * d + r)` lets tiled code match a
   size as `q * d + r` instead of rewriting into it (read:
   `sources/papers/mcbride-2004-view-from-left/view.ps`, §6); its indices
   erase.
4. **Index sets avoid products** (§2.7): a reshape between `Table (Fin n,
   Fin m) a` and `Array [<n, m] a` is the identity.

**decision** Idris's equality is not changed (D11): no normalization of
shape arithmetic in conversion, which would accept programs upstream
Idris rejects; no solver outside Idris (no oracle, nothing beyond the
toolchain at compile time). The proof always exists, at quantity 0
(read: `third_party/Idris2/libs/prelude/Builtin.idr:155-159`,
`rewrite__impl`, whose rule and motive are at 0 and value at 1).

### 2.10 Quantities and updates in place

Shapes are indices at quantity 0, never read as values; the sizes a
program computes with are `Extents` values or sizes at quantity many.
**Erased does not mean constant** is kept exactly: the compiler reads an
erased shape's *form*, which the checked type states, and never assumes
its sizes (§3.2).

An array is a value: `update a i x` is a new array, and `a` is unchanged.
A program that wants the write in place binds the array at quantity 1:

```idris
step : (1 _ : Array s Double) -> Index s -> Double -> Array s Double
```

and the compiler then writes in place with no runtime test, or, under
`--demand-in-place`, rejects the program with `unsupported (uniqueness)`
naming the write (§3.10). The README's in-place promise covers it: a
quantity-1 value updated in place, "or the program will not compile, with
a named reason" (read: `README.md`). An unrestricted array updated after
it is read again is copied, which is the value meaning.

`Linear.Array` keeps the mutable, growable array threaded at quantity 1
(push, pop, reserve) for programs that build an array element by element.
`freeze` hands the rank-1 dense array (`Vector n a` under `Exists`), and
`thaw` takes one back.

### 2.11 How programs read

Each of these type-checks against the mock (measured).

```idris
rowSums : Vector 3 Double
rowSums = reduce (+) 0 m

colSums : Vector 4 Double
colSums = reduce (+) 0 (transpose m)          -- a view: no transpose is built

centred : Matrix 3 4 Double
centred = agree (-) m (map (/ 4) rowSums)     -- each row less its mean

clipped : Matrix 3 4 Double
clipped = [| min m 10 |]

matmul' : Matrix m k Double -> Matrix k n Double -> Matrix m n Double
matmul' a b = contract (+) 0 (*) a (transpose b)

batched : Array [<8, 64, 32] Double -> Array [<8, 32, 16] Double -> Array [<8, 64, 16] Double
batched = over2 [<_, _] [<_, _] matmul'

softmax1 : Vector n Double -> Vector n Double
softmax1 v = let top = foldr max 0 v
                 e = map (\x => exp (x - top)) v
                 z = sum e
             in map (/ z) e

softmax : Array (f :< n) Double -> Array (f :< n) Double    -- any rank
softmax = over [<_] softmax1
```

Life, the APL classic (recalled: Dyalog's one-liner, `{↑1 ⍵∨.∧3 4=+/,¯1
0 1∘.⊖¯1 0 1∘.⌽⊂⍵}`), with the board's extents in scope for the literals:

```idris
neighbours : Matrix h w Int -> Matrix h w Int
neighbours b =
  let ext = shape b
      shifts = [rotate dy (over [<_] (rotate dx) b) | dy <- [-1, 0, 1], dx <- [-1, 0, 1], (dy, dx) /= (0, 0)]
  in foldl (+) 0 shifts

life : Matrix h w Bool -> Matrix h w Bool
life b = let ext = shape b
             n = neighbours (map (\alive => if alive then 1 else 0) b)
         in [| rule b n |]
  where rule : Bool -> Int -> Bool
        rule alive k = k == 3 || (alive && k == 2)
```

A histogram, Dex's accumulation with data-dependent destinations (read:
`main.tex:1781-1811`):

```idris
histogram : {k : Nat} -> Vector n (Fin k) -> Vector k Int
histogram xs = accumulate (+) (fill [<k] 0) (map (\i => [<i]) xs) (map (const 1) xs)
```

spectral-norm's product, dense: a row loop whose element is a sum, which
§3.6 and §3.7 make one generic of two dimensions, parallel then
reduction, as `Lower/Loops.cppm` does today for the rank-1 library:

```idris
mulAv : {n : Nat} -> Vector n Double -> Vector n Double
mulAv v = tabulate [<n] (\[<i] => sum (tabulate [<n] (\[<j] => a i j * v !! [<j])))
```

### 2.12 Error messages

Shape errors are Idris type errors, at elaboration, at the user's line,
naming both shapes or the rule that failed (measured):

| program | message |
|---|---|
| `m + w`, `[<3, 4]` against `[<4]` | "When unifying: Array [<4] Int and: Array [<3, 4] Int. Mismatch between: [<] and [<3]." |
| `agree (-) m w`, the same shapes | "Can't find an implementation for Agree [<3, 4] [<4]." |
| `take 5` of a length-4 axis | "Can't find an implementation for LTE 5 4." |
| `reshape [<2, 3, 5]` of a 24-vector | "Can't find an implementation for count [<24] = count [<2, 3, 5]." |
| `matmul'` of `3×4` and `5×2` | "When unifying: Array [<5, 2] Double and: Matrix 4 2 Double. Mismatch between: 1 and 0." |

**decision** The library names its evidence for the rule a reader
recognizes (`Agree`, `LTE`, `Prefix`, `count`), so a failed search names
the rule and both shapes. The matrix product's row is Idris reporting
two literal sizes, 5 and 4, where their unary forms first differ; for
shapes that reads as nonsense. It is fixed in Idris's unifier error, which names the two
literals, as a patch under `upstream/` with its report, reproducer,
`tests/upstream/` check, `PINS.md` entry and plan to send it upstream, as
AGENTS.md requires (D12). Nothing in `third_party/Idris2` changes.

There are no runtime shape errors in typed code: the type checker has
accepted every shape. What can fail at runtime is what the program asks
for: a `Maybe` from `(!?)` or `resize`, or a crash the program wrote.

### 2.13 The interactive loop

**decision** `idris-mlir repl` evaluates through this compiler, never
through Idris's evaluator or Chez (D13). A line is an expression in the
scope of the loaded modules: Idris elaborates it, and its type, shape
included, is printed (`:t` stops there); the frontend translates it as a
program whose root displays the value; the pipeline compiles it exactly
as it compiles a program, and it runs in a child process on the JIT, as
compile-time evaluation runs its calls (read: `foreign/idr/lib/Eval/Child.cppm`).
The meaning of every primitive is then the runtime's, which AGENTS.md
requires, and the loop shows what the compiled program would print.

- `:let x = e` adds a definition; `:mlir e` prints the module after the
  array lowering (§3.4), so a reader sees the generics, their maps and
  what fused; `:mlir after=<pass> e` after any pass.
- Values print with `display` (§2.3), the shape first: `[<3, 4] Double`.
- **Measurement rule.** The first version runs the frontend per line on a
  generated main file, as `idris-mlir` runs it per program today (read:
  `foreign/idr/lib/Driver/Frontend.cppm`). When a one-line expression over
  arrays of up to 10^6 elements takes more than 1 s from line to output
  on either target, a resident frontend that keeps the session's checked
  modules is built.
- Tests are transcripts: an input script and its expected output, as
  every program test is.

Type-driven editing is Idris's own and needs nothing here: shapes are
types, so a hole in an array program shows its expected type with the
shapes in it, and case splitting on an `Index` pattern splits its axes
(recalled: Idris's holes and case split work on any data type).

## 3. How it lowers

### 3.1 Representation by form

**decision** (D2, D4) The frontend reads the normal form of every shape
index as a sequence of **components**: each `:< n` a **dimension**, `Lin`
nothing, `++` the concatenation of its sides' components, and any other
subterm (a variable, or a call that does not reduce, such as `replicate k
2` with `k` a variable) a **segment**: `f ++ g` is two segments, `[<n] ++
f` a dimension and a segment. An array whose shape has `k`
components is a ranked tensor of rank `k`, each dimension `?` unless
compile-time evaluation made it constant. A segment is one dimension
whose size is the product of its axes (the dissertation's collapse to
products; read: `sources/papers/slepak-2020-dissertation/Dissertation.pdf`,
§11.2; `sources/code/remorac/src/remora-internal/map_replicate_ast.ml:129-156`),
and carries its axes' extents, a `tensor<?xi64>`, beside the array (a
record of the tensor and that vector, §3.8). `Index s` is one `Fin` per
dimension (a segment's component is its row-major ordinal, with the
extents to decompose it when a program matches it), and `Extents s` one
natural per dimension and the vector per segment.

**Sizes and indices stay naturals; narrowing makes them words**
(**decision**). `Fin n` and `Nat` are unbounded, so a program may build
an index or extents past 2^63 with no array behind it and print them; a
word would print something else. So they keep the representation the
frontend gives every `Nat`-like value today, a natural that
`idr-narrow` makes an i64 where it proves the value small (read:
`IdrOps.td`, `Idr_NatType`; `Passes.td`, `idr-narrow`). A loop's indices
are small by construction (they come from `linalg.index`). An extent
becomes a tensor dimension through a checked conversion, the one the
library's definition makes before it allocates, so an array that exists
has words for extents, and a `Fin` below one converts to an index
exactly, with no check. To let `idr-narrow` prove index arithmetic small
(`finToNat i * 4 + finToNat j`), the range of `tensor.dim` of an array is
seeded from the target: an extent times its element's size is below
2^(w-1), `w` the pointer width of the module's data layout (a fact of the
target's entry, read by every tool). An array whose elements are
naturals (`Fin`, `Nat`, `Index`) is narrowed the same way, as a web
through the tensor from the values its loops write to the values its
reads give, into a tensor of i64; one that is not proved small takes the
counted path below.

So a rank-9 literal shape is a rank-9 tensor; `f ++ [<n]` with `f`
unknown is a rank-2 tensor; an array of a rank read from input is a
rank-1 tensor and its extents. No tensor is unranked, which linalg could
not take (read: `LinalgStructuredOps.td:147`, `Variadic<AnyRankedTensor>`),
and every reassociation between forms is static, which
`tensor.expand_shape` and `collapse_shape` require (read:
`include/mlir/Dialect/Tensor/IR/TensorOps.td:1091-1122`).

The representation is a function of the normal form, so two types Idris
converts have one representation. Where a value moves between types that
are equal only by a proof (`rewrite`, `replace`, which the frontend
already treats as the identity on their value), the forms may differ, and
the frontend inserts the reshape between them: a collapse, or an expand
whose sizes a segment's extents give. `believe_me` cannot move an array
between types in user code (§1).

**Elements are structures of tensors** (D4). An element type's slots, as
the frontend lays out an unboxed value, each become a tensor of the
array's shape: a word one tensor, a record one per field, a sum a tag
tensor and one per field of each constructor, a `Char` an i32 tensor, an
enumeration its tag, a natural an i64 tensor once narrowed (above). An
element `Array c b` appends `c`'s components to the array's: `Array f
(Array c b)` and `Array (f ++ c) b` are one tensor, and `nest` and
`merge` are nothing (SaC's with-loop scalarisation, done by the
representation; read: `sources/papers/grelck-2006-sac/paper.pdf`, §3.4).
Arrays are values, so storing equal-shaped inner arrays contiguously is
observationally the library's meaning.

**decision** An element with a counted slot (a string, a big, a box, a
closure, a suspension, an `Exists`-boxed array) keeps today's path: the
array is the library's record over a memref of cells, compiled as
written, counted by `idr-rc`. A tensor of counted elements would need a
reference per element copied and per element read, which no structured
op takes. **Measurement rule:** a `bench/` program that spends more than
a quarter of its time in loops over arrays of counted elements reopens
it, with `memCpyFn` duplicating and loop bodies counting (read:
`include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:256-344`,
`allocationFn`, `memCpyFn`).

### 3.2 Instances keyed by form

**decision** An erased argument whose form a representation reads (the
shape index of an `Array`, `Index`, `Extents`, `Cell` or `Table` in the
rest of the callee's type) keys the instance by its canonical skeleton:
its components' kinds, every size erased. This is the mechanism that
keys runtime arguments by their skeleton today, extended to the erased
arguments a representation reads (§1). A call at `[<3, 4]` and a call at
`[<n, m]` share the instance of form `[<_, _]`; a call at `f :< n` with
`f` a segment has its own. A recursion that peels axes off a statically
known shape terminates in instances (the shape gets shallower); one that
deepens it is refused as today; one at a segment stays in its instance,
where the rank is a runtime value. This is SaC's specialization ladder
(read: `grelck-2006-sac/paper.pdf`, §2.4, `int[*]`, `int[.,.]`,
`int[3,7]`) with no rung missing: a known form is a known rank, constant
sizes are static dimensions, and an unknown form is a segment.

The reason this is not the earlier 0004's "a rank erased at quantity 0
is not a constant the compiler may assume": that sentence is about
sizes. A shape's form is part of the checked type at the call, as a
constructor of a runtime argument is; the compiler reads forms and never
assumes values.

### 3.3 What the frontend emits

**decision** The contract gains `tensor` and `bufferization`, with Idris
builders generated from their ODS as for arith and memref today (D14).
The generating set's hooks emit:

| primitive | op |
|---|---|
| `tabulate` | `idr.array.tabulate` (§3.4) |
| `foldLast`, `accumulate` | `idr.array.fold` |
| `scanLast` | `idr.array.scan` |
| `(!!)` | `tensor.extract`, no guard: the `Fin` proved it, and converts exactly (§3.1) |
| `shape` | `tensor.dim` |
| `nest`, `merge`, `reshape`, `ravel` | nothing, `tensor.collapse_shape`, `tensor.expand_shape` |
| `take`, `drop`, `slice`, `(++)` | `tensor.extract_slice`, `tensor.concat` |
| `update`, `under` | `tensor.insert`, `tensor.insert_slice` of `extract_slice` |
| `freeze`, `thaw` | `bufferization.to_tensor`, `to_buffer` |

A hook is a faster lowering with the same meaning, so breaking one
(`--break-shape`) compiles the library's definition and changes no
result (read: `compiler/src/IdrisMLIR/Registry/Entry.idr`, `Kind`). With
the type's representation hook broken, the whole library compiles as
written over memrefs; with an op's hook broken, its definition meets the
tensor at the record's edge, by `to_buffer` and `to_tensor` (§3.8).

### 3.4 The loop ops and their two lowerings

`idr.array.tabulate` takes one size per component and a body over one
index per component, yielding the element's slots (or a cell's tensors,
for an element that is an array); `idr.array.fold` takes the frame's
accumulators and the array, and its body takes accumulators, element and
index; `idr.array.scan` is the fold that yields every prefix. All three
are pure (no world), of any rank, on tensors, and their meaning is the
library's: the body runs at every index, in row-major order. Their shape
is known from their sizes, as `array.new`'s is
(`ReifyRankedShapedTypeOpInterface`), so `tensor.dim` of one folds.

**decision** A loop's lowering is chosen by what its body may do (D10):

- **A body that only computes** (no op that may crash, no call of a
  function that may crash or diverge, by `idr-effects`' bits; read:
  `Passes.td`, `idr-effects`) lowers to `linalg.generic`: a tabulate's
  dimensions parallel, a fold's frame parallel and its axis a reduction.
  Its order cannot be observed, so linalg's parallel contract holds, and
  every upstream transformation applies.
- **Any other body** lowers to an `scf.for` nest in index order over the
  result, written by `tensor.insert`, which One-Shot makes in place.

linalg makes a body that conflicts with a parallel iterator undefined
behaviour (read: `sources/docs/mlir/docs/Dialects/Linalg/_index.md:290-295`),
and a crash at index 5 of a producer and at index 2 of its consumer
print different messages once fused. The iterator type is therefore the
effect fact: a loop that may crash or diverge is never a linalg op, so no
pass can reorder it, and no pass needs to ask. Today's test that keeps a
row's crash order (`tests/programs/arrays/linarray-rows-crash-order`)
holds by representation. Typed indices make bodies crash-free, which is
what makes them fusible and parallel.

The decision is taken by `idr-tensorize`, after the simplify loop,
`idr-defunctionalize` and `idr-in-bounds`, when a body's calls are known
and its provable guards are gone.

### 3.5 Reads become inputs

A `tensor.extract` of an array from outside a loop, at indices that are
affine functions without symbols of the loop's indices, becomes an input
of the generic: the array cut by `tensor.extract_slice` to what the loop
reads, with that map (`Lower/Loops.cppm`'s rule for reads at the loop's
own index, generalized). The cut is in bounds because `tensor.extract`
is: its indices are within its tensor, the guard's absence being the
proof (read: IdrOps.td's accesses, "A proof is the guard's absence"). So
the entry test and the second copy of the loop that `Loops.cppm` builds
today are gone for typed reads, and linalg's assumption that "dynamic
operand dimensions agree with each other" (read: `Linalg/_index.md:141-142`)
is the shape types'.

Through this rule the vocabulary's definitions become structured ops: a
`transpose` read is a permutation map, which `linalg-specialize-generic-ops`
can name `linalg.transpose` (read: `include/mlir/Dialect/Linalg/Passes.td:93`);
an `outer` read projects each argument onto its own dimensions, Remora's
replication without materializing it (read:
`sources/code/remora/remora/dynamic/lang/semantics.rkt:92-132`); a
`windows` read is `d0 + d1`; `contract` and `matmul` are a fold over a
tabulate, which §3.6 makes one generic of three dimensions, two parallel
and one reduction. Maps take no symbols (read:
`lib/Interfaces/IndexingMapOpInterface.cpp:70`), so `reverse` and `rotate`
stay reads at a computed index in the body, which the vectorizer gathers
(read: `lib/Dialect/Linalg/Transforms/Vectorization.cpp`,
`tensorExtractVectorizationPrecondition`). Only projected permutations,
which frame replication and transposes are, vectorize as transfers
(read: `Vectorization.cpp:583`).

### 3.6 Reductions, scans and order

**decision** (D15) A reduction dimension is split, tiled across lanes or
partitioned only when its combiner is associative and commutative by the
definition of its ops: integer `addi`, `muli`, `andi`, `ori`, `xori`,
`minsi`, `maxsi`, `minui`, `maxui`. The fact is read off the region each
time a pass asks, so nothing stores it and nothing can drop it. A float
combiner keeps program order: one lane, one tile, one shard. A fold whose
body is a fold of a tabulate (a matrix product's row) fuses into one
generic, frame parallel and the inner axis a reduction, which today's
lowering builds by hand at rank 1 (read: `Lower/Loops.cppm`, `reducedBy`)
and which upstream's elementwise fusion of an all-parallel producer into
a reduction consumer gives at any rank (conjecture; stage 3's `fused`
property checks it on `matmul` and `softmax`).

A fold into an array at destinations the data names (`accumulate`, a
histogram) has no linalg form, because a structured op's output map
cannot read data: Dex's third reduction pattern, "an irregular segmented
reduction" (read: `sources/papers/paszke-2021-dex/main.tex:1781-1811`). It
lowers to an `scf.for` in index order whose writes One-Shot puts in
place. When its combiner associates by its ops, the multicore path gives
each shard a private destination and combines them in shard order
(§3.13); otherwise it stays on one shard.

**decision** `idr.array.scan` is ours (D16): a region combiner over the
trailing axis, several operands, inclusive, modelled on Triton's `tt.scan`
(read: `sources/code/triton/include/triton/Dialect/Triton/IR/TritonOps.td:876-895`),
implementing `TilingInterface` on its frame. Its axis is sequential; for
a combiner associative by its ops it lowers as a two-pass scan (a scan per
tile, a scan of the tiles' totals, an add), and that is the only place it
splits. A segmented scan is a scan whose combiner is the lifted one
(§2.6). Upstream has no such op (§2.6); when one lands, ours goes.

### 3.7 Frames of cells and batching

A tabulate whose element is an array (a `map` over `nest`, which `over`
is) is a frame of cells. **decision** It lowers to `scf.forall` over the
frame, each iteration's cell computed on `tensor.extract_slice`s and
written by `tensor.parallel_insert_slice` (read:
`include/mlir/Dialect/SCF/IR/SCFOps.td`, `scf.forall`), and a pattern of
ours folds a forall whose body is one generic over the whole cell into
that generic with the frame's dimensions prepended, parallel. That is
batching, and it is Hui's integrated rank support: the cells are never
built, the frame becomes outer loops of the cell's op (read:
`rank1.htm`, §1, measured there at 1.8x to 157x over building the cells).
A rank-2 kernel over a frame is then one generic, which upstream tiles
and vectorizes as it does any.

The result's cell extents come from the body's shape, reified without
its data (`ReifyRankedShapedTypeOpInterface` on the yielded tensor's
op): Futhark's function slicing, done by upstream's interface (read:
`sources/papers/henriksen-2017-futhark-thesis/`, §6). A body whose result
shape depends on its data computes its first cell before the rest. An
empty frame's cell extents cannot be observed (no index of it exists),
so they are zero.

### 3.8 Records, sums and boxes that hold arrays

A pair of arrays, an array beside its count, a segment's extents beside
its tensor: an unboxed record or sum may hold tensors. **decision** The
first step of `idr-tensorize` replaces every unboxed record or sum that
holds a tensor by its slots (its tag and each field), across function
signatures, calls, block arguments, region results and matches, with
MLIR's one-to-many conversion (read:
`include/mlir/Transforms/DialectConversion.h`, `OneToNOpAdaptor`,
`replaceOpWithMultiple`). One-Shot then sees only tensors. A box (a cell
in the heap) holds a memref: a tensor stored into one is
`bufferization.to_buffer`, a value read out of one is `to_tensor`, not
`restrict`, because the box may be shared. This is the earlier 0004's
rule for frozen arrays read out of boxes, kept.

### 3.9 Fusion, tiling and vectorization

- **Fusion** is upstream's `linalg-fuse-elementwise-ops` (read:
  `Linalg/Passes.td:167`), on tensors, for generics, which only bodies
  that compute are (§3.4): Futhark's rule, never duplicate work and never
  lose parallelism (read: `henriksen-2017-futhark-thesis`, §7), with no
  read moved past a write, which tensors make impossible to express.
  Fusion stops at size-changing primitives (`filter`, `accumulate`,
  `concat`), as BQN's notes argue and linalg does anyway (read:
  `sources/docs/bqn/implementation/compile/fusion.md`).
- **Tiling for the cache** is `transform.structured.fuse` on generics of
  two or more dimensions, the tile's working set at most the L1 data
  cache read from DLTI (`L1_cache_size_in_bytes`, written by `idr-target`
  from the target's entry). **Measurement rule:** tiling stays on only
  where a benchmark it changes gets faster on both targets and none gets
  slower beyond the run-to-run spread.
- **Vectorization stays where it is.** The generics bufferize to memref
  generics, which `idr-vectorize` and `idr-narrow-lanes` treat as today.

### 3.10 Bufferization and grades

Kept from the earlier 0004, whose decisions stand:

- `idr-bufferize` is One-Shot Bufferize through
  `bufferization::runOneShotModuleBufferize`, function boundaries
  bufferized at the identity layout, `allocationFn` building
  `idr.array.alloc` (a new array cell of word elements, unspecified until
  written, as `tensor.empty`'s are), no deallocation pass: counting frees
  cells.
- The grade wraps the carrier: `!idr.lin<tensor<...>>` before
  bufferization and `!idr.lin<memref<...>>` after, `idr::QType`
  implementing `TensorLikeType` and `BufferLikeType` (read:
  `include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td:18-41`),
  and `idr.lin.enter` and `idr.lin.use` implementing
  `BufferizableOpInterface` as equivalent to their operand.
- One-Shot decides in place over SSA before `idr-rc`; after it every
  buffer is an array cell that `idr-rc` grades as any array. Neither
  consults the other.
- Recursion: upstream does not analyse recursive boundaries (read:
  `sources/docs/mlir/docs/Bufferization.md:283-284`). **Measurement
  rule:** a `bench/` program whose thread stays a copy only because of a
  recursive boundary is the threshold for extending the module analysis
  upstream, as a patch under `upstream/`.
- **The in-place clause.** Under `--demand-in-place` (read: `Passes.td`,
  `idr-demand`), every write whose array came out of a quantity-1 binder
  must be in place; one that One-Shot copies is `unsupported (uniqueness)`,
  naming the write and One-Shot's conflicting read.

### 3.11 Threads of writes on `Linear.Array`

Kept from the earlier 0004: a thread of writes on a `Linear.Array` that
starts at a new array, runs through SSA and ends where it is frozen or
stored, becomes `tensor.insert` when One-Shot's analysis of the raised
thread finds every write in place; a read-after-write conflict, where
the library's one-object meaning and the tensor's differ, keeps the
memref ops. A thread bound at quantity 1 never conflicts.

### 3.12 Compile-time evaluation

A closed array expression is a closed pure call, so `idr-eval` runs it
and its result becomes a dense constant (`arith.constant dense<...>`), up
to its 1 MiB limit (read: `Passes.td`, `idr-eval`). A shape that compile-
time evaluation makes constant makes static dimensions, and every loop
over them a known trip count. Evaluation lowers through the same
pipeline as a program, `idr-tensorize` and `idr-bufferize` included.

### 3.13 Multicore

The shard runtime, its fork and join and its lowering of `scf.forall`
are `proposals/0005-shards.md`'s (§8, stage P4); SPMD through upstream's
`shard-partition` is its P5, by its rule. What this proposal owns is
which loops may run on many cores: generics' parallel dimensions, which
only bodies that compute have (§3.4); reductions split only when their
combiner associates by its ops (§3.6), so a float result is the same on
any number of cores; the partitioned extent's lower bound, the extent at
which the partitioned spectral-norm row loop breaks even on each target,
rounded up to a power of two and kept in the target's entry.

## 4. What it deletes

- The ceiling of rank 1 on arrays the program does not order: they are
  tensors of any rank, and the memref predicates `Idr_ArrayValue` and
  `Idr_Rank1ArrayValue`, with the frontend's `Rank0 | Rank1`, stay with
  the arrays a world orders (`IOArray`, `Buffer`, `IORef`).
- `idr.array.generate`, `idr.array.fold` on memrefs, and the memref half
  of `Lower/Loops.cppm`, with its entry test and second copy of a loop.
- `Linear.Array`'s `IArray`, `ifoldl`, `imap`, `map`, `zipWith`, `sum`,
  and the registry's `prim__generate` and `prim__foldl` hooks.
- The words-only condition on loops (`Terms.idr`, `arrayLoop`).
- The earlier 0004's §3.7 and its fallback for a rank that is not a
  literal.

## 5. Rules of AGENTS.md it keeps

- **Idris does types; MLIR does programs.** Shapes, ranks, agreement and
  uniformity are Idris types, checked by Idris; the frontend reads forms
  to choose representations; which loops are parallel, what fuses and
  what is in place are decided in MLIR, from the ops.
- **One thing, one representation.** One array type, one loop family,
  one index type; index sets compute a shape rather than add a second
  kind of array; associativity is read off ops rather than stored; a
  nested array of one cell shape is the flat one.
- **Facts in types.** Quantity 1 wraps the tensor and the memref
  (§3.10); in-bounds is the guard's absence; the effect that keeps a loop
  in order is its representation (§3.4). No fact lives in a discardable
  attribute.
- **Erased does not mean constant.** Forms are read, sizes never assumed
  (§3.2). **Indexed vectors do not imply contiguous storage**: arrays are
  contiguous by the library's construction, `Vect` stays a list.
- **No primitive has an implementation in Idris.** The array library is
  not a primitive: its definitions are plain Idris over base's primitives,
  whose one meaning is the runtime's; the hooks are faster lowerings of
  the same definitions.
- **No oracle.** Expected files are the specification; a test runs with
  and without hooks against the same files. The interactive loop runs the
  compiler's code.
- **Never miscompile silently.** A body whose order is observable is
  never reordered; a counted element keeps its counted path; a size or
  an index is a word only where it is proved to fit; a coercion between
  representations is inserted, never assumed.
- **Both targets, nothing per target outside the entry.** Lane counts,
  the L1 size and the partition bound come from the target's entry;
  `reduceBlocked`'s fan-out is the program's, not a target's.
- **Only `IdrisMLIR.Frontend.*` imports Idris's modules; `third_party`
  is unmodified.** The error-message fix is a patch under `upstream/`.
- **Static linking.** The interactive loop's JIT is `idr-eval`'s, in the
  statically linked compiler; nothing of ours is loaded at run time.

## 6. Staged plan

Each stage passes `make check`, `make build`, `make test`, `make
test-idr` and `make test-mlir-tools` on both targets, and runs `bench/` on
both. New benchmarks, each with a C counterpart in `bench/c/` and no
Chez column (nothing here is shaped for Chez): `matmul` (1024, f64, the C
an `ikj` triple loop), `heat` (a 2-D five-point Jacobi step, 2048², 100
steps), `spectral-norm-dense` (spectral-norm over this library, against
`spectral-norm.c`), `prefix-sum` (an inclusive scan of 10^8 i64),
`histogram` (10^8 bytes into 256 bins). A ratio is read against its own
run's C; parity is within the run-to-run spread (`bench/README.md`).

1. **The language, as written.** `libs/mlir-array` with the types, the
   generating set over base's primitives and `Linear.Array`, the
   vocabulary, the interfaces, `IndexSet`, `Display`; the notation checks
   of §2 committed as type-level tests; type-error fixtures whose expected
   transcript is the error, one per rule; the `upstream/` patch for
   literal size mismatches (D12). Proof: a test per vocabulary entry
   against its expected output; the benchmarks run and are recorded as
   this stage's baseline (rank-1 loops over the flat backing, through
   today's hooks).
2. **Tensors by form.** The contract gains `tensor` and `bufferization`;
   the frontend's representation by components (§3.1) and instances by
   form (§3.2); the generating set's hooks (§3.3); `idr-tensorize` (record
   decomposition, the two lowerings, reads as inputs), `idr-bufferize`,
   grades over tensors; the range of `tensor.dim` seeded from the pointer
   width (§3.1); `IArray` and the rank-1 loop ops go. Proof: stage
   1's expected outputs unchanged, and unchanged with every hook broken;
   new `idr-expect` properties, `structured-loops=@f` (every array loop of
   `@f` is a linalg op, its frame parallel) and `typed-reads=@f` (no guard
   and no entry test on a typed read in `@f`) and `word-loops=@f` (no op on
   a big or a natural left in a loop of `@f`), the last on the `Fin`
   arithmetic of §2.11's examples; `vectorized` where it held;
   spectral-norm-linear within the spread of 0.596 s; `spectral-norm-dense`
   at least at spectral-norm-linear's ratio to C.
3. **Fusion, batching, tiling.** Proof: `fused=@f` (no array allocated
   between two loops of `@f`) on `map f (map g x)`, `softmax` and `matmul`;
   `batched` is one generic (`structured-loops`); `matmul` and `heat` at
   parity with their C or faster on both targets, else the tiling
   measurement rule decides what stays.
4. **Order.** `idr.array.scan`, its two-pass lowering, integer reductions
   across lanes, `reduceBlocked`. Proof: integer reductions and scans
   vectorized across lanes (`vectorized`), float reductions in program
   order (their outputs bit-equal to the in-order meaning in the expected
   files); `prefix-sum` at parity with its C.
5. **Index sets, shapes that depend on data, shape arithmetic.**
   `for` and `Table`, `filter`, `Ragged`, `accumulate`, `resize`,
   `Array.Shape.solve` and the views; arrays of naturals narrowed through
   the tensor (§3.1). Proof: tests; `word-loops` on `histogram` and on a
   gather through `select`; `histogram` at parity with its C; the tactic
   within its threshold (§2.9) on the corpus.
6. **Threads of writes and the in-place clause** (§3.10, §3.11). Proof:
   `in-place-thread=@f` (every write of `@f` in a raised thread and no
   copy inserted); a reject fixture under `--demand-in-place`;
   fannkuch-linear at parity with clang.
7. **The interactive loop** (§2.13). Proof: transcript tests; the latency
   rule measured on both targets and its outcome recorded.
8. **Multicore** (§3.13), after 0005's P4. Proof: 0005's rules for P4
   and P5; `heat` and `matmul` outputs identical on one shard and on all.

## 7. Rejected alternatives

- **Rank only where it is a literal** (the earlier 0004): it read a
  form, which the type states, as if it were a value. Forms are static;
  sizes are not (§3.2).
- **An unranked tensor or a runtime-rank descriptor for every array.**
  linalg takes ranked operands only, and reassociations are static;
  segments give dynamic rank with ranked tensors (§3.1).
- **Leading-axis primitives (J, BQN).** Typed by shape calculators on
  the whole shape (`major s`), they get stuck on a variable frame
  (`major (f :< n)`), where trailing-axis types infer the frame by
  unification; the leading axis is a free transpose away (§2.1, §3.5).
- **Trailing (NumPy) broadcasting and size-1 stretching**: a second
  agreement rule, decided by runtime sizes (§2.4).
- **Implicit lifting at application** (Remora) **or by elaboration**
  (AUTOMAP, which removes 54% of explicit maps at 2.5x type-checking
  time; read: `sources/papers/schenck-2024-automap/paper.pdf`, §1-2):
  either is a change to Idris's elaborator, which is upstream's and
  unmodified. `over`, `agree` and `map` are explicit, short and typed.
- **Arithmetic overloaded across shapes under the Prelude's names**:
  ambiguous elaboration of ordinary arithmetic (measured, §2.3).
- **A glyph module** (§2.3).
- **A shape index language of its own** (DML, Remora, Qube) or Dex's
  value-dependent types with syntactic equality: Idris's terms are the
  index language, and its equality is definitional.
- **A word-equation or SMT solver in the compiler or the checker**, and
  **shape arithmetic in Idris's conversion**: an oracle beside the
  toolchain, or programs accepted here and refused upstream (§2.9).
- **Fill elements and the zero-frame probe** (APL, J, BQN): a calculator
  or a nested result settles the empty frame by type (§2.4).
- **Emitting linalg from the frontend**: whether a body may crash or
  diverge is known only after inlining and defunctionalization, so the
  frontend emits a loop with the library's order and the MLIR side
  chooses (§3.4).
- **Reassociating float reductions, or proofs that license it for user
  monoids.** Floats do not associate; a parallel float sum is a function
  with its own order (`reduceBlocked`). A user monoid in a hot loop is
  the measurement that would add a lawful-monoid entry point.
- **Nested arrays as a cell per row**: an array of one cell shape is
  flat by representation (§3.1); a ragged one is `Ragged`.
- **Tensors of counted elements now** (§3.1, its measurement rule).
- **`tensor.generate`**, which has no destination and always allocates
  (read: `Bufferization.md`, "Destination-Passing Style"); **`tensor.gather`
  and `tensor.scatter`**, which have no bufferization model (read:
  `lib/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.cpp:1190-1210`
  registers neither); **`linalg` `library_call`**, a dynamically linked
  call; the sparse runtime library; `ShardToMPI`, OpenMP and the async
  runtime: each a C runtime or a shared library, outside AGENTS.md.
- **Ownership-based buffer deallocation**: a second ownership system
  beside counting.
- **An interactive loop on Idris's evaluator or Chez**: a second meaning
  of every primitive.
- **Autotuned thresholds and user-visible schedules** (Futhark's
  incremental flattening, Triton, Halide, TVM; read:
  `sources/papers/henriksen-2019-incremental-flattening/paper.pdf`, §4.2):
  non-reproducible builds, and a second program beside the program.
  Thresholds come from the target's entry; schedules are the compiler's.

## 8. Decisions

**D1. The library** is `libs/mlir-array`, in plain Idris over base's
primitives and `mlir-linear`, a trusted library as `mlir-linear` is.
Reason: AGENTS.md's rule for what the compiler ships beyond base; its
definitions are the meaning, and a hook can be broken without changing a
result.

**D2. Shapes are snoc lists, and rank is the form** (§2.1, §3.1, §3.2).
Reason: unification infers frames on snoc lists and not on cons lists
(measured); the form is in the checked type at every call, so reading it
is reading Idris's proof, not assuming a value.

**D3. Primitives act on their trailing cells; agreement is prefix
agreement** (§2.1, §2.4). Reason: one rule for primitives and the rank
operator, frames inferred without calculators, and an agreement that
never consults a runtime size.

**D4. Indices are `Fin`s; sizes and indices stay naturals, narrowed to
words where proved, with tensor extents bounded by the address space;
elements are structures of tensors; nested arrays of one cell shape are
flat** (§2.2, §3.1). Reason: no check on a typed access (the README's
promise), linalg's dimension agreement by type, crash-free bodies; a
word where a natural may not fit would print a different number; one
tensor per slot keeps loops on words.

**D5. Arithmetic at one shape, extents by search; agreement named**
(§2.3). Reason: measured: overloading across shapes makes ordinary
arithmetic ambiguous; this form passes every probe.

**D6. Rank is `merge ∘ map ∘ nest`, the empty frame settled by a
calculator** (§2.4). Reason: BQN's identity as the definition; Hui's
uniformity as a type; search finds the calculator in the common cases
(measured), and a nested result needs none.

**D7. A generating set of hooked primitives; the vocabulary is library
code** (§2.5). Reason: the smallest surface the compiler must keep equal
to the library; everything else becomes structured ops by §3.5.

**D8. Index sets are a one-parameter interface with an erased shape;
`Table` is a data type** (§2.7). Reason: measured: the only form whose
products resolve and whose literals type.

**D9. Names, not glyphs** (§2.3).

**D10. A loop's lowering is chosen by its body's effects** (§3.4).
Reason: the parallel iterator is the fact that order is unobservable, so
it must be true by representation.

**D11. Idris's equality is unchanged; shape arithmetic is the library's
tactic, with a threshold** (§2.9).

**D12. Literal size mismatches are reported as the literals**, by a patch
to Idris's unifier error under `upstream/`, with its report, reproducer,
check and plan (§2.12). Reason: the language's diagnostics are shape
errors, and today's message for the commonest one names unary remainders.

**D13. The interactive loop runs the compiler's code, with a latency
rule** (§2.13). Reason: one meaning per primitive.

**D14. The contract gains `tensor` and `bufferization`; linalg is the
MLIR side's** (§3.3, §3.4). Reason: views and edges have no effects and
are upstream's ops from birth; loops need the effect decision first.

**D15. Reductions and scans mean their left fold; reassociation is read
off the combiner's ops; parallel float sums are `reduceBlocked`** (§2.6,
§3.6). Reason: results identical on every target, lane width and core
count, with no stored fact.

**D16. `idr.array.scan` is ours until upstream has a scan with a region
combiner** (§3.6).

**D17. Counted elements keep the counted path, by measurement** (§3.1).

**D18. Records and sums of tensors are replaced by their slots before
bufferization; boxes hold memrefs** (§3.8).

## 9. Upstream used

| Mechanism | For |
|---|---|
| `tensor` (`empty`, `extract`, `insert`, `dim`, `extract_slice`, `insert_slice`, `concat`, `expand_shape`, `collapse_shape`, `parallel_insert_slice`) | views, reads, updates, reshapes (§3.3) |
| `linalg.generic`, `linalg-specialize-generic-ops`, `linalg-fuse-elementwise-ops`, `TilingInterface` | loops, fusion, tiling (§3.4, §3.9) |
| `scf.for`, `scf.forall` | loops in order; frames of cells (§3.4, §3.7) |
| `ReifyRankedShapedTypeOpInterface` | cell extents without data (§3.7) |
| One-to-many dialect conversion | records of tensors (§3.8) |
| One-Shot Bufferize, `TensorLikeType`, `BufferLikeType`, `BufferizableOpInterface`, `allocationFn` | bufferization and grades (§3.10) |
| `bufferization.to_tensor`, `to_buffer` | edges with boxes and `Linear.Array` (§3.8) |
| `transform.structured.fuse`, DLTI `L1_cache_size_in_bytes` | tiling (§3.9) |
| `linalg::vectorize` (through `idr-vectorize`) | lanes (§3.9) |
| `shard.grid`, `sharding-propagation`, `shard-partition` | SPMD, by 0005's rule (§3.13) |
