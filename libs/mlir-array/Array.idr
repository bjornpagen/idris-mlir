-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Typed arrays: `Array.Core`'s types and generating set, and the library
||| code over them.
|||
||| Nothing here sees how an array is held: every definition is written
||| over the generating set, and compiles as written to what those
||| functions become. Every fold here but `foldr`, the right fold its name
||| asks for, means its left fold in index order, so a sum of floats adds
||| in the order a program reads, on every target.
module Array

import public Array.Core
import public Data.Zippable
import Data.Nat
import Data.So

%default total

export infixl 10 !?

||| The array of the extents with every element `v`.
export
fill : Extents s -> a -> Array s a
fill e v = tabulate e (const v)

||| The array of one element.
export
scalar : a -> Scalar a
scalar v = fill [<] v

||| The extents of the frame: every axis but the last.
frame : Extents (f :< n) -> Extents f
frame (fe :< _) = fe

||| The left fold over the last axis, from `z` at every index of the frame.
export
reduce : (b -> a -> b) -> b -> Array (f :< n) a -> Array f b
reduce g z x = foldLast g (fill (frame (shape x)) z) x

||| `i` as a position below `n`, when it is one: one comparison, the
||| program's own, its proof erased.
export
checkIndex : (n : Nat) -> Nat -> Maybe (Fin n)
checkIndex n i = case choose (i < n) of
  Left below => Just (natToFinLt i @{below})
  Right _ => Nothing

||| The element at coordinates computed from integers: `Nothing` for a
||| negative coordinate, one past its extent, or coordinates of another
||| rank.
export
(!?) : Array s a -> SnocList Integer -> Maybe a
x !? is = map (x !!) (index (shape x) is)
  where
    index : Extents t -> SnocList Integer -> Maybe (Index t)
    index [<] [<] = Just [<]
    index (e :< n) (is :< i) =
      if i < 0 then Nothing
      else case (index e is, checkIndex n (cast i)) of
        (Just p, Just j) => Just (p :< j)
        _ => Nothing
    index _ _ = Nothing

||| An array of any shape has as many elements as one axis of its volume,
||| so it can be read as that axis, in row-major order.
0 counted : (e : Extents s) -> count s = count [<volume e]
counted e = sym (trans (multOneLeftNeutral (volume e)) (volumeIsCount e))

||| The right fold of the first `k` elements of `v` onto `acc`, the last of
||| them combined first: a list's right fold of the elements, without the
||| list, in a loop that keeps nothing but the accumulator.
foldBack : (a -> b -> b) -> Vector n a -> (k : Nat) -> (0 _ : LTE k n) -> b -> b
foldBack g v Z _ acc = acc
foldBack g v (S k) fits acc = foldBack g v k (lteSuccLeft fits) (g (v !! [<natToFinLT k {prf = fits}]) acc)

export
Functor (Array s) where
  map f x = tabulate (shape x) (\i => f (x !! i))

||| Folds in row-major order. `foldMap` is the left fold, not the default
||| right one, so the Prelude's `sum` and `product` combine from the left
||| as `reduce` does.
export
Foldable (Array s) where
  foldl g z x =
    let e = shape x in foldLast g (scalar z) (reshape [<volume e] @{counted e} x) !! [<]
  foldr g z x =
    let e = shape x in foldBack g (reshape [<volume e] @{counted e} x) (volume e) reflexive z
  toList x = foldl (:<) [<] x <>> []
  null x = volume (shape x) == 0
  foldMap f x = foldl (\acc, v => acc <+> f v) neutral x

||| Arrays of one shape, combined element by element. `unzipWith` applies
||| `f` once at each index and takes both arrays from its results.
export
Zippable (Array s) where
  zipWith f x y = tabulate (shape x) (\i => f (x !! i) (y !! i))
  unzipWith f x = let ys = map f x in (map fst ys, map snd ys)

------------------------------------------------------------------------------
-- Linear arrays, element by element
------------------------------------------------------------------------------

||| `step` at every position of an axis of `n`, in order, each given the
||| state the one before it returned. The state is linear, so it may be a
||| linear array each step reads or writes in place.
along : (n : Nat) -> ((1 _ : t) -> Fin n -> t) -> (1 _ : t) -> t
along n step st = go Z n Refl st
  where
    -- `done` positions are visited and `left` remain; the position visited
    -- next is `done`, below `n` because one remains.
    go : (done, left : Nat) -> (0 _ : done + left = n) -> (1 _ : t) -> t
    go done Z _ st = st
    go done (S left) prf st =
      let 0 next = trans (plusSuccRightSucc done left) prf in
      go (S done) left next
        (step st (natToFinLT done {prf = replace {p = LTE (S done)} next (lteAddRight (S done))}))

