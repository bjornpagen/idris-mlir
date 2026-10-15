-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Arrays whose shape is in their type: the shapes, the two array types,
||| and every function that can see how an array is held.
|||
||| An array is a shape and an element at every index of it, in row-major
||| order. A shape is a snoc list of the axes' lengths, outermost first, so
||| that a function on the trailing cells finds its frame by unification.
||| An index holds a `Fin` per axis, so every index is inside its array by
||| type and a read checks nothing.
|||
||| This module is the only one that names the representation, so that
||| everything else in the library is code over the functions below. Each
||| of them is the meaning of its name: idris-mlir knows them by their
||| qualified names and writes each call in MLIR's tensor operations with
||| that meaning, so none of their bodies is ever compiled there. They are
||| plain Idris over base's array primitives, with no primitive of their
||| own, so they mean the same on every backend that has base's.
module Array.Core

import public Data.Fin
import Data.Fin.Properties
import Data.Fin.Split
import Data.IOArray.Prims
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
-- The representation
------------------------------------------------------------------------------

||| The elements of an array of shape `s`. An empty array has no element to
||| give base's primitive as its fill, so it holds no backing, only the
||| proof that it is empty: an access, which holds an index, refutes that
||| proof, and never tests for it. A non-empty array holds base's array of
||| its `count s` elements in row-major order.
data Cells : (0 s : Shape) -> Type -> Type where
  None : (0 empty : count s = 0) -> Cells s a
  Slots : ArrayData a -> Cells s a

||| An array: its extents and its elements. Never written after it is
||| built. Only this module can build or take apart one.
export
data Array : (0 s : Shape) -> Type -> Type where
  MkArray : Extents s -> Cells s a -> Array s a

||| A linear array: its extents and its elements, written in place. One is
||| only ever given at quantity 1, fresh, to a continuation that returns an
||| unrestricted value, so no two references to one exist, and no old
||| version of it is read again; it leaves only by `freeze`.
export
data LArray : (0 s : Shape) -> Type -> Type where
  MkLArray : Extents s -> Cells s a -> LArray s a

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
-- Indices in row-major order
------------------------------------------------------------------------------

||| Every `Fin n`, in order, counted down from `n` so that each is made in
||| constant time.
fins : (n : Nat) -> List (Fin n)
fins n = go n reflexive []
  where
    go : (k : Nat) -> (0 _ : LTE k n) -> List (Fin n) -> List (Fin n)
    go Z _ acc = acc
    go (S k) fits acc = go k (lteSuccLeft fits) (natToFinLT k :: acc)

||| The indices of a shape in row-major order: none, with the proof that
||| the shape has no element, or the first and then the rest.
data Indices : (0 s : Shape) -> Type where
  NoIndex : (0 empty : count s = 0) -> Indices s
  FirstThen : Index s -> List (Index s) -> Indices s

||| A product with a factor of a successor is a successor, so a product of 0
||| with one has 0 for its other factor.
0 zeroFactor : (x : Nat) -> x * S k = 0 -> x = 0
zeroFactor Z _ = Refl
zeroFactor (S _) Refl impossible

||| The indices of the extents in row-major order, the proof of emptiness
||| read off the extents themselves.
enumerate : (e : Extents s) -> Indices s
enumerate [<] = FirstThen [<] []
enumerate {s = s :< Z} (e :< Z) = NoIndex (multZeroRightZero (count s))
enumerate (e :< S m) = case enumerate e of
  NoIndex empty => NoIndex (rewrite empty in Refl)
  FirstThen i rest =>
    FirstThen (i :< FZ)
      (map (\j => i :< FS j) (fins m) ++ concatMap (\p => map (p :<) (fins (S m))) rest)

||| An index's position in row-major order.
offset : Extents s -> Index s -> Int
offset e i = cast (go e i)
  where
    go : Extents t -> Index t -> Nat
    go [<] [<] = 0
    go (e :< n) (is :< j) = go e is * n + finToNat j

||| An index refutes emptiness: every axis it crosses has a successor
||| length, so its shape's count is a successor.
occupied : Index s -> (0 _ : count s = 0) -> Void
occupied [<] Refl impossible
occupied (is :< FZ) empty = occupied is (zeroFactor _ empty)
occupied (is :< FS _) empty = occupied is (zeroFactor _ empty)

||| The element at an index.
element : Extents s -> Cells s a -> Index s -> a
element e (None empty) i = void (occupied i empty)
element e (Slots d) i = unsafePerformIO (primIO (prim__arrayGet d (offset e i)))

