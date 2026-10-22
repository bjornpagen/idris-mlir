-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| Finite types, and why a search over one ends.
|||
||| A type is finite when a list holds every value of it. A list without
||| duplicates whose values are all in another list is no longer than it
||| (the pigeonhole principle), so a search that keeps each value it meets
||| once has room left for fewer values at each step: the values not yet
||| kept are its measure.
module Libraries.Data.List.Finite

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List.Elem
import Data.Nat
import Data.Vect

%default total

||| A list in which no value occurs twice.
public export
data NoDup : List a -> Type where
  Nil : NoDup []
  (::) : Not (Elem x xs) -> NoDup xs -> NoDup (x :: xs)

0 dropElemLength : (p : Elem x ys) -> S (length (dropElem ys p)) = length ys
dropElemLength Here = Refl
dropElemLength (There p) = cong S (dropElemLength p)

0 dropElemKeeps : (p : Elem x ys) -> Elem y ys -> Not (y = x) -> Elem y (dropElem ys p)
dropElemKeeps Here Here neq = absurd (neq Refl)
dropElemKeeps Here (There e) neq = e
dropElemKeeps (There p) Here neq = Here
dropElemKeeps (There p) (There e) neq = There (dropElemKeeps p e neq)

||| The pigeonhole principle: a list without duplicates whose values are all
||| in `ys` is no longer than `ys`.
export
0 pigeonhole : {xs : List a} -> NoDup xs -> ((y : a) -> Elem y xs -> Elem y ys) ->
             LTE (length xs) (length ys)
pigeonhole [] sub = LTEZero
pigeonhole {xs = x :: xs} (notIn :: nd) sub
    = let p = sub x Here in
      rewrite sym (dropElemLength p) in
      LTESucc (pigeonhole nd (\y, e => dropElemKeeps p (sub y (There e))
                                                     (\eq => notIn (rewrite sym eq in e))))

||| A type every value of which is in one list.
public export
interface Finite a where
  0 values : List a
  0 complete : (x : a) -> Elem x values

-- The lists of every value of a composite type, from its parts'.
flatMap : (a -> List b) -> List a -> List b
flatMap f [] = []
flatMap f (x :: xs) = f x ++ flatMap f xs

0 elemAppendLeft : Elem x xs -> Elem x (xs ++ ys)
elemAppendLeft Here = Here
elemAppendLeft (There e) = There (elemAppendLeft e)

0 elemAppendRight : {xs : List a} -> Elem x ys -> Elem x (xs ++ ys)
elemAppendRight {xs = []} e = e
elemAppendRight {xs = _ :: _} e = There (elemAppendRight e)

0 elemFlatMap : {0 f : a -> List b} -> {xs : List a} -> Elem x xs -> Elem y (f x) -> Elem y (flatMap f xs)
elemFlatMap Here e = elemAppendLeft e
elemFlatMap {xs = _ :: _} (There p) e = elemAppendRight (elemFlatMap p e)

vects : (n : Nat) -> List a -> List (Vect n a)
vects Z as = [[]]
vects (S n) as = flatMap (\x => map (x ::) (vects n as)) as

0 vectsComplete : {as : List a} -> ((x : a) -> Elem x as) -> (v : Vect n a) -> Elem v (vects n as)
vectsComplete c [] = Here
vectsComplete c (x :: xs) = elemFlatMap (c x) (elemMap (x ::) (vectsComplete c xs))

export
{n : Nat} -> Finite a => Finite (Vect n a) where
  values = vects n values
  complete v = vectsComplete complete v

fins : (m : Nat) -> List (Fin m)
fins Z = []
fins (S k) = FZ :: map FS (fins k)

0 finsComplete : (i : Fin m) -> Elem i (fins m)
finsComplete FZ = Here
finsComplete (FS i) = There (elemMap FS (finsComplete i))

export
{m : Nat} -> Finite (Fin m) where
  values = fins m
  complete = finsComplete

pairs : List a -> List b -> List (a, b)
pairs as bs = flatMap (\x => map (x,) bs) as

export
(Finite a, Finite b) => Finite (a, b) where
  values = pairs values values
  complete (x, y) = elemFlatMap (complete x) (elemMap (x,) (complete y))

||| The values of a finite type a list without duplicates has room for after
||| one more, when that one is not in it: fewer than before, by one.
export
0 roomAfter : Finite a => {xs : List a} -> NoDup xs -> Not (Elem x xs) ->
              (room : Nat) -> length xs + room = length (values {a}) ->
              (room' : Nat ** (room = S room', length (x :: xs) + room' = length (values {a})))
roomAfter nd notIn Z prf
    = let fits = pigeonhole (notIn :: nd) (\y, _ => complete y)
          tight : LTE (S (length xs)) (length xs)
          tight = replace {p = LTE (S (length xs))}
                          (trans (sym prf) (plusZeroRightNeutral (length xs))) fits in
      absurd (succNotLTEpred tight)
roomAfter nd notIn (S k) prf
    = (k ** (Refl, rewrite plusSuccRightSucc (length xs) k in prf))
