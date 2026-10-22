-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Fixpoints over relations: semi-naive Datalog, and maps whose values
||| rise in a lattice of finite height.
|||
||| A round joins only what the last round added against the rest, keeps
||| what is new, and goes on with that alone. Every relation lives in a
||| finite universe and holds each tuple once, so a round that adds anything
||| leaves less room; the round decides that with one comparison it makes
||| anyway, its evidence erased, and the recursion is on the room left. A
||| round that leaves the room as it was added nothing, which is the
||| fixpoint: no round count and no budget ends one.
module Relational.Fixpoint

import public Relational.Join
import Control.WellFounded
import Data.Nat
import Data.So

%default total

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

export infixr 5 :+

||| The derived relations of a program over a universe of `u`, one for each
||| arity of `ar`.
public export
data Store : (ar : Vect p Nat) -> (u : Nat) -> Type where
  NoRelations : Store [] u
  (:+) : Relation k u -> Store ks u -> Store (k :: ks) u

||| A derived relation, by its position.
export
get : (j : Fin p) -> Store ar u -> Relation (index j ar) u
get FZ (r :+ _) = r
get (FS j) (_ :+ rs) = get j rs

modify : (j : Fin p) -> (Relation (index j ar) u -> Relation (index j ar) u) -> Store ar u -> Store ar u
modify FZ f (r :+ rs) = f r :+ rs
modify (FS j) f (r :+ rs) = r :+ modify j f rs

||| No tuple in any relation.
blank : {ar : Vect p Nat} -> Store ar u
blank {ar = []} = NoRelations
blank {ar = k :: _} = none {k} :+ blank

unite : Store ar u -> Store ar u -> Store ar u
unite NoRelations NoRelations = NoRelations
unite (r :+ rs) (s :+ ss) = union r s :+ unite rs ss

without : Store ar u -> Store ar u -> Store ar u
without NoRelations NoRelations = NoRelations
without (r :+ rs) (s :+ ss) = difference r s :+ without rs ss

||| How many tuples the store could still gain: for each relation, the
||| tuples of its universe it does not hold.
room : {u : Nat} -> {ar : Vect p Nat} -> Store ar u -> Nat
room {ar = []} NoRelations = 0
room {ar = k :: ks} (r :+ rs) = minus (power u k) (cardinality r) + room {ar = ks} rs

||| A literal of a rule's body: an atom over a fixed relation, or over a
||| derived one, by its position.
public export
data Literal : (ar : Vect p Nat) -> (v, u : Nat) -> Type where
  Fixed : Atom v u -> Literal ar v u
  Derived : (j : Fin p) -> Vect (index j ar) (Fin v) -> Literal ar v u

||| A rule over `v` variables: the derived relation it adds to and the
||| variables of its head; the literals every derivation satisfies; the
||| fixed atoms none does; and its conditions. Only fixed relations are
||| negated, so every program is stratified.
public export
data Rule : (ar : Vect p Nat) -> (u : Nat) -> Type where
  MkRule : {v : Nat} -> (target : Fin p) -> (head : Vect (index target ar) (Fin v)) ->
           (body : List (Literal ar v u)) -> (absent : List (Atom v u)) ->
           (filters : List (Tuple v u -> Bool)) -> Rule ar u

------------------------------------------------------------------------------
-- Semi-naive evaluation
------------------------------------------------------------------------------

||| What a derived literal reads in one evaluation of a body.
data Reads = Whole | Added

||| A literal as an atom, a derived one over the whole store or over what the
||| last round added.
atomOf : {ar : Vect p Nat} -> (whole, added : Store ar u) -> Reads -> Literal ar v u -> Atom v u
atomOf whole added _ (Fixed a) = a
atomOf whole added Whole (Derived j vars) = MkAtom vars (get j whole)
atomOf whole added Added (Derived j vars) = MkAtom vars (get j added)

||| The body as atoms, the literal at `here` reading what was added and the
||| rest the whole store.
atomsWith : {ar : Vect p Nat} -> (whole, added : Store ar u) -> (here, at : Nat) -> List (Literal ar v u) -> List (Atom v u)
atomsWith whole added here at [] = []
atomsWith whole added here at (l :: ls) =
  atomOf whole added (if here == at then Added else Whole) l :: atomsWith whole added here (S at) ls

||| The positions of the derived literals of a body.
derivedAt : Nat -> List (Literal ar v u) -> List Nat
derivedAt at [] = []
derivedAt at (Fixed _ :: ls) = derivedAt (S at) ls
derivedAt at (Derived _ _ :: ls) = at :: derivedAt (S at) ls

