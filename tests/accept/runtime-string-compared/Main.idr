module Main

-- `digits` recurses on a runtime value, so the string it returns is built
-- at runtime, on the heap, and compared, not written.

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
  putStrLn (case prim__eq_String (digits (prim__cast_CharInt c)) "255" of
              0 => "no"
              _ => "yes")
