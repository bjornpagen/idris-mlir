module Lib

import Prelude

-- An abstract type: Int inside this module, opaque outside it, with an
-- ordering of its own (descending), as named implementations.
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
