-- expect: PROF-PRIM-4 line 12
module Main

import Prelude

-- A string built from a runtime number is only ever written: matching on
-- it would compare its bytes at runtime. (A match on a string chosen among
-- literals is a match on its choice: ELIM-G-20.)
main : IO ()
main = do
  c <- getChar
  case prim__cast_IntString (prim__cast_CharInt c) of
    "97" => putStrLn "a"
    _ => putStrLn "other"
