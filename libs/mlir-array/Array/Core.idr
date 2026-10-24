-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Arrays whose shape is in their type: the shapes, the two array types
||| and the handle a linear array is frozen behind, and the generating set
||| every other array function is written over.
|||
||| An array is a shape and an element at every index of it, in row-major
||| order. A shape is a snoc list of the axes' lengths, outermost first, so
||| that a function on the trailing cells finds its frame by unification.
||| An index holds a `Fin` per axis, so every index is inside its array by
||| type and a read checks nothing.
|||
||| idris-mlir writes every call of a function of the generating set as the
||| tensor operation of its meaning. The functions the compiler's own code
||| reaches have a body over base's primitive arrays: that body is their
||| one meaning, which both hosts run, and the operation idris-mlir writes
||| in its place computes the same. The rest have no body: only programs
||| idris-mlir compiles reach them, and the operation is their meaning.
module Array.Core

import public Data.Fin
import Data.IOArray.Prims
import Data.Nat
import Data.So
import Linear.Notation

%default total

export infixl 10 !!

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| The lengths of an array's axes, outermost first.
public export
Shape : Type
Shape = SnocList Nat

||| The number of elements of an array of a shape: the product of its
||| lengths, 1 for a scalar.
public export
count : Shape -> Nat
count [<] = 1
count (s :< n) = count s * n

namespace Extents
  ||| A shape at run time. Its lengths are its index's, so a value of it is
  ||| the shape itself and cannot disagree with it.
  public export
  data Extents : Shape -> Type where
    Lin : Extents [<]
    (:<) : Extents s -> (n : Nat) -> Extents (s :< n)

namespace Index
  ||| A position in a shape: one `Fin` per axis, each below its length.
  public export
  data Index : Shape -> Type where
    Lin : Index [<]
    (:<) : Index s -> Fin n -> Index (s :< n)

namespace Cell
  ||| The form of an array's cells: how many trailing axes they take, their
  ||| lengths left to unification.
  public export
  data Cell : Shape -> Type where
    Lin : Cell [<]
    (:<) : Cell s -> (0 n : Nat) -> Cell (s :< n)

||| The number of elements of an array of these extents, at run time.
export
volume : Extents s -> Nat
volume [<] = 1
volume (e :< n) = volume e * n

||| The run-time count is the count of the shape.
export
volumeIsCount : (e : Extents s) -> volume e = count s
volumeIsCount [<] = Refl
volumeIsCount (e :< n) = cong (* n) (volumeIsCount e)

------------------------------------------------------------------------------
-- Positions
------------------------------------------------------------------------------

||| A product of successors is one.
0 bothOccupied : IsSucc a -> IsSucc b -> IsSucc (a * b)
bothOccupied ItIsSucc ItIsSucc = ItIsSucc

||| An axis that has a position has a length that is a successor.
0 positioned : Fin n -> IsSucc n
positioned FZ = ItIsSucc
positioned (FS _) = ItIsSucc

||| Extents that have an index have an element.
0 occupied : (e : Extents s) -> Index s -> IsSucc (volume e)
occupied [<] [<] = ItIsSucc
occupied (e :< _) (p :< j) = bothOccupied (occupied e p) (positioned j)

||| Where the elements of extents start: nowhere, since some axis has no
||| position, or at the first index, every axis at its first position.
data Start : Extents s -> Type where
  Elementless : (0 empty : volume e = Z) -> Start e
  From : {0 e : Extents s} -> Index s -> Start e

||| Where the elements of extents start, read off their lengths.
start : (e : Extents s) -> Start e
start [<] = From [<]
start (e :< Z) = Elementless (multZeroRightZero (volume e))
start (e :< S m) = case start e of
  Elementless empty => Elementless (cong (* S m) empty)
  From i => From (i :< FZ)

||| The index after `i` in row-major order, the last axis fastest; after the
||| last index, the first.
following : Extents s -> Index s -> Index s
following [<] [<] = [<]
following (e :< Z) (_ :< j) = absurd j
following (e :< S m) (p :< j) = case choose (S (finToNat j) < S m) of
  Left more => p :< natToFinLt (S (finToNat j)) @{more}
  Right _ => following e p :< FZ

||| The position of an index among the elements of extents, in row-major
||| order: the natural it is, as the extents and the index hold their
||| lengths and positions.
position : Extents s -> Index s -> Nat
position [<] [<] = 0
position (e :< n) (p :< j) = position e p * n + finToNat j

