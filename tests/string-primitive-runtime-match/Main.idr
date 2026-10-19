module Main

import Prelude

-- A string built from a runtime number, matched: the match compares its
-- bytes at runtime, and the string is freed after it.
main : IO ()
main = do
  c <- getChar
  case prim__cast_IntString (prim__cast_CharInt c) of
    "97" => putStrLn "a"
    _ => putStrLn "other"
