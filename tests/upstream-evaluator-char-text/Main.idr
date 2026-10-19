module Main

-- The elaborator computes a primitive applied to constants with the
-- primitive itself, so a Char's text is the Char, whatever it is: no
-- escape, as `show` would write. Each proof is checked by computing it.
-- The fork carries upstream/20-evaluator-char-text/pull-request.diff; when a
-- re-sync brings upstream's fix, this test goes with the report
-- (upstream/README.md).

import Prelude

newline : prim__cast_CharString '\n' = "\n"
newline = Refl

backslash : prim__cast_CharString '\\' = "\\"
backslash = Refl

quote : prim__cast_CharString '\'' = "'"
quote = Refl

eAcute : prim__cast_CharString '\233' = "\233"
eAcute = Refl

doubleQuote : prim__cast_CharString '"' = "\""
doubleQuote = Refl

nul : prim__cast_CharString '\0' = "\0"
nul = Refl

delete : prim__cast_CharString '\DEL' = "\DEL"
delete = Refl

-- The first scalar value past the BMP, and the last one.
astral : prim__cast_CharString '\x1F600' = "\x1F600"
astral = Refl

lastScalar : prim__cast_CharString '\x10FFFF' = "\x10FFFF"
lastScalar = Refl

main : IO ()
main = putStrLn (prim__cast_CharString 'x')
