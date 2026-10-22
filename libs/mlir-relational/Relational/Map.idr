-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Relations as tries over a finite universe.
|||
||| A tuple is `k` coordinates, each a natural below the universe's size
||| `u`. A map holds tuples with a value each, as a trie: a level per
||| column, its keys ascending, each with the trie of the tuples that start
||| with it. Keys ascend by type, so no tuple is held twice, and every key is
||| below `u` by type, so a map of arity `k` holds at most `u` to the `k`
||| tuples: that bound is what ends a fixpoint over maps. A relation is a map
||| whose values say nothing.
|||
||| Every structure here is plain Idris over base, so both hosts run it.
module Relational.Map

import public Data.Vect
import Data.Maybe
import Data.Nat
import Relational.Order

%default total

------------------------------------------------------------------------------
-- Coordinates and tuples
------------------------------------------------------------------------------

||| A value of a universe of `u` values: a natural below `u`, its bound
||| erased.
public export
record Coord (0 u : Nat) where
  constructor MkCoord
  value : Nat
  0 below : LT value u

||| Every value of the universe, ascending.
export
coords : (u : Nat) -> List (Coord u)
coords u = from u reflexive []
  where
    from : (k : Nat) -> (0 _ : LTE k u) -> List (Coord u) -> List (Coord u)
    from Z _ acc = acc
    from (S k) fits acc = from k (lteSuccLeft fits) (MkCoord k fits :: acc)

||| A tuple: a coordinate for each of `k` columns.
public export
Tuple : Nat -> Nat -> Type
Tuple k u = Vect k (Coord u)

------------------------------------------------------------------------------
-- Maps
------------------------------------------------------------------------------

mutual
  ||| The tuples of `k` columns over a universe of `u`, each with a value of
  ||| `l`: at no column, the empty tuple's value or nothing; at more, the
  ||| branches of the first column.
  public export
  data Map : (k, u : Nat) -> Type -> Type where
    Empty : Map 0 u l
    Value : l -> Map 0 u l
    Level : Branches 0 k u l -> Map (S k) u l

  ||| Branches whose keys ascend from at least `lo`, each below `u`, each
  ||| child holding a tuple.
  public export
  data Branches : (lo, k, u : Nat) -> Type -> Type where
    Done : Branches lo k u l
    Next : (key : Nat) -> (0 above : LTE lo key) -> (0 below : LT key u) ->
           (child : Map k u l) -> (rest : Branches (S key) k u l) -> Branches lo k u l

||| A set of tuples: a map whose values say nothing.
public export
Relation : Nat -> Nat -> Type
Relation k u = Map k u ()

||| The map of no tuple.
export
none : {k : Nat} -> Map k u l
none {k = Z} = Empty
none {k = S _} = Level Done

||| Whether a map holds no tuple. No child is empty, so this looks at one
||| level.
export
isEmpty : Map k u l -> Bool
isEmpty Empty = True
isEmpty (Value _) = False
isEmpty (Level Done) = True
isEmpty (Level (Next _ _ _ _ _)) = False

||| The map of one tuple.
export
single : Tuple k u -> l -> Map k u l
single [] v = Value v
single (c :: cs) v = Level (Next c.value LTEZero c.below (single cs v) Done)