||| The slot of an index: its position, as the offset the slots take.
||| Computed as a natural and cast once: the stock host adds and multiplies
||| naturals as its integers are, where every step on an `Int` also wraps
||| it to 64 bits.
offset : Extents s -> Index s -> Int
offset e i = cast (position e i)

------------------------------------------------------------------------------
-- The two array types
------------------------------------------------------------------------------

-- Their constructors are this module's alone, so no other module can take
-- an array apart or build one but through the generating set. An array of
-- no element holds no slots: base's primitive array is made with an
-- element to fill it, and an array with no index has none to give.

||| An array: its extents and an element at every index. Never written
||| after it is built.
export
data Array : (0 s : Shape) -> Type -> Type where
  ||| No element: some axis has no position, so no index reads one.
  Empty : (e : Extents s) -> (0 empty : volume e = Z) -> Array s a
  ||| An element in each slot, the slots in row-major order.
  Stored : (e : Extents s) -> (slots : ArrayData a) -> Array s a

||| A linear array: its extents and an element at every index, written in
||| place. One is only ever given at quantity 1, fresh, to a continuation
||| that returns an unrestricted value, so no two references to one exist,
||| and no old version of it is read again; it leaves only by `freeze`. It
||| holds an array whose slots no other reference reaches while it lives,
||| which is what lets it write them.
export
data LArray : (0 s : Shape) -> Type -> Type where
  Writing : (elements : Array s a) -> LArray s a

||| An array of no axes: one element.
public export
Scalar : Type -> Type
Scalar = Array [<]

||| An array of one axis of length `n`.
public export
Vector : Nat -> Type -> Type
Vector n = Array [<n]

||| An array of two axes, `m` rows of `n`.
public export
Matrix : Nat -> Nat -> Type -> Type
Matrix m n = Array [<m, n]

------------------------------------------------------------------------------
-- The generating set
------------------------------------------------------------------------------

-- A body below runs each effect on base's primitive array inside the one
-- action whose result it returns, so the value cannot be had without the
-- effect: no effect sits in a binding or an argument whose value nothing
-- uses, which the stock host's inliner would drop.

||| The extents the array was built with.
export
shape : Array s a -> Extents s
shape (Empty e _) = e
shape (Stored e _) = e

||| `f` at each of the `left` indices after `i` in row-major order, put in
||| the slots from `slot` on.
storeAfter : ArrayData a -> Extents s -> (Index s -> a) -> Index s -> (slot : Int) -> (left : Nat) -> IO ()
storeAfter slots e f i slot Z = pure ()
storeAfter slots e f i slot (S left) = do
  let next = following e i
  primIO (prim__arraySet slots slot (f next))
  storeAfter slots e f next (slot + 1) left

||| `f` at every index in row-major order, in fresh slots: the first
||| index's element fills them as they are made, and each later index's
||| replaces its own.
storeFrom : Extents s -> (Index s -> a) -> Index s -> IO (Array s a)
storeFrom e f i = do
  let n = volume e
  slots <- primIO (prim__newArray (cast n) (f i))
  storeAfter slots e f i 1 (pred n)
  pure (Stored e slots)

tabulateFrom : (e : Extents s) -> (Index s -> a) -> Start e -> Array s a
tabulateFrom e f (Elementless empty) = Empty e empty
tabulateFrom e f (From i) = unsafePerformIO (storeFrom e f i)

||| The array whose element at each index is `f` of the index: `f` is
||| applied once at each index, in row-major order (the last axis fastest),
||| and never when the shape has no element.
export
tabulate : Extents s -> (Index s -> a) -> Array s a
tabulate e f = tabulateFrom e f (start e)

||| The element at an index. The index is inside the array by its type, so
||| nothing is checked, and an array with no element has no index.
export
(!!) : Array s a -> Index s -> a
Empty e empty !! i = void (uninhabited (replace {p = IsSucc} empty (occupied e i)))
Stored e slots !! i = unsafePerformIO (primIO (prim__arrayGet slots (offset e i)))

||| The left fold from `acc` over the elements of `x` under `q` along the
||| last axis, from position `done`, `left` of them still to come.
foldAxis : (b -> a -> b) -> Array (f :< n) a -> Index f -> (done, left : Nat) -> (0 _ : done + left = n) -> b -> b
foldAxis g x q done Z _ acc = acc
foldAxis g x q done (S left) fits acc =
  let 0 next = trans (plusSuccRightSucc done left) fits in
  foldAxis g x q (S done) left next
    (g acc (x !! (q :< natToFinLT done {prf = replace {p = LTE (S done)} next (lteAddRight (S done))})))

