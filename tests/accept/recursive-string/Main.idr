module Main

-- `digits` recurses on a runtime value, so the string it returns is not
-- known at compile time, but its only use is output, so idr-specialize
-- makes a clone of `digits` that writes at each tail, where output fusion
-- takes the append apart: no string is built at runtime. On empty stdin the
-- Prelude's getChar returns character 255.

import Prelude

partial
digits : Int -> String
digits n = case prim__lt_Int n 10 of
  0 => prim__strAppend (digits (prim__div_Int n 10)) (prim__cast_IntString (prim__mod_Int n 10))
  _ => prim__cast_IntString n

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (digits (prim__cast_CharInt c))
