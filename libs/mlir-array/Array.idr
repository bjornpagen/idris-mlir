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

||| The left fold over the last axis, from `z` at every index of the frame.
export
reduce : (b -> a -> b) -> b -> Array (f :< n) a -> Array f b
reduce g z x = case shape x of
  fe :< _ => foldLast g (fill fe z) x

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

namespace LArray
  ||| The array with each element replaced by `f` of it, in place, in
  ||| row-major order.
  export
  map : (a -> a) -> (1 _ : LArray s a) -> LArray s a
  map f arr =
    let e # arr = LArray.shape arr in
    visit e (\arr, i => let x # arr = LArray.read arr i in LArray.write arr i (f x)) arr

  ||| The left fold of the elements in row-major order, and the array given
  ||| back unchanged.
  export
  foldl : (b -> a -> b) -> b -> (1 _ : LArray s a) -> Res b (const (LArray s a))
  foldl g z arr =
    let e # arr = LArray.shape arr in
    visit e (\(acc # arr), i => let x # arr = LArray.read arr i in g acc x # arr) (z # arr)

  ||| Each element replaced, in place, by what `f` gives for its index, the
  ||| element and the state, the elements taken in row-major order and the
  ||| state threaded from each to the next; the last state, and the array
  ||| given back. The state is linear, so it may be another linear array,
  ||| read or written at each index.
  export
  traverse : (Index s -> a -> (1 _ : t) -> Res a (const t)) -> (1 _ : t) -> (1 _ : LArray s a) ->
             LPair t (LArray s a)
  traverse f st arr =
    let e # arr = LArray.shape arr in
    visit e (\(before # arr), i =>
      let x # arr = LArray.read arr i
          y # after = f i x before
      in after # LArray.write arr i y) (st # arr)