foldFrame : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Extents (f :< n) -> Array f b
foldFrame g z x (fe :< len) = tabulate fe (\q => foldAxis g x q 0 len Refl (z !! q))

||| For each index `p` of the frame, in row-major order, the left fold over
||| the last axis from the frame's element of `z`:
||| `g (... (g (z !! p) (x !! (p :< 0))) ...) (x !! (p :< n - 1))`.
export
foldLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b
foldLast g z x = foldFrame g z x (shape x)

||| At `p :< j`, the left fold from `z !! p` over `x !! (p :< 0)` to
||| `x !! (p :< j)`, inclusive.
export %extern
scanLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array (f :< n) b

||| At each index `p` of the frame, the cell of `x` under `p`, its shape the
||| trailing axes the cell's form takes.
export %extern
nest : Cell c -> Array (f ++ c) a -> Array f (Array c a)

||| The cells put back together: the inverse of `nest`. The cells' extents
||| are given, so that an empty frame, which has no cell to read them
||| from, still has a shape.
export %extern
merge : Extents c -> Array f (Array c a) -> Array (f ++ c) a

||| The same elements in the same row-major order, at other extents of the
||| same count: the same slots.
export
reshape : Extents t -> {auto 0 same : count s = count t} -> Array s a -> Array t a
reshape et @{same} (Empty e empty) =
  Empty et (trans (volumeIsCount et) (trans (sym same) (trans (sym (volumeIsCount e)) empty)))
reshape et (Stored e slots) = Stored et slots

||| The last two axes swapped: at `p :< j :< i`, the element of `x` at
||| `p :< i :< j`. With `nest` and `merge` it moves any axis to the end,
||| where `take`, `drop`, `(++)`, `pad` and the folds act.
export %extern
transpose : Array (f :< m :< n) a -> Array (f :< n :< m) a

||| The first `k` positions of the last axis: at `p :< j`, `x !! (p :< j)`.
export %extern
take : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< k) a

||| The positions of the last axis after the first `k`: at `p :< j`,
||| `x !! (p :< k + j)`.
export %extern
drop : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< minus n k) a

||| The two arrays one after the other along the last axis: at `p :< j`,
||| `x !! (p :< j)` for `j < n`, else `y !! (p :< j - n)`.
export %extern
(++) : Array (f :< n) a -> Array (f :< m) a -> Array (f :< n + m) a

||| `lo` copies of `v`, the elements, then `hi` copies of `v`, along the last
||| axis.
export %extern
pad : (lo, hi : Nat) -> a -> Array (f :< n) a -> Array (f :< lo + n + hi) a

||| A new array equal to `x` but `v` at `i`; `x` itself is unchanged.
export %extern
update : Array s a -> Index s -> a -> Array s a

------------------------------------------------------------------------------
-- Linear arrays
------------------------------------------------------------------------------

||| The elements of the slots from `slot` on, `left` of them, copied into
||| the same slots of `target`.
copyAfter : (source, target : ArrayData a) -> (slot : Int) -> (left : Nat) -> IO ()
copyAfter source target slot Z = pure ()
copyAfter source target slot (S left) = do
  x <- primIO (prim__arrayGet source slot)
  primIO (prim__arraySet target slot x)
  copyAfter source target (slot + 1) left

||| The elements in fresh slots: the first fills them as they are made, and
||| each later one replaces its own.
copySlots : Extents s -> ArrayData a -> IO (Array s a)
copySlots e slots = do
  let n = volume e
  leading <- primIO (prim__arrayGet slots 0)
  fresh <- primIO (prim__newArray (cast n) leading)
  copyAfter slots fresh 1 (pred n)
  pure (Stored e fresh)

||| The array's elements in slots of their own.
copied : Array s a -> Array s a
copied (Empty e empty) = Empty e empty
copied (Stored e slots) = unsafePerformIO (copySlots e slots)

||| `v` put in a slot, in place, and the array that holds it: the array is
||| the write's result, so nothing reads it before the write.
writeSlot : Extents s -> ArrayData a -> (slot : Int) -> a -> IO (Array s a)
writeSlot e slots slot v = do
  primIO (prim__arraySet slots slot v)
  pure (Stored e slots)

