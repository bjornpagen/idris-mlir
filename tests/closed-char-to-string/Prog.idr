module Prog

-- A Char's string is the character, written in UTF-8: U+00E9 is `é`, not
-- the escape `\233` that `show` writes, though the argument is a literal.

public export
eAcute : String
eAcute = prim__cast_CharString '\233'