||| `step` at every index of the extents, in row-major order with the last
||| axis fastest, each given the state the one before it returned.
visit : Extents s -> ((1 _ : t) -> Index s -> t) -> (1 _ : t) -> t
visit [<] step st = step st [<]
visit (e :< n) step st = visit e (\st, p => along n (\st, j => step st (p :< j)) st) st

-- Each step below takes its state apart in a top-level clause of its own,
-- never in the lambda `visit` runs: `#` names both `Res`'s constructor and
-- `LPair`'s, and the stock host is slow to elaborate a match on such a name
-- inside a lambda's delayed case block, where a clause with a signature
-- settles it at once.
namespace LArray
  ||| `f` of the element read, written back where it was read.
  rewriteAt : (a -> a) -> Index s -> (1 _ : Res a (const (LArray s a))) -> LArray s a
  rewriteAt f i (x # arr) = LArray.write arr i (f x)

  mapOver : (a -> a) -> (1 _ : Res (Extents s) (const (LArray s a))) -> LArray s a
  mapOver f (e # arr) = visit e (\arr, i => rewriteAt f i (LArray.read arr i)) arr

  ||| The array with each element replaced by `f` of it, in place, in
  ||| row-major order.
  export
  map : (a -> a) -> (1 _ : LArray s a) -> LArray s a
  map f arr = mapOver f (LArray.shape arr)

  ||| The accumulator combined with the element read, the array given back.
  foldRead : (b -> a -> b) -> b -> (1 _ : Res a (const (LArray s a))) -> Res b (const (LArray s a))
  foldRead g acc (x # arr) = g acc x # arr

  foldStep : (b -> a -> b) -> (1 _ : Res b (const (LArray s a))) -> Index s -> Res b (const (LArray s a))
  foldStep g (acc # arr) i = foldRead g acc (LArray.read arr i)

  foldOver : (b -> a -> b) -> b -> (1 _ : Res (Extents s) (const (LArray s a))) -> Res b (const (LArray s a))
  foldOver g z (e # arr) = visit e (foldStep g) (z # arr)

  ||| The left fold of the elements in row-major order, and the array given
  ||| back unchanged.
  export
  foldl : (b -> a -> b) -> b -> (1 _ : LArray s a) -> Res b (const (LArray s a))
  foldl g z arr = foldOver g z (LArray.shape arr)

  ||| The new element written where the old one was read, after the state.
  traverseWrite : Index s -> (1 _ : LArray s a) -> (1 _ : Res a (const t)) -> LPair t (LArray s a)
  traverseWrite i arr (y # after) = after # LArray.write arr i y

  traverseRead : (Index s -> a -> (1 _ : t) -> Res a (const t)) -> Index s -> (1 _ : t) ->
                 (1 _ : Res a (const (LArray s a))) -> LPair t (LArray s a)
  traverseRead f i before (x # arr) = traverseWrite i arr (f i x before)

  traverseStep : (Index s -> a -> (1 _ : t) -> Res a (const t)) -> (1 _ : LPair t (LArray s a)) -> Index s ->
                 LPair t (LArray s a)
  traverseStep f (before # arr) i = traverseRead f i before (LArray.read arr i)

  traverseOver : (Index s -> a -> (1 _ : t) -> Res a (const t)) -> (1 _ : t) ->
                 (1 _ : Res (Extents s) (const (LArray s a))) -> LPair t (LArray s a)
  traverseOver f st (e # arr) = visit e (traverseStep f) (st # arr)

  ||| Each element replaced, in place, by what `f` gives for its index, the
  ||| element and the state, the elements taken in row-major order and the
  ||| state threaded from each to the next; the last state, and the array
  ||| given back. The state is linear, so it may be another linear array,
  ||| read or written at each index.
  export
  traverse : (Index s -> a -> (1 _ : t) -> Res a (const t)) -> (1 _ : t) -> (1 _ : LArray s a) ->
             LPair t (LArray s a)
  traverse f st arr = traverseOver f st (LArray.shape arr)
