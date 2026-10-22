-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Intervals and Allen's relations between them, as a query's filter.
|||
||| Exactly one of Allen's thirteen relations holds of any two proper
||| intervals, so the relation is computed once, by comparing endpoints,
||| and a join asks whether it is in a mask: a set of relations, one bit
||| each, so "during or equal" is one test.
module Relational.Interval

import Data.Bits
import Relational.Join
import Relational.Order

%default total

||| A proper interval: the naturals from `start` up to `end`, which is
||| after it.
public export
record Interval where
  constructor MkInterval
  start : Nat
  end : Nat
  0 proper : LT start end

||| How the first of two intervals stands to the second.
public export
data Allen
  = Precedes | Meets | Overlaps | FinishedBy | Contains | Starts | Equals
  | StartedBy | During | Finishes | OverlappedBy | MetBy | PrecededBy

||| The relation of two intervals that share a point, from how their starts
||| and their ends compare.
overlapping : Order s1 s2 -> Order e1 e2 -> Allen
overlapping (Same _) (Same _) = Equals
overlapping (Same _) (Less _) = Starts
overlapping (Same _) (More _) = StartedBy
overlapping (Less _) (Same _) = FinishedBy
overlapping (More _) (Same _) = Finishes
overlapping (Less _) (Less _) = Overlaps
overlapping (Less _) (More _) = Contains
overlapping (More _) (Less _) = During
overlapping (More _) (More _) = OverlappedBy

||| The one relation that holds of two intervals.
export
relate : Interval -> Interval -> Allen
relate a b = case order a.end b.start of
  Less _ => Precedes
  Same _ => Meets
  More _ => case order b.end a.start of
    Less _ => PrecededBy
    Same _ => MetBy
    More _ => overlapping (order a.start b.start) (order a.end b.end)

||| A set of Allen's relations.
public export
record Mask where
  constructor MkMask
  bits : Bits16

bitOf : Allen -> Fin 16
bitOf Precedes = 0
bitOf Meets = 1
bitOf Overlaps = 2
bitOf FinishedBy = 3
bitOf Contains = 4
bitOf Starts = 5
bitOf Equals = 6
bitOf StartedBy = 7
bitOf During = 8
bitOf Finishes = 9
bitOf OverlappedBy = 10
bitOf MetBy = 11
bitOf PrecededBy = 12

||| The set of these relations.
export
mask : List Allen -> Mask
mask rs = MkMask (foldl (\acc, r => setBit acc (bitOf r)) zeroBits rs)

||| Whether a relation is in the set.
export
holds : Mask -> Allen -> Bool
holds m r = testBit m.bits (bitOf r)

||| The interval two coordinates bound, if it is proper.
spanned : Coord u -> Coord u -> Maybe Interval
spanned s e = case order s.value e.value of
  Less proper => Just (MkInterval s.value e.value proper)
  _ => Nothing

||| A filter for a query over `v` variables: the interval the first pair of
||| variables binds stands to the one the second pair binds in a relation
||| of the mask. A pair that binds no proper interval stands in none.
export
stands : Mask -> (s1, e1, s2, e2 : Fin v) -> Tuple v u -> Bool
stands m s1 e1 s2 e2 env = case spanned (index s1 env) (index e1 env) of
  Just a => case spanned (index s2 env) (index e2 env) of
    Just b => holds m (relate a b)
    Nothing => False
  Nothing => False