||| The elements `f` gives at every index, each applied once in row-major
||| order: the first index's element is base's fill, and each later index
||| is written once.
build : (e : Extents s) -> (Index s -> a) -> Cells s a
build e f = case enumerate e of
  NoIndex empty => None empty
  FirstThen i rest => Slots (unsafePerformIO (do
    d <- primIO (prim__newArray (cast (volume e)) (f i))
    traverse_ (\j => primIO (prim__arraySet d (offset e j) (f j))) rest
    pure d))

||| A position below `k` as a position below `n`, for `k` at most `n`: the
||| same natural, the bound erased.
widen : Fin k -> (0 _ : LTE k n) -> Fin n
widen j fits = natToFinLT (finToNat j) {prf = transitive (elemSmallerThanBound j) fits}

||| Two indices of one shape are equal when every coordinate is.
sameIndex : Index s -> Index s -> Bool
sameIndex [<] [<] = True
sameIndex (is :< i) (js :< j) = finToNat i == finToNat j && sameIndex is js

||| The extents of a frame and of its cells, from the extents of the whole.
splitExtents : Cell c -> Extents (f ++ c) -> (Extents f, Extents c)
splitExtents [<] e = (e, [<])
splitExtents (c :< _) (e :< n) = let (fe, ce) = splitExtents c e in (fe, ce :< n)

||| The extents of a frame and its cells together.
joinExtents : Extents f -> Extents c -> Extents (f ++ c)
joinExtents fe [<] = fe
joinExtents fe (ce :< n) = joinExtents fe ce :< n

||| An index into the frame and one into the cell, as one index.
joinIndex : Cell c -> Index f -> Index c -> Index (f ++ c)
joinIndex [<] p [<] = p
joinIndex (c :< _) p (q :< j) = joinIndex c p q :< j

||| An index of the whole, as one into the frame and one into the cell.
splitIndex : Extents c -> Index (f ++ c) -> (Index f, Index c)
splitIndex [<] i = (i, [<])
splitIndex (ce :< _) (i :< j) = let (p, q) = splitIndex ce i in (p, q :< j)

------------------------------------------------------------------------------
-- The generating set
------------------------------------------------------------------------------

||| The extents of an array.
export
shape : Array s a -> Extents s
shape (MkArray e _) = e

||| The array whose element at each index is `f` of the index: `f` is
||| applied once at each index, in row-major order, and never when the
||| shape has no element.
export
tabulate : Extents s -> (Index s -> a) -> Array s a
tabulate e f = MkArray e (build e f)

||| The element at an index. The index is inside the array by its type, so
||| nothing is checked.
export
(!!) : Array s a -> Index s -> a
(!!) (MkArray e c) i = element e c i

||| For each index of the frame, in row-major order, the left fold over the
||| last axis from the frame's element of `z`, in index order.
export
foldLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array f b
foldLast g z x = case shape x of
  fe :< n => tabulate fe (\p => foldl (\acc, j => g acc (x !! (p :< j))) (z !! p) (fins n))

||| At each index of the frame and each position `j` of the last axis, the
||| left fold from the frame's element of `z` over the last axis up to and
||| including `j`.
export
scanLast : (b -> a -> b) -> Array f b -> Array (f :< n) a -> Array (f :< n) b
scanLast g z x = case shape x of
  fe :< n => tabulate (fe :< n) (\(p :< j) =>
    foldl (\acc, k => g acc (x !! (p :< k))) (z !! p) (upTo j))
  where
    upTo : {m : Nat} -> Fin m -> List (Fin m)
    upTo j = filter (\k => finToNat k <= finToNat j) (fins m)

||| The cells of the given form, at each index of the frame.
export
nest : Cell c -> Array (f ++ c) a -> Array f (Array c a)
nest c x = let (fe, ce) = splitExtents c (shape x) in
           tabulate fe (\p => tabulate ce (\q => x !! joinIndex c p q))

||| The cells put back together: the inverse of `nest`. The cells' extents
||| are given, so that an empty frame, which has no cell to read them
||| from, still has a shape.
export
merge : Extents c -> Array f (Array c a) -> Array (f ++ c) a
merge ce x = tabulate (joinExtents (shape x) ce) (\i =>
  let (p, q) = splitIndex ce i in (x !! p) !! q)

||| The same elements in the same row-major order, at other extents of the
||| same count: the elements are shared, since their order does not change.
export
reshape : Extents t -> {auto 0 same : count s = count t} -> Array s a -> Array t a
reshape t (MkArray _ (None empty)) = MkArray t (None (trans (sym same) empty))
reshape t (MkArray _ (Slots d)) = MkArray t (Slots d)

||| The first `k` positions of the last axis.
export
take : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< k) a
take k x = case shape x of
  fe :< _ => tabulate (fe :< k) (\(p :< j) => x !! (p :< widen j fits))

