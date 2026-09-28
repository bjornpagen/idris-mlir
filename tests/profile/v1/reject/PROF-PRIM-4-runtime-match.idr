-- expect: PROF-PRIM-4 line 10
module Main

import Prelude

-- A string built from a runtime number is only ever written: matching on
-- it would compare its bytes at runtime. (A match on a string chosen among
-- literals is allowed: it allocates nothing, docs/cutover.md A10.) Since
-- the cutover the error is reported at the definition, `main` (unverified).
main : IO ()
main = do
  c <- getChar
  case prim__cast_IntString (prim__cast_CharInt c) of
    "97" => putStrLn "a"
    _ => putStrLn "other"
