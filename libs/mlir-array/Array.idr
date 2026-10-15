-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Typed arrays: `Array.Core`'s types and generating set, and the library
||| code over them.
|||
||| Nothing here sees how an array is held: every definition is written
||| over the generating set, and compiles as written to what those
||| functions become. Every fold here means its left fold in index order,
||| so a sum of floats adds in the order a program reads, on every target.
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
  foldr g z x = foldr g z (toList x)
  toList x = foldl (:<) [<] x <>> []
  null x = volume (shape x) == 0
  foldMap f x = foldl (\acc, v => acc <+> f v) neutral x

||| Arrays of one shape, combined element by element.
export
Zippable (Array s) where
  zipWith f x y = tabulate (shape x) (\i => f (x !! i) (y !! i))
  unzipWith f x = (map (fst . f) x, map (snd . f) x)