||| `v` put in the slot of `i`, in place.
overwrite : Array s a -> Index s -> a -> Array s a
overwrite (Empty e empty) i v = void (uninhabited (replace {p = IsSucc} empty (occupied e i)))
overwrite (Stored e slots) i v = unsafePerformIO (writeSlot e slots (offset e i) v)

-- Declared outside its namespace, as `LArray` is, so that its constructor
-- stays this module's alone yet both `Frozen.read` and `LArray.withFrozen`
-- reach it.

||| A linear array's elements frozen in place, behind a handle used once
||| in the region `r`: nothing writes them while the handle lives, so a
||| read through it is a value of the handle and the index, and when the
||| handle is given back they are the linear array's again, in the same
||| slots. Only `LArray.withFrozen` makes one, for a region fresh to its
||| continuation, and only it ends one, so neither the handle nor the
||| array it holds outlives that continuation; what leaves it is
||| elements.
export
data Frozen : (0 r : Type) -> (0 s : Shape) -> Type -> Type where
  Held : (elements : Array s a) -> Frozen r s a

namespace Frozen
  ||| The element at an index, and the handle given back.
  export
  read : (1 _ : Frozen r s a) -> Index s -> Res a (const (Frozen r s a))
  read (Held x) i = (x !! i) # Held x

-- A function on linear arrays whose name a function on arrays or on
-- another type also has is told apart by this namespace, as Prelude tells
-- a list's from a snoc list's.
namespace LArray
  ||| The result of `k`, given a fresh linear array of the extents, every
  ||| element `v`. The continuation is used once, so it may hold other
  ||| linear values, and its result is unrestricted, so that the array
  ||| cannot leave it but by `freeze` and one `withArray` nests in
  ||| another's continuation: a program holds several linear arrays at
  ||| once. Every slot holds a value from the start, an empty array's
  ||| included, so no slot is ever unset.
  export %extern
  withArray : Extents s -> a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b

  ||| The element at an index, and the array given back unchanged.
  export
  read : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))
  read (Writing x) i = (x !! i) # Writing x

  ||| The array with `v` at `i`, written in place. No old version of the
  ||| array is read again, so writing in place is the value's meaning.
  export
  write : (1 _ : LArray s a) -> Index s -> a -> LArray s a
  write (Writing x) i v = Writing (overwrite x i v)

  ||| The linear array's elements as an array, with no copy: the linear
  ||| array is consumed, so nothing writes them again.
  export
  freeze : (1 _ : LArray s a) -> !* (Array s a)
  freeze (Writing x) = MkBang x

  ||| The result of `k`, given a fresh linear array with the array's
  ||| elements, as `withArray` gives one; the array is unchanged.
  export
  thaw : Array s a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b
  thaw x k = k (Writing (copied x))

  ||| The handle given back, its elements the linear array's again.
  thawed : (1 _ : Res b (const (Frozen r s a))) -> Res b (const (LArray s a))
  thawed (y # Held x) = y # Writing x

  ||| What `k` returns, given the linear array's elements frozen in place
  ||| behind a handle of a fresh region, and the linear array back with
  ||| them, thawed in place: no copy either way. The handle is the one way
  ||| to the elements and `k` gives it back, and `k`'s result cannot name
  ||| the region, so when the slots are written again nothing but the
  ||| linear array reaches them.
  export
  withFrozen : (1 _ : LArray s a) ->
               (1 k : {0 r : Type} -> (1 _ : Frozen r s a) -> Res b (const (Frozen r s a))) ->
               Res b (const (LArray s a))
  withFrozen (Writing x) k = thawed (k {r = ()} (Held x))

  ||| The extents, and the array given back unchanged.
  export %extern
  shape : (1 _ : LArray s a) -> Res (Extents s) (const (LArray s a))

  ||| A fresh linear array `k` positions longer on the last axis: the old
  ||| elements at their indices and `v` in every new slot. The old array
  ||| is consumed.
  export %extern
  grow : (k : Nat) -> a -> (1 _ : LArray (f :< n) a) -> LArray (f :< n + k) a

------------------------------------------------------------------------------
-- From the world
------------------------------------------------------------------------------

||| The array whose element at each index is the result of `act` at the
||| index: the actions run once each, in row-major order and in the
||| world's order, and none runs when the shape has no element. This is
||| how a value is taken from something the world orders (a buffer, an
||| `IOArray`) once, so that the code that reads it after is pure.
export %extern
tabulateIO : Extents s -> (Index s -> IO a) -> IO (Array s a)