||| Branches above one bound are above a lower one: only the first key's
||| bound changes.
relax : (0 _ : LTE lo lo') -> Branches lo' k u l -> Branches lo k u l
relax _ Done = Done
relax le (Next x lx cx child rest) = Next x (transitive le lx) cx child rest

||| The branch at `x` and then `rest`, the branch dropped when its child
||| holds nothing, so that no child is ever empty.
keep : (x : Nat) -> (0 _ : LTE lo x) -> (0 _ : LT x u) -> Map k u l -> Branches (S x) k u l -> Branches lo k u l
keep x lx cx child rest = if isEmpty child then relax (lteSuccRight lx) rest else Next x lx cx child rest

-- Two merges below hold one side's first branch apart, its key and bounds
-- as arguments, and swap sides when the other side's key is smaller: so
-- no cell is rebuilt only to change the bound of its key, and every cell
-- built is a branch of the result.

mutual
  ||| Every tuple of either map; a tuple of both takes `f` of its values,
  ||| the first map's first.
  export
  unionWith : (l -> l -> l) -> Map k u l -> Map k u l -> Map k u l
  unionWith f Empty m = m
  unionWith f (Value v) Empty = Value v
  unionWith f (Value v) (Value w) = Value (f v w)
  unionWith f (Level xs) (Level ys) = Level (unionB f xs ys)

  unionB : (l -> l -> l) -> Branches lo k u l -> Branches lo k u l -> Branches lo k u l
  unionB f xs Done = xs
  unionB f xs (Next y ly cy ty ys) = leftWith f xs y ly cy ty ys

  -- The first map's branches `xs`, with the second's branch at `y` and then
  -- its branches `ys`.
  leftWith : (l -> l -> l) -> Branches lo k u l -> (y : Nat) -> (0 _ : LTE lo y) -> (0 _ : LT y u) ->
             Map k u l -> Branches (S y) k u l -> Branches lo k u l
  leftWith f Done y ly cy ty ys = Next y ly cy ty ys
  leftWith f (Next x lx cx tx xs) y ly cy ty ys = case order x y of
    Less xy => Next x lx cx tx (leftWith f xs y xy cy ty ys)
    Same Refl => Next x lx cx (unionWith f tx ty) (unionB f xs ys)
    More yx => Next y ly cy ty (rightWith f ys x yx cx tx xs)

  -- The second map's branches `ys`, with the first's branch at `x` and then
  -- its branches `xs`.
  rightWith : (l -> l -> l) -> Branches lo k u l -> (x : Nat) -> (0 _ : LTE lo x) -> (0 _ : LT x u) ->
              Map k u l -> Branches (S x) k u l -> Branches lo k u l
  rightWith f Done x lx cx tx xs = Next x lx cx tx xs
  rightWith f (Next y ly cy ty ys) x lx cx tx xs = case order y x of
    Less yx => Next y ly cy ty (rightWith f ys x yx cx tx xs)
    Same Refl => Next y ly cy (unionWith f tx ty) (unionB f xs ys)
    More xy => Next x lx cx tx (leftWith f xs y xy cy ty ys)

||| Every tuple of either relation.
export
union : Relation k u -> Relation k u -> Relation k u
union = unionWith (\_, _ => ())

mutual
  ||| The entries of the first map whose tuples the second does not hold.
  export
  difference : Map k u l -> Map k u m -> Map k u l
  difference Empty _ = Empty
  difference (Value v) Empty = Value v
  difference (Value _) (Value _) = Empty
  difference (Level xs) (Level ys) = Level (minusB xs ys)

  minusB : Branches lo k u l -> Branches lo k u m -> Branches lo k u l
  minusB xs Done = xs
  minusB xs (Next y ly _ ty ys) = minusAt xs y ly ty ys

  -- The branches `xs`, without the key `y`, whose child is `ty`, and the
  -- keys of `ys`.
  minusAt : Branches lo k u l -> (y : Nat) -> (0 _ : LTE lo y) -> Map k u m -> Branches (S y) k u m ->
            Branches lo k u l
  minusAt Done y ly ty ys = Done
  minusAt (Next x lx cx tx xs) y ly ty ys = case order x y of
    Less xy => Next x lx cx tx (minusAt xs y xy ty ys)
    Same Refl => keep x lx cx (difference tx ty) (minusB xs ys)
    More _ => keepAt x lx cx tx xs ys

  -- The branch at `x` and then `xs`, without the keys of `ys`. No branch of
  -- `ys` enters the result, so the bound its keys ascend from is its own,
  -- not the result's.
  keepAt : (x : Nat) -> (0 _ : LTE lo x) -> (0 _ : LT x u) -> Map k u l -> Branches (S x) k u l ->
           Branches lo' k u m -> Branches lo k u l
  keepAt x lx cx tx xs Done = Next x lx cx tx xs
  keepAt x lx cx tx xs (Next y ly _ ty ys) = case order x y of
    Less xy => Next x lx cx tx (minusAt xs y xy ty ys)
    Same Refl => keep x lx cx (difference tx ty) (minusB xs ys)
    More _ => keepAt x lx cx tx xs ys

mutual
  ||| The entries `p` keeps: a selection.
  export
  filterWith : (Tuple k u -> l -> Bool) -> Map k u l -> Map k u l
  filterWith p Empty = Empty
  filterWith p (Value v) = if p [] v then Value v else Empty
  filterWith p (Level bs) = Level (filterB p bs)

  filterB : (Tuple (S k) u -> l -> Bool) -> Branches lo k u l -> Branches lo k u l
  filterB p Done = Done
  filterB p (Next x lx cx child rest) =
    keep x lx cx (filterWith (\t, v => p (MkCoord x cx :: t) v) child) (filterB p rest)

mutual
  ||| The value a tuple has, if the map holds it.
  export
  valueAt : Tuple k u -> Map k u l -> Maybe l
  valueAt [] Empty = Nothing
  valueAt [] (Value v) = Just v
  valueAt (c :: cs) (Level bs) = valueIn c.value cs bs

  valueIn : Nat -> Tuple k u -> Branches lo k u l -> Maybe l
  valueIn x cs Done = Nothing
  valueIn x cs (Next y _ _ child rest) = case order x y of
    Less _ => Nothing
    Same _ => valueAt cs child
    More _ => valueIn x cs rest

||| Whether the relation holds the tuple: a probe, and with `not` an
||| anti-probe.
export
member : Tuple k u -> Relation k u -> Bool
member t r = isJust (valueAt t r)

mutual
  ||| How many tuples the map holds.
  export
  cardinality : Map k u l -> Nat
  cardinality Empty = 0
  cardinality (Value _) = 1
  cardinality (Level bs) = cardinalityB bs

  cardinalityB : Branches lo k u l -> Nat
  cardinalityB Done = 0
  cardinalityB (Next _ _ _ child rest) = cardinality child + cardinalityB rest

mutual
  ||| Every entry, its tuples ascending, combined from the left.
  export
  foldEntries : (acc -> Tuple k u -> l -> acc) -> acc -> Map k u l -> acc
  foldEntries f acc Empty = acc
  foldEntries f acc (Value v) = f acc [] v
  foldEntries f acc (Level bs) = foldB f acc bs

  foldB : (acc -> Tuple (S k) u -> l -> acc) -> acc -> Branches lo k u l -> acc
  foldB f acc Done = acc
  foldB f acc (Next x _ cx child rest) =
    foldB f (foldEntries (\a, t, v => f a (MkCoord x cx :: t) v) acc child) rest

||| Every entry, its tuples ascending.
export
entries : Map k u l -> List (Tuple k u, l)
entries m = foldEntries (\acc, t, v => acc :< (t, v)) [<] m <>> []

||| Every tuple, ascending.
export
tuples : Relation k u -> List (Tuple k u)
tuples r = foldEntries (\acc, t, _ => acc :< t) [<] r <>> []

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------

||| A stack of maps, the newest on top, whose ranks (each map merged from
||| two to the rank entries) rise toward the bottom: pushing merges equal
||| ranks as a binary counter carries, so building from `n` entries merges
||| each entry about log `n` times.
push : (l -> l -> l) -> Nat -> Map k u l -> List (Nat, Map k u l) -> List (Nat, Map k u l)
push f rank m [] = [(rank, m)]
push f rank m ((rank', m') :: older) =
  if rank == rank' then push f (S rank) (unionWith f m' m) older else (rank, m) :: (rank', m') :: older

collapse : {k : Nat} -> (l -> l -> l) -> List (Nat, Map k u l) -> Map k u l
collapse f [] = none
collapse f ((_, m) :: older) = unionWith f (collapse f older) m

||| The map of these entries; a tuple given twice takes `f` of its values,
||| the earlier first.
export
fromEntries : {k : Nat} -> (l -> l -> l) -> List (Tuple k u, l) -> Map k u l
fromEntries f es = collapse f (foldl (\st, e => push f 0 (single (fst e) (snd e)) st) [] es)

||| The relation of these tuples.
export
relation : {k : Nat} -> List (Tuple k u) -> Relation k u
relation ts = fromEntries (\_, _ => ()) (map (\t => (t, ())) ts)