||| A body with no derived literal, as atoms.
fixedOnly : List (Literal ar v u) -> Maybe (List (Atom v u))
fixedOnly [] = Just []
fixedOnly (Fixed a :: ls) = map (a ::) (fixedOnly ls)
fixedOnly (Derived _ _ :: _) = Nothing

||| What a rule derives from the whole store and what the last round added:
||| once for each of its derived literals, that one reading what was added.
fire : {u : Nat} -> {ar : Vect p Nat} -> (whole, added : Store ar u) -> Store ar u -> Rule ar u -> Store ar u
fire whole added acc (MkRule {v} target head body absent filters) =
  foldl (\st, here => modify target (union (run (MkQuery head (atomsWith whole added here 0 body) absent filters))) st)
        acc (derivedAt 0 body)

||| What the rules with no derived literal derive: they are fired once, at
||| the start, since nothing a round adds changes them.
seed : {u : Nat} -> {ar : Vect p Nat} -> Store ar u -> Rule ar u -> Store ar u
seed acc (MkRule {v} target head body absent filters) = case fixedOnly body of
  Just atoms => modify target (union (run (MkQuery head atoms absent filters))) acc
  Nothing => acc

rounds : {u : Nat} -> {ar : Vect p Nat} -> List (Rule ar u) -> (whole, added : Store ar u) ->
         (0 _ : Accessible LT (room whole)) -> Store ar u
rounds rules whole added (Access rec) =
  let fresh = without (foldl (fire whole added) blank rules) whole
      grown = unite whole fresh
  in case choose (room grown < room whole) of
       Left fewer => rounds rules grown fresh (rec (room grown) (ltOpReflectsLT (room grown) (room whole) fewer))
       Right _ => grown

||| The least store the rules hold of: every tuple a rule derives from the
||| fixed relations and the derived ones.
export
saturate : {u : Nat} -> {ar : Vect p Nat} -> List (Rule ar u) -> Store ar u
saturate rules = let start = foldl seed blank rules in rounds rules start start (wellFounded (room start))

------------------------------------------------------------------------------
-- Maps over a lattice
------------------------------------------------------------------------------

||| A lattice of finite height, as a map's values merge: `merge` joins two
||| values, and `rank` is how many more times a value can rise, at most
||| `height`. A merge never raises the rank, and lowers it whenever it
||| changes the value; so subsumption, keeping only the weakest of what was
||| derived, is a merge too.
public export
record Lattice (l : Type) where
  constructor MkLattice
  merge : l -> l -> l
  height : Nat
  rank : l -> Nat
  0 bounded : (x : l) -> LTE (rank x) height
  0 settles : (x, y : l) -> LTE (rank (merge x y)) (rank x)
  0 rises : (x, y : l) -> Not (merge x y = x) -> LT (rank (merge x y)) (rank x)

||| How much a map could still change: its room, a tuple of which costs
||| more than any rise of a value, and the rises its values have left.
weight : {k, u : Nat} -> Lattice l -> Map k u l -> Nat
weight lat m = minus (power u k) (cardinality m) * S lat.height + foldEntries (\acc, _, v => acc + lat.rank v) 0 m

||| Whether an entry of the merged map is new, or rose from what it was.
rose : Lattice l -> Map k u l -> Tuple k u -> l -> Bool
rose lat before t v = case valueAt t before of
  Nothing => True
  Just old => lat.rank v < lat.rank old

mapRounds : {k, u : Nat} -> (lat : Lattice l) -> (Map k u l -> Map k u l -> Map k u l) -> (whole, changed : Map k u l) ->
            (0 _ : Accessible LT (weight lat whole)) -> Map k u l
mapRounds lat step whole changed (Access rec) =
  let merged = unionWith lat.merge whole (step whole changed)
  in case choose (weight lat merged < weight lat whole) of
       Left lower =>
         mapRounds lat step merged (filterWith (rose lat whole) merged)
                   (rec (weight lat merged) (ltOpReflectsLT (weight lat merged) (weight lat whole) lower))
       Right _ => merged

||| The least fixpoint of `step` over a map whose values rise in a lattice:
||| `step` takes the whole map and the entries that changed in the last
||| round, and gives what they derive, which is merged in.
export
saturateMap : {k, u : Nat} -> Lattice l -> (step : Map k u l -> Map k u l -> Map k u l) -> Map k u l -> Map k u l
saturateMap lat step start = mapRounds lat step start start (wellFounded (weight lat start))
