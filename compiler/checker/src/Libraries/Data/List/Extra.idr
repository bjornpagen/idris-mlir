-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Data.List.Extra

import public Data.List

%default total

||| Fetches the element at a given position.
||| Returns `Nothing` if the position beyond the list's end.
public export
elemAt : List a -> Nat -> Maybe a
elemAt []        _     = Nothing
elemAt (l :: _)  Z     = Just l
elemAt (_ :: ls) (S n) = elemAt ls n

export
findBy : (a -> Maybe b) -> List a -> Maybe b
findBy p [] = Nothing
findBy p (x :: xs)
  = case p x of
      Nothing => findBy p xs
      Just win => pure win

export
findBy' : (a -> Bool) -> List a -> (List a, Maybe a, List a)
findBy' f [] = ([], Nothing, [])
findBy' f (x :: xs) =
  case f x of
    True  => ([], Just x, xs)
    False =>
      let (pre, mb, post) = findBy' f xs in
      (x :: pre, mb, post)

||| Returns first element that matches the predicate and the list without it
export
findAndDeleteBy : (a -> Bool) -> List a -> Maybe (a, List a)
findAndDeleteBy f xs
  = case findBy' f xs of
      (pre, Just x, post) => Just (x, pre ++ post)
      _                   => Nothing

||| Remove adjacent duplicates
export
dedup : Eq a => List a -> List a
dedup (a :: xs@(b :: _)) = if a == b then dedup xs else a :: dedup xs
dedup xs                = xs
