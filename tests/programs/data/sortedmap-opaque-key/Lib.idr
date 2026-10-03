module Lib

import Prelude
import Data.SortedMap

-- Meters is Int inside this module and opaque outside it, with its own,
-- descending, ordering.
export
Meters : Type
Meters = Int

export
meters : Int -> Meters
meters x = x

export
value : Meters -> Int
value x = x

intEq : Int -> Int -> Bool
intEq a b = a == b

intLt : Int -> Int -> Bool
intLt a b = a < b

export
[eqM] Eq Meters where
  a == b = intEq a b

export
[ordM] Ord Meters using eqM where
  compare a b = if intLt a b then GT else if intEq a b then EQ else LT

-- Inside Lib the two map types are one: a map built with ordM leaves as a
-- map of Ints, still holding ordM.
export
asInts : SortedMap Meters String -> SortedMap Int String
asInts m = m
