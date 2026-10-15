-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Arrays whose shape is in their type: the shapes, the two array types,
||| and the generating set every other array function is written over.
|||
||| An array is a shape and an element at every index of it, in row-major
||| order. A shape is a snoc list of the axes' lengths, outermost first, so
||| that a function on the trailing cells finds its frame by unification.
||| An index holds a `Fin` per axis, so every index is inside its array by
||| type and a read checks nothing.
|||
||| The two array types have no constructors and the generating set has no
||| bodies: each function is declared with its meaning, and idris-mlir
||| writes every call of one as the tensor operation of that meaning. Its
||| meaning is held there alone, so no Idris body can come to mean
||| something else; no other backend runs these functions.
module Array.Core

import public Data.Fin
import Data.Nat
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
-- The two array types
------------------------------------------------------------------------------

-- Both are external, as base's arrays of the runtime are: a type with no
-- constructor that no proof may call empty, whose every argument decides
-- an implementation search over it as a data type's do. A plain forward
-- declaration would let the search pick an implementation before the
-- shape is known, and guess the shape.

||| An array: its extents and an element at every index. Never written
||| after it is built. It has no constructor, so no module can take one
||| apart or build one but through the generating set.
export
data Array : (0 s : Shape) -> Type -> Type where [external]

||| A linear array: its extents and an element at every index, written in
||| place. One is only ever given at quantity 1, fresh, to a continuation
||| that returns an unrestricted value, so no two references to one exist,
||| and no old version of it is read again; it leaves only by `freeze`.
export
data LArray : (0 s : Shape) -> Type -> Type where [external]

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

||| The extents the array was built with.
export %extern
shape : Array s a -> Extents s

||| The array whose element at each index is `f` of the index: `f` is
||| applied once at each index, in row-major order (the last axis fastest),
||| and never when the shape has no element.
export %extern
tabulate : Extents s -> (Index s -> a) -> Array s a

||| The element at an index. The index is inside the array by its type, so
||| nothing is checked.
export %extern
(!!) : Array s a -> Index s -> a

||| For each index `p` of the frame, in row-major order, the left fold over
||| the last axis from the frame's element of `z`:
||| `g (... (g (z !! p) (x !! (p :< 0))) ...) (x !! (p :< n - 1))`.
export %extern
foldLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b

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
||| same count.
export %extern
reshape : Extents t -> {auto 0 same : count s = count t} -> Array s a -> Array t a

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
  export %extern
  read : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))

  ||| The array with `v` at `i`, written in place. No old version of the
  ||| array is read again, so writing in place is the value's meaning.
  export %extern
  write : (1 _ : LArray s a) -> Index s -> a -> LArray s a

  ||| The linear array's elements as an array, with no copy: the linear
  ||| array is consumed, so nothing writes them again.
  export %extern
  freeze : (1 _ : LArray s a) -> !* (Array s a)

  ||| The result of `k`, given a fresh linear array with the array's
  ||| elements, as `withArray` gives one; the array is unchanged.
  export %extern
  thaw : Array s a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b

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
