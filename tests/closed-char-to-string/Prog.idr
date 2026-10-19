module Prog

import Prelude

-- A Char's string is the character, written in UTF-8: U+00E9 is `é`, not
-- the escape `\233` that `show` writes, though the argument is a literal.
-- So is every character at the ends of UTF-8's lengths: U+0000 and U+007F
-- in one byte, U+0080 and U+07FF in two, U+0800 and U+FFFF in three,
-- U+10000 and U+10FFFF in four.

public export
eAcute : String
eAcute = prim__cast_CharString '\233'

public export
ends : List String
ends =
  [ prim__cast_CharString '\0', prim__cast_CharString '\127'
  , prim__cast_CharString '\128', prim__cast_CharString '\2047'
  , prim__cast_CharString '\2048', prim__cast_CharString '\65535'
  , prim__cast_CharString '\65536', prim__cast_CharString '\1114111' ]
