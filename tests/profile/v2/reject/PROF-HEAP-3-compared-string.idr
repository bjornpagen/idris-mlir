-- expect: PROF-HEAP-3 line 12
module Main

-- rule: PROF-HEAP-3, ELIM-G-5, ELIM-G-7
-- `digits` recurses on a runtime value, so the string it returns is built
-- at runtime, and its use is a comparison, not output: neither raising
-- (ELIM-G-5) nor output fusion (ELIM-G-7) consumes it, so it would need
-- the heap.

import Prelude

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
