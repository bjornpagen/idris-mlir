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
