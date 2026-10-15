## C19 The array library surface

Producer: U13. Consumers: U14 (trust, recognition, the type mapping of
C20), U15 (the tensor types C22 emits for these types), U18 (the ported
and new programs, the bench runs, every `packages` file), U12 and U08
(invariant I2, on which 0003 D33's `restrict writable` and the release
model rest). Everything here is fixed; a consumer that needs another
name or type escalates, never adds one.

### 1. Packages

`libs/mlir-linear/mlir-linear.ipkg` (changed; the growable array module
`libs/mlir-linear/Linear/Array.idr` is deleted with its two Scheme-spec
primitives):

```
package mlir-linear
version = 0.1.0

brief = "Linear data and a linear string iterator for idris-mlir, in Idris over base's primitives and a few of the compiler's own"
authors = "idris-mlir"

depends = base

modules = Linear.List,
          Linear.Nat,
          Linear.Notation,
          Linear.String.Iterator
```

The four modules keep their source and exports byte for byte
(`libs/mlir-linear/Linear/List.idr:12-37`, `Nat.idr:11-26`,
`Notation.idr:10-41`, `String/Iterator.idr`). Which of their types the
registry names as rebuilt in place and exclusive is C20's (0004 §4
stage 1).

`libs/mlir-array/mlir-array.ipkg` (new, 0003 D1):

```
package mlir-array
version = 0.1.0

brief = "Typed arrays for idris-mlir: shapes in the type, a generating set the compiler lowers to MLIR's tensors, linear arrays and a growable vector, in plain Idris over base's primitives"
authors = "idris-mlir"

depends = base, mlir-linear

modules = Array,
          Array.Core,
          Linear.Vec
```

