module Prog

import Prelude

-- A literal is its conversion applied to it, and the primitives the
-- conversion applies mean what the runtime computes: "12.7" through a
-- FromString that casts it to an Int is 0 (no literal of an Int), and a
-- Double literal through a FromDouble that writes it is the even one of
-- its two equally near texts.

public export
data N = MkN Int

public export
number : N -> Int
number (MkN i) = i

public export
FromString N where
  fromString s = MkN (prim__cast_StringInt s)

public export
FromDouble String where
  fromDouble d = prim__cast_DoubleString d

public export
viaString : N
viaString = "12.7"

public export
viaDouble : String
viaDouble = 12.886856079101562

-- More literals through the same conversions: an Int literal is read, in
-- any base, modulo 2^64; and a Double's text is its fewest digits, in the
-- layout of either side of 1e-3 and 1e10.
public export
viaStrings : List N
viaStrings = ["12", "-0x10", "9223372036854775808", "1_000", " 1"]

public export
viaDoubles : List String
viaDoubles = [0.1, 1.0e-3, 9.999e-4, 1.0e10, 9999999999.0, 1.0e21]
