-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Conjunctive queries, answered by generic join.
|||
||| A query binds its variables one at a time, in the order of their
||| numbers: that order is its plan, fixed by whoever numbers the variables,
||| and the one thing about a query that is static. At each variable, every
||| atom that binds it offers the keys of its trie's level, and the variable
||| takes the keys they all offer; so no intermediate relation is built,
||| and a join of many atoms costs no more than its answer allows. A
||| variable no atom binds ranges over the universe, which is finite.
module Relational.Join

import public Relational.Map
import Data.List
import Data.Nat
import Relational.Order

%default total

------------------------------------------------------------------------------
-- Queries
------------------------------------------------------------------------------

||| An atom of a query: a relation, and the variable each of its columns
||| binds. A variable may bind two columns, which then hold one value.
public export
data Atom : (0 v, u : Nat) -> Type where
  MkAtom : {k : Nat} -> (vars : Vect k (Fin v)) -> (rel : Relation k u) -> Atom v u

||| A conjunctive query over `v` variables of a universe of `u`: the
||| variables its answer gives, in order; the atoms every answer satisfies;
||| the atoms no answer satisfies; and the conditions every answer meets.
public export
record Query (v, u, h : Nat) where
  constructor MkQuery
  output : Vect h (Fin v)
  atoms : List (Atom v u)
  absent : List (Atom v u)
  filters : List (Tuple v u -> Bool)

||| Whether two variables are one. A variable is a small number, compared as
||| the machine compares numbers.
sameVar : Fin v -> Fin v -> Bool
sameVar x y = finToNat x == finToNat y

------------------------------------------------------------------------------
-- Atoms in the plan's order
------------------------------------------------------------------------------

||| A positive atom as the join walks it: the variables it has yet to bind,
||| ascending, and the trie of its tuples under the values bound so far.
||| The two have one length, so an atom with a variable left has a level to
||| bind it with.
data Cursor : (0 v, u : Nat) -> Type where
  MkCursor : {0 d : Nat} -> (vars : Vect d (Fin v)) -> (trie : Relation d u) -> Cursor v u

||| The first of the columns that bind `x`, searching from the left; `j`,
||| which binds it, when none before it does.
firstColumn : Fin v -> Fin k -> Vect m (Fin k, Fin v) -> Fin k
firstColumn x j [] = j
firstColumn x j ((c, y) :: rest) = if sameVar y x then c else firstColumn x j rest

||| For each column, the first column that binds its variable.
representatives : {k : Nat} -> Vect k (Fin v) -> Vect k (Fin k)
representatives vars = map (\j => firstColumn (index j vars) j (zip (allFins k) vars)) (allFins k)

||| Each variable once, with the first column that binds it, ascending by
||| variable.
distinct : {k : Nat} -> Vect k (Fin k) -> Vect k (Fin v) -> List (Fin v, Fin k)
distinct reps vars =
  sortBy (\a, b => compare (finToNat (fst a)) (finToNat (fst b)))
    (map (\cv => (snd cv, fst cv)) (filter (\cv => finToNat (index (fst cv) reps) == finToNat (fst cv))
                                           (toList (zip (allFins k) vars))))

||| A tuple in the order of the atom's distinct variables, if the columns
||| one variable binds agree.
reorder : {k : Nat} -> Vect k (Fin k) -> Vect d (Fin v, Fin k) -> Tuple k u -> Maybe (Tuple d u)
reorder reps ws t =
  if all (\j => (index j t).value == (index (index j reps) t).value) (allFins k)
    then Just (map (\w => index (snd w) t) ws)
    else Nothing

||| An atom with its trie keyed by its variables in the plan's order.
cursor : Atom v u -> Cursor v u
cursor (MkAtom {k} vars rel) =
  let reps = representatives vars
      ws = fromList (distinct reps vars)
  in MkCursor (map fst ws) (relation (mapMaybe (reorder reps ws) (tuples rel)))

------------------------------------------------------------------------------
-- The walk
------------------------------------------------------------------------------

||| A cursor at the variable being bound: it binds it, with the branches its
||| trie has for it, or it waits for a later variable.
data Turn : (0 v, u : Nat) -> Type where
  Binds : {0 d : Nat} -> (rest : Vect d (Fin v)) -> (branches : Branches 0 d u ()) -> Turn v u
  Waits : Cursor v u -> Turn v u

