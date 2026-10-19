module Lib

import Prelude

-- The refused program's Lib with Meters a data type of its own, not Int
-- under another name: SortedMap Meters String and SortedMap Int String are
-- then two types to the compiler as they are to Idris, and each map holds
-- one Ord.
export
data Meters = MkMeters Int

export
meters : Int -> Meters
meters x = MkMeters x

export
value : Meters -> Int
value (MkMeters x) = x

intEq : Int -> Int -> Bool
intEq a b = a == b

intLt : Int -> Int -> Bool
intLt a b = a < b

export
[eqM] Eq Meters where
  a == b = intEq (value a) (value b)

export
[ordM] Ord Meters using eqM where
  compare a b = if intLt (value a) (value b) then GT else if intEq (value a) (value b) then EQ else LT
