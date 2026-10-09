module Main

-- The elaborator computes a primitive applied to constants with the
-- primitive itself, so a Char's text is the Char, whatever it is: no
-- escape, as `show` would write. Each proof is checked by computing it.

import Prelude

newline : prim__cast_CharString '\n' = "\n"
newline = Refl

backslash : prim__cast_CharString '\\' = "\\"
backslash = Refl

quote : prim__cast_CharString '\'' = "'"
quote = Refl

eAcute : prim__cast_CharString '\233' = "\233"
eAcute = Refl

main : IO ()
main = putStrLn (prim__cast_CharString 'x')
