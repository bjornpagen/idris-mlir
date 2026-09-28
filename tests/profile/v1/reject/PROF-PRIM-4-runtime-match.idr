-- expect: PROF-PRIM-4 line 13
module Main

import Prelude

-- A string built from a runtime number is only ever written: matching on
-- it would compare its bytes at runtime. (A match on a string chosen among
-- literals is allowed: it allocates nothing, PROF-PRIM-4.) The error is
-- reported at the match, the innermost location of the user's code
-- (DIAG-LOC-1).
main : IO ()
main = do
  c <- getChar
  case prim__cast_IntString (prim__cast_CharInt c) of
    "97" => putStrLn "a"
    _ => putStrLn "other"