Install order: `mlir-linear` before `mlir-array` (the `install` macro
installs in list order, `Makefile:159-173`; `SHIPPED`, `Makefile:222`, is
the coordinator's). A program that imports any module of `mlir-array`
names both packages, `-p mlir-linear -p mlir-array`: Idris's `-p` adds the
package it names, not that package's dependencies
(`compiler/idris/README.md:23-27`). So every such program's `packages`
file reads `mlir-linear mlir-array`.

Neither package declares a `%foreign`; `mlir-linear`'s only `%extern`s are
`Linear.String.Iterator`'s three (`Iterator.idr:25-27`), and `mlir-array`
declares none (0003 D37). Both typecheck with the pinned Idris
(*measured*, 2026-10-14, private build directories), and neither needs a
meaning of ours on its Chez backend, since base's array primitives are the
only ones they call.

### 2. `Array.Core` (package `mlir-array`, file `libs/mlir-array/Array/Core.idr`)

```idris
module Array.Core

import public Data.Fin
import Data.Fin.Properties
import Data.Fin.Split
import Data.IOArray.Prims
import Data.Nat
import Linear.Notation

%default total

export infixl 10 !!
```

`Data.Fin` is re-exported, since an index is made of `Fin`s.
`Linear.Notation` is imported, not re-exported: its linear `id` and `(.)`
would stand beside the Prelude's in every user module. A program that
writes `MkBang` or `unrestricted` imports `Linear.Notation` itself, as the
bench programs do today.

#### 2.1 Shapes, extents, indices, cells (public data, compiled as written)

```idris
public export
Shape : Type
Shape = SnocList Nat

public export
count : Shape -> Nat
count [<] = 1
count (s :< n) = count s * n

namespace Extents
  public export
  data Extents : Shape -> Type where
    Lin  : Extents [<]
    (:<) : Extents s -> (n : Nat) -> Extents (s :< n)

namespace Index
  public export
  data Index : Shape -> Type where
    Lin  : Index [<]
    (:<) : Index s -> Fin n -> Index (s :< n)

namespace Cell
  public export
  data Cell : Shape -> Type where
    Lin  : Cell [<]
    (:<) : Cell s -> (0 n : Nat) -> Cell (s :< n)

export
volume : Extents s -> Nat

export
volumeIsCount : (e : Extents s) -> volume e = count s

public export
Scalar : Type -> Type
Scalar = Array [<]

public export
Vector : Nat -> Type -> Type
Vector n = Array [<n]

public export
Matrix : Nat -> Nat -> Type -> Type
Matrix m n = Array [<m, n]
```

Qualified names: `Array.Core.Shape`, `Array.Core.count`,
`Array.Core.Extents.Extents` with `Array.Core.Extents.Lin` and
`Array.Core.Extents.(:<)`, `Array.Core.Index.Index` (likewise),
`Array.Core.Cell.Cell` (likewise), `Array.Core.volume`,
`Array.Core.volumeIsCount`. Shapes are snoc lists, outermost axis first
(D2); `[<m, n]` is a value of `Extents [<m, n]` and a pattern of
`Index [<m, n]` by Idris's snoc-list syntax. `count` reduces at the type
level; `volume` is its run-time twin over a singleton, a product of
naturals computed as written. `Extents s` is a singleton of its shape; an
`Index s` holds one `Fin` per axis, so it is inside its array by type
(D4). In a `Cell` the sizes are erased and left to unification.

#### 2.2 The two array types (abstract)

```idris
export
data Array : (0 s : Shape) -> Type -> Type

export
data LArray : (0 s : Shape) -> Type -> Type
```

Qualified names `Array.Core.Array` and `Array.Core.LArray`. Their
constructors are private to `Array.Core` and never reach the frontend:
`MkArray : Extents s -> Cells s a -> Array s a`,
`MkLArray : Extents s -> Cells s a -> LArray s a`, over the private
`Cells s a` with `None : (0 empty : count s = 0) -> Cells s a` and
`Slots : ArrayData a -> Cells s a` (base's `Data.IOArray.Prims.ArrayData`,
the `count s` elements in row-major order). This is the Idris meaning
only; idris-mlir never compiles a body that opens it (§2.3, I1).

#### 2.3 The recognized functions

Every function below opens the representation, so the frontend knows
each by its qualified name `Array.Core.<name>` and lowers its calls to
upstream ops with the meaning given (C20, after 0003 §4.1 and §8); it
never compiles the body. In every type, each implicit is quantity 0.

The generating set (0003 §3.5, D7; `accumulate` is stage 5 and absent):

```idris
export
shape : Array s a -> Extents s

export
tabulate : Extents s -> (Index s -> a) -> Array s a

export
(!!) : Array s a -> Index s -> a

export
foldLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b

export
scanLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array (f :< n) b

export
nest : Cell c -> Array (f ++ c) a -> Array f (Array c a)

export
merge : Extents c -> Array f (Array c a) -> Array (f ++ c) a

export
reshape : Extents t -> {auto 0 same : count s = count t} -> Array s a -> Array t a

export
take : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< k) a

export
drop : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< minus n k) a

export
(++) : Array (f :< n) a -> Array (f :< m) a -> Array (f :< n + m) a

export
pad : (lo, hi : Nat) -> a -> Array (f :< n) a -> Array (f :< lo + n + hi) a

export
update : Array s a -> Index s -> a -> Array s a
```

`f ++ c` in a shape is the Prelude's `SnocList.(++)`, which recurses on
its right argument (`Prelude/Types.idr:424-427`), so `f ++ (c :< n)`
reduces to `(f ++ c) :< n`. The array `(++)` keeps the Prelude's fixity
`infixr 7` (`Prelude/Ops.idr:13`). `drop`'s result is `minus n k`: 0003
§3.5's table writes `f :< k` for `drop` as for `take`, a slip, since a
drop of `k` from `n` leaves `n - k`.

The linear half (0003 §3.8, D19, D37):

```idris
export
withArray : Extents s -> a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b

export
read : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))

export
write : (1 _ : LArray s a) -> Index s -> a -> LArray s a

export
freeze : (1 _ : LArray s a) -> !* (Array s a)

export
thaw : Array s a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b

export
lshape : (1 _ : LArray s a) -> Res (Extents s) (const (LArray s a))

export
grow : (k : Nat) -> a -> (1 _ : LArray (f :< n) a) -> LArray (f :< n + k) a
```

`withArray` and `thaw` take their continuation at quantity 1 and return
its `!* b`, Linear Haskell's `alloc :: Int -> a -> (Array a %1 -> Ur b)
%1 -> Ur b`, not 0003 §3.8's sketch `((1 _ : LArray s a) -> Ur b) -> b`.
Reason (*measured* by typechecking the ports with the pinned Idris): with
the sketch a program cannot hold two linear arrays at once. A second
`withArray` inside the first's continuation returns `b` where that
continuation must return `!* b`, and an unrestricted continuation cannot
capture the first array, which is linear. With a linear continuation and
an unrestricted result, `withArray e1 v1 (\a1 => withArray e2 v2 (\a2 =>
...))` composes, and the program unwraps once with `unrestricted`. I2 is
unchanged: the only `!* b` a continuation can build is `MkBang`, whose
field is unrestricted, so no linear array leaves in it.

The world bridge (0003 §13):

```idris
export
tabulateIO : Extents s -> (Index s -> IO a) -> IO (Array s a)
```

Meanings (each is what the Idris definition computes; row-major order
is the order of `Index s` with the last axis fastest):

| name | meaning |
| --- | --- |
| `shape x` | the extents `x` was built with |
| `tabulate e f` | `f i` at each `i`; `f` applied once per index, in row-major order, and never when `count s = 0` |
| `x !! i` | the element at `i`; no check: the index is in bounds by type |
| `foldLast g z x` | for each frame index `p`, in row-major order, the left fold `g (... (g (z !! p) (x !! (p :< 0))) ...) (x !! (p :< n - 1))` |
| `scanLast g z x` | at `p :< j`, the left fold of `z !! p` with `x !! (p :< 0)` to `x !! (p :< j)`, inclusive |
| `nest c x` | at frame index `p`, the cell of `x` under `p`, of the shape `c`'s rank leaves |
| `merge e x` | the inverse of `nest`; `e` gives the cell's extents when the frame is empty (D6) |
| `reshape e x` | the same elements in row-major order, at the extents `e` |
| `take k x` | at `p :< j`, `x !! (p :< j)` for `j < k` |
| `drop k x` | at `p :< j`, `x !! (p :< k + j)` |
| `x ++ y` | at `p :< j`, `x !! (p :< j)` for `j < n`, else `y !! (p :< j - n)` |
| `pad lo hi v x` | `lo` copies of `v`, then the elements, then `hi` copies of `v`, along the last axis |
| `update x i v` | a new array equal to `x` but `v` at `i`; `x` is unchanged |
| `withArray e v k` | `k`'s result, `k` given a fresh linear array of extents `e`, every element `v` |
| `read a i` | the element at `i`, and the array back unchanged |
| `write a i v` | the array with `v` at `i`, in place |
| `freeze a` | the elements as an `Array`, with no copy; the linear array is consumed |
| `thaw x k` | `k`'s result, `k` given a fresh linear array with `x`'s elements; `x` is unchanged |
| `lshape a` | the extents, and the array back unchanged |
| `grow k v a` | a fresh linear array `k` longer on the last axis, `a`'s elements at their indices and `v` in every new slot; `a` is consumed |
| `tabulateIO e act` | `act i` run once per index in row-major order, in the world's order, each result at its index; never run when `count s = 0` |

#### 2.4 Invariants (what the compiler may rely on, and the library keeps)

- I1. Only the definitions of §2.3, and private helpers reached only from
  them, name `MkArray`, `MkLArray`, `None` or `Slots`. The module boundary
  is the check: the constructors are not exported.
- I2. No `LArray` value exists at quantity ω. A function that yields one
  either takes one at quantity 1 (`write`, `grow`, and the second
  component of `read` and `lshape`) or gives a fresh one, at quantity 1,
  to a continuation used once whose result is `!*` (`withArray`, `thaw`);
  `freeze` is the only way out, and it consumes its argument. So every
  `LArray` is born fresh and aliases no shared buffer, and a record that
  holds one is linear (0003 §3.8, D33).
- I3. Every slot of every array holds a value: a fill is always given;
  there is no `Maybe` of an element.
- I4. An `Array` is never written after it is built. An `LArray`'s
  backing is written only by `write`, in place, and no older version of
  it is read again.
- I5. The extents are held once, in the value: no element count,
  capacity or backing length is stored beside them, and none is read
  (D37).
- I6. Every fold means its left fold in index order (0003 §6, D15), and
  every function applied per index runs in row-major order.

### 3. `Array` (package `mlir-array`, file `libs/mlir-array/Array.idr`)

```idris
module Array

import public Array.Core
import public Data.Zippable
import Data.Nat
import Data.So

%default total

export infixl 10 !?

export
scalar : a -> Scalar a

export
fill : Extents s -> a -> Array s a

export
reduce : (b -> a -> b) -> b -> Array (f :< n) a -> Array f b

export
checkIndex : (n : Nat) -> Nat -> Maybe (Fin n)

export
(!?) : Array s a -> SnocList Integer -> Maybe a

export
Functor (Array s)

export
Foldable (Array s)

export
Zippable (Array s)
```

Plain code over §2.3, compiled as written; nothing here opens a
constructor.
- `scalar v = fill [<] v`; `fill e v = tabulate e (const v)`;
  `reduce g z x = foldLast g (fill frame z) x`, the frame the extents of
  `x` without the last axis.
- `checkIndex n i` is `Just` the `Fin` with value `i` when `i < n`, else
  `Nothing`: one comparison (`choose (i < n)`) and `natToFinLt` under the
  erased proof. It costs one comparison only because C20 makes
  `Data.Fin.natToFinLT` the identity on its natural.
- `x !? is` is `Nothing` when the rank of `is` differs from `x`'s, or a
  coordinate is negative or not below its extent; else the element.
- `map f x = tabulate (shape x) (\i => f (x !! i))`.
- `Foldable`: `foldl g z x` is the left fold in row-major order, by
  `foldLast` over `x` reshaped to `[<volume (shape x)]` from `scalar z`,
  read at `[<]`; `foldMap f` is the left fold with `<+>` from `neutral`,
  so the Prelude's `sum` and `product` (`concat @{Additive}`,
  `Prelude/Interfaces.idr:408-420`) add from the left in index order;
  `toList` is the elements in row-major order (`foldl` into a snoc list);
  `foldr` is the list's right fold over `toList`; `null x` is
  `volume (shape x) == 0`.
- `Zippable`: `zipWith g x y = tabulate (shape x) (\i => g (x !! i) (y !!
  i))`, at one shape; `unzipWith g x = (map (fst . g) x, map (snd . g)
  x)`; the other methods are base's defaults.

Stage 1 has exactly this vocabulary. `Traversable`, `Show`, the numeric
hints of D5 and the rest of §3.5's vocabulary come with the later stages
whose proofs use them.

### 4. `Linear.Vec` (package `mlir-array`, file `libs/mlir-array/Linear/Vec.idr`)

```idris
module Linear.Vec

import Array
import Data.Nat
import Data.So
import Linear.Notation

%default total

export
data Vec : Type -> Type

export
withVec : (n : Nat) -> a -> (1 _ : (1 _ : Vec a) -> !* b) -> !* b

export
size : (1 _ : Vec a) -> Res Nat (const (Vec a))

export
capacity : (1 _ : Vec a) -> Res Nat (const (Vec a))

export
read : (1 _ : Vec a) -> Nat -> Res a (const (Vec a))

export
write : (1 _ : Vec a) -> Nat -> a -> Vec a

export
push : (1 _ : Vec a) -> a -> Vec a

export
pop : (1 _ : Vec a) -> Res (Maybe a) (const (Vec a))

export
reserve : (1 _ : Vec a) -> Nat -> a -> Vec a

export
freeze : (1 _ : Vec a) -> !* (n : Nat ** Vector n a)
```

Plain code over `Array.Core`'s linear half, compiled as written. The
private constructor is
`MkVec : {0 cap : Nat} -> (size : Nat) -> (0 fits : LTE size cap) -> (1 cells : LArray [<cap] a) -> Vec a`:
the capacity is the array's extent, read with `lshape`, never stored
(I5). Meanings:
- `withVec n v k`: `k`'s result, `k` given a vector of `n` elements, each
  `v`, of capacity `n`; the continuation is linear and the result
  unrestricted, as `withArray`'s.
- `size`, `capacity`: the element count and the extent, the vector back.
- `read v i`, `write v i x`: the element at `i`, or the vector with `x`
  there, in place, for `i < size`; any other `i` consumes the vector and
  ends the program with `assert_total (idris_crash "array index out of
  bounds")`, base's own idiom (`Data/Buffer.idr:321`), which needs the
  package trusted (C20).
- `push v x`: `x` after the last element; in place while `size <
  capacity`, else the cells grow to `max (size + 1) (max 4 (2 *
  capacity))` slots, every new one holding `x` (the rule of the deleted
  module, `Linear/Array.idr:168-173`, and 0003 §3.8's doubling: `n`
  pushes copy fewer than `2n` elements).
- `pop v`: the last element taken off, or `Nothing` when empty; the
  capacity stays.
- `reserve v k x`: unchanged when `k <= capacity - size`; else the cells
  grow to `max (size + k) (max 4 (2 * capacity))` slots, the new ones
  holding `x`.
- `freeze v`: the `size` elements, frozen, with their count.
Every `LTE` the record carries is erased; no run-time `Dec` is computed.

### 5. The fork's table (file `compiler/idris/src/Libraries/Data/Table.idr`)

```idris
module Libraries.Data.Table

import Data.IOArray
import Data.IORef

%default total

export
Table : Type -> Type
Table a = IORef (IOArray a)

export
newTable : HasIO io => Int -> io (Table a)

export
lookupSlot : HasIO io => Int -> Table a -> io (Maybe a)

export
claimSlot : HasIO io => Int -> Table a -> io ()

export
setSlot : HasIO io => Int -> a -> Table a -> io ()
```

On base's `Data.IOArray` (0003 D38): mutation in program order of a
table the world orders, held in one `IORef` of its own. The backing's
length is the capacity; an unwritten slot reads `Nothing`, so the table
keeps no count beside the context's own `nextEntry`. `newTable n` has
room for `max 0 n` slots; `lookupSlot i` is the slot, `Nothing` for an
index never written; `claimSlot i` (with `i` at most one past every slot
claimed before) grows the backing, when `i` is past it, to `max (i + 1)
(max 4 (2 * capacity))` by `newArrayCopy`, so claiming `n` slots copies
fewer than `2n` entries; `setSlot i x` writes a claimed slot. It imports
nothing of `libs/`. Its callers, `Core/Context.idr:53, 99, 109, 115`, hold
it as `content : Table ContextEntry` (`Core/Context/Context.idr:401`) and
call it under `coreLift`; those files and the fork's `.ipkg` are owned by
no lane, and U13's handoff gives their edits.

### 6. What a consumer may not assume

- That an `Array` or `LArray` of rank 1 is a `List`, a `Vect` or base's
  `IOArray`: it is none of them, and `Vect n a` stays a list (AGENTS.md:
  indexed vectors do not imply contiguous storage).
- That a quantity-1 binder of a plain `Array` owns its buffer: only
  `LArray` is born fresh (I2); a linear binder does not imply unique
  ownership.
- That an extent at quantity 0 is a constant: it is the value's own,
  read with `shape` or `lshape`.
- Any name in `Array.Core` beyond §2, or in `Array` beyond §3.