||| The positions of the last axis after the first `k`.
export
drop : (k : Nat) -> {auto 0 fits : LTE k n} -> Array (f :< n) a -> Array (f :< minus n k) a
drop k x = case shape x of
  fe :< n =>
    let 0 back = trans (plusCommutative k (minus n k)) (plusMinusLte k n fits) in
    tabulate (fe :< minus n k) (\(p :< j) => x !! (p :< replace {p = Fin} back (shift k j)))

||| The two arrays one after the other along the last axis.
export
(++) : Array (f :< n) a -> Array (f :< m) a -> Array (f :< n + m) a
x ++ y = case (shape x, shape y) of
  (fe :< n, _ :< m) => tabulate (fe :< n + m) (\(p :< j) => case splitSum j of
    Left i => x !! (p :< i)
    Right i => y !! (p :< i))

||| `lo` copies of `v`, the elements, then `hi` copies of `v`, along the last
||| axis.
export
pad : (lo, hi : Nat) -> a -> Array (f :< n) a -> Array (f :< lo + n + hi) a
pad lo hi v x = case shape x of
  fe :< n => tabulate (fe :< lo + n + hi) (\(p :< j) => case splitSum {m = lo + n} j of
    Left i => case splitSum {m = lo} i of
      Left _ => v
      Right k => x !! (p :< k)
    Right _ => v)

||| The array with `v` at `i` and every other element as it was; the
||| argument itself is unchanged.
export
update : Array s a -> Index s -> a -> Array s a
update x i v = tabulate (shape x) (\k => if sameIndex k i then v else x !! k)

------------------------------------------------------------------------------
-- Linear arrays
------------------------------------------------------------------------------

||| A fresh linear array of the extents, every element `v`, given to a
||| continuation that returns an unrestricted value, so that the array
||| cannot leave it but by `freeze`. The continuation is used once, so it
||| may hold other linear values, and the result stays unrestricted, so
||| that one `withArray` nests in another's continuation and a program can
||| hold several linear arrays at once.
export
withArray : Extents s -> a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b
withArray e v k = k (MkLArray e (build e (const v)))

||| The element at an index, with the array given back.
export
read : (1 _ : LArray s a) -> Index s -> Res a (const (LArray s a))
read (MkLArray e c) i = element e c i # MkLArray e c

||| The array with `v` at `i`, written in place. The array given back comes
||| out of the action, so that the write is never dropped as an unused
||| value; no old version of the array is read again, so writing in place
||| is the value's meaning on every backend.
export
write : (1 _ : LArray s a) -> Index s -> a -> LArray s a
write (MkLArray e (None empty)) i v = void (occupied i empty)
write (MkLArray e (Slots d)) i v =
  unsafePerformIO (do primIO (prim__arraySet d (offset e i) v); pure (MkLArray e (Slots d)))

||| The linear array's elements as an array, with no copy: the linear
||| array is consumed, so nothing writes them again.
export
freeze : (1 _ : LArray s a) -> !* (Array s a)
freeze (MkLArray e c) = MkBang (MkArray e c)

||| A fresh linear array with the array's elements, given to a
||| continuation as `withArray` gives one; the array is unchanged.
export
thaw : Array s a -> (1 _ : (1 _ : LArray s a) -> !* b) -> !* b
thaw x k = k (MkLArray (shape x) (build (shape x) (x !!)))

||| The extents of a linear array, with the array given back.
export
lshape : (1 _ : LArray s a) -> Res (Extents s) (const (LArray s a))
lshape (MkLArray e c) = e # MkLArray e c

||| A fresh linear array `k` positions longer on the last axis: the old
||| elements at their indices and `v` in every new position. The old array
||| is consumed.
export
grow : (k : Nat) -> a -> (1 _ : LArray (f :< n) a) -> LArray (f :< n + k) a
grow k v (MkLArray (fe :< n) c) =
  MkLArray (fe :< n + k) (build (fe :< n + k) (\(p :< j) => case splitSum j of
    Left i => element (fe :< n) c (p :< i)
    Right _ => v))

------------------------------------------------------------------------------
-- From the world
------------------------------------------------------------------------------

||| The array whose element at each index is the result of `act` at the
||| index: the actions run once each, in row-major order and in the
||| world's order, and none runs when the shape has no element. This is
||| how a value is taken from something the world orders (a buffer, an
||| `IOArray`) once, so that the code that reads it after is pure.
export
tabulateIO : Extents s -> (Index s -> IO a) -> IO (Array s a)
tabulateIO e act = case enumerate e of
  NoIndex empty => pure (MkArray e (None empty))
  FirstThen i rest => do
    first <- act i
    d <- primIO (prim__newArray (cast (volume e)) first)
    traverse_ (\j => do x <- act j; primIO (prim__arraySet d (offset e j) x)) rest
    pure (MkArray e (Slots d))