turn : Fin v -> Cursor v u -> Turn v u
turn x (MkCursor (y :: ys) (Level bs)) =
  if sameVar y x then Binds ys bs else Waits (MkCursor (y :: ys) (Level bs))
turn x (MkCursor [] t) = Waits (MkCursor [] t)

||| A binding cursor's offer: each key of its level, with the cursor moved
||| to the key's child.
offers : Vect d (Fin v) -> Branches lo d u () -> List (Coord u, Cursor v u)
offers rest Done = []
offers rest (Next x _ cx child more) = (MkCoord x cx, MkCursor rest child) :: offers rest more

||| The keys both sides offer, ascending, each with the cursors that go on
||| from it.
meet : List (Coord u, List (Cursor v u)) -> List (Coord u, Cursor v u) -> List (Coord u, List (Cursor v u))
meet [] _ = []
meet _ [] = []
meet ((c, cs) :: xs) ((c', k) :: ys) = case order c.value c'.value of
  Less _ => meet xs ((c', k) :: ys)
  Same _ => (c, k :: cs) :: meet xs ys
  More _ => meet ((c, cs) :: xs) ys

binders : List (Turn v u) -> List (List (Coord u, Cursor v u))
binders [] = []
binders (Binds rest bs :: ts) = offers rest bs :: binders ts
binders (Waits _ :: ts) = binders ts

waiters : List (Turn v u) -> List (Cursor v u)
waiters [] = []
waiters (Binds _ _ :: ts) = waiters ts
waiters (Waits c :: ts) = c :: waiters ts

||| The values variable `x` takes, each with the cursors that follow: every
||| cursor that binds `x`, moved to the value's child, and every other as it
||| was. A variable no cursor binds takes every value of the universe.
candidates : {u : Nat} -> Fin v -> List (Cursor v u) -> List (Coord u, List (Cursor v u))
candidates x cursors =
  let turns = map (turn x) cursors
      waiting = waiters turns
  in case binders turns of
       [] => map (\c => (c, waiting)) (coords u)
       (first :: others) =>
         map (\o => (fst o, snd o ++ waiting)) (foldl meet (map (\o => (fst o, [snd o])) first) others)

||| Every binding of the variables still to bind, `steps`, after `bound`,
||| onto `found`.
walk : {u : Nat} -> (steps : Vect r (Fin v)) -> (bound : Vect b (Coord u)) -> (0 _ : b + r = v) ->
       List (Cursor v u) -> SnocList (Tuple v u) -> SnocList (Tuple v u)
walk [] bound prf _ found =
  found :< replace {p = \n => Vect n (Coord u)} (trans (sym (plusZeroRightNeutral b)) prf) bound
walk (x :: xs) bound prf cursors found =
  foldl (\acc, next => walk xs (snoc bound (fst next)) (trans (plusSuccRightSucc b _) prf) (snd next) acc)
        found (candidates x cursors)

||| The bindings no absent atom holds and every filter keeps, as the
||| query's output columns.
answer : Query v u h -> Tuple v u -> Maybe (Tuple h u)
answer q env =
  if all (\a => not (holds a)) q.absent && all (\f => f env) q.filters
    then Just (map (\x => index x env) q.output)
    else Nothing
  where
    holds : Atom v u -> Bool
    holds (MkAtom vars rel) = member (map (\x => index x env) vars) rel

||| The query's answer.
export
run : {v, u, h : Nat} -> Query v u h -> Relation h u
run q = relation (mapMaybe (answer q) (walk (allFins v) [] Refl (map cursor q.atoms) [<] <>> []))

------------------------------------------------------------------------------
-- Aggregates
------------------------------------------------------------------------------

||| The relation grouped by a key each tuple gives, the values of a group
||| combined by `f`: a count, a sum or a maximum is a merge, and exact.
export
aggregate : {g : Nat} -> (Tuple k u -> Tuple g u) -> (Tuple k u -> l) -> (l -> l -> l) -> Relation k u -> Map g u l
aggregate key value f r = fromEntries f (map (\t => (key t, value t)) (tuples r))

||| The relation on some of its columns, in the order given.
export
project : {g : Nat} -> Vect g (Fin k) -> Relation k u -> Relation g u
project cols r = relation (map (\t => map (\c => index c t) cols) (tuples r))
