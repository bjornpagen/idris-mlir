-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| The sparse form a call's size-change graph is kept in, in a definition
||| and its TTC: only the arcs that say something. Graphs are composed
||| dense, as matrices over the size-change semiring
||| (`Core.Termination.SizeChange`).
module Libraries.Data.SparseMatrix

import Algebra.Semiring

import Data.List
import Data.List1

%default total

namespace Vector
  ||| A sparse vector is a list of pairs consisting of an index and its
  ||| corresponding element.
  |||
  ||| Invariants:
  ||| - indices must appear in order and should to be duplicate-free,
  ||| - elements must be additively non-neutral,
  ||| - missing entries are assumed to be neutral.
  public export
  Vector : Type -> Type
  Vector a = List (Nat, a)

  ||| Turns a list into a sparse vector, discarding neutral elements in
  ||| the process.
  export
  fromList : (Eq a, Semiring a) => List a -> Vector a
  fromList = go Z
    where
      go : Nat -> List a -> Vector a
      go i [] = []
      go i (x :: xs)
          = if x == plusNeutral
               then go (S i) xs
               else (i, x) :: go (S i) xs

  export
  lookupOrd : Ord k => k -> List (k, a) -> Maybe a
  lookupOrd i [] = Nothing
  lookupOrd i ((k, x) :: xs) =
    case compare i k of
      LT => Nothing
      EQ => Just x
      GT => lookupOrd i xs

namespace Vector1
  public export
  Vector1 : Type -> Type
  Vector1 a = List1 (Nat, a)

  export
  fromList : (Eq a, Semiring a) => List a -> Maybe (Vector1 a)
  fromList = Data.List1.fromList . Vector.fromList

  export
  lookupOrd : Ord k => k -> List1 (k, a) -> Maybe a
  lookupOrd i ((k, x) ::: xs) =
    case compare i k of
      LT => Nothing
      EQ => Just x
      GT => lookupOrd i xs

  export
  maxIndex : Vector1 a -> Nat
  maxIndex ((i, x) ::: xs) = maybe i fst (last' xs)

||| A sparse matrix is a sparse vector of (non-empty) sparse vectors.
public export
Matrix : Type -> Type
Matrix a = Vector (Vector1 a)

export
fromListList : (Eq a, Semiring a) => List (List a) -> Matrix a
fromListList = mapMaybe (\(i, xs) => map (i,) (Vector1.fromList xs)) . withIndex
  where
    -- may contain empty lists
    withIndex : List (List a) -> List (Nat, List a)
    withIndex = go Z
      where
        go : Nat -> List (List a) -> List (Nat, List a)
        go i [] = []
        go i (x :: xs) = (i, x) :: go (S i) xs
