-- expect: PROF-HEAP-3 line 10
-- rule: ELIM-G-7, OPT-PIPE-5
module Main

import Prelude

-- A string function is inlined where it is called, but not into its own
-- recursive call (OPT-PIPE-5), and the string that call returns is built at
-- runtime, out of output fusion's reach (ELIM-G-7): it would need the heap.
digits : Int -> String
digits n = case prim__lt_Int n 10 of
  0 => prim__strAppend (digits (prim__div_Int n 10)) (prim__cast_IntString (prim__mod_Int n 10))
  _ => prim__cast_IntString n

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (digits (prim__cast_CharInt c))
