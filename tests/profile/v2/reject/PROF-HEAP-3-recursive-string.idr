-- expect: PROF-HEAP-3 line 10
-- rule: ELIM-G-19
module Main

import Prelude

-- A string function is unfolded where it is called (ELIM-G-19), but its
-- recursive call is specialized, and the string that call returns is built
-- at runtime: it would need the heap.
digits : Int -> String
digits n = case prim__lt_Int n 10 of
  0 => prim__strAppend (digits (prim__div_Int n 10)) (prim__cast_IntString (prim__mod_Int n 10))
  _ => prim__cast_IntString n

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (digits (prim__cast_CharInt c))
